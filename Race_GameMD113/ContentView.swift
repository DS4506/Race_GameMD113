
import SwiftUI
import CoreMotion
import Combine
import UIKit

// MARK: - Motion service

final class MotionService {
    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()

    @Published private(set) var acceleration = CMAcceleration(x: 0, y: 0, z: 0)
    @Published private(set) var rotationRate = CMRotationRate(x: 0, y: 0, z: 0)

    var accelerationPublisher: AnyPublisher<CMAcceleration, Never> { $acceleration.eraseToAnyPublisher() }
    var rotationPublisher: AnyPublisher<CMRotationRate, Never> { $rotationRate.eraseToAnyPublisher() }

    func startUpdates(accelHz: Double = 50, gyroHz: Double = 50) {
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 1.0 / accelHz
            motionManager.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
                guard let d = data else { return }
                DispatchQueue.main.async { self?.acceleration = d.acceleration }
            }
        }
        if motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = 1.0 / gyroHz
            motionManager.startGyroUpdates(to: queue) { [weak self] data, _ in
                guard let d = data else { return }
                DispatchQueue.main.async { self?.rotationRate = d.rotationRate }
            }
        }
    }

    func stopUpdates() {
        if motionManager.isAccelerometerActive { motionManager.stopAccelerometerUpdates() }
        if motionManager.isGyroActive { motionManager.stopGyroUpdates() }
    }
}

// MARK: - Pedometer service

final class PedometerService {
    private let pedometer = CMPedometer()

    @Published private(set) var steps: Int = 0
    @Published private(set) var distanceMeters: Double? = nil
    @Published private(set) var lastUpdate: Date? = nil

    var stepsPublisher: AnyPublisher<Int, Never> { $steps.eraseToAnyPublisher() }
    var distancePublisher: AnyPublisher<Double?, Never> { $distanceMeters.eraseToAnyPublisher() }
    var lastUpdatePublisher: AnyPublisher<Date?, Never> { $lastUpdate.eraseToAnyPublisher() }

    func start() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let d = data else { return }
            DispatchQueue.main.async {
                self?.steps = d.numberOfSteps.intValue
                self?.distanceMeters = d.distance?.doubleValue
                self?.lastUpdate = d.endDate
            }
        }
    }

    func stop() { pedometer.stopUpdates() }
}

// MARK: - View model

final class ActivityViewModel: ObservableObject {
    private let motionService = MotionService()
    private let pedometerService = PedometerService()
    private var cancellables: Set<AnyCancellable> = []

    @Published var isTracking: Bool = false
    @Published var steps: Int = 0
    @Published var distanceMeters: Double? = nil
    @Published var acceleration = CMAcceleration(x: 0, y: 0, z: 0)
    @Published var rotationRate = CMRotationRate(x: 0, y: 0, z: 0)
    @Published var feedback: String = "Ready"
    @Published var inactive: Bool = false

    private let milestone: Int = 500
    private let inactivitySeconds: TimeInterval = 30 * 60
    private var lastMovementAt: Date = Date()

    init() { bind() }

    private func bind() {
        motionService.accelerationPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] acc in
                self?.acceleration = acc
                let m = sqrt(acc.x*acc.x + acc.y*acc.y + acc.z*acc.z)
                if m > 0.03 { self?.lastMovementAt = Date() }
            }.store(in: &cancellables)

        motionService.rotationPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] rot in
                self?.rotationRate = rot
                self?.lastMovementAt = Date()
            }.store(in: &cancellables)

        pedometerService.stepsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] s in
                guard let self = self else { return }
                self.steps = s
                self.lastMovementAt = Date()
                self.inactive = false
                if s > 0 && s % milestone == 0 {
                    self.feedback = "Great job. \(s) steps reached."
                    Haptics.notifySuccess()
                }
            }.store(in: &cancellables)

        pedometerService.distancePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] d in self?.distanceMeters = d }
            .store(in: &cancellables)

        Timer.publish(every: 10, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                let idle = Date().timeIntervalSince(self.lastMovementAt)
                if idle >= self.inactivitySeconds {
                    if !self.inactive {
                        self.feedback = "You have been inactive for 30 minutes. A short walk would help."
                        Haptics.notifyWarning()
                    }
                    self.inactive = true
                } else {
                    self.inactive = false
                }
            }.store(in: &cancellables)
    }

    func start() {
        isTracking = true
        motionService.startUpdates()
        pedometerService.start()
        feedback = "Tracking started."
    }

    func stop() {
        isTracking = false
        motionService.stopUpdates()
        pedometerService.stop()
        feedback = "Tracking paused."
    }

    func distanceDisplay() -> String {
        if let meters = distanceMeters {
            return meters >= 1000 ? String(format: "%.2f km", meters/1000) : String(format: "%.0f m", meters)
        } else {
            let est = Double(steps) * 0.78
            return est >= 1000 ? String(format: "~%.2f km", est/1000) : String(format: "~%.0f m", est)
        }
    }
}

// MARK: - Haptics

