import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
    checks += 1
}
func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.01) -> Bool { abs(a - b) < tolerance }
check(L("English", "Türkçe", language: .english) == "English", "English localization")
check(L("English", "Türkçe", language: .turkish) == "Türkçe", "Turkish localization")
let observer = GeoPoint(latitude: 0, longitude: 0, altitude: 0)
let north = Geometry.vector(from: observer, to: GeoPoint(latitude: 1, longitude: 0, altitude: 10000))
let east = Geometry.vector(from: observer, to: GeoPoint(latitude: 0, longitude: 1, altitude: 10000))
check(north.z < -100000 && abs(north.x) < 1, "North must project along negative Z")
check(east.x > 100000 && abs(east.z) < 1, "East must project along positive X")
let overhead = Geometry.vector(from: observer, to: GeoPoint(latitude: 0, longitude: 0, altitude: 10000))
check(near(overhead.y, 10000) && near(overhead.x, 0), "Overhead is vertical")
check(near(Geometry.distance(observer, GeoPoint(latitude: 0, longitude: 1, altitude: 0)), 111194.927, 1), "Distance in metres")
let dateLine = Geometry.bounds(GeoPoint(latitude: 0, longitude: 179.9, altitude: 0), km: 100)
check(dateLine.west == -180 && dateLine.east == 180, "Date line bounds must remain valid")
let os = Data(#"{"time":100,"states":[["abcdef","THY123  ","Turkey",99,100,29,41,1000,false,200,90,0,null,1100],["ground","GROUND","Turkey",99,100,29,41,0,true,0,0,0,null,0],["nopos","NOPOS","Turkey",null,100,null,null,null,false,null,null,null,null,null]]}"#.utf8)
let flights = try FlightDecoder.openSky(os)
check(flights.count == 1, "Reject ground and no-position aircraft")
check(flights[0].callsign == "THY123", "Trim callsign")
check(flights[0].point.altitude == 1100 && flights[0].geometricAltitude, "Prefer geometric altitude")
check(flights[0].origin == nil && flights[0].airline == nil, "Do not invent route or carrier")
let emptySky = try FlightDecoder.openSky(Data(#"{"states":null}"#.utf8))
check(emptySky.isEmpty, "Null states are an empty sky")
let fr = Data(#"{"data":[{"fr24_id":"123","lat":41,"lon":29,"alt":10000,"gspeed":100,"timestamp":"2026-08-31T12:00:00.123Z","flight":"TK123","type":"A21N","operating_as":"THY","orig_iata":"IST","dest_iata":"BER"}]}"#.utf8)
let f = try FlightDecoder.fr24(fr)[0]
check(near(f.point.altitude, 3048), "FR24 feet to metres")
check(near(f.speed!, 51.4444), "FR24 knots to metres/second")
check(f.route == "IST → BER" && f.modelName == "Airbus A321neo", "FR24 metadata mapping")
let readsb = Data(#"{"now":1788177600000,"ac":[{"hex":"abcdef","flight":"TEST1 ","lat":41,"lon":29,"alt_baro":10000,"gs":100,"seen_pos":5},{"hex":"ground","lat":41,"lon":29,"alt_baro":"ground","alt_geom":100,"seen_pos":1}]}"#.utf8)
let rs = try FlightDecoder.readsb(readsb)
check(rs.count == 1 && near(rs[0].point.altitude, 3048), "Readsb ignores ground and converts altitude")
check(near(rs[0].timestamp.timeIntervalSince1970, 1788177595), "Readsb milliseconds and position age")
var moving = flights[0]
moving.point = observer
moving.speed = 200
moving.track = 90
moving.timestamp = Date(timeIntervalSince1970: 100)
let predicted = Geometry.predicted(moving, now: Date(timeIntervalSince1970: 110))
check(near(Geometry.distance(observer, predicted), 2000, 1), "Extrapolate using ground speed")
let capped = Geometry.predicted(moving, now: Date(timeIntervalSince1970: 200))
check(near(Geometry.distance(observer, capped), 3000, 1), "Cap extrapolation at 15 seconds")
do { _ = try FlightDecoder.fr24(Data(#"{"error":"unauthorized"}"#.utf8)); fatalError("Malformed responses must fail") } catch { checks += 1 }
for (path, decode) in [("/tmp/plane-tracker-opensky.json", FlightDecoder.openSky), ("/tmp/plane-tracker-lol.json", FlightDecoder.readsb), ("/tmp/plane-tracker-fi.json", FlightDecoder.readsb)] {
    if let data = FileManager.default.contents(atPath: path) {
        let live = try decode(data)
        check(!live.isEmpty, "Live fixture should contain airborne traffic: \(path)")
        print("Decoded \(live.count) live flights from \(URL(fileURLWithPath: path).lastPathComponent)")
    }
}
print("PASS: \(checks) geometry, units, timestamps and provider checks")
