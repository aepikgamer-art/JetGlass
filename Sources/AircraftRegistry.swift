import Foundation

// MARK: - adsbdb.com registration lookup
// OpenSky live traffic gives us a modeS hex + callsign, but jetapi.dev needs a
// registration to find photos. adsbdb.com is a free static database that maps
// mode S hex -> registration / type / owner.

struct ADSBDBLookup: Codable {
    struct ADSBDBAircraft: Codable {
        let type: String?
        let manufacturer: String?
        let mode_s: String?
        let registration: String?
        let registered_owner: String?
        let registered_owner_country_name: String?
    }
    struct ADSBDBResponse: Codable {
        let aircraft: ADSBDBAircraft?
    }
    let response: ADSBDBResponse?
}

final class AircraftRegistry: @unchecked Sendable {
    static let shared = AircraftRegistry()

    private var cache: [String: ADSBDBLookup.ADSBDBAircraft] = [:]
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }

    /// Registration + type info for a mode S hex (e.g. "a4ad94"). Cached.
    func info(for modeS: String) async -> ADSBDBLookup.ADSBDBAircraft? {
        let key = modeS.trimmingCharacters(in: .whitespaces).uppercased()
        guard !key.isEmpty else { return nil }
        if let hit = cache[key] { return hit }
        guard let url = URL(string: "https://api.adsbdb.com/v0/aircraft/\(key)") else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            let decoded = try JSONDecoder().decode(ADSBDBLookup.self, from: data)
            if let aircraft = decoded.response?.aircraft {
                cache[key] = aircraft
                return aircraft
            }
        } catch {
            // Offline or unknown hex — caller falls back to live data only.
        }
        return nil
    }
}
