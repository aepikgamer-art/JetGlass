import Foundation

enum JetAPIError: LocalizedError {
    case badQuery
    case http(Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .badQuery: return "Queries can only contain letters, numbers and dashes."
        case .http(let code):
            if code == 404 { return "No aircraft found for that search." }
            return "jetapi.dev returned error \(code). Try again in a bit."
        case .decoding: return "Couldn't read the response from jetapi.dev."
        }
    }
}

/// Thin client for https://www.jetapi.dev
/// GET /api?reg=<query>&photos=N&flights=N
final class JetAPIClient {
    private let session: URLSession
    private var baseURL: URL

    init(baseURLString: String) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
        self.baseURL = URL(string: baseURLString) ?? URL(string: "https://www.jetapi.dev")!
    }

    func updateBaseURL(_ string: String) {
        if let url = URL(string: string) { baseURL = url }
    }

    /// Searches JetPhotos (and optionally FlightRadar24) for a registration or keyword query.
    func lookup(query: String, photos: Int, flights: Int, onlyJetPhotos: Bool = false) async throws -> JetAPIResponse {
        let sanitized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: " ", with: "-")
        guard !sanitized.isEmpty,
              sanitized.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            throw JetAPIError.badQuery
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("api"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "reg", value: sanitized),
            URLQueryItem(name: "photos", value: String(photos)),
            URLQueryItem(name: "flights", value: String(flights)),
        ]
        if onlyJetPhotos {
            components?.queryItems?.append(URLQueryItem(name: "only_jp", value: "true"))
        }
        guard let url = components?.url else { throw JetAPIError.badQuery }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw JetAPIError.http(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(JetAPIResponse.self, from: data)
        } catch {
            throw JetAPIError.decoding
        }
    }

    func imageCacheURL(for photo: JetPhoto) -> URL? { photo.imageURL }
}
