import SwiftUI
import MapKit

struct CameraMapView: UIViewRepresentable {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var cameraStore: FlockCameraStore
    @Binding var selectedCamera: FlockCamera?
    @Binding var showDetail: Bool
    @Binding var region: MKCoordinateRegion

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.setRegion(region, animated: true)

        let existingAnnotations = mapView.annotations.compactMap { $0 as? CameraAnnotation }
        let newAnnotations = cameraStore.cameras.map { CameraAnnotation(camera: $0) }

        if existingAnnotations.count != newAnnotations.count ||
            Set(existingAnnotations.map(\.id)) != Set(newAnnotations.map(\.id)) {
            mapView.removeAnnotations(existingAnnotations)
            mapView.addAnnotations(newAnnotations)
        }

        let existingOverlays = mapView.overlays.compactMap { $0 as? FOVConeOverlay }
        let newOverlays = cameraStore.cameras.compactMap { camera -> FOVConeOverlay? in
            guard camera.direction != nil else { return nil }
            return FOVConeOverlay(camera: camera)
        }

        if existingOverlays.count != newOverlays.count {
            mapView.removeOverlays(existingOverlays)
            mapView.addOverlays(newOverlays)
        }
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: CameraMapView

        init(_ parent: CameraMapView) {
            self.parent = parent
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

            let detailButton = UIButton(type: .detailDisclosure)
            view.rightCalloutAccessoryView = detailButton

            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let coneOverlay = overlay as? FOVConeOverlay {
                let renderer = MKPolygonRenderer(polygon: coneOverlay.polygon)
                renderer.fillColor = UIColor.systemRed.withAlphaComponent(0.2)
                renderer.strokeColor = UIColor.systemRed.withAlphaComponent(0.6)
                renderer.lineWidth = 2
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            guard let cameraAnnotation = view.annotation as? CameraAnnotation else { return }
            parent.selectedCamera = parent.cameraStore.cameras.first(where: { $0.id == cameraAnnotation.id })
            parent.showDetail = true
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.region = mapView.region
        }
    }
}

class CameraAnnotation: NSObject, MKAnnotation {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(camera: FlockCamera) {
        self.id = camera.id
        self.coordinate = camera.coordinate
        self.title = camera.operatorName ?? camera.brand ?? "ALPR Camera"
        var subtitleParts: [String] = []
        if let brand = camera.brand, camera.operatorName != nil {
            subtitleParts.append(brand)
        }
        if let mount = camera.mountType {
            subtitleParts.append(mount.capitalized)
        }
        if camera.direction != nil {
            subtitleParts.append("\(Int(camera.directionDegrees))°")
        }
        self.subtitle = subtitleParts.isEmpty ? "ALPR Camera" : subtitleParts.joined(separator: " · ")
    }
}

class FOVConeOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    let polygon: MKPolygon

    init(camera: FlockCamera) {
        self.coordinate = camera.coordinate

        let vertices = camera.fovConeVertices(radiusMeters: 250)
        self.polygon = MKPolygon(coordinates: vertices, count: vertices.count)
        self.boundingMapRect = polygon.boundingMapRect
    }
}

struct CameraMapViewContainer: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var cameraStore: FlockCameraStore
    @State private var selectedCamera: FlockCamera?
    @State private var showDetail = false
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )

    var body: some View {
        ZStack {
            CameraMapView(
                selectedCamera: $selectedCamera,
                showDetail: $showDetail,
                region: $region
            )
            .ignoresSafeArea()

            VStack {
                if cameraStore.isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading cameras...")
                            .font(.caption)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding(.top, 8)
                }

                if let error = cameraStore.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding(.top, 8)
                }

                Spacer()

                HStack {
                    VStack(alignment: .leading) {
                        Text("\(cameraStore.cameras.count) cameras")
                            .font(.caption)
                            .fontWeight(.bold)
                        Text("in view")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)

                    Spacer()

                    VStack(spacing: 12) {
                        MapControlButton(icon: "location.fill", action: centerOnUser)
                        MapControlButton(icon: "plus", action: zoomIn)
                        MapControlButton(icon: "minus", action: zoomOut)
                    }
                    .padding()
                }

                if let camera = selectedCamera, showDetail {
                    CameraDetailCard(camera: camera, isShowing: $showDetail)
                        .transition(.move(edge: .bottom))
                        .animation(.easeInOut, value: showDetail)
                }
            }
        }
        .onAppear {
            centerOnUser()
        }
    }

    func centerOnUser() {
        guard let location = locationManager.currentLocation else { return }
        region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    }

    func zoomIn() {
        let span = MKCoordinateSpan(
            latitudeDelta: region.span.latitudeDelta * 0.5,
            longitudeDelta: region.span.longitudeDelta * 0.5
        )
        region = MKCoordinateRegion(center: region.center, span: span)
    }

    func zoomOut() {
        let span = MKCoordinateSpan(
            latitudeDelta: min(region.span.latitudeDelta * 2, 1.0),
            longitudeDelta: min(region.span.longitudeDelta * 2, 1.0)
        )
        region = MKCoordinateRegion(center: region.center, span: span)
    }
}

struct CameraDetailCard: View {
    let camera: FlockCamera
    @Binding var isShowing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let op = camera.operatorName {
                        Text(op)
                            .font(.headline)
                    } else if let brand = camera.brand {
                        Text(brand)
                            .font(.headline)
                    } else {
                        Text("Unknown Owner")
                            .font(.headline)
                    }
                    Text("OSM ID: \(camera.osmId)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { isShowing = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
            }

            Divider()

            // Owner section - prominent
            if let op = camera.operatorName {
                HStack(spacing: 10) {
                    Image(systemName: "person.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Owner / Operator")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(op)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }
                .padding(10)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }

            if let brand = camera.brand {
                DetailRow(icon: "tag.fill", label: "Brand", value: brand)
            }

            DetailRow(icon: "video.fill", label: "Type", value: camera.cameraType?.capitalized ?? "ALPR")

            if let mount = camera.mountType {
                DetailRow(icon: "arrow.up.doc.fill", label: "Mount", value: mount.capitalized)
            }

            if let zone = camera.surveillanceZone {
                DetailRow(icon: "mappin.circle.fill", label: "Zone", value: zone.capitalized)
            }

            if camera.direction != nil {
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    Text("Direction")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(camera.directionDegrees))° \(cardinalDirection(camera.directionDegrees))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                HStack {
                    Image(systemName: "scope")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    Text("Field of View")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(camera.fovDegrees))° (estimated)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }

            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(.blue)
                    .frame(width: 24)
                Text("Coordinates")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.5f, %.5f", camera.lat, camera.lon))
                    .font(.caption)
                    .monospacedDigit()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 8)
        .padding(.horizontal)
        .padding(.bottom, 16)
    }

    func cardinalDirection(_ degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees + 22.5) / 45.0) % 8
        return directions[index]
    }
}

struct DetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct MapControlButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .shadow(radius: 3)
        }
    }
}
