import SwiftUI

/// Settings → App Icon. The default icon, the supporter icons and the Head Chef icons, each in
/// their own section. Locked icons open the supporter sheet instead of applying.
struct AppIconPickerView: View {
    @Environment(SupporterStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var current: MealMateAppIcon = .default
    @State private var showsSupporter = false
    @State private var failed = false

    var body: some View {
        List {
            Section {
                grid([.default])
            }
            Section {
                grid(MealMateAppIcon.supporterIcons.filter { $0 != .default })
            } header: {
                Text("Supporter")
            } footer: {
                Text(store.isSupporter
                     ? "Yours for good. Thank you for supporting MealMate."
                     : "Any tip or subscription unlocks these for good.")
            }
            Section {
                grid(MealMateAppIcon.headChefIcons)
            } header: {
                Text("Head Chef")
            } footer: {
                Text(store.isHeadChef
                     ? "Included while your Head Chef subscription is active. If it ends, MealMate switches back to the default icon."
                     : "Included with a Head Chef subscription, for as long as it’s active.")
            }
        }
        .screenBackground()
        .readableContentWidth()
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .trackingAppIcon($current)
        .sheet(isPresented: $showsSupporter) {
            SupporterView(context: .settings)
        }
        .alert("Couldn’t Change the Icon", isPresented: $failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try again in a moment.")
        }
    }

    private func grid(_ icons: [MealMateAppIcon]) -> some View {
        let size: CGFloat = horizontalSizeClass == .regular ? 84 : 68
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: size + 12), spacing: Theme.Spacing.m, alignment: .top)],
                         alignment: .leading, spacing: Theme.Spacing.l) {
            ForEach(icons) { icon in
                tile(icon, size: size)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func tile(_ icon: MealMateAppIcon, size: CGFloat) -> some View {
        let available = icon.isAvailable(isSupporter: store.isSupporter, tier: store.activeTier)
        let selected = current == icon
        return Button {
            guard available else {
                showsSupporter = true
                return
            }
            Task {
                do {
                    try await MealMateAppIcon.select(icon)
                } catch {
                    failed = true
                }
                current = .current
            }
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                AppIconImage(icon: icon, size: size, isSelected: selected, isLocked: !available)
                Text(icon.displayName)
                    .font(.caption)
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon.displayName)
        .accessibilityValue(available ? "" : "Locked")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
