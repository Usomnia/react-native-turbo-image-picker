//
//  CameraFullscreenViewController.swift
//  RNTurboImagePicker
//
//  iOS 기본 카메라 앱 UI와 동일 (동영상 제외)
//
//  ── 핵심 구현 전략 ──────────────────────────────────────────────
//  AVCaptureVideoPreviewLayer는 UIView.animate frame 변경에
//  반응하지 않아 닫기 애니메이션이 깨지는 문제가 있음.
//
//  해결책: "스냅샷 이미지" 전략
//   - 닫기: 마지막 캡처 프레임을 UIImageView로 만들어 축소 애니메이션
//           실제 CameraPreviewView는 즉시 셀에 복귀
//   - 카메라 전환(0.5×↔1×↔2×): 전환 동안 스냅샷으로 화면을 가려
//           블랙/점프 현상 방지 후 페이드 인
//

import AVFoundation
import Photos
import UIKit

// MARK: - CameraExpandOverlay

class CameraExpandOverlay: UIView {

    // MARK: - Public

    private weak var borrowedCameraView: CameraPreviewView?
    var onPhotoCaptured: ((UIImage) -> Void)?
    var onDismiss: (() -> Void)?

    // MARK: - State

    private var flashMode: AVCaptureDevice.FlashMode = .off
    private var isCapturing = false
    private var sourceCellFrame: CGRect = .zero
    private var isFrontCamera = false
    private var isSwitchingCamera = false      // 카메라 전환 중 중복 방지
    private var currentZoomIndex = 1
    private var pinchBeginZoom: CGFloat = 1.0

    private struct ZoomLevel {
        let factor: CGFloat
        let selectedTitle: String
        let normalTitle: String
    }
    private let zoomLevels: [ZoomLevel] = [
        ZoomLevel(factor: 0.5, selectedTitle: "0.5×", normalTitle: "0.5"),
        ZoomLevel(factor: 1.0, selectedTitle: "1×",   normalTitle: "1"),
        ZoomLevel(factor: 2.0, selectedTitle: "2×",   normalTitle: "2")
    ]
    private var zoomBtns: [UIButton] = []
    private var zoomWidthConstraints: [NSLayoutConstraint] = []
    private var zoomHeightConstraints: [NSLayoutConstraint] = []

    private static let yellow = UIColor(red: 1.0, green: 0.83, blue: 0.0, alpha: 1.0)
    private static let sessionQueue = DispatchQueue(label: "com.overlay.camera.q", qos: .userInitiated)

    // MARK: - Subviews

    private let dimView: UIView = {
        let v = UIView(); v.backgroundColor = .black; v.alpha = 0; return v
    }()

    private let cameraContainer: UIView = {
        let v = UIView(); v.backgroundColor = .black; v.clipsToBounds = true; return v
    }()

    private lazy var flashButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.tintColor = .white; btn.alpha = 0
        btn.addTarget(self, action: #selector(flashTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var zoomContainer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0, alpha: 0.15)
        v.layer.cornerRadius = 20
        v.alpha = 0
        return v
    }()

