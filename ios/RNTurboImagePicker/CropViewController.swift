import UIKit

// MARK: - Adaptive Color Palette (Dark / Light mode)

extension UIColor {
    /// 전체 화면 배경: 다크=블랙, 라이트=흰색
    static var cropBackground: UIColor {
        UIColor { t in t.userInterfaceStyle == .dark ? .black : .white }
    }
    /// 하단 바: 다크=거의 검정, 라이트=거의 흰색
    static var cropBarBackground: UIColor {
        UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 0.08, alpha: 0.98)
                : UIColor(white: 0.97, alpha: 0.98)
        }
    }
    /// 선택된 비율 버튼 배경
    static var cropRatioBtnSelected: UIColor {
        UIColor { t in t.userInterfaceStyle == .dark ? .white : .black }
    }
    /// 선택된 비율 버튼 텍스트
    static var cropRatioBtnSelectedText: UIColor {
        UIColor { t in t.userInterfaceStyle == .dark ? .black : .white }
    }
    /// 비선택 비율 버튼 배경
    static var cropRatioBtnNormal: UIColor {
        UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 0.25, alpha: 1)
                : UIColor(white: 0.85, alpha: 1)
        }
    }
    /// 비선택 비율 버튼 텍스트 / 아이콘
    static var cropRatioBtnNormalText: UIColor {
        UIColor { t in t.userInterfaceStyle == .dark ? .white : .black }
    }
    /// 크롭 오버레이 어두운 마스크
    static var cropMask: UIColor {
        UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor.black.withAlphaComponent(0.55)
                : UIColor.black.withAlphaComponent(0.4)
        }
    }
    /// 크롭 테두리 및 핸들
    static var cropBorder: UIColor {
        UIColor { t in t.userInterfaceStyle == .dark ? .white : UIColor(white: 0.9, alpha: 1) }
    }
    /// 그리드 라인
    static var cropGridLine: UIColor {
        UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.8)
                : UIColor.white.withAlphaComponent(0.7)
        }
    }
    /// 비율 스크롤 배경
    static var cropRatioBackground: UIColor {
        UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 0.10, alpha: 1)
                : UIColor(white: 0.93, alpha: 1)
        }
    }
}

// MARK: - CropViewController

final class CropViewController: UIViewController {

    // MARK: - Aspect Ratio

    enum AspectRatio: CaseIterable {
        case freeform, square, p34, l43, p916, l169

        var title: String {
            switch self {
            case .freeform: return Localizer.getString(key: "crop_freeform", languageCode: CropViewController.currentLanguageCode)
            case .square:   return "1:1"
            case .p34:      return "3:4"
            case .l43:      return "4:3"
            case .p916:     return "9:16"
            case .l169:     return "16:9"
            }
        }

        /// width / height. nil = freeform
        var value: CGFloat? {
            switch self {
            case .freeform: return nil
            case .square:   return 1
            case .p34:      return 3.0 / 4.0
            case .l43:      return 4.0 / 3.0
            case .p916:     return 9.0 / 16.0
            case .l169:     return 16.0 / 9.0
            }
        }
    }

    private enum Handle { case tl, tr, bl, br }

    // MARK: - Public API

    var onCropComplete: ((UIImage) -> Void)?
    var onCancel: (() -> Void)?

    // MARK: - Private State

    private let sourceImage: UIImage
    private var workingImage: UIImage      // after flip / rotate transforms
    private var currentRatio: AspectRatio = .freeform
    private var flipH = false
    private var rotations = 0             // 0-3, each step = +90° clockwise

    /// cropRect in `view` coordinate space
    private var cropRect: CGRect = .zero
    /// Actual image display rect in `view` coordinate space (aspectFit result)
    private var imageDisplayRect: CGRect = .zero
    private var didInitCropRect = false

    private var activeHandle: Handle?
    private var panStart: CGPoint = .zero
    private var cropAtPanStart: CGRect = .zero
    private let minCrop: CGFloat = 44

    // MARK: - UI

