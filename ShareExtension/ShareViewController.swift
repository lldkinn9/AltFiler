import UIKit
import Social
import UniformTypeIdentifiers

/// 他アプリ（写真・Safari・ファイル等）の共有シートから AltFiler へ直接ファイルを取り込む Share Extension
class ShareViewController: UIViewController {
    
    /// メインアプリの Bundle Identifier から動的に App Group ID (`group.<MainBundleID>`) を解決（個人IDハードコード完全排除）
    private var resolvedAppGroupId: String {
        if let customGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String, !customGroup.isEmpty {
            return customGroup
        }
        if let bundleId = Bundle.main.bundleIdentifier {
            var components = bundleId.components(separatedBy: ".")
            if Bundle.main.bundleURL.pathExtension == "appex", components.count > 1 {
                components.removeLast()
            }
            return "group." + components.joined(separator: ".")
        }
        return "group.app.altfiler"
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        handleSharedItems()
    }
    
    private func handleSharedItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            completeRequest()
            return
        }
        
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: resolvedAppGroupId) else {
            completeRequest()
            return
        }
        
        let pendingDir = containerURL.appendingPathComponent("PendingImports", isDirectory: true)
        if !FileManager.default.fileExists(atPath: pendingDir.path) {
            try? FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)
        }
        
        let dispatchGroup = DispatchGroup()
        
        for item in extensionItems {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                let targetType = UTType.item.identifier
                if provider.hasItemConformingToTypeIdentifier(targetType) {
                    dispatchGroup.enter()
                    provider.loadFileRepresentation(forTypeIdentifier: targetType) { url, _ in
                        defer { dispatchGroup.leave() }
                        guard let sourceURL = url else { return }
                        
                        let fileName = sourceURL.lastPathComponent
                        let destURL = pendingDir.appendingPathComponent("\(UUID().uuidString)_\(fileName)")
                        try? FileManager.default.copyItem(at: sourceURL, to: destURL)
                    }
                }
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            self.completeRequest()
        }
    }
    
    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}

