import SwiftUI
import UIKit

/// Avatar in the top-right of every tab root; opens Settings.
struct AccountButton: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(\.mealie) private var mealie

    var body: some View {
        Button {
            router.isSettingsPresented = true
        } label: {
            UserAvatar(user: session.currentUser, size: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Account and settings")
    }
}

/// Round avatar: the user's Mealie profile picture, initials while it loads, when the user
/// has none (404) or loading fails.
///
/// Loaded with the bearer token through `RecipeImageLoader` (memory + disk, keyed by the
/// `cacheKey` URL, so a new picture gets a new URL once `/api/users/self` is refreshed). A
/// cached picture shows on the first frame, so tab switches don't flash the initials.
struct UserAvatar: View {
    let user: User?
    var size: CGFloat = 32
    @Environment(\.mealie) private var mealie
    @State private var loaded: (url: URL, image: UIImage)?

    var body: some View {
        let url = user.flatMap { mealie.userAvatarURL(for: $0) }
        ZStack {
            Circle().fill(.quaternary)
            if let image = image(for: url) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Text(user?.initials ?? "")
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .contentShape(Circle())
        .task(id: url) {
            guard let url, loaded?.url != url, RecipeImageLoader.memoryImage(for: url) == nil else { return }
            guard let image = await RecipeImageLoader.shared.image(for: mealie.mediaRequest(url), maxPixelSize: Self.maxPixelSize),
                  !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.25)) { loaded = (url, image) }
        }
    }

    /// One decode for every avatar size (toolbar 32pt, Settings 52pt) at 3x and up.
    private static let maxPixelSize: CGFloat = 256

    private func image(for url: URL?) -> UIImage? {
        guard let url else { return nil }
        if let loaded, loaded.url == url { return loaded.image }
        return RecipeImageLoader.memoryImage(for: url)
    }
}
