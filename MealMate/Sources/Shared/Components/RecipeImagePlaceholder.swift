import SwiftUI

/// Stand-in for a recipe without a photo (or while/if the photo fails to load).
///
/// A quiet fill with one of a few muted food tones, picked deterministically from `seed`
/// (pass the recipe id or slug) so the same recipe always looks the same and a grid of
/// photo-less recipes is not a wall of identical grey. Fills its frame; size and clip it
/// at the call site, e.g. `.aspectRatio(Theme.Aspect.card, contentMode: .fill)` and
/// `.recipeImageShape()`.
struct RecipeImagePlaceholder: View {
    var seed: String = ""
    var showsGlyph = true

    var body: some View {
        let tone = Self.tone(for: seed)
        Rectangle()
            .fill(.mealMateSurfaceSecondary)
            .overlay { Rectangle().fill(tone.opacity(0.18)) }
            .overlay {
                if showsGlyph {
                    GeometryReader { proxy in
                        let side = min(max(min(proxy.size.width, proxy.size.height) * 0.22, 14), 40)
                        Image(systemName: "fork.knife")
                            .resizable()
                            .scaledToFit()
                            .frame(width: side, height: side)
                            .foregroundStyle(tone.opacity(0.75))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .accessibilityHidden(true)
    }

    /// Sage, oat, clay, stone, mist. Used only at low opacity over `mealMateSurfaceSecondary`.
    private static let tones: [Color] = [
        Color(red: 0x7A / 255, green: 0x9E / 255, blue: 0x6C / 255),
        Color(red: 0xB8 / 255, green: 0x9F / 255, blue: 0x6E / 255),
        Color(red: 0xB0 / 255, green: 0x7A / 255, blue: 0x5E / 255),
        Color(red: 0x8E / 255, green: 0x88 / 255, blue: 0x7C / 255),
        Color(red: 0x7E / 255, green: 0x95 / 255, blue: 0x9B / 255),
    ]

    /// Stable across launches (unlike `hashValue`): FNV-1a over the UTF-8 bytes.
    private static func tone(for seed: String) -> Color {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return tones[Int(hash % UInt64(tones.count))]
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.gridMinimumColumnWidth), spacing: Theme.Spacing.grid)],
              spacing: Theme.Spacing.grid) {
        ForEach(["lemon-herb-chicken", "tomato-soup", "banana-bread", "green-curry", "focaccia", "ramen"], id: \.self) { slug in
            RecipeImagePlaceholder(seed: slug)
                .aspectRatio(Theme.Aspect.card, contentMode: .fill)
                .recipeImageShape()
        }
    }
    .padding(Theme.Spacing.screen)
    .frame(maxHeight: .infinity, alignment: .top)
    .screenBackground()
}
