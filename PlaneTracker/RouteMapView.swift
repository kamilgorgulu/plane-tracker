import SwiftUI
import MapKit
import Charts

private extension GeoPoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

struct RouteMapView: View {
    @ObservedObject var model: TrackerModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?
    @State private var position: MapCameraPosition = .automatic
    @State private var detailFlight: Flight?
    var initialFlightID: String?
    private var flight: Flight? { model.flights.first { $0.id == selection } }
    private var key: String { flight.map(model.routeKey) ?? "" }
    private var metadata: Flight? { model.routeDetails[key] ?? flight }
    private var samples: [FlightSample] { flight.map(model.trail) ?? [] }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Map(position: $position, interactionModes: [.pan, .zoom], selection: $selection) {
                    UserAnnotation()
                    if let flight {
                        if samples.count > 1 {
                            MapPolyline(coordinates: samples.map(\.point.coordinate))
                                .stroke(.cyan, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        }
                        if let origin = metadata?.originPoint {
                            Marker("\(t("Departure", "Kalkış")) · \(metadata?.origin ?? "")", systemImage: "airplane.departure", coordinate: origin.coordinate).tint(.cyan)
                        }
                        if let destination = metadata?.destinationPoint {
                            MapPolyline(coordinates: [flight.point.coordinate, destination.coordinate], contourStyle: .geodesic)
                                .stroke(.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 6]))
                            Marker("\(t("Destination", "Varış")) · \(metadata?.destination ?? "")", systemImage: "target", coordinate: destination.coordinate).tint(.orange)
                        }
                    }
                    ForEach(model.flights) { item in
                        Annotation(item.title, coordinate: item.point.coordinate) {
                            Image(systemName: "airplane")
                                .font(.system(size: item.id == selection ? 25 : 18, weight: .bold))
                                .rotationEffect(.degrees((item.track ?? 90) - 90))
                                .foregroundStyle(item.id == selection ? .black : .white)
                                .padding(10)
                                .background(item.id == selection ? Color.mint : Color.black.opacity(0.75), in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1))
                                .accessibilityLabel(t("Show the route for \(item.title)", "\(item.title) rotasını göster"))
                        }.tag(item.id)
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .mapControls { MapScaleView() }
                .safeAreaInset(edge: .bottom, spacing: 0) { routeCard(now: context.date) }
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        legend(.cyan, t("Observed flight path", "Gözlenen uçuş rotası"), dashed: false)
                        legend(.orange, t("Current → destination", "Mevcut konum → varış"), dashed: true)
                        Text(t("The path contains positions received while tracking.", "Rota, takip sırasında alınan konumları içerir.")).font(.caption2).foregroundStyle(.secondary)
                    }.padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)).padding(12)
                }
            }
            .navigationTitle(t("Flight map", "Uçuş haritası")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(t("Close", "Kapat")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button { focusRoute() } label: { Image(systemName: "scope") }.accessibilityLabel(t("Focus on route", "Rotaya odaklan")) }
            }
            .onAppear {
                selection = initialFlightID ?? model.flights.first?.id
                focusRoute()
            }
            .task(id: key) {
                guard let flight else { return }
                await model.loadRoute(flight)
                guard !Task.isCancelled, selection == flight.id else { return }
                focusRoute()
            }
            .onChange(of: selection) { _, _ in focusRoute() }
            .onChange(of: model.flights.map(\.id)) { _, ids in
                if selection == nil || !ids.contains(selection!) { selection = ids.first }
            }
            .sheet(item: $detailFlight) { snapshot in
                FlightDetail(model: model, flightOverride: currentDetail(snapshot), onClose: { detailFlight = nil })
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder private func routeCard(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if model.provider == .demo { DemoExitButton(model: model) }
            if let flight {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(flight.title).font(.title3.bold())
                        Text(metadata?.route ?? flight.route).font(.caption).lineLimit(2)
                    }
                    Spacer()
                    Text(flight.isDemo ? "DEMO" : t("\(Int(max(0, now.timeIntervalSince(flight.timestamp)))) sec ago", "\(Int(max(0, now.timeIntervalSince(flight.timestamp)))) sn önce"))
                        .font(.caption.monospaced()).foregroundStyle(flight.isDemo || now.timeIntervalSince(flight.timestamp) >= 30 ? .orange : .mint)
                }
                HStack(spacing: 16) {
                    Text("\(Int(flight.point.altitude)) m")
                    Text(flight.speed.map { "\(Int($0 * 3.6)) km/h" } ?? t("Speed unknown", "Hız bilinmiyor"))
                    Text(metadata?.modelName ?? flight.modelName).lineLimit(1)
                }.font(.caption).foregroundStyle(.secondary)
                Text(model.routeStatus[key] ?? t("Looking up airports…", "Havalimanları sorgulanıyor…")).font(.caption2).foregroundStyle(.secondary)
                Text(samples.count > 1 ? t("The cyan line is the observed path. The orange line only connects the current position to the destination.", "Turkuaz çizgi gözlenen rotadır. Turuncu çizgi yalnızca mevcut konumu varış noktasına bağlar.") : t("The route will appear as new live positions are received.", "Yeni canlı konumlar alındıkça rota görünecektir."))
                    .font(.caption2).foregroundStyle(.orange)
                HStack {
                    Button(t("Fit route", "Rotayı sığdır")) { focusRoute() }.buttonStyle(.bordered)
                    Spacer()
                    Button(t("Flight details", "Uçuş ayrıntıları")) { detailFlight = currentDetail(flight) }.buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black)
                }.font(.caption.bold())

            } else {
                Text(t("Waiting for nearby flights", "Yakındaki uçuşlar bekleniyor")).font(.headline)
                Text(model.status).font(.caption).foregroundStyle(.secondary)
            }
            Text(t("\(model.source) · Tap an aircraft to select its route.", "\(model.source) · Rotasını seçmek için bir uçağa dokunun.")).font(.caption2).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.ultraThinMaterial)
    }

    private func legend(_ color: Color, _ text: String, dashed: Bool) -> some View {
        HStack(spacing: 8) {
            Path { path in path.move(to: .zero); path.addLine(to: CGPoint(x: 24, y: 0)) }
                .stroke(color, style: StrokeStyle(lineWidth: 3, dash: dashed ? [4, 3] : []))
                .frame(width: 24, height: 1)
            Text(text).font(.caption2.bold())
        }
    }
    private func currentDetail(_ snapshot: Flight) -> Flight {
        let current = model.flights.first { $0.id == snapshot.id } ?? snapshot
        var result = model.routeDetails[model.routeKey(current)] ?? current
        result.point = current.point; result.speed = current.speed
        result.track = current.track; result.timestamp = current.timestamp
        return result
    }
    private func focusRoute() {
        guard let flight else {
            if let observer = model.searchCenter { position = .region(MKCoordinateRegion(center: observer.coordinate, latitudinalMeters: model.radius * 2200, longitudinalMeters: model.radius * 2200)) }
            return
        }
        var points = samples.map(\.point)
        if points.isEmpty { points = [flight.point] }
        if let origin = metadata?.originPoint { points.append(origin) }
        if let destination = metadata?.destinationPoint { points.append(destination) }
        var rect = MKMapRect.null
        for point in points {
            let p = MKMapPoint(point.coordinate)
            rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 1, height: 1))
        }
        let minimum = 20000 * MKMapPointsPerMeterAtLatitude(flight.point.latitude)
        let padX = max(rect.width * 0.18, minimum / 2), padY = max(rect.height * 0.18, minimum / 2)
        position = .rect(rect.insetBy(dx: -padX, dy: -padY))
    }
    private func t(_ english: String, _ turkish: String) -> String { model.t(english, turkish) }
}

