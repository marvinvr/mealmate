import SwiftUI

// The share extension's UI ("Import to Mealie" from Safari and other apps).
// Compiled into both targets: MealMateShare hosts it in a UIHostingController,
// the app renders it for the DEBUG `share-preview/<state>` routes. Keep it
// free of app-only code (AppRouter, AppSession, ...).

/// State of one share-sheet import.
@MainActor
@Observable
final class ShareImportModel {
    enum Phase: Equatable {
        /// Reading the shared item.
        case loading
        /// Nothing that looks like a web link was shared.
        case noLink
        /// MealMate isn't signed in on this device.
        case signedOut
        case ready
        case importing
        case duplicate(RecipeSummary)
        case imported(name: String, slug: String)
        case failed(RecipeImportProblem)
    }

    private(set) var phase: Phase = .loading
    private(set) var url: URL?
    /// Server host shown as the import target, e.g. "mealie.example.com".
    let serverHost: String?

    @ObservationIgnored private let service: MealieService?

    /// `service == nil` means signed out.
    init(service: MealieService?) {
        self.service = service
        self.serverHost = service.map { $0.baseURL.host() ?? $0.baseURL.absoluteString }
    }

    /// Model using the credentials the app stored in the App Group + shared Keychain.
    static func fromStoredCredentials() -> ShareImportModel {
        let service = CredentialStore.load().map { MealieService(baseURL: $0.serverURL, token: $0.token) }
        return ShareImportModel(service: service)
    }

    /// Called once the shared item has been read.
    func setSharedURL(_ url: URL?) {
        self.url = url
        if service == nil {
            phase = .signedOut
        } else {
            phase = url == nil ? .noLink : .ready
        }
    }

    func importRecipe(allowDuplicate: Bool = false) async {
        guard let service, let url else { return }
        if case .importing = phase { return }
        phase = .importing
        let importer = RecipeImporter(service: service)
        if !allowDuplicate, let existing = await importer.existingRecipe(importedFrom: url) {
            phase = .duplicate(existing)
            return
        }
        do {
            let recipe = try await importer.importRecipe(from: url, includeOrganizers: ImportPreferences.includeOrganizers)
            phase = .imported(name: recipe.displayName, slug: recipe.slug)
        } catch let problem as RecipeImportProblem {
            phase = .failed(problem)
        } catch {
            phase = .failed(RecipeImportProblem(MealieError.wrap(error)))
        }
    }

    /// Deep link that opens a recipe in the app.
    nonisolated static func appURL(forRecipe slug: String) -> URL? {
        URL(string: "mealmate://recipe/\(slug.pathSegment)")
    }

    nonisolated static let appURL = URL(string: "mealmate://recipes")!

    #if DEBUG
    func debugShow(_ phase: Phase, url: URL?) {
        self.url = url
        self.phase = phase
    }
    #endif
}

/// Share sheet content. `onOpenApp` opens a `mealmate://` URL and closes the
/// extension; `onClose` just closes it.
struct ShareImportView: View {
    @Bindable var model: ShareImportModel
    var onClose: () -> Void
    var onOpenApp: (URL) -> Void

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .screenBackground()
                .navigationTitle("Import to Mealie")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if isFinished {
                            Button("Done", systemImage: "checkmark", action: onClose)
                        } else {
                            Button("Cancel", systemImage: "xmark", action: onClose)
                        }
                    }
                }
        }
        .animation(.smooth, value: model.phase)
        .sensoryFeedback(.success, trigger: model.phase) { _, new in
            if case .imported = new { return true }
            return false
        }
        .sensoryFeedback(.error, trigger: model.phase) { _, new in
            if case .failed = new { return true }
            return false
        }
    }

    private var isFinished: Bool {
        if case .imported = model.phase { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .noLink:
            ContentUnavailableView {
                Label("No Link Found", systemImage: "link")
            } description: {
                Text("Share a recipe page from Safari or another app, and MealMate imports it into Mealie.")
            }
        case .signedOut:
            ContentUnavailableView {
                Label("Sign In to MealMate First", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("Open MealMate and connect it to your Mealie server, then share this page again.")
            } actions: {
                Button("Open MealMate") { onOpenApp(ShareImportModel.appURL) }
                    .buttonStyle(.bordered)
            }
        case .ready:
            ready
        case .importing:
            ImportProgressView(source: model.url?.host() ?? "the page")
        case .duplicate(let existing):
            ContentUnavailableView {
                Label("Already in Your Recipes", systemImage: "book.closed")
            } description: {
                Text("You imported this page before as \(Text(existing.displayName).bold()).")
            } actions: {
                if let url = ShareImportModel.appURL(forRecipe: existing.slug) {
                    Button { onOpenApp(url) } label: {
                        Text("Open in MealMate").font(.body.weight(.semibold))
                    }
                    .primaryActionStyle()
                    .controlSize(.large)
                }
                Button("Import a Copy") { Task { await model.importRecipe(allowDuplicate: true) } }
                    .buttonStyle(.bordered)
                    .tint(.primary)
            }
        case .imported(let name, let slug):
            ContentUnavailableView {
                Label {
                    Text("Imported “\(name)”")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            } description: {
                Text("It’s in your recipes on \(model.serverHost ?? "your server").")
            } actions: {
                if let url = ShareImportModel.appURL(forRecipe: slug) {
                    Button { onOpenApp(url) } label: {
                        Text("Open in MealMate").font(.body.weight(.semibold))
                    }
                    .primaryActionStyle()
                    .controlSize(.large)
                }
            }
        case .failed(let problem):
            ContentUnavailableView {
                Label(problem.title, systemImage: problem.kind == .serverUnreachable ? "wifi.exclamationmark" : "exclamationmark.triangle")
            } description: {
                Text(problem.message)
            } actions: {
                Button("Try Again") { Task { await model.importRecipe() } }
                    .buttonStyle(.bordered)
                    .tint(.primary)
            }
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if let url = model.url {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    Image(systemName: "safari")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(url.host() ?? "Web page")
                            .font(.headline)
                        Text(url.absoluteString)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .truncationMode(.middle)
                    }
                }
                .surfaceCard()
                .accessibilityElement(children: .combine)
            }
            Label {
                Text("Saves to **\(model.serverHost ?? "your server")**")
            } icon: {
                Image(systemName: "server.rack")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button {
                Task { await model.importRecipe() }
            } label: {
                Text("Import to Mealie")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .primaryActionStyle()
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.xs)
    }
}

/// Spinner + what's happening; imports usually take a few seconds.
struct ImportProgressView: View {
    let source: String

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ProgressView()
                .controlSize(.large)
            VStack(spacing: Theme.Spacing.xxs) {
                Text("Importing Recipe")
                    .font(.title3.weight(.semibold))
                Text(source == "AI" ? "Your server’s AI is reading the recipe." : "Mealie is reading \(source).")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text("This can take a few seconds.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Inline explanation of a failed import.
struct ImportProblemRow: View {
    let problem: RecipeImportProblem

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(problem.title)
                    .font(.headline)
                Text(problem.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: problem.kind == .serverUnreachable ? "wifi.exclamationmark" : "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .padding(.vertical, Theme.Spacing.xxs)
    }
}

