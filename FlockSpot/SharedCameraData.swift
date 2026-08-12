import Foundation
import CoreLocation

struct SharedCameraEntry: Codable {
    let osmId: Int
    let lat: Double
    let lon: Double
    let operatorName: String?
    let brand: String?

    static func from(element: OverpassElement) -> SharedCameraEntry {
        SharedCameraEntry(
            osmId: element.id,
            lat: element.lat,
            lon: element.lon,
            operatorName: element.tags?["operator"],
            brand: element.tags?["brand"] ?? element.tags?["manufacturer"]
        )
    }
}

struct SharedCameraData {
    static let appGroupID = "group.com.flocksafety.FlockSpot"
    static let camerasKey = "shared_cameras"
    static let userLatKey = "shared_user_lat"
    static let userLonKey = "shared_user_lon"
    static let headingKey = "shared_heading"
    static let timestampKey = "shared_timestamp"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func save(cameras: [FlockCamera], location: CLLocation?, heading: Double) {
        guard let defaults = sharedDefaults else { return }

        let entries = cameras.map { cam in
            SharedCameraEntry(
                osmId: cam.osmId,
                lat: cam.lat,
                lon: cam.lon,
                operatorName: cam.operatorName,
                brand: cam.brand
            )
        }

        let encoder = JSONEncoder()
        if let data = try? encoder.encode(entries) {
            defaults.set(data, forKey: camerasKey)
        }

        if let location = location {
            defaults.set(location.coordinate.latitude, forKey: userLatKey)
            defaults.set(location.coordinate.longitude, forKey: userLonKey)
        }

        defaults.set(heading, forKey: headingKey)
        defaults.set(Date().timeIntervalSince1970, forKey: timestampKey)
    }

    static func loadCameras() -> [SharedCameraEntry] {
        guard let defaults = sharedDefaults,
              let data = defaults.data(forKey: camerasKey) else { return [] }
        return (try? JSONDecoder().decode([SharedCameraEntry].self, from: data)) ?? []
    }

    static func loadUserLocation() -> CLLocation? {
        guard let defaults = sharedDefaults,
              defaults.object(forKey: userLatKey) != nil else { return nil }
        let lat = defaults.double(forKey: userLatKey)
        let lon = defaults.double(forKey: userLonKey)
        return CLLocation(latitude: lat, longitude: lon)
    }

    static func loadHeading() -> Double {
        sharedDefaults?.double(forKey: headingKey) ?? 0
    }
}