struct FlightJourneyOverview: View {
    let flight: Flight
    let samples: [FlightSample]
    let language: AppLanguage
    @State private var position: MapCameraPosition = .automatic

    private var displaySamples: [FlightSample] {
        samples.isEmpty ? [FlightSample(timestamp: flight.timestamp, point: flight.point)] : samples
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t("FLIGHT PATH", "UÇUŞ ROTASI")).font(.caption.monospaced().bold()).foregroundStyle(.mint)
            Map(position: $position, interactionModes: [.pan, .zoom]) {
                if displaySamples.count > 1 {
                    MapPolyline(coordinates: displaySamples.map(\.point.coordinate))
                        .stroke(.cyan, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
                if let origin = flight.originPoint {
                    Marker(flight.origin ?? t("Departure", "Kalkış"), systemImage: "airplane.departure", coordinate: origin.coordinate).tint(.cyan)
                }
                if let destination = flight.destinationPoint {
                    MapPolyline(coordinates: [flight.point.coordinate, destination.coordinate], contourStyle: .geodesic)
                        .stroke(.orange, style: StrokeStyle(lineWidth: 3, dash: [7, 5]))
                    Marker(flight.destination ?? t("Destination", "Varış"), systemImage: "target", coordinate: destination.coordinate).tint(.orange)
                }
                Annotation(flight.title, coordinate: flight.point.coordinate) {
                    Image(systemName: "airplane")
                        .font(.title3.bold())
                        .rotationEffect(.degrees((flight.track ?? 90) - 90))
                        .foregroundStyle(.black)
                        .padding(9)
                        .background(Color.mint, in: Circle())
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .onAppear { fitRoute() }
            .onChange(of: displaySamples.count) { _, _ in fitRoute() }

            HStack(spacing: 18) {
                legend(.cyan, t("Observed path", "Gözlenen rota"), dashed: false)
                legend(.orange, t("To destination", "Varışa doğru"), dashed: true)
            }
            Text(displaySamples.count > 1 ? t("Based on live positions received during this tracking session.", "Bu takip oturumunda alınan canlı konumlara dayanır.") : t("Keep tracking this flight to build its observed path.", "Gözlenen rotayı oluşturmak için bu uçuşu takip etmeye devam edin."))
                .font(.caption).foregroundStyle(.secondary)

            Text(t("ALTITUDE PROFILE", "İRTİFA PROFİLİ")).font(.caption.monospaced().bold()).foregroundStyle(.mint).padding(.top, 4)
            Chart(displaySamples) { sample in
                AreaMark(x: .value("Time", sample.timestamp), y: .value("Altitude", sample.point.altitude))
                    .foregroundStyle(.linearGradient(colors: [.cyan.opacity(0.45), .cyan.opacity(0.04)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", sample.timestamp), y: .value("Altitude", sample.point.altitude))
                    .foregroundStyle(.cyan).lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            .chartYAxisLabel(t("Altitude (m)", "İrtifa (m)"))
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour().minute()) } }
            .frame(height: 190)
            Text(displaySamples.count > 1 ? t("Altitude values correspond to the observed path above.", "İrtifa değerleri yukarıdaki gözlenen rotaya karşılık gelir.") : t("More than one live position is needed to draw an altitude profile.", "İrtifa grafiği için birden fazla canlı konum gerekir."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func legend(_ color: Color, _ label: String, dashed: Bool) -> some View {
        HStack(spacing: 7) {
            Path { path in path.move(to: .zero); path.addLine(to: CGPoint(x: 24, y: 0)) }
                .stroke(color, style: StrokeStyle(lineWidth: 3, dash: dashed ? [4, 3] : []))
                .frame(width: 24, height: 1)
            Text(label).font(.caption2.bold())
        }
    }

    private func fitRoute() {
        var points = displaySamples.map(\.point)
        if let origin = flight.originPoint { points.append(origin) }
        if let destination = flight.destinationPoint { points.append(destination) }
        var rect = MKMapRect.null
        for point in points {
            let mapPoint = MKMapPoint(point.coordinate)
            rect = rect.union(MKMapRect(x: mapPoint.x, y: mapPoint.y, width: 1, height: 1))
        }
        let minimum = 20_000 * MKMapPointsPerMeterAtLatitude(flight.point.latitude)
        let padX = max(rect.width * 0.16, minimum / 2)
        let padY = max(rect.height * 0.16, minimum / 2)
        position = .rect(rect.insetBy(dx: -padX, dy: -padY))
    }
    private func t(_ english: String, _ turkish: String) -> String { L(english, turkish, language: language) }
}
