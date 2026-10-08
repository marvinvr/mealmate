import SwiftUI

/// Sheets for the create/import routes (deep links and DEBUG `-MealMateRoute`):
///
/// | Route | Opens |
/// | --- | --- |
/// | `import`, `import/<url>` | Import sheet (URL prefilled, not started) |
/// | `import-run/<url>` | Import sheet that starts importing right away (DEBUG; real write) |
/// | `import-state/<importing\|failed\|unavailable\|duplicate\|ai>` | Import sheet in a fixed state (DEBUG) |
/// | `editor-new` | New recipe editor (DEBUG `editor-new/autosave`: scripted create + save) |
/// | `editor-edit/<slug>`, `editor-edit/<slug>/<section>` | Editor for an existing recipe (DEBUG: scrolled to ingredients/steps/notes/organize, `tags`/`categories` picker, `autosave` scripted edit + save) |
/// | `share-preview/<ready\|importing\|imported\|duplicate\|failed\|signedout\|nolink>` | Share extension UI (DEBUG) |
/// | `share-preview/live/<url>` | Share extension UI for a real URL (DEBUG; imports for real) |
///
/// The routes leave a `create:` intent in `AppRouter.pendingIntent`; this
/// modifier (attached once in `MainTabView`) presents the matching sheet.
enum CreateFlowSheet: Identifiable, Equatable {
    /// `autoStart`: DEBUG `import-run/<url>` starts the import right away (real write).
    case importRecipe(url: String?, autoStart: Bool = false)
    /// `debug`: DEBUG action (`autosave`), see `RecipeEditorView(debugAction:)`.
    case newRecipe(debug: String? = nil)
    /// `section`: DEBUG scroll target (see `RecipeEditorView(slug:scrollTo:)`).
    case editRecipe(slug: String, section: String? = nil)
    #if DEBUG
    case importState(ImportRecipeView.DebugState)
    case sharePreview(SharePreviewView.Scenario?, liveURL: URL?)
    #endif

    var id: String {
        switch self {
        case .importRecipe(let url, let autoStart): "import-\(url ?? "")-\(autoStart)"
        case .newRecipe(let debug): "editor-new-\(debug ?? "")"
        case .editRecipe(let slug, let section): "editor-\(slug)-\(section ?? "")"
        #if DEBUG
        case .importState(let state): "import-state-\(state.rawValue)"
        case .sharePreview(let state, let url): "share-\(state?.rawValue ?? "live")-\(url?.absoluteString ?? "")"
        #endif
        }
    }

    static let intentPrefix = "create:"

    /// Parses a `create:` intent (see `AppRoute.registry`).
    init?(intent: String) {
        guard intent.hasPrefix(Self.intentPrefix) else { return nil }
        let parts = intent.dropFirst(Self.intentPrefix.count).split(separator: "/", maxSplits: 1).map(String.init)
        let argument = parts.count > 1 ? parts[1] : nil
        switch parts.first {
        case "import": self = .importRecipe(url: argument)
        case "editor-new": self = .newRecipe(debug: argument)
        case "editor-edit":
            guard let argument else { return nil }
            let pieces = argument.split(separator: "/", maxSplits: 1).map(String.init)
            self = .editRecipe(slug: pieces[0], section: pieces.count > 1 ? pieces[1] : nil)
        #if DEBUG
        case "import-run": self = .importRecipe(url: argument, autoStart: true)
        case "import-state":
            guard let state = argument.flatMap(ImportRecipeView.DebugState.init(rawValue:)) else { return nil }
            self = .importState(state)
        case "share-preview":
            if let argument, argument.hasPrefix("live/") {
                self = .sharePreview(nil, liveURL: URL(string: String(argument.dropFirst("live/".count))))
            } else {
                guard let state = argument.flatMap(SharePreviewView.Scenario.init(rawValue:)) else { return nil }
                self = .sharePreview(state, liveURL: nil)
            }
        #endif
        default: return nil
        }
    }
}

extension View {
    /// Presents `CreateFlowSheet`s requested through `create:` route intents.
    func createFlowRouteSheets() -> some View {
        modifier(CreateFlowRouteSheets())
    }
}

private struct CreateFlowRouteSheets: ViewModifier {
    @Environment(AppRouter.self) private var router
    @State private var sheet: CreateFlowSheet?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: consume)
            .onChange(of: router.pendingIntent) { consume() }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .importRecipe(let url, let autoStart):
                    #if DEBUG
                    ImportRecipeView(initialURL: url, debugAutoStart: autoStart)
                    #else
                    ImportRecipeView(initialURL: url)
                    #endif
                case .newRecipe(let debug):
                    #if DEBUG
                    RecipeEditorView(debugAction: debug)
                    #else
                    RecipeEditorView()
                    #endif
                case .editRecipe(let slug, let section):
                    #if DEBUG
                    RecipeEditorView(slug: slug, scrollTo: section)
                    #else
                    RecipeEditorView(slug: slug)
                    #endif
                #if DEBUG
                case .importState(let state): ImportRecipeView(debugState: state)
                case .sharePreview(let state, let url): SharePreviewView(state: state, liveURL: url)
                #endif
                }
            }
    }

    private func consume() {
        guard let intent = router.consumeIntent(CreateFlowSheet.intentPrefix) else { return }
        sheet = CreateFlowSheet(intent: intent)
    }
}
