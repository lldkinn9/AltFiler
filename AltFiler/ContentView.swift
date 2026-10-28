import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
import CoreTransferable
import PDFKit
import AVFoundation
import AVKit
import MediaPlayer
import Combine

// MARK: - PhotosUI Media Transferable (大容量動画・写真のメモリ肥大化ゼロファイル転送)
struct MovieTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let tempDir = FileManager.default.temporaryDirectory
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let originalName = received.file.lastPathComponent
            let safeName = originalName.isEmpty ? "movie_\(UUID().uuidString).\(ext)" : originalName
            let destination = tempDir.appendingPathComponent("\(UUID().uuidString)_\(safeName)")
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: received.file, to: destination)
            return MovieTransferable(url: destination)
        }
    }
}

struct ImageTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .image) { img in
            SentTransferredFile(img.url)
        } importing: { received in
            let tempDir = FileManager.default.temporaryDirectory
            let ext = received.file.pathExtension.isEmpty ? "jpg" : received.file.pathExtension
            let originalName = received.file.lastPathComponent
            let safeName = originalName.isEmpty ? "image_\(UUID().uuidString).\(ext)" : originalName
            let destination = tempDir.appendingPathComponent("\(UUID().uuidString)_\(safeName)")
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: received.file, to: destination)
            return ImageTransferable(url: destination)
        }
    }
}

// MARK: - AltFiler Modern Dark Design System
struct CosmicTheme {
    static let spaceBlack = Color(red: 0.03, green: 0.03, blue: 0.07)
    static let deepSpaceCard = Color(red: 0.08, green: 0.09, blue: 0.15).opacity(0.85)
    static let nebulaCyan = Color(red: 0.2, green: 0.85, blue: 1.0)
    static let nebulaPurple = Color(red: 0.65, green: 0.35, blue: 0.95)
    static let singularityRed = Color(red: 1.0, green: 0.25, blue: 0.35)
    static let starlightWhite = Color.white.opacity(0.9)
    static let cosmicTextSub = Color.white.opacity(0.6)
}

