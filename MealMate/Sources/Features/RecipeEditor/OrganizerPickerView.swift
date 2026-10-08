import SwiftUI

/// Multi-select list of the server's categories or tags (pushed from the editor).
/// Typing a name that doesn't exist offers to create it.
struct OrganizerPickerView: View {
    let kind: OrganizerKind
    @Binding var selection: [Organizer]

    @Environment(\.mealie) private var mealie
    @State private var model: OrganizerPickerModel?
    @State private var query = ""

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .screenBackground()
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil { model = OrganizerPickerModel(kind: kind, mealie: mealie) }
            await model?.load()
        }
    }

    @ViewBuilder
    private func content(_ model: OrganizerPickerModel) -> some View {
        let filtered = model.filtered(by: query)
        List {
            if model.canCreate(query) {
                Section {
                    Button {
                        Task {
                            if let created = await model.create(name: query) {
                                selection.append(created)
                                query = ""
                            }
                        }
                    } label: {
                        Label("Add “\(query.trimmingCharacters(in: .whitespaces))”", systemImage: "plus.circle")
                    }
                    .disabled(model.isCreating)
                }
            }
            if !selection.isEmpty && query.isEmpty {
                Section("Selected") {
                    ForEach(selection, id: \.stableID) { organizer in
                        row(organizer, isSelected: true)
                    }
                }
            }
            Section {
                ForEach(filtered.filter { query.isEmpty ? !isSelected($0) : true }, id: \.stableID) { organizer in
                    row(organizer, isSelected: isSelected(organizer))
                }
            } header: {
                if query.isEmpty && !selection.isEmpty && !filtered.isEmpty { Text("All \(kind.title)") }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search or add \(kind.editorSingularTitle.lowercased())")
        .autocorrectionDisabled()
        .refreshable { await model.load() }
        .overlay {
            if model.isLoaded && model.all.isEmpty && query.isEmpty && selection.isEmpty {
                ContentUnavailableView {
                    Label("No \(kind.title) Yet", systemImage: kind.systemImage)
                } description: {
                    Text("Type a name in the search field to add the first one.")
                }
            } else if let error = model.errorMessage, model.all.isEmpty {
                ContentUnavailableView {
                    Label("Can’t Load \(kind.title)", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await model.load() } }
                        .buttonStyle(.bordered)
                }
            }
        }
        .alert("Couldn’t Add \(kind.editorSingularTitle)", isPresented: Binding(
            get: { model.createError != nil }, set: { if !$0 { model.createError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.createError ?? "")
        }
        .sensoryFeedback(.selection, trigger: selection.map(\.stableID))
    }

    private func row(_ organizer: Organizer, isSelected: Bool) -> some View {
        Button {
            toggle(organizer)
        } label: {
            HStack {
                Text(organizer.name)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func isSelected(_ organizer: Organizer) -> Bool {
        selection.contains { $0.stableID == organizer.stableID || $0.slug == organizer.slug }
    }

    private func toggle(_ organizer: Organizer) {
        withAnimation(.snappy) {
            if isSelected(organizer) {
                selection.removeAll { $0.stableID == organizer.stableID || $0.slug == organizer.slug }
            } else {
                selection.append(organizer)
            }
        }
    }
}

@MainActor
@Observable
final class OrganizerPickerModel {
    let kind: OrganizerKind
    private(set) var all: [Organizer] = []
    private(set) var isLoaded = false
    private(set) var isCreating = false
    private(set) var errorMessage: String?
    var createError: String?

    @ObservationIgnored private let mealie: MealieService
    private var cacheKey: String { "editor.organizers.\(kind.rawValue)" }

    init(kind: OrganizerKind, mealie: MealieService) {
        self.kind = kind
        self.mealie = mealie
    }

    func load() async {
        if all.isEmpty, let cached = await mealie.cached([Organizer].self, key: cacheKey) {
            all = cached
            isLoaded = true
        }
        do {
            let fresh = try await mealie.organizers(kind)
            all = fresh
            errorMessage = nil
            isLoaded = true
            await mealie.storeInCache(fresh, key: cacheKey)
        } catch {
            let wrapped = MealieError.wrap(error)
            guard !wrapped.isCancelled else { return }
            errorMessage = wrapped.errorDescription
            isLoaded = true
        }
    }

    func filtered(by query: String) -> [Organizer] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.name.localizedStandardContains(trimmed) }
    }

    func canCreate(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, isLoaded else { return false }
        return !all.contains { $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    func create(name: String) async -> Organizer? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isCreating else { return nil }
        isCreating = true
        defer { isCreating = false }
        do {
            let created = try await mealie.createOrganizer(kind, name: trimmed)
            all.append(created)
            all.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            await mealie.storeInCache(all, key: cacheKey)
            return created
        } catch {
            createError = MealieError.wrap(error).errorDescription
            return nil
        }
    }
}

extension OrganizerKind {
    var editorSingularTitle: String {
        switch self {
        case .category: "Category"
        case .tag: "Tag"
        case .tool: "Tool"
        }
    }
}
