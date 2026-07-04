import Foundation

/// App-owned registry for HUD definitions and their shared background workers.
@MainActor
final class HUDRegistry {
    /// Builds one HUD definition using app-wide dependencies.
    private typealias DefinitionBuilder = (HUDController, AppBackgroundWorkers) -> AnyHUDDefinition

    /// HUD definitions available for presentation.
    let definitions: [AnyHUDDefinition]

    /// App-wide background workers available to HUD definitions.
    private let workers: AppBackgroundWorkers

    /// Creates the app HUD registry.
    /// - Parameter hudController: HUD lifecycle handle shared with HUD definitions.
    init(hudController: HUDController) {
        let workers = AppBackgroundWorkers()
        self.workers = workers
        definitions = Self.makeDefinitions(hudController: hudController, workers: workers)
    }

    /// Starts all registered background workers after the app launches.
    func applicationDidFinishLaunching() {
        workers.applicationDidFinishLaunching()
    }

    /// Builds all registered HUD definitions from the HUD builder map.
    /// - Parameters:
    ///   - hudController: HUD lifecycle handle shared with HUD definitions.
    ///   - workers: App-wide background worker container.
    /// - Returns: HUD definitions available for presentation.
    private static func makeDefinitions(
        hudController: HUDController,
        workers: AppBackgroundWorkers
    ) -> [AnyHUDDefinition] {
        definitionBuilders
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { entry in entry.value(hudController, workers) }
    }

    /// HUD definition builders keyed by HUD identifier.
    private static var definitionBuilders: [HUDID: DefinitionBuilder] {
        [
            TimerHUDDefinition.hudID: { hudController, workers in
                AnyHUDDefinition(
                    TimerHUDDefinition(
                        hudController: hudController,
                        workers: workers
                    )
                )
            },
        ]
    }
}
