import SwiftUI

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

/// Round avatar: the Mealie profile picture when available, initials otherwise.
struct UserAvatar: View {
    let user: User?
    var size: CGFloat = 32
    @Environment(\.mealie) private var mealie

    var body: some View {
        ZStack {
            Circle().fill(.quaternary)
            Text(user?.initials ?? "")
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            if let user, let url = mealie.userAvatarURL(userID: user.id, cacheKey: user.cacheKey) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .contentShape(Circle())
    }
}
