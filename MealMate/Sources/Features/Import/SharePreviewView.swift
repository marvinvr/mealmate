#if DEBUG
import SwiftUI

/// DEBUG: renders the share extension's UI inside the app so its states can be
/// screenshotted (`share-preview/<state>` and `share-preview/live/<url>` routes).
/// The share extension itself can only be opened from a share sheet.
struct SharePreviewView: View {
    enum Scenario: String, CaseIterable, Sendable {
        case ready, importing, imported, duplicate, failed, signedout, nolink
    }

    /// Fixed state, or `nil` for a live preview of `liveURL` (imports for real).
    let state: Scenario?
    var liveURL: URL?

    @Environment(\.mealie) private var mealie
    @Environment(\.dismiss) private var dismiss
    @State private var model: ShareImportModel?

    var body: some View {
        Group {
            if let model {
                ShareImportView(model: model, onClose: { dismiss() }, onOpenApp: { url in
                    dismiss()
                    UIApplication.shared.open(url)
                })
            } else {
                Color.clear // an empty Group never runs `.task`
            }
        }
        .task {
            guard model == nil else { return }
            let sampleURL = URL(string: "https://www.example.com/recipes/lemon-herb-chicken")!
            let model = ShareImportModel(service: state == .signedout ? nil : mealie)
            switch state {
            case nil:
                model.setSharedURL(liveURL)
            case .ready:
                model.setSharedURL(sampleURL)
            case .importing:
                model.debugShow(.importing, url: sampleURL)
            case .imported:
                model.debugShow(.imported(name: "Lemon Herb Chicken", slug: "lemon-herb-chicken"), url: sampleURL)
            case .duplicate:
                model.debugShow(.duplicate(RecipeSummary(id: "00000000-0000-4000-8000-000000000001", slug: "lemon-herb-chicken", name: "Lemon Herb Chicken")), url: sampleURL)
            case .failed:
                model.debugShow(.failed(RecipeImportProblem(.server(status: 400, message: "BAD_RECIPE_DATA"))), url: sampleURL)
            case .signedout:
                model.setSharedURL(sampleURL)
            case .nolink:
                model.setSharedURL(nil)
            }
            self.model = model
        }
    }
}
#endif
