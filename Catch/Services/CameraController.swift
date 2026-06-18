import AVFoundation
import UIKit

enum CameraError: Error { case captureFailed }

/// 후면/전면 정지 촬영 래퍼.
/// - 권한 확인 → 세션 구성(입력+출력 원자적) → 시작/정지 → 촬영.
/// - 세션 변경은 전용 큐에서, 상태 발행은 메인에서.
@MainActor
final class CameraController: NSObject, ObservableObject {
    enum Status { case idle, configuring, ready, denied, failed }

    @Published private(set) var status: Status = .idle
    @Published var position: AVCaptureDevice.Position = .back

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "catch.camera.session")
    private var configured = false
    private var photoContinuation: CheckedContinuation<UIImage, Error>?

    override init() {
        super.init()
        prepare()
    }

    // MARK: - 권한 + 구성

    /// 권한 확인 후 세션을 구성한다(필요 시 권한 팝업).
    func prepare() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            status = .configuring
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted { self.configure() } else { self.status = .denied }
                }
            }
        default:
            status = .denied
        }
    }

    private func configure() {
        guard !configured else { status = .ready; return }
        status = .configuring
        let session = self.session
        let output = self.photoOutput
        let position = self.position
        queue.async {
            session.beginConfiguration()
            session.sessionPreset = .photo
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input),
                  session.canAddOutput(output) else {
                session.commitConfiguration()
                Task { @MainActor in self.status = .failed }
                return
            }
            session.addInput(input)
            session.addOutput(output)
            session.commitConfiguration()
            Task { @MainActor in
                self.configured = true
                self.status = .ready
            }
        }
    }

    // MARK: - 실행 제어

    func startRunning() {
        let session = self.session
        queue.async { if !session.isRunning { session.startRunning() } }
    }

    func stopRunning() {
        let session = self.session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    /// 전/후면 전환.
    func flip() {
        position = (position == .back) ? .front : .back
        let session = self.session
        let position = self.position
        queue.async {
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
        }
    }

    // MARK: - 촬영

    func capturePhoto() async throws -> UIImage {
        guard photoContinuation == nil else { throw CameraError.captureFailed }
        let output = self.photoOutput
        return try await withCheckedThrowingContinuation { cont in
            self.photoContinuation = cont
            self.queue.async {
                output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let result: Result<UIImage, Error>
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
            result = .success(image)
        } else {
            result = .failure(CameraError.captureFailed)
        }
        Task { @MainActor in
            switch result {
            case .success(let image): self.photoContinuation?.resume(returning: image)
            case .failure(let err):   self.photoContinuation?.resume(throwing: err)
            }
            self.photoContinuation = nil
        }
    }
}
