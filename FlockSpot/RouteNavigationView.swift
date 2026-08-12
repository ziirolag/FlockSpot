import SwiftUI
import MapKit
import CoreLocation
import AVFoundation

struct RouteNavigationView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var cameraStore: FlockCameraStore

    @State private var destinationText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var route: NavigationRoute?
    @State private var isCalculating = false
    @State private var errorMessage: String?
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )

    @State private var isNavigating = false
    @State private var isFollowingUser = true
    @State private var currentManeuverIndex = 0
    @State private var remainingDistanceMeters: Double = 0
    @State private var remainingTimeSeconds: Double = 0
    @State private var lastRerouteTime: Date?

    private let speechSynthesizer = AVSpeechSynthesizer()

    var body: some View {
        ZStack(alignment: .bottom) {
            routeMap
                .ignoresSafeArea()

            VStack(spacing: 12) {
                if isNavigating {
                    navigationTopCard
                } else {
                    searchBarCard
                }

                if errorMessage != nil {
                    errorBanner
                }

                Spacer()

                if !isFollowingUser {
                    recenterButton
                        .padding(.bottom, 12)
                }

                bottomSheet
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            if isCalculating {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    Spacer()
                }
            }
        }
        .onAppear {
            if let location = locationManager.currentLocation {
                region = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            }
        }
        .onReceive(locationManager.$currentLocation) { location in
            guard isNavigating, let location = location, let route = route else { return }
            updateNavigationProgress(location: location, route: route)
        }
    }

    // MARK: - Map

    private var routeMap: some View {
        RouteMapView(
            route: route,
            isNavigating: isNavigating,
            isFollowingUser: $isFollowingUser,
            cameras: cameraStore.cameras,
            region: $region
        )
        .environmentObject(locationManager)
    }

    // MARK: - Search Bar

    private var searchBarCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.title3)
                .foregroundColor(.blue)

            TextField("Where to?", text: $destinationText)
                .font(.body)
                .submitLabel(.route)
                .onSubmit(searchDestinations)

            Button(action: searchDestinations) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .disabled(destinationText.isEmpty || locationManager.currentLocation == nil)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }

    // MARK: - Navigation Top Card

    private var navigationTopCard: some View {
        HStack(spacing: 12) {
            if let maneuver = currentManeuver {
                Image(systemName: maneuverIcon(for: maneuver.instruction))
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(maneuver.instruction)
                        .font(.headline)
                        .lineLimit(2)
                    if let dist = distanceToManeuver(maneuver) {
                        Text(dist)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            Button(action: endNavigation) {
                Image(systemName: "xmark")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(.regularMaterial)
                    .clipShape(Circle())
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }

    private var recenterButton: some View {
        Button {
            recenter()
        } label: {
            Image(systemName: "location.fill")
                .font(.title2)
                .foregroundColor(.blue)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .shadow(radius: 4)
        }
    }

    // MARK: - Error Banner

    private var errorBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(errorMessage ?? "")
                .font(.caption)
                .foregroundColor(.primary)
            Spacer()
            Button {
                errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    // MARK: - Bottom Sheet

    private var bottomSheet: some View {
        VStack(spacing: 0) {
            if !searchResults.isEmpty {
                searchResultsContent
            } else if let route = route {
                if isNavigating {
                    navigationStatusContent(route: route)
                } else {
                    routePreviewContent(route: route)
                }
            } else {
                emptyPromptContent
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .cornerRadius(24)
    }

    private var emptyPromptContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                .font(.largeTitle)
                .foregroundColor(.blue.opacity(0.8))
            Text("Enter a destination")
                .font(.headline)
            Text("Search for an address, then choose a result to preview the camera-safe route.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
    }

    private var searchResultsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Choose a destination")
                    .font(.headline)
                Spacer()
                Text("\(searchResults.count) found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(searchResults.enumerated()), id: \.offset) { index, item in
                        Button {
                            selectDestination(item)
                        } label: {
                            searchResultRow(item: item, index: index)
                        }
                        if index < searchResults.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxHeight: 280)
        }
    }

    private func searchResultRow(item: MKMapItem, index: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.blue))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name ?? "Unknown")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if let subtitle = item.placemark.title {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let distance = distanceToUser(item) {
                Text(distance)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func routePreviewContent(route: NavigationRoute) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(formatDistance(route.distanceMeters)) · \(formatTime(route.timeSeconds))")
                        .font(.title3)
                        .fontWeight(.bold)
                    if route.avoidedCameras.count > 0 {
                        Label("\(route.avoidedCameras.count) camera\(route.avoidedCameras.count == 1 ? "" : "s") avoided", systemImage: "checkmark.shield")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("No cameras on route", systemImage: "checkmark.shield")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button {
                    clearRoute()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(.regularMaterial)
                        .clipShape(Circle())
                }
            }

            Button {
                startNavigation(route: route)
            } label: {
                HStack {
                    Image(systemName: "location.fill")
                    Text("Go")
                        .fontWeight(.bold)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(16)
            }
        }
    }

    private func navigationStatusContent(route: NavigationRoute) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let next = nextManeuver(in: route) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.turn.up.right")
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Then")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(next.instruction)
                            .font(.headline)
                            .lineLimit(2)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "flag.checkered")
                        .font(.title2)
                        .foregroundColor(.green)
                        .frame(width: 44)

                    Text("Arriving at destination")
                        .font(.headline)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(formatDistance(remainingDistanceMeters)) remaining")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("\(formatTime(remainingTimeSeconds)) to destination")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    endNavigation()
                } label: {
                    Text("End")
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.15))
                        .cornerRadius(12)
                }
            }
        }
    }

    // MARK: - Helpers

    private var currentManeuver: NavigationManeuver? {
        guard let route = route, currentManeuverIndex < route.maneuvers.count else { return nil }
        return route.maneuvers[currentManeuverIndex]
    }

    private func nextManeuver(in route: NavigationRoute) -> NavigationManeuver? {
        let nextIndex = currentManeuverIndex + 1
        guard nextIndex < route.maneuvers.count else { return nil }
        return route.maneuvers[nextIndex]
    }

    private func distanceToManeuver(_ maneuver: NavigationManeuver) -> String? {
        guard let location = locationManager.currentLocation else { return nil }
        let maneuverLocation = CLLocation(latitude: maneuver.coordinate.latitude, longitude: maneuver.coordinate.longitude)
        return formatDistance(location.distance(from: maneuverLocation))
    }

    private func distanceToUser(_ item: MKMapItem) -> String? {
        guard let userLocation = locationManager.currentLocation else { return nil }
        let itemLocation = CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
        return formatDistance(userLocation.distance(from: itemLocation))
    }

    private func maneuverIcon(for instruction: String) -> String {
        let lower = instruction.lowercased()
        if lower.contains("left") { return "arrow.turn.up.left" }
        if lower.contains("right") { return "arrow.turn.up.right" }
        if lower.contains("uturn") || lower.contains("u-turn") { return "arrow.uturn.up" }
        if lower.contains("roundabout") || lower.contains("rotary") { return "arrow.triangle.2.circlepath" }
        if lower.contains("merge") { return "arrow.merge.right" }
        if lower.contains("exit") || lower.contains("ramp") { return "arrow.right.square" }
        if lower.contains("destination") { return "mappin.circle.fill" }
        return "arrow.up"
    }

    // MARK: - Actions

    private func searchDestinations() {
        guard let userLocation = locationManager.currentLocation else {
            errorMessage = "Current location unavailable"
            return
        }
        isCalculating = true
        errorMessage = nil
        clearRoute()

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = destinationText
        request.region = MKCoordinateRegion(
            center: userLocation.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
        )
        request.resultTypes = [.address, .pointOfInterest]

        let search = MKLocalSearch(request: request)
        search.start { response, error in
            DispatchQueue.main.async {
                self.isCalculating = false
                guard let response = response else {
                    self.errorMessage = error?.localizedDescription ?? "No search results"
                    return
                }
                let sorted = response.mapItems.sorted { a, b in
                    let locA = CLLocation(latitude: a.placemark.coordinate.latitude, longitude: a.placemark.coordinate.longitude)
                    let locB = CLLocation(latitude: b.placemark.coordinate.latitude, longitude: b.placemark.coordinate.longitude)
                    return userLocation.distance(from: locA) < userLocation.distance(from: locB)
                }
                self.searchResults = sorted
            }
        }
    }

    private func selectDestination(_ item: MKMapItem) {
        guard let userLocation = locationManager.currentLocation else { return }
        searchResults = []
        isCalculating = true
        fetchCameraAvoidingRoute(from: userLocation.coordinate, to: item.placemark.coordinate)
    }

    private func clearRoute() {
        route = nil
        isNavigating = false
        isFollowingUser = true
        currentManeuverIndex = 0
        remainingDistanceMeters = 0
        remainingTimeSeconds = 0
    }

    private func startNavigation(route: NavigationRoute) {
        isNavigating = true
        isFollowingUser = true
        currentManeuverIndex = 0
        remainingDistanceMeters = route.distanceMeters
        remainingTimeSeconds = route.timeSeconds
        if let location = locationManager.currentLocation {
            region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
        if let maneuver = route.maneuvers.first {
            speak(maneuver.instruction)
        }
    }

    private func endNavigation() {
        isNavigating = false
        isFollowingUser = true
        currentManeuverIndex = 0
        route = nil
        searchResults = []
        remainingDistanceMeters = 0
        remainingTimeSeconds = 0
        if let location = locationManager.currentLocation {
            region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
    }

    private func updateNavigationProgress(location: CLLocation, route: NavigationRoute) {
        let distanceFromRoute = route.polyline.minDistance(to: location)
        if distanceFromRoute > 150 {
            let now = Date()
            if lastRerouteTime == nil || now.timeIntervalSince(lastRerouteTime!) > 10 {
                lastRerouteTime = now
                speak("Recalculating")
                fetchCameraAvoidingRoute(from: location.coordinate, to: route.destination)
            }
            return
        }

        var advanced = false
        while currentManeuverIndex < route.maneuvers.count {
            let maneuver = route.maneuvers[currentManeuverIndex]
            let maneuverLocation = CLLocation(latitude: maneuver.coordinate.latitude, longitude: maneuver.coordinate.longitude)
            if location.distance(from: maneuverLocation) < 50 {
                currentManeuverIndex += 1
                advanced = true
            } else {
                break
            }
        }

        var remainingDistance = route.distanceMeters
        var remainingTime = route.timeSeconds
        for i in 0..<currentManeuverIndex {
            remainingDistance -= route.maneuvers[i].distanceMeters
            remainingTime -= route.maneuvers[i].timeSeconds
        }
        remainingDistanceMeters = max(remainingDistance, 0)
        remainingTimeSeconds = max(remainingTime, 0)

        if isFollowingUser, let location = locationManager.currentLocation {
            withAnimation {
                region = MKCoordinateRegion(
                    center: location.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            }
        }

        if advanced, let maneuver = currentManeuver {
            speak(maneuver.instruction)
        }
    }

    private func speak(_ text: String) {
        speechSynthesizer.stopSpeaking(at: .word)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speechSynthesizer.speak(utterance)
    }

    private func recenter() {
        isFollowingUser = true
        if isNavigating, let location = locationManager.currentLocation {
            region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        } else if let route = route {
            region = route.region
        } else if let location = locationManager.currentLocation {
            region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }
    }

    private func fetchCameraAvoidingRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) {
        ValhallaRouter.fetchRoute(from: from, to: to, excludePolygons: []) { result in
            switch result {
            case .failure(let error):
                self.fetchAppleDirections(from: from, to: to) { route in
                    DispatchQueue.main.async {
                        self.isCalculating = false
                        if let route = route {
                            self.route = route
                            self.region = route.region
                            self.errorMessage = "Camera avoidance unavailable; showing standard route"
                        } else {
                            self.errorMessage = error.localizedDescription
                        }
                    }
                }
            case .success(let initialRoute):
                // Fetch any cameras missing from the route corridor, then re-route around them
                self.cameraStore.loadCamerasAlongRoute(polyline: initialRoute.polyline) {
                    DispatchQueue.main.async {
                        let nearCameras = self.camerasNearRoute(initialRoute, maxDistance: 100)
                        guard !nearCameras.isEmpty else {
                            self.isCalculating = false
                            self.route = initialRoute
                            self.region = initialRoute.region
                            self.isFollowingUser = true
                            return
                        }

                        let sortedCameras = nearCameras.sorted { a, b in
                            initialRoute.polyline.minDistance(to: a.location) < initialRoute.polyline.minDistance(to: b.location)
                        }
                        let limitedCameras = Array(sortedCameras.prefix(15))
                        let polygons = limitedCameras.map { self.exclusionPolygon(around: $0, radiusMeters: 100) }

                        ValhallaRouter.fetchRoute(from: from, to: to, excludePolygons: polygons) { result in
                            DispatchQueue.main.async {
                                self.isCalculating = false
                                switch result {
                                case .failure:
                                    self.route = initialRoute
                                    self.region = initialRoute.region
                                    self.isFollowingUser = true
                                    self.errorMessage = "Could not avoid all cameras; showing best route"
                                case .success(let finalRoute):
                                    let finalCameras = self.camerasNearRoute(finalRoute, maxDistance: 100)
                                    var updated = finalRoute
                                    updated.avoidedCameras = limitedCameras.filter { cam in
                                        !finalCameras.contains(where: { $0.id == cam.id })
                                    }
                                    self.route = updated
                                    self.region = updated.region
                                    self.isFollowingUser = true
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func fetchAppleDirections(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, completion: @escaping (NavigationRoute?) -> Void) {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            guard let mapRoute = response?.routes.first else {
                completion(nil)
                return
            }
            let coords = mapRoute.polyline.coordinates
            let maneuvers = mapRoute.steps.map { step in
                let stepCoords = step.polyline.coordinates
                let coordinate = stepCoords.last ?? coords.last ?? to
                return NavigationManeuver(
                    instruction: step.instructions,
                    coordinate: coordinate,
                    distanceMeters: step.distance,
                    timeSeconds: 0
                )
            }
            let region = MKCoordinateRegion(polyline: coords, paddingFactor: 1.4)
            let route = NavigationRoute(
                polyline: coords,
                maneuvers: maneuvers,
                distanceMeters: mapRoute.distance,
                timeSeconds: mapRoute.expectedTravelTime,
                region: region,
                destination: to
            )
            completion(route)
        }
    }

    private func camerasNearRoute(_ route: NavigationRoute, maxDistance: CLLocationDistance) -> [FlockCamera] {
        cameraStore.cameras.filter { camera in
            route.polyline.minDistance(to: camera.location) <= maxDistance
        }
    }

    private func exclusionPolygon(around camera: FlockCamera, radiusMeters: Double) -> [[Double]] {
        let coords = squareCoordinates(around: camera.coordinate, radiusMeters: radiusMeters)
        return coords.map { [$0.longitude, $0.latitude] }
    }

    private func squareCoordinates(around center: CLLocationCoordinate2D, radiusMeters: Double) -> [CLLocationCoordinate2D] {
        let earthRadius = 6371000.0
        let dLat = (radiusMeters / earthRadius) * (180.0 / .pi)
        let dLon = (radiusMeters / (earthRadius * cos(center.latitude * .pi / 180.0))) * (180.0 / .pi)
        let nw = CLLocationCoordinate2D(latitude: center.latitude + dLat, longitude: center.longitude - dLon)
        let ne = CLLocationCoordinate2D(latitude: center.latitude + dLat, longitude: center.longitude + dLon)
        let se = CLLocationCoordinate2D(latitude: center.latitude - dLat, longitude: center.longitude + dLon)
        let sw = CLLocationCoordinate2D(latitude: center.latitude - dLat, longitude: center.longitude - dLon)
        return [nw, ne, se, sw, nw]
    }
}

// MARK: - Route Model

struct NavigationManeuver: Identifiable {
    let id = UUID()
    let instruction: String
    let coordinate: CLLocationCoordinate2D
    let distanceMeters: Double
    let timeSeconds: Double
}

struct NavigationRoute {
    let polyline: [CLLocationCoordinate2D]
    let maneuvers: [NavigationManeuver]
    let distanceMeters: Double
    let timeSeconds: Double
    let region: MKCoordinateRegion
    let destination: CLLocationCoordinate2D
    var avoidedCameras: [FlockCamera] = []

    var instructions: [String] {
        maneuvers.map(\.instruction)
    }
}

// MARK: - Valhalla Router

enum ValhallaRouter {
    static let endpoint = "https://valhalla1.openstreetmap.de/route"

    static func fetchRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, excludePolygons: [[[Double]]], completion: @escaping (Result<NavigationRoute, Error>) -> Void) {
        performRequest(from: from, to: to, excludePolygons: excludePolygons, attempt: 1, completion: completion)
    }

    private static func performRequest(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, excludePolygons: [[[Double]]], attempt: Int, completion: @escaping (Result<NavigationRoute, Error>) -> Void) {
        guard let url = URL(string: endpoint) else {
            completion(.failure(NSError(domain: "Valhalla", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "locations": [
                ["lat": from.latitude, "lon": from.longitude],
                ["lat": to.latitude, "lon": to.longitude]
            ],
            "costing": "auto",
            "exclude_polygons": excludePolygons,
            "directions_options": [
                "units": "miles",
                "language": "en-US"
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                if attempt < 2 {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                        performRequest(from: from, to: to, excludePolygons: excludePolygons, attempt: attempt + 1, completion: completion)
                    }
                } else {
                    completion(.failure(error))
                }
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "Valhalla", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }

            do {
                let route = try parseRoute(data: data, destination: to)
                completion(.success(route))
            } catch {
                if attempt < 2 {
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                        performRequest(from: from, to: to, excludePolygons: excludePolygons, attempt: attempt + 1, completion: completion)
                    }
                } else {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    private static func parseRoute(data: Data, destination: CLLocationCoordinate2D) throws -> NavigationRoute {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Valhalla", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
        }

        if let error = json["error"] as? String {
            throw NSError(domain: "Valhalla", code: -1, userInfo: [NSLocalizedDescriptionKey: error])
        }

        guard let trip = json["trip"] as? [String: Any] else {
            throw NSError(domain: "Valhalla", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing trip"])
        }

        if let status = trip["status"] as? Int, status != 0 {
            let message = trip["status_message"] as? String ?? "Routing failed (status \(status))"
            throw NSError(domain: "Valhalla", code: status, userInfo: [NSLocalizedDescriptionKey: message])
        }

        guard let legs = trip["legs"] as? [[String: Any]], !legs.isEmpty else {
            throw NSError(domain: "Valhalla", code: -1, userInfo: [NSLocalizedDescriptionKey: "No route legs"])
        }

        var allCoordinates: [CLLocationCoordinate2D] = []
        var maneuvers: [NavigationManeuver] = []

        for (index, leg) in legs.enumerated() {
            guard let shape = leg["shape"] as? String, !shape.isEmpty else {
                throw NSError(domain: "Valhalla", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing route shape"])
            }
            let legCoordinates = decodePolyline(shape, precision: 1e-6)
            if index == 0 {
                allCoordinates.append(contentsOf: legCoordinates)
            } else {
                allCoordinates.append(contentsOf: legCoordinates.dropFirst())
            }

            if let legManeuvers = leg["maneuvers"] as? [[String: Any]] {
                for maneuver in legManeuvers {
                    guard let instruction = maneuver["instruction"] as? String, !instruction.isEmpty else { continue }
                    let endIndex = maneuver["end_shape_index"] as? Int ?? (legCoordinates.count - 1)
                    let safeIndex = min(max(endIndex, 0), legCoordinates.count - 1)
                    let coordinate = legCoordinates[safeIndex]
                    let lengthMiles = maneuver["length"] as? Double ?? 0
                    let time = maneuver["time"] as? Double ?? 0
                    maneuvers.append(NavigationManeuver(
                        instruction: instruction,
                        coordinate: coordinate,
                        distanceMeters: lengthMiles * 1609.34,
                        timeSeconds: time
                    ))
                }
            }
        }

        guard !allCoordinates.isEmpty else {
            throw NSError(domain: "Valhalla", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty route shape"])
        }

        let summary = trip["summary"] as? [String: Any]
        let lengthMiles = summary?["length"] as? Double ?? 0
        let timeSeconds = summary?["time"] as? Double ?? 0
        let distanceMeters = lengthMiles * 1609.34

        let region = MKCoordinateRegion(polyline: allCoordinates, paddingFactor: 1.4)

        return NavigationRoute(
            polyline: allCoordinates,
            maneuvers: maneuvers,
            distanceMeters: distanceMeters,
            timeSeconds: timeSeconds,
            region: region,
            destination: destination
        )
    }
}

// MARK: - Map View

struct RouteMapView: UIViewRepresentable {
    @EnvironmentObject var locationManager: LocationManager
    var route: NavigationRoute?
    var isNavigating: Bool
    @Binding var isFollowingUser: Bool
    var cameras: [FlockCamera]
    @Binding var region: MKCoordinateRegion

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.mapType = .mutedStandard
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let currentRegion = mapView.region
        let centerDiff = abs(region.center.latitude - currentRegion.center.latitude)
            + abs(region.center.longitude - currentRegion.center.longitude)
        let spanDiff = abs(region.span.latitudeDelta - currentRegion.span.latitudeDelta)
            + abs(region.span.longitudeDelta - currentRegion.span.longitudeDelta)
        let needsCameraUpdate = centerDiff > 0.0005 || spanDiff > 0.0005

        if needsCameraUpdate {
            context.coordinator.isProgrammaticChange = true
            let spanMeters = max(region.span.latitudeDelta, region.span.longitudeDelta) * 111320
            let distance = max(spanMeters * 1.5, 200)
            let camera = MKMapCamera(
                lookingAtCenter: region.center,
                fromDistance: distance,
                pitch: isNavigating ? 0 : 45,
                heading: 0
            )
            mapView.setCamera(camera, animated: true)
        }

        let existingRoute = mapView.overlays.compactMap { $0 as? MKPolyline }
        mapView.removeOverlays(existingRoute)

        if let route = route, route.polyline.count > 1 {
            let polyline = MKPolyline(coordinates: route.polyline, count: route.polyline.count)
            mapView.addOverlay(polyline)
        }

        let existingAnnotations = mapView.annotations.compactMap { $0 as? CameraAnnotation }
        let newAnnotations = cameras.map { CameraAnnotation(camera: $0) }
        if existingAnnotations.count != newAnnotations.count ||
            Set(existingAnnotations.map(\.id)) != Set(newAnnotations.map(\.id)) {
            mapView.removeAnnotations(existingAnnotations)
            mapView.addAnnotations(newAnnotations)
        }
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: RouteMapView
        var isProgrammaticChange = false

        init(_ parent: RouteMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if !isProgrammaticChange {
                parent.isFollowingUser = false
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if !isProgrammaticChange {
                parent.region = mapView.region
            }
            isProgrammaticChange = false
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = parent.isNavigating ? .systemBlue : .systemBlue.withAlphaComponent(0.8)
                renderer.lineWidth = parent.isNavigating ? 6 : 5
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let cameraAnnotation = annotation as? CameraAnnotation else { return nil }
            let identifier = "CameraPin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: cameraAnnotation, reuseIdentifier: identifier)
            view.annotation = cameraAnnotation
            view.canShowCallout = true
            view.markerTintColor = .systemRed
            view.glyphImage = UIImage(systemName: "video.fill")
            return view
        }
    }
}

// MARK: - Formatters

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

private func formatTime(_ seconds: Double) -> String {
    let totalMinutes = Int(seconds / 60)
    if totalMinutes < 60 {
        return "\(totalMinutes) min"
    } else {
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours)h \(minutes)m"
    }
}

// MARK: - Polyline Decoding

private func decodePolyline(_ encoded: String, precision: Double = 1e-6) -> [CLLocationCoordinate2D] {
    var coordinates: [CLLocationCoordinate2D] = []
    var index = encoded.startIndex
    var lat = 0
    var lon = 0

    while index < encoded.endIndex {
        var b: Int
        var shift = 0
        var result = 0
        repeat {
            let char = encoded[index]
            index = encoded.index(after: index)
            b = Int(char.asciiValue!) - 63
            result |= (b & 0x1f) << shift
            shift += 5
        } while b >= 0x20
        let dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1))
        lat += dlat

        shift = 0
        result = 0
        repeat {
            let char = encoded[index]
            index = encoded.index(after: index)
            b = Int(char.asciiValue!) - 63
            result |= (b & 0x1f) << shift
            shift += 5
        } while b >= 0x20
        let dlon = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1))
        lon += dlon

        let latitude = Double(lat) * precision
        let longitude = Double(lon) * precision
        coordinates.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    }
    return coordinates
}

// MARK: - Region / Distance Helpers

extension MKCoordinateRegion {
    init(polyline: [CLLocationCoordinate2D], paddingFactor: Double = 1.3) {
        var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0
        for coord in polyline {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * paddingFactor, 0.001),
            longitudeDelta: max((maxLon - minLon) * paddingFactor, 0.001)
        )
        self.init(center: center, span: span)
    }
}

extension Array where Element == CLLocationCoordinate2D {
    func minDistance(to location: CLLocation) -> CLLocationDistance {
        guard count >= 2 else {
            if let first = first {
                return location.distance(from: CLLocation(latitude: first.latitude, longitude: first.longitude))
            }
            return .greatestFiniteMagnitude
        }

        var minDist: CLLocationDistance = .greatestFiniteMagnitude
        for i in 0..<(count - 1) {
            let start = self[i]
            let end = self[i + 1]
            let dist = distanceToSegment(from: location.coordinate, toSegment: (start, end))
            minDist = Swift.min(minDist, dist)
        }
        return minDist
    }
}

private func distanceToSegment(from point: CLLocationCoordinate2D, toSegment segment: (CLLocationCoordinate2D, CLLocationCoordinate2D)) -> CLLocationDistance {
    let a = CLLocation(latitude: segment.0.latitude, longitude: segment.0.longitude)
    let b = CLLocation(latitude: segment.1.latitude, longitude: segment.1.longitude)
    let p = CLLocation(latitude: point.latitude, longitude: point.longitude)

    let d13 = a.distance(from: p)
    let d12 = a.distance(from: b)
    guard d12 > 0 else { return d13 }

    let bearingAP = a.bearing(to: p)
    let bearingAB = a.bearing(to: b)

    let R = 6371000.0
    let crossTrack = asin(sin(d13 / R) * sin((bearingAP - bearingAB).radians)) * R
    let alongTrack = acos(max(-1, min(1, cos(d13 / R) / cos(crossTrack / R)))) * R

    if alongTrack < 0 || alongTrack > d12 || crossTrack.isNaN {
        return Swift.min(d13, b.distance(from: p))
    } else {
        return abs(crossTrack)
    }
}

extension CLLocation {
    func bearing(to destination: CLLocation) -> Double {
        let lat1 = self.coordinate.latitude.radians
        let lon1 = self.coordinate.longitude.radians
        let lat2 = destination.coordinate.latitude.radians
        let lon2 = destination.coordinate.longitude.radians

        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x).degrees
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