// MARK: - Main View (AltFiler 1.0)
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var fileManager = LocalFileManager.shared
    @StateObject private var lockManager = FolderLockManager.shared
    @StateObject private var playbackManager = PlaybackManager.shared
    @StateObject private var proManager = ProUpgradeManager.shared
    
    private let appVersion = "1.0"
    private let onboardingSeenKey = "AltFiler_HasSeenOnboarding"
    @AppStorage("AltFiler_FirstFolderGuideCompleted") private var isFirstFolderGuideCompleted: Bool = false
    
    @State private var currentDirectoryURL: URL? = nil
    @State private var searchQuery: String = ""
    @State private var isGridView: Bool = true
    @State private var sortOption: SortOption = .name
    @State private var isAscending: Bool = true
    
    // 設定・オンボーディング・プライバシーシールド状態
    @State private var showSettingsSheet: Bool = false
    @State private var showOnboardingSheet: Bool = false
    @State private var isPrivacyShieldVisible: Bool = false
    
    // 選択モード状態
    @State private var isSelectionMode: Bool = false
    @State private var selectedURLs: Set<URL> = []
    
    // お気に入り状態
    @State private var favoritePaths: Set<String> = []
    @State private var filterOnlyFavorites: Bool = false
    
    // シート・ダイアログ状態
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var renameTargetItem: FileItem? = nil
    @State private var renameNewName = ""
    @State private var selectedFileForDetail: FileItem? = nil
    @State private var importedNotificationText: String? = nil
    
    // フォルダ鍵（ロック/解除/パスワード認証）状態
    @State private var passwordTargetFolder: FileItem? = nil
    @State private var passwordInputText = ""
    @State private var passwordAlertMode: PasswordAlertMode = .unlockFolder
    @State private var showPasswordAlert = false
    
    enum PasswordAlertMode {
        case unlockFolder         // ロックされたフォルダを開く認証
        case setupAndLockFolder   // 初回マスターパスワード設定＆フォルダロック
        case lockFolderWithAuth   // 既存マスターパスワード認証によるフォルダロック設定
        case unlockSetting        // フォルダのロック保護設定を解除する認証
    }
    
    // ビューワ＆共有シート状態
    @State private var viewingItem: FileItem? = nil
    @State private var videoPlayingItem: FileItem? = nil
    @State private var audioPlayingItem: FileItem? = nil
    @State private var shareURL: URL? = nil
    @State private var shareURLs: [URL] = []
    @State private var isSharePresented = false
    
    // フォルダ移動/コピー先選択シート状態
    @State private var showFolderPicker = false
    @State private var folderPickerAction: FolderActionType = .move
    @State private var singleActionTargetURLs: [URL] = []
    
    // 外部ファイルインポート（ドキュメントピッカー & URLバッファ）
    @State private var showFileImporter = false
    @State private var pendingImportURLs: [URL] = []
    @State private var importDebounceTimer: Timer? = nil
    
    // 写真・動画ピッカー状態 (PhotosPicker)
    @State private var showPhotosPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isImportingPhotos = false
    
    enum SortOption {
        case name, date, size
    }
    
    enum FolderActionType {
        case move, copy
    }
    
    var body: some View {
        ZStack {
            // モダン・ダーク背景
            CosmicTheme.spaceBlack
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: - Header
                headerView
                
                // MARK: - Search Bar (ファイル検索バー)
                spectrumScannerView
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                // MARK: - Selection Action Bar (選択モード時アクションバー)
                if isSelectionMode {
                    selectionActionBarView
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // インポート通知バナー
                if let text = importedNotificationText {
                    HStack {
                        Image(systemName: "arrow.down.doc.fill")
                            .foregroundColor(CosmicTheme.nebulaCyan)
                        Text(text)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(CosmicTheme.starlightWhite)
                        Spacer()
                    }
                    .padding(10)
                    .background(CosmicTheme.nebulaPurple.opacity(0.4))
                    .cornerRadius(8)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // MARK: - Main File Grid / List (ファイル表示エリア & 左端エッジスワイプ親戻り対応)
                fileContentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 30, coordinateSpace: .local)
                            .onEnded { value in
                                // 画面左端付近からの右スワイプで親階層へ戻る
                                if value.startLocation.x < 50 && value.translation.width > 60 && abs(value.translation.height) < 100 {
                                    if currentDirectoryURL != nil {
                                        withAnimation {
                                            navigateToParentFolder()
                                        }
                                    }
                                }
                            }
                    )
                
                // MARK: - Mini Player (継続再生ミニプレーヤー)
                miniPlayerView
                
                // MARK: - Bottom Control Bar (戻るボタン, 3点リーダメニュー, ＋新規フォルダボタン)
                bottomControlBarView
                
                // MARK: - Ad Banner Slot (無料版バナー広告表示エリア 50pt / Pro版では完全非表示)
                if proManager.shouldDisplayAdBanner {
                    AdBannerSlotView {
                        showSettingsSheet = true
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // MARK: - Storage Meter (ストレージ使用量メーター)
                storageMeterView
            }
            
            // アプリ起動時ロック画面オーバーレイ
            if lockManager.isAppLockEnabled && lockManager.hasMasterPassword && !lockManager.isAppUnlockedForSession {
                AppLockOverlayView(lockManager: lockManager)
                    .transition(.opacity)
                    .zIndex(100)
            }
            
            // バックグラウンド移行・マルチタスク画面での覗き見防止シールド
            if lockManager.isPrivacyShieldEnabled && isPrivacyShieldVisible {
                PrivacyShieldOverlayView()
                    .transition(.opacity)
                    .zIndex(200)
            }
        }
        .onAppear {
            fileManager.purgeTemporaryDirectory()
            fileManager.refreshStorageInfo()
            loadFavorites()
            checkAppGroupPendingImports()
            if !UserDefaults.standard.bool(forKey: onboardingSeenKey) {
                showOnboardingSheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if lockManager.isPrivacyShieldEnabled {
                isPrivacyShieldVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            withAnimation(.easeOut(duration: 0.15)) {
                isPrivacyShieldVisible = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            checkAppGroupPendingImports()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            fileManager.purgeTemporaryDirectory()
            lockManager.handleAppDidEnterBackground()
        }
        // 他アプリ・Webからの受取インポート処理（デバウンスバッファ一括対応）
        .onOpenURL { incomingURL in
            pendingImportURLs.append(incomingURL)
            importDebounceTimer?.invalidate()
            importDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                let urlsToImport = pendingImportURLs
                pendingImportURLs.removeAll()
                let count = fileManager.importExternalFiles(from: urlsToImport, destinationDirURL: nil)
                withAnimation {
                    if count == 1, let first = urlsToImport.first {
                        importedNotificationText = "「ダウンロード」フォルダへ格納しました: \(first.lastPathComponent)"
                    } else if count > 1 {
                        importedNotificationText = "「ダウンロード」フォルダへ格納しました: \(count)件のファイル"
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    withAnimation {
                        importedNotificationText = nil
                    }
                }
            }
        }
        // 写真・動画ライブラリからの直接一括取り込み (PhotosPicker)
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 50,
            matching: .any(of: [.images, .videos]),
            photoLibrary: .shared()
        )
        .onChange(of: selectedPhotoItems) { items in
            guard !items.isEmpty else { return }
            importSelectedPhotos(items)
        }
        // アプリ内一括ファイル取り込み（「ファイル」アプリ等から複数選択）
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType.item],
            allowsMultipleSelection: true,
            onCompletion: { result in
                switch result {
                case .success(let urls):
                    let targetDir = currentDirectoryURL
                    let count = fileManager.importExternalFiles(from: urls, destinationDirURL: targetDir)
                    let dirName = targetDir?.lastPathComponent ?? "ダウンロード"
                    withAnimation {
                        if count == 1, let first = urls.first {
                            importedNotificationText = "「\(dirName)」へ格納しました: \(first.lastPathComponent)"
                        } else if count > 1 {
                            importedNotificationText = "「\(dirName)」へ格納しました: \(count)件のファイル"
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                        withAnimation {
                            importedNotificationText = nil
                        }
                    }
                case .failure(let error):
                    print("[ContentView] ファイル選択エラー: \(error)")
                }
            }
        )
        // フォルダロック認証 / 設定ダイアログ
        .alert(
            passwordAlertTitle,
            isPresented: $showPasswordAlert
        ) {
            SecureField("パスワード", text: $passwordInputText)
            Button("キャンセル", role: .cancel) {
                passwordTargetFolder = nil
                passwordInputText = ""
            }
            Button(passwordAlertConfirmButtonTitle) {
                processPasswordSubmit()
            }
        } message: {
            Text(passwordAlertMessageText)
        }
        // 新規フォルダ作成
        .alert("新規フォルダ作成", isPresented: $showNewFolderAlert) {
            TextField("フォルダ名", text: $newFolderName)
            Button("キャンセル", role: .cancel) { newFolderName = "" }
            Button("作成") {
                let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    try? fileManager.createDirectory(named: trimmed, parentURL: currentDirectoryURL)
                    newFolderName = ""
                    isFirstFolderGuideCompleted = true
                }
            }
        }
        // 名称変更
        .alert("名称変更", isPresented: Binding(
            get: { renameTargetItem != nil },
            set: { if !$0 { renameTargetItem = nil } }
        )) {
            TextField("新しい名前", text: $renameNewName)
            Button("キャンセル", role: .cancel) { renameTargetItem = nil }
            Button("変更") {
                if let item = renameTargetItem, !renameNewName.isEmpty {
                    try? fileManager.renameItem(at: item.url, to: renameNewName)
                    renameTargetItem = nil
                }
            }
        }
        // 詳細情報シート
        .sheet(item: $selectedFileForDetail) { item in
            FileDetailView(item: item)
        }
        // インアプリ・ビューワ（画像 / PDF - 表示順ソート連動スワイプ連続表示対応）
        .fullScreenCover(item: $viewingItem) { item in
            CosmicViewerSheet(
                initialItem: item,
                folderItems: filteredAndSortedItems,
                onShare: { targetURL in
                    self.shareURL = targetURL
                    self.isSharePresented = true
                }
            )
        }
        // 高機能動画プレイヤー (フォルダ連続再生)
        .fullScreenCover(item: $videoPlayingItem) { item in
            CosmicVideoPlayerSheet(
                initialItem: item,
                folderItems: filteredAndSortedItems,
                isFavorite: { item in isFavorite(item: item) },
                onToggleFavorite: { item in toggleFavorite(item: item) },
                onDelete: { itemToDelete in
                    try? fileManager.deleteItem(at: itemToDelete.url)
                }
            )
        }
        // 高機能音声プレイヤー
        .fullScreenCover(item: $audioPlayingItem) { item in
            CosmicAudioPlayerSheet(
                initialItem: item,
                folderItems: filteredAndSortedItems,
                isFavorite: { item in isFavorite(item: item) },
                onToggleFavorite: { item in toggleFavorite(item: item) },
                onDelete: { itemToDelete in
                    try? fileManager.deleteItem(at: itemToDelete.url)
                }
            )
        }
        // フォルダ移動/コピー先選択シート
        .sheet(isPresented: $showFolderPicker) {
            FolderDestinationPickerSheet(
                actionType: folderPickerAction,
                targetURLs: singleActionTargetURLs.isEmpty ? Array(selectedURLs) : singleActionTargetURLs,
                onDestinationSelected: { destDirURL in
                    let targets = singleActionTargetURLs.isEmpty ? Array(selectedURLs) : singleActionTargetURLs
                    if folderPickerAction == .move {
                        fileManager.moveItems(urls: targets, to: destDirURL)
                    } else {
                        fileManager.copyItems(urls: targets, to: destDirURL)
                    }
                    isSelectionMode = false
                    selectedURLs.removeAll()
                    singleActionTargetURLs.removeAll()
                }
            )
        }
        // 他アプリで開く（Share Sheet / UIActivityViewController）
        .sheet(isPresented: $isSharePresented) {
            if !shareURLs.isEmpty {
                ActivityViewControllerBridge(activityItems: shareURLs)
            } else if let url = shareURL {
                ActivityViewControllerBridge(activityItems: [url])
            }
        }
        // 設定・アプリ情報シート
        .sheet(isPresented: $showSettingsSheet) {
            SettingsSheetView(
                lockManager: lockManager,
                fileManager: fileManager,
                appVersion: appVersion,
                onShowOnboarding: {
                    showOnboardingSheet = true
                }
            )
        }
        // 初回起動オンボーディング（使い方ガイド）シート
        .fullScreenCover(isPresented: $showOnboardingSheet) {
            OnboardingSheetView {
                UserDefaults.standard.set(true, forKey: onboardingSeenKey)
            }
        }
        // コピー / 移動 / ZIP 最下部ステータスバー (進捗パーセント & プログレスバー)
        .safeAreaInset(edge: .bottom) {
            if fileManager.isOperating {
                VStack(spacing: 6) {
                    HStack {
                        Text(fileManager.operationTitle)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(CosmicTheme.starlightWhite)
                        Spacer()
                        Text("\(Int(fileManager.operationProgress * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(CosmicTheme.nebulaCyan)
                    }
                    ProgressView(value: fileManager.operationProgress)
                        .tint(CosmicTheme.nebulaCyan)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(CosmicTheme.deepSpaceCard)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CosmicTheme.nebulaCyan.opacity(0.4), lineWidth: 1))
                        .shadow(color: CosmicTheme.nebulaCyan.opacity(0.4), radius: 8)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut, value: fileManager.isOperating)
            }
        }
    }
    
    // MARK: - Header Component
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("AltFiler")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(CosmicTheme.starlightWhite)
                    
                    Text(appVersion)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(CosmicTheme.nebulaCyan)
                }
                
                if currentDirectoryURL != nil {
                    Text("フォルダ: " + currentDirectoryRelativePath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(CosmicTheme.cosmicTextSub)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Button(action: {
                showSettingsSheet = true
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(CosmicTheme.nebulaCyan)
                    .padding(8)
                    .background(
                        Circle()
                            .fill(CosmicTheme.deepSpaceCard)
                            .overlay(Circle().stroke(CosmicTheme.nebulaCyan.opacity(0.35), lineWidth: 1))
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
    
    // MARK: - Bottom Control Bar (戻るボタン, 3点リーダメニュー, ＋新規フォルダ作成ボタン)
    private var bottomControlBarView: some View {
        HStack(spacing: 14) {
            // 戻るボタン
            Button(action: {
                if currentDirectoryURL != nil {
                    withAnimation {
                        navigateToParentFolder()
                    }
                }
            }) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(currentDirectoryURL != nil ? CosmicTheme.nebulaCyan : CosmicTheme.cosmicTextSub.opacity(0.3))
            }
            .disabled(currentDirectoryURL == nil)
            
            // 3点リーダメニュー
            Menu {
                Button(action: { showPhotosPicker = true }) {
                    Label("写真・動画を取り込む", systemImage: "photo.on.rectangle.angled")
                }
                
                Button(action: { showFileImporter = true }) {
                    Label("外部ファイルを取り込む", systemImage: "square.and.arrow.down")
                }
                
                Divider()
                
                Button(action: {
                    isSelectionMode.toggle()
                    if !isSelectionMode { selectedURLs.removeAll() }
                }) {
                    Label(isSelectionMode ? "選択モード解除" : "複数選択", systemImage: isSelectionMode ? "xmark.circle" : "checkmark.circle")
                }
                
                Button(action: { showNewFolderAlert = true }) {
                    Label("新規フォルダ作成", systemImage: "folder.badge.plus")
                }
                
                Divider()
                
                Menu("並び順") {
                    Button("名前") { sortOption = .name }
                    Button("日時") { sortOption = .date }
                    Button("サイズ") { sortOption = .size }
                    Divider()
                    Button(action: { filterOnlyFavorites.toggle() }) {
                        Label(filterOnlyFavorites ? "すべてのファイルを表示" : "★ お気に入りだけ表示", systemImage: filterOnlyFavorites ? "star.slash" : "star.fill")
                    }
                }
                
                Button(action: { isAscending.toggle() }) {
                    Label(isAscending ? "昇順 ➔ 降順" : "降順 ➔ 昇順", systemImage: "arrow.up.arrow.down")
                }
                
                Divider()
                
                Button(action: { isGridView.toggle() }) {
                    Label(isGridView ? "リスト表示に切り替え" : "グリッド表示に切り替え", systemImage: isGridView ? "list.bullet" : "square.grid.2x2")
                }
                
                Divider()
                
                Button(action: { showSettingsSheet = true }) {
                    Label("設定・アプリ情報", systemImage: "gearshape.fill")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(isSelectionMode ? CosmicTheme.nebulaCyan : CosmicTheme.nebulaPurple)
                    .shadow(color: CosmicTheme.nebulaPurple.opacity(0.8), radius: 6)
            }
            
            // 「…」の右隣：ワンタップ新規フォルダ作成「＋」ボタン
            Button(action: {
                showNewFolderAlert = true
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(CosmicTheme.nebulaCyan)
                        .shadow(color: CosmicTheme.nebulaCyan.opacity(0.85), radius: shouldShowFirstFolderLead ? 8 : 4)
                    
                    if shouldShowFirstFolderLead {
                        Text("新規フォルダ")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(CosmicTheme.nebulaCyan)
                            .padding(.trailing, 4)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, shouldShowFirstFolderLead ? 6 : 0)
                .background(
                    Group {
                        if shouldShowFirstFolderLead {
                            Capsule()
                                .fill(CosmicTheme.nebulaCyan.opacity(0.15))
                                .overlay(Capsule().stroke(CosmicTheme.nebulaCyan.opacity(0.6), lineWidth: 1))
                        }
                    }
                )
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
    
    // MARK: - Search Bar
    private var spectrumScannerView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(searchQuery.isEmpty ? CosmicTheme.cosmicTextSub : CosmicTheme.nebulaCyan)
            
            TextField("ファイル検索...", text: $searchQuery)
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(CosmicTheme.starlightWhite)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            
            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(CosmicTheme.cosmicTextSub)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(CosmicTheme.deepSpaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: searchQuery.isEmpty ? [CosmicTheme.nebulaPurple.opacity(0.3), CosmicTheme.nebulaCyan.opacity(0.3)] : [CosmicTheme.nebulaCyan, CosmicTheme.nebulaPurple],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: searchQuery.isEmpty ? 1 : 1.5
                        )
                )
        )
    }
    
    // MARK: - Selection Action Bar (【全選択】 / 【解除】 / 【ZIP】 / 【共有】 / 【コピー】 / 【移動】 / 【削除】)
    private var selectionActionBarView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button(action: {
                    let currentURLs = filteredAndSortedItems.map { $0.url }
                    if selectedURLs.count == currentURLs.count {
                        selectedURLs.removeAll()
                    } else {
                        selectedURLs = Set(currentURLs)
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.square.fill")
                        Text(selectedURLs.count == filteredAndSortedItems.count && !filteredAndSortedItems.isEmpty ? "全解除" : "全選択")
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(CosmicTheme.nebulaCyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .background(CosmicTheme.nebulaCyan.opacity(0.15))
                    .cornerRadius(8)
                }
                
                Button(action: {
                    isSelectionMode = false
                    selectedURLs.removeAll()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "xmark.circle")
                        Text("閉じる")
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(CosmicTheme.cosmicTextSub)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Text("\(selectedURLs.count)項目")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(CosmicTheme.starlightWhite)
                    .padding(.horizontal, 4)
                
                Button(action: {
                    compressSelectedItemsToZip(Array(selectedURLs))
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.zipper")
                        Text("ZIP圧縮")
                    }
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.teal)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.teal.opacity(0.18))
                    .cornerRadius(8)
                }
                .disabled(selectedURLs.isEmpty)
                
                Button(action: {
                    self.shareURLs = Array(selectedURLs)
                    self.shareURL = nil
                    self.isSharePresented = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("共有")
                    }
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(CosmicTheme.starlightWhite)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(CosmicTheme.starlightWhite.opacity(0.15))
                    .cornerRadius(8)
                }
                .disabled(selectedURLs.isEmpty)
                
                Button(action: {
                    singleActionTargetURLs.removeAll()
                    folderPickerAction = .copy
                    showFolderPicker = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("コピー")
                    }
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(CosmicTheme.nebulaCyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(CosmicTheme.nebulaCyan.opacity(0.15))
                    .cornerRadius(8)
                }
                .disabled(selectedURLs.isEmpty)
                
                Button(action: {
                    singleActionTargetURLs.removeAll()
                    folderPickerAction = .move
                    showFolderPicker = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.line.flat")
                        Text("移動")
                    }
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(CosmicTheme.nebulaPurple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(CosmicTheme.nebulaPurple.opacity(0.15))
                    .cornerRadius(8)
                }
                .disabled(selectedURLs.isEmpty)
                
                Button(action: {
                    let targets = Array(selectedURLs)
                    let containsProtected = targets.contains { fileManager.isProtectedDownloadFolder($0) }
                    fileManager.deleteItems(urls: targets)
                    selectedURLs.removeAll()
                    isSelectionMode = false
                    if containsProtected {
                        withAnimation {
                            importedNotificationText = "※「ダウンロード」フォルダは外部取込用のため削除できません"
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                            withAnimation { importedNotificationText = nil }
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                        Text("削除")
                    }
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(CosmicTheme.singularityRed)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(CosmicTheme.singularityRed.opacity(0.15))
                    .cornerRadius(8)
                }
                .disabled(selectedURLs.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(CosmicTheme.deepSpaceCard)
        .border(width: 1, edges: [.bottom], color: CosmicTheme.nebulaCyan.opacity(0.4))
    }
    
    // MARK: - 初回起動時の新規フォルダ作成リード表示判定
    private var shouldShowFirstFolderLead: Bool {
        currentDirectoryURL == nil && searchQuery.isEmpty && !isFirstFolderGuideCompleted && fileManager.rootItems.count <= 1
    }
    
    // MARK: - 初回フォルダ作成を促すリード画面カード
    private var firstFolderLeadCardView: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(CosmicTheme.nebulaCyan)
                    Text("FIRST STEP GUIDE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(CosmicTheme.nebulaCyan)
                }
                Spacer()
                Button(action: {
                    withAnimation {
                        isFirstFolderGuideCompleted = true
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(CosmicTheme.cosmicTextSub.opacity(0.7))
                }
            }
            
            ZStack {
                Circle()
                    .fill(CosmicTheme.nebulaCyan.opacity(0.14))
                    .frame(width: 64, height: 64)
                    .overlay(Circle().stroke(CosmicTheme.nebulaCyan.opacity(0.45), lineWidth: 1))
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(CosmicTheme.nebulaCyan)
            }
            .padding(.top, 2)
            
            VStack(spacing: 6) {
                Text("まずは「＋」ボタンから\n最初のフォルダを作ってみましょう")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(CosmicTheme.starlightWhite)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                
                Text("画面下部の「＋」ボタンを押すと、いつでも新しいフォルダを作成できます。「写真」「動画」「プライベート」など用途に合わせて自由に作成し、長押しメニューからロック保護（Face ID / Touch ID）も設定できます。")
                    .font(.system(size: 12))
                    .foregroundColor(CosmicTheme.cosmicTextSub)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 4)
            }
            
            Button(action: {
                showNewFolderAlert = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("最初のフォルダを作成する")
                        .fontWeight(.bold)
                }
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [CosmicTheme.nebulaCyan, CosmicTheme.nebulaPurple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .shadow(color: CosmicTheme.nebulaCyan.opacity(0.35), radius: 8, y: 2)
            }
            .padding(.top, 4)
            
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(CosmicTheme.nebulaCyan)
                Text("画面左下の「＋ 新規フォルダ」からもワンタップで作成できます")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CosmicTheme.nebulaCyan)
            }
            .padding(.top, 2)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(CosmicTheme.deepSpaceCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            LinearGradient(
                                colors: [CosmicTheme.nebulaCyan.opacity(0.65), CosmicTheme.nebulaPurple.opacity(0.55)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: CosmicTheme.nebulaCyan.opacity(0.18), radius: 12)
        )
    }
    
    // MARK: - File Content View
    private var fileContentView: some View {
        let items = filteredAndSortedItems
        
        return Group {
            if items.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    if shouldShowFirstFolderLead {
                        firstFolderLeadCardView
                            .padding(.horizontal, 16)
                    } else {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 48))
                            .foregroundColor(CosmicTheme.cosmicTextSub.opacity(0.5))
                        Text("ファイルやフォルダが存在しません")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(CosmicTheme.cosmicTextSub)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            } else if isGridView {
                ScrollView {
                    VStack(spacing: 20) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 14)], spacing: 16) {
                            ForEach(items) { item in
                                gridCell(for: item)
                            }
                        }
                        
                        if shouldShowFirstFolderLead {
                            firstFolderLeadCardView
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(16)
                }
            } else {
                List {
                    ForEach(items) { item in
                        listRow(for: item)
                            .listRowBackground(CosmicTheme.deepSpaceCard)
                    }
                    if shouldShowFirstFolderLead {
                        firstFolderLeadCardView
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .padding(.vertical, 8)
                    }
                }
                .listStyle(.plain)
            }
        }
        .id(currentDirectoryURL)
    }
    
    // MARK: - Grid Cell
    private func gridCell(for item: FileItem) -> some View {
        let isSelected = selectedURLs.contains(item.url)
        let isDup = duplicateFileURLs.contains(item.url)
        let isFav = isFavorite(item: item)
        
        return VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? CosmicTheme.nebulaCyan.opacity(0.2) : CosmicTheme.deepSpaceCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? CosmicTheme.nebulaCyan : (item.isDirectory ? CosmicTheme.nebulaPurple.opacity(0.5) : CosmicTheme.nebulaCyan.opacity(0.3)), lineWidth: isSelected ? 2 : 1)
                    )
                
                FileThumbnailView(item: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(6)
                
                // 重複ファイルバッジ (赤チェックマーク - 左上)
                if isDup {
                    VStack {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.red)
                                .shadow(color: .black, radius: 4)
                                .padding(6)
                            Spacer()
                        }
                        Spacer()
                    }
                }
                
                // お気に入りバッジ (黄色い星 - 右上)
                if isFav {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "star.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.yellow)
                                .shadow(color: .black, radius: 4)
                                .padding(6)
                        }
                        Spacer()
                    }
                }
                
                if isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundColor(isSelected ? CosmicTheme.nebulaCyan : CosmicTheme.cosmicTextSub)
                        .padding(8)
                }
            }
            .frame(height: 95)
            .contentShape(Rectangle())
            .clipped()
            
            HStack(spacing: 4) {
                if isFav {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                }
                Text(item.name)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(CosmicTheme.starlightWhite)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleItemTap(item)
        }
        // ドラッグ＆ドロップ（複数選択中も一括ドラッグ移動対応）
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard item.isDirectory else { return false }
            if isSelectionMode && !selectedURLs.isEmpty {
                return handleDropToFolder(targetFolder: item, draggedURL: nil)
            }
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let sourceURL = url {
                        DispatchQueue.main.async {
                            _ = handleDropToFolder(targetFolder: item, draggedURL: sourceURL)
                        }
                    }
                }
            }
            return true
        }
        .contextMenu {
            contextMenuItems(for: item)
        }
    }
    
    // MARK: - List Row
    private func listRow(for item: FileItem) -> some View {
        let isSelected = selectedURLs.contains(item.url)
        let isDup = duplicateFileURLs.contains(item.url)
        let isFav = isFavorite(item: item)
        
        return HStack(spacing: 12) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? CosmicTheme.nebulaCyan : CosmicTheme.cosmicTextSub)
            }
            
            ZStack(alignment: .topLeading) {
                FileThumbnailView(item: item)
                    .frame(width: 36, height: 36)
                
                if isDup {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .offset(x: -4, y: -4)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if isFav {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.yellow)
                    }
                    Text(item.name)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(CosmicTheme.starlightWhite)
                        .lineLimit(1)
                }
                
                Text(item.isDirectory ? "フォルダ" : formatBytes(item.size))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(CosmicTheme.cosmicTextSub)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            handleItemTap(item)
        }
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard item.isDirectory else { return false }
            if isSelectionMode && !selectedURLs.isEmpty {
                return handleDropToFolder(targetFolder: item, draggedURL: nil)
            }
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let sourceURL = url {
                        DispatchQueue.main.async {
                            _ = handleDropToFolder(targetFolder: item, draggedURL: sourceURL)
                        }
                    }
                }
            }
            return true
        }
        .contextMenu {
            contextMenuItems(for: item)
        }
    }
    
    // MARK: - ドラッグ＆ドロップ一括処理
    @discardableResult
    private func handleDropToFolder(targetFolder: FileItem, draggedURL: URL?) -> Bool {
        guard targetFolder.isDirectory else { return false }
        
        let urlsToMove: [URL]
        if isSelectionMode && !selectedURLs.isEmpty {
            urlsToMove = Array(selectedURLs)
        } else if let url = draggedURL {
            urlsToMove = [url]
        } else {
            return false
        }
        
        let validURLs = urlsToMove.filter { $0 != targetFolder.url }
        guard !validURLs.isEmpty else { return false }
        
        fileManager.moveItems(urls: validURLs, to: targetFolder.url)
        
        if isSelectionMode {
            selectedURLs.removeAll()
            isSelectionMode = false
        }
        
        withAnimation {
            importedNotificationText = "「\(targetFolder.name)」へ\(validURLs.count)件を移動しました"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation { importedNotificationText = nil }
        }
        
        return true
    }
    
    // MARK: - Context Menu
    @ViewBuilder
    private func contextMenuItems(for item: FileItem) -> some View {
        Text(item.name)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
        
        Button(action: {
            toggleFavorite(item: item)
        }) {
            Label(
                isFavorite(item: item) ? "お気に入りから削除" : "お気に入りに追加",
                systemImage: isFavorite(item: item) ? "star.slash" : "star.fill"
            )
        }
        
        Divider()
        
        Button(action: {
            selectedFileForDetail = item
        }) {
            Label("詳細情報", systemImage: "info.circle")
        }
        
        Button(action: {
            self.shareURLs = [item.url]
            self.shareURL = item.url
            self.isSharePresented = true
        }) {
            Label(item.isDirectory ? "共有 (ファイルアプリ等へ保存)" : "アプリで開く (共有)", systemImage: "square.and.arrow.up")
        }
        
        Button(action: {
            singleActionTargetURLs = [item.url]
            folderPickerAction = .copy
            showFolderPicker = true
        }) {
            Label("コピー", systemImage: "doc.on.doc")
        }
        
        if !fileManager.isProtectedDownloadFolder(item.url) {
            Button(action: {
                singleActionTargetURLs = [item.url]
                folderPickerAction = .move
                showFolderPicker = true
            }) {
                Label("移動", systemImage: "folder.line.flat")
            }
            
            Button(action: {
                renameTargetItem = item
                renameNewName = item.name
            }) {
                Label("名称変更", systemImage: "pencil")
            }
        }
        
        Divider()
        
        // ZIP 解凍・圧縮メニュー
        if !item.isDirectory && item.url.pathExtension.lowercased() == "zip" {
            Button(action: {
                extractZipArchiveItem(item)
            }) {
                Label("ZIPをここに解凍", systemImage: "archivebox.fill")
            }
        }
        
        Button(action: {
            compressSelectedItemsToZip([item.url])
        }) {
            Label("ZIPに圧縮", systemImage: "doc.zipper")
        }
        
        // フォルダ専用：鍵・ロック機能（認証必須）
        if item.isDirectory {
            Divider()
            if lockManager.isFolderProtected(url: item.url) {
                Button(action: {
                    requestUnlockFolderSetting(item: item)
                }) {
                    Label("ロック解除 (保護オフ)", systemImage: "lock.open")
                }
            } else {
                Button(action: {
                    requestLockFolderSetting(item: item)
                }) {
                    Label("ロック設定 (保護オン)", systemImage: "lock.fill")
                }
            }
        }
        
        Divider()
        
        // メニューから明示的に選択モードへ移行
        Button(action: {
            isSelectionMode = true
            selectedURLs.insert(item.url)
        }) {
            Label("選択", systemImage: "checkmark.circle")
        }
        
        if !fileManager.isProtectedDownloadFolder(item.url) {
            Divider()
            
            Button(role: .destructive, action: {
                try? fileManager.deleteItem(at: item.url)
            }) {
                Label("削除", systemImage: "trash.fill")
            }
        }
    }
    
    // MARK: - Storage Meter
    private var storageMeterView: some View {
        VStack(spacing: 6) {
            HStack {
                Text("ストレージ使用量")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(CosmicTheme.nebulaCyan)
                Spacer()
                Text("アプリ保存量: \(formatBytes(fileManager.appStorageBytes)) / 端末空き: \(formatBytes(fileManager.freeDiskSpaceBytes))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(CosmicTheme.cosmicTextSub)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.1))
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [CosmicTheme.nebulaPurple, CosmicTheme.nebulaCyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(10, geo.size.width * CGFloat(min(1.0, Double(fileManager.appStorageBytes) / Double(max(1, fileManager.freeDiskSpaceBytes + fileManager.appStorageBytes))))))
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(CosmicTheme.spaceBlack.opacity(0.95))
        .border(width: 1, edges: [.top], color: Color.white.opacity(0.1))
    }
    
    // MARK: - Mini Player View (継続再生ミニプレーヤーバー)
    @ViewBuilder
    private var miniPlayerView: some View {
        if let item = playbackManager.currentItem {
            HStack(spacing: 12) {
                Button(action: {
                    if playbackManager.isVideo {
                        videoPlayingItem = item
                    } else {
                        audioPlayingItem = item
                    }
                }) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(CosmicTheme.nebulaCyan.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: playbackManager.isVideo ? "video.fill" : "music.note")
                                .font(.system(size: 14))
                                .foregroundColor(CosmicTheme.nebulaCyan)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(CosmicTheme.starlightWhite)
                                .lineLimit(1)
                            
                            Text(playbackManager.isVideo ? "動画再生中" : "音声再生中")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(CosmicTheme.cosmicTextSub)
                        }
                    }
                }
                
                Spacer()
                
                Button(action: {
                    playbackManager.togglePlayPause()
                }) {
                    Image(systemName: playbackManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(CosmicTheme.nebulaCyan)
                }
                
                Button(action: {
                    playbackManager.stop()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(CosmicTheme.cosmicTextSub)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(CosmicTheme.deepSpaceCard)
            .border(width: 1, edges: [.top], color: CosmicTheme.nebulaCyan.opacity(0.3))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    // MARK: - お気に入り & 重複ファイル検出ヘルパー
    private func loadFavorites() {
        let array = UserDefaults.standard.stringArray(forKey: "AltFiler_FavoritePaths") ?? []
        favoritePaths = Set(array)
    }
    
    private func toggleFavorite(item: FileItem) {
        let rel = lockManager.relativePath(for: item.url)
        if favoritePaths.contains(rel) {
            favoritePaths.remove(rel)
        } else {
            favoritePaths.insert(rel)
        }
        UserDefaults.standard.set(Array(favoritePaths), forKey: "AltFiler_FavoritePaths")
    }
    
    private func isFavorite(item: FileItem) -> Bool {
        let rel = lockManager.relativePath(for: item.url)
        return favoritePaths.contains(rel)
    }
    
    private var duplicateFileURLs: Set<URL> {
        let items = fileManager.listItems(at: currentDirectoryURL).filter { !$0.isDirectory && $0.size > 0 }
        var sizeMap: [Int64: [URL]] = [:]
        for item in items {
            sizeMap[item.size, default: []].append(item.url)
        }
        var duplicates = Set<URL>()
        for (_, urls) in sizeMap where urls.count > 1 {
            for url in urls {
                duplicates.insert(url)
            }
        }
        return duplicates
    }
    
    // MARK: - Action Handlers
    private var filteredAndSortedItems: [FileItem] {
        let items = fileManager.listItems(at: currentDirectoryURL)
        var filtered = searchQuery.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
        
        if filterOnlyFavorites {
            filtered = filtered.filter { isFavorite(item: $0) }
        }
        
        return filtered.sorted { item1, item2 in
            if item1.isDirectory != item2.isDirectory {
                return item1.isDirectory
            }
            
            let result: Bool
            switch sortOption {
            case .name:
                result = item1.name.localizedCompare(item2.name) == .orderedAscending
            case .date:
                result = item1.modificationDate < item2.modificationDate
            case .size:
                result = item1.size < item2.size
            }
            return isAscending ? result : !result
        }
    }
    
    private var currentDirectoryRelativePath: String {
        guard let current = currentDirectoryURL?.resolvingSymlinksInPath() else { return "/" }
        let rootURL = LocalFileManager.shared.rootDirectoryURL.resolvingSymlinksInPath()
        let currentPath = current.standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path
        
        if currentPath.hasPrefix(rootPath) {
            let rel = String(currentPath.dropFirst(rootPath.count))
            return rel.isEmpty ? "/" : rel
        }
        return "/" + current.lastPathComponent
    }
    
    /// 写真・動画ライブラリから選択されたメディアの一括取り込み（大容量動画ストリーミング・安全非同期対応）
    private func importSelectedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let targetDir = currentDirectoryURL
        let dirName = targetDir?.lastPathComponent ?? "ダウンロード"
        let totalCount = items.count
        isImportingPhotos = true
        
        withAnimation {
            importedNotificationText = "メディアを取り込み中 (0/\(totalCount))..."
        }
        
        Task {
            var importedURLs: [URL] = []
            var processedCount = 0
            
            for item in items {
                // まず大容量動画（FileRepresentation）としてのロードを試行
                if let movie = try? await item.loadTransferable(type: MovieTransferable.self) {
                    importedURLs.append(movie.url)
                } else if let image = try? await item.loadTransferable(type: ImageTransferable.self) {
                    importedURLs.append(image.url)
                }
                processedCount += 1
                let current = processedCount
                await MainActor.run {
                    withAnimation {
                        importedNotificationText = "メディアを取り込み中 (\(current)/\(totalCount))..."
                    }
                }
            }
            
            // ローカルストレージ（ダウンロードフォルダまたは現在開いているフォルダ）へ格納
            let successCount = fileManager.importExternalFiles(from: importedURLs, destinationDirURL: targetDir)
            
            await MainActor.run {
                selectedPhotoItems.removeAll()
                isImportingPhotos = false
                withAnimation {
                    if successCount > 0 {
                        importedNotificationText = "「\(dirName)」へ格納しました: \(successCount)件のメディア"
                    } else {
                        importedNotificationText = "メディアの取り込みに失敗しました"
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    withAnimation {
                        importedNotificationText = nil
                    }
                }
            }
        }
    }
    
    // MARK: - App Group 共有コンテナからの自動取り込み
    private func checkAppGroupPendingImports() {
        let appGroupId: String
        if let customGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String, !customGroup.isEmpty {
            appGroupId = customGroup
        } else {
            appGroupId = Bundle.main.bundleIdentifier.map { "group.\($0)" } ?? "group.app.altfiler"
        }
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            return
        }
        let pendingDir = containerURL.appendingPathComponent("PendingImports", isDirectory: true)
        let fileManager = FileManager.default
        
        guard let files = try? fileManager.contentsOfDirectory(at: pendingDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]), !files.isEmpty else {
            return
        }
        
        let count = self.fileManager.importExternalFiles(from: files, destinationDirURL: nil)
        
        // 共有コンテナ内の一時ファイルをクリーンアップ
        for file in files {
            try? fileManager.removeItem(at: file)
        }
        
        if count > 0 {
            withAnimation {
                importedNotificationText = "共有から「ダウンロード」フォルダへ格納しました: \(count)件"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                withAnimation {
                    importedNotificationText = nil
                }
            }
        }
    }
    
    private func navigateToParentFolder() {
        guard let current = currentDirectoryURL?.resolvingSymlinksInPath() else { return }
        
        let activeRoot = LocalFileManager.shared.rootDirectoryURL.resolvingSymlinksInPath()
        let currentPath = current.standardizedFileURL.path
        let rootPath = activeRoot.standardizedFileURL.path
        
        if currentPath == rootPath || !currentPath.hasPrefix(rootPath) {
            currentDirectoryURL = nil
            if isSelectionMode {
                isSelectionMode = false
                selectedURLs.removeAll()
            }
            return
        }
        
        let parent = current.deletingLastPathComponent().resolvingSymlinksInPath()
        let parentPath = parent.standardizedFileURL.path
        
        if parentPath == rootPath {
            currentDirectoryURL = nil
        } else if parentPath.hasPrefix(rootPath) {
            currentDirectoryURL = parent
        } else {
            currentDirectoryURL = nil
        }
        
        if isSelectionMode {
            isSelectionMode = false
            selectedURLs.removeAll()
        }
    }
    
    private func handleItemTap(_ item: FileItem) {
        if isSelectionMode {
            if selectedURLs.contains(item.url) {
                selectedURLs.remove(item.url)
            } else {
                selectedURLs.insert(item.url)
            }
        } else {
            if item.isDirectory {
                if lockManager.isFolderLocked(url: item.url) {
                    // 生体認証 (Face ID / Touch ID) をまず試行
                    lockManager.authenticateWithBiometrics(reason: "フォルダ「\(item.name)」の鍵を解除") { success in
                        if success {
                            lockManager.unlockFolderForSession(url: item.url)
                            currentDirectoryURL = item.url
                        } else {
                            // 生体認証不可・キャンセル時はパスワード入力アラート
                            passwordTargetFolder = item
                            passwordInputText = ""
                            passwordAlertMode = .unlockFolder
                            showPasswordAlert = true
                        }
                    }
                } else {
                    currentDirectoryURL = item.url
                }
            } else {
                let ext = item.url.pathExtension.lowercased()
                let videoExtensions = ["mp4", "mov", "m4v", "mkv", "avi", "webm", "3gp"]
                let audioExtensions = ["mp3", "m4a", "wav", "aac", "flac", "aiff", "alac", "ogg"]
                if ext == "zip" {
                    extractZipArchiveItem(item)
                } else if videoExtensions.contains(ext) {
                    videoPlayingItem = item
                } else if audioExtensions.contains(ext) {
                    audioPlayingItem = item
                } else {
                    viewingItem = item
                }
            }
        }
    }
    
    // MARK: - ZIP 圧縮・解凍アクション
    
    private func compressSelectedItemsToZip(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let targetDir = currentDirectoryURL ?? fileManager.rootDirectoryURL
        fileManager.compressItems(urls: urls, in: targetDir) { result in
            if isSelectionMode {
                selectedURLs.removeAll()
                isSelectionMode = false
            }
            switch result {
            case .success(let zipURL):
                withAnimation {
                    importedNotificationText = "📦 ZIP圧縮完了: \(zipURL.lastPathComponent)"
                }
            case .failure(let error):
                withAnimation {
                    importedNotificationText = "⚠️ ZIP圧縮エラー: \(error.localizedDescription)"
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                withAnimation { importedNotificationText = nil }
            }
        }
    }
    
    private func extractZipArchiveItem(_ item: FileItem) {
        let targetDir = currentDirectoryURL ?? fileManager.rootDirectoryURL
        fileManager.extractZipItem(at: item.url, in: targetDir) { result in
            switch result {
            case .success(let folderURL):
                withAnimation {
                    importedNotificationText = "📂 ZIP解凍完了: \(folderURL.lastPathComponent)"
                }
            case .failure(let error):
                withAnimation {
                    importedNotificationText = "⚠️ ZIP解凍エラー: \(error.localizedDescription)"
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                withAnimation { importedNotificationText = nil }
            }
        }
    }
    
    // MARK: - フォルダ鍵・ロック管理ヘルパー（全操作に認証を要求する厳格仕様）
    
    private func requestLockFolderSetting(item: FileItem) {
        if lockManager.hasMasterPassword {
            // マスターパスワード登録済みの場合も、生体認証または現在のパスワード認証が必須
            lockManager.authenticateWithBiometrics(reason: "フォルダ「\(item.name)」にロックを設定") { success in
                if success {
                    lockManager.lockFolder(url: item.url)
                    withAnimation {
                        importedNotificationText = "🔒 フォルダ「\(item.name)」をロックしました"
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        withAnimation { importedNotificationText = nil }
                    }
                } else {
                    passwordTargetFolder = item
                    passwordInputText = ""
                    passwordAlertMode = .lockFolderWithAuth
                    showPasswordAlert = true
                }
            }
        } else {
            // マスターパスワード未登録時、新規パスワード設定ダイアログ
            passwordTargetFolder = item
            passwordInputText = ""
            passwordAlertMode = .setupAndLockFolder
            showPasswordAlert = true
        }
    }
    
    private func requestUnlockFolderSetting(item: FileItem) {
        lockManager.authenticateWithBiometrics(reason: "フォルダ「\(item.name)」のロック設定を解除") { success in
            if success {
                lockManager.unlockFolderSetting(url: item.url)
                withAnimation {
                    importedNotificationText = "🔓 フォルダ「\(item.name)」のロックを解除しました"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation { importedNotificationText = nil }
                }
            } else {
                passwordTargetFolder = item
                passwordInputText = ""
                passwordAlertMode = .unlockSetting
                showPasswordAlert = true
            }
        }
    }
    
    private var passwordAlertTitle: String {
        switch passwordAlertMode {
        case .unlockFolder: return "フォルダ解錠認証"
        case .setupAndLockFolder: return "パスワード設定 & ロック"
        case .lockFolderWithAuth: return "フォルダロック認証"
        case .unlockSetting: return "ロック設定の解除"
        }
    }
    
    private var passwordAlertConfirmButtonTitle: String {
        switch passwordAlertMode {
        case .unlockFolder: return "解錠"
        case .setupAndLockFolder: return "設定してロック"
        case .lockFolderWithAuth: return "ロックする"
        case .unlockSetting: return "解除"
        }
    }
    
    private var passwordAlertMessageText: String {
        guard let folder = passwordTargetFolder else { return "" }
        switch passwordAlertMode {
        case .unlockFolder:
            return "フォルダ「\(folder.name)」はロックされています。パスワードを入力してください。"
        case .setupAndLockFolder:
            return "フォルダ保護に使用するマスターパスワードを入力してください。"
        case .lockFolderWithAuth:
            return "フォルダ「\(folder.name)」をロックするには現在のパスワードを入力してください。"
        case .unlockSetting:
            return "フォルダ「\(folder.name)」のロック保護を解除するにはパスワードを入力してください。"
        }
    }
    
    private func processPasswordSubmit() {
        guard let folder = passwordTargetFolder else { return }
        let input = passwordInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        
        switch passwordAlertMode {
        case .unlockFolder:
            if lockManager.verifyPassword(input) {
                lockManager.unlockFolderForSession(url: folder.url)
                currentDirectoryURL = folder.url
            } else {
                withAnimation {
                    importedNotificationText = "⚠️ パスワードが正しくありません"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation { importedNotificationText = nil }
                }
            }
        case .setupAndLockFolder:
            lockManager.setMasterPassword(input)
            lockManager.lockFolder(url: folder.url)
            withAnimation {
                importedNotificationText = "🔒 フォルダ「\(folder.name)」をロックしました"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation { importedNotificationText = nil }
            }
        case .lockFolderWithAuth:
            if lockManager.verifyPassword(input) {
                lockManager.lockFolder(url: folder.url)
                withAnimation {
                    importedNotificationText = "🔒 フォルダ「\(folder.name)」をロックしました"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation { importedNotificationText = nil }
                }
            } else {
                withAnimation {
                    importedNotificationText = "⚠️ パスワードが正しくありません"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation { importedNotificationText = nil }
                }
            }
        case .unlockSetting:
            if lockManager.verifyPassword(input) {
                lockManager.unlockFolderSetting(url: folder.url)
                withAnimation {
                    importedNotificationText = "🔓 フォルダ「\(folder.name)」のロックを解除しました"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation { importedNotificationText = nil }
                }
            } else {
                withAnimation {
                    importedNotificationText = "⚠️ パスワードが正しくありません"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation { importedNotificationText = nil }
                }
            }
        }
        
        passwordTargetFolder = nil
        passwordInputText = ""
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - File Thumbnail Component
struct FileThumbnailView: View {
    let item: FileItem
    @State private var thumbnailImage: UIImage? = nil
    
    var body: some View {
        ZStack {
            if item.isDirectory {
                // 完全ステルス仕様：見た目ではロックの有無が判断できない通常のパープルアイコン
                Image(systemName: "folder.fill")
                    .font(.system(size: 34))
                    .foregroundColor(CosmicTheme.nebulaPurple)
            } else if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .clipped()
            } else {
                Image(systemName: defaultIconName(for: item.name))
                    .font(.system(size: 32))
                    .foregroundColor(CosmicTheme.nebulaCyan)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            generateThumbnail()
        }
    }
    
    private func generateThumbnail() {
        guard !item.isDirectory else { return }
        let ext = item.url.pathExtension.lowercased()
        
        DispatchQueue.global(qos: .userInitiated).async {
            var image: UIImage? = nil
            
            if ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(ext) {
                image = UIImage(contentsOfFile: item.url.path)
            } else if ["mp4", "mov", "m4v", "mkv", "avi"].contains(ext) {
                let asset = AVAsset(url: item.url)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                let time = CMTime(seconds: 1.0, preferredTimescale: 60)
                if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                    image = UIImage(cgImage: cgImage)
                }
            } else if ext == "pdf" {
                if let doc = PDFDocument(url: item.url), let page = doc.page(at: 0) {
                    let pageRect = page.bounds(for: .mediaBox)
                    let renderer = UIGraphicsImageRenderer(size: pageRect.size)
                    image = renderer.image { ctx in
                        UIColor.white.set()
                        ctx.fill(pageRect)
                        ctx.cgContext.translateBy(x: 0, y: pageRect.size.height)
                        ctx.cgContext.scaleBy(x: 1.0, y: -1.0)
                        page.draw(with: .mediaBox, to: ctx.cgContext)
                    }
                }
            }
            
            if let result = image {
                DispatchQueue.main.async {
                    self.thumbnailImage = result
                }
            }
        }
    }
    
    private func defaultIconName(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "gif", "webp": return "photo.fill"
        case "mp4", "mov", "m4v", "mkv", "avi": return "film.fill"
        case "mp3", "m4a", "wav", "aac", "flac": return "waveform"
        case "pdf": return "doc.richtext.fill"
        case "txt", "md": return "doc.text.fill"
        case "zip", "tar", "gz": return "archivebox.fill"
        default: return "doc.fill"
        }
    }
}

// MARK: - File Detail View
struct FileDetailView: View {
    let item: FileItem
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                CosmicTheme.spaceBlack.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    FileThumbnailView(item: item)
                        .frame(width: 80, height: 80)
                        .padding(.top, 20)
                    
                    Text(item.name)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(CosmicTheme.starlightWhite)
                        .multilineTextAlignment(.center)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        detailRow(title: "種類", value: item.isDirectory ? "フォルダ" : "ファイル")
                        detailRow(title: "サイズ", value: formatBytes(item.size))
                        detailRow(title: "作成日時", value: formatDate(item.creationDate))
                        detailRow(title: "更新日時", value: formatDate(item.modificationDate))
                        detailRow(title: "パス", value: item.url.path)
                    }
                    .padding(16)
                    .background(CosmicTheme.deepSpaceCard)
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    
                    Spacer()
                }
            }
            .navigationTitle("詳細情報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
    
    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(CosmicTheme.nebulaCyan)
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(CosmicTheme.starlightWhite)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - ズームイン/アウト・全画面フィット・指スワイプ切替対応 画像ビューア
struct CosmicZoomableImageView: View {
    let uiImage: UIImage
    var onSwipePrevious: (() -> Void)? = nil
    var onSwipeNext: (() -> Void)? = nil
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale = max(1.0, min(scale * delta, 5.0))
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                                if scale <= 1.0 {
                                    withAnimation(.spring()) {
                                        scale = 1.0
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                if scale > 1.0 {
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                            }
                            .onEnded { value in
                                if scale > 1.0 {
                                    lastOffset = offset
                                } else {
                                    // 等倍(scale <= 1.0)時の左右指スワイプ判定で前後の画像へ切替
                                    let horizontalAmount = value.translation.width
                                    let verticalAmount = value.translation.height
                                    if abs(horizontalAmount) > 50 && abs(horizontalAmount) > abs(verticalAmount) {
                                        if horizontalAmount > 0 {
                                            onSwipePrevious?() // 右スワイプ -> 前の画像へ
                                        } else {
                                            onSwipeNext?()     // 左スワイプ -> 次の画像へ
                                        }
                                    }
                                    withAnimation(.spring()) {
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            if scale > 1.0 {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2.5
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

struct CosmicViewerSheet: View {
    let initialItem: FileItem
    var folderItems: [FileItem] = []
    let onShare: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var imagePlaylist: [FileItem] = []
    @State private var currentIndex: Int = 0
    
    private var currentItem: FileItem {
        if imagePlaylist.indices.contains(currentIndex) {
            return imagePlaylist[currentIndex]
        }
        return initialItem
    }
    
    var body: some View {
        ZStack {
            CosmicTheme.spaceBlack.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 上部: 画像・コンテンツ表示エリア
                let ext = currentItem.url.pathExtension.lowercased()
                Group {
                    if ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(ext) {
                        if let uiImage = UIImage(contentsOfFile: currentItem.url.path) {
                            CosmicZoomableImageView(
                                uiImage: uiImage,
                                onSwipePrevious: {
                                    showPreviousImage()
                                },
                                onSwipeNext: {
                                    showNextImage()
                                }
                            )
                            .id(currentItem.url)
                        } else {
                            viewerErrorView(message: "画像を読み込めませんでした")
                        }
                    } else if ext == "pdf" {
                        PDFKitRepresentable(url: currentItem.url)
                    } else {
                        viewerErrorView(message: "この形式のプレビューには対応していません")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // 下部: フッター（コントロールバー）
                HStack(spacing: 16) {
                    // 各種ボタン（左寄せ）
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(CosmicTheme.cosmicTextSub)
                    }
                    
                    Button(action: { onShare(currentItem.url) }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18))
                            .foregroundColor(CosmicTheme.nebulaCyan)
                    }
                    
                    if imagePlaylist.count > 1 {
                        HStack(spacing: 12) {
                            Button(action: showPreviousImage) {
                                Image(systemName: "chevron.left.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(currentIndex > 0 ? CosmicTheme.nebulaCyan : CosmicTheme.cosmicTextSub.opacity(0.3))
                            }
                            .disabled(currentIndex == 0)
                            
                            Button(action: showNextImage) {
                                Image(systemName: "chevron.right.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(currentIndex < imagePlaylist.count - 1 ? CosmicTheme.nebulaCyan : CosmicTheme.cosmicTextSub.opacity(0.3))
                            }
                            .disabled(currentIndex >= imagePlaylist.count - 1)
                        }
                    }
                    
                    Spacer()
                    
                    // ファイル名称・インジケータ（右側）
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(currentItem.name)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(CosmicTheme.starlightWhite)
                            .lineLimit(1)
                        
                        if imagePlaylist.count > 1 {
                            Text("\(currentIndex + 1) / \(imagePlaylist.count)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(CosmicTheme.nebulaCyan)
                        }
                    }
                }
                .padding(16)
                .background(CosmicTheme.deepSpaceCard)
            }
        }
        .statusBarHidden(true)
        .onAppear {
            setupImagePlaylist()
        }
    }
    
    private func setupImagePlaylist() {
        let imageExtensions = ["jpg", "jpeg", "png", "heic", "gif", "webp"]
        let images = folderItems.filter { item in
            !item.isDirectory && imageExtensions.contains(item.url.pathExtension.lowercased())
        }
        
        if images.isEmpty {
            self.imagePlaylist = [initialItem]
            self.currentIndex = 0
        } else {
            self.imagePlaylist = images
            if let idx = images.firstIndex(where: { $0.url == initialItem.url }) {
                self.currentIndex = idx
            } else {
                self.imagePlaylist = [initialItem]
                self.currentIndex = 0
            }
        }
    }
    
    private func showPreviousImage() {
        guard currentIndex > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            currentIndex -= 1
        }
    }
    
    private func showNextImage() {
        guard currentIndex < imagePlaylist.count - 1 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            currentIndex += 1
        }
    }
    
    private func viewerErrorView(message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(CosmicTheme.singularityRed)
            Text(message)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(CosmicTheme.starlightWhite)
            Spacer()
        }
    }
}

// MARK: - PDFKit Representable
struct PDFKitRepresentable: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}

// MARK: - Folder Destination Picker Sheet (多階層深層ナビゲーション対応)
struct FolderDestinationPickerSheet: View {
    let actionType: ContentView.FolderActionType
    let targetURLs: [URL]
    let onDestinationSelected: (URL) -> Void
    
    @State private var currentFolderURL: URL = LocalFileManager.shared.rootDirectoryURL
    @State private var navigationHistory: [URL] = []
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                CosmicTheme.spaceBlack.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // ヘッダー情報
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(actionType == .move ? "移動先フォルダを選択" : "コピー先フォルダを選択")
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundColor(CosmicTheme.starlightWhite)
                            
                            let isRoot = currentFolderURL.resolvingSymlinksInPath().standardizedFileURL == LocalFileManager.shared.rootDirectoryURL.resolvingSymlinksInPath().standardizedFileURL
                            let dirName = isRoot ? "ルート" : currentFolderURL.lastPathComponent
                            Text("対象: \(targetURLs.count)件 | 現在地: /\(dirName)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(CosmicTheme.nebulaCyan)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("キャンセル") { dismiss() }
                            .foregroundColor(CosmicTheme.cosmicTextSub)
                    }
                    .padding(16)
                    .background(CosmicTheme.deepSpaceCard)
                    
                    List {
                        // 上の階層へ戻るボタン
                        if !navigationHistory.isEmpty {
                            Button(action: {
                                if let parent = navigationHistory.popLast() {
                                    currentFolderURL = parent
                                }
                            }) {
                                HStack {
                                    Image(systemName: "chevron.left.circle.fill")
                                        .foregroundColor(CosmicTheme.nebulaCyan)
                                    Text("上の階層に戻る")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundColor(CosmicTheme.nebulaCyan)
                                }
                            }
                            .listRowBackground(CosmicTheme.deepSpaceCard)
                        }
                        
                        // 現在表示中のフォルダに決定するアクション行
                        Button(action: {
                            onDestinationSelected(currentFolderURL)
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(CosmicTheme.nebulaCyan)
                                Text(actionType == .move ? "この位置に移動決定" : "この位置にコピー決定")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(CosmicTheme.starlightWhite)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(CosmicTheme.nebulaPurple.opacity(0.35))
                        
                        // サブフォルダ一覧
                        ForEach(foldersInCurrentDirectory, id: \.url) { folder in
                            let isTargetSelf = targetURLs.contains(folder.url)
                            
                            Button(action: {
                                if !isTargetSelf {
                                    navigationHistory.append(currentFolderURL)
                                    currentFolderURL = folder.url
                                }
                            }) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(isTargetSelf ? CosmicTheme.cosmicTextSub : CosmicTheme.nebulaPurple)
                                    Text(folder.name)
                                        .font(.system(size: 14, design: .monospaced))
                                        .foregroundColor(isTargetSelf ? CosmicTheme.cosmicTextSub : CosmicTheme.starlightWhite)
                                    Spacer()
                                    if !isTargetSelf {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12))
                                            .foregroundColor(CosmicTheme.cosmicTextSub)
                                    }
                                }
                            }
                            .disabled(isTargetSelf)
                            .listRowBackground(CosmicTheme.deepSpaceCard)
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
    }
    
    private var foldersInCurrentDirectory: [FileItem] {
        LocalFileManager.shared.listItems(at: currentFolderURL).filter { $0.isDirectory }
    }
}

// MARK: - ActivityViewController Bridge
struct ActivityViewControllerBridge: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Border Helper
extension View {
    func border(width: CGFloat, edges: [Edge], color: Color) -> some View {
        overlay(EdgeBorder(width: width, edges: edges).foregroundColor(color))
    }
}

struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for edge in edges {
            var x: CGFloat {
                switch edge {
                case .top, .bottom, .leading: return rect.minX
                case .trailing: return rect.maxX - width
                }
            }
            var y: CGFloat {
                switch edge {
                case .top, .leading, .trailing: return rect.minY
                case .bottom: return rect.maxY - width
                }
            }
            var w: CGFloat {
                switch edge {
                case .top, .bottom: return rect.width
                case .leading, .trailing: return width
                }
            }
            var h: CGFloat {
                switch edge {
                case .top, .bottom: return width
                case .leading, .trailing: return rect.height
                }
            }
            path.addRect(CGRect(x: x, y: y, width: w, height: h))
        }
        return path
    }
}

// MARK: - Marquee Text (ゆったり自動スクロールテキスト)
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    
    @State private var animate = false
    
    var body: some View {
        GeometryReader { geo in
            let textWidth = measureTextWidth(text: text)
            if textWidth > geo.size.width - 20 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 45) {
                        Text(text)
                            .font(font)
                            .foregroundColor(color)
                        Text(text)
                            .font(font)
                            .foregroundColor(color)
                    }
                    .offset(x: animate ? -textWidth - 45 : 0)
                    .animation(
                        Animation.linear(duration: Double(text.count) * 0.38)
                            .repeatForever(autoreverses: false),
                        value: animate
                    )
                    .onAppear {
                        animate = true
                    }
                }
                .disabled(true)
            } else {
                Text(text)
                    .font(font)
                    .foregroundColor(color)
                    .lineLimit(1)
            }
        }
        .frame(height: 22)
    }
    
    private func measureTextWidth(text: String) -> CGFloat {
        let constraintRect = CGSize(width: CGFloat.greatestFiniteMagnitude, height: 24)
        let boundingBox = text.boundingRect(
            with: constraintRect,
            options: .usesLineFragmentOrigin,
            attributes: [.font: UIFont.monospacedSystemFont(ofSize: 15, weight: .bold)],
            context: nil
        )
        return ceil(boundingBox.width)
    }
}

