import Foundation

/// Stable keys for app-wide background workers.
enum AppBackgroundWorkerKey: CaseIterable, Hashable {}

/// App-wide background worker container shared by HUD definitions.
@MainActor
final class AppBackgroundWorkers {
    /// Background workers keyed by stable app worker identifiers.
    private let workersByKey: [AppBackgroundWorkerKey: any HUDBackgroundWorker]

    /// Creates the default app-wide worker container.
    init() {
        workersByKey = [:]
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

}
