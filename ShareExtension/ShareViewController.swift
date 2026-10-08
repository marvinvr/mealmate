import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Entry point of the MealMate share extension: "Import to Mealie" for a web
/// page shared from Safari (or text containing a link from any app).
///
/// Reads the first web URL from the extension items, then hosts
/// `ShareImportView` (shared with the app, see `Features/Import`). Credentials
/// come from the App Group + shared Keychain group the app writes on sign-in.
final class ShareViewController: UIViewController {
    private lazy var model = ShareImportModel.fromStoredCredentials()

    override func viewDidLoad() {
        super.viewDidLoad()
        let root = ShareImportView(
            model: model,
            onClose: { [weak self] in self?.close() },
            onOpenApp: { [weak self] url in self?.openApp(url) }
        )
        // Extensions don't pick up the app's global accent; set Rosemary explicitly.
        .tint(Color("AccentColor"))
        let host = UIHostingController(rootView: root)
        host.view.tintColor = UIColor(named: "AccentColor")
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)

        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        let model = self.model
        Task { @MainActor in
            model.setSharedURL(await Self.firstWebURL(in: providers))
        }
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Opens `mealmate://…` in the app. Share extensions have no public API for
    /// this, so it walks the responder chain to the hosting `UIApplication` and
    /// calls `open(_:options:completionHandler:)` through the runtime.
    private func openApp(_ url: URL) {
        let selector = sel_registerName("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication, application.responds(to: selector) {
                typealias OpenURL = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let open = unsafeBitCast(application.method(for: selector), to: OpenURL.self)
                open(application, selector, url as NSURL, NSDictionary(), nil)
                break
            }
            responder = current.next
        }
        close()
    }

    /// First http(s) URL among the shared items: a URL attachment (Safari) wins,
    /// otherwise the first link found in shared text.
    private static func firstWebURL(in providers: [NSItemProvider]) async -> URL? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
               let web = RecipeURLExtractor.webURL(url) {
                return web
            }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
            let text = (item as? String) ?? (item as? URL)?.absoluteString
                ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
            if let text, let url = RecipeURLExtractor.firstWebURL(in: text) {
                return url
            }
        }
        return nil
    }
}
