import MapKit
import SwiftUI

/// Satellite view of the hole in play: the green outline, your position, this hole's
/// shots, and the line of play. Imagery rather than the standard map style, because a
/// vector map of a golf course is a featureless green rectangle.
struct HoleMapView: View {
    @Environment(AppModel.self) private var model
    @State private var camera: MapCameraPosition = .automatic
    @State private var hasFramedHole = false

    private var hole: Hole? { model.engine.currentHole }
    private var shots: [Shot] { model.engine.currentHoleScore?.shots ?? [] }

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()

            if let polygon = hole?.green?.polygon, polygon.count >= 3 {
                MapPolygon(coordinates: polygon.coordinates)
                    .foregroundStyle(.green.opacity(0.35))
                    .stroke(.green, lineWidth: 2)
            } else if let pin = hole?.green?.center {
                Annotation("Green", coordinate: pin.coordinate) {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Circle().fill(.green))
                }
            }

            // The line of play, drawn from where you are to the middle of the green.
            if let player = model.location.currentLocation, let centre = hole?.green?.center {
                MapPolyline(coordinates: [player.coordinate, centre.coordinate])
                    .stroke(.yellow.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }

            // Shots played on this hole, so a mis-logged one is obvious on the map.
            ForEach(shots) { shot in
                Annotation(label(for: shot), coordinate: shot.origin.coordinate) {
                    Circle()
                        .fill(.white)
                        .stroke(.black, lineWidth: 1)
                        .frame(width: 10, height: 10)
                }
                if let end = shot.end {
                    MapPolyline(coordinates: [shot.origin.coordinate, end.coordinate])
                        .stroke(.white.opacity(0.7), lineWidth: 2)
                }
            }
        }
        .mapStyle(.imagery(elevation: .realistic))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onChange(of: model.engine.currentHoleNumber) { _, _ in
            hasFramedHole = false
            frameHoleIfNeeded()
        }
        .onChange(of: model.location.currentLocation) { _, _ in
            frameHoleIfNeeded()
        }
        .onAppear { frameHoleIfNeeded() }
    }

    private func label(for shot: Shot) -> String {
        guard let id = shot.clubID, let club = model.store.club(withID: id) else { return "Shot" }
        return club.abbreviation
    }

    /// Frames the player and the green together once per hole, then leaves the camera
    /// alone so panning to check a hazard isn't yanked back on the next GPS fix.
    private func frameHoleIfNeeded() {
        guard !hasFramedHole else { return }
        guard let player = model.location.currentLocation, let centre = hole?.green?.center else { return }

        let midpoint = GeoPoint(
            latitude: (player.latitude + centre.latitude) / 2,
            longitude: (player.longitude + centre.longitude) / 2
        )
        let span = Geodesy.distance(from: player, to: centre)
        camera = .region(
            MKCoordinateRegion(
                center: midpoint.coordinate,
                latitudinalMeters: max(150, span * 1.6),
                longitudinalMeters: max(150, span * 1.6)
            )
        )
        hasFramedHole = true
    }
}
