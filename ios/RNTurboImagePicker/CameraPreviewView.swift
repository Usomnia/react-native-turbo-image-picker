//
//  CameraPreviewView.swift
//  ImageGalleryTest
//
//  카메라 프리뷰 기능
//

import AVFoundation
import UIKit

// 🚀 메모리 누수를 방지하기 위한 Delegate Proxy (AVCaptureVideoDataOutput이 델리게이트를 강하게 참조하는 것을 방지)
private class SampleBufferDelegateProxy: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    weak var target: CameraPreviewView?
    
    init(target: CameraPreviewView) {
        self.target = target
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        target?.captureOutput(output, didOutput: sampleBuffer, from: connection)
    }
}

class CameraPreviewView: UIView {
    
    // MARK: - Properties
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    // internal: 전체화면 카메라 VC가 세션을 공유할 수 있도록 접근 허용
    var stillImageOutput: AVCapturePhotoOutput?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    
    // 마지막 화면을 캡처해두는 뷰 (스크롤/정지 시 깜빡임 방지용)
    private var lastFrameSnapshotView: UIView?
    
    // 🚀 갤러리를 닫고 다시 열 때 사용할 전역(static) 스냅샷 이미지
    private static var globalLastCameraSnapshot: UIImage?
    
    // 🚀 갤러리 ID (특정 갤러리가 닫힐 때 카메라를 안전하게 종료하기 위함)
    var galleryID: String?

    // 🚀 캡처 부하를 줄이기 위한 타임스탬프
    private var lastCaptureTime: TimeInterval = 0
    private var isConfiguringCamera = false
    
    // 🚀 세션 시작/종료의 레이스 컨디션을 방지하기 위한 전용 시리얼 큐
    private static let sharedSessionQueue = DispatchQueue(label: "com.camera.sessionQueue", qos: .userInitiated)
    
    // 🚀 활성화된 카메라 인스턴스를 추적하여 중복 실행 및 권한 잠김 방지
    private static weak var currentActiveCamera: CameraPreviewView?
    
    // 로딩 중임을 나타내는 블러 뷰
    private lazy var blurLoadingView: UIVisualEffectView = {
        // 기존 다크(dark)보다 더 얇고 유리 같은 투명도를 위해 systemUltraThinMaterialDark 사용
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        return blurView
    }()
    
    var onPhotoCaptured: ((UIImage?) -> Void)?
    
    /// 전체화면 카메라 VC가 동일한 세션을 공유하기 위해 사용
    func getCameraSessionInfo() -> (session: AVCaptureSession, output: AVCapturePhotoOutput)? {
        guard let session = captureSession, let output = stillImageOutput else { return nil }
        return (session, output)
    }

    /// 가장 마지막으로 캡처된 카메라 프레임 이미지 (애니메이션 스냅샷용)
    var lastCameraSnapshot: UIImage? { Self.globalLastCameraSnapshot }

    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        // 🚀 까만 화면이 깜빡이는 것을 방지하기 위해 배경을 투명하게 설정
        backgroundColor = .clear
        clipsToBounds = true
        
        addSubview(blurLoadingView)
        blurLoadingView.frame = bounds
        
        // ⚠️ 여기서 setupCamera()를 호출하지 않음!
        // 카메라 세션은 startPreview()가 명시적으로 호출될 때만 시작합니다.
        // (모든 셀의 init에서 카메라를 시작하면 하드웨어 충돌 발생)
        setupNotifications()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        debugPrint("🧹 [Deinit] CameraPreviewView 해제 시작")
        NotificationCenter.default.removeObserver(self)
        
        // 🚨 중요: AVCaptureSession 정리는 메인 스레드에서 동기적으로 처리
        // deinit에서 비동기 작업이나 대기는 데드락 위험이 있음
        
        // 메인 스레드에서 실행 중이 아니면 메인 스레드로 전환
        if Thread.isMainThread {
            cleanupCaptureSessionSync()
        } else {
            DispatchQueue.main.sync {
                self.cleanupCaptureSessionSync()
            }
        }
        
