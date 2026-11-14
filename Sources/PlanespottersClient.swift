import Foundation

// MARK: - Planespotters.net photo client
// The public API only supports exact lookups:
//   GET https://api.planespotters.net/pub/photos/reg/{REG}
//   GET https://api.planespotters.net/pub/photos/hex/{MODE-S HEX}

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

final class PlanespottersClient {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = [
            "User-Agent": "JetGlass/2.09 (+https://github.com/aepikgamer-art/JetGlass)"
        ]
        self.session = URLSession(configuration: config)
    }

    /// Looks up photos for a registration (or a 6-character Mode-S hex code).
    /// Returns [] when the aircraft simply has no photos on planespotters.
    func photos(reg: String) async throws -> [JetPhoto] {
        let term = reg
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard !term.isEmpty else { return [] }

        // A 6-char hex code is a Mode-S address - try that first.
        let isHex = term.count == 6 && term.allSatisfy { $0.isNumber || "ABCDEF".contains($0) }
        var kinds: [String] = ["reg"]
        if isHex { kinds = ["hex", "reg"] }

        for kind in kinds {
            let found = try await fetch(kind: kind, term: term)
            if !found.isEmpty { return found }
        }
        return []
    }

    private func fetch(kind: String, term: String) async throws -> [JetPhoto] {
        guard let url = URL(string: "https://api.planespotters.net/pub/photos/" + kind + "/" + term) else {
            return []
        }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if let http, http.statusCode == 404 { return [] }
            throw JetAPIError.http(http?.statusCode ?? 0)
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
