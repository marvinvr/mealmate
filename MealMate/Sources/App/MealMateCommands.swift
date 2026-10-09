import SwiftUI

/// Menu bar (iPadOS) and hardware-keyboard shortcuts: ⌘1–⌘4 switch tabs, ⌘N new recipe,
/// ⇧⌘N import from a URL, ⌘, settings. Disabled while signed out. Screen-level shortcuts
/// (cook mode ← / → / Esc) live on their buttons.
struct MealMateCommands: Commands {
    let router: AppRouter
    let session: AppSession

    private var isSignedIn: Bool { session.phase == .signedIn }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Recipe") { open("editor-new") }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!isSignedIn)
            Button("Import Recipe from URL…") { open("import") }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!isSignedIn)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { router.isSettingsPresented = true }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(!isSignedIn)
        }
        CommandMenu("Go") {
            ForEach(Array(AppTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { router.selectedTab = tab }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .disabled(!isSignedIn)
            }
        }
    }

    private func open(_ route: String) {
        AppRoute(string: route)?.apply(router: router, session: session)
    }
}
