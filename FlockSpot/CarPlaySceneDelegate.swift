import CarPlay
import CoreLocation
import MapKit

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    var cameras: [SharedCameraEntry] = []
    var userLocation: CLLocation?
    var locationManager: CLLocationManager?
    private var lastLocationUpdate: Date = .distantPast

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        loadFromSharedCache()
        interfaceController.setRootTemplate(makeListTemplate(), animated: true, completion: nil)
        startLocationUpdates()
    }

    func templateApplicationSceneDidDisconnect(_ templateApplicationScene: CPTemplateApplicationScene) {
        locationManager?.stopUpdatingLocation()
        locationManager = nil
    }

    // MARK: - Templates

    private func makeListTemplate() -> CPListTemplate {
        let cameras = camerasWithDistance().prefix(20)
        let cameraItems: [CPListItem] = cameras.map { item in
            let name = item.camera.operatorName ?? item.camera.brand ?? "ALPR Camera"
            let dist = formatDistance(item.distance)
            let listItem = CPListItem(text: name, detailText: "\(dist) away")
            listItem.handler = { [weak self] _, completion in
                let coord = CLLocationCoordinate2D(latitude: item.camera.lat, longitude: item.camera.lon)
                self?.openInMaps(coordinate: coord, name: name)
                completion()
            }
            return listItem
        }

        let section = CPListSection(items: cameraItems.isEmpty ? [CPListItem(text: "No cameras loaded", detailText: "Pull to refresh")] : Array(cameraItems))
        let template = CPListTemplate(title: "Nearby ALPR Cameras", sections: [section])
        template.tabImage = UIImage(systemName: "eye.fill")
        template.tabTitle = "FlockSpot GPS"

        template.leadingNavigationBarButtons = [
            CPBarButton(title: "Refresh") { [weak self] _ in
                self?.refreshFromOverpass()
            }
        ]

        return template
    }

    private func openInMaps(coordinate: CLLocationCoordinate2D, name: String) {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    // MARK: - Helpers

    private func camerasWithDistance() -> [(camera: SharedCameraEntry, distance: CLLocationDistance)] {
        guard let location = userLocation else {
            return cameras.map { (camera: $0, distance: 0) }
        }
        return cameras.map { cam in
            let camLoc = CLLocation(latitude: cam.lat, longitude: cam.lon)
            return (camera: cam, distance: location.distance(from: camLoc))
        }.sorted { $0.distance < $1.distance }
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 1609 {
            return String(format: "%.0f ft", meters * 3.28084)
        } else {
            return String(format: "%.1f mi", meters / 1609.34)
        }
    }

    // MARK: - Cache

    private func loadFromSharedCache() {
        guard let defaults = UserDefaults(suiteName: "group.com.flocksafety.FlockSpot"),
              let data = defaults.data(forKey: "shared_cameras"),
              let decoded = try? JSONDecoder().decode([SharedCameraEntry].self, from: data) else {
            return
        }
        cameras = decoded
    }

    // MARK: - Location

    private func startLocationUpdates() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyBest
        locationManager?.distanceFilter = 50
        locationManager?.startUpdatingLocation()
    }

    // MARK: - Overpass Fetch

    private func refreshFromOverpass() {
        guard let location = userLocation else { return }

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let r = 10.0 / 111.0

        let query = """
        [out:json][timeout:30];
        node["man_made"="surveillance"]["surveillance:type"="ALPR"](\(lat - r),\(lon - r),\(lat + r),\(lon + r));
        out body;
        """

        var components = URLComponents(string: "https://overpass-api.de/api/interpreter")!
        components.queryItems = [URLQueryItem(name: "data", value: query)]

        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 35

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self,
                  let data = data,
                  let firstChars = String(data: data.prefix(20), encoding: .utf8),
                  !firstChars.contains("<!"),
                  let response = try? JSONDecoder().decode(OverpassResponse.self, from: data) else { return }

            DispatchQueue.main.async {
                self.cameras = response.elements.map { SharedCameraEntry.from(element: $0) }
                self.updateList()
            }
        }.resume()
    }

    private func updateList() {
        interfaceController?.setRootTemplate(makeListTemplate(), animated: false, completion: nil)
    }
}

extension CarPlaySceneDelegate: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        userLocation = location

        // Only rebuild list every 10 seconds to avoid constant redraws
        let now = Date()
        guard now.timeIntervalSince(lastLocationUpdate) > 10 else { return }
        lastLocationUpdate = now

        // Also reload from shared cache in case app wrote new data
        loadFromSharedCache()
        updateList()
    }
}
