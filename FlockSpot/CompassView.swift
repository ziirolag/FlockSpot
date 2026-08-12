import SwiftUI

struct CompassView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var cameraStore: FlockCameraStore

    var nearestCamera: FlockCamera? {
        guard let location = locationManager.currentLocation else { return nil }
        return cameraStore.nearestCamera(to: location)
    }

    var bearingToNearest: Double {
        guard let location = locationManager.currentLocation,
              let camera = nearestCamera else { return 0 }
        return cameraStore.bearing(to: camera, from: location)
    }

    var headingDegrees: Double {
        locationManager.heading?.magneticHeading ?? 0
    }

    var rotationAngle: Double {
        headingDegrees - bearingToNearest
    }

    var distanceToNearest: String {
        guard let location = locationManager.currentLocation,
              let camera = nearestCamera else { return "--" }
        let distance = cameraStore.distance(to: camera, from: location)
        let miles = distance / 1609.34
        if miles < 0.1 {
            return String(format: "%.0f ft", distance * 3.28084)
        } else if miles < 10 {
            return String(format: "%.2f mi", miles)
        } else {
            return String(format: "%.1f mi", miles)
        }
    }

    var cameraBearings: [(camera: FlockCamera, bearing: Double)] {
        guard let location = locationManager.currentLocation else { return [] }
        return cameraStore.cameras.map { cam in
            (cam, cameraStore.bearing(to: cam, from: location))
        }
    }

    var nearbyCameraBearings: [(camera: FlockCamera, bearing: Double)] {
        guard let location = locationManager.currentLocation else { return [] }
        let maxMeters = 3219.0 // ~2 miles
        return cameraStore.cameras.compactMap { cam in
            let dist = location.distance(from: cam.location)
            guard dist <= maxMeters else { return nil }
            return (cam, cameraStore.bearing(to: cam, from: location))
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                if locationManager.currentLocation == nil {
                    VStack(spacing: 16) {
                        Image(systemName: "location.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.yellow)
                        Text("Waiting for location...")
                            .foregroundColor(.white)
                        Button("Enable Location") {
                            locationManager.requestPermission()
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    }
                } else if cameraStore.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading cameras from OpenStreetMap...")
                            .foregroundColor(.gray)
                    }
                } else {
                    HorizontalCompassBar(
                        heading: headingDegrees,
                        cameraBearings: nearbyCameraBearings
                    )
                    .padding(.top, 8)

                    ZStack {
                        CompassRing()
                            .frame(width: 280, height: 280)

                        CardinalLabels()
                            .frame(width: 280, height: 280)

                        FlockCameraIndicator(angle: bearingToNearest)
                            .frame(width: 280, height: 280)

                        CompassNeedle(angle: bearingToNearest)
                            .frame(width: 200, height: 200)
                    }
                    .frame(width: 320, height: 320)
                    .rotationEffect(.degrees(-headingDegrees))

                    if let camera = nearestCamera {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "video.fill")
                                    .foregroundColor(.red)
                                Text("Nearest Camera")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                                Spacer()
                            }

                            if let op = camera.operatorName {
                                Text(op)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            } else if let brand = camera.brand {
                                Text(brand)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }

                            Text(distanceToNearest)
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundColor(.green)

                            VStack(spacing: 3) {
                                if let brand = camera.brand, camera.operatorName != nil {
                                    Text(brand)
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                if let mount = camera.mountType {
                                    Text("\(mount.capitalized) mount")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                if camera.direction != nil {
                                    Text("Facing \(Int(camera.directionDegrees))° \(cardinalDirection(camera.directionDegrees))")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }

                            Text("\(cameraStore.cameras.count) cameras nearby")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                    } else {
                        VStack(spacing: 8) {
                            Text("No cameras found nearby")
                                .foregroundColor(.gray)
                            if let error = cameraStore.error {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                    }

                    Spacer()
                }
            }
            .padding()
        }
    }

    func cardinalDirection(_ degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees + 22.5) / 45.0) % 8
        return directions[index]
    }
}

