import SwiftUI
import LocalAuthentication

// MARK: - 1. 初回起動オンボーディング（使い方ガイド）シート

struct OnboardingSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0
    var onComplete: () -> Void
    
    private struct OnboardingSlide: Identifiable {
        let id = UUID()
        let badge: String
        let title: String
        let subtitle: String
        let iconName: String
        let accentColors: [Color]
        let highlights: [(icon: String, text: String)]
    }
    
    private let slides: [OnboardingSlide] = [
        OnboardingSlide(
            badge: "INDEPENDENT STORAGE",
            title: "iOS標準とは別環境の\n完全独立ファイル管理",
            subtitle: "標準の「ファイル」や「写真」アプリの一覧に混ぜたくない大切なデータを、独立したローカル領域で安全に整理・保管できます。",
            iconName: "folder.fill.badge.gearshape",
            accentColors: [.cyan, .blue],
            highlights: [
                ("lock.shield.fill", "第三者に悟られない「ステルス仕様のフォルダロック」"),
                ("faceid", "Face ID / Touch ID ＆ Keychain (SHA-256) 暗号化保護"),
                ("eye.slash.fill", "マルチタスク画面での覗き見を防ぐプライバシーシールド")
            ]
        ),
        OnboardingSlide(
            badge: "PRO MEDIA PLAYER",
            title: "動画・音声・画像を\n妥協なく快適再生",
            subtitle: "単なる保管庫にとどまらず、取り込んだメディアを標準アプリ以上に快適に楽しめるオールインワンプレイヤーを搭載しています。",
            iconName: "play.rectangle.on.rectangle.fill",
            accentColors: [.blue, .purple],
            highlights: [
                ("forward.fill", "長押し中だけ2.0倍速再生・左右ダブルタップ10秒スキップ"),
                ("arrow.up.left.and.arrow.down.right", "動画のピンチズーム拡大（最大4.0倍）＆自由なパン移動"),
                ("bookmark.fill", "見たい瞬間を記憶する「クリップ機能」＆ PiP・バックグラウンド再生")
            ]
        ),
        OnboardingSlide(
            badge: "SEAMLESS WORKFLOW",
            title: "簡単インポート＆\nZIP圧縮・解凍に完全対応",
            subtitle: "写真ライブラリ・ファイル選択・他アプリの共有シートからの取り込みに加え、ZIPアーカイブの圧縮と解凍もこれ1つで完結します。",
            iconName: "doc.zipper",
            accentColors: [.teal, .cyan],
            highlights: [
                ("square.and.arrow.down.on.square.fill", "写真・動画・書類・他アプリの「共有」から一括インポート"),
                ("archivebox.fill", "ファイルやフォルダのZIP圧縮＆タップ1つで即座にZIP解凍"),
                ("checkmark.seal.fill", "外部通信ゼロ・100%オフライン完結の安心設計")
            ]
        )
    ]
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.06, blue: 0.14),
                    Color(red: 0.02, green: 0.03, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .foregroundStyle(.cyan)
                        Text("AltFiler")
                            .font(.system(.subheadline, design: .rounded).weight(.black))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Button {
                        onComplete()
                        dismiss()
                    } label: {
                        Text("スキップ")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                TabView(selection: $currentPage) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                        VStack(spacing: 22) {
                            Spacer(minLength: 8)
                            
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: slide.accentColors.map { $0.opacity(0.25) },
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 116, height: 116)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(
                                                LinearGradient(colors: slide.accentColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                                                lineWidth: 1.5
                                            )
                                    )
                                    .shadow(color: slide.accentColors.first?.opacity(0.4) ?? .cyan.opacity(0.4), radius: 20)
                                
                                Image(systemName: slide.iconName)
                                    .font(.system(size: 46, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(colors: [.white, slide.accentColors.first ?? .cyan], startPoint: .top, endPoint: .bottom)
                                    )
                            }
                            
                            VStack(spacing: 10) {
                                Text(slide.badge)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .tracking(2)
                                    .foregroundStyle(.cyan)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.cyan.opacity(0.14)))
                                
                                Text(slide.title)
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(4)
                                
                                Text(slide.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.72))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 12)
                                    .lineSpacing(3)
                            }
                            
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(slide.highlights.enumerated()), id: \.offset) { _, item in
                                    HStack(spacing: 12) {
                                        Image(systemName: item.icon)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(.cyan)
                                            .frame(width: 32, height: 32)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .fill(Color.cyan.opacity(0.14))
                                            )
                                        Text(item.text)
                                            .font(.footnote.weight(.medium))
                                            .foregroundStyle(.white.opacity(0.92))
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                            .padding(18)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            )
                            .padding(.horizontal, 24)
                            
                            Spacer(minLength: 16)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // ページインジケーター＆次へボタン
                VStack(spacing: 18) {
                    HStack(spacing: 8) {
                        ForEach(0..<slides.count, id: \.self) { idx in
                            Capsule()
                                .fill(idx == currentPage ? Color.cyan : Color.white.opacity(0.25))
                                .frame(width: idx == currentPage ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.3), value: currentPage)
                        }
                    }
                    
                    Button {
                        if currentPage < slides.count - 1 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                currentPage += 1
                            }
                        } else {
                            onComplete()
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(currentPage < slides.count - 1 ? "次へ進む" : "AltFiler をはじめる")
                                .font(.headline.weight(.bold))
                            Image(systemName: currentPage < slides.count - 1 ? "arrow.right" : "checkmark.circle.fill")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.cyan, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .shadow(color: .cyan.opacity(0.35), radius: 12, y: 4)
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 28)
            }
        }
    }
}

