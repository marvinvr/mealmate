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
/// Same URL as Mealie's web UI (`profile.webp?cacheKey=…`), loaded with the bearer token through
/// `RecipeImageLoader`. A cached picture shows on the first frame, so tab switches don't flash
/// the initials. The `cacheKey` alone isn't a reliable version (it stays put when the file
/// changes outside an upload or OIDC sync), so the picture is then re-fetched like a browser
/// revalidates it, at most once per `refreshInterval`.
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
            guard let url else { return }
            let request = mealie.mediaRequest(url)
            let loader = RecipeImageLoader.shared
            if image(for: url) == nil,
               let cached = await loader.image(for: request, maxPixelSize: Self.maxPixelSize), !Task.isCancelled {
                withAnimation(.smooth(duration: 0.25)) { loaded = (url, cached) }
            }
            let refreshed = await loader.refresh(request, maxPixelSize: Self.maxPixelSize, minInterval: Self.refreshInterval)
            guard !Task.isCancelled else { return }
            switch refreshed {
            case .image(let image):
                withAnimation(.smooth(duration: 0.25)) { loaded = (url, image) }
            case .missing:
                withAnimation(.smooth(duration: 0.25)) { loaded = nil }
            case .unchanged:
                break
            }
        }
    }

    /// One decode for every avatar size (toolbar 32pt, Settings 52pt) at 3x and up.
    private static let maxPixelSize: CGFloat = 256
    /// Toolbar avatars appear on every tab switch; one re-fetch a minute is plenty.
    private static let refreshInterval: TimeInterval = 60

    private func image(for url: URL?) -> UIImage? {
        guard let url else { return nil }
        if let loaded, loaded.url == url { return loaded.image }
        return RecipeImageLoader.memoryImage(for: url)
    }
}
