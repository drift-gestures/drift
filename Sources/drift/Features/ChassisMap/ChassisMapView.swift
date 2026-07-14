import Foundation
import SwiftUI

/// A live, standalone visualization of chassis accelerometer motion and detected impacts.
struct ChassisMapView: View {
    @ObservedObject var store: ChassisMapStore

    var body: some View {
        VStack(spacing: 6) {
            chassis
            readout
        }
        .padding(8)
        .frame(width: 240, height: 190)
        .background(.clear)
    }

    private var chassis: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !store.isEnabled)) { timeline in
            Canvas { context, size in
                let surface = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
                context.fill(
                    Path(roundedRect: surface, cornerRadius: 18),
                    with: .color(Color(nsColor: .controlBackgroundColor))
                )
                context.stroke(
                    Path(roundedRect: surface.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 18),
                    with: .color(.secondary.opacity(0.45)),
                    lineWidth: 1
                )

                drawCenterGuides(in: &context, surface: surface)
                drawZoneGuides(in: &context, surface: surface)
                drawImpactMarkers(in: &context, surface: surface, now: timeline.date)
                drawLiveCrosshair(in: &context, surface: surface)
            }
        }
        .accessibilityLabel("Live chassis accelerometer")
        .accessibilityValue("\(store.impactMarkers.count) recent impacts")
    }

    /// Numeric live g-value readout, the coordinate counterpart to the trackpad map's frame data.
    private var readout: some View {
        HStack(spacing: 10) {
            axisLabel("X", value: store.latestSample?.x)
            axisLabel("Y", value: store.latestSample?.y)
            axisLabel("Z", value: store.latestSample?.z)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func axisLabel(_ axis: String, value: Double?) -> some View {
        Text("\(axis) \(value.map { String(format: "%+.2fg", $0) } ?? "—")")
    }

    /// Draws faint center cross-lines so the crosshair's offset from rest is readable.
    private func drawCenterGuides(in context: inout GraphicsContext, surface: CGRect) {
        var guides = Path()
        guides.move(to: CGPoint(x: surface.midX, y: surface.minY))
        guides.addLine(to: CGPoint(x: surface.midX, y: surface.maxY))
        guides.move(to: CGPoint(x: surface.minX, y: surface.midY))
        guides.addLine(to: CGPoint(x: surface.maxX, y: surface.midY))
        context.stroke(guides, with: .color(.secondary.opacity(0.2)), lineWidth: 1)
    }

    /// Draws faint rings at calibrated zone centers so snapped hits are legible as zones.
    private func drawZoneGuides(in context: inout GraphicsContext, surface: CGRect) {
        for zoneCenter in store.zoneCenters {
            let center = map(zoneCenter, into: surface)
            let diameter: CGFloat = 22
            let ringRect = CGRect(
                x: center.x - diameter / 2,
                y: center.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            context.stroke(
                Path(ellipseIn: ringRect),
                with: .color(.secondary.opacity(0.35)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
        }
    }

    /// Draws fading dots for recently detected taps/slaps at their approximate coordinates.
    private func drawImpactMarkers(in context: inout GraphicsContext, surface: CGRect, now: Date) {
        for marker in store.impactMarkers {
            let opacity = markerOpacity(for: marker, at: now)
            guard opacity > 0 else { continue }

            let center = map(marker.coordinate, into: surface)
            let color: Color = marker.intensity == .slap ? .red : .yellow
            let diameter = max(10, min(40, 10 + marker.peakMagnitude * 16))
            let dotRect = CGRect(
                x: center.x - diameter / 2,
                y: center.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            context.fill(Path(ellipseIn: dotRect), with: .color(color.opacity(0.75 * opacity)))
            context.stroke(Path(ellipseIn: dotRect), with: .color(color.opacity(0.5 * opacity)), lineWidth: 1.5)
        }
    }

    /// Fraction of a marker's fade window remaining, from `1` (just detected) to `0` (fully faded).
    private func markerOpacity(for marker: ChassisMapStore.ImpactMarker, at date: Date) -> Double {
        max(0, min(1, 1 - date.timeIntervalSince(marker.recordedAt) / ChassisMapStore.impactFadeDuration))
    }

    /// Draws the live crosshair at the smoothed accelerometer position.
    private func drawLiveCrosshair(in context: inout GraphicsContext, surface: CGRect) {
        let center = map(store.livePosition, into: surface)
        let armLength: CGFloat = 8
        var crosshair = Path()
        crosshair.move(to: CGPoint(x: center.x - armLength, y: center.y))
        crosshair.addLine(to: CGPoint(x: center.x + armLength, y: center.y))
        crosshair.move(to: CGPoint(x: center.x, y: center.y - armLength))
        crosshair.addLine(to: CGPoint(x: center.x, y: center.y + armLength))
        context.stroke(crosshair, with: .color(.primary), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        let ringDiameter: CGFloat = 10
        let ringRect = CGRect(
            x: center.x - ringDiameter / 2,
            y: center.y - ringDiameter / 2,
            width: ringDiameter,
            height: ringDiameter
        )
        context.stroke(Path(ellipseIn: ringRect), with: .color(.primary.opacity(0.6)), lineWidth: 1.5)
    }

    /// Maps a normalized `0...1` coordinate into the drawing surface, with `y` up.
    private func map(_ point: CGPoint, into surface: CGRect) -> CGPoint {
        CGPoint(
            x: surface.minX + min(max(point.x, 0), 1) * surface.width,
            y: surface.minY + (1 - min(max(point.y, 0), 1)) * surface.height
        )
    }
}
