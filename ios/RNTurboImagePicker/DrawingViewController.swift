import UIKit
import CoreImage

// MARK: - Drawing Tool Type
enum DrawingToolType {
    case pen
    case mosaic
    case eraser
}

// MARK: - Drawing Path
struct DrawingPath {
    var path: UIBezierPath
    var type: DrawingToolType
    var color: UIColor
    var lineWidth: CGFloat
}

// MARK: - BrushSizeSlider
protocol BrushSizeSliderDelegate: AnyObject {
    func brushSizeSlider(_ slider: BrushSizeSliderView, didChangeValue value: CGFloat)
    func brushSizeSliderDidBeginDragging(_ slider: BrushSizeSliderView)
    func brushSizeSliderDidEndDragging(_ slider: BrushSizeSliderView)
}

class BrushSizeSliderView: UIView {
    weak var delegate: BrushSizeSliderDelegate?
    
    var minimumValue: CGFloat = 2.0
    var maximumValue: CGFloat = 50.0
    var value: CGFloat = 10.0 {
        didSet { updateThumbPosition() }
    }
    
    private let trackLayer = CAShapeLayer()
    private let thumbView = UIView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private func setup() {
        trackLayer.fillColor = UIColor(white: 1.0, alpha: 0.5).cgColor
        layer.addSublayer(trackLayer)
        
        thumbView.backgroundColor = .white
        thumbView.layer.shadowColor = UIColor.black.cgColor
        thumbView.layer.shadowOffset = .zero
        thumbView.layer.shadowOpacity = 0.3
        thumbView.layer.shadowRadius = 4
        addSubview(thumbView)
        
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let topWidth: CGFloat = 16.0
        let bottomWidth: CGFloat = 4.0
        let h = bounds.height
        let midX = bounds.width / 2
        
        let path = UIBezierPath()
        path.addArc(withCenter: CGPoint(x: midX, y: topWidth/2), radius: topWidth/2, startAngle: .pi, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: midX + bottomWidth/2, y: h - bottomWidth/2))
        path.addArc(withCenter: CGPoint(x: midX, y: h - bottomWidth/2), radius: bottomWidth/2, startAngle: 0, endAngle: .pi, clockwise: true)
        path.close()
        
        trackLayer.path = path.cgPath
        
        let thumbSize: CGFloat = 30.0
        thumbView.bounds = CGRect(x: 0, y: 0, width: thumbSize, height: thumbSize)
        thumbView.layer.cornerRadius = thumbSize / 2
        updateThumbPosition()
    }
    
    private func updateThumbPosition() {
        let h = bounds.height
        let thumbSize: CGFloat = 30.0
        let topY: CGFloat = thumbSize / 2
        let bottomY: CGFloat = h - thumbSize / 2
        
        let percentage = (value - minimumValue) / (maximumValue - minimumValue)
        let y = bottomY - percentage * (bottomY - topY)
        
        thumbView.center = CGPoint(x: bounds.width / 2, y: y)
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let loc = gesture.location(in: self)
        updateValue(from: loc.y)
        
        if gesture.state == .began {
            delegate?.brushSizeSliderDidBeginDragging(self)
        } else if gesture.state == .ended || gesture.state == .cancelled {
            delegate?.brushSizeSliderDidEndDragging(self)
        }
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let loc = gesture.location(in: self)
        updateValue(from: loc.y)
        delegate?.brushSizeSliderDidBeginDragging(self)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.delegate?.brushSizeSliderDidEndDragging(self)
        }
    }
    
    private func updateValue(from y: CGFloat) {
        let h = bounds.height
        let thumbSize: CGFloat = 30.0
        let topY: CGFloat = thumbSize / 2
        let bottomY: CGFloat = h - thumbSize / 2
        
        let clampedY = max(topY, min(bottomY, y))
        let percentage = 1.0 - (clampedY - topY) / (bottomY - topY)
        
        value = minimumValue + percentage * (maximumValue - minimumValue)
        delegate?.brushSizeSlider(self, didChangeValue: value)
    }
}

// MARK: - Drawing Canvas View
class DrawingCanvasView: UIView {
    
    // 🚀 성능 최적화: draw() 핫패스에서 UIColor 반복 생성 방지
    private static let mosaicShadowColor = UIColor(white: 0, alpha: 0.2).cgColor
    private static let mosaicCoreColor = UIColor.black.cgColor
    
