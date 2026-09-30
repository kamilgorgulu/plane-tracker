import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case turkish = "tr"

    var id: String { rawValue }
    var name: String { self == .english ? "English" : "Türkçe" }
    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .english
    }
}

func L(_ english: String, _ turkish: String, language: AppLanguage = .current) -> String {
    language == .turkish ? turkish : english
}

struct GeoPoint: Equatable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
}

struct FlightSample: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let point: GeoPoint

    init(id: UUID = UUID(), timestamp: Date, point: GeoPoint) {
        self.id = id
        self.timestamp = timestamp
        self.point = point
    }
}

struct Flight: Identifiable, Equatable {
    let id: String
    var callsign: String
    var point: GeoPoint
    var speed: Double?
    var track: Double?
    var timestamp: Date
    var airline: String?
    var aircraft: String?
    var registration: String?
    var origin: String?
    var destination: String?
    var geometricAltitude: Bool = false
    var isDemo: Bool = false
    var metadataFromCommunity: Bool = false
    var originPoint: GeoPoint?
    var destinationPoint: GeoPoint?

    var title: String { callsign.isEmpty ? id.uppercased() : callsign }
    var route: String { "\(origin ?? L("Unknown", "Bilinmiyor")) → \(destination ?? L("Unknown", "Bilinmiyor"))" }
    var airlineName: String {
        if airline == "SAMPLE" { return L("Sample Airline", "Örnek Havayolu") }
        return Self.airlines[airline ?? ""] ?? airline ?? L("Not provided", "Sağlanmadı")
    }
    var modelName: String { Self.models[aircraft ?? ""] ?? aircraft ?? L("Not provided", "Sağlanmadı") }
    static let airlines = ["PGT": "Pegasus", "AJT": "AJet", "SXS": "SunExpress", "DLH": "Lufthansa", "BAW": "British Airways", "UAE": "Emirates", "QTR": "Qatar Airways", "KLM": "KLM", "AFR": "Air France"]
    static let models = ["A320": "Airbus A320", "A321": "Airbus A321", "A20N": "Airbus A320neo", "A21N": "Airbus A321neo", "A319": "Airbus A319", "A333": "Airbus A330-300", "A359": "Airbus A350-900", "B738": "Boeing 737-800", "B38M": "Boeing 737 MAX 8", "B77W": "Boeing 777-300ER", "B789": "Boeing 787-9"]
}

enum Geometry {
    static let radius = 6_371_000.0
    static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    static func distance(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let lat = radians(b.latitude - a.latitude), lon = radians(b.longitude - a.longitude)
        let h = pow(sin(lat / 2), 2) + cos(radians(a.latitude)) * cos(radians(b.latitude)) * pow(sin(lon / 2), 2)
        return 2 * radius * asin(sqrt(min(1, max(0, h))))
    }
    // Earth-centred coordinates converted to local east, up, south (ARKit).
    // Includes Earth curvature, rather than treating distant aircraft as a flat map.
    static func vector(from observer: GeoPoint, to target: GeoPoint) -> SIMD3<Double> {
        func ecef(_ p: GeoPoint) -> SIMD3<Double> {
            let lat = radians(p.latitude), lon = radians(p.longitude), r = radius + p.altitude
            return SIMD3(r * cos(lat) * cos(lon), r * cos(lat) * sin(lon), r * sin(lat))
        }
        let d = ecef(target) - ecef(observer), lat = radians(observer.latitude), lon = radians(observer.longitude)
        let east = -sin(lon) * d.x + cos(lon) * d.y
        let north = -sin(lat) * cos(lon) * d.x - sin(lat) * sin(lon) * d.y + cos(lat) * d.z
        let up = cos(lat) * cos(lon) * d.x + cos(lat) * sin(lon) * d.y + sin(lat) * d.z
        return SIMD3(east, up, -north)
    }
    static func predicted(_ flight: Flight, now: Date) -> GeoPoint {
        guard let speed = flight.speed, let track = flight.track else { return flight.point }
        let age = min(15, max(0, now.timeIntervalSince(flight.timestamp)))
        return destination(from: flight.point, bearing: track, metres: speed * age)
    }
    static func destination(from point: GeoPoint, bearing degrees: Double, metres: Double) -> GeoPoint {
        let angular = metres / radius, bearing = radians(degrees)
        let lat = radians(point.latitude), lon = radians(point.longitude)
        let newLat = asin(sin(lat) * cos(angular) + cos(lat) * sin(angular) * cos(bearing))
        let newLon = lon + atan2(sin(bearing) * sin(angular) * cos(lat), cos(angular) - sin(lat) * sin(newLat))
        return GeoPoint(latitude: newLat * 180 / .pi, longitude: (newLon * 180 / .pi + 540).truncatingRemainder(dividingBy: 360) - 180, altitude: point.altitude)
    }
    static func bounds(_ center: GeoPoint, km: Double) -> (south: Double, north: Double, west: Double, east: Double) {
        let latDelta = km / 111.0, lonDelta = min(180, latDelta / max(0.01, cos(radians(center.latitude))))
        let west = center.longitude - lonDelta, east = center.longitude + lonDelta
        // A full longitude band safely covers requests that cross the date line.
        return (max(-90, center.latitude - latDelta), min(90, center.latitude + latDelta), west < -180 || east > 180 ? -180 : west, west < -180 || east > 180 ? 180 : east)
    }
}

