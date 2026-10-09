import SwiftUI

/// "Reorder Sections": the list's labels in section order, drag to rearrange (e.g. to match
/// the walk through a store). Mealie keeps the order per list (`labelSettings`); the caller
/// saves it optimistically.
struct ShoppingSectionOrderSheet: View {
    /// Unchecked items per label id, shown as a quiet count.
    let counts: [String: Int]
    var onSave: ([ShoppingList.LabelSetting]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var settings: [ShoppingList.LabelSetting]
    private let originalOrder: [String]

    init(settings: [ShoppingList.LabelSetting], counts: [String: Int], onSave: @escaping ([ShoppingList.LabelSetting]) -> Void) {
        _settings = State(initialValue: settings)
        originalOrder = settings.map(\.id)
        self.counts = counts
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Group {
                if settings.isEmpty {
                    ContentUnavailableView {
                        Label("No Labels", systemImage: "tag")
                    } description: {
                        Text("Create labels in Mealie to group items into sections.")
                    }
                } else {
                    list
                }
            }
            .screenBackground()
            .navigationTitle("Reorder Sections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                if !settings.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", systemImage: "checkmark") {
                            onSave(settings)
                            dismiss()
                        }
                        .disabled(settings.map(\.id) == originalOrder)
                    }
                }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(settings) { setting in
                    row(setting)
                }
                .onMove { settings.move(fromOffsets: $0, toOffset: $1) }
            } footer: {
                Text("Drag labels into the order you shop. Items without a label stay at the end.")
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
    }

    private func row(_ setting: ShoppingList.LabelSetting) -> some View {
        let count = counts[setting.labelId] ?? 0
        return HStack(spacing: Theme.Spacing.s) {
            if let color = setting.label?.customColor {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
            }
            Text(setting.label?.name ?? "Label")
            Spacer()
            if count > 0 {
                Text(count, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
