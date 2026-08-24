import UIKit

final class ProfileCropViewController: UIViewController {

    var onCropComplete: ((UIImage) -> Void)?
    var onCancel: (() -> Void)?

    var maxWidth:  Int = 0
    var maxHeight: Int = 0
    var themeColor: UIColor?
    public var languageCode: String = "en"
    lazy var cancelTitle = Localizer.getString(key: "cancel", languageCode: languageCode)
    lazy var okTitle     = Localizer.getString(key: "confirm", languageCode: languageCode)

    private let sourceImage: UIImage
    private var workingImage: UIImage
    private var isRotating = false
    private var didLayout  = false

    // MARK: - Sub-views

    private lazy var cropContainer: UIView = {
        let v = UIView()
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.delegate = self
        sv.minimumZoomScale = 1.0
        sv.maximumZoomScale = 6.0
        sv.showsVerticalScrollIndicator   = false
        sv.showsHorizontalScrollIndicator = false
        sv.alwaysBounceVertical = true
        sv.bouncesZoom = true
        if #available(iOS 11.0, *) { sv.contentInsetAdjustmentBehavior = .never }
        return sv
    }()

    internal let imageView = UIImageView()
    private lazy var circleOverlay = CircleDashedOverlayView()

    private lazy var bottomBar: UIView = {
        let v = UIView()
        v.backgroundColor = .cropBarBackground
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var cancelBtn: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle(cancelTitle, for: .normal)
        b.setTitleColor(.cropRatioBtnNormalText, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 17)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        return b
    }()

