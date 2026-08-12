import Foundation
import CoreLocation
import Combine
import WidgetKit

class FlockCameraStore: ObservableObject {
    @Published var cameras: [FlockCamera] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastFetchTime: Date?
    @Published var lastFetchCenter: CLLocation?
    @Published var addedCount: Int = 0
    @Published var removedCount: Int = 0

    private var currentTask: URLSessionDataTask?
    private let defaults = UserDefaults.standard
    private let cacheKey = "cached_cameras"

    static let overpassURL = "https://overpass-api.de/api/interpreter"
    static let searchRadiusKm: Double = 10
    static let staleThresholdSeconds: TimeInterval = 1200 // 20 minutes

    struct CachedData: Codable {
        let cameras: [FlockCamera]
        let centerLat: Double
        let centerLon: Double
        let fetchedAt: TimeInterval
    }

    init() {
        loadFromDiskCache()
    }

    // MARK: - Public API

    func loadCameras(for location: CLLocation, force: Bool = false) {
        currentTask?.cancel()

        let center = snapToGrid(location, gridDegrees: 0.1)

        if !force, let lastFetch = lastFetchCenter, let lastTime = lastFetchTime {
            let distance = lastFetch.distance(from: center)
            let elapsed = Date().timeIntervalSince(lastTime)
            if distance < 5000 && elapsed < Self.staleThresholdSeconds && !cameras.isEmpty {
                return
            }
        }

        isLoading = true
        error = nil

        fetchCameras(at: center, radiusKm: Self.searchRadiusKm) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.error = "Failed to fetch cameras: \(error.localizedDescription)"
                }
            case .success(let fetchedCameras):
                let oldIds = Set(self.cameras.map(\.osmId))
                let newIds = Set(fetchedCameras.map(\.osmId))
                let addedCount = newIds.subtracting(oldIds).count
                let removedCount = oldIds.subtracting(newIds).count

                let cached = CachedData(
                    cameras: fetchedCameras,
                    centerLat: center.coordinate.latitude,
                    centerLon: center.coordinate.longitude,
                    fetchedAt: Date().timeIntervalSince1970
                )
                let cachedData = try? JSONEncoder().encode(cached)

                DispatchQueue.main.async {
                    self.addedCount = addedCount
                    self.removedCount = removedCount
                    self.cameras = fetchedCameras
                    self.lastFetchCenter = center
                    self.lastFetchTime = Date()
                    self.isLoading = false
                    self.error = nil

                    if let data = cachedData {
                        self.defaults.set(data, forKey: self.cacheKey)
                    }

                    if let loc = LocationManager.shared?.currentLocation,
                       let heading = LocationManager.shared?.heading?.magneticHeading {
                        SharedCameraData.save(cameras: fetchedCameras, location: loc, heading: heading)
                    }

                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
    }

    // MARK: - Route Corridor Loading

    func loadCamerasAlongRoute(polyline: [CLLocationCoordinate2D], completion: (() -> Void)? = nil) {
        let sampleInterval: Double = 8000 // meters
        let radiusKm: Double = 10

        var samplePoints: [CLLocation] = []
        var accumulated: Double = 0
        var previous: CLLocation?

        for coord in polyline {
            let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            if let prev = previous {
                accumulated += loc.distance(from: prev)
                if accumulated >= sampleInterval {
                    samplePoints.append(loc)
                    accumulated = 0
                }
            } else {
                samplePoints.append(loc)
            }
            previous = loc
        }
        if let last = previous, samplePoints.last.map({ $0.distance(from: last) > sampleInterval / 4 }) ?? true {
            samplePoints.append(last)
        }

        guard !samplePoints.isEmpty else {
            completion?()
            return
        }

        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: 2)
        var allCameras: [FlockCamera] = []
        let lock = NSLock()

        for point in samplePoints {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                semaphore.wait()
                self.fetchCameras(at: point, radiusKm: radiusKm) { result in
                    if case .success(let cameras) = result {
                        lock.lock()
                        allCameras.append(contentsOf: cameras)
                        lock.unlock()
                    }
                    semaphore.signal()
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else {
                completion?()
                return
            }
            let uniqueById = Dictionary(grouping: allCameras, by: { $0.osmId }).compactMap { $0.value.first }
            let existingIds = Set(self.cameras.map(\.osmId))
            let newCameras = uniqueById.filter { !existingIds.contains($0.osmId) }
            if !newCameras.isEmpty {
                self.cameras.append(contentsOf: newCameras)
                self.saveToDiskCache()
                if let loc = LocationManager.shared?.currentLocation,
                   let heading = LocationManager.shared?.heading?.magneticHeading {
                    SharedCameraData.save(cameras: self.cameras, location: loc, heading: heading)
                }
                WidgetCenter.shared.reloadAllTimelines()
            }
            completion?()
        }
    }