enum Haptics {
    static func notifySuccess() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func notifyWarning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

// MARK: - Dashboard UI (rings + tiles)

@MainActor
struct ContentView: View {
    @StateObject private var vm: ActivityViewModel

    init() {
        _vm = StateObject(wrappedValue: ActivityViewModel())
    }

    private let stepGoal: Double = 8000
    private let distanceGoalMeters: Double = 5000

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color.blue.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {

                    HStack(alignment: .firstTextBaseline) {
                        Text("Activity")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                        Button {
                            vm.isTracking ? vm.stop() : vm.start()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: vm.isTracking ? "pause.circle.fill" : "play.circle.fill")
                                Text(vm.isTracking ? "Stop" : "Start").fontWeight(.semibold)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(vm.isTracking ? Color.red.opacity(0.9) : Color.green.opacity(0.9))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 4)
                        }
                        .accessibilityLabel(vm.isTracking ? "Stop Tracking" : "Start Tracking")
                    }
                    .padding(.horizontal)

                    HStack(spacing: 16) {
                        RingCard(
                            title: "Steps",
                            systemImage: "figure.walk",
                            valueText: "\(vm.steps)",
                            progress: min(Double(vm.steps) / stepGoal, 1.0),
                            ringColors: [Color.green, Color.teal],
                            subtitle: "Goal \(Int(stepGoal))"
                        )
                        RingCard(
                            title: "Distance",
                            systemImage: "location.fill",
                            valueText: vm.distanceDisplay(),
                            progress: {
                                if let m = vm.distanceMeters { return min(m / distanceGoalMeters, 1.0) }
                                let est = Double(vm.steps) * 0.78
                                return min(est / distanceGoalMeters, 1.0)
                            }(),
                            ringColors: [Color.purple, Color.blue],
                            subtitle: "Goal \(String(format: "%.1f km", distanceGoalMeters/1000))"
                        )
                    }
                    .padding(.horizontal)

                    TileRow(
                        left: MetricTile(
                            title: "Acceleration",
                            systemImage: "waveform.path.ecg",
                            value: String(format: "%.2f, %.2f, %.2f", vm.acceleration.x, vm.acceleration.y, vm.acceleration.z),
                            tint: .mint
                        ),
                        right: MetricTile(
                            title: "Gyroscope",
                            systemImage: "gyroscope",
                            value: String(format: "%.2f, %.2f, %.2f", vm.rotationRate.x, vm.rotationRate.y, vm.rotationRate.z),
                            tint: .pink
                        )
                    )
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: vm.inactive ? "hourglass.bottomhalf.filled" : "sparkles")
                                .foregroundColor(vm.inactive ? .yellow : .green)
                            Text("Status")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.9))
                            Spacer()
                        }
                        Text(vm.feedback)
                            .font(.body)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(vm.inactive ? Color.yellow.opacity(0.25) : Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 24)
                }
                .padding(.vertical, 20)
            }
        }
    }
}

// MARK: - Ring components

struct RingCard: View {
    var title: String
    var systemImage: String
    var valueText: String
    var progress: Double
    var ringColors: [Color]
    var subtitle: String

    @State private var animatedProgress: Double = 0

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RingBackground()
                RingProgress(progress: animatedProgress, colors: ringColors)
                VStack(spacing: 2) {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                    Text(valueText)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                }
            }
            .frame(width: 150, height: 150)

            VStack(spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 6)
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { animatedProgress = progress } }
        .onChange(of: progress) { newValue in
            withAnimation(.easeInOut(duration: 0.6)) { animatedProgress = newValue }
        }
    }
}

struct RingBackground: View {
    var body: some View {
        Circle().stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 16))
    }
}

struct RingProgress: View {
    var progress: Double
    var colors: [Color]

    var body: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(
                AngularGradient(gradient: Gradient(colors: colors), center: .center),
                style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round)
            )
            .rotationEffect(.degrees(-90))
            .shadow(color: colors.last?.opacity(0.6) ?? .clear, radius: 4, x: 0, y: 2)
            .animation(.easeInOut(duration: 0.6), value: progress)
    }
}

// MARK: - Metric tiles

struct TileRow: View {
    var left: MetricTile
    var right: MetricTile

    var body: some View {
        HStack(spacing: 12) {
            left
            right
        }
    }
}

struct MetricTile: View {
    var title: String
    var systemImage: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).foregroundColor(tint)
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.06))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 4)
    }
}

// MARK: - Preview

@MainActor
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let demo = ActivityViewModel()
        demo.steps = 4567
        demo.distanceMeters = 3210
        demo.acceleration = CMAcceleration(x: 0.02, y: -0.98, z: 0.03)
        demo.rotationRate = CMRotationRate(x: 0.1, y: 0.2, z: -0.1)
        demo.feedback = "Great job. 4,500+ steps logged."

        return Group {
            ContentView()
                .preferredColorScheme(.dark)
            ContentView()
                .previewDevice("iPhone 15 Pro")
                .preferredColorScheme(.dark)
        }
    }
}