    private lazy var rotateBtn: UIButton = {
        let b = UIButton(type: .system)
        let bundle = Bundle(for: ProfileCropViewController.self)
        let resourceBundle: Bundle
        if let url = bundle.url(forResource: "RNTurboImagePickerAssets", withExtension: "bundle"),
           let bUrl = Bundle(url: url) {
            resourceBundle = bUrl
        } else {
            resourceBundle = bundle
        }
        let img = UIImage(named: "rotate_icon", in: resourceBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate)
        b.setImage(img, for: .normal)
        b.tintColor = .cropRatioBtnNormalText
        b.contentHorizontalAlignment = .fill
        b.contentVerticalAlignment = .fill
        b.imageView?.contentMode = .scaleAspectFit
        b.imageEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(rotateTapped), for: .touchUpInside)
        return b
    }()

    private lazy var okBtn: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle(okTitle, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        b.backgroundColor  = UIColor(red: 0.93, green: 0.29, blue: 0.15, alpha: 1)
        b.layer.cornerRadius = 16
        b.contentEdgeInsets  = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(okTapped), for: .touchUpInside)
        return b
    }()

    // MARK: - Interactive Dismiss State

    private var isDismissingViaScrollView = false
    private var initialPanTranslationY: CGFloat = 0
    private var initialPanTranslationX: CGFloat = 0

    // MARK: - Init

    init(image: UIImage) {
        self.sourceImage  = image
        self.workingImage = image
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .cropBackground
        imageView.image = workingImage
        imageView.contentMode = .scaleToFill
        if let tc = themeColor { okBtn.backgroundColor = tc }
        setupLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isRotating else { return }
        scrollView.frame    = cropContainer.bounds
        circleOverlay.frame = cropContainer.bounds
        circleOverlay.setNeedsDisplay()
        if !didLayout {
            didLayout = true
            fitImage()
        }
    }

    // MARK: - Layout

    private func setupLayout() {
        scrollView.addSubview(imageView)
        cropContainer.addSubview(scrollView)
        cropContainer.addSubview(circleOverlay)
        circleOverlay.isUserInteractionEnabled = false

        view.addSubview(cropContainer)
        view.addSubview(bottomBar)
        bottomBar.addSubview(cancelBtn)
        bottomBar.addSubview(rotateBtn)
        bottomBar.addSubview(okBtn)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 88),

            cancelBtn.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 24),
            cancelBtn.centerYAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 32),

            rotateBtn.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            rotateBtn.centerYAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 32),
            rotateBtn.widthAnchor.constraint(equalToConstant: 44),
            rotateBtn.heightAnchor.constraint(equalToConstant: 44),

            okBtn.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -20),
            okBtn.centerYAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 32),
            okBtn.heightAnchor.constraint(equalToConstant: 32),

            // cropContainer: full screen width, extends under status bar
            cropContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cropContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cropContainer.topAnchor.constraint(equalTo: view.topAnchor),
            cropContainer.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
        ])
    }

    // MARK: - Image Fit

    private var circleSide: CGFloat {
        min(cropContainer.bounds.width, cropContainer.bounds.height)
    }

    private func fitImage() {
        let containerW = cropContainer.bounds.width
        let containerH = cropContainer.bounds.height
        let side = circleSide
        guard side > 0, workingImage.size.width > 0 else { return }

        let img   = workingImage.size
        let scale = max(side / img.width, side / img.height)
        let fw    = img.width  * scale
        let fh    = img.height * scale

        imageView.frame        = CGRect(origin: .zero, size: CGSize(width: fw, height: fh))
        scrollView.contentSize = CGSize(width: fw, height: fh)

        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 6.0
        scrollView.zoomScale = 1.0

        // Set up insets to constrain panning exactly to the circle
        let baseInsetX = max((containerW - side) / 2, 0)
        let baseInsetY = max((containerH - side) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: baseInsetY, left: baseInsetX,
                                               bottom: baseInsetY, right: baseInsetX)

        let ox = (fw - containerW) / 2
        let oy = (fh - containerH) / 2
        scrollView.setContentOffset(CGPoint(x: ox, y: oy), animated: false)

    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        onCancel?()
        dismiss(animated: true)
    }

    private func resetViewTransform() {
        self.view.transform = .identity
        self.view.alpha = 1.0
        self.view.layer.cornerRadius = 0
    }

    private func cancelScrollViewDismiss() {
        UIView.animate(withDuration: 0.3, animations: {
            self.resetViewTransform()
        })
    }

    /// Bitmap rotation (like Android's bitmap-rotate approach).
    /// Rotate workingImage 90° CW, mathematically preserving the zoom and pan.
    @objc private func rotateTapped() {
        guard !isRotating else { return }
        isRotating = true
        rotateBtn.isEnabled = false

        let doRotate = {
            let src = self.workingImage
            var rotatedImage: UIImage?
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                rotatedImage = self.rotateBitmap90CW(src)
                group.leave()
            }

            // Temporarily disable clipping so zoomed image fills corners during rotation
            let oldClips = self.scrollView.clipsToBounds
            self.scrollView.clipsToBounds = false

            // Visual animation: physically rotate the scrollView
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: {
                self.scrollView.transform = CGAffineTransform(rotationAngle: .pi / 2)
            }) { _ in
                // Wait synchronously to prevent 1-frame flash
                group.wait()
                
                if let rotated = rotatedImage {
                    self.applyRotatedBitmap(rotated)
                }
                
                // Reset transform to identity and re-layout
                self.scrollView.transform = .identity
                self.scrollView.clipsToBounds = oldClips
                self.isRotating = false
                self.rotateBtn.isEnabled = true
                self.view.layoutIfNeeded()
            }
        }

        doRotate()
    }

    private func applyRotatedBitmap(_ rotated: UIImage) {
        let W = scrollView.bounds.width
        let H = scrollView.bounds.height
        let Z = scrollView.zoomScale

        let oldCw = scrollView.contentSize.width
        let oldCh = scrollView.contentSize.height
        let oldOx = scrollView.contentOffset.x
        let oldOy = scrollView.contentOffset.y

        // Calculate new offsets perfectly mapping the 90 CW rotation
        let newOx = -W/2 - H/2 - oldOy + oldCh
        let newOy = W/2 - H/2 + oldOx

        workingImage = rotated
        imageView.image = rotated

        let side = min(W, H)
        let scale = max(side / rotated.size.width, side / rotated.size.height)
        let newFw = rotated.size.width * scale
        let newFh = rotated.size.height * scale

        // Temporarily reset zoom to 1 to set base frame properly
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 6.0
        scrollView.zoomScale = 1.0

        imageView.frame = CGRect(origin: .zero, size: CGSize(width: newFw, height: newFh))
        scrollView.contentSize = CGSize(width: newFw, height: newFh)
        
        // Restore zoom scale
        scrollView.zoomScale = Z
        
        // Force inset calculation just in case zoomScale was already 1.0
        scrollViewDidZoom(scrollView)

        scrollView.setContentOffset(CGPoint(x: newOx, y: newOy), animated: false)
    }

    private func rotateBitmap90CW(_ src: UIImage) -> UIImage {
        let newSize = CGSize(width: src.size.height, height: src.size.width)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = src.scale
        return UIGraphicsImageRenderer(size: newSize, format: fmt).image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: newSize.width, y: 0)
            c.rotate(by: .pi / 2)
            src.draw(in: CGRect(origin: .zero, size: src.size))
        }
    }

    @objc private func okTapped() {
        let cropped = cropCurrentView()
        onCropComplete?(cropped)
    }

    // MARK: - Crop (circle-based, rotation-aware)

    private func cropCurrentView() -> UIImage {
        let containerW = cropContainer.bounds.width
        let containerH = cropContainer.bounds.height
        let side   = min(containerW, containerH)
        let cx     = containerW / 2
        let cy     = containerH / 2

        let zoom   = scrollView.zoomScale
        let rawOffset = scrollView.contentOffset
        // Use raw offset directly; contentInset is visual padding inside the scroll view coordinate system
        let offset = rawOffset

        let imgW = workingImage.size.width
        let imgH = workingImage.size.height
        let fitW = imageView.bounds.width
        let fitH = imageView.bounds.height
        let pxScaleX = imgW / fitW
        let pxScaleY = imgH / fitH

        // Circle top-left in content coordinates
        let circleOriginX = (offset.x / zoom) + (cx / zoom) - (side / zoom / 2)
        let circleOriginY = (offset.y / zoom) + (cy / zoom) - (side / zoom / 2)
        let circleW = side / zoom
        let circleH = side / zoom

        let visX = circleOriginX * pxScaleX
        let visY = circleOriginY * pxScaleY
        let visW = circleW * pxScaleX
        let visH = circleH * pxScaleY

        let cropRect = CGRect(x: visX, y: visY, width: visW, height: visH)
            .intersection(CGRect(origin: .zero, size: workingImage.size))

        // Force perfect square
        let targetSide = min(cropRect.width, cropRect.height)
        var outSize = CGSize(width: targetSide, height: targetSide)
        let mw = maxWidth  > 0 ? CGFloat(maxWidth)  : .greatestFiniteMagnitude
        let mh = maxHeight > 0 ? CGFloat(maxHeight) : .greatestFiniteMagnitude
        if outSize.width > mw || outSize.height > mh {
            let s = min(mw / outSize.width, mh / outSize.height)
            let scaledSide = (targetSide * s).rounded()
            outSize = CGSize(width: scaledSide, height: scaledSide)
        }

        // Render crop — no extra rotation needed, workingImage is already rotated
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = workingImage.scale
        let renderer = UIGraphicsImageRenderer(size: outSize, format: fmt)
        let result = renderer.image { _ in
            workingImage.draw(in: CGRect(
                x: -cropRect.origin.x * (outSize.width  / targetSide),
                y: -cropRect.origin.y * (outSize.height / targetSide),
                width:  imgW * (outSize.width  / targetSide),
                height: imgH * (outSize.height / targetSide)
            ))
        }
        return result
    }
}

