import Foundation
import Security

enum Provider: String, CaseIterable, Identifiable {
    case automatic, openSky, adsbLOL, adsbFI, flightradar, demo
    var id: String { rawValue }
    var name: String {
        switch self {
        case .automatic: return L("Automatic · free", "Otomatik · ücretsiz")
        case .openSky: return "OpenSky"
        case .adsbLOL: return "ADSB.lol"
        case .adsbFI: return "adsb.fi"
        case .flightradar: return "Flightradar24"
        case .demo: return L("Demo · not a real flight", "Demo · gerçek uçuş değil")
        }
    }
}

enum APIError: LocalizedError {
    case http(Int), missingKey, rateLimit, invalid
    var errorDescription: String? {
        switch self {
        case .http(let code): return L("Flight data service response: HTTP \(code).", "Uçuş veri servisi yanıtı: HTTP \(code).")
        case .missingKey: return L("A Flightradar24 API key is required. You can use Automatic free mode instead.", "Flightradar24 API anahtarı gerekli. Bunun yerine ücretsiz Otomatik modu kullanabilirsiniz.")
        case .rateLimit: return L("The service rate limit was reached. It will be retried later.", "Servis kotasına ulaşıldı. Daha sonra yeniden denenecek.")
        case .invalid: return L("The service did not return valid flight data.", "Servis geçerli uçuş verisi döndürmedi.")
        }
    }
}