        debugPrint("✅ [Deinit] CameraPreviewView 해제 완료")
    }
    
    // 🧹 AVCaptureSession 정리 (메인 스레드 블로킹 방지)
    private func cleanupCaptureSessionSync() {
        guard let session = captureSession else {
            // 세션이 없으면 layer만 제거
            previewLayer?.removeFromSuperlayer()
            previewLayer = nil
            stillImageOutput = nil
            videoDataOutput = nil
            return
        }
        
        // 🚀 UI 요소는 즉시 해제하여 메모리 및 화면 정리
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
        stillImageOutput = nil
        videoDataOutput = nil
        captureSession = nil
        
        // 🚀 세션 정지 및 하드웨어 점유 해제는 시간이 오래 걸리므로 백그라운드 큐로 던져서 메인 스레드 버벅임 방지
        Self.sharedSessionQueue.async {
            if session.isRunning {
                session.stopRunning()
                debugPrint("   ✓ AVCaptureSession 백그라운드 정지 완료")
            }
            
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            session.commitConfiguration()
            debugPrint("✅ [Cleanup] 백그라운드 세션 설정 해제 완료")
        }
    }
    
    // MARK: - Lifecycle
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        
        // 뷰가 윈도우에 추가되고 화면에 보여질 때만 기존 세션을 재시작
        // (새 세션 시작은 startPreview()에서만 처리)
        if window != nil, !isHidden, let session = captureSession {
            setNeedsLayout()
            Self.sharedSessionQueue.async {
                if !session.isRunning {
                    session.startRunning()
                }
            }
        }
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionDidStartRunning),
            name: .AVCaptureSessionDidStartRunning,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionDidStopRunning),
            name: .AVCaptureSessionDidStopRunning,
            object: nil
        )
        
        // 🚀 갤러리가 닫힐 때 카메라를 강제 종료하기 위한 노티피케이션
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(forceStopCamera),
            name: NSNotification.Name("GalleryDidDismissNotification"),
            object: nil
        )
    }
    
    @objc private func forceStopCamera(notification: Notification) {
        // 알림에 포함된 galleryID가 내 galleryID와 일치하는 경우에만 카메라 세션 완전 종료
        guard let id = notification.userInfo?["galleryID"] as? String,
              id == self.galleryID else {
            return
        }
        
        stopPreview()
        
        DispatchQueue.main.async { [weak self] in
            self?.cleanupCaptureSessionSync()
        }
    }
    
    @objc private func sessionDidStartRunning(notification: Notification) {
        guard let session = captureSession,
              let notifiedSession = notification.object as? AVCaptureSession,
              session == notifiedSession else { return }
        
        fadeOutSnapshot()
    }
    
    // 🚀 화면 전환 페이드아웃 애니메이션을 공통 함수로 분리
    private func fadeOutSnapshot() {
        DispatchQueue.main.async { [weak self] in
            // 카메라 켜짐 즉시 스냅샷 제거 (딜레이 없이 빠르게 전환하여 깜빡임/다시 로딩되는 느낌 없앰)
            UIView.animate(withDuration: 0.15, delay: 0.0, options: .curveEaseOut, animations: {
                self?.blurLoadingView.alpha = 0
                self?.lastFrameSnapshotView?.alpha = 0
            }, completion: { _ in
                self?.lastFrameSnapshotView?.removeFromSuperview()
                self?.lastFrameSnapshotView = nil
            })
        }
    }
    
    @objc private func sessionDidStopRunning(notification: Notification) {
        guard let session = captureSession,
              let notifiedSession = notification.object as? AVCaptureSession,
              session == notifiedSession else { return }
        
        DispatchQueue.main.async { [weak self] in
            // 세션이 멈추면 마지막 화면 스냅샷을 띄워 어색하게 깜빡이거나 뷰가 사라지는 현상 방지
            if self?.lastFrameSnapshotView == nil, let lastImage = Self.globalLastCameraSnapshot {
                let iv = UIImageView(image: lastImage)
                iv.frame = self?.bounds ?? .zero
                iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                iv.contentMode = .scaleAspectFill
                self?.addSubview(iv)
                self?.lastFrameSnapshotView = iv
            }
        }
    }
    
    // MARK: - Camera Setup
    
    private func setupCamera() {
        if isConfiguringCamera || captureSession != nil { return }
        
        // 이전 카메라 뷰가 아직 살아있다면 먼저 강제 정리하여 카메라 하드웨어 점유를 해제합니다.
        if let oldCamera = Self.currentActiveCamera, oldCamera !== self {
            oldCamera.cleanupCaptureSessionSync()
        }
        Self.currentActiveCamera = self
        
        isConfiguringCamera = true
        
        let cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch cameraAuthStatus {
        case .authorized:
            configureCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.configureCamera()
                } else {
                    DispatchQueue.main.async { self?.isConfiguringCamera = false }
                }
            }
        default:
            isConfiguringCamera = false
            break
        }
    }
    
    private func configureCamera() {
        Self.sharedSessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            guard self.captureSession == nil else { 
                DispatchQueue.main.async { self.isConfiguringCamera = false }
                return 
            }
            
            let session = AVCaptureSession()
            session.sessionPreset = .photo
            
            // 🚀 광각 카메라가 없을 경우(일부 기기) 기본 비디오 카메라로 폴백
            guard let videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) ?? AVCaptureDevice.default(for: .video) else {
                #if targetEnvironment(simulator)
                // 🚀 시뮬레이터용 가짜 카메라 피드 (작동 확인용)
                DispatchQueue.main.async {
                    let fakeView = UIView(frame: self.bounds)
                    fakeView.backgroundColor = UIColor(red: 0.2, green: 0.2, blue: 0.3, alpha: 1.0)
                    fakeView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    
                    let label = UILabel()
                    label.text = "Simulator\nCamera Feed"
                    label.numberOfLines = 2
                    label.textAlignment = .center
                    label.textColor = .white
                    label.font = .systemFont(ofSize: 16, weight: .bold)
                    label.translatesAutoresizingMaskIntoConstraints = false
                    fakeView.addSubview(label)
                    
                    NSLayoutConstraint.activate([
                        label.centerXAnchor.constraint(equalTo: fakeView.centerXAnchor),
                        label.centerYAnchor.constraint(equalTo: fakeView.centerYAnchor)
                    ])
                    
                    self.addSubview(fakeView)
                    
                    // 가짜 애니메이션 제거 (사용자 요청으로 단일 배경색 유지)
                }
                #endif
                return
            }
            
            do {
                let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
                
                guard session.canAddInput(videoInput) else { return }
                session.addInput(videoInput)
                
                // Photo Output 설정
                let output = AVCapturePhotoOutput()
                if session.canAddOutput(output) {
                    session.addOutput(output)
                    self.stillImageOutput = output
                }
                
                // 🚀 Video Data Output 설정 (마지막 라이브 프레임 캡처용)
                let dataOutput = AVCaptureVideoDataOutput()
                dataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
                dataOutput.alwaysDiscardsLateVideoFrames = true
                if session.canAddOutput(dataOutput) {
                    session.addOutput(dataOutput)
                    // 샘플 버퍼 델리게이트는 시리얼 큐에서 처리 (Retain Cycle 방지용 Proxy 사용)
                    let proxy = SampleBufferDelegateProxy(target: self)
                    dataOutput.setSampleBufferDelegate(proxy, queue: Self.sharedSessionQueue)
                    self.videoDataOutput = dataOutput
                }
                
                // Preview Layer UI 설정은 메인 스레드에서
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    let preview = AVCaptureVideoPreviewLayer(session: session)
                    preview.videoGravity = .resizeAspectFill
                    preview.frame = self.bounds // 🚀 생성 즉시 frame 설정
                    preview.masksToBounds = true
                    
                    self.layer.addSublayer(preview)
                    self.previewLayer = preview
                    self.captureSession = session
                    
                    // 🚀 UI 설정이 완료된 후, 안전하게 백그라운드에서 세션 시작
                    Self.sharedSessionQueue.async {
                        session.startRunning()
                        
                        DispatchQueue.main.async {
                            self.isConfiguringCamera = false
                        }
                    }
                }
                
            } catch {
                print("❌ 카메라 설정 오류: \(error)")
                DispatchQueue.main.async {
                    self.isConfiguringCamera = false
                }
            }
        }
    }
    
    // MARK: - Camera Controls
    
    func startPreview() {
        guard let session = captureSession else {
            setupCamera()
            return
        }
        
        Self.sharedSessionQueue.async { [weak self] in
            if !session.isRunning {
                session.startRunning()
            } else {
                // 🚀 이미 세션이 돌고 있다면 Notification이 발생하지 않으므로 여기서 직접 페이드아웃 호출
                self?.fadeOutSnapshot()
            }
        }
    }
    
    func stopPreview() {
        guard let session = captureSession else { return }
        
        // 🚀 스크롤로 가려질 때 (정지 직전) 마지막 라이브 프레임을 화면에 붙임
        if lastFrameSnapshotView == nil, let lastImage = Self.globalLastCameraSnapshot {
            let iv = UIImageView(image: lastImage)
            iv.frame = self.bounds
            iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            iv.contentMode = .scaleAspectFill
            self.addSubview(iv)
            self.lastFrameSnapshotView = iv
        }
        
        Self.sharedSessionQueue.async { [weak session] in
            if session?.isRunning == true {
                session?.stopRunning()
                debugPrint("   ✓ stopPreview 호출 완료 (시리얼 큐)")
            }
        }
    }
    
    func ensureRunning() {
        guard let session = captureSession else { return }
        
        Self.sharedSessionQueue.async {
            if !session.isRunning {
                session.startRunning()
            }
        }
    }
    
    func capturePhoto(flashMode: AVCaptureDevice.FlashMode = .off) {
        guard let output = stillImageOutput else { return }
        
        let settings: AVCapturePhotoSettings
        if output.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }
        
        if output.supportedFlashModes.contains(flashMode) {
            settings.flashMode = flashMode
        }
        
        output.capturePhoto(with: settings, delegate: self)
    }
    
    @objc func cameraViewTapped() {
        capturePhoto()
    }
    
    // MARK: - Layout
    
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 && bounds.height > 0 else { return }

        // 일반 레이아웃 시에는 암묵적 애니메이션 비활성화 (깜빡임 방지)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraPreviewView: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // ⚠️ 이 델리게이트는 백그라운드 스레드에서 호출됨
        // UIView 애니메이션이 포함된 콜백은 반드시 메인 스레드에서 실행해야 함
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            DispatchQueue.main.async { self.onPhotoCaptured?(nil) }
            return
        }
        DispatchQueue.main.async { self.onPhotoCaptured?(image) }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraPreviewView: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // 부하를 방지하기 위해 초당 3프레임(약 0.33초) 간격으로만 저장
        let currentTime = CACurrentMediaTime()
        if currentTime - lastCaptureTime < 0.33 { return }
        lastCaptureTime = currentTime
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = FilterManager.shared.context
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        // 방향 보정 (기본적으로 오른쪽으로 누운 형태이므로 우회전)
        let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
        
        DispatchQueue.main.async {
            Self.globalLastCameraSnapshot = image
        }
    }
}