    var originalImage: UIImage? {
        didSet {
            setupMosaicImage()
            setNeedsDisplay()
        }
    }
    
    private var mosaicImage: UIImage?
    private var displayMosaicImage: UIImage?
    private var lastBoundsForDisplayMosaic: CGRect = .zero
    
    var paths: [DrawingPath] = []
    var undonePaths: [DrawingPath] = []
    var currentPath: DrawingPath?
    
    var currentTool: DrawingToolType = .pen
    var currentColor: UIColor = .systemYellow
    var currentLineWidth: CGFloat = 10.0
    
    /// 모자이크 타일의 화면 기준 크기 (pt). 클수록 강한 모자이크 (픽셀이 큼)
    /// 범위: 6pt (미세) ~ 20pt (강함), 기본값: 6pt (가장 약하게)
    var mosaicBlockSizePt: CGFloat = 6.0 {
        didSet {
            setupMosaicImage()
        }
    }
    
    var onStateChanged: (() -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.isMultipleTouchEnabled = false
        self.clipsToBounds = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupMosaicImage() {
        guard let img = originalImage else { return }
        
        let imgSize = img.size
        let imgScale = img.scale
        let blockSizePt = mosaicBlockSizePt
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // mosaicBlockSizePt: 슬라이더 값 (클수록 강한 모자이크)
            // 실제 scaleFactor는 blockSizePt에 반비례: 블록이 클수록 소 이미지가 더 작아짐 = 강한 모자이크
            // 예: blockSizePt=6  → scaleFactor=1/12  → 작은 이미지 크게 = 약한 모자이크
            //     blockSizePt=16 → scaleFactor=1/32  ≈ 0.031 → 중간
            //     blockSizePt=40 → scaleFactor=1/80  = 0.0125 → 강한 모자이크
            let scaleFactor = 1.0 / (blockSizePt * 2.0)
            let smallSize = CGSize(
                width: max(1, floor(imgSize.width * scaleFactor)),
                height: max(1, floor(imgSize.height * scaleFactor))
            )
            
            // 1. Draw downscaled
            UIGraphicsBeginImageContextWithOptions(smallSize, false, 1.0)
            guard let smallContext = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                return
            }
            smallContext.interpolationQuality = .default
            img.draw(in: CGRect(origin: .zero, size: smallSize))
            let smallImg = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            guard let small = smallImg else { return }
            
            // 2. Draw upscaled without anti-aliasing
            UIGraphicsBeginImageContextWithOptions(imgSize, false, imgScale)
            guard let largeContext = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                return
            }
            largeContext.interpolationQuality = .none // CRITICAL for pixelation!
            small.draw(in: CGRect(origin: .zero, size: imgSize))
            let mosaicImg = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            DispatchQueue.main.async {
                self?.mosaicImage = mosaicImg
                self?.displayMosaicImage = nil
                self?.updateDisplayMosaicIfNeeded()
                self?.setNeedsDisplay()
            }
        }
    }
    
    private var lastPoint: CGPoint = .zero
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        
        let path = UIBezierPath()
        path.move(to: point)
        
        lastPoint = point
        
        // 모자이크 툴은 브러시 크기 중간(고정)
        let lineWidthToUse: CGFloat = currentTool == .mosaic ? 40.0 : currentLineWidth
        currentPath = DrawingPath(path: path, type: currentTool, color: currentColor, lineWidth: lineWidthToUse)
        undonePaths.removeAll() // Clear redo stack on new drawing
        setNeedsDisplay()
        onStateChanged?()
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let currentPath = currentPath else { return }
        let point = touch.location(in: self)
        
        let dx = point.x - lastPoint.x
        let dy = point.y - lastPoint.y
        let dist = sqrt(dx*dx + dy*dy)
        
        // Prevent knots and artifacts by ignoring points that are too close
        if dist < 3.0 { return }
        
        let midPoint = CGPoint(x: (lastPoint.x + point.x) / 2, y: (lastPoint.y + point.y) / 2)
        currentPath.path.addQuadCurve(to: midPoint, controlPoint: lastPoint)
        
        lastPoint = point
        setNeedsDisplay()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        
        if let currentPath = currentPath {
            currentPath.path.addLine(to: point)
            paths.append(currentPath)
        }
        currentPath = nil
        setNeedsDisplay()
        onStateChanged?()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        currentPath = nil
        setNeedsDisplay()
        onStateChanged?()
    }
    
    func undo() {
        guard !paths.isEmpty else { return }
        let p = paths.removeLast()
        undonePaths.append(p)
        setNeedsDisplay()
        onStateChanged?()
    }
    
    func redo() {
        guard !undonePaths.isEmpty else { return }
        let p = undonePaths.removeLast()
        paths.append(p)
        setNeedsDisplay()
        onStateChanged?()
    }
    
    func clearAll() {
        paths.removeAll()
        undonePaths.removeAll()
        setNeedsDisplay()
        onStateChanged?()
    }
    
    // 🚀 성능 최적화: displayMosaicImage 생성을 draw() 밖으로 분리
    // draw()는 프레임마다 호출되므로 메모리 할당을 최소화
    override func layoutSubviews() {
        super.layoutSubviews()
        updateDisplayMosaicIfNeeded()
    }
    
    private func updateDisplayMosaicIfNeeded() {
        guard lastBoundsForDisplayMosaic != bounds || displayMosaicImage == nil else { return }
        guard let mosaic = mosaicImage, bounds.width > 0, bounds.height > 0 else { return }
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 0 // uses device scale
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        displayMosaicImage = renderer.image { _ in
            mosaic.draw(in: CGRect(origin: .zero, size: bounds.size))
        }
        lastBoundsForDisplayMosaic = bounds
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        let allPaths = paths + (currentPath != nil ? [currentPath!] : [])
        
        var i = 0
        while i < allPaths.count {
            let p = allPaths[i]
            
            if p.type == .mosaic {
                var j = i + 1
                while j < allPaths.count && allPaths[j].type == .mosaic {
                    j += 1
                }
                let mosaicGroup = Array(allPaths[i..<j])
                if let mosaicImg = displayMosaicImage {
                    renderMosaicTileSnapped(into: context, mosaicGroup: mosaicGroup, mosaicImage: mosaicImg, inBounds: bounds)
                }
                i = j
            } else {
                context.saveGState()
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.setLineWidth(p.lineWidth)
                
                if p.type == .eraser {
                    context.setBlendMode(.clear)
                    context.setStrokeColor(UIColor.clear.cgColor)
                    context.addPath(p.path.cgPath)
                    context.strokePath()
                } else {
                    context.setBlendMode(.normal)
                    context.setStrokeColor(p.color.cgColor)
                    context.addPath(p.path.cgPath)
                    context.strokePath()
                }
                context.restoreGState()
                i += 1
            }
        }
    }
    
    func generateMergedImage() -> UIImage? {
        guard let img = originalImage else { return nil }
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = img.scale
        
        // 1. Render all drawing paths into an overlay image
        let overlayRenderer = UIGraphicsImageRenderer(size: img.size, format: format)
        let overlayImage = overlayRenderer.image { context in
            let cgContext = context.cgContext
            let scaleX = img.size.width / bounds.width
            let scaleY = img.size.height / bounds.height
            
            cgContext.scaleBy(x: scaleX, y: scaleY)
            
            var i = 0
            while i < paths.count {
                let p = paths[i]
                
                if p.type == .mosaic {
                    var j = i + 1
                    while j < paths.count && paths[j].type == .mosaic {
                        j += 1
                    }
                    let mosaicGroup = Array(paths[i..<j])
                    // Export 시에도 타일 스냅 렌더링 사용 (mosaicImage: 원본 해상도 기준)
                    if let mosaicImg = mosaicImage {
                        renderMosaicTileSnapped(into: cgContext, mosaicGroup: mosaicGroup, mosaicImage: mosaicImg, inBounds: bounds)
                    }
                    i = j
                } else {
                    cgContext.saveGState()
                    cgContext.setLineCap(.round)
                    cgContext.setLineJoin(.round)
                    cgContext.setLineWidth(p.lineWidth)
                    
                    if p.type == .eraser {
                        cgContext.setBlendMode(.clear)
                        cgContext.setStrokeColor(UIColor.clear.cgColor)
                        cgContext.addPath(p.path.cgPath)
                        cgContext.strokePath()
                    } else {
                        cgContext.setBlendMode(.normal)
                        cgContext.setStrokeColor(p.color.cgColor)
                        cgContext.addPath(p.path.cgPath)
                        cgContext.strokePath()
                    }
                    cgContext.restoreGState()
                    i += 1
                }
            }
        }
        
        // 2. Composite the overlay on top of the original image
        let finalRenderer = UIGraphicsImageRenderer(size: img.size, format: format)
        return finalRenderer.image { _ in
            img.draw(at: .zero)
            overlayImage.draw(at: .zero)
        }
    }
    
    /// 타일 단위 모자이크 렌더링: 경로를 작은 마스크 비트맵으로 래스터화 후
    /// 덮인 타일만 완전 불투명하게 채워 가장자리 반투명 현상 제거
    private func renderMosaicTileSnapped(into context: CGContext, mosaicGroup: [DrawingPath], mosaicImage: UIImage, inBounds viewBounds: CGRect) {
        let cw = viewBounds.width
        let ch = viewBounds.height
        guard cw > 0, ch > 0 else { return }
        
        let numTilesX = max(40, Int(cw / 24))
        let numTilesY = max(1, Int(CGFloat(numTilesX) * ch / cw) + 1)
        let tileW = cw / CGFloat(numTilesX)
        let tileH = ch / CGFloat(numTilesY)
        let scaleX = CGFloat(numTilesX) / cw
        let scaleY = CGFloat(numTilesY) / ch
        
        // 1. 경로를 타일 격자 크기의 그레이스케일 마스크로 래스터화
        var maskBytes = [UInt8](repeating: 0, count: numTilesX * numTilesY)
        guard let graySpace = CGColorSpace(name: CGColorSpace.linearGray),
              let maskCtx = CGContext(data: &maskBytes, width: numTilesX, height: numTilesY,
                                     bitsPerComponent: 8, bytesPerRow: numTilesX,
                                     space: graySpace, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
        
        // CGContext는 Y축 반전 (하단이 0) → UIKit 경로와 맞추기 위해 플립
        maskCtx.translateBy(x: 0, y: CGFloat(numTilesY))
        maskCtx.scaleBy(x: scaleX, y: -scaleY)
        maskCtx.setLineCap(.round)
        maskCtx.setLineJoin(.round)
        maskCtx.setStrokeColor(gray: 1, alpha: 1)
        
        for mp in mosaicGroup {
            maskCtx.setLineWidth(mp.lineWidth)
            maskCtx.addPath(mp.path.cgPath)
            maskCtx.strokePath()
        }
        
        // 2. 덮인 타일을 모아 클리핑 경로 생성
        var coveredPath = CGMutablePath()
        for ty in 0..<numTilesY {
            for tx in 0..<numTilesX {
                if maskBytes[ty * numTilesX + tx] > 0 {
                    coveredPath.addRect(CGRect(
                        x: CGFloat(tx) * tileW,
                        y: CGFloat(ty) * tileH,
                        width: tileW,
                        height: tileH
                    ))
                }
            }
        }
        
        // 3. 덮인 타일만 클리핑 후 모자이크 이미지 한 번에 그리기
        // coveredPath가 비어있으면 clip()이 전체 컨텍스트를 클리핑하므로 반드시 확인
        guard !coveredPath.isEmpty else { return }
        context.saveGState()
        context.addPath(coveredPath)
        context.clip()
        mosaicImage.draw(in: viewBounds, blendMode: .normal, alpha: 1.0)
        context.restoreGState()
    }
}