actor FlightService {
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 12
        c.timeoutIntervalForResource = 18
        c.urlCache = nil
        return URLSession(configuration: c)
    }()
    private var blockedUntil: [Provider: Date] = [:]
    private var metadataCache: [String: (Date, Flight)] = [:]
    func fetch(provider: Provider, center: GeoPoint, radius: Double, key: String) async throws -> (flights: [Flight], source: String) {
        let candidates: [Provider] = provider == .automatic ? [.openSky, .adsbLOL, .adsbFI] : [provider]
        var lastError: Error = APIError.rateLimit
        for candidate in candidates {
            try Task.checkCancellation()
            if let until = blockedUntil[candidate], until > Date() { continue }
            do {
                let request = try makeRequest(candidate, center: center, radius: radius, key: key)
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw APIError.invalid }
                if http.statusCode == 429 {
                    let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 300
                    blockedUntil[candidate] = Date().addingTimeInterval(max(60, retry))
                    throw APIError.rateLimit
                }
                guard http.statusCode == 200 else { throw APIError.http(http.statusCode) }
                let flights: [Flight]
                switch candidate {
                case .openSky: flights = try FlightDecoder.openSky(data)
                case .flightradar: flights = try FlightDecoder.fr24(data)
                default: flights = try FlightDecoder.readsb(data)
                }
                var unique = Set<String>()
                let filtered = flights.filter {
                    let age = Date().timeIntervalSince($0.timestamp)
                    return age >= -10 && age < 60 && Geometry.distance(center, $0.point) <= radius * 1000 && unique.insert($0.id).inserted
                }
                return (filtered, candidate.name)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = error
                if blockedUntil[candidate] == nil || blockedUntil[candidate]! < Date() {
                    blockedUntil[candidate] = Date().addingTimeInterval(60)
                }
            }
        }
        throw lastError
    }

    private func makeRequest(_ provider: Provider, center: GeoPoint, radius: Double, key: String) throws -> URLRequest {
        let b = Geometry.bounds(center, km: radius)
        var components: URLComponents
        switch provider {
        case .openSky:
            components = URLComponents(string: "https://opensky-network.org/api/states/all")!
            components.queryItems = [URLQueryItem(name: "lamin", value: String(b.south)), URLQueryItem(name: "lamax", value: String(b.north)), URLQueryItem(name: "lomin", value: String(b.west)), URLQueryItem(name: "lomax", value: String(b.east))]
        case .flightradar:
            guard !key.isEmpty else { throw APIError.missingKey }
            components = URLComponents(string: "https://fr24api.flightradar24.com/api/live/flight-positions/full")!
            components.queryItems = [URLQueryItem(name: "bounds", value: "\(b.north),\(b.south),\(b.west),\(b.east)")]
        case .adsbFI:
            components = URLComponents(string: "https://opendata.adsb.fi/api/v3/lat/\(center.latitude)/lon/\(center.longitude)/dist/\(Int(ceil(radius / 1.852)))")!
        default:
            components = URLComponents(string: "https://api.adsb.lol/v2/point/\(center.latitude)/\(center.longitude)/\(Int(ceil(radius / 1.852)))")!
        }
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if provider == .flightradar {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("v1", forHTTPHeaderField: "Accept-Version")
        }
        return request
    }

    // Lookup only when a card is opened. No guessing routes from airline prefixes.
    func enrich(_ flight: Flight) async -> Flight {
        if flight.isDemo { return flight }
        let cacheKey = flight.id + ":" + flight.callsign
        if let cached = metadataCache[cacheKey], Date().timeIntervalSince(cached.0) < 1800 {
            return merge(flight, metadata: cached.1)
        }
        var result = flight
        if flight.aircraft == nil, flight.id.range(of: "^[0-9a-fA-F]{6}$", options: .regularExpression) != nil,
           let response = await lookup("aircraft/" + flight.id), let aircraft = response["aircraft"] as? [String: Any] {
            result.aircraft = aircraft["icao_type"] as? String ?? aircraft["type"] as? String
            result.registration = aircraft["registration"] as? String
        }
        if flight.originPoint == nil || flight.destinationPoint == nil,
           flight.callsign.range(of: "^[A-Z0-9]{3,8}$", options: .regularExpression) != nil,
           let response = await lookup("callsign/" + flight.callsign), let route = response["flightroute"] as? [String: Any] {
            func airport(_ key: String) -> String? {
                guard let item = route[key] as? [String: Any] else { return nil }
                let code = item["iata_code"] as? String ?? item["icao_code"] as? String
                let city = item["municipality"] as? String
                return [code, city].compactMap { $0 }.joined(separator: " · ")
            }
            result.origin = flight.origin ?? airport("origin")
            result.destination = flight.destination ?? airport("destination")
            func coordinate(_ key: String) -> GeoPoint? {
                guard let item = route[key] as? [String: Any], let lat = item["latitude"] as? Double,
                      let lon = item["longitude"] as? Double, abs(lat) <= 90, abs(lon) <= 180 else { return nil }
                let known = key == "origin" ? flight.origin : flight.destination
                if let known {
                    let code = known.components(separatedBy: " · ").first ?? known
                    guard code == item["iata_code"] as? String || code == item["icao_code"] as? String else { return nil }
                }
                return GeoPoint(latitude: lat, longitude: lon, altitude: 0)
            }
            result.originPoint = coordinate("origin")
            result.destinationPoint = coordinate("destination")
            result.airline = flight.airline ?? ((route["airline"] as? [String: Any])?["icao"] as? String)
            result.metadataFromCommunity = true
        }
        if metadataCache.count > 200 { metadataCache.removeAll() }
        metadataCache[cacheKey] = (Date(), result)
        return result
    }
    private func merge(_ flight: Flight, metadata: Flight) -> Flight {
        var result = flight
        result.aircraft = flight.aircraft ?? metadata.aircraft
        result.registration = flight.registration ?? metadata.registration
        result.origin = flight.origin ?? metadata.origin
        result.destination = flight.destination ?? metadata.destination
        result.airline = flight.airline ?? metadata.airline
        result.metadataFromCommunity = metadata.metadataFromCommunity
        result.originPoint = flight.originPoint ?? metadata.originPoint
        result.destinationPoint = flight.destinationPoint ?? metadata.destinationPoint
        return result
    }
    private func lookup(_ path: String) async -> [String: Any]? {
        guard !Task.isCancelled, let url = URL(string: "https://api.adsbdb.com/v0/" + path),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return root["response"] as? [String: Any]
    }
}

enum TokenStore {
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "PlaneTracker.FR24", kSecAttrAccount as String: "personal-token"] }
    static func read() -> String {
        var q = query
        q[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ token: String) -> Bool {
        if token.isEmpty { let status = SecItemDelete(query as CFDictionary); return status == errSecSuccess || status == errSecItemNotFound }
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { return SecItemAdd(query.merging(attributes) { _, b in b } as CFDictionary, nil) == errSecSuccess }
        return status == errSecSuccess
    }
}
