import SwiftUI
import MapKit

// MARK: - Annotations

final class PlaneAnnotation: MKPointAnnotation {
    private(set) var aircraft: LiveAircraft
    init(_ aircraft: LiveAircraft) {
        self.aircraft = aircraft
        super.init()
        coordinate = CLLocationCoordinate2D(latitude: aircraft.latitude, longitude: aircraft.longitude)
        title = aircraft.flight ?? aircraft.registration ?? aircraft.id
    }

    /// Moves an existing annotation to the aircraft's new position/heading
    /// instead of tearing it down and adding a new one every refresh.
    func update(_ new: LiveAircraft) {
        aircraft = new
        coordinate = CLLocationCoordinate2D(latitude: new.latitude, longitude: new.longitude)
        title = new.flight ?? new.registration ?? new.id
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
                view.setTrack(plane.aircraft.track)
                view.setAirlineLabel(visible: showAirlineLabels,
                                     aircraft: plane.aircraft,
                                     compact: model.compactLabels)
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
                view.setTrack(plane.aircraft.track)
                view.setAirlineLabel(visible: parent.showAirlineLabels,
                                     aircraft: plane.aircraft,
                                     compact: parent.model.compactLabels)
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

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let plane = view.annotation as? PlaneAnnotation else { return }
            mapView.deselectAnnotation(plane, animated: false)
            parent.model.onSelectAircraft(plane.aircraft)
        }
    }
}

/// ✈️ plane emoji annotation that rotates with the aircraft's track,
/// with an airline label above that shrinks when the sky gets crowded.
final class PlaneAnnotationView: MKAnnotationView {
    private let planeEmoji = UILabel()
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

        planeEmoji.text = "✈️"
        planeEmoji.font = .systemFont(ofSize: 26)
        planeEmoji.frame = CGRect(x: 6, y: 8, width: 28, height: 28)
        planeEmoji.textAlignment = .center
        addSubview(planeEmoji)

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
        setTrack(plane.aircraft.track)
        setAirlineLabel(visible: label.superview != nil, aircraft: plane.aircraft, compact: false)
    }

    func setTrack(_ degrees: Double) {
        // Rotate just the emoji so the label stays horizontal.
        planeEmoji.transform = CGAffineTransform(rotationAngle: CGFloat(degrees) * .pi / 180)
    }

    func setAirlineLabel(visible: Bool, aircraft: LiveAircraft, compact: Bool) {
        let text = aircraft.airlineName ?? aircraft.flight
        guard visible, let text else {
            label.isHidden = true
            return
        }
        if compact {
            // Crowded sky: tiny text, callsign only — less overlap.
            label.font = .systemFont(ofSize: 7, weight: .medium)
            label.text = " \(aircraft.flight ?? text) "
            label.frame = CGRect(x: -14, y: -12, width: 68, height: 12)
        } else {
            label.font = .systemFont(ofSize: 10, weight: .semibold)
            label.text = " \(text) · \(aircraft.altitudeDisplay) "
            label.frame = CGRect(x: -20, y: -16, width: 80, height: 16)
        }
        label.isHidden = false
    }
}

// MARK: - View model

@MainActor
final class LiveMapModel: ObservableObject {
    @Published var aircraft: [LiveAircraft] = []
    @Published var isRefreshing = false
    @Published var lastError: String?
    @Published var compactLabels = false
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
                // Shrink flight text when there are too many planes on screen.
                self.compactLabels = planes.count >= 20
                self.lastError = planes.isEmpty
                    ? "No traffic in this area right now — try zooming out."
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
        var byID: [String: PlaneAnnotation] = [:]
        for plane in currentPlanes { byID[plane.aircraft.id] = plane }

        let newIDs = Set(aircraft.map(\.id))

