import SwiftUI

// Small views shared by the Shopping and Meal Plan features.

/// Square recipe thumbnail (or a quiet placeholder when there's no recipe).
struct PlanningRecipeThumbnail: View {
    let recipe: RecipeSummary?
    var size: CGFloat = 56
    /// Glyph for the no-recipe case (e.g. a meal plan note).
    var systemImage = "fork.knife"

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        let side = size * scale
        Group {
            if let recipe {
                RecipeImage(recipe: recipe, size: side > 64 ? .min : .tiny)
            } else {
                Rectangle()
                    .fill(.mealMateSurfaceSecondary)
                    .overlay {
                        Image(systemName: systemImage)
                            .font(.system(size: side * 0.36))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityHidden(true)
            }
        }
        .frame(width: side, height: side)
        .recipeImageShape(cornerRadius: Theme.Radius.thumbnail)
    }
}

/// Toast-like confirmation that floats above the content and goes away on its own.
struct ActionToast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var systemImage = "checkmark.circle.fill"
    /// Optional action, e.g. "Undo".
    var actionTitle: String?
    var duration: Duration = .seconds(4)
}

private struct ActionToastModifier: ViewModifier {
    @Binding var toast: ActionToast?
    var action: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast {
                    ToastView(toast: toast, action: {
                        action()
                        self.toast = nil
                    })
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.bottom, Theme.Spacing.s)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(for: toast.duration)
                        guard !Task.isCancelled else { return }
                        withAnimation(.smooth) { self.toast = nil }
                    }
                }
            }
            .animation(.smooth, value: toast)
    }
}

private struct ToastView: View {
    let toast: ActionToast
    var action: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: toast.systemImage)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle = toast.actionTitle {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .frame(minHeight: 48)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .onAppear {
            AccessibilityNotification.Announcement(toast.message).post()
        }
    }
}

extension View {
    /// Shows `toast` at the bottom; `action` runs when its button is tapped.
    func actionToast(_ toast: Binding<ActionToast?>, action: @escaping () -> Void = {}) -> some View {
        modifier(ActionToastModifier(toast: toast, action: action))
    }
}