// MARK: - Device Controls (CameraExpandOverlay 전용)

extension CameraPreviewView {

    /// 현재 활성 비디오 디바이스
    private var currentVideoDevice: AVCaptureDevice? {
        captureSession?.inputs
            .compactMap { ($0 as? AVCaptureDeviceInput)?.device }
            .first { $0.hasMediaType(.video) }
    }

    /// 현재 줌 팩터
    var zoomFactor: CGFloat {
        currentVideoDevice?.videoZoomFactor ?? 1.0
    }

    /// 최소 줌 팩터
    var minZoomFactor: CGFloat {
        currentVideoDevice?.minAvailableVideoZoomFactor ?? 1.0
    }

    /// 최대 줌 팩터 (8배로 상한)
    var maxZoomFactor: CGFloat {
        min(currentVideoDevice?.maxAvailableVideoZoomFactor ?? 1.0, 8.0)
    }

    /// 줌 팩터 설정
    /// - Parameters:
    ///   - factor: 원하는 줌 배율
    ///   - animated: true면 ramp(부드럽게), false면 즉시 적용
    func setZoomFactor(_ factor: CGFloat, animated: Bool = false) {
        guard let device = currentVideoDevice else { return }
        let clamped = max(device.minAvailableVideoZoomFactor,
                          min(factor, min(device.maxAvailableVideoZoomFactor, 8.0)))
        do {
            try device.lockForConfiguration()
            if animated {
                device.ramp(toVideoZoomFactor: clamped, withRate: 6)
            } else {
                device.videoZoomFactor = clamped
            }
            device.unlockForConfiguration()
        } catch {}
    }

