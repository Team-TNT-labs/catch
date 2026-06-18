import AVFoundation
import UIKit

enum CameraError: Error { case captureFailed }

/// 후면 카메라 정지 촬영 래퍼.
@MainActor
final class CameraController: NSObject, ObservableObject {
    enum Status { case unknown, configuring, ready, denied, failed }

    @Published var status: Status = .unknown

    @Published var position: AVCaptureDevice.Position = .back

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "catch.camera.session")
    private var captureContinuation: CheckedContinuation<UIImage, Error>?

    /// 전/후면 전환.
    func flip() async {
        position = position == .back ? .front : .back
        await reconfigureInput()
    }

    private func reconfigureInput() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                self.session.beginConfiguration()
                for input in self.session.inputs { self.session.removeInput(input) }
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.position),
                   let input = try? AVCaptureDeviceInput(device: device),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                self.session.commitConfiguration()
                cont.resume()
            }
        }
    }

    /// 권한 상태에 따라 분기 후 세션 구성.
    func requestAccessAndConfigure() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            await configure()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { await configure() } else { status = .denied }
        default:
            status = .denied
        }
    }

    private func configure() async {
        // 이미 구성됐다면(중복 호출) 다시 추가하지 않고 바로 시작.
        if !session.inputs.isEmpty {
            startSession()
            status = .ready
            return
        }
        status = .configuring
        // 세션 구성 성공 여부를 동기적으로 받아온다(상태 레이스 방지).
        let success = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            sessionQueue.async {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo

                // 중복 추가 방지: 기존 입력/출력 정리 후 재구성.
                for input in self.session.inputs { self.session.removeInput(input) }
                for output in self.session.outputs { self.session.removeOutput(output) }

                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.position),
                      let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    cont.resume(returning: false); return
                }
                self.session.addInput(input)

                guard self.session.canAddOutput(self.photoOutput) else {
                    self.session.commitConfiguration()
                    cont.resume(returning: false); return
                }
                self.session.addOutput(self.photoOutput)
                self.session.commitConfiguration()
                cont.resume(returning: true)
            }
        }
        if success {
            startSession()
            status = .ready
        } else {
            status = .failed
        }
    }

    func startSession() {
        sessionQueue.async {
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stopSession() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// 메인 뷰로 나갈 때 — 세션 정지 + 상태 리셋(재진입 시 매번 검정→페이드).
    func deactivate() {
        stopSession()
        status = .unknown
    }

    func capturePhoto() async throws -> UIImage {
        // 직전 촬영이 아직 진행 중이면 중복 호출을 거부(continuation 덮어쓰기/누수 방지).
        guard captureContinuation == nil else { throw CameraError.captureFailed }
        let settings = AVCapturePhotoSettings()
        return try await withCheckedThrowingContinuation { cont in
            self.captureContinuation = cont
            self.photoOutput.capturePhoto(with: settings, delegate: self)
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
            case .success(let image): self.captureContinuation?.resume(returning: image)
            case .failure(let err): self.captureContinuation?.resume(throwing: err)
            }
            self.captureContinuation = nil
        }
    }
}
