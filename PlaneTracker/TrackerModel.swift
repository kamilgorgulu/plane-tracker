import SwiftUI
import CoreLocation
import AVFoundation

@MainActor
final class TrackerModel: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var flights: [Flight] = []
    @Published var location: CLLocation?
    @Published var headingAccuracy: Double = -1
    @Published var source = L("Waiting for connection", "Bağlantı bekleniyor")
    @Published var status = L("Start with camera and location access.", "Kamera ve konum erişimiyle başlayın.")
    @Published var cameraAllowed = false
    @Published var locationDenied = false
    @Published var isLoading = false
    @Published var lastUpdate: Date?
    @Published var selected: Flight?
    @Published var enriching = false
    @Published var started = false
    @Published var provider: Provider = Provider(rawValue: UserDefaults.standard.string(forKey: "provider") ?? "") ?? .automatic
    @Published var radius: Double = UserDefaults.standard.double(forKey: "radius") == 0 ? 50 : UserDefaults.standard.double(forKey: "radius")
    @Published var headingOffset: Double = 0
    @Published var sessionID = UUID()
    @Published var trackingStatus = L("Preparing sensors", "Sensörler hazırlanıyor")
    @Published var routeDetails: [String: Flight] = [:]
    @Published var routeStatus: [String: String] = [:]
    @Published private(set) var trails: [String: [FlightSample]] = [:]
    @Published var language: AppLanguage = .current
    private let manager = CLLocationManager()
    private let service = FlightService()
    private var loop: Task<Void, Never>?
    private var detailsTask: Task<Void, Never>?
    private var active = true
    private var generation = UUID()

    var observer: GeoPoint? {
        guard let location, location.horizontalAccuracy >= 0, location.horizontalAccuracy < 200,
              abs(location.timestamp.timeIntervalSinceNow) < 60 else { return nil }
        return GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                        altitude: location.verticalAccuracy >= 0 ? location.altitude : 0)
    }
    // Indoor map searches can use a recent coarse fix; AR still requires observer.
    var searchCenter: GeoPoint? {
        guard let location, location.horizontalAccuracy >= 0, location.horizontalAccuracy < 3000,
              abs(location.timestamp.timeIntervalSinceNow) < 900 else { return nil }
        return GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, altitude: location.verticalAccuracy >= 0 ? location.altitude : 0)
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.headingFilter = 2
        manager.headingOrientation = .portrait
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            provider = .demo
            started = true
            makeDemo()
            if ProcessInfo.processInfo.arguments.contains("--demo-detail") { selected = flights.first }
        }
    }

    func start() {
        started = true
        if provider == .demo { makeDemo(); return }
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        Task {
            cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
            if !cameraAllowed { status = t("Camera access is off. Enable it in Settings; the flight list remains available.", "Kamera erişimi kapalı. Ayarlar'dan etkinleştirin; uçuş listesi kullanılabilir.") }
        }
        restart()
    }
    func setActive(_ value: Bool) {
        active = value
        if value && started {
            cameraAllowed = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            if provider != .demo { manager.startUpdatingLocation(); manager.startUpdatingHeading() }
            sessionID = UUID()
            restart()
        } else {
            loop?.cancel(); detailsTask?.cancel()
            manager.stopUpdatingLocation(); manager.stopUpdatingHeading()
        }
    }
    func applySettings(provider: Provider, radius: Double) {
        self.provider = provider
        self.radius = radius
        UserDefaults.standard.set(provider.rawValue, forKey: "provider")
        UserDefaults.standard.set(radius, forKey: "radius")
        flights = []; selected = nil; lastUpdate = nil
        routeDetails = [:]; routeStatus = [:]; trails = [:]
        source = t("Waiting for connection", "Bağlantı bekleniyor")
        sessionID = UUID()
        if provider == .demo { manager.stopUpdatingLocation(); manager.stopUpdatingHeading(); restart() }
        else { start() }
    }
    func exitDemo() {
        dismissSelection()
        status = t("Switching to live mode…", "Canlı moda geçiliyor…")
        applySettings(provider: .automatic, radius: radius)
    }
    func restart() {
        loop?.cancel()
        generation = UUID()
        let current = generation
        guard active && started else { return }
        if provider == .demo { makeDemo(); return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh(generation: current)
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }
    private func refresh(generation current: UUID) async {
        guard let center = searchCenter else {
            status = locationDenied ? t("Location access is off. Enable Precise Location in Settings.", "Konum erişimi kapalı. Ayarlar'dan Kesin Konum'u etkinleştirin.") : t("Waiting for GPS. Move outdoors and enable Precise Location.", "GPS bekleniyor. Açık alana çıkın ve Kesin Konum'u etkinleştirin.")
            return
        }
        isLoading = true
        defer { if current == generation { isLoading = false } }
        do {
            let result = try await service.fetch(provider: provider, center: center, radius: radius, key: TokenStore.read())
            guard !Task.isCancelled, current == generation else { return }
            for flight in result.flights { record(flight) }
            flights = result.flights.sorted { Geometry.distance(center, $0.point) < Geometry.distance(center, $1.point) }
            source = result.source
            lastUpdate = Date()
            let keys = Set(flights.map(routeKey))
            routeDetails = routeDetails.filter { keys.contains($0.key) }
            routeStatus = routeStatus.filter { keys.contains($0.key) }
            trails = trails.filter { keys.contains($0.key) }
            status = flights.isEmpty ? t("No current flights found in this area.", "Bu bölgede güncel uçuş bulunamadı.") : t("Tap a label to explore a flight.", "Bir uçuşu incelemek için etikete dokunun.")
            if observer == nil { status = t("Location is approximate or stale. Use the route map indoors; wait for outdoor GPS for camera alignment.", "Konum yaklaşık veya eski. İç mekânda rota haritasını kullanın; kamera hizalaması için açık havada GPS bekleyin.") }
            if let selected, let newer = flights.first(where: { $0.id == selected.id }) { select(newer) }
        } catch {
            guard !Task.isCancelled, current == generation else { return }
            status = error.localizedDescription
            flights.removeAll { Date().timeIntervalSince($0.timestamp) >= 60 }
        }
    }
    func select(_ flight: Flight) {
        detailsTask?.cancel()
        selected = flight
        enriching = !flight.isDemo
        detailsTask = Task {
            let enriched = await service.enrich(flight)
            guard !Task.isCancelled, selected?.id == flight.id else { return }
            selected = enriched
            enriching = false
        }
    }
    func dismissSelection() { detailsTask?.cancel(); selected = nil; enriching = false }

    func t(_ english: String, _ turkish: String) -> String { L(english, turkish, language: language) }

    func setLanguage(_ value: AppLanguage) {
        language = value
        UserDefaults.standard.set(value.rawValue, forKey: "appLanguage")
        if provider == .demo { makeDemo() }
        else {
            source = t("Waiting for next update", "Sonraki güncelleme bekleniyor")
            status = t("Language updated.", "Dil güncellendi.")
        }
    }

    func trail(for flight: Flight) -> [FlightSample] {
        trails[routeKey(flight)] ?? [FlightSample(timestamp: flight.timestamp, point: flight.point)]
    }

    private func record(_ flight: Flight) {
        let key = routeKey(flight)
        var samples = trails[key] ?? []
        guard samples.last?.timestamp != flight.timestamp else { return }
        if let last = samples.last {
            let interval = flight.timestamp.timeIntervalSince(last.timestamp)
            let distance = Geometry.distance(last.point, flight.point)
            if interval <= 0 { return }
            if interval > 900 || distance > max(50_000, (flight.speed ?? 250) * interval * 4) { samples.removeAll() }
        }
        samples.append(FlightSample(timestamp: flight.timestamp, point: flight.point))
        let cutoff = Date().addingTimeInterval(-6 * 60 * 60)
        samples = Array(samples.filter { $0.timestamp >= cutoff }.suffix(1_440))
        trails[key] = samples
    }

    func routeKey(_ flight: Flight) -> String { flight.id + ":" + flight.callsign }
    func loadRoute(_ flight: Flight) async {
        let key = routeKey(flight), current = generation
        if flight.isDemo { routeDetails[key] = flight; routeStatus[key] = t("DEMO · route and flight are simulated", "DEMO · rota ve uçuş örnektir"); return }
        routeStatus[key] = t("Looking up departure and destination airports…", "Kalkış ve varış havalimanları sorgulanıyor…")
        let detail = await service.enrich(flight)
        guard !Task.isCancelled, current == generation else { return }
        routeDetails[key] = detail
        if detail.originPoint != nil && detail.destinationPoint != nil {
            routeStatus[key] = t("Airports come from community data and may not match the current flight.", "Havalimanları topluluk verisinden gelir ve güncel uçuşla eşleşmeyebilir.")
        } else if detail.originPoint != nil || detail.destinationPoint != nil {
            routeStatus[key] = t("One airport is unavailable; only the known side is shown.", "Bir havalimanı bulunamadı; yalnızca bilinen taraf gösteriliyor.")
        } else {
            routeStatus[key] = t("Airport coordinates are unavailable for this flight.", "Bu uçuş için havalimanı koordinatları bulunamadı.")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationDenied = manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            if active && started && provider != .demo { manager.startUpdatingLocation(); manager.startUpdatingHeading() }
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let wasMissing = searchCenter == nil
        location = locations.last
        if wasMissing && searchCenter != nil { restart() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) { headingAccuracy = newHeading.headingAccuracy }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { status = t("Location is unavailable. Try again outdoors.", "Konum alınamıyor. Açık havada yeniden deneyin.") }
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }

    private func makeDemo() {
        source = t("DEMO · not a real flight", "DEMO · gerçek uçuş değil")
        status = t("Sample screen. Tap Exit demo to switch to live flights.", "Örnek ekran. Canlı uçuşlara geçmek için Demodan çık düğmesine dokunun.")
        let now = Date()
        let demo = Flight(id: "demo", callsign: "DEMO 101", point: GeoPoint(latitude: 41.1, longitude: 29.1, altitude: 10670), speed: 231, track: 310, timestamp: now, airline: "SAMPLE", aircraft: "A21N", registration: "SAMPLE", origin: "IST · Istanbul", destination: "BER · Berlin", isDemo: true, originPoint: GeoPoint(latitude: 41.2613, longitude: 28.7419, altitude: 0), destinationPoint: GeoPoint(latitude: 52.3667, longitude: 13.5033, altitude: 0))
        flights = [demo]
        let demoPoints = [
            GeoPoint(latitude: 41.2613, longitude: 28.7419, altitude: 0),
            GeoPoint(latitude: 41.23, longitude: 28.82, altitude: 1_900),
            GeoPoint(latitude: 41.20, longitude: 28.90, altitude: 4_300),
            GeoPoint(latitude: 41.17, longitude: 28.98, altitude: 7_200),
            GeoPoint(latitude: 41.14, longitude: 29.05, altitude: 9_600),
            demo.point
        ]
        trails[routeKey(demo)] = demoPoints.enumerated().map { index, point in
            FlightSample(timestamp: now.addingTimeInterval(Double(index - demoPoints.count + 1) * 180), point: point)
        }
        isLoading = false
    }
}
