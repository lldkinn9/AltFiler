import SwiftUI
import StoreKit
import Combine
import AppTrackingTransparency
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

/// StoreKit 2（Apple公式 App Store アプリ内課金）による「広告非表示（AltFiler Pro）」管理＆AdMobバナー制御クラス
@MainActor
public final class ProUpgradeManager: ObservableObject {
    public static let shared = ProUpgradeManager()
    
    /// App Store Connect で登録する非消耗型（買い切り）課金アイテムの製品ID
    public let proProductID = "com.lldkinn9.AltFiler.pro"
    
    private let proUnlockedKey = "AltFiler_IsProUnlocked"
    private let showAdMockKey = "AltFiler_ShowAdMockPreview"
    
    /// Pro版（広告非表示）が有効化されているか
    @Published public var isProUnlocked: Bool {
        didSet {
            UserDefaults.standard.set(isProUnlocked, forKey: proUnlockedKey)
        }
    }
    
    /// 開発・デザイン確認用：バナー広告の表示ON/OFF（DEBUGビルドのみ設定画面に表示）
    @Published public var isAdBannerMockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAdBannerMockEnabled, forKey: showAdMockKey)
        }
    }
    
    /// App Store から取得した製品情報
    @Published public private(set) var proProduct: Product? = nil
    @Published public private(set) var isPurchasing: Bool = false
    @Published public var statusMessage: String? = nil
    @Published public private(set) var isAdSDKInitialized: Bool = false
    
    private var transactionListenerTask: Task<Void, Never>? = nil
    
    /// 現在メイン画面に広告バナーを表示すべきか
    public var shouldDisplayAdBanner: Bool {
        #if DEBUG
        return !isProUnlocked && isAdBannerMockEnabled
        #else
        return !isProUnlocked
        #endif
    }
    
    /// Info.plist から広告ユニットIDを動的に解決（ハードコード防止・DEBUG時はGoogle公式テストIDを使用）
    public var resolvedBannerAdUnitID: String {
        #if DEBUG
        // Google AdMob 公式のiOSバナーテスト専用ID（開発中の自己クリック規約違反を防ぐため必須）
        return "ca-app-pub-3940256099942544/2435281174"
        #else
        if let plistID = Bundle.main.object(forInfoDictionaryKey: "AdMobBannerUnitID") as? String,
           !plistID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plistID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
        #endif
    }
    
    private init() {
        self.isProUnlocked = UserDefaults.standard.bool(forKey: proUnlockedKey)
        self.isAdBannerMockEnabled = UserDefaults.standard.object(forKey: showAdMockKey) as? Bool ?? true
        
        // StoreKit 2 トランザクション監視タスク開始
        self.transactionListenerTask = listenForTransactions()
        
        Task {
            await refreshPurchasedStatus()
            await fetchProducts()
        }
    }
    
    deinit {
        transactionListenerTask?.cancel()
    }
    
    // MARK: - ATT (App Tracking Transparency) ＆ AdMob SDK 初期化
    
    /// オンボーディング完了後、無料版利用時のみ ATT 許可リクエストおよび AdMob 初期化を実行
    public func requestTrackingAndStartAdsIfNeeded() {
        guard !isProUnlocked else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
                ATTrackingManager.requestTrackingAuthorization { _ in
                    Task { @MainActor in
                        self.initializeAdSDKIfNeeded()
                    }
                }
            } else {
                self.initializeAdSDKIfNeeded()
            }
        }
    }
    
    private func initializeAdSDKIfNeeded() {
        guard !isAdSDKInitialized, !isProUnlocked else { return }
        isAdSDKInitialized = true
        #if canImport(GoogleMobileAds)
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        #endif
    }
    
    // MARK: - StoreKit 2 公式決済・購入ステータス確認（Apple規約 3.1.1 完全準拠）
    
    /// バックグラウンドでの決済更新・ファミリー共有や別端末からの購入をリアルタイム監視
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    if transaction.productID == "com.lldkinn9.AltFiler.pro" && transaction.revocationDate == nil {
                        await MainActor.run {
                            ProUpgradeManager.shared.isProUnlocked = true
                        }
                    }
                    await transaction.finish()
                }
            }
        }
    }
    
    /// App Store から製品情報（価格・名称）を取得
    public func fetchProducts() async {
        do {
            let products = try await Product.products(for: [proProductID])
            self.proProduct = products.first
        } catch {
            print("[ProUpgradeManager] 製品情報取得スキップ: \(error)")
        }
    }
    
    /// 購入済みトランザクションの検証
    public func refreshPurchasedStatus() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == proProductID,
               transaction.revocationDate == nil {
                self.isProUnlocked = true
                return
            }
        }
    }
    
    /// App Store アプリ内課金（買い切り）の購入実行
    public func purchasePro() async {
        isPurchasing = true
        defer { isPurchasing = false }
        
        if proProduct == nil {
            await fetchProducts()
        }
        
        guard let product = proProduct else {
            #if DEBUG
            withAnimation {
                self.isProUnlocked = true
                self.statusMessage = "✨ AltFiler Pro（広告非表示）を有効化しました（DEBUGプレビュー）"
            }
            #else
            self.statusMessage = "App Store から製品情報を取得できませんでした。通信環境をご確認の上、再度お試しください。"
            #endif
            return
        }
        
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    withAnimation {
                        self.isProUnlocked = true
                        self.statusMessage = "✨ ご購入ありがとうございます！広告が完全に非表示になりました。"
                    }
                } else {
                    self.statusMessage = "購入情報の検証に失敗しました。"
                }
            case .userCancelled:
                break
            case .pending:
                self.statusMessage = "決済の承認待ちです。"
            @unknown default:
                break
            }
        } catch {
            self.statusMessage = "購入処理に失敗しました: \(error.localizedDescription)"
        }
    }
    
    /// 購入の復元（Apple審査 Guideline 3.1.1 必須機能）
    public func restorePurchases() async {
        isPurchasing = true
        defer { isPurchasing = false }
        
        do {
            try await AppStore.sync()
            await refreshPurchasedStatus()
            if isProUnlocked {
                self.statusMessage = "✅ 購入履歴を復元し、広告を非表示にしました。"
            } else {
                self.statusMessage = "復元可能な購入履歴が見つかりませんでした。"
            }
        } catch {
            self.statusMessage = "購入の復元に失敗しました: \(error.localizedDescription)"
        }
    }
    
    /// 表示用の価格テキスト（App Store 取得前は設定価格 ¥500 を表示）
    public var displayPrice: String {
        proProduct?.displayPrice ?? "¥500"
    }
}