// MARK: - DrawingViewController
class DrawingViewController: UIViewController {
    
    var sourceImage: UIImage
    var themeColor: UIColor = .systemYellow
    var onDrawingComplete: ((UIImage) -> Void)?
    var onCancel: (() -> Void)?
    
    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.backgroundColor = .clear
        sv.delegate = self
        sv.minimumZoomScale = 1.0
        sv.maximumZoomScale = 5.0
        sv.showsVerticalScrollIndicator = false
        sv.showsHorizontalScrollIndicator = false
        sv.delaysContentTouches = false
        sv.panGestureRecognizer.minimumNumberOfTouches = 2 // 2 fingers to pan, 1 for drawing
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    
    private lazy var imageContainer: UIView = {
        let v = UIView()
        v.backgroundColor = .clear
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    private lazy var imageView: UIImageView = {
        let iv = UIImageView(image: sourceImage)
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    
    private lazy var canvasView: DrawingCanvasView = {
        let cv = DrawingCanvasView()
        cv.originalImage = sourceImage
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()
    
    private lazy var topBar: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.editorOverlay
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    private lazy var bottomBar: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.editorCellBackground
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    private lazy var colorPickerContainer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.editorCellBackground // Match bottomBar
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    private lazy var colorScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    
    private lazy var colorStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 16
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    
    private let colors: [UIColor] = [
        .white, .lightGray, .gray, .darkGray, .black,
        .systemRed, .systemOrange, .systemYellow,
        .systemGreen, .systemTeal, .systemBlue, .systemPurple, .systemPink,
        UIColor(red: 1.00, green: 0.80, blue: 0.80, alpha: 1.0), // Pastel Pink
        UIColor(red: 1.00, green: 0.88, blue: 0.60, alpha: 1.0), // Pastel Orange
        UIColor(red: 1.00, green: 0.96, blue: 0.60, alpha: 1.0), // Pastel Yellow
        UIColor(red: 0.75, green: 0.95, blue: 0.75, alpha: 1.0), // Pastel Green
        UIColor(red: 0.70, green: 0.85, blue: 1.00, alpha: 1.0), // Pastel Blue
        UIColor(red: 0.85, green: 0.75, blue: 1.00, alpha: 1.0)  // Pastel Purple
    ]
    private var colorButtons: [UIButton] = []
    private var selectedColorIndex: Int = UserDefaults.standard.object(forKey: "drawing_colorIndex") != nil
        ? UserDefaults.standard.integer(forKey: "drawing_colorIndex")
        : 0 // Default White
    
    private lazy var sizeSlider: BrushSizeSliderView = {
        let s = BrushSizeSliderView()
        s.minimumValue = 2.0
        s.maximumValue = 50.0
        let savedSize = UserDefaults.standard.object(forKey: "drawing_brushSize") != nil
            ? CGFloat(UserDefaults.standard.float(forKey: "drawing_brushSize"))
            : 10.0
        s.value = savedSize
        s.delegate = self
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()
    
    private lazy var brushPreviewCircle: UIView = {
        let v = UIView()
        v.backgroundColor = themeColor
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOffset = .zero
        v.layer.shadowOpacity = 0.3
        v.layer.shadowRadius = 4
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    private var sliderLeadingConstraint: NSLayoutConstraint!
    private var brushPreviewWidthConstraint: NSLayoutConstraint!
    
    // Top Bar Buttons
    private lazy var deleteBtn = makeIconBtn("ic_drawing_delete", fallbackSys: "trash", action: #selector(trashTapped))
    private lazy var rewardBtn = makeIconBtn("ic_drawing_reward", fallbackSys: "arrow.uturn.backward", action: #selector(undoTapped))
    private lazy var forwardBtn = makeIconBtn("ic_drawing_forward", fallbackSys: "arrow.uturn.forward", action: #selector(redoTapped))
    
    // Bottom Bar Buttons
    private lazy var cancelBtn = makeSysBtn("xmark", action: #selector(cancelTapped))
    private lazy var penBtn = makeIconBtn("ic_editor_drawing", fallbackSys: "pencil.tip", action: #selector(penTapped))
    private lazy var mosaicBtn = makeIconBtn("ic_editor_mosaic", fallbackSys: "checkerboard.rectangle", action: #selector(mosaicTapped))
    private lazy var eraserBtn = makeIconBtn("ic_editor_eraser", fallbackSys: "eraser", pointSize: 22, action: #selector(eraserTapped))
    private lazy var confirmBtn = makeSysBtn("checkmark", action: #selector(confirmTapped))
    
    init(image: UIImage) {
        self.sourceImage = image
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .overFullScreen
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.editorBackground
        
        setupLayout()
        setupColorPicker()
        updateTopBarStates()
        updateBottomTools()
        
        canvasView.onStateChanged = { [weak self] in
            self?.updateTopBarStates()
        }
    }
    
    private func setupLayout() {
        view.addSubview(scrollView)
        scrollView.addSubview(imageContainer)
        imageContainer.addSubview(imageView)
        imageContainer.addSubview(canvasView)
        
        view.addSubview(topBar)
        view.addSubview(colorPickerContainer)
        view.addSubview(bottomBar)
        
        let safeArea = view.safeAreaLayoutGuide
        
        topBar.addSubview(deleteBtn)
        topBar.addSubview(rewardBtn)
        topBar.addSubview(forwardBtn)
        
        colorPickerContainer.addSubview(colorScrollView)
        colorScrollView.addSubview(colorStack)
        
        bottomBar.addSubview(cancelBtn)
        bottomBar.addSubview(confirmBtn)
        
        let centerStack = UIStackView(arrangedSubviews: [penBtn, mosaicBtn, eraserBtn])
        centerStack.axis = .horizontal
        centerStack.alignment = .center
        centerStack.spacing = 15 // Bring buttons much closer together
        centerStack.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(centerStack)
        
        view.addSubview(sizeSlider)
        view.addSubview(brushPreviewCircle)
        
        sliderLeadingConstraint = sizeSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -20)
        brushPreviewWidthConstraint = brushPreviewCircle.widthAnchor.constraint(equalToConstant: sizeSlider.value)
        
        // Constraints
        NSLayoutConstraint.activate([
            // Scroll View
            scrollView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: colorPickerContainer.topAnchor),
            
            // Image Container inside ScrollView
            imageContainer.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageContainer.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageContainer.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageContainer.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            
            imageContainer.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageContainer.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            
            imageView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),
            
            // Canvas View needs to perfectly overlap imageView's content frame
            // We'll update this in viewDidLayoutSubviews
            
            // Top Bar
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.bottomAnchor.constraint(equalTo: safeArea.topAnchor, constant: 44),
            
            // delete: 우측 끝
            deleteBtn.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -8),
            deleteBtn.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -8),
            
            // reward (undo): 좌측
            rewardBtn.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 8),
            rewardBtn.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -8),
            
            // forward (redo): reward 바로 오른쪽
            forwardBtn.leadingAnchor.constraint(equalTo: rewardBtn.trailingAnchor, constant: 8),
            forwardBtn.bottomAnchor.constraint(equalTo: topBar.bottomAnchor, constant: -8),
            
            // Bottom Bar
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 88),
            
            cancelBtn.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 16),
            cancelBtn.centerYAnchor.constraint(equalTo: centerStack.centerYAnchor),
            
            confirmBtn.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -16),
            confirmBtn.centerYAnchor.constraint(equalTo: centerStack.centerYAnchor),
            
            centerStack.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            centerStack.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            centerStack.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
            
            // Color Picker
            colorPickerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            colorPickerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            colorPickerContainer.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
            colorPickerContainer.heightAnchor.constraint(equalToConstant: 50),
            
            colorScrollView.topAnchor.constraint(equalTo: colorPickerContainer.topAnchor),
            colorScrollView.leadingAnchor.constraint(equalTo: colorPickerContainer.leadingAnchor),
            colorScrollView.trailingAnchor.constraint(equalTo: colorPickerContainer.trailingAnchor),
            colorScrollView.bottomAnchor.constraint(equalTo: colorPickerContainer.bottomAnchor),
            
            colorStack.topAnchor.constraint(equalTo: colorScrollView.topAnchor),
            colorStack.leadingAnchor.constraint(equalTo: colorScrollView.leadingAnchor, constant: 16),
            colorStack.trailingAnchor.constraint(equalTo: colorScrollView.trailingAnchor, constant: -16),
            colorStack.bottomAnchor.constraint(equalTo: colorScrollView.bottomAnchor),
            colorStack.heightAnchor.constraint(equalTo: colorScrollView.heightAnchor),
            
            // Slider
            sliderLeadingConstraint,
            sizeSlider.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            sizeSlider.widthAnchor.constraint(equalToConstant: 40),
            sizeSlider.heightAnchor.constraint(equalToConstant: 300),
            
            // Brush Preview
            brushPreviewCircle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            brushPreviewCircle.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            brushPreviewWidthConstraint,
            brushPreviewCircle.heightAnchor.constraint(equalTo: brushPreviewCircle.widthAnchor)
        ])
        
        brushPreviewCircle.layer.cornerRadius = sizeSlider.value / 2
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        let containerRect = imageContainer.bounds
        guard containerRect.width > 0, containerRect.height > 0 else { return }
        
        let imgSize = sourceImage.size
        let scale = min(containerRect.width / imgSize.width, containerRect.height / imgSize.height)
        let scaledW = imgSize.width * scale
        let scaledH = imgSize.height * scale
        
        let offsetX = (containerRect.width - scaledW) / 2
        let offsetY = (containerRect.height - scaledH) / 2
        
        let imgFrame = CGRect(x: offsetX, y: offsetY, width: scaledW, height: scaledH)
        canvasView.frame = imgFrame
    }
    
    private func setupColorPicker() {
        canvasView.currentColor = colors[selectedColorIndex]
        canvasView.currentLineWidth = sizeSlider.value
        // 저장된 모자이크 블록 크기 복원
        let savedMosaicSize = UserDefaults.standard.float(forKey: "drawing_mosaicBlockSize")
        if savedMosaicSize > 0 {
            canvasView.mosaicBlockSizePt = CGFloat(savedMosaicSize)
        }
        
        var sizeConstraints: [NSLayoutConstraint] = []
        for (index, color) in colors.enumerated() {
            let btn = UIButton(type: .custom)
            btn.backgroundColor = color
            btn.layer.cornerRadius = 15
            btn.layer.borderWidth = 2
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.tag = index
            btn.addTarget(self, action: #selector(colorTapped(_:)), for: .touchUpInside)
            
            applyColorBorder(btn, color: color, isSelected: index == selectedColorIndex)
            
            sizeConstraints.append(btn.widthAnchor.constraint(equalToConstant: 30))
            sizeConstraints.append(btn.heightAnchor.constraint(equalToConstant: 30))
            
            colorStack.addArrangedSubview(btn)
            colorButtons.append(btn)
        }
        NSLayoutConstraint.activate(sizeConstraints)
    }
    
    private func applyColorBorder(_ btn: UIButton, color: UIColor, isSelected: Bool) {
        if isSelected {
            btn.layer.borderColor = UIColor.lightGray.cgColor // Selected border
        } else if color == .black || color == .darkGray {
            btn.layer.borderColor = UIColor(white: 1.0, alpha: 0.3).cgColor
        } else {
            btn.layer.borderColor = UIColor.clear.cgColor
        }
    }
    
    private func makeSysBtn(_ sysName: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        btn.setImage(UIImage(systemName: sysName, withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.editorForeground
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: 44).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 44).isActive = true
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }
    
    private func makeIconBtn(_ baseName: String, fallbackSys: String? = nil, pointSize: CGFloat = 18, action: Selector) -> UIButton {
        let btn = UIButton(type: .custom)
        // ToolbarIcons 폴더의 ~dark/~light 파일로 로드 (AssetBundle이 처리)
        if let img = AssetBundle.image(named: baseName) {
            btn.setImage(img.withRenderingMode(.alwaysTemplate), for: .normal)
            btn.imageEdgeInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        } else if let fs = fallbackSys {
            let cfg = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            btn.setImage(UIImage(systemName: fs, withConfiguration: cfg), for: .normal)
        }
        btn.tintColor = UIColor.editorForeground
        btn.imageView?.contentMode = .scaleAspectFit
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: 48).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 48).isActive = true
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }
    
    private func updateTopBarStates() {
        rewardBtn.isEnabled = !canvasView.paths.isEmpty
        rewardBtn.alpha = rewardBtn.isEnabled ? 1.0 : 0.3
        
        forwardBtn.isEnabled = !canvasView.undonePaths.isEmpty
        forwardBtn.alpha = forwardBtn.isEnabled ? 1.0 : 0.3
        
        deleteBtn.isEnabled = !canvasView.paths.isEmpty
        deleteBtn.alpha = deleteBtn.isEnabled ? 1.0 : 0.3
    }
    
    private func updateBottomTools() {
        let fgColor = UIColor.editorForeground
        penBtn.tintColor = canvasView.currentTool == .pen ? themeColor : fgColor
        mosaicBtn.tintColor = canvasView.currentTool == .mosaic ? themeColor : fgColor
        eraserBtn.tintColor = canvasView.currentTool == .eraser ? themeColor : fgColor
        colorPickerContainer.isHidden = (canvasView.currentTool == .eraser || canvasView.currentTool == .mosaic)
        
        // 모자이크 툴 선택 시: 슬라이더를 모자이크 강도 조절 모드로
        if canvasView.currentTool == .mosaic {
            sizeSlider.minimumValue = 6
            sizeSlider.maximumValue = 20
            sizeSlider.value = canvasView.mosaicBlockSizePt
        } else {
            sizeSlider.minimumValue = 2
            sizeSlider.maximumValue = 50
            sizeSlider.value = canvasView.currentLineWidth
        }
    }
    
    // MARK: - Actions
    
    @objc private func colorTapped(_ sender: UIButton) {
        let newIndex = sender.tag
        guard newIndex != selectedColorIndex else { return }
        
        let prevBtn = colorButtons[selectedColorIndex]
        applyColorBorder(prevBtn, color: colors[selectedColorIndex], isSelected: false)
        
        selectedColorIndex = newIndex
        UserDefaults.standard.set(newIndex, forKey: "drawing_colorIndex")
        canvasView.currentColor = colors[newIndex]
        brushPreviewCircle.backgroundColor = themeColor
        applyColorBorder(sender, color: canvasView.currentColor, isSelected: true)
    }
    
    @objc private func undoTapped() {
        canvasView.undo()
    }
    
    @objc private func redoTapped() {
        canvasView.redo()
    }
    
    @objc private func trashTapped() {
        canvasView.clearAll()
    }
    
    @objc private func cancelTapped() {
        onCancel?()
        let finish = {
            self.dismiss(animated: false)
        }
        
        if scrollView.zoomScale > 1.0 {
            UIView.animate(withDuration: 0.25, animations: {
                self.scrollView.zoomScale = 1.0
            }) { _ in finish() }
        } else {
            finish()
        }
    }
    
    @objc private func penTapped() {
        canvasView.currentTool = .pen
        updateBottomTools()
    }
    
    @objc private func mosaicTapped() {
        canvasView.currentTool = .mosaic
        updateBottomTools()
    }
    
    @objc private func eraserTapped() {
        canvasView.currentTool = .eraser
        updateBottomTools()
    }
    
    @objc private func confirmTapped() {
        let finish = {
            if let merged = self.canvasView.generateMergedImage() {
                self.onDrawingComplete?(merged)
            }
            self.dismiss(animated: false)
        }
        
        if scrollView.zoomScale > 1.0 {
            UIView.animate(withDuration: 0.25, animations: {
                self.scrollView.zoomScale = 1.0
            }) { _ in finish() }
        } else {
            finish()
        }
    }
}

// MARK: - UIScrollViewDelegate
extension DrawingViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageContainer
    }
}

