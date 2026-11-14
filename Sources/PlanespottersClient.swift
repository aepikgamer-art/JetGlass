import Foundation

// MARK: - Planespotters.net photo client
// The public API only supports exact lookups:
//   GET https://api.planespotters.net/pub/photos/reg/{REG}
//   GET https://api.planespotters.net/pub/photos/hex/{MODE-S HEX}
// Fleet sweeps use the free adsb.lol live API to find aircraft by type or
// airline callsign, then pull each aircraft's photos from planespotters.
// Airline metadata (name / ICAO / IATA) comes from adsbdb.com.

struct PlanespottersResponse: Codable {
    let photos: [PlanespottersPhoto]
}

struct PlanespottersPhoto: Codable {
    let id: String?
    let link: String
    let photographer: String?
    let thumbnail: PlanespottersImage?
    let thumbnailLarge: PlanespottersImage?

    enum CodingKeys: String, CodingKey {
        case id, link, photographer, thumbnail
        case thumbnailLarge = "thumbnail_large"
    }
}

struct PlanespottersImage: Codable {
    let src: String
}

struct AdsblolResponse: Codable {
    let ac: [AdsblolAircraft]?
}

struct AdsblolAircraft: Codable {
    let hex: String?
    let r: String?
    let t: String?
    let flight: String?
}

struct AdsbdbAirlineResponse: Codable {
    let response: [AdsbdbAirline]?
}

struct AdsbdbAirline: Codable {
    let name: String
    let icao: String
    let iata: String?
}

