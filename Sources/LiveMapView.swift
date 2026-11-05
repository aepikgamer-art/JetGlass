import SwiftUI
import MapKit

// MARK: - Annotations

final class PlaneAnnotation: MKPointAnnotation {
    let aircraft: LiveAircraft
    init(_ aircraft: LiveAircraft) {
        self.aircraft = aircraft
        super.init()
        coordinate = CLLocationCoordinate2D(latitude: aircraft.latitude, longitude: aircraft.longitude)
        title = aircraft.flight ?? aircraft.registration ?? aircraft.id
    }
}

final class AirportAnnotation: MKPointAnnotation {
    let airport: Airport
    init(_ airport: Airport) {
        self.airport = airport
        super.init()
        coordinate = CLLocationCoordinate2D(latitude: airport.latitude, longitude: airport.longitude)
        title = airport.icao
    }
}

// MARK: - MKMapView bridge

struct MapViewBridge: UIViewRepresentable {
    @ObservedObject var model: LiveMapModel
    var showAirlineLabels: Bool

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = true
        map.pointOfInterestFilter = .excludingAll
        map.mapType = .standard
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "plane")
        map.setRegion(model.region, animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        model.syncAnnotations(onto: map)

        if let target = model.flyToAirport {
            map.setRegion(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
            ), animated: true)
            model.flyToAirport = nil
        }

        model.ensureAirportMarker(on: map)

        for case let plane as PlaneAnnotation in map.annotations {
            if let view = map.view(for: plane) as? PlaneAnnotationView {
                view.setAirlineLabel(visible: showAirlineLabels, aircraft: plane.aircraft)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewBridge
        private var fetchTask: Task<Void, Never>?

        init(parent: MapViewBridge) { self.parent = parent }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.model.region = mapView.region
            fetchTask?.cancel()
            fetchTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await self?.parent.model.refresh()
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let plane = annotation as? PlaneAnnotation {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "plane") as? PlaneAnnotationView)
                    ?? PlaneAnnotationView(annotation: plane, reuseIdentifier: "plane")
                view.annotation = plane
                view.setAirlineLabel(visible: parent.showAirlineLabels, aircraft: plane.aircraft)
                return view
            }
            if let airport = annotation as? AirportAnnotation {
                let view = MKMarkerAnnotationView(annotation: airport, reuseIdentifier: "airport")
                view.glyphImage = UIImage(systemName: "airplane.circle")
                view.markerTintColor = .systemIndigo
                view.canShowCallout = true
                return view
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                    calloutAccessoryControlTapped control: UIControl) {
            guard let plane = view.annotation as? PlaneAnnotation else { return }
            parent.model.onSelectAircraft(plane.aircraft)
        }
    }
}

/// Plane icon that rotates with the aircraft's track and can show an airline label above.
final class PlaneAnnotationView: MKAnnotationView {
    private let label = UILabel()

    override var annotation: MKAnnotation? { willSet { configure() } }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }

    private func setup() {
        frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        centerOffset = CGPoint(x: 0, y: -10)
        canShowCallout = true

        let icon = UIImageView(image: UIImage(systemName: "airplane"))
        icon.tintColor = .systemCyan
        icon.contentMode = .scaleAspectFit
        icon.frame = CGRect(x: 8, y: 10, width: 24, height: 24)
        icon.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(icon)

        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        label.layer.cornerRadius = 5
        label.layer.masksToBounds = true
        label.textAlignment = .center
        label.frame = CGRect(x: -20, y: -16, width: 80, height: 16)
        addSubview(label)

        let detail = UIButton(type: .detailDisclosure)
        rightCalloutAccessoryView = detail
    }

    private func configure() {
        guard let plane = annotation as? PlaneAnnotation else { return }
        let angle = CGFloat(plane.aircraft.track) * .pi / 180
        transform = CGAffineTransform(rotationAngle: angle)
        setAirlineLabel(visible: label.superview != nil, aircraft: plane.aircraft)
    }

    func setAirlineLabel(visible: Bool, aircraft: LiveAircraft) {
        let text = aircraft.airlineName ?? aircraft.flight
        if visible, let text {
            label.text = " \(text) · \(aircraft.altitudeDisplay) "
            label.isHidden = false
        } else {
            label.isHidden = true
        }
    }
}

// MARK: - View model

