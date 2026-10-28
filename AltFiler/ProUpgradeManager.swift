import SwiftUI
import StoreKit
import Combine

/// StoreKit 2（Apple公式 App Store アプリ内課金）による「広告非表示（AltFiler Pro）」管理＆広告バナーモッククラス
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
    
    /// 開発・デザイン確認用：バナー広告モックの表示ON/OFF（デフォルトON）
    @Published public var isAdBannerMockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAdBannerMockEnabled, forKey: showAdMockKey)
        }
    }
    
    /// App Store から取得した製品情報
    @Published public private(set) var proProduct: Product? = nil
    @Published public private(set) var isPurchasing: Bool = false
    @Published public var statusMessage: String? = nil
    
    /// 現在メイン画面に広告バナーを表示すべきか
    public var shouldDisplayAdBanner: Bool {
        !isProUnlocked && isAdBannerMockEnabled
    }
    
    private init() {
        self.isProUnlocked = UserDefaults.standard.bool(forKey: proUnlockedKey)
        self.isAdBannerMockEnabled = UserDefaults.standard.object(forKey: showAdMockKey) as? Bool ?? true
        
        Task {
            await refreshPurchasedStatus()
            await fetchProducts()
        }
    }
    
    // MARK: - StoreKit 2 公式決済・購入ステータス確認（Apple規約 3.1.1 完全準拠）
    
    /// App Store から製品情報（価格・名称）を取得
    public func fetchProducts() async {
        do {
            let products = try await Product.products(for: [proProductID])
            self.proProduct = products.first
        } catch {
            print("[ProUpgradeManager] 製品情報取得スキップ（未登録またはオフライン）: \(error)")
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
        
        // App Store Connect 上で製品登録前のシミュレータ動作確認時はモック購入として即時反映
        guard let product = proProduct else {
            withAnimation {
                self.isProUnlocked = true
                self.statusMessage = "✨ AltFiler Pro（広告非表示）を有効化しました（プレビュー動作）"
            }
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
    
    /// 表示用の価格テキスト（App Store 未接続時は参考価格 ¥300 を表示）
    public var displayPrice: String {
        proProduct?.displayPrice ?? "¥300"
    }
}

// MARK: - メイン画面下部の標準バナー広告モックビュー (320x50pt 相当)

struct AdBannerSlotView: View {
    var onTapRemoveAds: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            // AD バッジ（Apple / AdMob 規約準拠の広告明示ラベル）
            Text("AD")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.18))
                )
            
            // バナー広告モック本体（50pt高）
            HStack(spacing: 10) {
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
                    Text("広告バナー表示エリア（高さ 50pt モック）")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                    Text("無料版ではここにバナー広告が表示されます")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                
                Spacer(minLength: 4)
                
                // 右端：広告を消す（Pro版案内）ショートカットボタン
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
    }
}
