import SwiftUI

@main
struct PlaneTrackerApp: App {
    var body: some Scene { WindowGroup { ContentView().preferredColorScheme(.dark) } }
}

struct ContentView: View {
    @StateObject private var model = TrackerModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showList = false
    @State private var showMap = false
    @State private var detailDetent: PresentationDetent = ProcessInfo.processInfo.arguments.contains("--demo-detail") ? .large : .medium
    private let mint = Color(red: 0.45, green: 0.97, blue: 0.78)

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.055, blue: 0.08).ignoresSafeArea()
            if model.started && model.cameraAllowed && model.provider != .demo && scenePhase == .active && !showMap {
                SkyCamera(model: model).id(model.sessionID).ignoresSafeArea()
            } else { skyBackground }
            LinearGradient(colors: [.black.opacity(0.75), .clear, .clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
            if model.started {
                VStack(spacing: 16) {
                    header
                    HStack {
                        Label(model.provider == .demo ? "DEMO" : model.source, systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption.weight(.semibold)).foregroundStyle(model.provider == .demo ? .orange : mint)
                        Spacer()
                        Text("\(Int(model.radius)) KM").font(.caption.monospaced().weight(.bold))
                    }.padding(12).background(.black.opacity(0.45), in: Capsule())
                    if model.provider == .demo { DemoExitButton(model: model) }
                    Spacer()
                    if model.provider == .demo, let flight = model.flights.first {
                        Button { model.select(flight) } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "airplane").font(.largeTitle)
                                Text("\(flight.title) · \(flight.modelName)").font(.subheadline.bold())
                                Text(t("Sample flight · tap for details", "Örnek uçuş · ayrıntılar için dokunun")).font(.caption)
                            }.foregroundStyle(mint).padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                        }
                    } else {
                        Image(systemName: "viewfinder").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(.white.opacity(0.5)).allowsHitTesting(false)
                    }
                    Spacer()
                    bottomPanel
                }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
            } else { welcome }
        }
        .sheet(isPresented: $showSettings) { SettingsView(model: model) }
        .sheet(isPresented: $showList) { flightList }
        .fullScreenCover(isPresented: $showMap) { RouteMapView(model: model) }
        .sheet(item: Binding(get: { showMap ? nil : model.selected }, set: { if $0 == nil { model.dismissSelection() } })) { _ in
            FlightDetail(model: model).presentationDetents([.medium, .large], selection: $detailDetent).presentationDragIndicator(.visible)
        }
        .onChange(of: scenePhase) { _, phase in model.setActive(phase == .active) }
    }

    private var skyBackground: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(colors: [Color(red: 0.07, green: 0.25, blue: 0.29), .clear], center: .center, startRadius: 0, endRadius: 400)
                ForEach(1..<5) { index in
                    Circle().stroke(mint.opacity(0.08), lineWidth: 1).frame(width: CGFloat(index) * 145, height: CGFloat(index) * 145)
                }
                Rectangle().fill(mint.opacity(0.08)).frame(width: 1)
                Rectangle().fill(mint.opacity(0.08)).frame(height: 1)
            }.frame(width: geo.size.width, height: geo.size.height)
        }.ignoresSafeArea().allowsHitTesting(false)
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(t("THE SKY", "GÖKYÜZÜ")).font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(4).foregroundStyle(mint)
                Text(t("Flight Radar", "Uçuş Radarı")).font(.title2.bold())
            }
            Spacer()
            Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3").font(.title3).padding(13).background(.ultraThinMaterial, in: Circle()) }
                .accessibilityLabel(t("Settings", "Ayarlar"))
        }.foregroundStyle(.white)
    }
    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(model.flights.count)").font(.system(size: 38, weight: .light, design: .rounded))
                Text(t("nearby flights", "yakındaki uçuş")).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if model.isLoading { ProgressView().tint(mint) }
                else { Image(systemName: "airplane.circle.fill").font(.title).foregroundStyle(mint) }
            }
            Text(model.status).font(.footnote).fixedSize(horizontal: false, vertical: true)
            if model.provider != .demo {
                Text(model.trackingStatus).font(.caption2).foregroundStyle(.secondary)
                if model.headingAccuracy < 0 || model.headingAccuracy > 20 {
                    Text(t("Compass accuracy may be low. Move away from magnets and move the phone in a figure eight.", "Pusula hassasiyeti düşük olabilir. Mıknatıslardan uzaklaşın ve telefonu sekiz çizerek hareket ettirin.")).font(.caption2).foregroundStyle(.orange)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let last = model.lastUpdate {
                        Text(t("Last update \(Int(max(0, context.date.timeIntervalSince(last)))) sec ago · every 15 sec", "Son güncelleme \(Int(max(0, context.date.timeIntervalSince(last)))) sn önce · 15 sn aralıkla")).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 10) {
                Button { showMap = true } label: { Label(t("Map", "Harita"), systemImage: "map.fill").padding(.vertical, 13).padding(.horizontal, 16) }
                    .background(mint, in: Capsule()).foregroundStyle(.black)
                Button { showList = true } label: { Label(t("Flight list", "Uçuş listesi"), systemImage: "list.bullet").frame(maxWidth: .infinity).padding(.vertical, 13) }
                    .background(.white.opacity(0.12), in: Capsule()).foregroundStyle(.white)
                Button { model.sessionID = UUID() } label: { Image(systemName: "scope").padding(14).background(.white.opacity(0.1), in: Circle()) }.accessibilityLabel(t("Realign camera", "Kamerayı yeniden hizala"))
            }.font(.subheadline.bold())
            Text(t("Tap a flight to see its observed path, destination and altitude profile.", "Gözlenen rotayı, varış noktasını ve irtifa grafiğini görmek için bir uçuşa dokunun.")).font(.caption2).foregroundStyle(.secondary)
        }.padding(18).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26))
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Image(systemName: "airplane").font(.system(size: 56)).foregroundStyle(mint)
            Text(t("Look up.\nDiscover the flight.", "Başınızı kaldırın.\nUçuşu keşfedin.")).font(.system(size: 42, weight: .bold, design: .rounded))
            Text(t("Point your iPhone at the sky to see nearby aircraft information over the live camera view.", "Yakındaki uçak bilgilerini canlı kamera görüntüsünde görmek için iPhone'unuzu gökyüzüne yöneltin."))
                .foregroundStyle(.secondary).font(.body)
            VStack(alignment: .leading, spacing: 14) {
                Label(t("The camera image stays on your device and is not recorded.", "Kamera görüntüsü cihazınızda kalır ve kaydedilmez."), systemImage: "camera")
                Label(t("Your approximate search area is sent to flight data services.", "Yaklaşık arama bölgeniz uçuş veri servislerine gönderilir."), systemImage: "location")
                Label(t("Free sources work without an account or API key.", "Ücretsiz kaynaklar hesap veya API anahtarı gerektirmez."), systemImage: "checkmark.shield")
            }.font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Button { model.start() } label: { Text(t("Scan the sky", "Gökyüzünü tara")).font(.headline).frame(maxWidth: .infinity).padding(18).background(mint, in: Capsule()).foregroundStyle(.black) }
            Button { model.started = true; model.applySettings(provider: .demo, radius: 50) } label: { Text(t("View a sample first", "Önce örnek ekranı görün")).frame(maxWidth: .infinity) }.tint(.white)
            Text(t("Labels are approximate. Do not use this app for navigation.", "Etiketler yaklaşık konumdadır. Bu uygulamayı seyrüsefer için kullanmayın.")).font(.caption2).foregroundStyle(.secondary)
        }.padding(28).padding(.bottom, 12)
    }
    private var flightList: some View {
        NavigationStack {
            List {
                Section(model.source) {
                    if model.flights.isEmpty { Text(model.status) }
                    ForEach(model.flights) { flight in
                        Button {
                            showList = false
                            Task { try? await Task.sleep(for: .milliseconds(350)); model.select(flight) }
                        } label: {
                            HStack {
                                Image(systemName: "airplane").foregroundStyle(mint).frame(width: 30)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(flight.title).font(.headline)
                                    Text("\(Int(flight.point.altitude)) m · \(flight.speed.map { "\(Int($0 * 3.6)) km/h" } ?? t("Speed unknown", "Hız bilinmiyor"))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let observer = model.observer { Text("\(Int(Geometry.distance(observer, flight.point) / 1000)) km").font(.caption.monospaced()) }
                                Image(systemName: "chevron.right").font(.caption)
                            }.padding(.vertical, 6)
                        }.tint(.white)
                    }
                }
                Section { Text(t("Live positions expire after 60 seconds. Route and aircraft details are requested when you select a flight.", "Canlı konumlar 60 saniye sonra geçersiz olur. Rota ve uçak ayrıntıları bir uçuş seçtiğinizde sorgulanır.")).font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle(t("Nearby flights", "Yakındaki uçuşlar")).toolbar { ToolbarItem(placement: .topBarTrailing) { Button(t("Close", "Kapat")) { showList = false } } }
        }
    }

    private func t(_ english: String, _ turkish: String) -> String { model.t(english, turkish) }
}

struct FlightDetail: View {
    @ObservedObject var model: TrackerModel
    var flightOverride: Flight? = nil
    var onClose: (() -> Void)? = nil
    var body: some View {
        ScrollView {
            if let flight = flightOverride ?? model.selected {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Image(systemName: "airplane.circle.fill").font(.system(size: 42)).foregroundStyle(.mint)
                        VStack(alignment: .leading) { Text(flight.title).font(.title.bold()); Text(flight.airlineName).foregroundStyle(.secondary) }
                        Spacer()
                        Button { if let onClose { onClose() } else { model.dismissSelection() } } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary) }.accessibilityLabel(t("Close", "Kapat"))
                    }
                    if flight.isDemo {
                        Text(t("DEMO · This card does not show a real flight.", "DEMO · Bu kart gerçek bir uçuşu göstermiyor.")).foregroundStyle(.orange).font(.caption.bold())
                        DemoExitButton(model: model, onExit: onClose)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(t("DEPARTURE → DESTINATION", "KALKIŞ → VARIŞ")).font(.caption.monospaced()).foregroundStyle(.mint)
                        Text(flight.route).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                    }
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 18) {
                        GridRow { field(t("AIRCRAFT", "UÇAK"), flight.modelName); field(t("REGISTRATION", "TESCİL"), flight.registration ?? t("Unknown", "Bilinmiyor")) }
                        GridRow { field(t("ALTITUDE", "İRTİFA"), "\(Int(flight.point.altitude)) m"); field(t("GROUND SPEED", "YER HIZI"), flight.speed.map { "\(Int($0 * 3.6)) km/h" } ?? t("Unknown", "Bilinmiyor")) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if model.enriching && flightOverride == nil { HStack { ProgressView(); Text(t("Loading route and aircraft details…", "Rota ve uçak ayrıntıları yükleniyor…")).font(.caption) } }
                    FlightJourneyOverview(flight: flight, samples: model.trail(for: flight), language: model.language)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let age = Int(max(0, context.date.timeIntervalSince(flight.timestamp)))
                        Text(flight.isDemo ? t("Sample values", "Örnek değerler") : t("Position received \(age) sec ago\(age >= 30 ? " · STALE DATA" : "")", "Konum \(age) sn önce alındı\(age >= 30 ? " · ESKİ VERİ" : "")"))
                            .font(.caption.monospaced()).foregroundStyle(age >= 30 && !flight.isDemo ? .orange : .secondary)
                    }
                    Text(flight.geometricAltitude ? t("Altitude is geometric and is not height above terrain.", "İrtifa geometrik yüksekliktir; yerden yükseklik değildir.") : t("Altitude is pressure-based and is not height above terrain. Vertical AR alignment may be approximate.", "İrtifa standart basınca göredir; yerden yükseklik değildir. Dikey AR hizalaması yaklaşık olabilir.")).font(.caption).foregroundStyle(.secondary)
                    if flight.metadataFromCommunity {
                        Text(t("Route and airline data come from the adsbdb community database. They may not match the current flight when a callsign is reused.", "Rota ve havayolu verileri adsbdb topluluk veritabanından gelir. Çağrı kodu yeniden kullanıldığında güncel uçuşla eşleşmeyebilir.")).font(.caption).foregroundStyle(.orange)
                    }
                    Text(t("Live position: \(model.source) · Additional details: adsbdb when available. Missing data is not guessed.", "Canlı konum: \(model.source) · Ek ayrıntılar: varsa adsbdb. Eksik bilgiler tahmin edilmez.")).font(.caption2).foregroundStyle(.secondary)
                }.padding(24).padding(.top, 10)
            }
        }
    }
    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(label).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(.secondary); Text(value).font(.subheadline.bold()) }
    }
    private func t(_ english: String, _ turkish: String) -> String { model.t(english, turkish) }
}

