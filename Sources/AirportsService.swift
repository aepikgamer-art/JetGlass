import Foundation

/// Loads the bundled airport database and resolves ICAO codes.
final class AirportsService {
    static let shared = AirportsService()

    private(set) var airports: [Airport] = []
    private var byICAO: [String: Airport] = [:]

    private init() {
        guard let url = Bundle.main.url(forResource: "Airports", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode([Airport].self, from: data) else {
            airports = []
            return
        }
        airports = loaded
        byICAO = Dictionary(uniqueKeysWithValues: loaded.map { ($0.icao.uppercased(), $0) })
    }

    func airport(forICAO icao: String) -> Airport? {
        byICAO[icao.trimmingCharacters(in: .whitespaces).uppercased()]
    }

    /// Fuzzy search by ICAO, IATA, name or city — used by the map search field.
    func search(_ query: String, limit: Int = 8) -> [Airport] {
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        guard !q.isEmpty else { return [] }
        if q.count == 4, let exact = byICAO[q] { return [exact] }
        return airports.filter {
            $0.icao.hasPrefix(q) || $0.iata.hasPrefix(q)
                || $0.name.uppercased().contains(q)
                || $0.city.uppercased().contains(q)
        }.prefix(limit).map { $0 }
    }
}