// MARK: - AltFiler Video Player

enum PlayerRepeatMode: String, CaseIterable {
    case off = "OFF"
    case single = "1動画"
    case all = "全動画"
}

struct CosmicVideoPlayerSheet: View {
    let initialItem: FileItem
    let folderItems: [FileItem]
    let isFavorite: (FileItem) -> Bool
    let onToggleFavorite: (FileItem) -> Void
    let onDelete: (FileItem) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    // フォルダ内の動画アイテムリスト（再生リスト）
    @State private var videoPlaylist: [FileItem] = []
    @State private var currentIndex: Int = 0
    
    // AVPlayer 状態
    @State private var player: AVPlayer? = nil
    @State private var isPlaying: Bool = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isEditingSlider: Bool = false
    @State private var sliderValue: Double = 0
    
    // コントロール状態
    @State private var repeatMode: PlayerRepeatMode = .off
    @State private var isShuffle: Bool = false
    @State private var speedRate: Float = 1.0
    @State private var isControlsHidden: Bool = false
    @State private var showDeleteAlert: Bool = false
    
    // 長押し倍速再生状態 (押下中 2.0x 再生)
    @State private var isFastForwarding: Bool = false
    @State private var wasPlayingBeforeFastForward: Bool = false
    
    // 画面ジェスチャー状態 (左右ダブルタップ10秒移動)
    @State private var doubleTapFeedbackText: String? = nil
    @State private var feedbackTimer: Timer? = nil
    