    private lazy var zoomStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal; sv.spacing = 6; sv.alignment = .center; sv.alpha = 0
        return sv
    }()

    private let instructionLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = "사진"
        lbl.textColor = yellow
        lbl.font = .systemFont(ofSize: 15, weight: .semibold)
        lbl.textAlignment = .center
        lbl.alpha = 0
        return lbl
    }()

    private lazy var closeButton: UIButton = {
        let btn = UIButton(type: .custom)
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        btn.setImage(UIImage(systemName: "xmark", withConfiguration: cfg), for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = UIColor(white: 0.15, alpha: 0.85) // 조금 더 어둡게
        btn.layer.cornerRadius = 28
        btn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return btn
    }()

    private let shutterRing: UIView = {
        let v = UIView()
        v.backgroundColor = .clear
        v.layer.borderColor = UIColor.white.cgColor
        v.layer.borderWidth = 4.0
        v.isUserInteractionEnabled = false
        return v
    }()

    private lazy var shutterFill: UIButton = {
        let btn = UIButton()
        btn.backgroundColor = .white
        btn.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        btn.addTarget(self, action: #selector(shutterDown), for: .touchDown)
        btn.addTarget(self, action: #selector(shutterUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        return btn
    }()

    private lazy var flipButton: UIButton = {
        let btn = UIButton(type: .custom)
        let cfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        btn.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.camera", withConfiguration: cfg), for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = UIColor(white: 0.15, alpha: 0.85) // 조금 더 어둡게
        btn.layer.cornerRadius = 28
        btn.addTarget(self, action: #selector(flipTapped), for: .touchUpInside)
        return btn
    }()

    // MARK: - Transitions
    
    private func flipCameraWithTransition(_ action: @escaping (@escaping () -> Void) -> Void) {
        guard !isSwitchingCamera, let cam = borrowedCameraView else { return }
        isSwitchingCamera = true
        
        let snapshot = cam.snapshotView(afterScreenUpdates: false) ?? UIView()
        snapshot.frame = cam.bounds
        cam.addSubview(snapshot)
        
        action {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                UIView.transition(with: cam, duration: 0.4, options: [.transitionFlipFromLeft, .allowAnimatedContent], animations: {
                    snapshot.removeFromSuperview()
                }) { _ in
                    self.isSwitchingCamera = false
                }
            }
        }
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildHierarchy()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildHierarchy() {
        addSubview(dimView)
        addSubview(zoomContainer)
        addSubview(zoomStack)
        addSubview(flashButton)
        addSubview(instructionLabel)
        addSubview(closeButton)
        addSubview(shutterRing)
        addSubview(shutterFill)
        addSubview(flipButton)
        buildZoomButtons()
        updateFlashIcon()
    }

    private func buildZoomButtons() {
        for (i, _) in zoomLevels.enumerated() {
            let btn = UIButton(type: .custom)
            btn.tag = i
            btn.layer.masksToBounds = true
            btn.translatesAutoresizingMaskIntoConstraints = false
            
            let w = btn.widthAnchor.constraint(equalToConstant: 30)
            let h = btn.heightAnchor.constraint(equalToConstant: 30)
            w.isActive = true
            h.isActive = true
            zoomWidthConstraints.append(w)
            zoomHeightConstraints.append(h)
            
            btn.addTarget(self, action: #selector(zoomBtnTapped(_:)), for: .touchUpInside)
            applyZoomStyle(btn, index: i, selected: i == currentZoomIndex)
            zoomStack.addArrangedSubview(btn)
            zoomBtns.append(btn)
        }
    }

    private func applyZoomStyle(_ btn: UIButton, index: Int, selected: Bool) {
        let level = zoomLevels[index]
        btn.setTitle(selected ? level.selectedTitle : level.normalTitle, for: .normal)
        btn.setTitleColor(selected ? Self.yellow : .white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: selected ? 15 : 13, weight: selected ? .bold : .medium)
        btn.backgroundColor = UIColor(white: 0, alpha: 0.35) // 좀 더 투명하게
        
        let size: CGFloat = selected ? 38 : 30
        btn.layer.cornerRadius = size / 2
        
        zoomWidthConstraints[index].constant = size
        zoomHeightConstraints[index].constant = size
    }

    private func refreshZoomButtons(animated: Bool = false) {
        let update = {
            self.zoomBtns.enumerated().forEach { i, btn in
                self.applyZoomStyle(btn, index: i, selected: i == self.currentZoomIndex)
            }
            self.zoomStack.layoutIfNeeded()
        }
        
        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut], animations: update)
        } else {
            update()
        }
    }

    // MARK: - Gestures
    // 제스처는 show() 에서 cameraView에 직접 부착 (cameraContainer 불필요)

    // MARK: - Metrics

    private var safeTop: CGFloat    { window?.safeAreaInsets.top    ?? 44 }
    private var safeBottom: CGFloat { window?.safeAreaInsets.bottom  ?? 34 }
    private var screenW: CGFloat    { UIScreen.main.bounds.width }
    private var screenH: CGFloat    { UIScreen.main.bounds.height }

    private var targetCameraFrame: CGRect {
        CGRect(x: 0, y: safeTop + 85, width: screenW, height: screenW * 4.0 / 3.0) // 카메라 화면을 좀 더 아래로 이동
    }

    // MARK: - Show
    //
    // ── 핵심 전략: cameraView 직접 frame 애니메이션 ──────────────────────────
    //
    // cameraContainer(4:3) + transform 방식의 문제:
    //   닫힐 때 transform으로 셀 위치를 흉내 내지만, reattach 시 셀의 실제
    //   frame(정사각형)과 약간 달라 위치 점프 발생.
    //
    // 해결: cameraView 자체를 window에 직접 추가하고 frame을 애니메이션.
    //   닫힐 때 frame = sourceCellFrame (정확한 셀 위치) → reattach 시
    //   contentView.bounds와 동일 영역 → 위치 불일치 없음.
    // ──────────────────────────────────────────────────────────────────────

    func show(in window: UIView, from cellFrame: CGRect, cameraView: CameraPreviewView) {
        sourceCellFrame = cellFrame
        borrowedCameraView = cameraView
        frame = window.bounds
        window.addSubview(self)

        dimView.frame = bounds
        dimView.alpha = 0

        // ── 열기 애니메이션 Wrapper 패턴 ───────────────────────────────────────
        // 닫기와 마찬가지로 열 때도 bounds가 커지면 비디오 레이어가 팍! 하고 snap 됩니다.
        // 이를 막기 위해 cameraView를 처음부터 3:4(최종 크기)로 만들고,
        // 작게 축소(transform)해서 1:1 래퍼 안에 넣은 상태로 시작합니다.
        // 그리고 래퍼와 비율을 동시에 키우면 완벽히 부드럽게 열립니다.
        // ─────────────────────────────────────────────────────────────────
        let cropWrapper = UIView(frame: cellFrame) // 1:1 셀 크기에서 시작
        cropWrapper.clipsToBounds = true
        insertSubview(cropWrapper, aboveSubview: dimView)

        let finalBounds = targetCameraFrame // 최종 3:4 크기 (예: 390x520)
        cameraView.bounds = CGRect(origin: .zero, size: finalBounds.size)
        cameraView.autoresizingMask = [] // 🔥 이중 스케일 방지
        
        let scaleX = cellFrame.width / finalBounds.width
        let scaleY = cellFrame.height / finalBounds.height
        let initialScale = max(scaleX, scaleY)
        
        cameraView.transform = CGAffineTransform(scaleX: initialScale, y: initialScale)
        cameraView.center = CGPoint(x: cellFrame.width / 2, y: cellFrame.height / 2)
        
        cropWrapper.addSubview(cameraView)
        cameraView.isHidden = false

        // 컨트롤들은 숨긴 상태로 시작 (layoutAllControls 내부에서 alpha = 0 됨)
        layoutAllControls()

        let openDuration: TimeInterval = 0.45
        UIView.animate(
            withDuration: openDuration,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0.0,
            options: [.curveEaseInOut, .allowUserInteraction]
        ) {
            cropWrapper.frame = finalBounds
            cameraView.transform = .identity
            cameraView.center = CGPoint(x: finalBounds.width / 2, y: finalBounds.height / 2)
            self.dimView.alpha = 1
            
            // 컨트롤 페이드 인을 동시에 진행하여 훨씬 빠르고 반응성 있게 만듭니다
            self.flashButton.alpha   = 1
            self.zoomContainer.alpha = 1
            self.zoomStack.alpha     = 1
            self.instructionLabel.alpha = 1
            self.shutterRing.alpha   = 1
            self.flipButton.alpha    = 1
            self.closeButton.alpha   = 1
        } completion: { _ in
            // 애니메이션 완료 후 wrapper 제거하고 원래 뷰계층으로 복귀
            cameraView.transform = .identity
            cameraView.frame = finalBounds
            self.insertSubview(cameraView, aboveSubview: self.dimView)
            cropWrapper.removeFromSuperview()

            // 제스처 부착
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(self.handlePinch(_:)))
            let tap   = UITapGestureRecognizer(target: self, action: #selector(self.handleTap(_:)))
            let pan   = UIPanGestureRecognizer(target: self, action: #selector(self.handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            cameraView.addGestureRecognizer(pinch)
            cameraView.addGestureRecognizer(tap)
            cameraView.addGestureRecognizer(pan)

            cameraView.onPhotoCaptured = { [weak self] image in
                guard let self, let image else { return }
                let cb = self.onPhotoCaptured
                self.dismissOverlay { cb?(image) }
            }
            self.currentZoomIndex = 1
            self.refreshZoomButtons()
            if cameraView.isOnUltraWideCamera {
                cameraView.switchToWideAngle(targetZoom: 1.0) {}
            }
            if !cameraView.isUltraWideAvailable { self.zoomBtns.first?.isHidden = true }
        }
    }

    private func layoutAllControls() {
        let safeT = safeTop
        let safeB = safeBottom
        
        // 닫기 버튼: 셔터 좌측
        let iconSz: CGFloat = 50
        
        let shutterSz: CGFloat = 80 // 크게
        let shutterY = screenH - safeB - 10 - shutterSz
        
        shutterRing.frame = CGRect(x: (screenW - shutterSz) / 2, y: shutterY, width: shutterSz, height: shutterSz)
        shutterRing.layer.cornerRadius = shutterSz / 2
        shutterRing.alpha = 0
        
        let fillSz: CGFloat = 66
        shutterFill.frame = CGRect(x: (screenW - fillSz) / 2, y: shutterY + (shutterSz - fillSz) / 2, width: fillSz, height: fillSz)
        shutterFill.layer.cornerRadius = fillSz / 2
        
        // 플래시 버튼: 좌상단
        let topIconSz: CGFloat = 44
        flashButton.frame = CGRect(x: 16, y: safeT + 10, width: topIconSz, height: topIconSz)
        flashButton.alpha = 0
        
        closeButton.frame = CGRect(x: screenW * 0.12 - iconSz / 2, y: shutterY + (shutterSz - iconSz) / 2, width: iconSz, height: iconSz)
        closeButton.alpha = 0
        
        flipButton.frame = CGRect(x: screenW * 0.88 - iconSz / 2, y: shutterY + (shutterSz - iconSz) / 2, width: iconSz, height: iconSz)
        flipButton.alpha = 0
        
        instructionLabel.sizeToFit()
        instructionLabel.frame = CGRect(x: 0, y: targetCameraFrame.maxY + 25, width: screenW, height: 20) // 살짝 더 아래로 내림
        instructionLabel.alpha = 0
        
        zoomStack.sizeToFit()
        let zoomSz = zoomStack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        
        let height: CGFloat = max(40, zoomSz.height + 6)
        let zoomY = targetCameraFrame.maxY - 15 - height // 카메라 뷰 안쪽 하단
        
        zoomContainer.frame = CGRect(
            x: (screenW - zoomSz.width - 24) / 2,
            y: zoomY,
            width: zoomSz.width + 24, height: height
        )
        zoomContainer.layer.cornerRadius = height / 2
        zoomContainer.alpha = 0
        
        zoomStack.frame = CGRect(
            x: (screenW - zoomSz.width) / 2,
            y: zoomY + (height - zoomSz.height) / 2,
            width: zoomSz.width, height: zoomSz.height
        )
        zoomStack.alpha = 0
    }

    // MARK: - Dismiss
    //
    // cameraView.frame을 sourceCellFrame으로 직접 애니메이션.
    // 닫힐 때 cameraView가 정확히 셀 위치/크기가 되므로 reattach 시 위치 일치.

    func dismissOverlay(completion: (() -> Void)? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.dismissOverlay(completion: completion) }
            return
        }

        guard let cameraView = borrowedCameraView else {
            removeFromSuperview(); completion?(); return
        }

        // ── 시각적 위치 캡처 + 래퍼(Wrapper) 패턴 (No Bounds Change) ─────────
        // 카메라 레이어(previewLayer)는 bounds가 1픽셀이라도 변하면 내부 비디오 피드를
        // 즉시(snap) 재조정해버리는 치명적인 버그가 있습니다.
        // 이를 막기 위해 cameraView의 bounds(3:4 원본 크기)를 절대 건드리지 않고,
        // 오직 transform(비율 축소)과 center만 애니메이션하여 cropWrapper 안에서 부드럽게 크롭합니다.
        // ─────────────────────────────────────────────────────────────────
        let visualFrame = cameraView.layer.presentation()?.frame ?? cameraView.frame
        let originalBounds = cameraView.bounds // 항상 3:4 원본 크기 유지 (예: 390x520)
        cameraView.layer.removeAllAnimations()
        
        // 1. 현재 화면상 위치에 정확히 맞는 클리핑 래퍼 생성
        let cropWrapper = UIView(frame: visualFrame)
        cropWrapper.clipsToBounds = true
        insertSubview(cropWrapper, belowSubview: cameraView)
        
        // 2. 현재 시각적 크기 비율 계산 (pan 제스처 등으로 축소되어 있을 수 있음)
        // 화면에 보여지는 width를 기준으로 원본 대비 얼마로 축소되어 있는지 확인
        let currentScale = visualFrame.width / originalBounds.width
        
        // 3. cameraView를 래퍼 안으로 이동
        // 🔥 아주 중요: GalleryCell에서 설정된 autoresizingMask가 켜져 있으면,
        // cropWrapper의 bounds가 변할 때 cameraView의 bounds도 같이 변해서 이중 축소/스냅이 일어납니다!
        cameraView.autoresizingMask = []
        cropWrapper.addSubview(cameraView)
        
        cameraView.bounds = originalBounds
        cameraView.transform = CGAffineTransform(scaleX: currentScale, y: currentScale)
        // 래퍼의 정중앙에 배치하면 시각적으로 이전과 100% 동일한 위치가 됨
        cameraView.center = CGPoint(x: visualFrame.width / 2, y: visualFrame.height / 2)

        borrowedCameraView?.resetZoomToDefault()

        // 1단계+2단계 동시 애니메이션: 스프링 물리 엔진을 적용하여 iOS 네이티브스러운 쫀득한 애니메이션 구현
        let shrinkDuration: TimeInterval = 0.45
        let targetCropFrame = self.sourceCellFrame // 갤러리 셀 크기 (예: 130x261)
        
        // 🔥 aspectFill 비율 계산: 타겟 프레임을 "가득" 채울 수 있는 최소 스케일
        let scaleX = targetCropFrame.width / originalBounds.width
        let scaleY = targetCropFrame.height / originalBounds.height
        let targetScale = max(scaleX, scaleY)
        
        let targetTransform = CGAffineTransform(scaleX: targetScale, y: targetScale)
        // 래퍼 정중앙에 배치 (남는 좌우 또는 상하는 래퍼의 clipsToBounds에 의해 자동으로 크롭됨)
        let targetCenter = CGPoint(x: targetCropFrame.width / 2, y: targetCropFrame.height / 2)

        UIView.animate(
            withDuration: shrinkDuration,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0.0,
            options: [.curveEaseInOut, .allowUserInteraction]
        ) {
            self.flashButton.alpha   = 0
            self.zoomContainer.alpha = 0
            self.zoomStack.alpha     = 0
            self.instructionLabel.alpha = 0
            self.shutterRing.alpha   = 0
            self.flipButton.alpha    = 0
            self.closeButton.alpha   = 0
            self.dimView.alpha       = 0
            
            // 갤러리 셀로 돌아갈 때, 카메라 화면 자체가 투명해지지 않도록 복구
            self.alpha = 1.0
            
            cropWrapper.frame = targetCropFrame
            cameraView.transform = targetTransform
            cameraView.center = targetCenter
            cameraView.layer.cornerRadius = 0
        } completion: { _ in
            // 3단계: 제스처 제거, 셀에 복귀, overlay 제거
            cameraView.gestureRecognizers?.forEach { cameraView.removeGestureRecognizer($0) }
            cameraView.onPhotoCaptured = nil
            self.onDismiss?()  // reattachCameraPreviewView()
            
            cropWrapper.removeFromSuperview()
            self.removeFromSuperview()
            completion?()
        }
    }

    // MARK: - Camera Switch Transition

    /// 카메라 전환 시 검은 화면 점프 방지:
    /// 전환 중 dim 오버레이로 화면을 잠깐 가리고 페이드 인
    private func switchCameraWithTransition(_ action: @escaping (@escaping () -> Void) -> Void, completion: (() -> Void)? = nil) {
        guard !isSwitchingCamera, let cam = borrowedCameraView else { return }
        isSwitchingCamera = true

        let snapshot = cam.snapshotView(afterScreenUpdates: false) ?? UIView()
        snapshot.frame = cam.bounds
        cam.addSubview(snapshot)
        
        action {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseInOut) {
                    snapshot.alpha = 0
                } completion: { _ in
                    snapshot.removeFromSuperview()
                    self.isSwitchingCamera = false
                    completion?()
                }
            }
        }
    }


    // MARK: - Gesture Handlers

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard let cam = borrowedCameraView, !isSwitchingCamera else { return }
        switch g.state {
        case .began:
            pinchBeginZoom = cam.zoomFactor

        case .changed:
            let rawFactor = pinchBeginZoom * g.scale

            if rawFactor < cam.minZoomFactor {
                // 최소 줌 이하 → 울트라와이드 전환 (0.5×)
                if cam.isUltraWideAvailable && currentZoomIndex != 0 {
                    currentZoomIndex = 0
                    refreshZoomButtons()
                    switchCameraWithTransition { done in
                        cam.switchToUltraWide { [weak self] _ in
                            self?.pinchBeginZoom = cam.zoomFactor
                            done()
                        }
                    }
                }
            } else if currentZoomIndex == 0 && rawFactor >= 1.08 {
                // 울트라와이드에서 1× 이상 → 와이드앵글 복귀
                currentZoomIndex = 1
                refreshZoomButtons()
                switchCameraWithTransition { done in
                    cam.switchToWideAngle(targetZoom: rawFactor) { [weak self] in
                        self?.pinchBeginZoom = cam.zoomFactor
                        done()
                    }
                }
            } else {
                cam.setZoomFactor(rawFactor, animated: false)
                syncZoomButtonsToFactor(rawFactor)
            }

        default: break
        }
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        guard let cam = borrowedCameraView else { return }
        let ptInCam = g.location(in: cam)       // previewLayer 좌표계
        cam.focusAndExpose(at: ptInCam)
        let ptInSelf = g.location(in: self)     // overlay 좌표계 (indicator 표시)
        showFocusIndicator(at: ptInSelf)
    }

    // MARK: - Pan (상하 드래그 → 닫기)
    //
    // X는 고정(0), Y만 이동. 계산 단순화 + 자연스러운 세로 스와이프

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard let cam = borrowedCameraView else { return }
        let translation = g.translation(in: self)
        let dy = max(0, translation.y)   // 위로 드래그는 무시

        switch g.state {
        case .changed:
            let scale = max(0.85, 1.0 - (dy / (bounds.height * 2)))
            cam.transform = CGAffineTransform(translationX: translation.x, y: dy).scaledBy(x: scale, y: scale)
            
            let alpha = max(0.4, 1.0 - (dy / (bounds.height * 1.5)))
            self.alpha = alpha
            
            cam.layer.masksToBounds = true
            cam.layer.cornerRadius = min(40, max(0, dy / 5.0))
            
            // 버튼류는 조금 더 빨리 숨기기
            let ctrlAlpha = max(0, 1.0 - (dy / (bounds.height * 0.3)))
            flashButton.alpha       = ctrlAlpha
            zoomContainer.alpha     = ctrlAlpha
            zoomStack.alpha         = ctrlAlpha
            instructionLabel.alpha  = ctrlAlpha
            shutterRing.alpha       = ctrlAlpha
            flipButton.alpha        = ctrlAlpha
            closeButton.alpha       = ctrlAlpha

        case .ended, .cancelled:
            let vy = g.velocity(in: self).y
            if dy > 150 || vy > 500 {
                dismissOverlay()
            } else {
                UIView.animate(
                    withDuration: 0.3, delay: 0,
                    usingSpringWithDamping: 0.8, initialSpringVelocity: 0,
                    options: [.allowUserInteraction]
                ) {
                    cam.transform = .identity
                    self.alpha = 1.0
                    cam.layer.cornerRadius = 0
                    
                    self.flashButton.alpha      = 1
                    self.zoomContainer.alpha    = 1
                    self.zoomStack.alpha        = 1
                    self.instructionLabel.alpha = 1
                    self.shutterRing.alpha      = 1
                    self.flipButton.alpha       = 1
                    self.closeButton.alpha      = 1
                }
            }
        default: break
        }
    }

    private func showFocusIndicator(at pt: CGPoint) {
        let sz: CGFloat = 68
        let box = UIView(frame: CGRect(x: pt.x-sz/2, y: pt.y-sz/2, width: sz, height: sz))
        box.layer.borderColor = Self.yellow.cgColor
        box.layer.borderWidth = 1.5; box.alpha = 0
        addSubview(box)  // overlay에 추가 (cameraView 위에 표시)
        UIView.animate(withDuration: 0.15) {
            box.alpha = 1
            box.transform = CGAffineTransform(scaleX: 0.82, y: 0.82)
        } completion: { _ in
            UIView.animate(withDuration: 0.4, delay: 0.8) { box.alpha = 0 }
            completion: { _ in box.removeFromSuperview() }
        }
    }

    private func syncZoomButtonsToFactor(_ factor: CGFloat) {
        let idx: Int
        if factor < 0.75      { idx = 0 }
        else if factor < 1.5  { idx = 1 }
        else                  { idx = 2 }
        guard idx != currentZoomIndex else { return }
        currentZoomIndex = idx
        refreshZoomButtons(animated: true)
    }

    // MARK: - Button Actions

    @objc private func closeTapped() { dismissOverlay() }

    @objc private func flashTapped() {
        switch flashMode {
        case .off:  flashMode = .on
        case .on:   flashMode = .auto
        default:    flashMode = .off
        }
        updateFlashIcon()
        UIView.animate(withDuration: 0.1) {
            self.flashButton.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
        } completion: { _ in
            UIView.animate(withDuration: 0.08) { self.flashButton.transform = .identity }
        }
    }

    @objc private func zoomBtnTapped(_ sender: UIButton) {
        let idx = sender.tag
        guard let cam = borrowedCameraView else { return }
        
        let prevIdx = currentZoomIndex
        if prevIdx == idx { return }
        
        currentZoomIndex = idx
        refreshZoomButtons(animated: true)

        let isSwitchingLens = (prevIdx == 0 && idx != 0) || (prevIdx != 0 && idx == 0)
        
        let performZoom = { (done: @escaping () -> Void) in
            switch idx {
            case 0:
                cam.switchToUltraWide { _ in done() }
            case 1:
                cam.switchToWideAngle(targetZoom: 1.0) { done() }
            case 2:
                cam.switchToWideAngle(targetZoom: 2.0) { done() }
            default: done()
            }
        }
        
        if isSwitchingLens {
            switchCameraWithTransition(performZoom)
        } else {
            performZoom { }
        }
    }

    @objc private func flipTapped() {
        guard !isSwitchingCamera, let session = borrowedCameraView?.getCameraSessionInfo()?.session else { return }
        
        UIView.animate(withDuration: 0.15) {
            self.flipButton.transform = CGAffineTransform(rotationAngle: .pi * 0.8)
        } completion: { _ in
            UIView.animate(withDuration: 0.15) { self.flipButton.transform = .identity }
        }
        
        let front = isFrontCamera
        
        flipCameraWithTransition { done in
            Self.sessionQueue.async { [weak self] in
                guard let self else { DispatchQueue.main.async { done() }; return }
                session.beginConfiguration()
                session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
                              .filter { $0.device.hasMediaType(.video) }
                              .forEach { session.removeInput($0) }
                let pos: AVCaptureDevice.Position = front ? .back : .front
                guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: pos)
                             ?? AVCaptureDevice.default(for: .video),
                      let inp = try? AVCaptureDeviceInput(device: dev),
                      session.canAddInput(inp) else {
                    session.commitConfiguration()
                    DispatchQueue.main.async { done() }
                    return
                }
                session.addInput(inp)
                session.commitConfiguration()
                DispatchQueue.main.async { 
                    self.isFrontCamera.toggle()
                    done()
                }
            }
        }
    }

    @objc private func shutterDown() {
        UIView.animate(withDuration: 0.08) {
            self.shutterRing.transform = CGAffineTransform(scaleX: 0.87, y: 0.87)
            self.shutterRing.alpha = 0.5
        }
    }

    @objc private func shutterUp() {
        UIView.animate(withDuration: 0.1) {
            self.shutterRing.transform = .identity
            self.shutterRing.alpha = 1.0
        }
    }

    @objc private func shutterTapped() {
        guard !isCapturing else { return }
        isCapturing = true
        let flash = UIView(frame: bounds)
        flash.backgroundColor = .black; flash.alpha = 0
        addSubview(flash)
        UIView.animate(withDuration: 0.04, animations: { flash.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.16) { flash.alpha = 0 } completion: { _ in
                flash.removeFromSuperview(); self.isCapturing = false
            }
        }
        borrowedCameraView?.capturePhoto(flashMode: self.flashMode)
    }

    private func updateFlashIcon() {
        let cfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        let name: String
        switch flashMode {
        case .on:   name = "bolt.fill"
        case .off:  name = "bolt.slash.fill"
        default:    name = "bolt.badge.automatic.fill"
        }
        flashButton.setImage(UIImage(systemName: name, withConfiguration: cfg), for: .normal)
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
