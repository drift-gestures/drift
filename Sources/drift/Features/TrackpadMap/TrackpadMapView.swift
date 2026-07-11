import Foundation
import SwiftUI

/// A live, standalone visualization of the physical trackpad contact surface.
struct TrackpadMapView: View {
    @ObservedObject var store: TrackpadMapStore

    var body: some View {
        trackpad
            .padding(8)
            .frame(width: 240, height: 150)
            .background(.clear)
    }

    private var trackpad: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !store.isEnabled)) { timeline in
            Canvas { context, size in
                let railThickness: CGFloat = 8
                let railSpacing: CGFloat = 4
                let surface = CGRect(
                    x: railThickness + railSpacing,
                    y: 0,
                    width: size.width - railThickness - railSpacing,
                    height: size.height - railThickness - railSpacing
                )
                context.fill(
                    Path(roundedRect: surface, cornerRadius: 18),
                    with: .color(Color(nsColor: .controlBackgroundColor))
                )
                context.stroke(
                    Path(roundedRect: surface.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 18),
                    with: .color(.secondary.opacity(0.45)),
                    lineWidth: 1
                )

                drawScrollRails(in: &context, surface: surface, size: size)
                drawTrails(in: &context, surface: surface, now: timeline.date)
                drawSnapshotCenter(in: &context, surface: surface)
            }
        }
        .accessibilityLabel("Live virtual trackpad")
        .accessibilityValue("\(store.snapshot?.fingerCount ?? 0) active contacts")
    }

    private func drawTrails(in context: inout GraphicsContext, surface: CGRect, now: Date) {
        for trail in store.trails.values.sorted(by: { $0.id < $1.id }) {
            let visiblePoints = trail.points.filter { trailOpacity(for: $0, at: now) > 0 }
            let mappedPoints = visiblePoints.map { map($0.position, into: surface) }
            let color = color(for: trail.id)

            for index in mappedPoints.indices.dropFirst() {
                var segment = Path()
                segment.move(to: mappedPoints[index - 1])
                segment.addLine(to: mappedPoints[index])
                context.stroke(
                    segment,
                    with: .color(color.opacity(0.55 * trailOpacity(for: visiblePoints[index], at: now))),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                )
            }

            guard let currentPoint = mappedPoints.last, let latestPoint = visiblePoints.last else { continue }
            let opacity = trailOpacity(for: latestPoint, at: now)
            let diameter = max(5, min(20, trail.contact.size * 20))
            let contactRect = CGRect(
                x: currentPoint.x - diameter / 2,
                y: currentPoint.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            context.fill(Path(ellipseIn: contactRect), with: .color(color.opacity(0.9 * opacity)))
            context.stroke(Path(ellipseIn: contactRect), with: .color(color.opacity(0.4 * opacity)), lineWidth: 4)
        }
    }

    private func trailOpacity(for point: TrackpadMapStore.TrailPoint, at date: Date) -> Double {
        max(0, min(1, 1 - date.timeIntervalSince(point.recordedAt) / TrackpadMapStore.trailFadeDuration))
    }

    private func drawSnapshotCenter(in context: inout GraphicsContext, surface: CGRect) {
        guard let snapshot = store.snapshot, !snapshot.contacts.isEmpty else { return }

        let center = map(snapshot.center, into: surface)
        let averageRadius = snapshot.contacts
            .map { map(CGPoint(x: $0.normalizedPosition.x, y: $0.normalizedPosition.y), into: surface) }
            .map { hypot($0.x - center.x, $0.y - center.y) }
            .reduce(0, +) / CGFloat(snapshot.contacts.count)
        let radiusRect = CGRect(
            x: center.x - averageRadius,
            y: center.y - averageRadius,
            width: averageRadius * 2,
            height: averageRadius * 2
        )
        context.stroke(Path(ellipseIn: radiusRect), with: .color(.primary.opacity(0.5)), lineWidth: 1)

        let armLength: CGFloat = 7
        var crosshair = Path()
        crosshair.move(to: CGPoint(x: -armLength, y: 0))
        crosshair.addLine(to: CGPoint(x: armLength, y: 0))
        crosshair.move(to: CGPoint(x: 0, y: -armLength))
        crosshair.addLine(to: CGPoint(x: 0, y: armLength))

        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: .radians(store.displayRotation))
        context.stroke(
            crosshair,
            with: .color(.primary),
            style: StrokeStyle(lineWidth: 2, lineCap: .round)
        )
        context.rotate(by: .radians(-store.displayRotation))
        context.translateBy(x: -center.x, y: -center.y)
    }

    private func drawScrollRails(in context: inout GraphicsContext, surface: CGRect, size: CGSize) {
        let railExtent: CGFloat = 8
        let tickThickness = TimerHUDStyle.tickHeight
        let tickStep = TimerHUDStyle.tickHeight + TimerHUDStyle.tickSpacing
        let verticalPhase = (-store.scrollPosition.y * surface.height)
            .truncatingRemainder(dividingBy: tickStep)
        let horizontalPhase = (store.scrollPosition.x * surface.width)
            .truncatingRemainder(dividingBy: tickStep)
        let verticalTickCount = Int(ceil(surface.height / tickStep)) + 2
        let horizontalTickCount = Int(ceil(surface.width / tickStep)) + 2

        for index in -verticalTickCount...verticalTickCount {
            let y = surface.midY + CGFloat(index) * tickStep + verticalPhase
            guard y >= surface.minY, y <= surface.maxY else { continue }
            let length = railLength(at: y, center: surface.midY, extent: surface.height, maximum: railExtent)
            let tick = CGRect(
                x: railExtent - length,
                y: y - tickThickness / 2,
                width: length,
                height: tickThickness
            )
            context.fill(Path(roundedRect: tick, cornerRadius: 1), with: .color(.white))
        }

        for index in -horizontalTickCount...horizontalTickCount {
            let x = surface.midX + CGFloat(index) * tickStep + horizontalPhase
            guard x >= surface.minX, x <= surface.maxX else { continue }
            let length = railLength(at: x, center: surface.midX, extent: surface.width, maximum: railExtent)
            let tick = CGRect(
                x: x - tickThickness / 2,
                y: size.height - railExtent,
                width: tickThickness,
                height: length
            )
            context.fill(Path(roundedRect: tick, cornerRadius: 1), with: .color(.white))
        }
    }

    private func railLength(at position: CGFloat, center: CGFloat, extent: CGFloat, maximum: CGFloat) -> CGFloat {
        let distanceFromCenter = min(abs(position - center) / (extent / 2), 1)
        let minimum = maximum / 4
        return maximum - (maximum - minimum) * distanceFromCenter
    }

    private func map(_ point: CGPoint, into surface: CGRect) -> CGPoint {
        CGPoint(
            x: surface.minX + min(max(point.x, 0), 1) * surface.width,
            y: surface.minY + (1 - min(max(point.y, 0), 1)) * surface.height
        )
    }

    private func color(for identifier: Int) -> Color {
        let colors: [Color] = [.blue, .orange, .green, .purple, .pink, .cyan, .yellow, .red]
        return colors[abs(identifier) % colors.count]
    }
}
