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
    @State private var selectedStop: Stop?
    @State private var showSheet = true
    @State private var sheetDetent: PresentationDetent = .fraction(0.15)

    // Performance: viewport state for culling
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var zoomLevel: Double = 0.05
    @State private var visibleStops: [Stop] = []
    @State private var visibleVehicles: [Vehicle] = []

    // Throttle: debounce map camera changes
    @State private var cameraChangeTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            mapView

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
                Haptics.light()
            }
        }
        // Refresh visible vehicles periodically (RT updates every 30s)
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            updateVisibleVehicles()
        }
        .task {
            await appState.bootstrap()
            // Initial viewport update after data loads
            updateVisibleContent()
        }
    }

    // MARK: - Map

    @ViewBuilder
    private var mapView: some View {
        Map(position: $cameraPosition, selection: $selectedStop) {
            UserAnnotation()

            // Stops: only at zoom > 15 (~0.008 degrees), via spatial index
            if zoomLevel < 0.01 {
                ForEach(visibleStops) { stop in
                    Annotation(stop.name, coordinate: stop.coordinate, anchor: .bottom) {
                        StopAnnotationView(stop: stop, isSelected: selectedStop == stop)
                    }
                    .tag(stop)
                }
            }

            // Vehicles: viewport-culled, capped
            ForEach(visibleVehicles) { vehicle in
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
            zoomLevel = context.region.span.latitudeDelta
            throttledUpdateContent()
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

    // MARK: - Sheet

    @ViewBuilder
    private var sheetContent: some View {
        VStack(spacing: 0) {
            PullBar()
                .padding(.top, 8)
                .padding(.bottom, 4)

            if let stop = selectedStop {
                StopSheet(stop: stop)
            } else if sheetDetent == .large {
                SearchSheet()
            } else {
                HomeSheet()
            }
        }
    }

    // MARK: - Performance: throttled viewport updates

    private func throttledUpdateContent() {
        cameraChangeTask?.cancel()
        cameraChangeTask = Task {
            // 150ms debounce — prevents thrashing during pan/zoom
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            updateVisibleContent()
        }
    }

    private func updateVisibleContent() {
        guard let region = visibleRegion, appState.dataProvider.isLoaded else { return }

        let latDelta = region.span.latitudeDelta / 2
        let lngDelta = region.span.longitudeDelta / 2
        let minLat = region.center.latitude - latDelta
        let maxLat = region.center.latitude + latDelta
        let minLng = region.center.longitude - lngDelta
        let maxLng = region.center.longitude + lngDelta

        // Stops via spatial index (only when zoomed in enough)
        if zoomLevel < 0.01 {
            visibleStops = appState.dataProvider.stopsInRegion(
                minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng
            )
        } else {
            visibleStops = []
        }

        updateVisibleVehicles()
    }

    private func updateVisibleVehicles() {
        guard let region = visibleRegion else { return }

        let latDelta = region.span.latitudeDelta / 2
        let lngDelta = region.span.longitudeDelta / 2
        let minLat = region.center.latitude - latDelta
        let maxLat = region.center.latitude + latDelta
        let minLng = region.center.longitude - lngDelta
        let maxLng = region.center.longitude + lngDelta

        // Viewport cull + cap at 300 to prevent MapKit choking
        let maxVehicles = 300
        let all = appState.realtimeProvider.vehicles
        var filtered: [Vehicle] = []
        filtered.reserveCapacity(min(all.count, maxVehicles))

        for v in all {
            if v.latitude >= minLat && v.latitude <= maxLat &&
               v.longitude >= minLng && v.longitude <= maxLng {
                filtered.append(v)
                if filtered.count >= maxVehicles { break }
            }
        }
        visibleVehicles = filtered
    }
}

#Preview {
    MapScreen()
        .environment(AppState())
}
