import SwiftUI
import ARKit
import SceneKit

struct SkyCamera: UIViewRepresentable {
    @ObservedObject var model: TrackerModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.scene = SCNScene()
        view.backgroundColor = .black
        view.session.delegate = context.coordinator
        context.coordinator.view = view
        context.coordinator.start()
        return view
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) { context.coordinator.model = model }
    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) { coordinator.stop(); uiView.session.pause() }

    @MainActor final class Coordinator: NSObject, ARSessionDelegate {
        var model: TrackerModel
        weak var view: ARSCNView?
        var timer: Timer?
        var buttons: [String: UIButton] = [:]
        init(model: TrackerModel) { self.model = model }
        func start() {
            guard AROrientationTrackingConfiguration.isSupported else { model.trackingStatus = model.t("AR is not supported on this device.", "Bu cihazda AR desteklenmiyor."); return }
            let config = AROrientationTrackingConfiguration()
            config.worldAlignment = .gravityAndHeading
            view?.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.drawLabels() }
            }
        }
        func stop() { timer?.invalidate(); timer = nil }
        func drawLabels() {
            guard let view, let frame = view.session.currentFrame, let observer = model.observer else {
                buttons.values.forEach { $0.isHidden = true }; return
            }
            let now = Date(), size = view.bounds.size
            var visible = Set<String>()
            var occupied: [CGRect] = []
            for flight in model.flights.prefix(100) {
                let age = now.timeIntervalSince(flight.timestamp)
                guard age < 60 else { continue }
                let direction = Geometry.vector(from: observer, to: Geometry.predicted(flight, now: now))
                let length = sqrt(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)
                guard length > 1, direction.y > 0 else { continue }
                let angle = Geometry.radians(model.headingOffset)
                let east = direction.x * cos(angle) - direction.z * sin(angle)
                let south = direction.x * sin(angle) + direction.z * cos(angle)
                let point = SIMD3<Float>(Float(east / length * 100), Float(direction.y / length * 100), Float(south / length * 100))
                let cameraPoint = frame.camera.viewMatrix(for: .portrait) * SIMD4<Float>(point.x, point.y, point.z, 1)
                guard cameraPoint.z < 0 else { continue }
                let projected = frame.camera.projectPoint(point, orientation: .portrait, viewportSize: size)
                guard projected.x.isFinite, projected.y.isFinite,
                      projected.x > 12, projected.x < size.width - 12,
                      projected.y > 140, projected.y < size.height - 240 else { continue }
                let rect = CGRect(x: min(max(8, projected.x - 75), size.width - 158), y: projected.y - 25, width: 150, height: 56)
                guard !occupied.contains(where: { $0.intersects(rect.insetBy(dx: -3, dy: -3)) }) else { continue }
                occupied.append(rect)
                visible.insert(flight.id)
                let button: UIButton
                if let existing = buttons[flight.id] { button = existing }
                else {
                    button = UIButton(type: .system)
                    button.layer.cornerRadius = 14
                    button.layer.borderWidth = 1
                    button.titleLabel?.numberOfLines = 2
                    button.titleLabel?.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
                    button.accessibilityHint = model.t("Open flight details", "Uçuş ayrıntılarını aç")
                    let id = flight.id
                    button.addAction(UIAction { [weak self] _ in
                        guard let self, let current = self.model.flights.first(where: { $0.id == id }) else { return }
                        self.model.select(current)
                    }, for: .touchUpInside)
                    buttons[id] = button
                    view.addSubview(button)
                }
                let distance = Geometry.distance(observer, flight.point) / 1000
                button.setTitle("✈ \(flight.title)\n\(Int(distance)) km · \(Int(flight.point.altitude)) m", for: .normal)
                button.backgroundColor = UIColor(red: 0.03, green: 0.10, blue: 0.15, alpha: 0.88)
                button.tintColor = age > 30 ? .systemOrange : .systemMint
                button.layer.borderColor = button.tintColor.withAlphaComponent(0.6).cgColor
                button.frame = rect
                button.isHidden = false
            }
            for id in Array(buttons.keys) where !visible.contains(id) { buttons[id]?.removeFromSuperview(); buttons.removeValue(forKey: id) }
        }
        nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
            Task { @MainActor in self.model.trackingStatus = self.model.t("Camera or sensor error. Use the realign button.", "Kamera veya sensör hatası. Yeniden hizala düğmesini kullanın.") }
        }
        nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            let state = camera.trackingState
            Task { @MainActor in
                let message: String
                switch state {
                case .normal: message = self.model.t("AR ready · alignment is approximate", "AR hazır · hizalama yaklaşık")
                case .notAvailable: message = self.model.t("AR tracking is unavailable", "AR izleme kullanılamıyor")
                case .limited: message = self.model.t("Aligning sensors · move the phone slowly", "Sensörler hizalanıyor · telefonu yavaşça hareket ettirin")
                }
                self.model.trackingStatus = message
            }
        }
        nonisolated func sessionWasInterrupted(_ session: ARSession) {
            Task { @MainActor in self.model.trackingStatus = self.model.t("Camera paused", "Kamera duraklatıldı") }
        }
        nonisolated func sessionInterruptionEnded(_ session: ARSession) {
            Task { @MainActor in self.model.sessionID = UUID() }
        }
    }
}