// MARK: - 2. 設定・アプリ情報画面 (SettingsSheetView)

struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var lockManager: FolderLockManager
    @ObservedObject var fileManager: LocalFileManager
    let appVersion: String
    var onShowOnboarding: () -> Void
    
    @State private var isShowingPasswordSheet = false
    @State private var isShowingPrivacyPolicy = false
    @State private var isShowingTermsOfUse = false
    @State private var cachePurgeDoneToast = false
    @State private var pendingEnableAppLock = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.05, blue: 0.12)
                    .ignoresSafeArea()
                
                List {
                    // セクション1: セキュリティとプライバシー保護
                    Section {
                        Button {
                            pendingEnableAppLock = false
                            isShowingPasswordSheet = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: lockManager.isMasterPasswordConfigured ? "key.fill" : "key.slash")
                                    .foregroundStyle(.cyan)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lockManager.isMasterPasswordConfigured ? "マスターパスワードを変更" : "マスターパスワードを設定")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Text(lockManager.isMasterPasswordConfigured ? "Keychain (SHA-256) で安全に保護されています" : "フォルダロックや起動ロックに必要です")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                                Spacer()
                                Text(lockManager.isMasterPasswordConfigured ? "設定済" : "未設定")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(lockManager.isMasterPasswordConfigured ? .green : .orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule().fill((lockManager.isMasterPasswordConfigured ? Color.green : Color.orange).opacity(0.15))
                                    )
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        }
                        
                        Toggle(isOn: Binding(
                            get: { lockManager.isAppLockEnabled },
                            set: { newValue in
                                if newValue && !lockManager.hasMasterPassword {
                                    pendingEnableAppLock = true
                                    isShowingPasswordSheet = true
                                } else {
                                    lockManager.isAppLockEnabled = newValue
                                }
                            }
                        )) {
                            HStack(spacing: 12) {
                                Image(systemName: "lock.iphone")
                                    .foregroundStyle(.cyan)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("アプリ起動時ロック")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.white)
                                    Text("起動時・バックグラウンド復帰時に認証を要求します")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            }
                        }
                        .tint(.cyan)
                        
                        Toggle(isOn: $lockManager.isBiometricsEnabled) {
                            HStack(spacing: 12) {
                                Image(systemName: lockManager.biometricIconName)
                                    .foregroundStyle(.cyan)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(lockManager.biometricTypeName) でロック解除")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.white)
                                    Text("フォルダ解錠や起動ロックで生体認証を使用します")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            }
                        }
                        .tint(.cyan)
                        
                        Toggle(isOn: $lockManager.isPrivacyShieldEnabled) {
                            HStack(spacing: 12) {
                                Image(systemName: "eye.slash.circle.fill")
                                    .foregroundStyle(.cyan)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("バックグラウンド覗き見防止")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.white)
                                    Text("マルチタスク画面で画面内容を即座にブラー保護します")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            }
                        }
                        .tint(.cyan)
                    } header: {
                        Text("セキュリティ・プライバシー")
                            .foregroundStyle(.cyan)
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                    
                    // セクション2: ストレージ使用状況
                    Section {
                        HStack {
                            Label("アプリ使用容量", systemImage: "internaldrive.fill")
                                .foregroundStyle(.white)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: fileManager.appStorageBytes, countStyle: .file))
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.cyan)
                        }
                        
                        HStack {
                            Label("デバイスの空き容量", systemImage: "externaldrive.fill.badge.checkmark")
                                .foregroundStyle(.white)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: fileManager.freeDiskSpaceBytes, countStyle: .file))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        
                        HStack {
                            Label("管理アイテム数", systemImage: "doc.on.doc.fill")
                                .foregroundStyle(.white)
                            Spacer()
                            Text("フォルダ \(fileManager.totalFolderCount) 個 / ファイル \(fileManager.totalFileCount) 個")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        
                        Button {
                            fileManager.purgeTemporaryDirectory()
                            fileManager.refreshStorageInfo()
                            withAnimation {
                                cachePurgeDoneToast = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation {
                                    cachePurgeDoneToast = false
                                }
                            }
                        } label: {
                            HStack {
                                Label("一時キャッシュをクリーンアップ", systemImage: "sparkles")
                                    .foregroundStyle(.cyan)
                                Spacer()
                                if cachePurgeDoneToast {
                                    Text("完了しました")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    } header: {
                        Text("独立ローカルストレージ")
                            .foregroundStyle(.cyan)
                    } footer: {
                        Text("すべてのファイルは iOS 標準の「ファイル」や「写真」アプリから独立したアプリ専用領域（AltFilerStorage）内で100%ローカル管理されます。")
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                    
                    // セクション3: ガイドと法的情報
                    Section {
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onShowOnboarding()
                            }
                        } label: {
                            HStack {
                                Label("使い方ガイド（オンボーディング）を表示", systemImage: "book.pages.fill")
                                    .foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        }
                        
                        Button {
                            isShowingPrivacyPolicy = true
                        } label: {
                            HStack {
                                Label("プライバシーポリシー", systemImage: "hand.raised.fill")
                                    .foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        }
                        
                        Button {
                            isShowingTermsOfUse = true
                        } label: {
                            HStack {
                                Label("利用規約・免責事項", systemImage: "doc.text.fill")
                                    .foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        }
                    } header: {
                        Text("サポート・規約")
                            .foregroundStyle(.cyan)
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                    
                    // セクション4: アプリ情報
                    Section {
                        HStack {
                            Text("アプリ名")
                                .foregroundStyle(.white)
                            Spacer()
                            Text("AltFiler")
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        HStack {
                            Text("バージョン")
                                .foregroundStyle(.white)
                            Spacer()
                            Text(appVersion)
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.cyan)
                        }
                        HStack {
                            Text("動作モード")
                                .foregroundStyle(.white)
                            Spacer()
                            Text("100% ローカル完結 (外部通信なし)")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    } header: {
                        Text("アプリ情報")
                            .foregroundStyle(.cyan)
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("設定・アプリ情報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.cyan)
                }
            }
            .sheet(isPresented: $isShowingPasswordSheet) {
                MasterPasswordChangeSheet(
                    lockManager: lockManager,
                    onPasswordSaved: {
                        if pendingEnableAppLock {
                            lockManager.isAppLockEnabled = true
                            pendingEnableAppLock = false
                        }
                    }
                )
            }
            .sheet(isPresented: $isShowingPrivacyPolicy) {
                LegalDocumentSheetView(
                    title: "プライバシーポリシー",
                    sections: LegalDocumentContent.privacyPolicySections
                )
            }
            .sheet(isPresented: $isShowingTermsOfUse) {
                LegalDocumentSheetView(
                    title: "利用規約・免責事項",
                    sections: LegalDocumentContent.termsSections
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - 3. マスターパスワード設定・変更シート（現在パスワードまたは生体認証による本人確認必須）

struct MasterPasswordChangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var lockManager: FolderLockManager
    var onPasswordSaved: (() -> Void)? = nil
    
    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var verifiedByBiometrics: Bool = false
    @State private var errorMessage: String? = nil
    
    private var isChangingExisting: Bool {
        lockManager.hasMasterPassword
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.05, blue: 0.12)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        Image(systemName: "key.shield.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.cyan)
                            .padding(.top, 12)
                        
                        Text(isChangingExisting ? "マスターパスワードの変更" : "マスターパスワードの新規設定")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        
                        Text("設定されたパスワードは SHA-256 でハッシュ化され、iOS Keychain のセキュア領域にのみ保存されます。")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        
                        if isChangingExisting {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("1. 本人確認")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.cyan)
                                
                                if verifiedByBiometrics {
                                    HStack(spacing: 8) {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundStyle(.green)
                                        Text("\(lockManager.biometricTypeName) で本人確認済み")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.green)
                                        Spacer()
                                    }
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.12)))
                                } else {
                                    SecureField("現在のパスワードを入力", text: $currentPassword)
                                        .padding(12)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                                        .foregroundStyle(.white)
                                    
                                    if lockManager.isBiometricsEnabled && lockManager.isBiometricsAvailable {
                                        Button {
                                            lockManager.authenticateWithBiometrics(reason: "マスターパスワードを変更するために本人確認を行います") { success in
                                                if success {
                                                    verifiedByBiometrics = true
                                                    errorMessage = nil
                                                }
                                            }
                                        } label: {
                                            HStack {
                                                Image(systemName: lockManager.biometricIconName)
                                                Text("\(lockManager.biometricTypeName) で本人確認する")
                                            }
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(.cyan)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.cyan.opacity(0.5), lineWidth: 1))
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text(isChangingExisting ? "2. 新しいパスワード" : "新しいパスワード")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.cyan)
                            
                            SecureField("新しいパスワードを入力", text: $newPassword)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                                .foregroundStyle(.white)
                            
                            SecureField("新しいパスワード（確認用）", text: $confirmPassword)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 20)
                        
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 20)
                        }
                        
                        Button {
                            savePassword()
                        } label: {
                            Text("パスワードを保存")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    .padding(.bottom, 28)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func savePassword() {
        let trimmedNew = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNew.isEmpty else {
            errorMessage = "新しいパスワードを入力してください。"
            return
        }
        guard trimmedNew == confirmPassword.trimmingCharacters(in: .whitespacesAndNewlines) else {
            errorMessage = "確認用パスワードが一致しません。"
            return
        }
        
        if isChangingExisting {
            let success = lockManager.changeMasterPassword(
                currentPassword: currentPassword,
                authenticatedByBiometrics: verifiedByBiometrics,
                newPassword: trimmedNew
            )
            if !success {
                errorMessage = "現在のパスワードが正しくありません。"
                return
            }
        } else {
            lockManager.setMasterPassword(trimmedNew)
        }
        
        onPasswordSaved?()
        dismiss()
    }
}

// MARK: - 4. アプリ起動ロック画面 (AppLockOverlayView)

struct AppLockOverlayView: View {
    @ObservedObject var lockManager: FolderLockManager
    @State private var passwordInput: String = ""
    @State private var showError: Bool = false
    @State private var hasTriggeredAutoBiometrics: Bool = false
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.04, blue: 0.11),
                    Color(red: 0.01, green: 0.02, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.14))
                        .frame(width: 96, height: 96)
                        .overlay(
                            Circle().strokeBorder(Color.cyan.opacity(0.45), lineWidth: 1.5)
                        )
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(.cyan)
                }
                
                VStack(spacing: 6) {
                    Text("AltFiler ロック中")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text("続行するには認証を行ってください")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                }
                
                VStack(spacing: 14) {
                    SecureField("マスターパスワードを入力", text: $passwordInput)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(showError ? Color.red : Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .foregroundStyle(.white)
                        .submitLabel(.go)
                        .onSubmit {
                            attemptPasswordUnlock()
                        }
                    
                    if showError {
                        Text("パスワードが正しくありません")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                    
                    Button {
                        attemptPasswordUnlock()
                    } label: {
                        Text("ロックを解除")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                    }
                    
                    if lockManager.isBiometricsEnabled && lockManager.isBiometricsAvailable {
                        Button {
                            triggerBiometrics()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: lockManager.biometricIconName)
                                Text("\(lockManager.biometricTypeName) でロック解除")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.cyan)
                            .padding(.vertical, 10)
                        }
                    }
                }
                .frame(maxWidth: 320)
                .padding(.horizontal, 24)
                
                Spacer()
            }
        }
        .onAppear {
            if !hasTriggeredAutoBiometrics && lockManager.isBiometricsEnabled {
                hasTriggeredAutoBiometrics = true
                triggerBiometrics()
            }
        }
    }
    
    private func attemptPasswordUnlock() {
        if lockManager.verifyPassword(passwordInput) {
            passwordInput = ""
            showError = false
            withAnimation(.easeOut(duration: 0.2)) {
                lockManager.unlockAppForSession()
            }
        } else {
            showError = true
        }
    }
    
    private func triggerBiometrics() {
        lockManager.authenticateWithBiometrics(reason: "AltFiler のロックを解除します") { success in
            if success {
                passwordInput = ""
                showError = false
                withAnimation(.easeOut(duration: 0.2)) {
                    lockManager.unlockAppForSession()
                }
            }
        }
    }
}

