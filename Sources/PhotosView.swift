import SwiftUI

// MARK: - Photos tab

struct PhotosView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var model = PhotosModel()
    @ObservedObject private var searchBus = PhotoSearch.shared
    @State private var query = ""
    @State private var selectedPhoto: JetPhoto?
    @FocusState private var focused: Bool

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    searchBar

                    if let error = model.error {
                        ContentUnavailableView("No luck", systemImage: "questionmark.bubble",
                                               description: Text(error))
                    } else if model.photos.isEmpty && !model.isLoading {
                        ContentUnavailableView("Search a registration",
                                              systemImage: "airplane.departure",
                                              description: Text("Try N142UW, A7-ALZ, or a query like A350."))
                    } else {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(model.photos) { photo in
                                Button { selectedPhoto = photo } label: { cell(photo) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }

                    if let fr = model.flightRadar {
                        flightCard(fr)
                    }
                }
                .padding()
            }
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedPhoto) { photo in
                PhotoDetailView(photo: photo, flightRadar: model.flightRadar)
                    .presentationDetents([.large])
            }
            .onChange(of: searchBus.pendingQuery) { _, newValue in
                if let newValue, !newValue.isEmpty {
                    query = newValue
                    searchBus.pendingQuery = nil
                    runSearch()
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Registration or query (e.g. N142UW)", text: $query)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($focused)
                .onSubmit(runSearch)
            if model.isLoading {
                ProgressView()
            } else if !query.isEmpty {
                Button { query = ""; model.reset() } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            } else {
                Button("Go", action: runSearch)
                    .buttonStyle(.glass)
            }
        }
        .padding(12)
        .glassCard()
    }

    private func cell(_ photo: JetPhoto) -> some View {
        AsyncImage(url: photo.thumbnailURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "airplane")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: 110)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(alignment: .bottomLeading) {
            Text(photo.airline.isEmpty ? photo.aircraft : photo.airline)
                .font(.caption2.weight(.semibold))
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 0))
                .lineLimit(1)
        }
    }

    private func flightCard(_ fr: FlightRadarResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("FlightRadar24 — recent flights", systemImage: "location.filled")
                .font(.subheadline.weight(.semibold))
            Text("\(fr.aircraft) · \(fr.airline)")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(fr.flights.prefix(settings.flightCount)) { flight in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(flight.flight) · \(flight.routeDisplay)")
                            .font(.subheadline)
                        Text("\(flight.date) · \(flight.status)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(flight.flightTime)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func runSearch() {
        focused = false
        Task { await model.search(query: query, settings: settings) }
    }
}

// MARK: - View model

@MainActor
final class PhotosModel: ObservableObject {
    @Published var photos: [JetPhoto] = []
    @Published var flightRadar: FlightRadarResult?
    @Published var isLoading = false
    @Published var error: String?

    func search(query: String, settings: AppSettings) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        error = nil
        photos = []
        flightRadar = nil

        let client = JetAPIClient(baseURLString: settings.apiBaseURL)
        do {
            let response = try await client.lookup(
                query: query,
                photos: max(1, settings.photoCount),
                flights: max(1, settings.flightCount)
            )
            photos = response.jetPhotos?.images ?? []
            flightRadar = response.flightRadar
            if photos.isEmpty && flightRadar == nil {
                error = "Nothing found for “\(query)”. Check the registration and try again."
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func reset() {
        photos = []
        flightRadar = nil
        error = nil
    }
}

// MARK: - Full-screen photo detail

struct PhotoDetailView: View {
    let photo: JetPhoto
    let flightRadar: FlightRadarResult?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var saving = false
    @State private var savedMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    AsyncImage(url: photo.imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        default:
                            Rectangle()
                                .fill(.quaternary)
                                .frame(height: 260)
                                .overlay(ProgressView())
                        }
                    }
                    .clipShape(.rect(cornerRadius: 20))

                    HStack(spacing: 12) {
                        Button {
                            download()
                        } label: {
                            if saving {
                                ProgressView()
                            } else {
                                Label("Download", systemImage: "square.and.arrow.down")
                            }
                        }
                        .buttonStyle(.glass)

                        if let url = photo.imageURL {
                            ShareLink(item: url) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.glass)
                        }

                        Button {
                            if let link = URL(string: photo.link) { openURL(link) }
                        } label: {
                            Label("Source", systemImage: "link")
                        }
                        .buttonStyle(.glass)
                    }

                    if let message = savedMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    infoCard
                    if let fr = flightRadar { flightSummary(fr) }
                }
                .padding()
            }
            .navigationTitle(photo.airline.isEmpty ? "Photo" : photo.airline)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Aircraft", photo.aircraft)
            row("Airline", photo.airline)
            row("Registration", regText)
            row("Serial", photo.serial)
            row("Location", photo.location)
            row("Photographer", photo.photographer)
            row("Taken", photo.dateTaken)
            row("Uploaded", photo.dateUploaded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var regText: String {
        if let fr = flightRadar, !fr.aircraft.isEmpty { return fr.aircraft }
        return photo.aircraft
    }

    private func flightSummary(_ fr: FlightRadarResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("FlightRadar24", systemImage: "location.filled")
                .font(.subheadline.weight(.semibold))
            row("Operator", fr.operatorName)
            row("Type", fr.typeCode)
            row("Mode-S", fr.modeS)
            ForEach(fr.flights.prefix(5)) { flight in
                Text("\(flight.flight) · \(flight.routeDisplay) · \(flight.date)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.subheadline)
            Spacer()
        }
    }

    private func download() {
        saving = true
        savedMessage = nil
        Task {
            do {
                try await ImageSaver.save(from: photo.image)
                savedMessage = "Saved to your photo library ✓"
            } catch {
                savedMessage = error.localizedDescription
            }
            saving = false
        }
    }
}
