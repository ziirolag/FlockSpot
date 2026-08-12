import SwiftUI
import WidgetKit

@main
struct FlockSpotApp: App {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var cameraStore = FlockCameraStore()
    @AppStorage("disclaimerAccepted") private var disclaimerAccepted = false
    @State private var lastWidgetReload = Date.distantPast

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
                .environmentObject(cameraStore)
                .fullScreenCover(isPresented: Binding(
                    get: { !disclaimerAccepted },
                    set: { _ in }
                )) {
                    DisclaimerView(disclaimerAccepted: $disclaimerAccepted)
                }
                .onAppear {
                    if disclaimerAccepted {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            locationManager.requestPermission()
                        }
                    }
                }
                .onReceive(locationManager.$currentLocation) { location in
                    if let location = location {
                        cameraStore.loadCameras(for: location)
                    }
                }
                .onReceive(locationManager.$heading) { heading in
                    if let heading = heading {
                        SharedCameraData.save(cameras: cameraStore.cameras, location: locationManager.currentLocation, heading: heading.magneticHeading)
                        let now = Date()
                        if now.timeIntervalSince(lastWidgetReload) >= 5 {
                            lastWidgetReload = now
                            WidgetCenter.shared.reloadAllTimelines()
                        }
                    }
                }
        }
    }
}
