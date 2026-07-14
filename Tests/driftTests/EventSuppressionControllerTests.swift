import XCTest
@testable import drift

final class EventSuppressionControllerTests: XCTestCase {
    func testInitialPermissionSetupKeepsPollingWhilePermissionsAreMissing() {
        let timer = TestPermissionTimer()
        var sessions: [TestTapSession] = []
        let controller = EventSuppressionController(
            permissionStateProvider: { .missing },
            permissionRequester: { _ in },
            tapSessionFactory: { _, _ in
                let session = TestTapSession()
                sessions.append(session)
                return session
            },
            permissionTimer: timer
        )

        XCTAssertFalse(controller.start())

        XCTAssertEqual(controller.status, .waitingForPermissions)
        XCTAssertTrue(timer.isRunning)
        XCTAssertTrue(sessions.isEmpty)
    }

    func testRuntimePermissionRevocationTearsDownTapAndStopsPolling() {
        var permissionState = EventSuppressionPermissionState.allowed
        let timer = TestPermissionTimer()
        var sessions: [TestTapSession] = []
        let controller = EventSuppressionController(
            permissionStateProvider: { permissionState },
            tapSessionFactory: { _, _ in
                let session = TestTapSession()
                sessions.append(session)
                return session
            },
            permissionTimer: timer
        )
        XCTAssertTrue(controller.start())

        permissionState = .missing
        timer.fire()

        XCTAssertEqual(controller.status, .disabled)
        XCTAssertFalse(timer.isRunning)
        XCTAssertTrue(sessions[0].isInvalidated)
    }

    func testTapDisabledNotificationDefersOldSessionTeardownAndStopsPolling() {
        let timer = TestPermissionTimer()
        var sessions: [TestTapSession] = []
        let controller = EventSuppressionController(
            permissionStateProvider: { .allowed },
            tapSessionFactory: { _, _ in
                let session = TestTapSession()
                sessions.append(session)
                return session
            },
            permissionTimer: timer
        )
        XCTAssertTrue(controller.start())

        controller.handleTapDisabledNotification()

        XCTAssertEqual(controller.status, .disabled)
        XCTAssertFalse(timer.isRunning)
        XCTAssertFalse(sessions[0].isInvalidated)
        drainMainQueue()
        XCTAssertTrue(sessions[0].isInvalidated)
    }

    func testFailedManualRetryRemainsDisabledWithoutPolling() {
        var shouldInstall = true
        let timer = TestPermissionTimer()
        let controller = EventSuppressionController(
            permissionStateProvider: { .allowed },
            tapSessionFactory: { _, _ in
                guard shouldInstall else { return nil }
                return TestTapSession()
            },
            permissionTimer: timer
        )
        XCTAssertTrue(controller.start())
        controller.handleTapDisabledNotification()
        shouldInstall = false

        XCTAssertFalse(controller.retrySuppression())

        XCTAssertEqual(controller.status, .disabled)
        XCTAssertFalse(timer.isRunning)
    }

    func testSuccessfulManualRetryKeepsFreshSessionWhenDeferredOldTeardownRuns() {
        let timer = TestPermissionTimer()
        var sessions: [TestTapSession] = []
        let controller = EventSuppressionController(
            permissionStateProvider: { .allowed },
            tapSessionFactory: { _, _ in
                let session = TestTapSession()
                sessions.append(session)
                return session
            },
            permissionTimer: timer
        )
        XCTAssertTrue(controller.start())
        controller.handleTapDisabledNotification()

        XCTAssertTrue(controller.retrySuppression())
        drainMainQueue()

        XCTAssertEqual(controller.status, .available)
        XCTAssertTrue(timer.isRunning)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertTrue(sessions[0].isInvalidated)
        XCTAssertFalse(sessions[1].isInvalidated)
    }

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

    private func drainMainQueue() {
        let expectation = expectation(description: "Main queue drained")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }
}

private extension EventSuppressionPermissionState {
    static let allowed = EventSuppressionPermissionState(
        hasInputMonitoring: true,
        hasAccessibility: true
    )
    static let missing = EventSuppressionPermissionState(
        hasInputMonitoring: false,
        hasAccessibility: false
    )
}

private final class TestTapSession: EventSuppressionTapSession {
    private(set) var isInvalidated = false

    func invalidate() {
        isInvalidated = true
    }
}

private final class TestPermissionTimer: EventSuppressionPermissionTimer {
    private var check: (() -> Void)?

    var isRunning: Bool {
        check != nil
    }

    func start(interval: TimeInterval, check: @escaping () -> Void) {
        guard self.check == nil else { return }
        self.check = check
    }

    func stop() {
        check = nil
    }

    func fire() {
        check?()
    }
}
