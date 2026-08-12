import Foundation
import CoreLocation

struct FlockCamera: Identifiable, Codable {
    let osmId: Int
    let lat: Double
    let lon: Double
    let operatorName: String?
    let brand: String?
    let direction: Double?
    let mountType: String?
    let cameraType: String?
    let surveillanceZone: String?
    let ref: String?

    var id: String { "osm-\(osmId)" }

    static let defaultFovDegrees: Double = 70

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var location: CLLocation {
        CLLocation(latitude: lat, longitude: lon)
    }

    var directionDegrees: Double {
        direction ?? 0
    }

    var fovDegrees: Double {
        FlockCamera.defaultFovDegrees
    }

    var displayName: String {
        operatorName ?? brand ?? "Unknown Camera"
    }

    func fovConeVertices(radiusMeters: Double = 200) -> [CLLocationCoordinate2D] {
        let centerLat = lat.radians
        let centerLon = lon.radians
        let earthRadius = 6371000.0

        let startBearing = (directionDegrees - fovDegrees / 2.0).radians
        let endBearing = (directionDegrees + fovDegrees / 2.0).radians

        var vertices: [CLLocationCoordinate2D] = []
        vertices.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))

        let segments = 32
        for i in 0...segments {
            let bearing = startBearing + (endBearing - startBearing) * Double(i) / Double(segments)
            let vertexLat = asin(sin(centerLat) * cos(radiusMeters / earthRadius) +
                           cos(centerLat) * sin(radiusMeters / earthRadius) * cos(bearing))
            let vertexLon = centerLon + atan2(sin(bearing) * sin(radiusMeters / earthRadius) * cos(centerLat),
                                        cos(radiusMeters / earthRadius) - sin(centerLat) * sin(vertexLat))
            vertices.append(CLLocationCoordinate2D(latitude: vertexLat.degrees, longitude: vertexLon.degrees))
        }

        return vertices
    }
}

struct OverpassResponse: Codable {
    let elements: [OverpassElement]
}

struct OverpassElement: Codable {
    let type: String
    let id: Int
    let lat: Double
    let lon: Double
    let tags: [String: String]?
}

extension FlockCamera {
    static func from(overpassElement element: OverpassElement) -> FlockCamera? {
        guard element.type == "node" else { return nil }
        let tags = element.tags ?? [:]

        let directionValue: Double?
        if let dirStr = tags["direction"], let dir = Double(dirStr) {
            directionValue = dir
        } else {
            directionValue = nil
        }

        return FlockCamera(
            osmId: element.id,
            lat: element.lat,
            lon: element.lon,
            operatorName: tags["operator"],
            brand: tags["brand"] ?? tags["manufacturer"],
            direction: directionValue,
            mountType: tags["camera:mount"],
            cameraType: tags["camera:type"],
            surveillanceZone: tags["surveillance:zone"],
            ref: tags["ref"]
        )
    }
}