// MARK: - UIScrollViewDelegate

extension ProfileCropViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let topBound = -scrollView.contentInset.top
        
        // 멀티 터치(줌) 시에는 무시
        if scrollView.panGestureRecognizer.numberOfTouches > 1 || scrollView.isZooming {
            if isDismissingViaScrollView {
                isDismissingViaScrollView = false
                cancelScrollViewDismiss()
            }
            return
        }
        
        if scrollView.isTracking {
            if scrollView.contentOffset.y < topBound {
                if !isDismissingViaScrollView {
                    isDismissingViaScrollView = true
                    let trans = scrollView.panGestureRecognizer.translation(in: view)
                    initialPanTranslationY = trans.y
                    initialPanTranslationX = trans.x
                }
            }
        }
        
        if isDismissingViaScrollView {
            let currentTranslation = scrollView.panGestureRecognizer.translation(in: view)
            let pullDown = currentTranslation.y - initialPanTranslationY
            let pullX = currentTranslation.x - initialPanTranslationX
            
            if pullDown < 0 {
                isDismissingViaScrollView = false
                resetViewTransform()
                return
            }
            
            // 상단 제한에 고정
            scrollView.contentOffset.y = topBound
            
            let progress = pullDown / view.bounds.height
            let scale = max(0.85, 1.0 - progress)
            
            view.transform = CGAffineTransform(translationX: pullX, y: pullDown).scaledBy(x: scale, y: scale)
            view.alpha = max(0.4, 1.0 - (progress * 1.5))
            view.layer.masksToBounds = true
            view.layer.cornerRadius = min(40, max(0, pullDown / 5.0))
        }
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if isDismissingViaScrollView {
            let currentTranslation = scrollView.panGestureRecognizer.translation(in: view).y
            let pullDown = max(0, currentTranslation - initialPanTranslationY)
            let velocity = scrollView.panGestureRecognizer.velocity(in: view).y
            
            if pullDown > 100 || velocity > 500 {
                onCancel?()
                dismiss(animated: true)
            } else {
                cancelScrollViewDismiss()
            }
            isDismissingViaScrollView = false
        }
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let svW = scrollView.bounds.width
        let svH = scrollView.bounds.height
        let cw  = scrollView.contentSize.width
        let ch  = scrollView.contentSize.height
        let side = min(svW, svH)

        // The base inset keeps panning constrained to the circle edges
        let baseInsetX = max((svW - side) / 2, 0)
        let baseInsetY = max((svH - side) / 2, 0)

        // If the content is smaller than the circle (e.g. during pinch-out bounce),
        // we add extra inset to keep it centered inside the circle.
        let extraInsetX = max((side - cw) / 2, 0)
        let extraInsetY = max((side - ch) / 2, 0)

        scrollView.contentInset = UIEdgeInsets(top: baseInsetY + extraInsetY,
                                               left: baseInsetX + extraInsetX,
                                               bottom: baseInsetY + extraInsetY,
                                               right: baseInsetX + extraInsetX)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        // fitImage ensures zoom=1.0 already covers the circle; 1.0 is always the minimum.
        if scale < 1.0 {
            scrollView.setZoomScale(1.0, animated: true)
        }
    }

    /// Minimum zoom is always 1.0 — fitImage() already scales the image to fill the circle.
    private func minZoomToCoverCircle() -> CGFloat { return 1.0 }
}

// MARK: - CircleDashedOverlayView

final class CircleDashedOverlayView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let side = min(rect.width, rect.height)
        let cx   = rect.midX
        let cy   = rect.midY
        let circleRect = CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)

        ctx.setFillColor(UIColor.black.withAlphaComponent(0.72).cgColor)
        ctx.fill(rect)
        ctx.setBlendMode(.clear)
        ctx.fillEllipse(in: circleRect)
        ctx.setBlendMode(.normal)
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.80).cgColor)
        ctx.setLineWidth(1.2)
        ctx.setLineDash(phase: 0, lengths: [6, 5])
        ctx.strokeEllipse(in: circleRect.insetBy(dx: 0.6, dy: 0.6))
    }
}
