import SwiftUI
import MapKit

struct MiniMapView: UIViewRepresentable {
    let cameras: [FlockCamera]
    let userLocation: CLLocation?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.isZoomEnabled = false
        mapView.isScrollEnabled = false
        mapView.isRotateEnabled = false
        mapView.layer.cornerRadius = 10
        mapView.layer.borderWidth = 1
        mapView.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        guard let userLocation = userLocation else { return }

        let region = MKCoordinateRegion(
            center: userLocation.coordinate,
            latitudinalMeters: 800,
            longitudinalMeters: 800
        )
        mapView.setRegion(region, animated: false)

        let existing = mapView.annotations.compactMap { $0 as? CameraAnnotation }
        let newAnnotations = cameras.map { CameraAnnotation(camera: $0) }
        if Set(existing.map(\.id)) != Set(newAnnotations.map(\.id)) {
            mapView.removeAnnotations(existing)
            mapView.addAnnotations(newAnnotations)
        }

        let existingOverlays = mapView.overlays.compactMap { $0 as? FOVConeOverlay }
        let newOverlays = cameras.compactMap { camera -> FOVConeOverlay? in
            guard camera.direction != nil else { return nil }
            return FOVConeOverlay(camera: camera)
        }
        if existingOverlays.count != newOverlays.count {
            mapView.removeOverlays(existingOverlays)
            mapView.addOverlays(newOverlays)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let cam = annotation as? CameraAnnotation else { return nil }

            let id = "MiniCam"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: cam, reuseIdentifier: id)

            view.annotation = cam
            view.canShowCallout = false
            view.markerTintColor = .systemRed
            view.glyphImage = UIImage(systemName: "video.fill")
            view.glyphTintColor = .white
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let cone = overlay as? FOVConeOverlay {
                let renderer = MKPolygonRenderer(polygon: cone.polygon)
                renderer.fillColor = UIColor.systemRed.withAlphaComponent(0.2)
                renderer.strokeColor = UIColor.systemRed.withAlphaComponent(0.6)
                renderer.lineWidth = 1.5
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

struct MiniMapViewContainer: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var cameraStore: FlockCameraStore

    var nearbyCameras: [FlockCamera] {
        guard let location = locationManager.currentLocation else { return [] }
        let maxMeters = 800.0
        return cameraStore.cameras.filter { location.distance(from: $0.location) <= maxMeters }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            MiniMapView(
                cameras: nearbyCameras,
                userLocation: locationManager.currentLocation
            )
            .frame(width: 160, height: 120)

            Text("\(nearbyCameras.count) cams in 800m")
                .font(.system(size: 9))
                .foregroundColor(.gray)
                .padding(.trailing, 2)
        }
    }
}

struct MiniMapView_Previews: PreviewProvider {
    static var previews: some View {
        MiniMapViewContainer()
            .environmentObject(LocationManager())
            .environmentObject(FlockCameraStore())
    }
}
