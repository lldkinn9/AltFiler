import Foundation
import Combine

/// ファイル・フォルダ情報を表すデータ構造
public struct FileItem: Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let url: URL
    public let isDirectory: Bool
    public let size: Int64
    public let creationDate: Date
    public let modificationDate: Date
    
    public init(url: URL, isDirectory: Bool, size: Int64, creationDate: Date, modificationDate: Date) {
        self.id = UUID()
        self.name = url.lastPathComponent
        self.url = url
        self.isDirectory = isDirectory
        self.size = size
        self.creationDate = creationDate
        self.modificationDate = modificationDate
    }
}

/// 完全独立ローカルファイルシステム管理クラス
public final class LocalFileManager: ObservableObject {
    public static let shared = LocalFileManager()
    
    /// アプリ独立ストレージのルートディレクトリ (`Application Support/AltFilerStorage`)
    public let rootDirectoryURL: URL
    
    /// 初期フォルダの名称リスト（「ダウンロード」のみ）
    public let defaultFolderNames = ["ダウンロード"]
    
    @Published public private(set) var rootItems: [FileItem] = []
    @Published public private(set) var appStorageBytes: Int64 = 0
    @Published public private(set) var freeDiskSpaceBytes: Int64 = 0
    @Published public private(set) var totalFileCount: Int = 0
    @Published public private(set) var totalFolderCount: Int = 0
    
    // 進捗ステータス管理
    @Published public var isOperating: Bool = false
    @Published public var operationTitle: String = ""
    @Published public var operationProgress: Double = 0.0
    
    private init() {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support ディレクトリの取得に失敗しました。")
        }
        
        let altFilerURL = appSupportURL.appendingPathComponent("AltFilerStorage", isDirectory: true)
        let legacyURL = appSupportURL.appendingPathComponent("EntropyStorage", isDirectory: true)
        
        // 旧ストレージディレクトリが存在し、新ディレクトリが未作成の場合は自動移行
        if fileManager.fileExists(atPath: legacyURL.path) && !fileManager.fileExists(atPath: altFilerURL.path) {
            try? fileManager.moveItem(at: legacyURL, to: altFilerURL)
        }
        
        // アプリ固有の独立ストレージパスを設定
        self.rootDirectoryURL = altFilerURL.resolvingSymlinksInPath()
        
