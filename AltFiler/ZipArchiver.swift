import Foundation
import Compression

/// iOS標準フレームワーク（Foundation + Compression）のみで動作する純粋Swift製 ZIP 圧縮・解凍エンジン
public enum ZipArchiverError: LocalizedError {
    case invalidArchive
    case unsupportedCompressionMethod(UInt16)
    case decompressionFailed
    case compressionFailed
    case fileWriteFailed
    
    public var errorDescription: String? {
        switch self {
        case .invalidArchive: return "有効なZIPアーカイブではありません。"
        case .unsupportedCompressionMethod(let method): return "未対応の圧縮方式（方式コード: \(method)）が含まれています。"
        case .decompressionFailed: return "ZIPデータの展開に失敗しました。"
        case .compressionFailed: return "ZIPデータの作成に失敗しました。"
        case .fileWriteFailed: return "ファイルの書き出しに失敗しました。"
        }
    }
}

public struct ZipArchiver {
    
    // MARK: - 1. ZIP 圧縮 (複数ファイル・フォルダ対応 / UTF-8 / Deflate & Store)
    
    /// 指定されたURL群（ファイル・フォルダ）を単一の `.zip` ファイルに圧縮する
    public static func createZip(
        from sourceURLs: [URL],
        to destinationZipURL: URL,
        progressHandler: ((Double) -> Void)? = nil
    ) throws {
        let fileManager = FileManager.default
        
        struct EntryItem {
            let fileURL: URL
            let relativePath: String
            let isDirectory: Bool
        }
        
        var entries: [EntryItem] = []
        
        for srcURL in sourceURLs {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: srcURL.path, isDirectory: &isDir) else { continue }
            let baseName = srcURL.lastPathComponent
            
            if isDir.boolValue {
                entries.append(EntryItem(fileURL: srcURL, relativePath: baseName + "/", isDirectory: true))
                if let enumerator = fileManager.enumerator(
                    at: srcURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for case let childURL as URL in enumerator {
                        let subIsDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                        let srcPath = srcURL.resolvingSymlinksInPath().path
                        let childPath = childURL.resolvingSymlinksInPath().path
                        var subRel = childPath.hasPrefix(srcPath) ? String(childPath.dropFirst(srcPath.count)) : childURL.lastPathComponent
                        if subRel.hasPrefix("/") { subRel.removeFirst() }
                        let fullRel = baseName + "/" + subRel + (subIsDir ? "/" : "")
                        entries.append(EntryItem(fileURL: childURL, relativePath: fullRel, isDirectory: subIsDir))
                    }
                }
            } else {
                entries.append(EntryItem(fileURL: srcURL, relativePath: baseName, isDirectory: false))
            }
        }
        
        var archiveData = Data()
        var centralDirectoryData = Data()
        var totalEntriesCount: UInt16 = 0
        let total = max(1, entries.count)
        