struct DemoExitButton: View {
    @ObservedObject var model: TrackerModel
    var onExit: (() -> Void)? = nil
    var body: some View {
        Button {
            onExit?()
            model.exitDemo()
        } label: {
            Label(model.t("Exit demo · Go live", "Demodan çık · Canlıya geç"), systemImage: "arrow.right.circle.fill")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.mint, in: Capsule())
                .foregroundStyle(.black)
        }
        .accessibilityIdentifier("exitDemoButton")
    }
}

struct SettingsView: View {
    @ObservedObject var model: TrackerModel
    @Environment(\.dismiss) private var dismiss
    @State private var provider: Provider = .automatic
    @State private var radius: Double = 50
    @State private var token = ""
    @State private var saveError = false
    @State private var language: AppLanguage = .english
    var body: some View {
        NavigationStack {
            Form {
                Section(model.t("Language", "Dil")) {
                    Picker(model.t("App language", "Uygulama dili"), selection: $language) {
                        ForEach(AppLanguage.allCases) { Text($0.name).tag($0) }
                    }.pickerStyle(.segmented)
                }
                Section(model.t("Flight data", "Uçuş verileri")) {
                    Picker(model.t("Source", "Kaynak"), selection: $provider) { ForEach(Provider.allCases) { Text($0.name).tag($0) } }
                    Text(model.t("Automatic free mode uses OpenSky → ADSB.lol → adsb.fi and falls back when a source fails or reaches its limit. Updates run every 15 seconds while the app is active.", "Ücretsiz Otomatik mod OpenSky → ADSB.lol → adsb.fi sırasını kullanır; bir kaynak hata verdiğinde veya kotaya ulaştığında diğerine geçer. Uygulama açıkken 15 saniyede bir güncellenir.")).font(.caption).foregroundStyle(.secondary)
                    if provider == .flightradar {
                        SecureField(model.t("Personal FR24 API key", "Kişisel FR24 API anahtarı"), text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text(model.t("A paid API plan may provide additional flight fields. The key is stored only in this device's Keychain, and requests may consume API credits.", "Ücretli API paketi ek uçuş alanları sağlayabilir. Anahtar yalnızca bu cihazın Anahtar Zinciri'nde saklanır ve sorgular API kredisi tüketebilir.")).font(.caption).foregroundStyle(.orange)
                        Link(model.t("Flightradar24 API account", "Flightradar24 API hesabı"), destination: URL(string: "https://fr24api.flightradar24.com")!)
                    }
                    LabeledContent(model.t("Search radius", "Arama yarıçapı"), value: "\(Int(radius)) km")
                    Slider(value: $radius, in: 10...100, step: 10)
                }
                Section(model.t("Camera alignment", "Kamera hizalama")) {
                    Text(model.t("If labels drift sideways, calibrate the compass outdoors away from magnets, then use the fine adjustment below.", "Etiketler yana kayıyorsa pusulayı açık havada ve mıknatıslardan uzakta kalibre edin, ardından aşağıdaki ince ayarı kullanın.")).font(.caption)
                    LabeledContent(model.t("Heading adjustment", "Yön düzeltmesi"), value: "\(Int(model.headingOffset))°")
                    Slider(value: $model.headingOffset, in: -45...45, step: 1)
                    Button(model.t("Reset heading adjustment", "Yön düzeltmesini sıfırla")) { model.headingOffset = 0 }
                    Button(model.t("Open device permission settings", "Cihaz izin ayarlarını aç")) { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                }
                Section(model.t("Privacy and sources", "Gizlilik ve kaynaklar")) {
                    Text(model.t("The camera is not recorded or uploaded. Your approximate search area is sent to the selected position provider; the selected callsign or registration may be sent to adsbdb. There are no analytics or ads.", "Kamera kaydedilmez veya yüklenmez. Yaklaşık arama bölgeniz seçilen konum sağlayıcısına; seçilen çağrı kodu veya tescil adsbdb'ye gönderilebilir. Analitik ve reklam yoktur.")).font(.caption)
                    Link("OpenSky Network", destination: URL(string: "https://opensky-network.org")!)
                    Link("ADSB.lol · ODbL 1.0", destination: URL(string: "https://www.adsb.lol/privacy-license/")!)
                    Link(model.t("adsb.fi · personal use", "adsb.fi · kişisel kullanım"), destination: URL(string: "https://adsb.fi")!)
                    Link(model.t("adsbdb · community route and aircraft data", "adsbdb · topluluk rota ve uçak verileri"), destination: URL(string: "https://www.adsbdb.com")!)
                    Text(model.t("Coverage is not complete. Free sources may omit route or aircraft details. Do not use this app for navigation.", "Kapsama tam değildir. Ücretsiz kaynaklarda rota veya uçak ayrıntıları eksik olabilir. Bu uygulamayı seyrüsefer için kullanmayın.")).font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle(model.t("Settings", "Ayarlar"))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button(model.t("Cancel", "Vazgeç")) { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(model.t("Save", "Kaydet")) {
                            guard TokenStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines)) else { saveError = true; return }
                            model.applySettings(provider: provider, radius: radius)
                            dismiss()
                        }
                    }
                }
                .onAppear { provider = model.provider; radius = model.radius; token = TokenStore.read(); language = model.language }
                .onChange(of: language) { _, value in model.setLanguage(value) }
                .alert(model.t("Could not save the key", "Anahtar kaydedilemedi"), isPresented: $saveError) { Button(model.t("OK", "Tamam"), role: .cancel) {} } message: { Text(model.t("Unlock the device and try again.", "Cihazın kilidini açıp yeniden deneyin.")) }
        }
    }
}