    private lazy var imageScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.delegate = self
        sv.minimumZoomScale = 1.0
        sv.maximumZoomScale = 5.0
        sv.showsVerticalScrollIndicator = false
        sv.showsHorizontalScrollIndicator = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 11.0, *) {
            sv.contentInsetAdjustmentBehavior = .never
        }
        return sv
    }()

    public static var currentLanguageCode: String = "en"

    private lazy var imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleToFill // Will be exactly sized to aspect fit size
        iv.clipsToBounds = true
        // Intentionally NOT translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private lazy var overlayView: CropOverlayView = {
        let v = CropOverlayView()
        v.backgroundColor = .clear
        v.isOpaque = false
        v.isUserInteractionEnabled = false
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var ratioScroll: UIScrollView = {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.alwaysBounceHorizontal = true
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var ratioStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 8
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var bottomBar: UIView = {
        let v = UIView()
        v.backgroundColor = .cropBarBackground
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var ratioBackgroundBar: UIView = {
        let v = UIView()
        v.backgroundColor = .cropRatioBackground
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var cancelBtn   = makeSysBtn("xmark",    action: #selector(cancelTapped))
    private lazy var flipBtn     = makeCropIconBtn(baseName: "ic_crop_reflect",
                                                   insets: UIEdgeInsets(top: 15, left: 12, bottom: 9, right: 12),
                                                   action: #selector(flipTapped))
    private lazy var rotateBtn   = makeCropIconBtn(baseName: "ic_crop_rotate",
                                                   insets: UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12),
                                                   action: #selector(rotateTapped))
    private lazy var confirmBtn  = makeSysBtn("checkmark", action: #selector(confirmTapped))

    // MARK: - Init

    init(image: UIImage) {
        self.sourceImage  = image
        self.workingImage = image
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .cropBackground
        setupLayout()
        setupGestures()
        buildRatioButtons()
        imageView.image = workingImage
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        // 비율 버튼 스타일 갱신
        for (i, v) in ratioStack.arrangedSubviews.enumerated() {
            guard let btn = v as? UIButton else { continue }
            applyRatioStyle(btn, selected: AspectRatio.allCases[i] == currentRatio)
        }
        // SF Symbol 아이콘 tint 갱신
        for btn in [cancelBtn, confirmBtn] {
            btn.tintColor = .cropRatioBtnNormalText
        }
        // 커스텀 아이콘 다크/라이트 재로드
        if let img = cropIconImage(baseName: "ic_crop_reflect") { flipBtn.setImage(img, for: .normal) }
        if let img = cropIconImage(baseName: "ic_crop_rotate")  { rotateBtn.setImage(img, for: .normal) }
        // 오버레이 색상 갱신 (CAShapeLayer 기반)
        overlayView.updateColors()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !didInitCropRect {
            recalcImageDisplayRect()
            cropRect = imageDisplayRect
            didInitCropRect = true
            refreshOverlay()
        }
    }

    // MARK: - Layout

    private func setupLayout() {
        view.addSubview(imageScrollView)
        imageScrollView.addSubview(imageView)
        view.addSubview(overlayView)
        view.addSubview(ratioBackgroundBar)
        view.addSubview(ratioScroll)
        view.addSubview(bottomBar)

        ratioScroll.addSubview(ratioStack)

        let leftSpacer = UIView()
        let rightSpacer = UIView()
        leftSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rightSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let toolStack = UIStackView(arrangedSubviews: [cancelBtn, leftSpacer, flipBtn, rotateBtn, rightSpacer, confirmBtn])
        toolStack.axis = .horizontal
        toolStack.alignment = .center
        toolStack.distribution = .fill
        
        // 아이콘을 조금 모으되, 약간의 여백(5pt)을 주어 자연스럽게 보이도록 합니다.
        toolStack.setCustomSpacing(5, after: flipBtn)
        toolStack.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(toolStack)

        NSLayoutConstraint.activate([
            // Spacer equality
            leftSpacer.widthAnchor.constraint(equalTo: rightSpacer.widthAnchor),
            
            // Bottom bar
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 88),

            toolStack.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            toolStack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 16),
            toolStack.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -16),
            toolStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            cancelBtn.widthAnchor.constraint(equalToConstant: 44),
            cancelBtn.heightAnchor.constraint(equalToConstant: 44),
            confirmBtn.widthAnchor.constraint(equalToConstant: 44),
            confirmBtn.heightAnchor.constraint(equalToConstant: 44),

            // Ratio background bar (separator)
            ratioBackgroundBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ratioBackgroundBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ratioBackgroundBar.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
            ratioBackgroundBar.heightAnchor.constraint(equalToConstant: 44),

            // Ratio scroll
            ratioScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ratioScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ratioScroll.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
            ratioScroll.heightAnchor.constraint(equalToConstant: 44),

            ratioStack.leadingAnchor.constraint(equalTo: ratioScroll.leadingAnchor, constant: 16),
            ratioStack.trailingAnchor.constraint(equalTo: ratioScroll.trailingAnchor, constant: -16),
            ratioStack.topAnchor.constraint(equalTo: ratioScroll.topAnchor),
            ratioStack.bottomAnchor.constraint(equalTo: ratioScroll.bottomAnchor),
            ratioStack.heightAnchor.constraint(equalTo: ratioScroll.heightAnchor),

            // Image scroll view
            imageScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            imageScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageScrollView.bottomAnchor.constraint(equalTo: ratioScroll.topAnchor),

            // Overlay exactly matches image scroll view area
            overlayView.topAnchor.constraint(equalTo: imageScrollView.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: imageScrollView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: imageScrollView.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: imageScrollView.bottomAnchor),
        ])
    }

    // MARK: - Button Factories

    /// SF Symbol 버튼 (cancel / confirm용)
    private func makeSysBtn(_ sysName: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        btn.setImage(UIImage(systemName: sysName, withConfiguration: cfg), for: .normal)
        btn.tintColor = .cropRatioBtnNormalText
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: 44).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 44).isActive = true
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    /// ToolbarIcons 폴더의 커스텀 이미지 버튼 (flip / rotate용)
    private func makeCropIconBtn(baseName: String,
                                 insets: UIEdgeInsets = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14),
                                 action: Selector) -> UIButton {
        let btn = UIButton(type: .custom)
        if let img = cropIconImage(baseName: baseName) {
            btn.setImage(img, for: .normal)
        } else {
            // fallback SF Symbol
            let sysFallback = baseName.contains("reflect") ? "arrow.left.and.right.righttriangle.left.righttriangle.right.fill" : "rotate.right.fill"
            let cfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
            btn.setImage(UIImage(systemName: sysFallback, withConfiguration: cfg), for: .normal)
            btn.tintColor = .cropRatioBtnNormalText
        }
        btn.imageView?.contentMode = .scaleAspectFit
        btn.imageEdgeInsets = insets
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: 48).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 48).isActive = true
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    /// 다크/라이트 모드에 맞는 ToolbarIcons 이미지 로드
    private func cropIconImage(baseName: String) -> UIImage? {
        let isDark = traitCollection.userInterfaceStyle == .dark
        let fileName = baseName + (isDark ? "~dark" : "~light")
        
        // 1) RNTurboImagePickerAssets 번들 내에서 조회
        let bundle = Bundle(for: CropViewController.self)
        let resourceBundle = bundle.url(forResource: "RNTurboImagePickerAssets", withExtension: "bundle")
            .flatMap { Bundle(url: $0) } ?? bundle
            
        if let path = resourceBundle.path(forResource: fileName, ofType: "webp") ??
                      resourceBundle.path(forResource: fileName, ofType: "webp", inDirectory: "ToolbarIcons"),
           let img = UIImage(contentsOfFile: path) {
            return img
        }

        // 2) 기존 메인 번들 직접 조회 (하위 호환성)
        if let path = Bundle.main.path(forResource: fileName, ofType: "webp",
                                       inDirectory: "ToolbarIcons"),
           let img = UIImage(contentsOfFile: path) {
            return img
        }
        return nil
    }


    // MARK: - Ratio Buttons

    private func buildRatioButtons() {
        for (i, ratio) in AspectRatio.allCases.enumerated() {
            let btn = UIButton(type: .custom)
            btn.setTitle(ratio.title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            btn.layer.cornerRadius = 14
            btn.clipsToBounds = true
            btn.tag = i
            btn.addTarget(self, action: #selector(ratioTapped(_:)), for: .touchUpInside)
            applyRatioStyle(btn, selected: ratio == currentRatio)
            ratioStack.addArrangedSubview(btn)
        }
    }

    private func applyRatioStyle(_ btn: UIButton, selected: Bool) {
        if selected {
            btn.backgroundColor = .cropRatioBtnSelected
            btn.setTitleColor(.cropRatioBtnSelectedText, for: .normal)
        } else {
            btn.backgroundColor = .cropRatioBtnNormal
            btn.setTitleColor(.cropRatioBtnNormalText, for: .normal)
        }
    }

    private func resetToFreeform() {
        currentRatio = .freeform
        for v in ratioStack.arrangedSubviews {
            guard let btn = v as? UIButton else { continue }
            applyRatioStyle(btn, selected: AspectRatio.allCases[btn.tag] == .freeform)
        }
    }

    // MARK: - Gestures

    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
        imageScrollView.panGestureRecognizer.require(toFail: pan)
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        let pt = gr.location(in: view)

        switch gr.state {
        case .began:
            activeHandle = nearestHandle(to: pt)
            panStart = pt
            cropAtPanStart = cropRect
            if activeHandle != nil || cropAtPanStart.contains(panStart) {
                overlayView.setGridAlpha(1.0, animated: true)
            }

        case .changed:
            let dx = pt.x - panStart.x
            let dy = pt.y - panStart.y
            if let h = activeHandle {
                applyCropResize(handle: h, dx: dx, dy: dy)
                refreshOverlay()
            } else if cropAtPanStart.contains(panStart) {
                moveCropRect(dx: dx, dy: dy)
                refreshOverlay()
            }

        case .ended, .cancelled:
            activeHandle = nil
            overlayView.setGridAlpha(0.0, animated: true)

        default: break
        }
    }

    private func nearestHandle(to pt: CGPoint) -> Handle? {
        let handles: [(Handle, CGPoint)] = [
            (.tl, CGPoint(x: cropRect.minX, y: cropRect.minY)),
            (.tr, CGPoint(x: cropRect.maxX, y: cropRect.minY)),
            (.bl, CGPoint(x: cropRect.minX, y: cropRect.maxY)),
            (.br, CGPoint(x: cropRect.maxX, y: cropRect.maxY)),
        ]
        let hitRadius: CGFloat = 44
        for (handle, center) in handles {
            if pt.distance(to: center) <= hitRadius { return handle }
        }
        return nil
    }

    private var visibleImageRect: CGRect {
        let intersection = imageDisplayRect.intersection(imageScrollView.frame)
        return intersection.isNull ? imageDisplayRect : intersection
    }

    private func moveCropRect(dx: CGFloat, dy: CGFloat) {
        let bounds = visibleImageRect
        var r = cropAtPanStart.offsetBy(dx: dx, dy: dy)
        let maxX = max(bounds.minX, bounds.maxX - r.width)
        let maxY = max(bounds.minY, bounds.maxY - r.height)
        r.origin.x = r.origin.x.clamped(to: bounds.minX ... maxX)
        r.origin.y = r.origin.y.clamped(to: bounds.minY ... maxY)
        cropRect = r
    }

    private func applyCropResize(handle: Handle, dx: CGFloat, dy: CGFloat) {
        var r = cropAtPanStart
        let bounds = visibleImageRect

        switch handle {
        case .tl:
            let newX = (r.origin.x + dx).clamped(to: bounds.minX ... r.maxX - minCrop)
            let newY = (r.origin.y + dy).clamped(to: bounds.minY ... r.maxY - minCrop)
            r.size.width  += r.origin.x - newX
            r.size.height += r.origin.y - newY
            r.origin.x = newX;  r.origin.y = newY

        case .tr:
            let newY = (r.origin.y + dy).clamped(to: bounds.minY ... r.maxY - minCrop)
            r.size.height += r.origin.y - newY
            r.origin.y = newY
            r.size.width = (r.size.width + dx).clamped(to: minCrop ... max(minCrop, bounds.maxX - r.origin.x))

        case .bl:
            let newX = (r.origin.x + dx).clamped(to: bounds.minX ... r.maxX - minCrop)
            r.size.width  += r.origin.x - newX
            r.origin.x = newX
            r.size.height = (r.size.height + dy).clamped(to: minCrop ... max(minCrop, bounds.maxY - r.origin.y))

        case .br:
            r.size.width  = (r.size.width  + dx).clamped(to: minCrop ... max(minCrop, bounds.maxX - r.origin.x))
            r.size.height = (r.size.height + dy).clamped(to: minCrop ... max(minCrop, bounds.maxY - r.origin.y))
        }

        // Apply aspect ratio
        if let ratio = currentRatio.value {
            switch handle {
            case .tl:
                r.size.height = r.size.width / ratio
                r.origin.y    = cropAtPanStart.maxY - r.size.height
            case .tr:
                r.size.height = r.size.width / ratio
                r.origin.y    = cropAtPanStart.maxY - r.size.height
            case .bl:
                r.size.height = r.size.width / ratio
            case .br:
                r.size.height = r.size.width / ratio
            }
            // Clamp again after ratio adjustment
            if r.maxY > imageDisplayRect.maxY {
                r.size.height = imageDisplayRect.maxY - r.origin.y
                r.size.width  = r.size.height * ratio
            }
            if r.origin.y < imageDisplayRect.minY {
                r.origin.y    = imageDisplayRect.minY
                r.size.height = cropAtPanStart.maxY - r.origin.y
                r.size.width  = r.size.height * ratio
            }
        }

        cropRect = r
    }

    // MARK: - Overlay Refresh

    private func recalcImageDisplayRect() {
        guard let img = imageView.image else { return }
        let svBounds = imageScrollView.bounds
        guard svBounds.width > 0, svBounds.height > 0 else { return }

        let imgSize = img.size
        let scale = min(svBounds.width / imgSize.width, svBounds.height / imgSize.height)
        let scaledW = imgSize.width  * scale
        let scaledH = imgSize.height * scale

        imageScrollView.zoomScale = 1.0
        
        imageView.transform = .identity
        imageView.frame = CGRect(x: 0, y: 0, width: scaledW, height: scaledH)
        imageScrollView.contentSize = CGSize(width: scaledW, height: scaledH)
        
        // Center it
        let offsetX = max((svBounds.width - scaledW) * 0.5, 0)
        let offsetY = max((svBounds.height - scaledH) * 0.5, 0)
        imageView.center = CGPoint(x: scaledW * 0.5 + offsetX,
                                   y: scaledH * 0.5 + offsetY)
        
        updateImageDisplayRectFromView()
    }

    private func updateImageDisplayRectFromView() {
        imageDisplayRect = imageScrollView.convert(imageView.frame, to: view)
        clampCropRectToImage()
    }

    private func clampCropRectToImage() {
        guard imageDisplayRect.width > 0, imageDisplayRect.height > 0 else { return }
        let bounds = visibleImageRect
        var r = cropRect
        
        // 1. Ensure size fits within image bounds
        if r.width > bounds.width || r.height > bounds.height {
            if let ratio = currentRatio.value {
                let scaleW = bounds.width / r.width
                let scaleH = bounds.height / r.height
                let scale = min(scaleW, scaleH)
                if scale < 1.0 {
                    r.size.width *= scale
                    r.size.height *= scale
                }
            } else {
                r.size.width = min(r.width, bounds.width)
                r.size.height = min(r.height, bounds.height)
            }
        }
        
        // 2. Clamp origin so it doesn't exceed image bounds
        r.origin.x = max(bounds.minX, min(r.origin.x, bounds.maxX - r.width))
        r.origin.y = max(bounds.minY, min(r.origin.y, bounds.maxY - r.height))
        
        if r != cropRect {
            cropRect = r
            refreshOverlay()
        }
    }

    private func refreshOverlay() {
        // overlayView is aligned to imageScrollView; convert cropRect to overlayView space
        let local = overlayView.convert(cropRect, from: view)
        overlayView.cropRect = local
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        onCancel?()
        dismiss(animated: true)
    }

    @objc private func flipTapped() {
        flipH.toggle()
        applyTransforms(animated: true, isFlip: true)
    }

    @objc private func rotateTapped() {
        resetToFreeform()
        if flipH {
            rotations = (rotations + 3) % 4
        } else {
            rotations = (rotations + 1) % 4
        }
        applyTransforms(animated: true, isFlip: false)
    }

    @objc private func confirmTapped() {
        guard let cropped = performCrop() else { return }
        onCropComplete?(cropped)
        dismiss(animated: true)
    }

    @objc private func ratioTapped(_ sender: UIButton) {
        currentRatio = AspectRatio.allCases[sender.tag]

        // Update button styles
        for v in ratioStack.arrangedSubviews {
            guard let btn = v as? UIButton else { continue }
            applyRatioStyle(btn, selected: btn.tag == sender.tag)
        }

        // Re-apply crop rect to satisfy new ratio
        if let ratio = currentRatio.value {
            var r = cropRect
            r.size.height = r.size.width / ratio
            if r.maxY > imageDisplayRect.maxY {
                r.size.height = imageDisplayRect.maxY - r.origin.y
                r.size.width  = r.size.height * ratio
            }
            cropRect = r
        }
        refreshOverlay()
    }

    // MARK: - Transform Helpers

    private func applyTransforms(animated: Bool = false, isFlip: Bool = false) {
        let oldImg = imageView.image
        var img = sourceImage

        // Rotate (single operation, no intermediate images)
        img = img.rotated(steps: rotations)
        // Flip
        if flipH {
            img = img.flippedHorizontally()
        }

        workingImage = img

        if animated {
            if isFlip {
                UIView.transition(with: imageView, duration: 0.3, options: .transitionFlipFromRight, animations: {
                    self.imageView.image = img
                }, completion: nil)
                
                UIView.animate(withDuration: 0.3) {
                    self.recalcImageDisplayRect()
                    self.cropRect = self.imageDisplayRect
                    self.refreshOverlay()
                    self.view.layoutIfNeeded()
                }
            } else {
                // Smooth Rotation Animation
                let oldDisplayRect = self.imageDisplayRect
                
                // 1. Calculate new target rect
                self.imageView.image = img
                self.recalcImageDisplayRect()
                let targetRect = self.imageDisplayRect
                
                // 2. Create temp view for rotation using old image
                let tempIv = UIImageView(image: oldImg)
                tempIv.frame = oldDisplayRect
                tempIv.contentMode = .scaleToFill
                self.view.insertSubview(tempIv, aboveSubview: self.imageView)
                
                self.imageScrollView.isHidden = true
                
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: {
                    // Animate to new bounds and rotation
                    tempIv.bounds = CGRect(origin: .zero, size: CGSize(width: targetRect.height, height: targetRect.width))
                    tempIv.center = CGPoint(x: targetRect.midX, y: targetRect.midY)
                    tempIv.transform = CGAffineTransform(rotationAngle: .pi / 2)
                    
                    self.cropRect = targetRect
                    self.refreshOverlay()
                }, completion: { _ in
                    self.imageScrollView.isHidden = false
                    tempIv.removeFromSuperview()
                    
                    // Final sanity check
                    self.recalcImageDisplayRect()
                    self.cropRect = targetRect
                    self.refreshOverlay()
                })
            }
        } else {
            imageView.image = img
            recalcImageDisplayRect()
            cropRect = imageDisplayRect
            refreshOverlay()
            view.setNeedsLayout()
        }
    }

    // MARK: - Crop Execution

    private func performCrop() -> UIImage? {
        guard let img = imageView.image else { return nil }
        guard let cgImage = img.cgImage else { return nil }
        guard imageDisplayRect.width > 0, imageDisplayRect.height > 0 else { return nil }

        // Convert cropRect from view space to imageView space
        let cropInImageView = view.convert(cropRect, to: imageView)

        // Use cgImage pixel dimensions (not UIImage logical size).
        // UIGraphicsImageRenderer applies the screen scale (e.g. 3× on Pro devices),
        // so after rotation: img.size is in logical points but cgImage.width is 3× larger.
        // Using img.size here would produce a crop 1/scale as large as expected.
        let scaleX = CGFloat(cgImage.width)  / imageView.bounds.width
        let scaleY = CGFloat(cgImage.height) / imageView.bounds.height

        let pixelRect = CGRect(
            x: cropInImageView.origin.x * scaleX,
            y: cropInImageView.origin.y * scaleY,
            width:  cropInImageView.width  * scaleX,
            height: cropInImageView.height * scaleY
        ).integral

        // Clamp to valid pixel bounds to avoid cropping failure
        let imageBounds = CGRect(origin: .zero, size: CGSize(width: cgImage.width, height: cgImage.height))
        let clampedRect = pixelRect.intersection(imageBounds)
        guard clampedRect.width > 0, clampedRect.height > 0 else { return nil }

        guard let cropped = cgImage.cropping(to: clampedRect) else { return nil }

        return UIImage(cgImage: cropped, scale: img.scale, orientation: img.imageOrientation)
    }
}

