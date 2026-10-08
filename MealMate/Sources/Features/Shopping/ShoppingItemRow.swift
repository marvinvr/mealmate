import SwiftUI

/// One shopping item: check circle, text (quantity · unit · food · note) and the recipes
/// it came from. Tapping the row toggles it; editing lives in swipe actions / context menu.
struct ShoppingItemRow: View {
    let item: ShoppingListItem
    var recipeNames: [String] = []
    var toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.checked ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    title
                        .strikethrough(item.checked, color: .secondary)
                        .foregroundStyle(item.checked ? .secondary : .primary)
                    if !recipeNames.isEmpty {
                        Text("\(Image(systemName: "book.pages")) \(recipeNames.joined(separator: ", "))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if item.isPending {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(item.isPending)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(item.checked ? [.isSelected] : [])
        .accessibilityHint(item.checked ? "Double-tap to uncheck." : "Double-tap to check off.")
    }

    /// Quantity and unit lightly emphasised, food in full weight, note secondary.
    private var title: some View {
        Text(item.displayText)
            .font(.body)
            .multilineTextAlignment(.leading)
    }

    private var accessibilityText: String {
        var parts = [item.displayText]
        if !recipeNames.isEmpty { parts.append("from \(recipeNames.joined(separator: ", "))") }
        if item.checked { parts.append("checked") }
        return parts.joined(separator: ", ")
    }
}

/// Section header for a label group: subtle colour dot (only for custom colours) + name.
struct ShoppingSectionHeader: View {
    let section: ShoppingSection

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let color = section.label?.customColor {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            Text(section.title)
            Spacer()
            Text(section.items.count, format: .number)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .accessibilityLabel("\(section.items.count) items")
        }
    }
}

#Preview {
    List {
        Section {
            ShoppingItemRow(item: .preview("2 cups flour"), recipeNames: ["Banana Bread"]) {}
            ShoppingItemRow(item: .preview("milk")) {}
            ShoppingItemRow(item: .preview("1 pack butter", checked: true)) {}
        }
    }
    .screenBackground()
}

extension ShoppingListItem {
    static func preview(_ text: String, checked: Bool = false) -> ShoppingListItem {
        ShoppingListItem(id: UUID().uuidString, shoppingListId: "list", quantity: 0, note: text,
                         display: text, checked: checked, createdAt: .now)
    }
}
