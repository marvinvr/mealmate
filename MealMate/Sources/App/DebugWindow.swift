#if DEBUG
import SwiftUI
import UIKit

/// DEBUG-only narrow window for iPad screenshots (`scripts/screenshot.sh --width`), since
/// `simctl` can't resize a simulator window into Split View / Slide Over.
///
/// `-MealMateWindowWidth <points>` lays the app out at that width (leading edge) and makes the
/// scene horizontally compact, like a narrow Split View / Stage Manager window. Sheets and
/// full-screen covers still use the whole screen.
@MainActor
enum DebugWindow {
    static var width: CGFloat? {
        let width = UserDefaults.standard.double(forKey: "MealMateWindowWidth")
        return width > 0 ? width : nil
    }

    static func apply() {
        guard width != nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.traitOverrides.horizontalSizeClass = .compact
    }
}

extension View {
    /// Applies `-MealMateWindowWidth` (DEBUG).
    func debugWindowWidth() -> some View {
        Group {
            if let width = DebugWindow.width {
                frame(width: width)
                    .environment(\.horizontalSizeClass, .compact)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black, ignoresSafeAreaEdges: .all)
            } else {
                self
            }
        }
        .task { DebugWindow.apply() }
    }
}
#endif
