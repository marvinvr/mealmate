import SwiftUI

@main
struct MealMateApp: App {
    @State private var session: AppSession
    @State private var router: AppRouter

    init() {
        // Recipe images load through URLSession.shared; give it a real disk cache.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 512 * 1024 * 1024)

        let session = AppSession()
        let router = AppRouter()
        // Configure before the first frame so a restored session never flashes onboarding.
        #if DEBUG
        let handledByHarness = DebugLaunch.configure(session: session, router: router)
        #else
        let handledByHarness = false
        #endif
        if !handledByHarness {
            session.restore()
        }
        _session = State(initialValue: session)
        _router = State(initialValue: router)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(router)
        }
    }
}
