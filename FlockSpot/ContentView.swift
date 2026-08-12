import SwiftUI
import UIKit
import CoreLocation

struct ContentView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var cameraStore: FlockCameraStore
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            CompassView()
                .tabItem {
                    Label("Compass", systemImage: "safari")
                }
                .tag(0)

            RouteNavigationView()
                .tabItem {
                    Label("Navigate", systemImage: "arrow.triangle.turn.up.right.circle")
                }
                .tag(1)

            CameraMapViewContainer()
                .tabItem {
                    Label("Map", systemImage: "map")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .accentColor(.blue)
    }
}

struct SettingsView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var cameraStore: FlockCameraStore

    var lastFetchAgo: String {
        guard let lastTime = cameraStore.lastFetchTime else { return "Never" }
        let seconds = Int(Date().timeIntervalSince(lastTime))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Location")) {
                    HStack {
                        Text("Status")
                        Spacer()
                        switch locationManager.authorizationStatus {
                        case .authorizedWhenInUse, .authorizedAlways:
                            Text("Authorized")
                                .foregroundColor(.green)
                        case .denied, .restricted:
                            Text("Denied")
                                .foregroundColor(.red)
                        case .notDetermined:
                            Text("Not Determined")
                                .foregroundColor(.orange)
                        default:
                            Text("Unknown")
                                .foregroundColor(.secondary)
                        }
                    }
                    if locationManager.authorizationStatus != .authorizedWhenInUse &&
                        locationManager.authorizationStatus != .authorizedAlways {
                        Button("Request Permission") {
                            locationManager.requestPermission()
                        }
                    }
                }

                Section(header: Text("GPS")) {
                    if let location = locationManager.currentLocation {
                        HStack {
                            Text("Latitude")
                            Spacer()
                            Text(String(format: "%.5f", location.coordinate.latitude))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Longitude")
                            Spacer()
                            Text(String(format: "%.5f", location.coordinate.longitude))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Accuracy")
                            Spacer()
                            Text(accuracyText(location.horizontalAccuracy))
                                .font(.caption)
                                .foregroundColor(accuracyColor(location.horizontalAccuracy))
                        }
                        HStack {
                            Text("Altitude")
                            Spacer()
                            Text(String(format: "%.1f m", location.altitude))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        if location.speed >= 0 {
                            HStack {
                                Text("Speed")
                                Spacer()
                                Text(String(format: "%.1f mph", location.speed * 2.23694))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                        }
                        if location.course >= 0 {
                            HStack {
                                Text("Course")
                                Spacer()
                                Text(String(format: "%.0f° %@", location.course, cardinalDirection(location.course)))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                        }
                        if let heading = locationManager.heading {
                            HStack {
                                Text("Heading")
                                Spacer()
                                Text(String(format: "%.0f° %@", heading.magneticHeading, cardinalDirection(heading.magneticHeading)))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                        }
                        Button {
                            UIPasteboard.general.string = String(format: "%.5f, %.5f", location.coordinate.latitude, location.coordinate.longitude)
                        } label: {
                            Label("Copy Coordinates", systemImage: "doc.on.doc")
                        }
                    } else {
                        Text("Waiting for GPS fix...")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Sync Status")) {
                    HStack {
                        Text("Cameras Loaded")
                        Spacer()
                        Text("\(cameraStore.cameras.count)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Last Sync")
                        Spacer()
                        Text(lastFetchAgo)
                            .foregroundColor(.secondary)
                    }
                    if let lastCenter = cameraStore.lastFetchCenter {
                        HStack {
                            Text("Center")
                            Spacer()
                            Text(String(format: "%.3f, %.3f",
                                        lastCenter.coordinate.latitude,
                                        lastCenter.coordinate.longitude))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                    }
                    if cameraStore.addedCount > 0 || cameraStore.removedCount > 0 {
                        HStack {
                            Text("Last Changes")
                            Spacer()
                            VStack(alignment: .trailing) {
                                if cameraStore.addedCount > 0 {
                                    Text("+\(cameraStore.addedCount) added")
                                        .foregroundColor(.green)
                                }
                                if cameraStore.removedCount > 0 {
                                    Text("-\(cameraStore.removedCount) removed")
                                        .foregroundColor(.red)
                                }
                            }
                            .font(.caption)
                        }
                    }
                    Button(action: {
                        cameraStore.refresh(forceLocation: locationManager.currentLocation)
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh Now")
                        }
                    }
                    .disabled(cameraStore.isLoading)
                }

                Section(header: Text("Auto-Refresh")) {
                    HStack {
                        Text("Interval")
                        Spacer()
                        Text("Every 15 min")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Stale After")
                        Spacer()
                        Text("30 min")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Re-fetch When")
                        Spacer()
                        Text("Moved ~2 mi")
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Data Source")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OpenStreetMap via Overpass API")
                            .font(.subheadline)
                        Text("Query: man_made=surveillance, surveillance:type=ALPR")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cache: In-memory + disk (30 min TTL)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Changes detected by comparing OSM node IDs between fetches")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func accuracyText(_ accuracy: CLLocationAccuracy) -> String {
        if accuracy < 0 { return "Unknown" }
        if accuracy < 5 { return String(format: "%.0f m (Excellent)", accuracy) }
        if accuracy < 20 { return String(format: "%.0f m (Good)", accuracy) }
        return String(format: "%.0f m (Poor)", accuracy)
    }

    private func accuracyColor(_ accuracy: CLLocationAccuracy) -> Color {
        if accuracy < 0 { return .secondary }
        if accuracy < 5 { return .green }
        if accuracy < 20 { return .yellow }
        return .red
    }

    private func cardinalDirection(_ degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees + 22.5) / 45.0) % 8
        return directions[index]
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(LocationManager())
            .environmentObject(FlockCameraStore())
    }
}
