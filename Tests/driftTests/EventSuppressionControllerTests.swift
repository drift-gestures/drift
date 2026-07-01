import XCTest
@testable import drift

final class EventSuppressionControllerTests: XCTestCase {
    func testStartRequestsMissingPermissionsOnceWhileAppIsOpen() {
        var requestCount = 0
        let controller = EventSuppressionController(
            permissionStateProvider: {
                EventSuppressionPermissionState(
                    hasInputMonitoring: false,
                    hasAccessibility: false
                )
            },
            permissionRequester: { _ in
                requestCount += 1
            }
        )

        XCTAssertFalse(controller.start())
        XCTAssertFalse(controller.start())
        controller.stop()

        XCTAssertEqual(requestCount, 1)
    }

    func testPermissionPollingStillChecksStateWithoutPromptingAgain() {
        var stateCheckCount = 0
        var requestCount = 0
        let controller = EventSuppressionController(
            permissionStateProvider: {
                stateCheckCount += 1
                return EventSuppressionPermissionState(
                    hasInputMonitoring: false,
                    hasAccessibility: false
                )
            },
            permissionRequester: { _ in
                requestCount += 1
            }
        )

        XCTAssertFalse(controller.start())
        XCTAssertFalse(controller.start())
        controller.stop()

        XCTAssertGreaterThanOrEqual(stateCheckCount, 2)
        XCTAssertEqual(requestCount, 1)
    }

    func testOpeningAppAgainCanRequestMissingPermissionsAgain() {
        var requestCount = 0
        let controller = EventSuppressionController(
            permissionStateProvider: {
                EventSuppressionPermissionState(
                    hasInputMonitoring: false,
                    hasAccessibility: false
                )
            },
            permissionRequester: { _ in
                requestCount += 1
            }
        )

        XCTAssertFalse(controller.start())
        controller.stop()
        XCTAssertFalse(controller.start())
        controller.stop()

        XCTAssertEqual(requestCount, 2)
    }

    func testStartDoesNotPromptWhenPermissionsAreAlreadyGranted() {
        var requestCount = 0
        let controller = EventSuppressionController(
            permissionStateProvider: {
                EventSuppressionPermissionState(
                    hasInputMonitoring: true,
                    hasAccessibility: true
                )
            },
            permissionRequester: { _ in
                requestCount += 1
            },
            permissionCheckInterval: 60
        )

        _ = controller.start()
        controller.stop()

        XCTAssertEqual(requestCount, 0)
    }
}
