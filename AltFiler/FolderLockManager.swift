import Foundation
import LocalAuthentication
import Combine
import CryptoKit
import Security

/// フォルダの鍵およびアプリ全体のセキュリティ（Keychain + SHA-256・生体認証・起動ロック・プライバシーシールド）管理クラス
public final class FolderLockManager: ObservableObject {
    public static let shared = FolderLockManager()
    
    private let userDefaults = UserDefaults.standard
    private let lockedFolderPathsKey = "AltFiler_LockedFolderPaths"
    private let legacyMasterPasswordHashKey = "AltFiler_MasterPasswordHash"
    
    // 設定キー
    private let appLockEnabledKey = "AltFiler_AppLockEnabled"
    private let biometricsEnabledKey = "AltFiler_BiometricsEnabled"
    private let privacyShieldEnabledKey = "AltFiler_PrivacyShieldEnabled"
    
    // Keychain 識別子
    private let keychainService = "com.altfiler.security.keychain"
    private let keychainAccount = "AltFiler_MasterPassword_SHA256"
    
    /// セッション内で一時解錠されたフォルダURLセット
    @Published public private(set) var sessionUnlockedURLs: Set<URL> = []
    
    /// ロックされているフォルダパス一覧（相対パス）
    @Published public private(set) var lockedPaths: Set<String> = []
    
    /// マスターパスワード設定状態（UI更新トリガー用）
    @Published public private(set) var isMasterPasswordConfigured: Bool = false
    
    /// アプリ起動ロックが有効か
    @Published public var isAppLockEnabled: Bool {
        didSet {
            userDefaults.set(isAppLockEnabled, forKey: appLockEnabledKey)
            if isAppLockEnabled {
                isAppUnlockedForSession = true
            }
        }
    }
    
    /// Face ID / Touch ID 生体認証を使用するか（デフォルト: ON）
    @Published public var isBiometricsEnabled: Bool {
        didSet {
            userDefaults.set(isBiometricsEnabled, forKey: biometricsEnabledKey)
        }
    }
    
    /// バックグラウンド移行時のブラー保護シールドを有効にするか（デフォルト: ON）
    @Published public var isPrivacyShieldEnabled: Bool {
        didSet {
            userDefaults.set(isPrivacyShieldEnabled, forKey: privacyShieldEnabledKey)
        }
    }
    
    /// アプリ起動ロックが現在解錠されているか
    @Published public var isAppUnlockedForSession: Bool = true
    
    private init() {
        let savedAppLock = userDefaults.bool(forKey: appLockEnabledKey)
        let savedBiometrics = userDefaults.object(forKey: biometricsEnabledKey) as? Bool ?? true
        let savedPrivacyShield = userDefaults.object(forKey: privacyShieldEnabledKey) as? Bool ?? true
        
        self.isAppLockEnabled = savedAppLock
        self.isBiometricsEnabled = savedBiometrics
        self.isPrivacyShieldEnabled = savedPrivacyShield
        
        // 旧UserDefaultsハッシュがあれば削除してクリーンアップ
        if userDefaults.string(forKey: legacyMasterPasswordHashKey) != nil {
            userDefaults.removeObject(forKey: legacyMasterPasswordHashKey)
        }
        
        loadLockedPaths()
        let hasPass = readHashFromKeychain() != nil
        self.isMasterPasswordConfigured = hasPass
        
        // アプリ起動ロックがONかつパスワード設定済みの場合は起動時ロック状態から開始
        if savedAppLock && hasPass {
            self.isAppUnlockedForSession = false
        } else {
            self.isAppUnlockedForSession = true
        }
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
    
    // MARK: - Keychain + CryptoKit (SHA-256) パスワード管理
    
    /// マスターパスワードが設定されているか
    public var hasMasterPassword: Bool {
        return readHashFromKeychain() != nil
    }
    
    /// パスワードを SHA-256 ハッシュ化して Keychain に保存
    public func setMasterPassword(_ rawPassword: String) {
        let trimmed = rawPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let hash = sha256Hex(trimmed)
        saveHashToKeychain(hash)
        isMasterPasswordConfigured = true
    }
    
    /// パスワードの検証（未設定時は false を返す厳格仕様）
    public func verifyPassword(_ rawPassword: String) -> Bool {
        guard let storedHash = readHashFromKeychain() else {
            return false
        }
        let trimmed = rawPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        return storedHash == sha256Hex(trimmed)
    }
    
    /// 現在のパスワードまたは生体認証を確認した上でマスターパスワードを変更
    public func changeMasterPassword(currentPassword: String?, authenticatedByBiometrics: Bool = false, newPassword: String) -> Bool {
        let trimmedNew = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNew.isEmpty else { return false }
        
        if hasMasterPassword {
            let isVerified = authenticatedByBiometrics || verifyPassword(currentPassword ?? "")
            guard isVerified else { return false }
        }
        
        setMasterPassword(trimmedNew)
        return true
    }
    
    /// CryptoKit SHA-256 ハッシュ生成
    private func sha256Hex(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Keychain へのハッシュ保存
    private func saveHashToKeychain(_ hash: String) {
        guard let data = hash.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }
    
    /// Keychain からのハッシュ読み出し
    private func readHashFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let hash = String(data: data, encoding: .utf8),
              !hash.isEmpty else {
            return nil
        }
        return hash
    }
    
    // MARK: - アプリ起動ロック＆セッション制御
    
    /// バックグラウンド移行時にセッションロックを適用
    public func handleAppDidEnterBackground() {
        if isAppLockEnabled && hasMasterPassword {
            isAppUnlockedForSession = false
        }
    }
    
    /// アプリ起動ロックを解錠
    public func unlockAppForSession() {
        isAppUnlockedForSession = true
    }
    
    // MARK: - フォルダロック設定操作
    
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
    
    /// 端末が生体認証に対応しているか＆種類名を取得
    public var biometricTypeName: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "生体認証"
        }
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        @unknown default: return "生体認証"
        }
    }
    
    /// 生体認証（Face ID / Touch ID）を試行
    public func authenticateWithBiometrics(reason: String, completion: @escaping (Bool) -> Void) {
        guard isBiometricsEnabled else {
            DispatchQueue.main.async {
                completion(false)
            }
            return
        }
        
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
