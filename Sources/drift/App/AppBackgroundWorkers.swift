import Foundation

/// Stable keys for app-wide background workers.
enum AppBackgroundWorkerKey: CaseIterable, Hashable {
    /// Local Excalidraw server and document storage runtime.
    case excalidraw
    /// Timer and Pomodoro runtime worker.
    case timer
}

/// App-wide background worker container shared by HUD definitions.
@MainActor
final class AppBackgroundWorkers {
    /// Background workers keyed by stable app worker identifiers.
    private let workersByKey: [AppBackgroundWorkerKey: any HUDBackgroundWorker]

    /// Creates the default app-wide worker container.
    init() {
        workersByKey = [
            .excalidraw: ExcalidrawBackgroundWorker(),
            .timer: TimerBackgroundWorker(),
        ]
    }

    /// Local Excalidraw server, document, and preference runtime worker.
    var excalidraw: ExcalidrawBackgroundWorker {
        worker(.excalidraw, as: ExcalidrawBackgroundWorker.self)
    }

    /// Timer and Pomodoro runtime worker.
    var timer: TimerBackgroundWorker {
        worker(.timer, as: TimerBackgroundWorker.self)
    }

    /// Starts all app-wide background workers after launch.
    func applicationDidFinishLaunching() {
        AppBackgroundWorkerKey.allCases
            .compactMap { workersByKey[$0] }
            .forEach { $0.applicationDidFinishLaunching() } 
    }

    /// Stops all app-wide background workers before the app terminates.
    func applicationWillTerminate() {
        AppBackgroundWorkerKey.allCases
            .compactMap { workersByKey[$0] }
            .forEach { $0.applicationWillTerminate() }
    }

    /// Reads a worker by key and concrete type.
    /// - Parameters:
    ///   - key: Stable worker key.
    ///   - type: Expected concrete worker type.
    /// - Returns: The requested worker.
    private func worker<Worker: HUDBackgroundWorker>(
        _ key: AppBackgroundWorkerKey,
        as type: Worker.Type
    ) -> Worker {
        guard let worker = workersByKey[key] as? Worker else {
            preconditionFailure("Missing background worker for \(key).")
        }
        return worker
    }
}
