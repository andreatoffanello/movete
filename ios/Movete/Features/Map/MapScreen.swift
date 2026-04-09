import SwiftUI
import MapKit

struct MapScreen: View {
    @Environment(AppState.self) private var appState

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 41.8967, longitude: 12.4822),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var selectedStop: Stop?
    @State private var showSheet = true
    @State private var sheetDetent: PresentationDetent = .fraction(0.15)
    @State private var mapZoom: Double = 0.05

    var body: some View {
        ZStack {
            mapView

            // Top search bar overlay
            VStack {
                searchBar
                Spacer()
            }
        }
        .sheet(isPresented: $showSheet) {
            sheetContent
                .presentationDetents(
                    [.fraction(0.15), .fraction(0.5), .large],
                    selection: $sheetDetent
                )
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.5)))
                .presentationContentInteraction(.scrolls)
                .presentationCornerRadius(24)
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled()
        }
        .onChange(of: selectedStop) { _, newStop in
            if newStop != nil {
                withAnimation(.smooth) {
                    sheetDetent = .fraction(0.5)
                }
            }
        }
        .task {
            await appState.bootstrap()
        }
    }

    // MARK: - Map

    @ViewBuilder
    private var mapView: some View {
        Map(position: $cameraPosition, selection: $selectedStop) {
            // User location
            UserAnnotation()

            // Stops — only show when zoomed in enough
            if mapZoom < 0.02, appState.dataProvider.isLoaded {
                let visibleStops = stopsInVisibleRegion()
                ForEach(visibleStops) { stop in
                    Annotation(stop.name, coordinate: stop.coordinate, anchor: .bottom) {
                        StopAnnotationView(stop: stop, isSelected: selectedStop == stop)
                    }
                    .tag(stop)
                }
            }

            // Live vehicles
            ForEach(appState.realtimeProvider.vehicles) { vehicle in
                Annotation("", coordinate: vehicle.coordinate) {
                    VehicleAnnotationView(
                        vehicle: vehicle,
                        route: appState.dataProvider.routeById[vehicle.routeId]
                    )
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            mapZoom = context.region.span.latitudeDelta
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        Button {
            withAnimation(.smooth) {
                selectedStop = nil
                sheetDetent = .large
            }
        } label: {
            HStack(spacing: MV.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(MV.Colors.textTertiary)
                Text("Cerca fermata o linea")
                    .font(MV.Typography.callout)
                    .foregroundStyle(MV.Colors.textTertiary)
                Spacer()
            }
            .padding(.horizontal, MV.Spacing.md)
            .padding(.vertical, MV.Spacing.sm)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: MV.Radius.lg, style: .continuous))
            .mvSubtleShadow()
        }
        .padding(.horizontal, MV.Spacing.md)
        .padding(.top, 4)
    }

    // MARK: - Sheet content

    @ViewBuilder
    private var sheetContent: some View {
        VStack(spacing: 0) {
            PullBar()
                .padding(.top, 8)
                .padding(.bottom, 4)

            if let stop = selectedStop {
                StopSheet(stop: stop)
            } else {
                HomeSheet()
            }
        }
    }

    // MARK: - Helpers

    private func stopsInVisibleRegion() -> [Stop] {
        guard let region = visibleRegion else { return [] }
        let latDelta = region.span.latitudeDelta / 2
        let lngDelta = region.span.longitudeDelta / 2
        let minLat = region.center.latitude - latDelta
        let maxLat = region.center.latitude + latDelta
        let minLng = region.center.longitude - lngDelta
        let maxLng = region.center.longitude + lngDelta

        return appState.dataProvider.stops.filter { stop in
            stop.lat >= minLat && stop.lat <= maxLat &&
            stop.lng >= minLng && stop.lng <= maxLng
        }
    }
}

#Preview {
    MapScreen()
        .environment(AppState())
}