// MARK: - 5. バックグラウンド覗き見防止シールド (PrivacyShieldOverlayView)

struct PrivacyShieldOverlayView: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            Color(red: 0.03, green: 0.04, blue: 0.10).opacity(0.88)
                .ignoresSafeArea()
            
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.25), Color.blue.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 84, height: 84)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(Color.cyan.opacity(0.5), lineWidth: 1.5)
                        )
                    
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(.cyan)
                }
                
                Text("AltFiler")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("プライバシー保護中")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - 6. プライバシーポリシー＆利用規約ビュー

struct LegalSectionItem: Identifiable {
    let id = UUID()
    let heading: String
    let bodyText: String
}

enum LegalDocumentContent {
    static let privacyPolicySections: [LegalSectionItem] = [
        LegalSectionItem(
            heading: "1. 基本方針（100%ローカル完結）",
            bodyText: "「AltFiler」（以下「本アプリ」）は、ユーザーのプライバシー保護を最優先に設計されています。本アプリ内で取り込まれたすべてのファイル、フォルダ構造、ブックマーク、クリップ設定、および認証情報は、お客様のデバイス（iPhone / iPad）内の独立したローカルストレージおよび iOS Keychain 内にのみ保存され、外部サーバーへ送信・収集されることは一切ありません。"
        ),
        LegalSectionItem(
            heading: "2. 個人情報の収集・外部送信について",
            bodyText: "本アプリは、外部の分析ツール、広告SDK、クラウド送信APIを一切含んでいません。氏名、メールアドレス、端末識別子、閲覧履歴、検索履歴、メディア再生履歴などの個人データや利用状況データを開発者または第三者へ送信することはありません。"
        ),
        LegalSectionItem(
            heading: "3. 生体認証（Face ID / Touch ID）およびパスワード保護",
            bodyText: "本アプリのロック機能で使用するマスターパスワードは、iOS標準の CryptoKit（SHA-256）により不可逆ハッシュ化された上で iOS Keychain に安全に格納されます。また、Face ID / Touch ID による生体認証は Apple 標準の LocalAuthentication フレームワークを介してOSレベルで処理され、本アプリが生体データそのものにアクセス・保存することはありません。"
        ),
        LegalSectionItem(
            heading: "4. 写真ライブラリ・ファイルへのアクセス権限",
            bodyText: "ユーザーが明示的に「写真から追加」または「ファイルから追加」を選択した場合に限り、選択されたメディアや書類を本アプリ内へコピーするためにのみアクセスします。"
        )
    ]
    