// MARK: - UIScrollViewDelegate & UIGestureRecognizerDelegate

extension CropViewController: UIScrollViewDelegate, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer is UIPanGestureRecognizer && gestureRecognizer.view == self.view {
            let pt = touch.location(in: view)
            if nearestHandle(to: pt) != nil { return true }
            if cropRect.contains(pt) { return true }
            return false
        }
        return true
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
        let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
        imageView.center = CGPoint(x: scrollView.contentSize.width * 0.5 + offsetX,
                                   y: scrollView.contentSize.height * 0.5 + offsetY)
        updateImageDisplayRectFromView()
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateImageDisplayRectFromView()
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if scrollView == imageScrollView {
            overlayView.setGridAlpha(1.0, animated: true)
        }
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if scrollView == imageScrollView && !decelerate {
            overlayView.setGridAlpha(0.0, animated: true)
        }
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if scrollView == imageScrollView {
            overlayView.setGridAlpha(0.0, animated: true)
        }
    }
    
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        if scrollView == imageScrollView {
            overlayView.setGridAlpha(1.0, animated: true)
        }
    }
    
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        if scrollView == imageScrollView {
            overlayView.setGridAlpha(0.0, animated: true)
        }
    }
}

// MARK: - CropOverlayView

final class CropGridView: UIView {
    var gridLines = 2
    