// MARK: - Horizontal Compass Bar (Fortnite/PUBG style)

struct HorizontalCompassBar: View {
    let heading: Double
    let cameraBearings: [(camera: FlockCamera, bearing: Double)]

    private let barWidth: CGFloat = 320
    private let degreesPerPixel: Double = 0.5
    private let majorTickEvery: Double = 30
    private let minorTickEvery: Double = 10

    private let cardinalMap: [(Double, String)] = [
        (0, "N"), (45, "NE"), (90, "E"), (135, "SE"),
        (180, "S"), (225, "SW"), (270, "W"), (315, "NW"), (360, "N")
    ]

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let tickY: CGFloat = 14
            let labelY: CGFloat = 30
            let dotY: CGFloat = 48

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    )

                ForEach(-180...180, id: \.self) { offset in
                    let deg = normalizeAngle(heading + Double(offset) * (1.0 / degreesPerPixel))
                    let rawX = cx + CGFloat(Double(offset) / degreesPerPixel)
                    let x = (rawX * UIScreen.main.scale).rounded() / UIScreen.main.scale

                    if x >= -20 && x <= barWidth + 20 {
                        if isCardinal(deg) {
                            VStack(spacing: 2) {
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(width: 2, height: 14)
                                Text(cardinalLabel(deg))
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(cardinalColor(deg))
                                Text("\(Int(deg))°")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .position(x: x, y: labelY)
                        } else if isMajor(deg) {
                            VStack(spacing: 1) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.6))
                                    .frame(width: 1, height: 10)
                                Text("\(Int(deg))°")
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            .position(x: x, y: labelY)
                        } else if isMinor(deg) {
                            Rectangle()
                                .fill(Color.white.opacity(0.25))
                                .frame(width: 1, height: 6)
                                .position(x: x, y: tickY)
                        }
                    }
                }

                ForEach(Array(mergedDots().enumerated()), id: \.offset) { _, dot in
                    let x = cx + CGFloat(dot.offset * degreesPerPixel)

                    if x >= 4 && x <= barWidth - 4 {
                        Circle()
                            .fill(dot.isNearest ? Color.red : Color.orange)
                            .frame(width: dot.isNearest ? 8 : 5, height: dot.isNearest ? 8 : 5)
                            .position(x: x, y: dotY)
                    }
                }

                Rectangle()
                    .fill(Color.red.opacity(0.6))
                    .frame(width: 1, height: 56)
                    .position(x: cx, y: 30)

                Path { path in
                    path.move(to: CGPoint(x: cx, y: 2))
                    path.addLine(to: CGPoint(x: cx - 4, y: 8))
                    path.addLine(to: CGPoint(x: cx + 4, y: 8))
                    path.closeSubpath()
                }
                .fill(Color.red)
            }
        }
        .frame(height: 58)
        .drawingGroup()
    }

    private func mergedDots() -> [(offset: Double, isNearest: Bool)] {
        var result: [(offset: Double, isNearest: Bool)] = []
        let nearestBearing = cameraBearings.min(by: { a, b in
            abs(angleDifference(from: heading, to: a.bearing)) < abs(angleDifference(from: heading, to: b.bearing))
        })?.bearing

        let sorted = cameraBearings.sorted { a, b in
            abs(angleDifference(from: heading, to: a.bearing)) < abs(angleDifference(from: heading, to: b.bearing))
        }

        for cam in sorted {
            let diff = angleDifference(from: heading, to: cam.bearing)
            let isNearest = cam.bearing == nearestBearing

            guard abs(diff) <= 90 else { continue }

            if let idx = result.firstIndex(where: { abs($0.offset - diff) < 3 }) {
                if isNearest { result[idx] = (result[idx].offset, true) }
            } else {
                result.append((offset: diff, isNearest: isNearest))
            }
        }
        return result
    }

    private func normalizeAngle(_ angle: Double) -> Double {
        (angle + 360).truncatingRemainder(dividingBy: 360)
    }

    private func angleDifference(from: Double, to: Double) -> Double {
        var diff = to - from
        while diff > 180 { diff -= 360 }
        while diff < -180 { diff += 360 }
        return diff
    }

    private func isCardinal(_ deg: Double) -> Bool {
        cardinalMap.contains { abs($0.0 - deg) < 1 }
    }

    private func isMajor(_ deg: Double) -> Bool {
        abs(deg.remainder(dividingBy: majorTickEvery)) < 1
    }

    private func isMinor(_ deg: Double) -> Bool {
        abs(deg.remainder(dividingBy: minorTickEvery)) < 1
    }

    private func cardinalLabel(_ deg: Double) -> String {
        cardinalMap.first { abs($0.0 - deg) < 1 }?.1 ?? ""
    }

    private func cardinalColor(_ deg: Double) -> Color {
        let label = cardinalLabel(deg)
        return label == "N" ? .red : .white
    }
}