// MARK: - Google AdMob 実バナー View (GoogleMobileAds 導入時に自動有効化)

#if canImport(GoogleMobileAds)
struct AdMobBannerRepresentable: UIViewRepresentable {
    let adUnitID: String
    
    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeBanner)
        banner.adUnitID = adUnitID
        banner.backgroundColor = .clear
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            banner.rootViewController = rootVC
        }
        banner.load(GADRequest())
        return banner
    }
    
    func updateUIView(_ uiView: GADBannerView, context: Context) {}
}
#endif

// MARK: - メイン画面下部のバナー広告スロットビュー (高さ 50pt)

struct AdBannerSlotView: View {
    @ObservedObject private var proManager = ProUpgradeManager.shared
    var onTapRemoveAds: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            #if canImport(GoogleMobileAds)
            if !proManager.resolvedBannerAdUnitID.isEmpty {
                AdMobBannerRepresentable(adUnitID: proManager.resolvedBannerAdUnitID)
                    .frame(width: 320, height: 50)
                
                Spacer(minLength: 0)
                
                Button(action: onTapRemoveAds) {
                    VStack(spacing: 2) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                        Text("広告消去")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.cyan.opacity(0.15))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.45), lineWidth: 1))
                    )
                }
            } else {
                mockBannerContent
            }
            #else
            mockBannerContent
            #endif
        }
        .frame(height: 50)
        .padding(.horizontal, 12)
        .background(
            Color(red: 0.06, green: 0.08, blue: 0.16)
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.white.opacity(0.08)),
            alignment: .top
        )
        .onAppear {
            proManager.requestTrackingAndStartAdsIfNeeded()
        }
    }
    
    private var mockBannerContent: some View {
        HStack(spacing: 10) {
            Text("AD")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.18))
                )
            
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.35), Color.blue.opacity(0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.cyan)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("AdMob バナー広告枠 (320×50)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                Text("SDK追加後に実広告へ自動切替されます")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            
            Spacer(minLength: 4)
            
            Button(action: onTapRemoveAds) {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                    Text("広告を消す")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.cyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.cyan.opacity(0.15))
                        .overlay(Capsule().stroke(Color.cyan.opacity(0.5), lineWidth: 1))
                )
            }
        }
    }
}
