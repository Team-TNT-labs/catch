import CoreMotion
import CoreGraphics
import QuartzCore

/// 자이로 중력 + 흔들기 감지. 실기기 전용(시뮬레이터에선 콜백이 발생하지 않음).
/// 콜백은 모션 큐(백그라운드)에서 호출되므로, 소비 측에서 메인 스레드로 디스패치해야 한다.
final class MotionService {
    private let manager = CMMotionManager()
    private let queue = OperationQueue()

    /// 중력 벡터(SpriteKit 좌표계, 세로 고정 기준) 콜백.
    var onGravity: ((CGVector) -> Void)?
    /// 흔들기 감지 콜백.
    var onShake: (() -> Void)?

    private let shakeThreshold: Double = 2.2
    private var lastShake: TimeInterval = 0

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }

            let g = motion.gravity   // 세로 고정: x 오른쪽 +, y 위 +
            self.onGravity?(CGVector(dx: g.x * 9.8, dy: g.y * 9.8))

            let a = motion.userAcceleration
            let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            let now = CACurrentMediaTime()
            if magnitude > self.shakeThreshold, now - self.lastShake > 0.5 {
                self.lastShake = now
                self.onShake?()
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