    static let termsSections: [LegalSectionItem] = [
        LegalSectionItem(
            heading: "1. 本アプリのご利用にあたって",
            bodyText: "AltFiler は、お客様の端末内で独立してファイルを整理・再生するためのローカルファイル管理＆メディアプレイヤーアプリです。"
        ),
        LegalSectionItem(
            heading: "2. データの管理とバックアップに関するご注意",
            bodyText: "本アプリは高いプライバシー性を維持するため、外部クラウドへの自動アップロードや「ごみ箱」フォルダを設けていません。アプリ内で削除したファイルや、アプリ自体を端末からアンインストールした場合のデータは復元できませんので、重要なデータは必要に応じて「共有・書き出し」機能等でお客様ご自身にてバックアップを行ってください。"
        ),
        LegalSectionItem(
            heading: "3. パスワードの管理について",
            bodyText: "セキュリティ保護の厳格化のため、マスターパスワードのバックドアや無条件リセット機能は搭載しておりません。設定されたマスターパスワードをお忘れにならないようご注意ください。"
        ),
        LegalSectionItem(
            heading: "4. 免責事項",
            bodyText: "本アプリの利用または利用不能により生じたいかなる損害（データの消失等を含む）についても、法令上の責任が認められる場合を除き、開発者は一切の責任を負いかねます。"
        )
    ]
}

struct LegalDocumentSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let sections: [LegalSectionItem]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.05, blue: 0.12)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.heading)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.cyan)
                                Text(section.bodyText)
                                    .font(.footnote)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineSpacing(4)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.05))
                            )
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .foregroundStyle(.cyan)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