@MainActor
final class LiveMapModel: ObservableObject {
    @Published var aircraft: [LiveAircraft] = []
    @Published var isRefreshing = false
    @Published var lastError: String?
    @Published var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.17, longitude: -96.5), // Sioux City / heartland default
        span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5)
    )
    @Published var flyToAirport: Airport?

    var showAirlineLabels = true
    var onSelectAircraft: (LiveAircraft) -> Void = { _ in }

    private let service = FR24LiveService()
    private var refreshTask: Task<Void, Never>?

    func refresh() {
        refreshTask?.cancel()
        let currentRegion = region
        refreshTask = Task { [weak self] in
            guard let self else { return }
            self.isRefreshing = true
            do {
                let planes = try await self.service.aircraft(in: currentRegion)
                guard !Task.isCancelled else { return }
                self.aircraft = planes
                self.lastError = planes.isEmpty
                    ? "No traffic in this area right now — pan somewhere busier (FR24 live feed)."
                    : nil
            } catch {
                guard !Task.isCancelled else { return }
                self.lastError = error.localizedDescription
            }
            self.isRefreshing = false
        }
    }

    func syncAnnotations(onto map: MKMapView) {
        let currentPlanes = map.annotations.compactMap { $0 as? PlaneAnnotation }
        let currentIDs = Set(currentPlanes.map(\.aircraft.id))
        let newIDs = Set(aircraft.map(\.id))

        for plane in currentPlanes where !newIDs.contains(plane.aircraft.id) {
            map.removeAnnotation(plane)
        }
        for plane in aircraft where !currentIDs.contains(plane.id) {
            map.addAnnotation(PlaneAnnotation(plane))
        }
    }

    func jump(to airport: Airport) {
        flyToAirport = airport
        lastAirport = AirportAnnotation(airport)
        airportMarkerAdded = false
    }

    private(set) var lastAirport: AirportAnnotation?
    private var airportMarkerAdded = false

    func ensureAirportMarker(on map: MKMapView) {
        guard let marker = lastAirport, !airportMarkerAdded else { return }
        map.removeAnnotations(map.annotations.filter { $0 is AirportAnnotation })
        map.addAnnotation(marker)
        airportMarkerAdded = true
    }
}

// MARK: - Live Map tab

struct LiveMapView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var model = LiveMapModel()
    @State private var search = ""
    @State private var results: [Airport] = []
    @State private var showAirlineLabels: Bool = true

    let openPhotosFor: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                mapView
                    .ignoresSafeArea(edges: .bottom)

                VStack {
                    glassSearchBar
                    Spacer()
                    glassStatus
                }
                .padding()
            }
            .navigationTitle("Live Map")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            showAirlineLabels = settings.showAirlineLabels
            model.showAirlineLabels = settings.showAirlineLabels
            model.onSelectAircraft = { plane in
                if let reg = plane.registration {
                    openPhotosFor(reg)
                } else {
                    openPhotosFor(plane.id)
                }
            }
            model.refresh()
        }
        .onDisappear {
            settings.showAirlineLabels = showAirlineLabels
        }
        .onChange(of: settings.mapRefreshSeconds) { _, interval in
            model.refresh()
        }
        .onChange(of: settings.showAirlineLabels) { _, value in
            showAirlineLabels = value
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(max(5, settings.mapRefreshSeconds)))
                guard !model.isRefreshing else { continue }
                model.refresh()
            }
        }
    }

    private var mapView: MapViewBridge {
        MapViewBridge(model: model, showAirlineLabels: showAirlineLabels)
    }

    private var glassSearchBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search airport by ICAO (e.g. KCOS)", text: $search)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: search) { _, value in
                        results = AirportsService.shared.search(value)
                    }
                    .onSubmit { goToFirstResult() }
                if !search.isEmpty {
                    Button { search = ""; results = [] } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)

            if !results.isEmpty && search.count < 4 {
                VStack(spacing: 4) {
                    ForEach(results) { airport in
                        Button { goTo(airport) } label: {
                            HStack {
                                Text(airport.icao).bold()
                                Text("· \(airport.iata)")
                                Spacer()
                                Text("\(airport.city), \(airport.country)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
        .glassCard()
        .padding(.horizontal, 8)
    }

    private var glassStatus: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $showAirlineLabels) {
                Label("Airlines above", systemImage: "tag")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)
            .tint(.cyan)

            Spacer()

            if model.isRefreshing {
                ProgressView()
            } else {
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.glass)
            }

            Text("\(model.aircraft.count) aircraft")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .glassCard()
        .padding(.horizontal, 8)
        .overlay(alignment: .top) {
            if let error = model.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 58)
            }
        }
    }

    private func goToFirstResult() {
        if let airport = results.first ?? AirportsService.shared.airport(forICAO: search) {
            goTo(airport)
        }
    }

    private func goTo(_ airport: Airport) {
        search = airport.icao
        results = []
        model.jump(to: airport)
    }
}