final class PlanespottersClient {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = [
            "User-Agent": "JetGlass/2.10 (+https://github.com/aepikgamer-art/JetGlass)"
        ]
        self.session = URLSession(configuration: config)
    }

    static func classify(_ term: String) -> String {
        let digits = term.filter { $0.isNumber }.count
        let letters = term.filter { $0.isLetter }.count
        if term.count == 6, digits == 6 { return "hex" }
        if letters >= 1, digits >= 2, term.count <= 4 { return "type" }
        if digits >= 1, letters >= 1, term.count <= 10 { return "reg" }
        if digits == 0, letters == term.count, term.count <= 12 { return "airline" }
        if term.range(of: "airline") != nil || term.range(of: "airways") != nil
            || term.range(of: "aviation") != nil || term.range(of: "lines") != nil {
            return "airline"
        }
        return "reg"
    }

    static func typeFamilyCodes(for query: String) -> [String] {
        let q = query.uppercased()
        let families: [String: [String]] = [
            "A318": ["A318"], "A319": ["A319", "A19N"], "A320": ["A20N", "A320"],
            "A321": ["A21N", "A321"], "A220": ["BCS3", "BCS1"],
            "A330": ["A339", "A333"], "A340": ["A346"], "A350": ["A359", "A35K"],
            "A380": ["A388"],
            "737": ["B738", "B739", "B38M"], "B737": ["B738", "B739", "B38M"],
            "747": ["B748", "B744"], "B747": ["B748", "B744"],
            "757": ["B752"], "B757": ["B752"], "767": ["B763"], "B767": ["B763"],
            "777": ["B77W", "B77L"], "B777": ["B77W", "B77L"],
            "787": ["B788", "B789", "B78X"], "B787": ["B788", "B789", "B78X"],
            "E175": ["E75L", "E75S"], "E190": ["E290"],
        ]
        if let fam = families[q] { return fam + [q] }
        return [q]
    }

    static let sweepTypes = ["A20N", "B738", "B739", "B38M", "A320", "A21N", "A321", "A359", "B77W", "B788", "B789", "A339"]

    func photos(reg: String) async throws -> [JetPhoto] {
        let term = reg
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard !term.isEmpty else { return [] }

        let isHex = term.count == 6 && term.allSatisfy { $0.isNumber || "ABCDEF".contains($0) }
        var kinds: [String] = ["reg"]
        if isHex { kinds = ["hex", "reg"] }

        for kind in kinds {
            let found = try await fetch(kind: kind, term: term)
            if !found.isEmpty { return found }
        }
        return []
    }

    func photosForType(_ typeQuery: String) async throws -> [JetPhoto] {
        for code in PlanespottersClient.typeFamilyCodes(for: typeQuery) {
            let aircraft = try await adsblol(kind: "type", value: code)
            let photos = try await collectPhotos(from: aircraft)
            if !photos.isEmpty { return photos }
        }
        return []
    }

    func photosForAirline(icao: String) async throws -> [JetPhoto] {
        for code in PlanespottersClient.sweepTypes {
            let aircraft = try await adsblol(kind: "type", value: code)
            let mine = aircraft.filter { ac in
                ac.flight?.trimmingCharacters(in: .whitespaces).hasPrefix(icao) ?? false
            }
            if mine.isEmpty { continue }
            let photos = try await collectPhotos(from: mine)
            if !photos.isEmpty { return photos }
        }
        return []
    }

    func resolveAirline(_ query: String) async -> AdsbdbAirline? {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let url = URL(string: "https://api.adsbdb.com/v0/airline/" + term) else { return nil }
        guard let (data, _) = try? await session.data(from: url) else { return nil }
        return (try? JSONDecoder().decode(AdsbdbAirlineResponse.self, from: data))?.response?.first
    }

    private func adsblol(kind: String, value: String) async throws -> [AdsblolAircraft] {
        guard let url = URL(string: "https://api.adsb.lol/v2/" + kind + "/" + value) else { return [] }
        let (data, response) = try await session.data(from: url)
        let http = response as? HTTPURLResponse
        if let http, !(200...299).contains(http.statusCode) { return [] }
        return (try? JSONDecoder().decode(AdsblolResponse.self, from: data))?.ac ?? []
    }

    private func collectPhotos(from aircraft: [AdsblolAircraft]) async throws -> [JetPhoto] {
        var out: [JetPhoto] = []
        var seen = Set<String>()
        for ac in aircraft.prefix(24) {
            guard out.count < 60 else { break }
            guard let hex = ac.hex?.lowercased(), !hex.isEmpty, seen.insert(hex).inserted else { continue }
            let found = try await fetch(kind: "hex", term: hex.uppercased())
            let reg = ac.r ?? ""
            let labeled = found.map { p in
                JetPhoto(
                    image: p.image,
                    link: p.link,
                    thumbnail: p.thumbnail,
                    dateTaken: p.dateTaken,
                    dateUploaded: p.dateUploaded,
                    location: p.location,
                    photographer: p.photographer,
                    aircraft: reg,
                    serial: p.serial,
                    airline: p.airline
                )
            }
            out.append(contentsOf: labeled)
        }
        return out
    }

    private func fetch(kind: String, term: String) async throws -> [JetPhoto] {
        guard let url = URL(string: "https://api.planespotters.net/pub/photos/" + kind + "/" + term) else {
            return []
        }
        let (data, response) = try await session.data(from: url)
        let http = response as? HTTPURLResponse
        if let http, !(200...299).contains(http.statusCode) {
            if http.statusCode == 404 { return [] }
            throw JetAPIError.http(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(PlanespottersResponse.self, from: data)
        return decoded.photos.map { p in
            var large = p.thumbnailLarge?.src ?? p.thumbnail?.src ?? ""
            var small = p.thumbnail?.src ?? large
            if large.hasPrefix("//") { large = "https:" + large }
            if small.hasPrefix("//") { small = "https:" + small }
            let who = p.photographer ?? ""
            return JetPhoto(
                image: large,
                link: p.link,
                thumbnail: small,
                dateTaken: "",
                dateUploaded: "",
                location: "",
                photographer: who,
                aircraft: term,
                serial: "",
                airline: who
            )
        }
    }
}