    // ピンチズーム状態 (1.0~4.0倍, X軸ドラッグ許可 / Y軸縦移動固定)
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var lastDragOffset: CGSize = .zero
    
    // Observers
    @State private var timeObserverToken: Any? = nil
    @State private var endObserverNotification: NSObjectProtocol? = nil
    
    let availableSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    
    var currentItem: FileItem? {
        guard currentIndex >= 0 && currentIndex < videoPlaylist.count else { return nil }
        return videoPlaylist[currentIndex]
    }
    
    var body: some View {
        ZStack {
            CosmicTheme.spaceBlack.ignoresSafeArea()
            
            if let item = currentItem {
                VStack(spacing: 0) {
                    // MARK: - 1. 動画プレイヤー描画部 (ピンチズーム X軸移動/Y軸固定 & 左右ダブルタップ)
                    ZStack {
                        Color.black.ignoresSafeArea()
                        
                        if let player = player {
                            PinchableVideoView(
                                player: player,
                                scale: $scale,
                                lastScale: $lastScale,
                                dragOffset: $dragOffset,
                                lastDragOffset: $lastDragOffset,
                                onSeek10: { isForward in
                                    seekBy(isForward ? 10 : -10)
                                },
                                onToggleControls: {
                                    withAnimation { isControlsHidden.toggle() }
                                }
                            )
                        } else {
                            ProgressView()
                                .tint(CosmicTheme.nebulaCyan)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    
                    // MARK: - 2. コントロールエリア
                    if !isControlsHidden {
                        VStack(spacing: 12) {
                            // メタデータ表示部 (ゆったり自動スクロールタイトル ＋ 保存パス)
                            VStack(alignment: .leading, spacing: 2) {
                                MarqueeText(
                                    text: item.name,
                                    font: .system(size: 15, weight: .bold, design: .monospaced),
                                    color: CosmicTheme.starlightWhite
                                )
                                
                                Text("保存先: " + relativePathForDisplay(item.url))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(CosmicTheme.cosmicTextSub)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            
                            // 再生バー (シークバー - リアルタイム映像フレーム追従対応)
                            HStack(spacing: 12) {
                                Text(formatTime(isEditingSlider ? sliderValue : currentTime))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(CosmicTheme.nebulaCyan)
                                    .frame(width: 45, alignment: .leading)
                                
                                Slider(
                                    value: Binding(
                                        get: { isEditingSlider ? sliderValue : currentTime },
                                        set: { newValue in
                                            isEditingSlider = true
                                            sliderValue = newValue
                                            seek(to: newValue, isSmooth: true)
                                        }
                                    ),
                                    in: 0...max(0.1, duration),
                                    onEditingChanged: { editing in
                                        if !editing {
                                            seek(to: sliderValue, isSmooth: false)
                                            isEditingSlider = false
                                        }
                                    }
                                )
                                .tint(CosmicTheme.nebulaCyan)
                                
                                Text(formatTime(duration))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(CosmicTheme.cosmicTextSub)
                                    .frame(width: 45, alignment: .trailing)
                            }
                            .padding(.horizontal, 16)
                            
                            // 1列目ボタン群 (主力再生制御)
                            HStack(spacing: 18) {
                                // ⚡ 押してる間倍速再生ボタン (2.0x)
                                VStack(spacing: 1) {
                                    Image(systemName: "forward.fill")
                                        .font(.system(size: 13, weight: .bold))
                                    Text("2x")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                }
                                .foregroundColor(isFastForwarding ? CosmicTheme.nebulaCyan : CosmicTheme.starlightWhite)
                                .frame(width: 32, height: 32)
                                .background(isFastForwarding ? CosmicTheme.nebulaCyan.opacity(0.2) : Color.clear)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(isFastForwarding ? CosmicTheme.nebulaCyan : Color.clear, lineWidth: 1.5)
                                )
                                .scaleEffect(isFastForwarding ? 1.15 : 1.0)
                                .shadow(color: isFastForwarding ? CosmicTheme.nebulaCyan.opacity(0.8) : Color.clear, radius: 6)
                                .animation(.easeInOut(duration: 0.15), value: isFastForwarding)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { _ in
                                            if !isFastForwarding {
                                                startFastForward()
                                            }
                                        }
                                        .onEnded { _ in
                                            stopFastForward()
                                        }
                                )
                                
                                Button(action: playPreviousVideo) {
                                    Image(systemName: "backward.end.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(CosmicTheme.starlightWhite)
                                }
                                
                                Button(action: { seekBy(-10) }) {
                                    Image(systemName: "goforward.10")
                                        .font(.system(size: 20))
                                        .scaleEffect(x: -1, y: 1)
                                        .foregroundColor(CosmicTheme.nebulaCyan)
                                }
                                
                                Button(action: togglePlayPause) {
                                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 48))
                                        .foregroundColor(CosmicTheme.nebulaCyan)
                                        .shadow(color: CosmicTheme.nebulaCyan.opacity(0.6), radius: 8)
                                }
                                
                                Button(action: { seekBy(10) }) {
                                    Image(systemName: "goforward.10")
                                        .font(.system(size: 20))
                                        .foregroundColor(CosmicTheme.nebulaCyan)
                                }
                                
                                Button(action: playNextVideo) {
                                    Image(systemName: "forward.end.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(CosmicTheme.starlightWhite)
                                }
                                
                                // ⭐️ お気に入りボタン
                                if let item = currentItem {
                                    let fav = isFavorite(item)
                                    Button(action: { onToggleFavorite(item) }) {
                                        Image(systemName: fav ? "star.fill" : "star")
                                            .font(.system(size: 20))
                                            .foregroundColor(fav ? .yellow : CosmicTheme.cosmicTextSub)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            
                            // 2列目ボタン群 (戻る/クリップ/シャッフル/リピート/速度/削除)
                            HStack(spacing: 16) {
                                // 🔙 戻る
                                Button(action: { dismiss() }) {
                                    VStack(spacing: 2) {
                                        Image(systemName: "chevron.left.circle.fill")
                                            .font(.system(size: 18))
                                        Text("戻る").font(.system(size: 9, design: .monospaced))
                                    }
                                    .foregroundColor(CosmicTheme.nebulaCyan)
                                }
                                
                                Spacer()
                                
                                // 📌 クリップボタン (再生位置保存 / 解除)
                                if let item = currentItem {
                                    let relPath = FolderLockManager.shared.relativePath(for: item.url)
                                    let isClipped = ClippedPositionManager.getClippedTime(for: relPath) != nil
                                    Button(action: {
                                        if isClipped {
                                            ClippedPositionManager.removeClippedTime(for: relPath)
                                        } else {
                                            ClippedPositionManager.setClippedTime(for: relPath, time: currentTime)
                                        }
                                    }) {
                                        VStack(spacing: 2) {
                                            Image(systemName: isClipped ? "bookmark.fill" : "bookmark")
                                                .font(.system(size: 18))
                                            Text(isClipped ? "クリップ中" : "クリップ")
                                                .font(.system(size: 9, design: .monospaced))
                                        }
                                        .foregroundColor(isClipped ? CosmicTheme.nebulaCyan : CosmicTheme.cosmicTextSub)
                                    }
                                    
                                    Spacer()
                                }
                                
                                // 🔀 シャッフル
                                Button(action: { isShuffle.toggle() }) {
                                    VStack(spacing: 2) {
                                        Image(systemName: "shuffle")
                                            .font(.system(size: 18))
                                        Text(isShuffle ? "シャッフルON" : "シャッフル")
                                            .font(.system(size: 9, design: .monospaced))
                                    }
                                    .foregroundColor(isShuffle ? CosmicTheme.nebulaCyan : CosmicTheme.cosmicTextSub)
                                }
                                
                                Spacer()
                                
                                // 🔁 リピート
                                Button(action: toggleRepeatMode) {
                                    VStack(spacing: 2) {
                                        Image(systemName: repeatMode == .single ? "repeat.1" : "repeat")
                                            .font(.system(size: 18))
                                        Text(repeatMode.rawValue).font(.system(size: 9, design: .monospaced))
                                    }
                                    .foregroundColor(repeatMode != .off ? CosmicTheme.nebulaCyan : CosmicTheme.cosmicTextSub)
                                }
                                
                                Spacer()
                                
                                // ⚡ 再生速度
                                Button(action: cycleSpeedRate) {
                                    VStack(spacing: 2) {
                                        Image(systemName: "speedometer")
                                            .font(.system(size: 18))
                                        Text(String(format: "x%.2f", speedRate).replacingOccurrences(of: ".00", with: ".0"))
                                            .font(.system(size: 9, design: .monospaced))
                                    }
                                    .foregroundColor(speedRate != 1.0 ? CosmicTheme.nebulaCyan : CosmicTheme.cosmicTextSub)
                                }
                                .contextMenu {
                                    Text("再生速度を選択")
                                    Divider()
                                    ForEach(availableSpeeds, id: \.self) { speed in
                                        Button(String(format: "x%.2f", speed)) {
                                            setSpeedRate(speed)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                // 🗑️ ゴミ箱 (物理完全削除)
                                Button(action: { showDeleteAlert = true }) {
                                    VStack(spacing: 2) {
                                        Image(systemName: "trash.fill")
                                            .font(.system(size: 18))
                                        Text("削除").font(.system(size: 9, design: .monospaced))
                                    }
                                    .foregroundColor(CosmicTheme.singularityRed)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 4)
                            .padding(.bottom, 16)
                        }
                        .background(CosmicTheme.deepSpaceCard)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(CosmicTheme.singularityRed)
                    Text("再生可能な動画ファイルが存在しません")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(CosmicTheme.starlightWhite)
                    Button(action: { dismiss() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                            Text("画面を閉じて戻る")
                        }
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(CosmicTheme.starlightWhite)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(CosmicTheme.nebulaPurple)
                        .cornerRadius(10)
                    }
                }
            }
        }
        .statusBarHidden(true)
        .onAppear {
            setupAudioSession()
            setupVideoPlaylist()
            loadCurrentVideo()
            setupRemoteCommandCenter()
        }
        .onDisappear {
            cleanUpPlayer()
        }
        .alert("動画の物理削除", isPresented: $showDeleteAlert) {
            Button("キャンセル", role: .cancel) {}
            Button("削除する", role: .destructive) {
                deleteCurrentVideo()
            }
        } message: {
            Text("この動画ファイルをストレージから完全に削除します。この操作は取り消せません。")
        }
    }
    
    // MARK: - プレイヤー制御ロジック
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[CosmicVideoPlayer] AVAudioSession 設定エラー: \(error)")
        }
    }
    
    private func setupVideoPlaylist() {
        let videoExts = ["mp4", "mov", "m4v", "mkv", "avi", "webm", "3gp"]
        let videos = folderItems.filter { !$0.isDirectory && videoExts.contains($0.url.pathExtension.lowercased()) }
        
        self.videoPlaylist = videos.isEmpty ? [initialItem] : videos
        if let idx = self.videoPlaylist.firstIndex(where: { $0.url == initialItem.url }) {
            self.currentIndex = idx
        } else {
            self.currentIndex = 0
        }
    }
    
    private func loadCurrentVideo() {
        guard let item = currentItem else { return }
        
        cleanUpTimeObserver()
        
        let newPlayer: AVPlayer
        if let sharedP = PlaybackManager.shared.player, PlaybackManager.shared.currentItem?.url == item.url {
            newPlayer = sharedP
            self.isPlaying = PlaybackManager.shared.isPlaying
        } else {
            PlaybackManager.shared.stop()
            
            let playerItem = AVPlayerItem(url: item.url)
            newPlayer = AVPlayer(playerItem: playerItem)
            PlaybackManager.shared.player = newPlayer
            PlaybackManager.shared.currentItem = item
            PlaybackManager.shared.isVideo = true
            PlaybackManager.shared.isPlaying = true
            self.isPlaying = true
            
            let relPath = FolderLockManager.shared.relativePath(for: item.url)
            if let savedTime = ClippedPositionManager.getClippedTime(for: relPath), savedTime > 0 {
                newPlayer.seek(to: CMTime(seconds: savedTime, preferredTimescale: 600))
            }
        }
        
        self.player = newPlayer
        newPlayer.rate = isPlaying ? speedRate : 0.0
        if isPlaying { newPlayer.play() }
        
        timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { time in
            guard !isEditingSlider else { return }
            self.currentTime = time.seconds
            PlaybackManager.shared.currentTime = time.seconds
            PlaybackManager.shared.isPlaying = self.isPlaying
            if let dur = newPlayer.currentItem?.duration.seconds, !dur.isNaN && dur > 0 {
                self.duration = dur
                PlaybackManager.shared.duration = dur
            }
            self.updateNowPlayingInfo()
        }
        
        if let endObserver = endObserverNotification {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserverNotification = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newPlayer.currentItem,
            queue: .main
        ) { _ in
            self.handleVideoEnded()
        }
        
        scale = 1.0
        lastScale = 1.0
        dragOffset = .zero
        lastDragOffset = .zero
        
        updateNowPlayingInfo()
    }
    
    private func handleVideoEnded() {
        if isFastForwarding {
            isFastForwarding = false
        }
        switch repeatMode {
        case .single:
            seek(to: 0)
            player?.play()
        case .all:
            playNextVideo()
        case .off:
            if currentIndex < videoPlaylist.count - 1 {
                playNextVideo()
            } else {
                isPlaying = false
            }
        }
    }
    
    // MARK: - 押してる間倍速再生制御 (2.0x)
    private func startFastForward() {
        guard let p = player, !isFastForwarding else { return }
        isFastForwarding = true
        wasPlayingBeforeFastForward = isPlaying
        p.rate = 2.0
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    private func stopFastForward() {
        guard let p = player, isFastForwarding else { return }
        isFastForwarding = false
        if wasPlayingBeforeFastForward {
            p.rate = speedRate
            p.play()
            isPlaying = true
        } else {
            p.pause()
            isPlaying = false
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        updateNowPlayingInfo()
    }
    
    private func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.rate = speedRate
            player.play()
            isPlaying = true
        }
        updateNowPlayingInfo()
    }
    
    private func playNextVideo() {
        guard !videoPlaylist.isEmpty else { return }
        if isShuffle {
            let nextIdx = Int.random(in: 0..<videoPlaylist.count)
            currentIndex = nextIdx
        } else {
            if currentIndex < videoPlaylist.count - 1 {
                currentIndex += 1
            } else {
                currentIndex = 0
            }
        }
        loadCurrentVideo()
    }
    
    private func playPreviousVideo() {
        guard !videoPlaylist.isEmpty else { return }
        if currentTime > 3.0 {
            seek(to: 0)
        } else {
            if currentIndex > 0 {
                currentIndex -= 1
            } else {
                currentIndex = videoPlaylist.count - 1
            }
            loadCurrentVideo()
        }
    }
    
    private func seekBy(_ seconds: Double) {
        let target = max(0, min(duration, currentTime + seconds))
        seek(to: target)
    }
    
    private func seek(to seconds: Double, isSmooth: Bool = false) {
        let targetTime = CMTime(seconds: seconds, preferredTimescale: 600)
        let tolerance = isSmooth ? CMTime.positiveInfinity : .zero
        player?.seek(to: targetTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { _ in
            self.currentTime = seconds
            self.updateNowPlayingInfo()
        }
    }
    
    private func toggleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .single
        case .single: repeatMode = .all
        case .all: repeatMode = .off
        }
    }
    
    private func cycleSpeedRate() {
        let nextIndex = (availableSpeeds.firstIndex(of: speedRate) ?? 2) + 1
        speedRate = availableSpeeds[nextIndex % availableSpeeds.count]
        if isPlaying {
            player?.rate = speedRate
        }
    }
    
    private func setSpeedRate(_ speed: Float) {
        speedRate = speed
        if isPlaying {
            player?.rate = speedRate
        }
    }
    
    private func deleteCurrentVideo() {
        guard let item = currentItem else { return }
        
        onDelete(item)
        videoPlaylist.remove(at: currentIndex)
        
        if videoPlaylist.isEmpty {
            dismiss()
        } else {
            if currentIndex >= videoPlaylist.count {
                currentIndex = 0
            }
            loadCurrentVideo()
        }
    }
    
    private func cleanUpTimeObserver() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }
    
    private func cleanUpPlayer() {
        if isFastForwarding {
            isFastForwarding = false
        }
        cleanUpTimeObserver()
        if let endObs = endObserverNotification {
            NotificationCenter.default.removeObserver(endObs)
        }
    }
    
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { _ in
            self.player?.play()
            self.isPlaying = true
            return .success
        }
        commandCenter.pauseCommand.addTarget { _ in
            self.player?.pause()
            self.isPlaying = false
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { _ in
            self.togglePlayPause()
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { _ in
            self.playNextVideo()
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { _ in
            self.playPreviousVideo()
            return .success
        }
        commandCenter.skipForwardCommand.preferredIntervals = [10]
        commandCenter.skipForwardCommand.addTarget { _ in
            self.seekBy(10)
            return .success
        }
        commandCenter.skipBackwardCommand.preferredIntervals = [10]
        commandCenter.skipBackwardCommand.addTarget { _ in
            self.seekBy(-10)
            return .success
        }
    }
    
    private func updateNowPlayingInfo() {
        guard let item = currentItem else { return }
        
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = item.name
        nowPlayingInfo[MPMediaItemPropertyArtist] = "AltFiler"
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? speedRate : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func relativePathForDisplay(_ url: URL) -> String {
        let rel = FolderLockManager.shared.relativePath(for: url)
        return rel.isEmpty ? url.lastPathComponent : "/" + rel
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        let min = total / 60
        let sec = total % 60
        return String(format: "%02d:%02d", min, sec)
    }
}

// MARK: - Pinchable Video View (1.0~4.0倍, X軸ドラッグ許可 / Y軸縦移動固定 & 左右ダブルタップ10秒送り戻し)
struct PinchableVideoView: View {
    let player: AVPlayer
    
    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var dragOffset: CGSize
    @Binding var lastDragOffset: CGSize
    
    let onSeek10: (Bool) -> Void
    let onToggleControls: () -> Void
    
    var body: some View {
        GeometryReader { geo in
            PlayerCustomLayerView(player: player)
                .scaleEffect(scale)
                .offset(x: dragOffset.width, y: 0)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            let newScale = scale * delta
                            scale = min(max(newScale, 1.0), 4.0)
                        }
                        .onEnded { _ in
                            lastScale = 1.0
                            if scale <= 1.0 {
                                scale = 1.0
                                dragOffset = .zero
                                lastDragOffset = .zero
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1.0 else { return }
                            let newX = lastDragOffset.width + value.translation.width
                            let maxLimit = (geo.size.width * (scale - 1)) / 2
                            dragOffset.width = max(-maxLimit, min(maxLimit, newX))
                        }
                        .onEnded { _ in
                            lastDragOffset = dragOffset
                        }
                )
                .onTapGesture(count: 2) { location in
                    let isForward = location.x >= (geo.size.width / 2.0)
                    onSeek10(isForward)
                }
                .onTapGesture(count: 1) {
                    onToggleControls()
                }
        }
    }
}

// MARK: - Custom Video Player Layer View (純粋 AVPlayerLayer 描画 & 自動 PiP 対応)
struct PlayerCustomLayerView: UIViewRepresentable {
    let player: AVPlayer
    
    func makeUIView(context: Context) -> PlayerUIView {
        return PlayerUIView(player: player)
    }
    
    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.updatePlayer(player)
    }
    
    class PlayerUIView: UIView, AVPictureInPictureControllerDelegate {
        override static var layerClass: AnyClass {
            return AVPlayerLayer.self
        }
        
        var playerLayer: AVPlayerLayer {
            return layer as! AVPlayerLayer
        }
        
        private var pipController: AVPictureInPictureController?
        
        init(player: AVPlayer) {
            super.init(frame: .zero)
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspect
            backgroundColor = .black
            
            setupPiP()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func updatePlayer(_ newPlayer: AVPlayer) {
            if playerLayer.player !== newPlayer {
                playerLayer.player = newPlayer
                setupPiP()
            }
        }
        
        private func setupPiP() {
            guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
            pipController = nil
            if let pip = AVPictureInPictureController(playerLayer: playerLayer) {
                pip.delegate = self
                if #available(iOS 14.2, *) {
                    pip.canStartPictureInPictureAutomaticallyFromInline = true
                }
                pipController = pip
            }
        }
    }
}

// MARK: - AltFiler Audio File Info View (音声ファイル情報表示カード)
struct CosmicAudioFileInfoView: View {
    let item: FileItem?
    let duration: Double
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            
            VStack(spacing: 20) {
                // 音源アイコン
                ZStack {
                    Circle()
                        .fill(CosmicTheme.nebulaCyan.opacity(0.15))
                        .frame(width: 84, height: 84)
                    
                    Image(systemName: "music.note")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundColor(CosmicTheme.nebulaCyan)
                        .shadow(color: CosmicTheme.nebulaCyan.opacity(0.6), radius: 10)
                }
                
                // ファイル名 ＋ 音声拡張子名
                VStack(spacing: 6) {
                    Text(item?.name ?? "音声ファイル")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(CosmicTheme.starlightWhite)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 16)
                    
                    if let url = item?.url {
                        Text(url.lastPathComponent)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(CosmicTheme.cosmicTextSub)
                    }
                }
                
                Divider()
                    .background(CosmicTheme.nebulaCyan.opacity(0.3))
                    .padding(.horizontal, 24)
                
                // ファイルメタ情報 (フォーマット, 容量, 再生時間)
                HStack(spacing: 28) {
                    VStack(spacing: 4) {
                        Text("形式")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(CosmicTheme.cosmicTextSub)
                        Text(item?.url.pathExtension.uppercased() ?? "AUDIO")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(CosmicTheme.nebulaCyan)
                    }
                    
                    VStack(spacing: 4) {
                        Text("容量")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(CosmicTheme.cosmicTextSub)
                        Text(formatFileSize(item?.url))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(CosmicTheme.starlightWhite)
                    }
                    
                    VStack(spacing: 4) {
                        Text("総再生時間")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(CosmicTheme.cosmicTextSub)
                        Text(formatDuration(duration))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(CosmicTheme.nebulaPurple)
                    }
                }
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 20)
            .background(CosmicTheme.deepSpaceCard)
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(CosmicTheme.nebulaCyan.opacity(0.35), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            
            Spacer()
        }
    }
    
    private func formatFileSize(_ url: URL?) -> String {
        guard let url = url,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return "0 B" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    private func formatDuration(_ dur: Double) -> String {
        guard !dur.isNaN && dur > 0 else { return "--:--" }
        let m = Int(dur) / 60
        let s = Int(dur) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - AltFiler Audio Player Sheet (高機能音声再生)
struct CosmicAudioPlayerSheet: View {
    let initialItem: FileItem
    let folderItems: [FileItem]
    let isFavorite: (FileItem) -> Bool
    let onToggleFavorite: (FileItem) -> Void
    let onDelete: (FileItem) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var audioPlaylist: [FileItem] = []
    @State private var currentIndex: Int = 0
    
    @State private var player: AVPlayer? = nil
    @State private var isPlaying: Bool = true
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isEditingSlider: Bool = false
    @State private var sliderValue: Double = 0
    
    @State private var repeatMode: PlayerRepeatMode = .off
    @State private var isShuffle: Bool = false
    @State private var speedRate: Float = 1.0
    @State private var showDeleteAlert: Bool = false
    
    // 長押し倍速再生状態 (押下中 2.0x 再生)
    @State private var isFastForwarding: Bool = false
    @State private var wasPlayingBeforeFastForward: Bool = false
    
    @State private var timeObserverToken: Any? = nil
    @State private var endObserverNotification: NSObjectProtocol? = nil
    
    let availableSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    
    var currentItem: FileItem? {
        guard currentIndex >= 0 && currentIndex < audioPlaylist.count else { return nil }
        return audioPlaylist[currentIndex]
    }
    
    var body: some View {
        ZStack {
            CosmicTheme.spaceBlack.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // ヘッダー (戻る & タイトル)
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(CosmicTheme.nebulaCyan)
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 2) {
                        Text(currentItem?.name ?? "音声再生")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundColor(CosmicTheme.starlightWhite)
                            .lineLimit(1)
                        Text("AltFiler Audio Player")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(CosmicTheme.cosmicTextSub)
                    }
                    
                    Spacer()
                    
                    Color.clear.frame(width: 24, height: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                // メイン表示エリア（音声ファイル情報カードに統一）
                CosmicAudioFileInfoView(item: currentItem, duration: duration)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // 下部コントロールバー (プログレスシークバー & 操作ボタン)
                VStack(spacing: 12) {
                    // シークバー
                    HStack(spacing: 12) {
                        Text(formatTime(isEditingSlider ? sliderValue : currentTime))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(CosmicTheme.cosmicTextSub)
                            .frame(width: 45, alignment: .leading)
                        
                        Slider(
                            value: Binding(
                                get: { isEditingSlider ? sliderValue : currentTime },
                                set: { newValue in
                                    isEditingSlider = true
                                    sliderValue = newValue
                                    seek(to: newValue, isSmooth: true)
                                }
                            ),
                            in: 0...max(0.1, duration),
                            onEditingChanged: { editing in
                                if !editing {
                                    seek(to: sliderValue, isSmooth: false)
                                    isEditingSlider = false
                                }
                            }
                        )
                        .tint(CosmicTheme.nebulaCyan)
                        
                        Text(formatTime(duration))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(CosmicTheme.cosmicTextSub)
                            .frame(width: 45, alignment: .trailing)
                    }
                    .padding(.horizontal, 16)
                    
                    // 1列目ボタン群 (主力再生操作)
                    HStack(spacing: 18) {
                        // ⚡ 押してる間倍速再生ボタン (2.0x)
                        VStack(spacing: 1) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text("2x")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(isFastForwarding ? CosmicTheme.nebulaCyan : CosmicTheme.starlightWhite)
                        .frame(width: 32, height: 32)
                        .background(isFastForwarding ? CosmicTheme.nebulaCyan.opacity(0.2) : Color.clear)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(isFastForwarding ? CosmicTheme.nebulaCyan : Color.clear, lineWidth: 1.5)
                        )
                        .scaleEffect(isFastForwarding ? 1.15 : 1.0)
                        .shadow(color: isFastForwarding ? CosmicTheme.nebulaCyan.opacity(0.8) : Color.clear, radius: 6)
                        .animation(.easeInOut(duration: 0.15), value: isFastForwarding)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    if !isFastForwarding {
                                        startFastForward()
                                    }
                                }
                                .onEnded { _ in
                                    stopFastForward()
                                }
                        )
                        
                        Button(action: playPreviousAudio) {
                            Image(systemName: "backward.end.fill")
                                .font(.system(size: 20))
                                .foregroundColor(CosmicTheme.starlightWhite)
                        }
                        
                        Button(action: { seekBy(-10) }) {
                            Image(systemName: "goforward.10")
                                .font(.system(size: 20))
                                .scaleEffect(x: -1, y: 1)
                                .foregroundColor(CosmicTheme.nebulaCyan)
                        }
                        
                        Button(action: togglePlayPause) {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(CosmicTheme.nebulaCyan)
                                .shadow(color: CosmicTheme.nebulaCyan.opacity(0.6), radius: 8)
                        }
                        
                        Button(action: { seekBy(10) }) {
                            Image(systemName: "goforward.10")
                                .font(.system(size: 20))
                                .foregroundColor(CosmicTheme.nebulaCyan)
                        }
                        
                        Button(action: playNextAudio) {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 20))
                                .foregroundColor(CosmicTheme.starlightWhite)
                        }
                        
                        // ⭐️ お気に入りボタン
                        if let item = currentItem {
                            let fav = isFavorite(item)
                            Button(action: { onToggleFavorite(item) }) {
                                Image(systemName: fav ? "star.fill" : "star")
                                    .font(.system(size: 20))
                                    .foregroundColor(fav ? .yellow : CosmicTheme.cosmicTextSub)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // 2列目ボタン群 (戻る/クリップ/シャッフル/リピート/速度/削除)
                    HStack(spacing: 16) {
                        Button(action: { dismiss() }) {
                            VStack(spacing: 2) {
                                Image(systemName: "chevron.left.circle.fill")
                                    .font(.system(size: 18))
                                Text("戻る").font(.system(size: 9, design: .monospaced))
                            }
                            .foregroundColor(CosmicTheme.nebulaCyan)
                        }
                        
                        Spacer()
                        
                        // 📌 クリップボタン (再生位置保存 / 解除)
                        if let item = currentItem {
                            let relPath = FolderLockManager.shared.relativePath(for: item.url)
                            let isClipped = ClippedPositionManager.getClippedTime(for: relPath) != nil
                            Button(action: {
                                if isClipped {
                                    ClippedPositionManager.removeClippedTime(for: relPath)
                                } else {
                                    ClippedPositionManager.setClippedTime(for: relPath, time: currentTime)
                                }
                            }) {
                                VStack(spacing: 2) {
                                    Image(systemName: isClipped ? "bookmark.fill" : "bookmark")
                                        .font(.system(size: 18))
                                    Text(isClipped ? "クリップ中" : "クリップ")
                                        .font(.system(size: 9, design: .monospaced))
                                }
                                .foregroundColor(isClipped ? CosmicTheme.nebulaCyan : CosmicTheme.cosmicTextSub)
                            }
                            
                            Spacer()
                        }
                        
                        Button(action: { isShuffle.toggle() }) {
                            VStack(spacing: 2) {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 18))
                                Text(isShuffle ? "シャッフルON" : "シャッフル")
                                    .font(.system(size: 9, design: .monospaced))
                            }
                            .foregroundColor(isShuffle ? CosmicTheme.nebulaCyan : CosmicTheme.cosmicTextSub)
                        }
                        
                        Spacer()
                        
                        Button(action: toggleRepeatMode) {
                            VStack(spacing: 2) {
                                Image(systemName: "repeat")
                                    .font(.system(size: 18))
                                Text(repeatMode.rawValue).font(.system(size: 9, design: .monospaced))
                            }
                            .foregroundColor(repeatMode != .off ? CosmicTheme.nebulaCyan : CosmicTheme.cosmicTextSub)
                        }
                        
                        Spacer()
                        
                        Button(action: cycleSpeedRate) {
                            VStack(spacing: 2) {
                                Image(systemName: "speedometer")
                                    .font(.system(size: 18))
                                Text(String(format: "x%.2f", speedRate).replacingOccurrences(of: ".00", with: ".0"))
                                    .font(.system(size: 9, design: .monospaced))
                            }
                            .foregroundColor(speedRate != 1.0 ? CosmicTheme.nebulaCyan : CosmicTheme.cosmicTextSub)
                        }
                        .contextMenu {
                            Text("再生速度を選択")
                            Divider()
                            ForEach(availableSpeeds, id: \.self) { speed in
                                Button(String(format: "x%.2f", speed)) {
                                    setSpeedRate(speed)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: { showDeleteAlert = true }) {
                            VStack(spacing: 2) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 18))
                                Text("削除").font(.system(size: 9, design: .monospaced))
                            }
                            .foregroundColor(CosmicTheme.singularityRed)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
                .background(CosmicTheme.deepSpaceCard)
            }
        }
        .statusBarHidden(true)
        .onAppear {
            setupAudioSession()
            setupAudioPlaylist()
            loadCurrentAudio()
            setupRemoteTransportControls()
        }
        .onDisappear {
            cleanUpPlayer()
        }
        .alert("音声ファイルの物理削除", isPresented: $showDeleteAlert) {
            Button("キャンセル", role: .cancel) {}
            Button("削除する", role: .destructive) {
                deleteCurrentAudio()
            }
        } message: {
            Text("この音声ファイルをストレージから完全に削除します。この操作は取り消せません。")
        }
    }
    
    // MARK: - ロック画面・コントロールセンター制御
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            self.togglePlayPause()
            return .success
        }
        
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            self.togglePlayPause()
            return .success
        }
        
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { _ in
            self.playNextAudio()
            return .success
        }
        
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { _ in
            self.playPreviousAudio()
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            if let posEvent = event as? MPChangePlaybackPositionCommandEvent {
                self.seek(to: posEvent.positionTime, isSmooth: false)
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.skipBackwardCommand.preferredIntervals = [10]
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.addTarget { event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10.0
            self.seekBy(-interval)
            return .success
        }
        
        commandCenter.skipForwardCommand.preferredIntervals = [10]
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.addTarget { event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10.0
            self.seekBy(interval)
            return .success
        }
    }
    
    private func updateNowPlayingInfo() {
        guard let item = currentItem else { return }
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = item.name
        info[MPMediaItemPropertyArtist] = "AltFiler"
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? speedRate : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    // MARK: - 音声制御ロジック
    
    private func toggleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .single
        case .single: repeatMode = .all
        case .all: repeatMode = .off
        }
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[CosmicAudioPlayer] AudioSession 設定エラー: \(error)")
        }
    }
    
    private func setupAudioPlaylist() {
        let audioExts = ["mp3", "m4a", "wav", "aac", "flac", "aiff", "alac", "ogg"]
        let audios = folderItems.filter { item in
            !item.isDirectory && audioExts.contains(item.url.pathExtension.lowercased())
        }
        
        self.audioPlaylist = audios.isEmpty ? [initialItem] : audios
        if let idx = self.audioPlaylist.firstIndex(where: { $0.url == initialItem.url }) {
            self.currentIndex = idx
        } else {
            self.currentIndex = 0
        }
    }
    
    private func loadCurrentAudio() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let observer = endObserverNotification {
            NotificationCenter.default.removeObserver(observer)
            endObserverNotification = nil
        }
        
        guard let item = currentItem else { return }
        
        let newPlayer: AVPlayer
        if let sharedP = PlaybackManager.shared.player, PlaybackManager.shared.currentItem?.url == item.url {
            newPlayer = sharedP
            self.isPlaying = PlaybackManager.shared.isPlaying
        } else {
            PlaybackManager.shared.stop()
            
            let playerItem = AVPlayerItem(url: item.url)
            newPlayer = AVPlayer(playerItem: playerItem)
            PlaybackManager.shared.player = newPlayer
            PlaybackManager.shared.currentItem = item
            PlaybackManager.shared.isVideo = false
            PlaybackManager.shared.isPlaying = true
            self.isPlaying = true
            
            let relPath = FolderLockManager.shared.relativePath(for: item.url)
            if let savedTime = ClippedPositionManager.getClippedTime(for: relPath), savedTime > 0 {
                newPlayer.seek(to: CMTime(seconds: savedTime, preferredTimescale: 600))
            }
        }
        
        self.player = newPlayer
        
        let interval = CMTime(seconds: 0.1, preferredTimescale: 60)
        timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !isEditingSlider else { return }
            self.currentTime = time.seconds
            PlaybackManager.shared.currentTime = time.seconds
            PlaybackManager.shared.isPlaying = self.isPlaying
            if let dur = newPlayer.currentItem?.duration.seconds, !dur.isNaN && dur > 0 {
                self.duration = dur
                PlaybackManager.shared.duration = dur
            }
            self.updateNowPlayingInfo()
        }
        