        for plane in currentPlanes where !newIDs.contains(plane.aircraft.id) {
            map.removeAnnotation(plane)
        }
        for plane in aircraft {
            if let existing = byID[plane.id] {
                // Same plane — glide it to its new position/heading.
                existing.update(plane)
            } else {
                map.addAnnotation(PlaneAnnotation(plane))
            }
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
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @StateObject private var model = LiveMapModel()
    @State private var search = ""
    @State private var results: [Airport] = []
    @State private var showAirlineLabels: Bool = true

    // Plane info card (FR24-style: photo banner + details below)
    @State private var cardPlane: LiveAircraft?
    @State private var cardData: JetAPIResponse?
    @State private var cardReg: String?
    @State private var cardType: String?
    @State private var cardLoading = false

    let openPhotosFor: (String) -> Void

    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        ZStack {
            mapView
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 10) {
                glassSearchBar

                if let plane = cardPlane {
                    planeCard(plane)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()
                glassStatus
            }
            .padding()
            .animation(.spring(duration: 0.3), value: cardPlane)
        }
        .toolbar(.hidden, for: .navigationBar) // no top title bar
        .onAppear {
            showAirlineLabels = settings.showAirlineLabels
            model.showAirlineLabels = settings.showAirlineLabels
            model.onSelectAircraft = { plane in
                showCard(for: plane)
            }
            model.refresh()
        }
        .onDisappear {
            settings.showAirlineLabels = showAirlineLabels
        }
        .onChange(of: settings.showAirlineLabels) { _, value in
            showAirlineLabels = value
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(max(15, settings.mapRefreshSeconds)))
                guard !model.isRefreshing else { continue }
                model.refresh()
            }
        }
    }

    private var mapView: MapViewBridge {
        MapViewBridge(model: model, showAirlineLabels: showAirlineLabels)
    }

    // MARK: Plane info card

    private func showCard(for plane: LiveAircraft) {
        cardPlane = plane
        cardData = nil
        cardReg = plane.registration
        cardType = nil
        cardLoading = true
        let client = JetAPIClient(baseURLString: settings.apiBaseURL)

        Task {
            // Resolve the registration from the mode S hex (adsbdb.com),
            // then search jetapi by registration — not callsign.
            var reg = plane.registration
            if reg == nil {
                if let info = await AircraftRegistry.shared.info(for: plane.modeS) {
                    reg = info.registration
                    cardType = [info.manufacturer, info.type]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                }
            }
            guard cardPlane?.id == plane.id else { return }
            cardReg = reg

            let query = reg ?? plane.flight ?? plane.id
            if let data = try? await client.lookup(query: query, photos: 4, flights: 5) {
                guard cardPlane?.id == plane.id else { return }
                cardData = data
                if let frType = data.flightRadar?.aircraft, !frType.isEmpty, cardType == nil {
                    cardType = frType
                }
            }
            guard cardPlane?.id == plane.id else { return }
            cardLoading = false
        }
    }

    private func planeCard(_ plane: LiveAircraft) -> some View {
        let reg = cardReg ?? plane.registration ?? plane.id
        return Group {
            if isLandscape {
                compactPlaneCard(plane, reg: reg)
            } else {
                fullPlaneCard(plane, reg: reg)
            }
        }
    }

    /// FR24-style portrait card: big photo banner up top, details underneath.
    private func fullPlaneCard(_ plane: LiveAircraft, reg: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Big photo banner across the top of the card.
            ZStack(alignment: .topTrailing) {
                cardBanner(height: 150, cornerRadius: 22)
                closeButton
                    .padding(10)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(reg)
                        .font(.title3.bold())
                        .lineLimit(1)
                    if let typeName = cardType, !typeName.isEmpty {
                        Text(typeName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }

                Text(cardData?.flightRadar?.airline.isEmpty == false
                     ? cardData?.flightRadar?.airline ?? "" : (plane.airlineName ?? ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let flight = cardData?.flightRadar?.flights.first {
                    // Route row like the FR24 panel: FROM → TO with times.
                    HStack(spacing: 6) {
                        Text(flight.from)
                            .bold()
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(flight.to)
                            .bold()
                        Text("· \(flight.std) → \(flight.sta)")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(flight.status)
                            .foregroundStyle(.tertiary)
                    }
                    .font(.subheadline)
                    .lineLimit(1)
                }

                // Live airspeed + current altitude.
                HStack(spacing: 10) {
                    Label("\(plane.speedKnots) kt", systemImage: "speedometer")
                    Label("\(plane.altitudeFeet) ft", systemImage: "arrow.up")
                    Spacer()
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)

                if cardLoading {
                    Text("Looking up \(reg)…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if cardData?.jetPhotos?.images.isEmpty != false {
                    Text("No JetPhotos match for \(reg) — showing live data.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let photo = cardData?.jetPhotos?.images.first {
                    Text("\(photo.location) · \(photo.photographer)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Button {
                        openPhotosFor(reg)
                    } label: {
                        Label("Open in Photos", systemImage: "photo.stack")
                            .font(.caption)
                    }
                    .buttonStyle(.glass)
                    Spacer()
                }
            }
            .padding(14)
        }
        .glassCard(cornerRadius: 24)
        .padding(.horizontal, 8)
    }

    /// Landscape card — photo banner on the left, details on the right, one compact row.
    private func compactPlaneCard(_ plane: LiveAircraft, reg: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            cardBanner(width: 120, height: 90, cornerRadius: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(reg)
                    .font(.headline)
                    .lineLimit(1)
                if let flight = cardData?.flightRadar?.flights.first {
                    Text("\(flight.from) → \(flight.to) · \(flight.status)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 10) {
                    Label("\(plane.speedKnots) kt", systemImage: "speedometer")
                    Label("\(plane.altitudeFeet) ft", systemImage: "arrow.up")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

                HStack {
                    Button {
                        openPhotosFor(reg)
                    } label: {
                        Label("Photos", systemImage: "photo.stack")
                            .font(.caption)
                    }
                    .buttonStyle(.glass)
                    Spacer()
                }
            }
            Spacer(minLength: 0)
        }
        .glassCard(cornerRadius: 20)
        .padding(.horizontal, 8)
        .overlay(alignment: .topTrailing) {
            closeButton
                .padding(14)
        }
    }

    private var closeButton: some View {
        Button {
            withAnimation { cardPlane = nil }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.white, .black.opacity(0.55))
        }
        .buttonStyle(.plain)
    }

    /// Wide photo banner — fills the top of the card like FR24's detail panel.
    @ViewBuilder
    private func cardBanner(width: CGFloat? = nil, height: CGFloat, cornerRadius: CGFloat) -> some View {
        Group {
            if let photo = cardData?.jetPhotos?.images.first, let image = photo.imageURL {
                AsyncImage(url: image) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        Rectangle().fill(.quaternary)
                    }
                }
            } else if cardLoading {
                ZStack {
                    Rectangle().fill(.quaternary)
                    ProgressView()
                }
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "airplane")
                        .font(.system(size: min(height * 0.4, 44)))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .clipped()
    }

    // MARK: Search + status

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
    }

    private func goTo(_ airport: Airport) {
        search = airport.icao
        results = []
        model.jump(to: airport)
    }
}
