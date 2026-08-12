# FlockSpot GPS — AI Continuation Breakdown

**Project location:** `/Users/wes/Documents/FlockSpot/FlockSpot/`  
**Xcode project:** `FlockSpot.xcodeproj`  
**Main target:** `FlockSpot` (iOS SwiftUI app)  
**Extension target:** `FlockSpotWidget` (WidgetKit home-screen widget)  
**Last updated:** 2026-08-12

---

## 1. What this app is

FlockSpot GPS is an iOS app that helps drivers identify and avoid ALPR (Automatic License Plate Reader) cameras. It uses:

- **CoreLocation** for GPS/heading.
- **MapKit** for maps, annotations, and route rendering.
- **OpenStreetMap Overpass API** to load nearby ALPR cameras.
- **Valhalla routing API** (OpenStreetMap) for turn-by-turn directions with camera avoidance.
- **Apple Directions (MKDirections)** as a fallback when Valhalla fails.

---

## 2. Architecture overview

### Entry point
- `FlockSpotApp.swift` — `App` lifecycle, creates `LocationManager` and `FlockCameraStore` as `StateObject`s, injects them via `environmentObject`, shows disclaimer on first launch, and triggers camera loads on location updates.

### Main UI
- `ContentView.swift` — `TabView` with four tabs:
  1. **Compass** (`CompassView.swift`)
  2. **Navigate** (`RouteNavigationView.swift`)
  3. **Map** (`CameraMapView.swift`)
  4. **Settings** (`SettingsView` inside `ContentView.swift`)

### Data / location layer
- `LocationManager.swift` — `CLLocationManagerDelegate`, publishes `currentLocation`, `heading`, and authorization status. Requests when-in-use then always authorization.
- `FlockCameraStore.swift` — fetches, caches, and stores ALPR cameras from Overpass. Also includes `loadCamerasAlongRoute(polyline:completion:)` to fetch cameras along a navigation corridor and merge them into the existing set.
- `FlockCamera.swift` — model for an ALPR camera (OSM id, lat/lon, operator, brand, direction, mount, etc.).
- `SharedCameraData.swift` — persists the current camera list + user location in `UserDefaults` app group for the widget.

### Feature-specific files
- `CompassView.swift` — custom compass UI pointing toward the nearest camera, plus a horizontal “Fortnite-style” compass bar.
- `CameraMapView.swift` — MapKit-based map with camera pins, FOV cones, camera detail card, and floating map controls.
- `RouteNavigationView.swift` — turn-by-turn navigation with search, route preview, camera avoidance, and recenter button.
- `DisclaimerView.swift` — full-screen terms/disclaimer shown before first use.
- `CarPlaySceneDelegate.swift` — CarPlay list template showing nearby cameras.

---

## 3. Recent feature work (what was just added)

### Navigation feature (`RouteNavigationView.swift`)
- Destination search via `MKLocalSearch`; results sorted nearest → furthest from user.
- Route preview: route is highlighted on the map in a **bird’s-eye 45° camera**.
- **Go** button starts navigation and switches the map to **2D / pitch 0**.
- Turn-by-turn card shows current maneuver, distance to it, next maneuver, remaining distance/time, and an **End** button.
- Automatic step advancement when the user comes within ~50 m of a maneuver coordinate.
- **Recenter button** (`location.fill`) appears when the user pans/zooms away during navigation.
- Map interaction is fully free during navigation; auto-follow pauses on user gesture.

### Camera avoidance
- Initial route is fetched from Valhalla without exclusions.
- `FlockCameraStore.loadCamerasAlongRoute(polyline:)` fetches cameras along the route corridor (sample every 8 km, 10 km radius) and merges them into the store.
- Cameras within ~100 m of the route are turned into `exclude_polygons` for Valhalla.
- Valhalla is called again with exclusions to produce a camera-safe route.
- If Valhalla fails at any step, the app falls back to Apple Directions and shows a warning.

### Performance / lag fixes
- `FlockCameraStore` now parses Overpass JSON and diffs cameras on a background queue; only the final `@Published` update runs on main.
- `FlockSpotApp` no longer reloads widgets on every location update. Heading-driven widget reloads are throttled to once every 5 seconds.

### UI polish
- Navigation screen uses floating material cards, consistent SF Symbols, and clear “preview → Go → navigating” states.
- Compass screen wraps nearest-camera info in a material card; removed redundant large title.
- Map screen uses shared `MapControlButton` with `.ultraThinMaterial` instead of opaque white/black controls.
- App display name changed to **FlockSpot GPS** across `Info.plist`, launch screen, CarPlay tab title, disclaimer, and widget plist.

### CarPlay deprecation fix
- Replaced deprecated `setRootTemplate(_:animated:)` with `setRootTemplate(_:animated:completion:)` in `CarPlaySceneDelegate.swift`.

---

## 4. Key APIs and endpoints

