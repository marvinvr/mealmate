import SwiftUI

/// Settings sheet (opened from the avatar button): account, server, about, sign out.
struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.mealie) private var mealie
    @State private var confirmsSignOut = false

    var body: some View {
        NavigationStack {
            List {
                accountSection
                serverSection
                aboutSection
                Section {
                    Button("Sign Out", role: .destructive) {
                        confirmsSignOut = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .screenBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .refreshable { await session.refresh() }
            // Picks up a profile picture (new `cacheKey`) or name changed in Mealie meanwhile.
            .task { await session.refresh() }
            .confirmationDialog("Sign out of \(serverHost)?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    dismiss()
                    session.signOut()
                }
            } message: {
                Text("Your recipes stay on your server. MealMate removes its access token from this device.")
            }
        }
    }

    private var serverHost: String {
        session.serverURL?.host() ?? "Mealie"
    }

    private var accountSection: some View {
        Section {
            HStack(spacing: 14) {
                UserAvatar(user: session.currentUser, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.currentUser?.displayName ?? "Signed in")
                        .font(.headline)
                    if let email = session.currentUser?.email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            if let household = session.currentUser?.household {
                LabeledContent("Household", value: household)
            }
            if let group = session.currentUser?.group {
                LabeledContent("Group", value: group)
            }
        }
    }

    private var serverSection: some View {
        Section("Server") {
            if let url = session.serverURL {
                LabeledContent("Address") {
                    Text(url.absoluteString)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if let info = session.appInfo {
                LabeledContent("Mealie Version", value: info.displayVersion)
                if info.isOIDCEnabled, let provider = info.oidcProviderName, !provider.isEmpty {
                    LabeledContent("Single Sign-On", value: provider)
                }
            }
            if let url = session.serverURL {
                Link(destination: url) {
                    Label("Open Mealie in Safari", systemImage: "safari")
                }
            }
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Self.appVersion)
            Link(destination: URL(string: "https://mealie.io")!) {
                Label("About Mealie", systemImage: "info.circle")
            }
        } header: {
            Text("About")
        } footer: {
            Text("MealMate is a free, independent app for Mealie. It isn’t affiliated with the Mealie project.")
        }
    }

    private static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        return "\(version) (\(build))"
    }
}