    private let gridLayer = CAShapeLayer()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        gridLayer.fillColor = nil
        gridLayer.strokeColor = UIColor.cropGridLine.cgColor
        gridLayer.lineWidth = 1.0
        layer.addSublayer(gridLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateGridPath()
    }
    
    func updateGridPath() {
        let path = CGMutablePath()
        for i in 1 ... gridLines {
            let x = bounds.minX + bounds.width  * CGFloat(i) / CGFloat(gridLines + 1)
            let y = bounds.minY + bounds.height * CGFloat(i) / CGFloat(gridLines + 1)
            path.move(to:    CGPoint(x: x, y: bounds.minY))
            path.addLine(to: CGPoint(x: x, y: bounds.maxY))
            path.move(to:    CGPoint(x: bounds.minX, y: y))
            path.addLine(to: CGPoint(x: bounds.maxX, y: y))
        }
        gridLayer.path = path
    }
    
    func updateColors() {
        gridLayer.strokeColor = UIColor.cropGridLine.cgColor
    }
}

final class CropOverlayView: UIView {

    var cropRect: CGRect = .zero {
        didSet {
            gridView.frame = cropRect
            updateLayers()
        }
    }

    private let cornerLen: CGFloat = 22
    private let cornerW:   CGFloat = 3
    private let gridView = CropGridView()
    
