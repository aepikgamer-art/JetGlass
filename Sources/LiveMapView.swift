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

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let plane = view.annotation as? PlaneAnnotation else { return }
            mapView.deselectAnnotation(plane, animated: false)
            parent.model.onSelectAircraft(plane.aircraft)
        }
    }
}

final class PlaneAnnotationView: MKAnnotationView {
    private let planeIcon = UIImageView()
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

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)
        let planeSymbol = UIImage(systemName: "airplane", withConfiguration: iconConfig)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        planeIcon.image = planeSymbol
        planeIcon.contentMode = .center
        planeIcon.frame = CGRect(x: 4, y: 4, width: 32, height: 32)
        planeIcon.layer.cornerRadius = 16
        planeIcon.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.92)
        planeIcon.layer.borderWidth = 1.5
        planeIcon.layer.borderColor = UIColor.white.withAlphaComponent(0.75).cgColor
        planeIcon.clipsToBounds = true
        addSubview(planeIcon)

        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        label.layer.cornerRadius = 5
        label.layer.masksToBounds = true
        label.textAlignment = .center
        label.frame = CGRect(x: -20, y: -16, width: 80, height: 16)
        addSubview(label)
    }

    private func configure() {
        guard let plane = annotation as? PlaneAnnotation else { return }
        setTrack(plane.aircraft.track)
        setAirlineLabel(visible: label.superview != nil, aircraft: plane.aircraft, compact: false)
    }

    func setTrack(_ degrees: Double) {
        planeIcon.transform = CGAffineTransform(rotationAngle: CGFloat(degrees) * .pi / 180)
    }

    func setAirlineLabel(visible: Bool, aircraft: LiveAircraft, compact: Bool) {
        let text = aircraft.airlineName ?? aircraft.flight
        guard visible, let text else {
            label.isHidden = true
            return
        }
        if compact {
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
        center: CLLocationCoordinate2D(latitude: 39.17, longitude: -96.5),
        span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5)
    )
    @Published var flyToAirport: Airport?
    @Published var airlineFilter: String?
    @Published var typeFilter: String?

    var showAirlineLabels = true
    var onSelectAircraft: (LiveAircraft) -> Void = { _ in }

    private let service = FR24LiveService()
    private var refreshTask: Task<Void, Never>?

    var displayedAircraft: [LiveAircraft] {
        aircraft.filter { plane in
            let airlineOK: Bool
            if let filter = airlineFilter {
                airlineOK = filter == "Other"
                    ? (plane.airlineName?.isEmpty != false)
                    : plane.airlineName == filter
            } else {
                airlineOK = true
            }
            let typeOK: Bool
            if let filter = typeFilter {
                typeOK = filter == "Unknown"
                    ? (plane.type?.isEmpty != false)
                    : plane.type == filter
            } else {
                typeOK = true
            }
            return airlineOK && typeOK
        }
    }

    var airlineOptions: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        var other = 0
        for plane in aircraft {
            if let name = plane.airlineName, !name.isEmpty {
                counts[name, default: 0] += 1
            } else {
                other += 1
            }
        }
        var options = counts.map { (name: $0.key, count: $0.value) }
        options.sort { $0.count > $1.count }
        if other > 0 { options.append((name: "Other", count: other)) }
        return options
    }

    var typeOptions: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        var unknown = 0
        for plane in aircraft {
            if let type = plane.type, !type.isEmpty {
                counts[type, default: 0] += 1
            } else {
                unknown += 1
            }
        }
        var options = counts.map { (name: $0.key, count: $0.value) }
        options.sort { $0.count > $1.count }
        if unknown > 0 { options.append((name: "Unknown", count: unknown)) }
        return options
    }

    var hasActiveFilter: Bool { airlineFilter != nil || typeFilter != nil }

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
                self.compactLabels = self.displayedAircraft.count >= 20
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
        let shown = displayedAircraft
        let currentPlanes = map.annotations.compactMap { $0 as? PlaneAnnotation }
        var byID: [String: PlaneAnnotation] = [:]
        for plane in currentPlanes { byID[plane.aircraft.id] = plane }

        let newIDs = Set(shown.map(\.id))

        for plane in currentPlanes where !newIDs.contains(plane.aircraft.id) {
            map.removeAnnotation(plane)
        }
        for plane in shown {
            if let existing = byID[plane.id] {
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
    @State private var showFilters = false

    @State private var cardPlane: LiveAircraft?
    @State private var cardData: JetAPIResponse?
    @State private var cardReg: String?
    @State private var cardType: String?
    @State private var cardLoading = false
    @State private var cardExpanded = false

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
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showFilters) {
            filtersSheet
                .presentationDetents([.medium, .large])
        }
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

    private func showCard(for plane: LiveAircraft) {
        cardPlane = plane
        cardData = nil
        cardReg = plane.registration
        cardType = plane.type
        cardLoading = true
        cardExpanded = false
        let client = JetAPIClient(baseURLString: settings.apiBaseURL)

        Task {
            var reg = plane.registration
            if reg == nil {
                if let info = await AircraftRegistry.shared.info(for: plane.modeS) {
                    reg = info.registration
                    if cardType == nil {
                        cardType = [info.manufacturer, info.type]
                            .compactMap { $0 }
                            .filter { !$0.isEmpty }
                            .joined(separator: " ")
                    }
                }
            }
            guard cardPlane?.id == plane.id else { return }
            cardReg = reg

            let query = reg ?? plane.flight ?? plane.id
            if let data = try? await client.lookup(query: query, photos: 6, flights: 5) {
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

    private func fullPlaneCard(_ plane: LiveAircraft, reg: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
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

                if cardExpanded {
                    cardExpandedInfo(plane, reg: reg)
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
                    Button {
                        withAnimation(.spring(duration: 0.35)) { cardExpanded.toggle() }
                    } label: {
                        Label(cardExpanded ? "Less" : "More info",
                              systemImage: cardExpanded ? "chevron.up.circle" : "chevron.down.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(14)
        }
        .glassCard(cornerRadius: 24)
        .padding(.horizontal, 8)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    if value.translation.height > 25, !cardExpanded {
                        withAnimation(.spring(duration: 0.35)) { cardExpanded = true }
                    } else if value.translation.height < -25, cardExpanded {
                        withAnimation(.spring(duration: 0.35)) { cardExpanded = false }
                    }
                }
        )
    }

    @ViewBuilder
    private func cardExpandedInfo(_ plane: LiveAircraft, reg: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            if let images = cardData?.jetPhotos?.images, images.count > 1 {
                Text("Photos")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(images.prefix(6).enumerated()), id: \.offset) { _, img in
                            if let url = img.thumbnailURL ?? img.imageURL {
                                AsyncImage(url: url) { phase in
                                    if case .success(let image) = phase {
                                        image.resizable().scaledToFill()
                                    } else {
                                        Rectangle().fill(.quaternary)
                                    }
                                }
                                .frame(width: 96, height: 64)
                                .clipShape(.rect(cornerRadius: 10))
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Aircraft")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                infoRow(label: "Mode S", value: plane.modeS.uppercased())
                if let type = plane.type, !type.isEmpty {
                    infoRow(label: "Type code", value: type)
                }
                if let serial = cardData?.jetPhotos?.images.first?.serial, !serial.isEmpty {
                    infoRow(label: "Serial", value: serial)
                }
                if let typeCode = cardData?.flightRadar?.typeCode, !typeCode.isEmpty {
                    infoRow(label: "FR24 type", value: typeCode)
                }
                if let operatorName = cardData?.flightRadar?.operatorName, !operatorName.isEmpty {
                    infoRow(label: "Operator", value: operatorName)
                }
            }

            if let flights = cardData?.flightRadar?.flights, !flights.isEmpty {
                Text("Recent flights")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(flights.prefix(5).enumerated()), id: \.offset) { _, f in
                        HStack {
                            Text(f.date)
                                .foregroundStyle(.secondary)
                            Text("\(f.from) → \(f.to)")
                            Spacer()
                            Text(f.flightTime.isEmpty ? f.status : f.flightTime)
                                .foregroundStyle(.tertiary)
                        }
                        .font(.caption2.monospacedDigit())
                        .lineLimit(1)
                    }
                }
            }

            if let link = cardData?.jetPhotos?.images.first?.link,
               let url = URL(string: link.hasPrefix("http") ? link : "https:" + link) {
                Link("View on JetPhotos", destination: url)
                    .font(.caption)
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.caption)
    }

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
            withAnimation { cardPlane = nil; cardExpanded = false }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.white, .black.opacity(0.55))
        }
        .buttonStyle(.plain)
    }

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

    private var glassSearchBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search ICAO, IATA, city or name", text: $search)
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

            if !results.isEmpty {
                VStack(spacing: 4) {
                    ForEach(results.prefix(6)) { airport in
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
                Label("Airlines", systemImage: "tag")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)
            .tint(.cyan)

            Spacer()

            Button {
                showFilters = true
            } label: {
                Image(systemName: model.hasActiveFilter
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.glass)
            .tint(model.hasActiveFilter ? .cyan : .primary)

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

            Text("\(model.displayedAircraft.count) aircraft")
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

    private var filtersSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Categories")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    model.airlineFilter = nil
                    model.typeFilter = nil
                }
                .font(.subheadline)
                .disabled(!model.hasActiveFilter)
                Button("Done") { showFilters = false }
                    .font(.subheadline.bold())
            }

            Text("Show only certain airlines or aircraft types on the map.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if !model.airlineOptions.isEmpty {
                        Text("Airlines")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(model.airlineOptions, id: \.name) { option in
                            filterRow(title: option.name, count: option.count,
                                      selected: model.airlineFilter == option.name) {
                                model.airlineFilter = (model.airlineFilter == option.name) ? nil : option.name
                            }
                        }
                    }

                    if !model.typeOptions.isEmpty {
                        Text("Aircraft types")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                        ForEach(model.typeOptions, id: \.name) { option in
                            filterRow(title: option.name, count: option.count,
                                      selected: model.typeFilter == option.name) {
                                model.typeFilter = (model.typeFilter == option.name) ? nil : option.name
                            }
                        }
                    }

                    if model.aircraft.isEmpty {
                        Text("No traffic yet — pan the map somewhere busy first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .padding()
    }

    private func filterRow(title: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(selected ? .cyan : .primary)
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? .cyan : .secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
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
