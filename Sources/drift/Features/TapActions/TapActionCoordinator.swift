import Foundation

/// Groups impacts that arrive in quick succession into a single/double/triple burst, then performs
/// the best-matching tap action once the burst settles.
///
/// Counting is done here rather than read from `ImpactSnapshot.repeatCount` so the settle window
/// that decides "is another tap coming?" is the same window that decides the final count — a tap
/// action can only fire after we are sure the burst is complete, exactly like click vs. double-click.
@MainActor
final class TapActionCoordinator {
    /// How long to wait after the last impact before treating a burst as complete.
    private let settleInterval: TimeInterval
    private let store: TapActionStore
    private let perform: (CustomGestureAction) -> Void
    private let onTrigger: (TapActionBinding, Int) -> Void

    /// Accumulated state for the burst currently being collected.
    private struct Burst {
        var count: Int
        var containsSlap: Bool
        var side: ImpactSide
    }
    private var burst: Burst?
    private var settleToken = 0

    /// Creates a coordinator.
    /// - Parameters:
    ///   - store: Source of the configured bindings.
    ///   - settleInterval: Quiet time after the last impact before the burst resolves.
    ///   - perform: Executes a matched action (defaults to `CustomGestureActionPerformer`).
    ///   - onTrigger: Notifier called when a binding fires, for logging/feedback.
    init(
        store: TapActionStore,
        settleInterval: TimeInterval = 0.35,
        perform: @escaping (CustomGestureAction) -> Void = { CustomGestureActionPerformer.perform($0) },
        onTrigger: @escaping (TapActionBinding, Int) -> Void = { _, _ in }
    ) {
        self.store = store
        self.settleInterval = settleInterval
        self.perform = perform
        self.onTrigger = onTrigger
    }

    /// Registers one detected impact into the current burst and (re)arms the settle timer.
    /// - Parameters:
    ///   - intensity: The classified impact force.
    ///   - side: The chassis side the impact was classified to, or `.any` when uncalibrated.
    func register(intensity: ImpactIntensity, side: ImpactSide) {
        if var current = burst {
            current.count += 1
            current.containsSlap = current.containsSlap || intensity == .slap
            burst = current
        } else {
            burst = Burst(count: 1, containsSlap: intensity == .slap, side: side)
        }

        settleToken += 1
        let token = settleToken
        DispatchQueue.main.asyncAfter(deadline: .now() + settleInterval) { [weak self] in
            guard let self, self.settleToken == token else { return }
            self.resolveBurst()
        }
    }

    /// Resolves the settled burst against the configured bindings and performs the best match.
    private func resolveBurst() {
        guard let burst else { return }
        self.burst = nil

        let resolvedIntensity: ImpactIntensity = burst.containsSlap ? .slap : .tap
        let candidates = store.snapshot().bindings.filter { binding in
            binding.trigger.count == burst.count &&
            binding.trigger.intensity.matches(resolvedIntensity) &&
            (binding.trigger.side == .any || binding.trigger.side == burst.side) &&
            binding.action.isConfigured
        }

        // Prefer the most specific match: a side- or force-scoped binding beats a catch-all so a
        // general rule cannot shadow a targeted one.
        guard let match = candidates.max(by: { specificity($0) < specificity($1) }) else { return }
        perform(match.action)
        onTrigger(match, burst.count)
    }

    /// Scores how specific a binding's trigger is, so more-specific matches win ties.
    private func specificity(_ binding: TapActionBinding) -> Int {
        (binding.trigger.side == .any ? 0 : 1) + (binding.trigger.intensity == .any ? 0 : 1)
    }
}