    // MARK: - Network

    private func fetchCameras(at location: CLLocation, radiusKm: Double, completion: @escaping (Result<[FlockCamera], Error>) -> Void) {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let r = radiusKm / 111.0

        let south = lat - r
        let north = lat + r
        let west = lon - r
        let east = lon + r

        let query = """
        [out:json][timeout:30];
        node["man_made"="surveillance"]["surveillance:type"="ALPR"](\(south),\(west),\(north),\(east));
        out body;
        """

        var components = URLComponents(string: Self.overpassURL)!
        components.queryItems = [URLQueryItem(name: "data", value: query)]

        guard let url = components.url else {
            completion(.failure(NSError(domain: "FlockCameraStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid query URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("FlockSpot GPS/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 35

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                if (error as NSError).code == NSURLErrorCancelled {
                    return
                }
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: "FlockCameraStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }

            if let firstBytes = String(data: data.prefix(50), encoding: .utf8),
               firstBytes.contains("<!DOCTYPE") || firstBytes.contains("<html") {
                completion(.failure(NSError(domain: "FlockCameraStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Rate limit or error page"])))
                return
            }

            do {
                let overpassResponse = try JSONDecoder().decode(OverpassResponse.self, from: data)
                let fetchedCameras = overpassResponse.elements.compactMap { FlockCamera.from(overpassElement: $0) }
                completion(.success(fetchedCameras))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func refresh(forceLocation: CLLocation?) {
        guard let location = forceLocation ?? lastFetchCenter else { return }
        loadCameras(for: location, force: true)
    }

    func cameras(near location: CLLocation, radiusInMiles: Double) -> [FlockCamera] {
        let radiusInMeters = radiusInMiles * 1609.34
        return cameras.filter { camera in
            let distance = location.distance(from: camera.location)
            return distance <= radiusInMeters
        }
    }

    func nearestCamera(to location: CLLocation) -> FlockCamera? {
        cameras.min(by: { a, b in
            location.distance(from: a.location) < location.distance(from: b.location)
        })
    }

    func distance(to camera: FlockCamera, from location: CLLocation) -> CLLocationDistance {
        location.distance(from: camera.location)
    }

    func bearing(to camera: FlockCamera, from location: CLLocation) -> Double {
        let lat1 = location.coordinate.latitude.radians
        let lon1 = location.coordinate.longitude.radians
        let lat2 = camera.coordinate.latitude.radians
        let lon2 = camera.coordinate.longitude.radians

        let dLon = lon2 - lon1

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)

        let bearing = atan2(y, x).degrees
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    // MARK: - Disk Cache

    private func saveToDiskCache() {
        guard let center = lastFetchCenter else { return }
        let cached = CachedData(
            cameras: cameras,
            centerLat: center.coordinate.latitude,
            centerLon: center.coordinate.longitude,
            fetchedAt: Date().timeIntervalSince1970
        )
        if let data = try? JSONEncoder().encode(cached) {
            defaults.set(data, forKey: cacheKey)
        }
    }

    private func loadFromDiskCache() {
        guard let data = defaults.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(CachedData.self, from: data) else {
            return
        }

        let age = Date().timeIntervalSince1970 - cached.fetchedAt
        guard age < Self.staleThresholdSeconds else { return }

        cameras = cached.cameras
        lastFetchCenter = CLLocation(latitude: cached.centerLat, longitude: cached.centerLon)
        lastFetchTime = Date(timeIntervalSince1970: cached.fetchedAt)
    }

    func clearCache() {
        cameras = []
        lastFetchCenter = nil
        lastFetchTime = nil
        addedCount = 0
        removedCount = 0
        defaults.removeObject(forKey: cacheKey)
    }

    // MARK: - Helpers

    private func snapToGrid(_ location: CLLocation, gridDegrees: Double) -> CLLocation {
        let lat = (location.coordinate.latitude / gridDegrees).rounded() * gridDegrees
        let lon = (location.coordinate.longitude / gridDegrees).rounded() * gridDegrees
        return CLLocation(latitude: lat, longitude: lon)
    }
}

extension Double {
    var radians: Double {
        self * .pi / 180
    }

    var degrees: Double {
        self * 180 / .pi
    }
}
