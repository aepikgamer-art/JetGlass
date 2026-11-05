import Foundation
import MapKit

enum LiveFeedError: LocalizedError {
    case badResponse
    var errorDescription: String? { "FlightRadar24's live feed didn't respond with traffic. Try panning or refreshing." }
}

/// Fetches live traffic from FlightRadar24's public zone feed endpoints.
///
/// The classic endpoint returns `{"aircraft": [[...arrays...]], "full_count": N, "version": 5}`.
/// Field layouts vary slightly between feed versions, so the parser locates
/// latitude/longitude by plausibility instead of trusting fixed indices.
final class FR24LiveService {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
            "Accept": "application/json",
        ]
        self.session = URLSession(configuration: config)
    }

    /// Fetch aircraft currently within `bounds` (FR24 order: north, south, west, east).
    func aircraft(in region: MKCoordinateRegion) async throws -> [LiveAircraft] {
        let latMin = max(-90.0, region.center.latitude - region.span.latitudeDelta)
        let latMax = min(90.0, region.center.latitude + region.span.latitudeDelta)
        let lonMin = max(-180.0, region.center.longitude - region.span.longitudeDelta)
        let lonMax = min(180.0, region.center.longitude + region.span.longitudeDelta)

        let bounds = "\(latMax),\(latMin),\(lonMin),\(lonMax)"
        let urlString = "https://data.flightradar24.com/zones/fcgi/feed.js"
            + "?bounds=\(bounds)&faa=1&sat=1&mlat=1&flarm=1&adsb=1&gnd=0&air=1"
            + "&vehicles=0&estimated=1&maxage=14400&gliders=0&stats=1"
        guard let url = URL(string: urlString) else { throw LiveFeedError.badResponse }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw LiveFeedError.badResponse
        }
        return try Self.parse(data)
    }

    // MARK: - Parsing

    static func parse(_ data: Data) throws -> [LiveAircraft] {
        let json = try? JSONSerialization.jsonObject(with: data)
        guard let object = json as? [String: Any] else { throw LiveFeedError.badResponse }

        var rows: [[Any]] = []
        if let aircraft = object["aircraft"] as? [[Any]] {
            rows = aircraft
        } else {
            // Older feed shape: { "<id>": [...], ... }
            for (_, value) in object where value is [Any] {
                if let row = value as? [Any] { rows.append(row) }
            }
        }
        return rows.compactMap(Self.aircraft(fromRow:))
    }

    static func aircraft(fromRow row: [Any]) -> LiveAircraft? {
        let strings = row.compactMap { $0 as? String }
        let numbers = row.compactMap { ($0 as? NSNumber)?.doubleValue }

        // Find the first plausible lat/lon pair (consecutive doubles in range).
        var lat: Double?
        var lon: Double?
        var latIndex = -1
        for (i, value) in numbers.enumerated() {
            let next = i + 1 < numbers.count ? numbers[i + 1] : nil
            if (-90...90).contains(value), let next, (-180...180).contains(next), !(value == 0 && next == 0) {
                lat = value
                lon = next
                latIndex = i
                break
            }
        }
        guard let lat, let lon else { return nil }

        // Track, altitude and speed follow lat/lon in all known layouts.
        let track = latIndex + 2 < numbers.count ? numbers[latIndex + 2] : 0
        let altitude = latIndex + 3 < numbers.count ? Int(numbers[latIndex + 3]) : 0
        let speed = latIndex + 4 < numbers.count ? Int(numbers[latIndex + 4]) : 0

        // Strings: flight id first, then a 6-char hex Mode-S address somewhere.
        let flight = strings.first(where: { !$0.isEmpty })
        let modeS = strings.first(where: { $0.count == 6 && $0.allSatisfy({ $0.isHexDigit }) }) ?? (flight ?? "")
        let registration = strings.first(where: { $0 != flight && $0.count >= 3 && $0.count <= 12 && !$0.contains(" ") && $0 != modeS })

        let id = flight ?? modeS
        guard !id.isEmpty else { return nil }

        return LiveAircraft(
            id: id,
            modeS: modeS,
            registration: (registration != id) ? registration : nil,
            flight: flight,
            latitude: lat,
            longitude: lon,
            track: track,
            altitudeFeet: altitude,
            speedKnots: speed,
            airlineName: AirlineNames.name(forFlight: flight)
        )
    }
}
