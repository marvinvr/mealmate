import SwiftUI

/// Small capsule label for tags, categories, tools and filter options.
///
/// Not a button by itself: wrap it in a `Button` (with `.buttonStyle(.plain)`) or a
/// `NavigationLink` when it is interactive. Selected chips use a light accent wash
/// instead of a solid fill so a row of filters stays calm.
struct TagChip: View {
    let title: String
    var systemImage: String?
    var isSelected = false

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(title)
                .lineLimit(1)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, 6)
        .background(
            isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.16)) : AnyShapeStyle(.mealMateSurfaceSecondary),
            in: .capsule
        )
        .contentShape(.capsule)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    HStack {
        TagChip(title: "Dinner")
        TagChip(title: "Vegetarian", isSelected: true)
        TagChip(title: "Dutch oven", systemImage: "frying.pan")
    }
    .padding()
    .screenBackground()
}
