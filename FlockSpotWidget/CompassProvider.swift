import WidgetKit
import SwiftUI
import CoreLocation

struct CompassProvider: TimelineProvider {
    func placeholder(in context: Context) -> CompassEntry {
        CompassEntry(date: Date(), camera: nil, heading: 0, distance: nil, bearing: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (CompassEntry) -> Void) {
        let cached = Self.loadFromCache()
        completion(cached)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CompassEntry>) -> Void) {
        let entry = Self.loadFromCache()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 1, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private static func loadFromCache() -> CompassEntry {
        guard let defaults = UserDefaults(suiteName: "group.com.flocksafety.FlockSpot") else {
            return CompassEntry(date: Date(), camera: nil, heading: 0, distance: nil, bearing: 0)
        }

        let heading = defaults.double(forKey: "shared_heading")
        let userLat = defaults.double(forKey: "shared_user_lat")
        let userLon = defaults.double(forKey: "shared_user_lon")
        let userLoc = CLLocation(latitude: userLat, longitude: userLon)

        guard let data = defaults.data(forKey: "shared_cameras"),
              let cameras = try? JSONDecoder().decode([SharedCameraEntry].self, from: data),
              !cameras.isEmpty else {
            return CompassEntry(date: Date(), camera: nil, heading: heading, distance: nil, bearing: 0)
        }

        var nearest: SharedCameraEntry?
        var nearestDist: Double = .infinity

        for cam in cameras {
            let camLoc = CLLocation(latitude: cam.lat, longitude: cam.lon)
            let dist = userLoc.distance(from: camLoc)
            if dist < nearestDist {
                nearestDist = dist
                nearest = cam
            }
        }

        guard let camera = nearest else {
            return CompassEntry(date: Date(), camera: nil, heading: heading, distance: nil, bearing: 0)
        }

        let bearingToCamera = bearing(from: userLoc, to: CLLocation(latitude: camera.lat, longitude: camera.lon))

        return CompassEntry(
            date: Date(),
            camera: camera,
            heading: heading,
            distance: nearestDist,
            bearing: bearingToCamera
        )
    }

    private static func bearing(from: CLLocation, to: CLLocation) -> Double {
        let lat1 = from.coordinate.latitude * .pi / 180
        let lon1 = from.coordinate.longitude * .pi / 180
        let lat2 = to.coordinate.latitude * .pi / 180
        let lon2 = to.coordinate.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

struct CompassEntry: TimelineEntry {
    let date: Date
    let camera: SharedCameraEntry?
    let heading: Double
    let distance: Double?
    let bearing: Double
}

struct SharedCameraEntry: Codable {
    let osmId: Int
    let lat: Double
    let lon: Double
    let operatorName: String?
    let brand: String?
}