// MARK: - BrushSizeSliderDelegate
extension DrawingViewController: BrushSizeSliderDelegate {
    func brushSizeSlider(_ slider: BrushSizeSliderView, didChangeValue value: CGFloat) {
        if canvasView.currentTool == .mosaic {
            // 모자이크 툴: 슬라이더가 타일 크기(= 모자이크 강도) 조절
            canvasView.mosaicBlockSizePt = value
            UserDefaults.standard.set(Float(value), forKey: "drawing_mosaicBlockSize")
            // 프리븷: 모자이크 블록 크기 시각화
            let displaySize = value * scrollView.zoomScale
            brushPreviewWidthConstraint.constant = displaySize
            brushPreviewCircle.layer.cornerRadius = 4 // 사각형 모양으로 클렇
        } else {
            canvasView.currentLineWidth = value
            UserDefaults.standard.set(Float(value), forKey: "drawing_brushSize")
            let displaySize = value * scrollView.zoomScale
            brushPreviewWidthConstraint.constant = displaySize
            brushPreviewCircle.layer.cornerRadius = displaySize / 2
        }
    }
    
    func brushSizeSliderDidBeginDragging(_ slider: BrushSizeSliderView) {
        let displaySize = slider.value * scrollView.zoomScale
        brushPreviewWidthConstraint.constant = displaySize
        if canvasView.currentTool == .mosaic {
            brushPreviewCircle.layer.cornerRadius = 4
        } else {
            brushPreviewCircle.layer.cornerRadius = displaySize / 2
        }
        
        sliderLeadingConstraint.constant = 0
        brushPreviewCircle.isHidden = false
        UIView.animate(withDuration: 0.2) {
            self.view.layoutIfNeeded()
        }
    }
    
    func brushSizeSliderDidEndDragging(_ slider: BrushSizeSliderView) {
        sliderLeadingConstraint.constant = -20
        UIView.animate(withDuration: 0.2, animations: {
            self.view.layoutIfNeeded()
        }) { _ in
            self.brushPreviewCircle.isHidden = true
        }
    }
}