enum FlightDecoder {
    static func readsb(_ data: Data) throws -> [Flight] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = (root["ac"] ?? root["aircraft"]) as? [[String: Any]] else { throw DecodeError.invalid }
        let rawNow = root["now"] as? Double ?? Date().timeIntervalSince1970
        let now = rawNow > 1e12 ? rawNow / 1000 : rawNow
        return rows.compactMap { row in
            guard let id = row["hex"] as? String, let lat = row["lat"] as? Double,
                  let lon = row["lon"] as? Double,
                  (row["alt_baro"] as? String) != "ground",
                  let altitude = (row["alt_geom"] as? Double) ?? (row["alt_baro"] as? Double),
                  let seen = row["seen_pos"] as? Double, abs(lat) <= 90, abs(lon) <= 180 else { return nil }
            return Flight(id: id, callsign: (row["flight"] as? String ?? "").trimmingCharacters(in: .whitespaces),
                          point: GeoPoint(latitude: lat, longitude: lon, altitude: altitude * 0.3048),
                          speed: (row["gs"] as? Double).map { $0 * 0.514444 }, track: row["track"] as? Double,
                          timestamp: Date(timeIntervalSince1970: now - seen), aircraft: row["t"] as? String,
                          registration: row["r"] as? String, geometricAltitude: row["alt_geom"] is Double)
        }
    }
    static func openSky(_ data: Data) throws -> [Flight] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DecodeError.invalid }
        if root["states"] is NSNull { return [] }
        guard let states = root["states"] as? [[Any]] else { throw DecodeError.invalid }
        return states.compactMap { row in
            guard row.count >= 14, let id = row[0] as? String,
                  let lon = row[5] as? Double, let lat = row[6] as? Double,
                  let altitude = (row[13] as? Double) ?? (row[7] as? Double),
                  let time = row[3] as? Double, let ground = row[8] as? Bool, !ground,
                  abs(lat) <= 90, abs(lon) <= 180 else { return nil }
            return Flight(id: id, callsign: (row[1] as? String ?? "").trimmingCharacters(in: .whitespaces),
                          point: GeoPoint(latitude: lat, longitude: lon, altitude: altitude),
                          speed: row[9] as? Double, track: row[10] as? Double,
                          timestamp: Date(timeIntervalSince1970: time), geometricAltitude: row[13] is Double)
        }
    }
    static func fr24(_ data: Data) throws -> [Flight] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["data"] as? [[String: Any]] else { throw DecodeError.invalid }
        return rows.compactMap { row in
            guard let id = row["fr24_id"] as? String, let lat = row["lat"] as? Double,
                  let lon = row["lon"] as? Double, let alt = row["alt"] as? Double, alt > 0,
                  let stamp = row["timestamp"] as? String, let date = parseDate(stamp),
                  abs(lat) <= 90, abs(lon) <= 180 else { return nil }
            func value(_ key: String) -> String? {
                guard let v = row[key] as? String, !v.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                return v
            }
            return Flight(id: id, callsign: value("flight") ?? value("callsign") ?? "",
                          point: GeoPoint(latitude: lat, longitude: lon, altitude: alt * 0.3048),
                          speed: (row["gspeed"] as? Double).map { $0 * 0.514444 }, track: row["track"] as? Double,
                          timestamp: date, airline: value("operating_as"), aircraft: value("type"),
                          registration: value("reg"), origin: value("orig_iata") ?? value("orig_icao"),
                          destination: value("dest_iata") ?? value("dest_icao"))
        }
    }
    static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value)
    }
    enum DecodeError: Error { case invalid }
}