    /// 탭한 포인트(cameraContainer 좌표계)로 포커스 & 노출 설정
    func focusAndExpose(at containerPoint: CGPoint) {
        guard let device = currentVideoDevice,
              let layer = previewLayer else { return }

        // 레이어 좌표 → 디바이스 좌표 변환
        let devicePoint = layer.captureDevicePointConverted(fromLayerPoint: containerPoint)

        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch {}
    }

    /// 울트라와이드(0.5×) 카메라가 이 디바이스에서 사용 가능한지 확인
    var isUltraWideAvailable: Bool {
        AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) != nil
    }

    /// 0.5× 버튼: 울트라와이드로 전환 (없으면 최소 줌)
    func switchToUltraWide(completion: @escaping (Bool) -> Void) {
        guard let session = captureSession else { completion(false); return }

        if let uwDevice = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back),
           let uwInput = try? AVCaptureDeviceInput(device: uwDevice) {
            Self.sharedSessionQueue.async {
                session.beginConfiguration()
                session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
                              .filter { $0.device.hasMediaType(.video) }
                              .forEach { session.removeInput($0) }
                if session.canAddInput(uwInput) {
                    session.addInput(uwInput)
                    session.commitConfiguration()
                    DispatchQueue.main.async { completion(true) }
                } else {
                    session.commitConfiguration()
                    DispatchQueue.main.async { completion(false) }
                }
            }
        } else {
            // 울트라와이드 없음 → 현재 디바이스 최소 줌 적용
            setZoomFactor(minZoomFactor, animated: true)
            completion(false)
        }
    }

    /// 메인 와이드앵글 카메라로 복귀 후 지정 줌 설정
    func switchToWideAngle(targetZoom: CGFloat, completion: @escaping () -> Void) {
        guard let session = captureSession else { completion(); return }

        let pos: AVCaptureDevice.Position = .back
        guard let wideDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: pos)
                ?? AVCaptureDevice.default(for: .video),
              let wideInput = try? AVCaptureDeviceInput(device: wideDevice) else {
            completion(); return
        }

        // 이미 와이드앵글이면 줌만 변경
        if let current = currentVideoDevice, current.deviceType == .builtInWideAngleCamera {
            setZoomFactor(targetZoom, animated: true)
            completion()
            return
        }

        Self.sharedSessionQueue.async {
            session.beginConfiguration()
            session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
                          .filter { $0.device.hasMediaType(.video) }
                          .forEach { session.removeInput($0) }
            if session.canAddInput(wideInput) {
                session.addInput(wideInput)
            }
            session.commitConfiguration()
            DispatchQueue.main.async {
                self.setZoomFactor(targetZoom, animated: true)
                completion()
            }
        }
    }
    /// 오버레이 닫힐 때 줌 초기화 (zoom factor만 1×, 세션 전환 없음)
    /// - 세션 전환(울트라와이드↔와이드앵글) 시 brief black flash 발생
    /// - 따라서 닫을 때는 zoom factor만 리셋하고,
    ///   울트라와이드 → 와이드앵글 전환은 다음에 열릴 때(show) 처리
    func resetZoomToDefault() {
        setZoomFactor(1.0, animated: false)
    }

    /// 현재 울트라와이드 카메라가 활성화되어 있는지 확인
    var isOnUltraWideCamera: Bool {
        currentVideoDevice?.deviceType == .builtInUltraWideCamera
    }
}