        endObserverNotification = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newPlayer.currentItem,
            queue: .main
        ) { _ in
            handleAudioPlaybackEnded()
        }
        
        if isPlaying {
            newPlayer.play()
            newPlayer.rate = speedRate
        }
        
        updateNowPlayingInfo()
    }
    
    private func handleAudioPlaybackEnded() {
        if isFastForwarding {
            isFastForwarding = false
        }
        switch repeatMode {
        case .single:
            seek(to: 0, isSmooth: false)
            player?.play()
            player?.rate = speedRate
        case .all:
            playNextAudio()
        case .off:
            if currentIndex < audioPlaylist.count - 1 {
                playNextAudio()
            } else {
                isPlaying = false
                seek(to: 0, isSmooth: false)
            }
        }
    }
    
    // MARK: - 押してる間倍速再生制御 (2.0x)
    private func startFastForward() {
        guard let p = player, !isFastForwarding else { return }
        isFastForwarding = true
        wasPlayingBeforeFastForward = isPlaying
        p.rate = 2.0
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    private func stopFastForward() {
        guard let p = player, isFastForwarding else { return }
        isFastForwarding = false
        if wasPlayingBeforeFastForward {
            p.rate = speedRate
            p.play()
            isPlaying = true
        } else {
            p.pause()
            isPlaying = false
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        updateNowPlayingInfo()
    }
    
    private func playNextAudio() {
        guard !audioPlaylist.isEmpty else { return }
        if isShuffle {
            let nextIdx = Int.random(in: 0..<audioPlaylist.count)
            currentIndex = nextIdx
        } else {
            if currentIndex < audioPlaylist.count - 1 {
                currentIndex += 1
            } else {
                currentIndex = 0
            }
        }
        loadCurrentAudio()
    }
    
    private func playPreviousAudio() {
        guard !audioPlaylist.isEmpty else { return }
        if currentTime > 3.0 {
            seek(to: 0, isSmooth: false)
        } else {
            if currentIndex > 0 {
                currentIndex -= 1
            } else {
                currentIndex = audioPlaylist.count - 1
            }
            loadCurrentAudio()
        }
    }
    
    private func togglePlayPause() {
        isPlaying.toggle()
        if isPlaying {
            player?.play()
            player?.rate = speedRate
        } else {
            player?.pause()
        }
        updateNowPlayingInfo()
    }
    
    private func seekBy(_ seconds: Double) {
        let newTime = min(max(0, currentTime + seconds), duration)
        seek(to: newTime, isSmooth: false)
    }
    
    private func seek(to time: Double, isSmooth: Bool) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 60)
        if isSmooth {
            player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player?.seek(to: cmTime)
        }
        self.currentTime = time
        updateNowPlayingInfo()
    }
    
    private func cycleSpeedRate() {
        if speedRate == 1.0 { speedRate = 1.25 }
        else if speedRate == 1.25 { speedRate = 1.5 }
        else if speedRate == 1.5 { speedRate = 2.0 }
        else if speedRate == 2.0 { speedRate = 0.5 }
        else { speedRate = 1.0 }
        
        if isPlaying {
            player?.rate = speedRate
        }
    }
    
    private func setSpeedRate(_ rate: Float) {
        self.speedRate = rate
        if isPlaying {
            player?.rate = rate
        }
    }
    
    private func deleteCurrentAudio() {
        guard let item = currentItem else { return }
        cleanUpPlayer()
        onDelete(item)
        audioPlaylist.remove(at: currentIndex)
        
        if audioPlaylist.isEmpty {
            dismiss()
        } else {
            if currentIndex >= audioPlaylist.count {
                currentIndex = audioPlaylist.count - 1
            }
            loadCurrentAudio()
        }
    }
    
    private func cleanUpPlayer() {
        if isFastForwarding {
            isFastForwarding = false
        }
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let observer = endObserverNotification {
            NotificationCenter.default.removeObserver(observer)
            endObserverNotification = nil
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        let min = total / 60
        let sec = total % 60
        return String(format: "%02d:%02d", min, sec)
    }
}