// MARK: - Cardinal Labels (Circular Compass)

struct CardinalLabels: View {
    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2
            let r = min(cx, cy) - 20

            Text("N")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.red)
                .position(x: cx, y: cy - r)
            Text("0°")
                .font(.system(size: 9))
                .foregroundColor(.gray)
                .position(x: cx, y: cy - r + 16)

            Text("E")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .position(x: cx + r, y: cy)
            Text("90°")
                .font(.system(size: 9))
                .foregroundColor(.gray)
                .position(x: cx + r, y: cy + 14)

            Text("S")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .position(x: cx, y: cy + r)
            Text("180°")
                .font(.system(size: 9))
                .foregroundColor(.gray)
                .position(x: cx, y: cy + r - 14)

            Text("W")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .position(x: cx - r, y: cy)
            Text("270°")
                .font(.system(size: 9))
                .foregroundColor(.gray)
                .position(x: cx - r, y: cy + 14)
        }
    }
}

// MARK: - Compass Ring

struct CompassRing: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 6)

            ForEach(0..<36) { i in
                Rectangle()
                    .fill(i % 9 == 0 ? Color.white : Color.gray.opacity(0.5))
                    .frame(width: i % 9 == 0 ? 2 : 1, height: i % 9 == 0 ? 12 : 6)
                    .offset(y: -130)
                    .rotationEffect(.degrees(Double(i) * 10))
            }
        }
    }
}

// MARK: - Compass Needle

struct CompassNeedle: View {
    let angle: Double

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: cx, y: cy - 65))
                    path.addLine(to: CGPoint(x: cx - 8, y: cy - 50))
                    path.addLine(to: CGPoint(x: cx + 8, y: cy - 50))
                    path.closeSubpath()
                }
                .fill(Color.red)
                .rotationEffect(.degrees(angle), anchor: .center)

                Path { path in
                    path.move(to: CGPoint(x: cx, y: cy + 40))
                    path.addLine(to: CGPoint(x: cx - 5, y: cy + 25))
                    path.addLine(to: CGPoint(x: cx + 5, y: cy + 25))
                    path.closeSubpath()
                }
                .fill(Color.red.opacity(0.5))
                .rotationEffect(.degrees(angle), anchor: .center)

                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2, height: 75)
                    .position(x: cx, y: cy - 12)
                    .rotationEffect(.degrees(angle), anchor: .center)

                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
                    .position(x: cx, y: cy)
            }
        }
    }
}

// MARK: - Camera Indicator

struct FlockCameraIndicator: View {
    let angle: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.3))
                .frame(width: 28, height: 28)
                .offset(y: -115)
                .rotationEffect(.degrees(angle))

            Image(systemName: "camera.fill")
                .font(.system(size: 16))
                .foregroundColor(.green)
                .offset(y: -115)
                .rotationEffect(.degrees(angle))
        }
    }
}

// MARK: - Triangle Shape

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Preview

struct CompassView_Previews: PreviewProvider {
    static var previews: some View {
        CompassView()
            .environmentObject(LocationManager())
            .environmentObject(FlockCameraStore())
    }
}
