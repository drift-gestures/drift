import XCTest
@testable import drift

final class ListenerArchitectureTests: XCTestCase {
    func testCustomGestureListenerRemainsAvailable() {
        _ = CustomGestureStore()
    }
}