    // CAShapeLayer-based rendering (GPU accelerated, no draw(_:) needed)
    private let maskLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let cornerLayer = CAShapeLayer()
    private let dimLayer = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        
        // Dim overlay with mask cutout
        dimLayer.backgroundColor = UIColor.cropMask.cgColor
        maskLayer.fillRule = .evenOdd
        dimLayer.mask = maskLayer
        layer.addSublayer(dimLayer)
        
        // Border
        borderLayer.fillColor = nil
        borderLayer.strokeColor = UIColor.cropBorder.cgColor
        borderLayer.lineWidth = 1
        layer.addSublayer(borderLayer)
        
        // Corner handles
        cornerLayer.fillColor = nil
        cornerLayer.strokeColor = UIColor.cropBorder.cgColor
        cornerLayer.lineWidth = cornerW
        cornerLayer.lineCap = .square
        layer.addSublayer(cornerLayer)
        
        gridView.alpha = 0.0
        addSubview(gridView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dimLayer.frame = bounds
        CATransaction.commit()
        updateLayers()
    }

    func setGridAlpha(_ alpha: CGFloat, animated: Bool) {
        if animated {
            UIView.animate(withDuration: 0.2) {
                self.gridView.alpha = alpha
            }
        } else {
            self.gridView.alpha = alpha
        }
    }
    
