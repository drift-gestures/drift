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
        Canvas { context, size in
            let surface = CGRect(origin: .zero, size: size)
            context.fill(
                Path(roundedRect: surface, cornerRadius: 18),
                with: .color(Color(nsColor: .controlBackgroundColor))
            )
            context.stroke(
                Path(roundedRect: surface.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 18),
                with: .color(.secondary.opacity(0.45)),
                lineWidth: 1
            )

            for trail in store.trails.values.sorted(by: { $0.id < $1.id }) {
                let color = color(for: trail.id)
                let mappedPoints = trail.points.map { map($0, into: size) }
                if mappedPoints.count > 1 {
                    var path = Path()
                    path.move(to: mappedPoints[0])
                    for point in mappedPoints.dropFirst() {
                        path.addLine(to: point)
                    }
                    context.stroke(
                        path,
                        with: .color(color.opacity(0.55)),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                    )
                }

                guard let currentPoint = mappedPoints.last else { continue }
                let diameter = max(10, min(20, trail.contact.size * 80))
                let contactRect = CGRect(
                    x: currentPoint.x - diameter / 2,
                    y: currentPoint.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                context.fill(Path(ellipseIn: contactRect), with: .color(color.opacity(0.9)))
                context.stroke(Path(ellipseIn: contactRect), with: .color(.white.opacity(0.8)), lineWidth: 1)
            }
        }
        .accessibilityLabel("Live virtual trackpad")
        .accessibilityValue("\(store.trails.count) active contacts")
    }

    private func map(_ point: CGPoint, into size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), 1) * size.width,
            y: (1 - min(max(point.y, 0), 1)) * size.height
        )
    }

    private func color(for identifier: Int) -> Color {
        let colors: [Color] = [.blue, .orange, .green, .purple, .pink, .cyan, .yellow, .red]
        return colors[abs(identifier) % colors.count]
    }
}
