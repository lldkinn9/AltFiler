import Foundation
import LocalAuthentication
import Combine

/// フォルダの鍵（パスワード・生体認証保護）管理クラス
public final class FolderLockManager: ObservableObject {
    public static let shared = FolderLockManager()
    
    private let userDefaults = UserDefaults.standard
    private let lockedFolderPathsKey = "AltFiler_LockedFolderPaths"
    private let masterPasswordHashKey = "AltFiler_MasterPasswordHash"
    
    /// セッション内で一時解錠されたフォルダURLセット
    @Published public private(set) var sessionUnlockedURLs: Set<URL> = []
    
    /// ロックされているフォルダパス一覧（相対パス）
    @Published public private(set) var lockedPaths: Set<String> = []
    
    private init() {
        loadLockedPaths()
    }
    
    // MARK: - 永続化データ読み書き
    
    private func loadLockedPaths() {
        let array = userDefaults.stringArray(forKey: lockedFolderPathsKey) ?? []
        let normalized = array.map { path -> String in
            var p = path
            if p.hasPrefix("/") { p.removeFirst() }
            return p
        }
        self.lockedPaths = Set(normalized)
    }
    
    private func saveLockedPaths() {
        userDefaults.set(Array(lockedPaths), forKey: lockedFolderPathsKey)
    }
    
    /// フォルダの相対パスを取得（iOSサンドボックスパス・シンボリックリンクの正規化対応）
    public func relativePath(for url: URL) -> String {
        let rootURL = LocalFileManager.shared.rootDirectoryURL.resolvingSymlinksInPath().standardizedFileURL
        let targetURL = url.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = rootURL.path
        let path = targetURL.path
        
        if path.hasPrefix(rootPath) {
            var rel = String(path.dropFirst(rootPath.count))
            if rel.hasPrefix("/") {
                rel.removeFirst()
            }
            return rel
        }
        return path
    }
    
    // MARK: - ロック状態判定
    
    /// 設定としてロックが有効化されているか
    public func isFolderProtected(url: URL) -> Bool {
        let relPath = relativePath(for: url)
        if relPath.isEmpty { return false }
        let slashPath = "/" + relPath
        let cleanPath = relPath.hasPrefix("/") ? String(relPath.dropFirst()) : relPath
        return lockedPaths.contains(relPath) || lockedPaths.contains(slashPath) || lockedPaths.contains(cleanPath)
    }
    
    /// 指定URLのフォルダが現在ロック状態か確認（セッション解錠中ならfalse）
    public func isFolderLocked(url: URL) -> Bool {
        if isFolderProtected(url: url) {
            let isUnlocked = sessionUnlockedURLs.contains(url) || sessionUnlockedURLs.contains(url.resolvingSymlinksInPath().standardizedFileURL)
            return !isUnlocked
        }
        return false
    }
    
    // MARK: - パスワード管理（認証必須・無条件リセット廃止）
    
    /// マスターパスワードが設定されているか
    public var hasMasterPassword: Bool {
        return userDefaults.string(forKey: masterPasswordHashKey) != nil
    }
    
    /// パスワードを設定
    public func setMasterPassword(_ rawPassword: String) {
        let hash = simpleHash(rawPassword)
        userDefaults.set(hash, forKey: masterPasswordHashKey)
    }
    
    /// パスワードの検証（未設定時は false を返す厳格仕様）
    public func verifyPassword(_ rawPassword: String) -> Bool {
        guard let storedHash = userDefaults.string(forKey: masterPasswordHashKey) else {
            return false
        }
        return storedHash == simpleHash(rawPassword)
    }
    
    private func simpleHash(_ input: String) -> String {
        return String(input.utf8.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1) })
    }
    
    // MARK: - ロック設定操作
    
    /// フォルダのロック保護を有効化
    public func lockFolder(url: URL) {
        let relPath = relativePath(for: url)
        lockedPaths.insert(relPath)
        sessionUnlockedURLs.remove(url)
        saveLockedPaths()
    }
    
    /// フォルダのロック保護を解除（保護自体を削除）
    public func unlockFolderSetting(url: URL) {
        let relPath = relativePath(for: url)
        lockedPaths.remove(relPath)
        sessionUnlockedURLs.remove(url)
        saveLockedPaths()
    }
    
    /// フォルダのセッション解錠
    public func unlockFolderForSession(url: URL) {
        sessionUnlockedURLs.insert(url)
    }
    
    // MARK: - 生体認証 (Face ID / Touch ID)
    
    /// 生体認証（Face ID / Touch ID）を試行
    public func authenticateWithBiometrics(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }
        
        // UI（ContextMenu等）のアニメーションが完了するのを待ってから生体認証を呼び出すことでフリーズを回避
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                DispatchQueue.main.async {
                    completion(success)
                }
            }
        }
    }
}