        // ディレクトリ初期化
        setupStorageDirectory()
        ensureDefaultFoldersExist()
        refreshStorageInfo()
    }
    
    // MARK: - ストレージ初期化
    
    private func setupStorageDirectory() {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: rootDirectoryURL.path) {
            do {
                try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("[LocalFileManager] ストレージディレクトリ作成エラー: \(error)")
            }
        }
    }
    
    /// 初期状態の必須フォルダ（「ダウンロード」のみ）が存在するか確認し、なければ作成する
    public func ensureDefaultFoldersExist() {
        let fileManager = FileManager.default
        for folderName in defaultFolderNames {
            let folderURL = rootDirectoryURL.appendingPathComponent(folderName, isDirectory: true)
            if !fileManager.fileExists(atPath: folderURL.path) {
                do {
                    try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    print("[LocalFileManager] 初期フォルダ作成エラー (\(folderName)): \(error)")
                }
            }
        }
        
        // 旧仕様の空フォルダ（画像・動画・音声）が残っている場合は初回のみ自動クリーンアップ
        let cleanupKey = "AltFiler_CleanedLegacyDefaultFolders_v1"
        if !UserDefaults.standard.bool(forKey: cleanupKey) {
            for legacyName in ["画像", "動画", "音声"] {
                let legacyFolderURL = rootDirectoryURL.appendingPathComponent(legacyName, isDirectory: true)
                if let contents = try? fileManager.contentsOfDirectory(atPath: legacyFolderURL.path), contents.isEmpty {
                    try? fileManager.removeItem(at: legacyFolderURL)
                }
            }
            UserDefaults.standard.set(true, forKey: cleanupKey)
        }
    }
    
    // MARK: - ファイル・フォルダ操作
    
    /// 重複のないユニークな宛先URLを生成（同名ファイルが存在する場合に (1), (2) を付与）
    private func generateUniqueURL(for destinationURL: URL) -> URL {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }
        
        let dir = destinationURL.deletingLastPathComponent()
        let ext = destinationURL.pathExtension
        let nameWithoutExt = destinationURL.deletingPathExtension().lastPathComponent
        
        var counter = 1
        while true {
            let newName = ext.isEmpty ? "\(nameWithoutExt) (\(counter))" : "\(nameWithoutExt) (\(counter)).\(ext)"
            let candidateURL = dir.appendingPathComponent(newName)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            counter += 1
        }
    }
    
    /// 外部アプリ・共有シート・ドキュメントピッカーから送られてきた複数ファイルの一括取り込み
    @discardableResult
    public func importExternalFiles(from sourceURLs: [URL], destinationDirURL: URL? = nil) -> Int {
        let fileManager = FileManager.default
        let downloadFolderURL = destinationDirURL ?? rootDirectoryURL.appendingPathComponent("ダウンロード", isDirectory: true)
        
        if !fileManager.fileExists(atPath: downloadFolderURL.path) {
            try? fileManager.createDirectory(at: downloadFolderURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        var successCount = 0
        
        for sourceURL in sourceURLs {
            // Security-Scoped URL のアクセス権取得
            let isAccessing = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }
            
            let fileName = sourceURL.lastPathComponent
            let initialDestination = downloadFolderURL.appendingPathComponent(fileName)
            let finalDestination = generateUniqueURL(for: initialDestination)
            
            do {
                try fileManager.copyItem(at: sourceURL, to: finalDestination)
                // 一時領域 (/tmp/ や /Inbox/) からの受け渡しであれば元ファイルをクリーンアップ
                if sourceURL.path.contains("/tmp/") || sourceURL.path.contains("/Inbox/") {
                    try? fileManager.removeItem(at: sourceURL)
                }
                print("[LocalFileManager] インポート完了: \(finalDestination.lastPathComponent)")
                successCount += 1
            } catch {
                print("[LocalFileManager] 外部ファイルインポート失敗 (\(fileName)): \(error)")
            }
        }
        
        refreshStorageInfo()
        return successCount
    }
    
    /// 単一外部ファイルのインポート
    public func importExternalFile(from sourceURL: URL) {
        importExternalFiles(from: [sourceURL])
    }
    
    /// 指定ディレクトリ内のアイテム一覧を取得
    public func listItems(at directoryURL: URL? = nil) -> [FileItem] {
        let targetURL = directoryURL ?? rootDirectoryURL
        let fileManager = FileManager.default
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: targetURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            return contents.compactMap { url in
                guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey]) else {
                    return nil
                }
                
                let isDirectory = resourceValues.isDirectory ?? false
                let size = Int64(resourceValues.fileSize ?? 0)
                let creationDate = resourceValues.creationDate ?? Date()
                let modificationDate = resourceValues.contentModificationDate ?? Date()
                
                return FileItem(
                    url: url,
                    isDirectory: isDirectory,
                    size: isDirectory ? 0 : size,
                    creationDate: creationDate,
                    modificationDate: modificationDate
                )
            }
        } catch {
            print("[LocalFileManager] アイテム一覧取得エラー: \(error)")
            return []
        }
    }
    
    /// 新規フォルダを作成
    public func createDirectory(named name: String, parentURL: URL? = nil) throws {
        let parent = parentURL ?? rootDirectoryURL
        let newFolderURL = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: newFolderURL, withIntermediateDirectories: true, attributes: nil)
        refreshStorageInfo()
    }
    
    /// 指定されたURLがシステム保護対象の「ダウンロード」フォルダ（ルート直下）かどうか判定
    public func isProtectedDownloadFolder(_ url: URL) -> Bool {
        let downloadURL = rootDirectoryURL.appendingPathComponent("ダウンロード", isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let targetURL = url.resolvingSymlinksInPath().standardizedFileURL
        return targetURL.path == downloadURL.path
    }
    
    /// 単一アイテムの物理完全削除（「ダウンロード」フォルダは削除不可）
    public func deleteItem(at url: URL) throws {
        guard !isProtectedDownloadFolder(url) else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        refreshStorageInfo()
    }
    
    /// 複数アイテムの物理完全削除（「ダウンロード」フォルダは削除不可）
    public func deleteItems(urls: [URL]) {
        let fileManager = FileManager.default
        for url in urls {
            guard !isProtectedDownloadFolder(url) else { continue }
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
        }
        refreshStorageInfo()
    }
    
    /// アイテムの名前変更（「ダウンロード」フォルダは名称変更不可）
    public func renameItem(at url: URL, to newName: String) throws {
        guard !isProtectedDownloadFolder(url) else { return }
        let destinationURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        try FileManager.default.moveItem(at: url, to: destinationURL)
        refreshStorageInfo()
    }
    
    /// 複数アイテムの移動（「ダウンロード」フォルダ自体は移動不可）
    public func moveItems(urls: [URL], to destinationDirURL: URL, completion: (() -> Void)? = nil) {
        let movableURLs = urls.filter { !isProtectedDownloadFolder($0) }
        guard !movableURLs.isEmpty else {
            completion?()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.async {
                self.isOperating = true
                self.operationTitle = "ファイルを移動中..."
                self.operationProgress = 0.0
            }
            
            let fileManager = FileManager.default
            let total = Double(movableURLs.count)
            
            for (index, sourceURL) in movableURLs.enumerated() {
                let destinationURL = destinationDirURL.appendingPathComponent(sourceURL.lastPathComponent)
                if sourceURL != destinationURL {
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        try? fileManager.removeItem(at: destinationURL)
                    }
                    try? fileManager.moveItem(at: sourceURL, to: destinationURL)
                }
                let progress = Double(index + 1) / total
                DispatchQueue.main.async {
                    self.operationProgress = progress
                }
            }
            
            DispatchQueue.main.async {
                self.refreshStorageInfo()
                self.isOperating = false
                completion?()
            }
        }
    }
    
    /// 複数アイテムのコピー
    public func copyItems(urls: [URL], to destinationDirURL: URL, completion: (() -> Void)? = nil) {
        guard !urls.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.async {
                self.isOperating = true
                self.operationTitle = "ファイルをコピー中..."
                self.operationProgress = 0.0
            }
            
            let fileManager = FileManager.default
            let total = Double(urls.count)
            
            for (index, sourceURL) in urls.enumerated() {
                var destinationURL = destinationDirURL.appendingPathComponent(sourceURL.lastPathComponent)
                if fileManager.fileExists(atPath: destinationURL.path) {
                    let nameWithoutExt = sourceURL.deletingPathExtension().lastPathComponent
                    let ext = sourceURL.pathExtension
                    let newName = ext.isEmpty ? "\(nameWithoutExt)_copy" : "\(nameWithoutExt)_copy.\(ext)"
                    destinationURL = destinationDirURL.appendingPathComponent(newName)
                }
                try? fileManager.copyItem(at: sourceURL, to: destinationURL)
                
                let progress = Double(index + 1) / total
                DispatchQueue.main.async {
                    self.operationProgress = progress
                }
            }
            
            DispatchQueue.main.async {
                self.refreshStorageInfo()
                self.isOperating = false
                completion?()
            }
        }
    }
    
    // MARK: - ZIP 圧縮・解凍操作
    
    /// 選択されたファイル・フォルダ群を `.zip` アーカイブに圧縮
    public func compressItems(urls: [URL], in directoryURL: URL, completion: ((Result<URL, Error>) -> Void)? = nil) {
        guard !urls.isEmpty else { return }
        
        let baseName: String
        if urls.count == 1, let first = urls.first {
            baseName = first.deletingPathExtension().lastPathComponent
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            baseName = "Archive_\(formatter.string(from: Date()))"
        }
        
        let initialZipURL = directoryURL.appendingPathComponent("\(baseName).zip")
        let finalZipURL = generateUniqueURL(for: initialZipURL)
        
        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.async {
                self.isOperating = true
                self.operationTitle = "ZIP圧縮中..."
                self.operationProgress = 0.0
            }
            
            do {
                try ZipArchiver.createZip(from: urls, to: finalZipURL) { progress in
                    DispatchQueue.main.async {
                        self.operationProgress = progress
                    }
                }
                DispatchQueue.main.async {
                    self.refreshStorageInfo()
                    self.isOperating = false
                    completion?(.success(finalZipURL))
                }
            } catch {
                DispatchQueue.main.async {
                    self.isOperating = false
                    completion?(.failure(error))
                }
            }
        }
    }
    
    /// `.zip` ファイルを指定ディレクトリ内に解凍
    public func extractZipItem(at zipURL: URL, in directoryURL: URL, completion: ((Result<URL, Error>) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            DispatchQueue.main.async {
                self.isOperating = true
                self.operationTitle = "ZIP解凍中..."
                self.operationProgress = 0.0
            }
            
            do {
                let extractedFolderURL = try ZipArchiver.extractZip(at: zipURL, to: directoryURL) { progress in
                    DispatchQueue.main.async {
                        self.operationProgress = progress
                    }
                }
                DispatchQueue.main.async {
                    self.refreshStorageInfo()
                    self.isOperating = false
                    completion?(.success(extractedFolderURL))
                }
            } catch {
                DispatchQueue.main.async {
                    self.isOperating = false
                    completion?(.failure(error))
                }
            }
        }
    }
    
    // MARK: - キャッシュ自動パージ・クリーンアップ
    
    public func purgeTemporaryDirectory() {
        let tempDir = FileManager.default.temporaryDirectory
        let fileManager = FileManager.default
        do {
            let tempFiles = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil, options: [])
            for fileURL in tempFiles {
                try? fileManager.removeItem(at: fileURL)
            }
        } catch {
            print("[LocalFileManager] 一時ファイルパージ失敗: \(error)")
        }
    }
    
    // MARK: - 容量計測
    
    public func refreshStorageInfo() {
        let stats = calculateDirectoryStats(at: rootDirectoryURL)
        self.appStorageBytes = stats.totalSize
        self.totalFileCount = stats.fileCount
        self.totalFolderCount = stats.folderCount
        self.freeDiskSpaceBytes = calculateFreeDiskSpace()
        self.rootItems = listItems(at: rootDirectoryURL)
    }
    
    private func calculateDirectoryStats(at url: URL) -> (totalSize: Int64, fileCount: Int, folderCount: Int) {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0, 0)
        }
        
        var totalSize: Int64 = 0
        var files = 0
        var folders = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]) {
                if resourceValues.isDirectory == true {
                    folders += 1
                } else {
                    files += 1
                    if let size = resourceValues.fileSize {
                        totalSize += Int64(size)
                    }
                }
            }
        }
        return (totalSize, files, folders)
    }
    
    private func calculateFreeDiskSpace() -> Int64 {
        do {
            let values = try rootDirectoryURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage {
                return capacity
            }
        } catch {
            print("[LocalFileManager] 空き容量計測エラー: \(error)")
        }
        
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: rootDirectoryURL.path)
            if let freeSize = attributes[.systemFreeSize] as? NSNumber {
                return freeSize.int64Value
            }
        } catch {
            print("[LocalFileManager] フォールバック空き容量計測エラー: \(error)")
        }
        
        return 0
    }
}

