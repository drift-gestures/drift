import CoreGraphics
import SwiftUI

/// HUD definition for the single Excalidraw surface.
struct ExcalidrawHUDDefinition: HudDefinition {
    /// Stable identifier used to register, show, hide, and message the Excalidraw HUD.
    static let hudID = HUDID(rawValue: "excalidraw")

    /// The Excalidraw HUD identifier required by `HudDefinition`.
    let id = hudID
    /// Default launcher size before the view applies a mode override.
    let size = ExcalidrawHUDStyle.launcherSize

    private let hudController: HUDController
    private let worker: ExcalidrawBackgroundWorker

    /// Creates the Excalidraw HUD definition.
    init(hudController: HUDController, worker: ExcalidrawBackgroundWorker) {
        self.hudController = hudController
        self.worker = worker
    }

    /// Positions all Excalidraw modes near the top-center of the visible screen.
    func position(in context: HUDLayoutContext, size: CGSize) -> CGPoint {
        let topInset: CGFloat = size.height > ExcalidrawHUDStyle.searchSize.height
            ? ExcalidrawHUDStyle.editorTopInset
            : ExcalidrawHUDStyle.launcherTopInset
        return CGPoint(
            x: context.screenFrame.midX - size.width / 2,
            y: context.screenFrame.maxY - size.height - topInset
        )
    }

    /// Builds the Excalidraw HUD SwiftUI content.
    func content(context: HUDContext) -> some View {
        let state = context.state.payload(as: ExcalidrawHUDState.self) ?? ExcalidrawHUDState()
        ExcalidrawHUDView(
            worker: worker,
            documents: worker.documents,
            hudController: hudController,
            screenFrame: context.layout.screenFrame,
            initialState: state
        )
    }
}
