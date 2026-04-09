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
    @State private var showSheet = true

    // Performance: viewport state
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var zoomLevel: Double = 0.05
    @State private var visibleStops: [Stop] = []
    @State private var visibleVehicles: [Vehicle] = []
    @State private var cameraChangeTask: Task<Void, Never>?

    /// True when sheet is at .large — map should blur
    private var isSheetFull: Bool {
        appState.sheetDetent == .large
    }

    var body: some View {
        @Bindable var state = appState

        ZStack {
            mapView
                .blur(radius: isSheetFull ? 6 : 0)
                .animation(.smooth, value: isSheetFull)

            VStack {
                if !isSheetFull {
                    searchBar
                }
                Spacer()
            }
        }
        .sheet(isPresented: $showSheet) {
            sheetContent
                .presentationDetents(
                    [.fraction(0.22), .fraction(0.5), .large],
                    selection: $state.sheetDetent
                )
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.5)))
                .presentationContentInteraction(.scrolls)
                .presentationCornerRadius(24)
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled()
        }
        .onChange(of: appState.sheetDetent) { _, newDetent in
            // If user drags to full from home, switch to search
            if newDetent == .large && appState.sheetContent == .home {
                appState.sheetContent = .search
            }
            // If user drags to peek from stop/line, go home
            if newDetent == .fraction(0.22) && appState.sheetContent != .home {
                appState.navigateHome()
            }
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            if !isSheetFull { updateVisibleVehicles() }
        }
        .task {
            await appState.bootstrap()
            updateVisibleContent()
        }
    }

    // MARK: - Map

    @ViewBuilder
    private var mapView: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()

            if zoomLevel < 0.01 {
                ForEach(visibleStops) { stop in
                    Annotation(stop.name, coordinate: stop.coordinate, anchor: .bottom) {
                        StopAnnotationView(stop: stop, isSelected: isStopSelected(stop))
                            .onTapGesture {
                                appState.navigate(to: .stop(stop))
                                flyTo(stop.coordinate)
                            }
                    }
                }
            }

            if !isSheetFull {
                ForEach(visibleVehicles) { vehicle in
                    Annotation("", coordinate: vehicle.coordinate) {
                        VehicleAnnotationView(
                            vehicle: vehicle,
                            route: appState.dataProvider.routeById[vehicle.routeId]
                        )
                    }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            zoomLevel = context.region.span.latitudeDelta
            throttledUpdateContent()
        }
        .onTapGesture {
            // Tap on empty map = go home
            if appState.sheetContent != .home {
                appState.navigateHome()
            }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        Button {
            appState.navigate(to: .search)
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

    // MARK: - Sheet content (state machine driven)

    @ViewBuilder
    private var sheetContent: some View {
        VStack(spacing: 0) {
            // Back button + pull bar
            sheetHeader

            switch appState.sheetContent {
            case .home:
                HomeSheet()
            case .search:
                SearchSheet()
            case .stop(let stop):
                StopSheet(stop: stop)
            case .line(let route):
                LineSheet(route: route)
            case .trip(let vehicle):
                TripSheet(vehicle: vehicle)
            case .alerts:
                AlertsSheet()
            }
        }
    }

    @ViewBuilder
    private var sheetHeader: some View {
        if appState.sheetContent == .home || appState.sheetContent == .search {
            // Minimal: just pull bar
            PullBar()
                .padding(.top, 8)
                .padding(.bottom, 4)
        } else {
            // Navigation header with back/close
            HStack {
                if appState.canNavigateBack {
                    Button {
                        appState.navigateBack()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Indietro")
                                .font(MV.Typography.calloutMedium)
                        }
                        .foregroundStyle(MV.Colors.accent)
                    }
                    .padding(.leading, MV.Spacing.md)
                }

                Spacer()
                PullBar()
                Spacer()

                Button {
                    appState.navigateHome()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(MV.Colors.textTertiary)
                }
                .padding(.trailing, MV.Spacing.md)
            }
            .frame(height: 36)
            .padding(.top, 8)
        }
    }

    // MARK: - Helpers

    private func isStopSelected(_ stop: Stop) -> Bool {
        if case .stop(let s) = appState.sheetContent { return s.id == stop.id }
        return false
    }

    private func flyTo(_ coordinate: CLLocationCoordinate2D) {
        withAnimation(.dramatic) {
            cameraPosition = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
            ))
        }
    }

    private func throttledUpdateContent() {
        cameraChangeTask?.cancel()
        cameraChangeTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            updateVisibleContent()
        }
    }

    private func updateVisibleContent() {
        guard let region = visibleRegion, appState.dataProvider.isLoaded else { return }
        let latD = region.span.latitudeDelta / 2
        let lngD = region.span.longitudeDelta / 2
        let minLat = region.center.latitude - latD
        let maxLat = region.center.latitude + latD
        let minLng = region.center.longitude - lngD
        let maxLng = region.center.longitude + lngD

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
        let latD = region.span.latitudeDelta / 2
        let lngD = region.span.longitudeDelta / 2
        let minLat = region.center.latitude - latD
        let maxLat = region.center.latitude + latD
        let minLng = region.center.longitude - lngD
        let maxLng = region.center.longitude + lngD

        let maxVehicles = 300
        var filtered: [Vehicle] = []
        filtered.reserveCapacity(min(appState.realtimeProvider.vehicles.count, maxVehicles))
        for v in appState.realtimeProvider.vehicles {
            if v.latitude >= minLat && v.latitude <= maxLat &&
               v.longitude >= minLng && v.longitude <= maxLng {
                filtered.append(v)
                if filtered.count >= maxVehicles { break }
            }
        }
        visibleVehicles = filtered
    }
}

// MARK: - Placeholder views for new sheet types

struct LineSheet: View {
    let route: Route
    var body: some View {
        ScrollView {
            Text("LineSheet: \(route.name)")
                .font(MV.Typography.headline)
                .foregroundStyle(MV.Colors.textPrimary)
                .padding()
        }
    }
}

struct TripSheet: View {
    let vehicle: Vehicle
    var body: some View {
        ScrollView {
            Text("TripSheet: vehicle \(vehicle.id)")
                .font(MV.Typography.headline)
                .foregroundStyle(MV.Colors.textPrimary)
                .padding()
        }
    }
}

struct AlertsSheet: View {
    var body: some View {
        ScrollView {
            Text("AlertsSheet")
                .font(MV.Typography.headline)
                .foregroundStyle(MV.Colors.textPrimary)
                .padding()
        }
    }
}

#Preview {
    MapScreen()
        .environment(AppState())
}