// MARK: - クリップ機能（再生位置保存・復元マネージャー）
struct ClippedPositionManager {
    static let key = "AltFiler_ClippedPositions"
    
    static func getClippedTime(for relPath: String) -> Double? {
        let dict = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        return dict[relPath]
    }
    
    static func setClippedTime(for relPath: String, time: Double) {
        var dict = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        dict[relPath] = time
        UserDefaults.standard.set(dict, forKey: key)
    }
    
    static func removeClippedTime(for relPath: String) {
        var dict = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        dict.removeValue(forKey: relPath)
        UserDefaults.standard.set(dict, forKey: key)
    }
}

// MARK: - グローバル再生マネージャー (バックグラウンド再生 & ミニプレーヤー同期)
final class PlaybackManager: NSObject, ObservableObject {
    static let shared = PlaybackManager()
    
    @Published var currentItem: FileItem? = nil
    @Published var player: AVPlayer? = nil
    @Published var isPlaying: Bool = false
    @Published var isVideo: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    
    @Published var showFullScreenVideo: Bool = false
    @Published var showFullScreenAudio: Bool = false
    
    private var timeObserverToken: Any?
    
    private override init() {
        super.init()
        setupAudioSession()
    }
    
    func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[PlaybackManager] AudioSession 設定エラー: \(error)")
        }
    }
    
    func togglePlayPause() {
        guard let p = player else { return }
        if isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            isPlaying = true
        }
    }
    
    func stop() {
        player?.pause()
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player = nil
        currentItem = nil
        isPlaying = false
        showFullScreenVideo = false
        showFullScreenAudio = false
    }
}

