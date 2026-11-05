import Foundation
import MapKit

enum LiveFeedError: LocalizedError {
    case badResponse
    var errorDescription: String? { "Couldn't reach any live traffic feed. Try panning or refreshing." }
}

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

    func aircraft(in region: MKCoordinateRegion) async throws -> [LiveAircraft] {
        let latMin = max(-90.0, region.center.latitude - region.span.latitudeDelta)
        let latMax = min(90.0, region.center.latitude + region.span.latitudeDelta)
        let lonMin = max(-180.0, region.center.longitude - region.span.longitudeDelta)
        let lonMax = min(180.0, region.center.longitude + region.span.longitudeDelta)

        if let planes = try? await fetchADSBLoL(center: region.center, region: region), !planes.isEmpty {
            return planes.filter {
                $0.latitude >= latMin && $0.latitude <= latMax &&
                $0.longitude >= lonMin && $0.longitude <= lonMax
            }
        }

        if let planes = try? await fetchFR24(latMin: latMin, latMax: latMax, lonMin: lonMin, lonMax: lonMax), !planes.isEmpty {
            return planes
        }

        return try await fetchOpenSky(latMin: latMin, latMax: latMax, lonMin: lonMin, lonMax: lonMax)
    }

    private func fetchADSBLoL(center: CLLocationCoordinate2D, region: MKCoordinateRegion) async throws -> [LiveAircraft] {
        let lonScale = abs(cos(center.latitude * .pi / 180))
        let spanNm = max(region.span.latitudeDelta, region.span.longitudeDelta * lonScale) * 69.0
        let radius = min(250.0, max(25.0, spanNm * 0.75))
        let urlString = "https://api.adsb.lol/v2/point/\(center.latitude)/\(center.longitude)/\(Int(radius))"
        guard let url = URL(string: urlString) else { throw LiveFeedError.badResponse }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw LiveFeedError.badResponse
        }
        return try Self.parseADSBLoL(data)
    }

    static func parseADSBLoL(_ data: Data) throws -> [LiveAircraft] {
        let json = try? JSONSerialization.jsonObject(with: data)
        guard let object = json as? [String: Any], let ac = object["ac"] as? [[String: Any]] else {
            throw LiveFeedError.badResponse
        }
        return ac.compactMap(Self.aircraft(fromADSBLoLRow:))
    }

    static func aircraft(fromADSBLoLRow ac: [String: Any]) -> LiveAircraft? {
        guard let lat = (ac["lat"] as? NSNumber)?.doubleValue,
              let lon = (ac["lon"] as? NSNumber)?.doubleValue else { return nil }

        let modeS = ((ac["hex"] as? String) ?? "??????").trimmingCharacters(in: .whitespaces)
        let flight = (ac["flight"] as? String)?.trimmingCharacters(in: .whitespaces)
        let registration = (ac["r"] as? String)?.trimmingCharacters(in: .whitespaces)
        let typeCode = (ac["t"] as? String)?.trimmingCharacters(in: .whitespaces)

        var altitudeFeet = 0
        if let alt = ac["alt_baro"] as? NSNumber {
            altitudeFeet = alt.intValue
        } else if let alt = ac["alt_baro"] as? String {
            altitudeFeet = alt.lowercased() == "ground" ? 0 : (Int(alt) ?? 0)
        }
        let speedKnots = Int((ac["gs"] as? NSNumber)?.doubleValue ?? 0)
        let track = (ac["track"] as? NSNumber)?.doubleValue ?? 0

        let id = modeS
        return LiveAircraft(
            id: id,
            modeS: modeS,
            registration: (registration?.isEmpty == false) ? registration : nil,
            flight: (flight?.isEmpty == false) ? flight : nil,
            latitude: lat,
            longitude: lon,
            track: track,
            altitudeFeet: altitudeFeet,
            speedKnots: speedKnots,
            airlineName: AirlineNames.name(forFlight: flight),
            type: (typeCode?.isEmpty == false) ? typeCode?.uppercased() : nil
        )
    }

    private func fetchFR24(latMin: Double, latMax: Double, lonMin: Double, lonMax: Double) async throws -> [LiveAircraft] {
        let bounds = "\(latMax),\(latMin),\(lonMin),\(lonMax)"
        let urlString = "https://data.flightradar24.com/zones/fcgi/feed.js"
            + "?bounds=\(bounds)&faa=1&sat=1&mlat=1&flarm=1&adsb=1&gnd=1&air=1"
            + "&vehicles=0&estimated=1&maxage=14400&gliders=0&stats=1"
        guard let url = URL(string: urlString) else { throw LiveFeedError.badResponse }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw LiveFeedError.badResponse
        }
        return try Self.parseFR24(data)
    }

    static func parseFR24(_ data: Data) throws -> [LiveAircraft] {
        let json = try? JSONSerialization.jsonObject(with: data)
        guard let object = json as? [String: Any] else { throw LiveFeedError.badResponse }

        var rows: [[Any]] = []
        if let aircraft = object["aircraft"] as? [[Any]] {
            rows = aircraft
        } else {
            for (_, value) in object where value is [Any] {
                if let row = value as? [Any] { rows.append(row) }
            }
        }
        return rows.compactMap(Self.aircraft(fromFRRow:))
    }

    static func aircraft(fromFRRow row: [Any]) -> LiveAircraft? {
        let strings = row.compactMap { $0 as? String }
        let numbers = row.compactMap { ($0 as? NSNumber)?.doubleValue }

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

        let track = latIndex + 2 < numbers.count ? numbers[latIndex + 2] : 0
        let altitude = latIndex + 3 < numbers.count ? Int(numbers[latIndex + 3]) : 0
        let speed = latIndex + 4 < numbers.count ? Int(numbers[latIndex + 4]) : 0

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
            airlineName: AirlineNames.name(forFlight: flight),
            type: nil
        )
    }

    private func fetchOpenSky(latMin: Double, latMax: Double, lonMin: Double, lonMax: Double) async throws -> [LiveAircraft] {
        let urlString = "https://opensky-network.org/api/states/all"
            + "?lamin=\(latMin)&lomin=\(lonMin)&lamax=\(latMax)&lomax=\(lonMax)"
        guard let url = URL(string: urlString) else { throw LiveFeedError.badResponse }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw LiveFeedError.badResponse
        }
        return try Self.parseOpenSky(data)
    }

    static func parseOpenSky(_ data: Data) throws -> [LiveAircraft] {
        let json = try? JSONSerialization.jsonObject(with: data)
        guard let object = json as? [String: Any], let states = object["states"] as? [[Any]] else {
            throw LiveFeedError.badResponse
        }
        return states.compactMap(Self.aircraft(fromOpenSkyRow:))
    }

    static func aircraft(fromOpenSkyRow row: [Any]) -> LiveAircraft? {
        func num(_ i: Int) -> Double? {
            guard i < row.count, let n = row[i] as? NSNumber else { return nil }
            return n.doubleValue
        }
        func str(_ i: Int) -> String? {
            guard i < row.count, let s = row[i] as? String, !s.isEmpty else { return nil }
            return s.trimmingCharacters(in: .whitespaces)
        }

        guard let lon = num(5), let lat = num(6) else { return nil }
        let modeS = str(0) ?? "??????"
        let callsign = str(1)
        let onGround = row.count > 8 ? ((row[8] as? NSNumber)?.boolValue ?? false) : false
        let baroAltM = num(7) ?? num(13)
        let velocity = num(9) ?? 0
        let track = num(10) ?? 0

        let altitudeFeet = onGround ? 0 : Int((baroAltM ?? 0) * 3.28084)
        let speedKnots = Int(velocity * 1.94384)

        return LiveAircraft(
            id: modeS,
            modeS: modeS,
            registration: nil,
            flight: callsign,
            latitude: lat,
            longitude: lon,
            track: track,
            altitudeFeet: altitudeFeet,
            speedKnots: speedKnots,
            airlineName: AirlineNames.name(forFlight: callsign),
            type: nil
        )
    }

    // MARK: - Route lookup (adsbdb)

    func route(callsign: String) async -> ADSBRoute? {
        let cs = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        guard cs.count >= 3,
              let url = URL(string: "https://api.adsbdb.com/v0/callsign/" + cs) else { return nil }
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
        return (try? JSONDecoder().decode(ADSBDBRouteResponse.self, from: data))?.response?.flightroute
    }
}

struct ADSBDBAirport: Codable {
    let icaoCode: String
    let iataCode: String
    let name: String
    let municipality: String
    let countryName: String
    let latitude: Double
    let longitude: Double

    enum CodingKeys: String, CodingKey {
        case icaoCode = "icao_code"
        case iataCode = "iata_code"
        case name
        case municipality
        case countryName = "country_name"
        case latitude
        case longitude
    }
}

struct ADSBRoute: Codable {
    let origin: ADSBDBAirport
    let destination: ADSBDBAirport
}

struct ADSBDBRouteResponse: Codable {
    struct Inner: Codable { let flightroute: ADSBRoute? }
    let response: Inner?
}