    func updateColors() {
        dimLayer.backgroundColor = UIColor.cropMask.cgColor
        borderLayer.strokeColor = UIColor.cropBorder.cgColor
        cornerLayer.strokeColor = UIColor.cropBorder.cgColor
        gridView.updateColors()
    }
    
    private func updateLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        // Mask: full rect with hole
        let fullPath = CGMutablePath()
        fullPath.addRect(bounds)
        fullPath.addRect(cropRect)
        maskLayer.path = fullPath
        
        // Border
        borderLayer.path = CGPath(rect: cropRect, transform: nil)
        
        // Corner handles (L-shaped)
        let cPath = CGMutablePath()
        let halfW = cornerW / 2.0
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: cropRect.minX, y: cropRect.minY),  1,  1),
            (CGPoint(x: cropRect.maxX, y: cropRect.minY), -1,  1),
            (CGPoint(x: cropRect.minX, y: cropRect.maxY),  1, -1),
            (CGPoint(x: cropRect.maxX, y: cropRect.maxY), -1, -1),
        ]
        for (origin, sx, sy) in corners {
            let cx = origin.x + sx * halfW
            let cy = origin.y + sy * halfW
            cPath.move(to: CGPoint(x: cx + sx * (cornerLen - cornerW), y: cy))
            cPath.addLine(to: CGPoint(x: cx, y: cy))
            cPath.addLine(to: CGPoint(x: cx, y: cy + sy * (cornerLen - cornerW)))
        }
        cornerLayer.path = cPath
        
        CATransaction.commit()
    }
}

// MARK: - UIImage Extensions

private extension UIImage {
    /// Rotate image by the given number of 90° clockwise steps (0-3).
    /// Uses UIGraphicsImageRenderer for automatic memory management.
    func rotated(steps: Int) -> UIImage {
        let normalizedSteps = ((steps % 4) + 4) % 4
        guard normalizedSteps != 0 else { return self }
        
        let isOddStep = (normalizedSteps % 2 != 0)
        let newSize = isOddStep ? CGSize(width: size.height, height: size.width) : size
        let angle = CGFloat(normalizedSteps) * (.pi / 2)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext
            cgCtx.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            cgCtx.rotate(by: angle)
            draw(in: CGRect(x: -size.width / 2, y: -size.height / 2,
                            width: size.width, height: size.height))
        }
    }
    
    /// Single 90° CW rotation (convenience wrapper).
    func rotated90CW() -> UIImage {
        return rotated(steps: 1)
    }

    func flippedHorizontally() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext
            cgCtx.translateBy(x: size.width, y: 0)
            cgCtx.scaleBy(x: -1, y: 1)
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Helpers

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