        for (idx, entry) in entries.enumerated() {
            guard let nameData = entry.relativePath.data(using: .utf8) else { continue }
            let localHeaderOffset = UInt32(clamping: archiveData.count)
            
            let modDate = (try? fileManager.attributesOfItem(atPath: entry.fileURL.path)[.modificationDate] as? Date) ?? Date()
            let (dosTime, dosDate) = dateToDosTimeAndDate(modDate)
            
            let uncompressedData: Data
            if entry.isDirectory {
                uncompressedData = Data()
            } else {
                uncompressedData = (try? Data(contentsOf: entry.fileURL, options: .mappedIfSafe)) ?? Data()
            }
            
            let crc = crc32(of: uncompressedData)
            let uncompressedSize = UInt32(clamping: uncompressedData.count)
            
            // 既に圧縮済みのメディア拡張子や極小ファイルは Store (0)、それ以外は Deflate (8)
            let ext = entry.fileURL.pathExtension.lowercased()
            let storeExtensions: Set<String> = ["mp4", "mov", "m4v", "jpg", "jpeg", "png", "heic", "mp3", "m4a", "aac", "zip", "gz"]
            let shouldStore = entry.isDirectory || uncompressedData.count < 128 || storeExtensions.contains(ext)
            
            let compressionMethod: UInt16
            let payloadData: Data
            if shouldStore {
                compressionMethod = 0
                payloadData = uncompressedData
            } else if let deflated = deflateCompress(uncompressedData), deflated.count < uncompressedData.count {
                compressionMethod = 8
                payloadData = deflated
            } else {
                compressionMethod = 0
                payloadData = uncompressedData
            }
            
            let compressedSize = UInt32(clamping: payloadData.count)
            let generalPurposeFlag: UInt16 = 0x0800 // Bit 11: UTF-8 ファイル名フラグ
            
            // Local File Header
            archiveData.appendUInt32LE(0x04034b50)
            archiveData.appendUInt16LE(20) // Version needed to extract (2.0)
            archiveData.appendUInt16LE(generalPurposeFlag)
            archiveData.appendUInt16LE(compressionMethod)
            archiveData.appendUInt16LE(dosTime)
            archiveData.appendUInt16LE(dosDate)
            archiveData.appendUInt32LE(crc)
            archiveData.appendUInt32LE(compressedSize)
            archiveData.appendUInt32LE(uncompressedSize)
            archiveData.appendUInt16LE(UInt16(clamping: nameData.count))
            archiveData.appendUInt16LE(0) // Extra field length
            archiveData.append(nameData)
            archiveData.append(payloadData)
            
            // Central Directory File Header
            centralDirectoryData.appendUInt32LE(0x02014b50)
            centralDirectoryData.appendUInt16LE(20) // Version made by
            centralDirectoryData.appendUInt16LE(20) // Version needed
            centralDirectoryData.appendUInt16LE(generalPurposeFlag)
            centralDirectoryData.appendUInt16LE(compressionMethod)
            centralDirectoryData.appendUInt16LE(dosTime)
            centralDirectoryData.appendUInt16LE(dosDate)
            centralDirectoryData.appendUInt32LE(crc)
            centralDirectoryData.appendUInt32LE(compressedSize)
            centralDirectoryData.appendUInt32LE(uncompressedSize)
            centralDirectoryData.appendUInt16LE(UInt16(clamping: nameData.count))
            centralDirectoryData.appendUInt16LE(0) // Extra field length
            centralDirectoryData.appendUInt16LE(0) // File comment length
            centralDirectoryData.appendUInt16LE(0) // Disk number start
            centralDirectoryData.appendUInt16LE(0) // Internal file attributes
            centralDirectoryData.appendUInt32LE(entry.isDirectory ? 0x10 : 0x00) // External attributes
            centralDirectoryData.appendUInt32LE(localHeaderOffset)
            centralDirectoryData.append(nameData)
            
            totalEntriesCount &+= 1
            progressHandler?(Double(idx + 1) / Double(total))
        }
        
        let centralDirOffset = UInt32(clamping: archiveData.count)
        let centralDirSize = UInt32(clamping: centralDirectoryData.count)
        archiveData.append(centralDirectoryData)
        
        // End of Central Directory Record (EOCD)
        archiveData.appendUInt32LE(0x06054b50)
        archiveData.appendUInt16LE(0) // Number of this disk
        archiveData.appendUInt16LE(0) // Disk where central directory starts
        archiveData.appendUInt16LE(totalEntriesCount)
        archiveData.appendUInt16LE(totalEntriesCount)
        archiveData.appendUInt32LE(centralDirSize)
        archiveData.appendUInt32LE(centralDirOffset)
        archiveData.appendUInt16LE(0) // Comment length
        
