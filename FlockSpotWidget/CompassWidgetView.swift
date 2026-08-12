import WidgetKit
import SwiftUI
import CoreLocation

struct CompassWidgetEntryView: View {
    var entry: CompassProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        case .systemMedium:
            mediumWidget
        default:
            smallWidget
        }
    }

    // MARK: - Small Widget

    var smallWidget: some View {
        ZStack {
            Color.black

            VStack(spacing: 4) {
                ZStack {
                    CompassRingWidget()
                        .frame(width: 80, height: 80)

                    CardinalLabelsWidget()
                        .frame(width: 80, height: 80)

                    CompassNeedleWidget(angle: entry.bearing)
                        .frame(width: 60, height: 60)
                }
                .rotationEffect(.degrees(-entry.heading))

                if let camera = entry.camera {
                    Text(camera.operatorName ?? camera.brand ?? "ALPR Camera")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if let dist = entry.distance {
                        Text(formatDistance(dist))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                    }
                } else {
                    Text("No camera")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
            }
            .padding(8)

            // Refresh button
            Button(intent: RefreshIntent()) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .position(x: 65, y: 65)
        }
        .widgetURL(URL(string: "flockspot://")!)
    }

    // MARK: - Medium Widget

    var mediumWidget: some View {
        ZStack {
            Color.black

            HStack(spacing: 12) {
                ZStack {
                    CompassRingWidget()
                        .frame(width: 90, height: 90)

                    CardinalLabelsWidget()
                        .frame(width: 90, height: 90)

                    CompassNeedleWidget(angle: entry.bearing)
                        .frame(width: 70, height: 70)
                }
                .rotationEffect(.degrees(-entry.heading))

                VStack(alignment: .leading, spacing: 4) {
                    Text("FlockSpot GPS")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)

                    if let camera = entry.camera {
                        Text(camera.operatorName ?? camera.brand ?? "ALPR Camera")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.green)
                            .lineLimit(1)

                        if let dist = entry.distance {
                            Text(formatDistance(dist))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    } else {
                        Text("No camera nearby")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                }

                Spacer()
            }
            .padding(12)

            // Refresh button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(intent: RefreshIntent()) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .widgetURL(URL(string: "flockspot://")!)
    }

    // MARK: - Helpers

    private func formatDistance(_ meters: Double) -> String {
        let miles = meters / 1609.34
        if miles < 0.1 {
            return String(format: "%.0f ft", meters * 3.28084)
        } else if miles < 10 {
            return String(format: "%.2f mi", miles)
        } else {
            return String(format: "%.1f mi", miles)
        }
    }
}

// MARK: - Widget Compass Components

struct CompassRingWidget: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 3)

            ForEach(0..<36) { i in
                Rectangle()
                    .fill(i % 9 == 0 ? Color.white : Color.gray.opacity(0.5))
                    .frame(width: i % 9 == 0 ? 2 : 1, height: i % 9 == 0 ? 7 : 4)
                    .offset(y: -37)
                    .rotationEffect(.degrees(Double(i) * 10))
            }
        }
    }
}

struct CardinalLabelsWidget: View {
    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2
            let r = min(cx, cy) - 8

            Text("N")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.red)
                .position(x: cx, y: cy - r)

            Text("E")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.white)
                .position(x: cx + r, y: cy)

            Text("S")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.white)
                .position(x: cx, y: cy + r)

            Text("W")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.white)
                .position(x: cx - r, y: cy)
        }
    }
}

struct CompassNeedleWidget: View {
    let angle: Double

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: cx, y: cy - 28))
                    path.addLine(to: CGPoint(x: cx - 5, y: cy - 15))
                    path.addLine(to: CGPoint(x: cx + 5, y: cy - 15))
                    path.closeSubpath()
                }
                .fill(Color.red)
                .rotationEffect(.degrees(angle), anchor: .center)

                Path { path in
                    path.move(to: CGPoint(x: cx, y: cy + 18))
                    path.addLine(to: CGPoint(x: cx - 3, y: cy + 8))
                    path.addLine(to: CGPoint(x: cx + 3, y: cy + 8))
                    path.closeSubpath()
                }
                .fill(Color.red.opacity(0.5))
                .rotationEffect(.degrees(angle), anchor: .center)

                Rectangle()
                    .fill(Color.red)
                    .frame(width: 1.5, height: 40)
                    .position(x: cx, y: cy - 5)
                    .rotationEffect(.degrees(angle), anchor: .center)

                Circle()
                    .fill(Color.white)
                    .frame(width: 4, height: 4)
                    .position(x: cx, y: cy)
            }
        }
    }
}

// MARK: - Widget Configuration

struct CompassWidget: Widget {
    let kind: String = "CompassWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CompassProvider()) { entry in
            CompassWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("FlockSpot Compass")
        .description("Points to the nearest ALPR camera.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CompassWidget_Previews: PreviewProvider {
    static var previews: some View {
        CompassWidgetEntryView(entry: CompassEntry(date: Date(), camera: nil, heading: 0, distance: nil, bearing: 0))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
    }
}