| Purpose | URL / API |
|---|---|
| ALPR camera data | `https://overpass-api.de/api/interpreter` |
| Turn-by-turn routing | `https://valhalla1.openstreetmap.de/route` |
| Search / geocoding | `MKLocalSearch` (Apple MapKit) |
| Fallback routing | `MKDirections` (Apple MapKit) |

---

## 5. How to build

From the project directory:

```bash
cd /Users/wes/Documents/FlockSpot/FlockSpot
xcodebuild -project FlockSpot.xcodeproj -scheme FlockSpot -destination 'id=<your-device-or-simulator-id>' build
```

For a quick compile check without a simulator, the “My Mac (Designed for iPhone)” destination works:

```bash
xcodebuild -project FlockSpot.xcodeproj -scheme FlockSpot -destination 'id=00008112-001C09283678201E' build CODE_SIGNING_ALLOWED=NO
```

---

## 6. Recently fixed limitations

| Limitation | Fix |
|---|---|
| No voice guidance | Added `AVSpeechSynthesizer` in `RouteNavigationView`; speaks the first maneuver on **Go** and each new maneuver as you drive. |
| No automatic rerouting | Added off-route detection in `RouteNavigationView.updateNavigationProgress`. If you go >150 m off the route, it recalculates after a 10-second cooldown and speaks “Recalculating.” |
| Concurrent Overpass requests along route | `FlockCameraStore.loadCamerasAlongRoute` now uses a `DispatchSemaphore(value: 2)` to limit corridor fetches to 2 concurrent requests. |
| Camera avoidance gaps | Exclusion polygon radius increased from 75 m to 100 m; route corridor cameras are fetched before final routing. |
| Valhalla reliability | Added one automatic retry (1-second delay) in `ValhallaRouter.performRequest`. |
| Widget purpose unclear | Widget is now explicitly a **nearest-camera compass** (not a GPS/navigation widget). Display name changed to **FlockSpot GPS Compass** and copy updated. |

---

## 7. Remaining limitations (require infrastructure or large scope)

- **Valhalla is a public demo service**: retries help, but for production a dedicated Valhalla/GraphHopper/Mapbox instance is still recommended.
- **No offline maps**: MapKit tiles and routing data require a network. Offline maps would need a different map renderer and tile store.
- **Camera avoidance is still heuristic**: exclusion polygons can occasionally block a route or miss a camera just outside the 100 m corridor.
- **CarPlay** only shows a nearby-camera list, not navigation.
- **Widget** shows the nearest camera from the last saved location; it does not enter navigation mode.

---

## 8. Common extension points

| Want to add… | Start here |
|---|---|
| Voice announcements | Already implemented via `AVSpeechSynthesizer` in `RouteNavigationView`. Tweak `speak(_:)` for different voices/languages. |
| Automatic rerouting / recenter | Already implemented in `RouteNavigationView.updateNavigationProgress` and `recenter()`. The recenter button appears whenever the user pans away; in preview it returns to the route overview, in navigation it returns to the user. |
| Avoid more camera types | Update the Overpass query in `FlockCameraStore.fetchCameras` |
| Save favorite destinations | Add `@AppStorage` or Core Data; wire into `RouteNavigationView.searchDestinations` |
| Offline camera cache | Extend `FlockCameraStore` disk cache to cover larger regions |
| Dark map style | Change `mapView.mapType` or use `MKStandardMapConfiguration` in `RouteMapView` / `CameraMapView` |
| Better route overview camera | Tweak the distance/pitch calculation in `RouteMapView.updateUIView` |

---

## 9. File map

```
FlockSpot/
├── FlockSpotApp.swift           # App entry point
├── ContentView.swift            # Tab container + SettingsView
├── CompassView.swift              # Compass + nearest camera card
├── CameraMapView.swift          # Map tab + camera detail card
├── RouteNavigationView.swift    # Turn-by-turn navigation
├── LocationManager.swift        # CoreLocation wrapper
├── FlockCameraStore.swift       # Overpass fetch + cache + route corridor loading
├── FlockCamera.swift              # Camera model + Overpass parsing
├── SharedCameraData.swift         # App-group shared defaults for widget
├── DisclaimerView.swift           # First-launch disclaimer
├── CarPlaySceneDelegate.swift     # CarPlay scene
├── Info.plist                     # App name / permissions
└── AI_BREAKDOWN.md                # This file
```

---

## 10. Notes for the next AI agent

- The project uses **no external Swift packages**; everything is Apple frameworks + URLSession.
- `RouteNavigationView.swift` is the most complex file; changes there often require matching changes in `FlockCameraStore.swift`.
- Be careful with `MKMapView` representable state: `RouteMapView` distinguishes user gestures from code-driven camera changes via `isProgrammaticChange`, and only calls `setCamera` when the desired region differs from the current map region by a threshold (prevents jitter/self-moving map).
- The `FlockCameraStore.cameras` array is now **append/merge** capable (via `loadCamerasAlongRoute`), but `loadCameras(for:)` still **replaces** it with the local-area fetch to keep the main map/compass focused.
- Always run `xcodebuild` after editing Swift files to catch compile errors early.