        do {
            try archiveData.write(to: destinationZipURL, options: .atomic)
        } catch {
            throw ZipArchiverError.fileWriteFailed
        }
    }
    
    // MARK: - 2. ZIP 解凍 (Central Directory ベース / Zip-Slip 防御 / UTF-8 & Shift-JIS フォールバック)
    
    /// `.zip` ファイルを指定ディレクトリへ安全に解凍する
    public static func extractZip(
        at zipFileURL: URL,
        to destinationDirectoryURL: URL,
        progressHandler: ((Double) -> Void)? = nil
    ) throws -> URL {
        let fileManager = FileManager.default
        guard let data = try? Data(contentsOf: zipFileURL, options: .mappedIfSafe),
              data.count >= 22 else {
            throw ZipArchiverError.invalidArchive
        }
        
        // EOCD (0x06054b50) を末尾から探索
        let maxCommentLength = min(data.count - 22, 65535)
        var eocdOffset: Int? = nil
        for i in 0...maxCommentLength {
            let pos = data.count - 22 - i
            if data.readUInt32LE(at: pos) == 0x06054b50 {
                eocdOffset = pos
                break
            }
        }
        
        guard let eocd = eocdOffset else {
            throw ZipArchiverError.invalidArchive
        }
        
        let totalEntries = Int(data.readUInt16LE(at: eocd + 10))
        let centralDirOffset = Int(data.readUInt32LE(at: eocd + 16))
        
        guard centralDirOffset >= 0, centralDirOffset <= data.count else {
            throw ZipArchiverError.invalidArchive
        }
        
        // 解凍先フォルダの決定（同名フォルダがなければ作成）
        let baseFolderName = zipFileURL.deletingPathExtension().lastPathComponent
        var outputRootURL = destinationDirectoryURL.appendingPathComponent(baseFolderName)
        var counter = 1
        while fileManager.fileExists(atPath: outputRootURL.path) {
            outputRootURL = destinationDirectoryURL.appendingPathComponent("\(baseFolderName) (\(counter))")
            counter += 1
        }
        try fileManager.createDirectory(at: outputRootURL, withIntermediateDirectories: true)
        let standardizedRootPath = outputRootURL.resolvingSymlinksInPath().standardizedFileURL.path
        
        var cursor = centralDirOffset
        let safeTotal = max(1, totalEntries)
        
        for entryIndex in 0..<totalEntries {
            guard cursor + 46 <= data.count,
                  data.readUInt32LE(at: cursor) == 0x02014b50 else {
                break
            }
            
            let compressionMethod = data.readUInt16LE(at: cursor + 10)
            let compressedSize = Int(data.readUInt32LE(at: cursor + 20))
            let uncompressedSize = Int(data.readUInt32LE(at: cursor + 24))
            let fileNameLength = Int(data.readUInt16LE(at: cursor + 28))
            let extraLength = Int(data.readUInt16LE(at: cursor + 30))
            let commentLength = Int(data.readUInt16LE(at: cursor + 32))
            let externalAttrs = data.readUInt32LE(at: cursor + 38)
            let localHeaderOffset = Int(data.readUInt32LE(at: cursor + 42))
            
            let nameStart = cursor + 46
            guard nameStart + fileNameLength <= data.count else { break }
            let nameData = data.subdata(in: nameStart..<(nameStart + fileNameLength))
            let rawName = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .shiftJIS)
                ?? "item_\(entryIndex)"
            
            cursor = nameStart + fileNameLength + extraLength + commentLength
            
            // macOS の __MACOSX メタデータや不可視ファイルはスキップ
            if rawName.hasPrefix("__MACOSX/") || rawName.contains("/._") || rawName.hasPrefix("._") {
                progressHandler?(Double(entryIndex + 1) / Double(safeTotal))
                continue
            }
            
            let isDirectory = rawName.hasSuffix("/") || ((externalAttrs & 0x10) != 0 && uncompressedSize == 0 && compressedSize == 0)
            let cleanedRelativePath = rawName
                .replacingOccurrences(of: "\\", with: "/")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            
            if cleanedRelativePath.isEmpty {
                progressHandler?(Double(entryIndex + 1) / Double(safeTotal))
                continue
            }
            
            let targetURL = outputRootURL.appendingPathComponent(cleanedRelativePath).standardizedFileURL
            let targetStandardizedPath = targetURL.resolvingSymlinksInPath().standardizedFileURL.path
            
            // Zip-Slip (パストラバーサル脆弱性) 防御チェック
            guard targetStandardizedPath.hasPrefix(standardizedRootPath) else {
                continue
            }
            
            if isDirectory {
                try? fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
            } else {
                let parentDir = targetURL.deletingLastPathComponent()
                try? fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
                
                guard localHeaderOffset + 30 <= data.count,
                      data.readUInt32LE(at: localHeaderOffset) == 0x04034b50 else {
                    continue
                }
                let localNameLen = Int(data.readUInt16LE(at: localHeaderOffset + 26))
                let localExtraLen = Int(data.readUInt16LE(at: localHeaderOffset + 28))
                let dataStart = localHeaderOffset + 30 + localNameLen + localExtraLen
                guard dataStart + compressedSize <= data.count else { continue }
                
                let compressedSlice = data.subdata(in: dataStart..<(dataStart + compressedSize))
                let outputData: Data
                
                if compressionMethod == 0 {
                    outputData = compressedSlice
                } else if compressionMethod == 8 {
                    if uncompressedSize == 0 {
                        outputData = Data()
                    } else if let decompressed = deflateDecompress(compressedSlice, expectedSize: uncompressedSize) {
                        outputData = decompressed
                    } else {
                        throw ZipArchiverError.decompressionFailed
                    }
                } else {
                    throw ZipArchiverError.unsupportedCompressionMethod(compressionMethod)
                }
                
                try outputData.write(to: targetURL, options: .atomic)
            }
            
            progressHandler?(Double(entryIndex + 1) / Double(safeTotal))
        }
        
        return outputRootURL
    }
    
    // MARK: - Raw Deflate (COMPRESSION_ZLIB) ヘルパー
    
    private static func deflateCompress(_ input: Data) -> Data? {
        if input.isEmpty { return Data() }
        let destCapacity = input.count + max(512, input.count / 10)
        let destBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destCapacity)
        defer { destBuffer.deallocate() }
        
        let compressedByteCount = input.withUnsafeBytes { srcRaw -> Int in
            guard let srcPtr = srcRaw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(
                destBuffer,
                destCapacity,
                srcPtr,
                input.count,
                nil,
                COMPRESSION_ZLIB
            )
        }
        
        guard compressedByteCount > 0 else { return nil }
        return Data(bytes: destBuffer, count: compressedByteCount)
    }
    
    private static func deflateDecompress(_ input: Data, expectedSize: Int) -> Data? {
        if expectedSize == 0 { return Data() }
        let destCapacity = max(expectedSize + 1024, input.count * 4, 4096)
        let destBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destCapacity)
        defer { destBuffer.deallocate() }
        
        let decodedByteCount = input.withUnsafeBytes { srcRaw -> Int in
            guard let srcPtr = srcRaw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(
                destBuffer,
                destCapacity,
                srcPtr,
                input.count,
                nil,
                COMPRESSION_ZLIB
            )
        }
        
        guard decodedByteCount > 0 else { return nil }
        return Data(bytes: destBuffer, count: decodedByteCount)
    }
    
    // MARK: - CRC-32 & MS-DOS 日時変換
    
    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()
    
    private static func crc32(of data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ crcTable[idx]
        }
        return crc ^ 0xFFFFFFFF
    }
    
    private static func dateToDosTimeAndDate(_ date: Date) -> (UInt16, UInt16) {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, min(2107, comps.year ?? 2026))
        let month = max(1, min(12, comps.month ?? 1))
        let day = max(1, min(31, comps.day ?? 1))
        let hour = max(0, min(23, comps.hour ?? 0))
        let minute = max(0, min(59, comps.minute ?? 0))
        let second = max(0, min(59, comps.second ?? 0))
        
        let dosTime = UInt16((hour << 11) | (minute << 5) | (second / 2))
        let dosDate = UInt16(((year - 1980) << 9) | (month << 5) | day)
        return (dosTime, dosDate)
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
    
    mutating func appendUInt32LE(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
    
    func readUInt16LE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        let b0 = UInt16(self[offset])
        let b1 = UInt16(self[offset + 1]) << 8
        return b0 | b1
    }
    
    func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        let b0 = UInt32(self[offset])
        let b1 = UInt32(self[offset + 1]) << 8
        let b2 = UInt32(self[offset + 2]) << 16
        let b3 = UInt32(self[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }
}
