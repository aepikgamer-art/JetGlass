import Foundation

// MARK: - JetAPI models (jetapi.dev)

struct JetAPIResponse: Codable {
    let jetPhotos: JetPhotosResult?
    let flightRadar: FlightRadarResult?

    enum CodingKeys: String, CodingKey {
        case jetPhotos = "JetPhotos"
        case flightRadar = "FlightRadar"
    }
}

struct JetPhotosResult: Codable {
    let reg: String
    let images: [JetPhoto]

    enum CodingKeys: String, CodingKey {
        case reg = "Reg"
        case images = "Images"
    }
}

struct JetPhoto: Codable, Identifiable, Hashable {
    let image: String
    let link: String
    let thumbnail: String
    let dateTaken: String
    let dateUploaded: String
    let location: String
    let photographer: String
    let aircraft: String
    let serial: String
    let airline: String

    var id: String { link }

    enum CodingKeys: String, CodingKey {
        case image = "Image"
        case link = "Link"
        case thumbnail = "Thumbnail"
        case dateTaken = "DateTaken"
        case dateUploaded = "DateUploaded"
        case location = "Location"
        case photographer = "Photographer"
        case aircraft = "Aircraft"
        case serial = "Serial"
        case airline = "Airline"
    }

    var thumbnailURL: URL? { URL(string: thumbnail.hasPrefix("http") ? thumbnail : "https:" + thumbnail) }
    var imageURL: URL? { URL(string: image) }
}

struct FlightRadarResult: Codable {
    let aircraft: String
    let airline: String
    let operatorName: String
    let typeCode: String
    let airlineCode: String
    let operatorCode: String
    let modeS: String
    let flights: [FlightRecord]

    enum CodingKeys: String, CodingKey {
        case aircraft = "Aircraft"
        case airline = "Airline"
        case operatorName = "Operator"
        case typeCode = "TypeCode"
        case airlineCode = "AirlineCode"
        case operatorCode = "OperatorCode"
        case modeS = "ModeS"
        case flights = "Flights"
    }
}

struct FlightRecord: Codable, Identifiable, Hashable {
    let date: String
    let from: String
    let to: String
    let flight: String
    let flightTime: String
    let std: String
    let atd: String
    let sta: String
    let status: String

    var id: String { "\(flight)-\(date)-\(std)" }
    var routeDisplay: String { "\(from) → \(to)" }

    enum CodingKeys: String, CodingKey {
        case date = "Date"
        case from = "From"
        case to = "To"
        case flight = "Flight"
        case flightTime = "FlightTime"
        case std = "STD"
        case atd = "ATD"
        case sta = "STA"
        case status = "Status"
    }
}

// MARK: - Live traffic

struct LiveAircraft: Identifiable, Hashable {
    let id: String
    let modeS: String
    let registration: String?
    let flight: String?
    let latitude: Double
    let longitude: Double
    let track: Double
    let altitudeFeet: Int
    let speedKnots: Int
    var airlineName: String?
    var type: String?

    var coordinateDescription: String {
        String(format: "%.3f, %.3f", latitude, longitude)
    }

    var altitudeDisplay: String {
        altitudeFeet >= 18000 ? "FL\(altitudeFeet / 100)" : "\(altitudeFeet) ft"
    }
}

// MARK: - Airports

struct Airport: Codable, Identifiable, Hashable {
    let icao: String
    let iata: String
    let name: String
    let city: String
    let country: String
    let latitude: Double
    let longitude: Double

    var id: String { icao }
}


// MARK: - Airline ICAO code lookup (common carriers)

enum AirlineNames {
    static let map: [String: String] = [
        "AAL": "American Airlines",
        "UAL": "United Airlines",
        "DAL": "Delta Air Lines",
        "SWA": "Southwest Airlines",
        "ASA": "Alaska Airlines",
        "JBU": "JetBlue",
        "NKS": "Spirit",
        "FFT": "Frontier",
        "HAL": "Hawaiian Airlines",
        "ACA": "Air Canada",
        "WJA": "WestJet",
        "VOZ": "Volaris",
        "VIV": "Viva Aerobus",
        "AMX": "Aeromexico",
        "BAW": "British Airways",
        "VIR": "Virgin Atlantic",
        "EZY": "easyJet",
        "RYR": "Ryanair",
        "DLH": "Lufthansa",
        "AFR": "Air France",
        "KLM": "KLM",
        "IBE": "Iberia",
        "SWR": "SWISS",
        "AUA": "Austrian",
        "SAS": "SAS",
        "FIN": "Finnair",
        "TAP": "TAP Air Portugal",
        "LOT": "LOT Polish",
        "THY": "Turkish Airlines",
        "UAE": "Emirates",
        "ETD": "Etihad",
        "QTR": "Qatar Airways",
        "SIA": "Singapore Airlines",
        "CPA": "Cathay Pacific",
        "ANA": "ANA",
        "JAL": "Japan Airlines",
        "KAL": "Korean Air",
        "AAR": "Asiana",
        "CCA": "Air China",
        "CES": "China Eastern",
        "CSN": "China Southern",
        "QFA": "Qantas",
        "ANZ": "Air New Zealand",
        "ETH": "Ethiopian Airlines",
        "MSR": "EgyptAir",
        "SAA": "South African",
        "RAM": "Royal Air Maroc",
        "FDX": "FedEx",
        "UPS": "UPS",
        "GTI": "Atlas Air",
        "CLX": "Cargolux",
        "AIC": "Air India",
        "SVA": "Saudia",
        "IRA": "Iran Air",
        "PGT": "Pegasus",
        "AYT": "Ajet",
        "TVF": "Transavia",
        "SXS": "SunExpress",
        "EIN": "Aer Lingus",
        "NAX": "Norwegian",
        "WZZ": "Wizz Air",
        "VLG": "Vueling",
        "ONE": "Avianca",
        "LAN": "LATAM",
        "GLO": "GOL",
        "AZU": "Azul",
        "ARG": "Aerolineas Argentinas",
        "CMP": "Copa Airlines",
        "LPE": "LATAM Peru",
        "RPA": "Republic",
        "EDV": "Endeavor",
        "SKW": "SkyWest",
        "ENY": "Envoy",
        "JZA": "Jazz",
    ]

    static func name(forFlight flight: String?) -> String? {
        guard let flight, flight.count >= 3 else { return nil }
        let prefix = String(flight.prefix(3)).uppercased()
        return map[prefix]
    }
}
