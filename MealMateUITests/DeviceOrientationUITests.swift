import XCTest

/// Not a real test: `scripts/sim-orientation.sh` runs it to rotate the simulator (simctl can't,
/// and apps can't rotate themselves in iPad windowing modes). The orientation sticks after the
/// runner exits, so `scripts/screenshot.sh` can shoot landscape afterwards.
final class DeviceOrientationUITests: XCTestCase {
    @MainActor
    func testSetOrientation() throws {
        guard let value = ProcessInfo.processInfo.environment["MEALMATE_ORIENTATION"] else {
            throw XCTSkip("Set TEST_RUNNER_MEALMATE_ORIENTATION=landscape|portrait (scripts/sim-orientation.sh).")
        }
        XCUIDevice.shared.orientation = value == "landscape" ? .landscapeLeft : .portrait
    }
}
