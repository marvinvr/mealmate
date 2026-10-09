import SwiftUI

/// Public links for one recipe (Mealie share tokens): anyone with the link can view the
/// recipe on the server's web UI without an account, until the link expires.
struct RecipePublicLinkSheet: View {
    let recipe: Recipe

    @Environment(\.mealie) private var mealie
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var model: RecipePublicLinkModel?
    @State private var expiry: PublicLinkExpiry = .month
    @State private var shareItem: PublicLinkShareItem?
    @State private var copiedID: String?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .screenBackground()
            .navigationTitle("Public Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
                .presentationDetents([.medium, .large])
        }
        .task {
            if model == nil { model = RecipePublicLinkModel(recipeID: recipe.id, mealie: mealie) }
            await model?.load()
        }
    }

    private func content(_ model: RecipePublicLinkModel) -> some View {
        List {
            if !model.links.isEmpty {
                Section {
                    ForEach(model.links) { token in
                        linkRow(token, model: model)
                    }
                } header: {
                    Text("Active Links")
                }
            }

            Section {
                Picker("Expires", selection: $expiry) {
                    ForEach(PublicLinkExpiry.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Button {
                    Task {
                        if let token = await model.create(expiresAt: expiry.date(from: Date())),
                           let url = url(for: token) {
                            shareItem = PublicLinkShareItem(url: url)
                        }
                    }
                } label: {
                    HStack {
                        Label("Create and Share Link", systemImage: "link.badge.plus")
                        Spacer()
                        if model.isCreating { ProgressView() }
                    }
                }
                .disabled(model.isCreating || session.currentUser?.groupSlug == nil)
            } footer: {
                if let error = model.error {
                    Text(error).foregroundStyle(.red)
                } else {
                    Text("Anyone with the link can view this recipe in a browser, without signing in, until the link expires.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await model.load() }
        .sensoryFeedback(.success, trigger: model.links.count) { old, new in new > old }
        .sensoryFeedback(.error, trigger: model.error) { _, new in new != nil }
    }

    @ViewBuilder
    private func linkRow(_ token: RecipeShareToken, model: RecipePublicLinkModel) -> some View {
        let url = url(for: token)
        HStack(spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(expiryText(token))
                if let created = token.createdAt {
                    Text("Created \(created.formatted(date: .abbreviated, time: .omitted))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let url {
                Button {
                    UIPasteboard.general.url = url
                    copiedID = token.id
                } label: {
                    Image(systemName: copiedID == token.id ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(copiedID == token.id ? "Copied" : "Copy Link")
                ShareLink(item: url, subject: Text(recipe.displayName)) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Share Link")
            }
        }
        .sensoryFeedback(.success, trigger: copiedID) { _, new in new == token.id }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await model.revoke(token) }
            } label: {
                Label("Revoke", systemImage: "trash")
            }
        }
        .contextMenu {
            if let url {
                Button("Copy Link", systemImage: "doc.on.doc") { UIPasteboard.general.url = url }
                ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") }
            }
            Button("Revoke Link", systemImage: "trash", role: .destructive) {
                Task { await model.revoke(token) }
            }
        }
    }

    private func url(for token: RecipeShareToken) -> URL? {
        RecipeLinks.publicURL(server: mealie.baseURL, groupSlug: session.currentUser?.groupSlug, tokenID: token.id)
    }

    private func expiryText(_ token: RecipeShareToken) -> String {
        guard let expiresAt = token.expiresAt else { return "Never expires" }
        return "Expires \(expiresAt.formatted(date: .abbreviated, time: .omitted))"
    }
}

private struct PublicLinkShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// How long a new public link stays valid. Mealie's web UI defaults to 30 days.
enum PublicLinkExpiry: String, CaseIterable, Identifiable {
    case day, week, month, year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "In 1 Day"
        case .week: "In 1 Week"
        case .month: "In 30 Days"
        case .year: "In 1 Year"
        }
    }

    func date(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .day: calendar.date(byAdding: .day, value: 1, to: now) ?? now
        case .week: calendar.date(byAdding: .day, value: 7, to: now) ?? now
        case .month: calendar.date(byAdding: .day, value: 30, to: now) ?? now
        case .year: calendar.date(byAdding: .year, value: 1, to: now) ?? now
        }
    }
}

@MainActor
@Observable
final class RecipePublicLinkModel {
    private(set) var links: [RecipeShareToken] = []
    private(set) var isCreating = false
    private(set) var error: String?

    @ObservationIgnored private let recipeID: String
    @ObservationIgnored private let mealie: MealieService

    init(recipeID: String, mealie: MealieService) {
        self.recipeID = recipeID
        self.mealie = mealie
    }

    func load() async {
        do {
            links = Self.active(try await mealie.shareTokens(recipeID: recipeID))
            error = nil
        } catch {
            let error = MealieError.wrap(error)
            guard !error.isCancelled else { return }
            self.error = error.errorDescription
        }
    }

    /// Creates a link and returns it (nil on failure, with `error` set).
    func create(expiresAt: Date) async -> RecipeShareToken? {
        isCreating = true
        defer { isCreating = false }
        do {
            let token = try await mealie.createShareToken(recipeID: recipeID, expiresAt: expiresAt)
            links = Self.active(links + [token])
            error = nil
            return token
        } catch {
            self.error = "Couldn’t create a link. \(MealieError.wrap(error).errorDescription ?? "")"
            return nil
        }
    }

    /// Optimistic revoke with rollback.
    func revoke(_ token: RecipeShareToken) async {
        let previous = links
        links.removeAll { $0.id == token.id }
        do {
            try await mealie.deleteShareToken(id: token.id)
            error = nil
        } catch {
            links = previous
            self.error = "Couldn’t revoke the link. \(MealieError.wrap(error).errorDescription ?? "")"
        }
    }

    /// Unexpired links for the recipe, the one expiring last first.
    nonisolated static func active(_ tokens: [RecipeShareToken], now: Date = Date()) -> [RecipeShareToken] {
        tokens
            .filter { !$0.isExpired(now: now) }
            .sorted { ($0.expiresAt ?? .distantFuture) > ($1.expiresAt ?? .distantFuture) }
    }
}
