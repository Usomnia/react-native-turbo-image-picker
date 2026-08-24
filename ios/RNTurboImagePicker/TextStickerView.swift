//
//  TextStickerView.swift
//  RNTurboImagePicker
//

import UIKit

protocol TextStickerViewDelegate: AnyObject {
    func stickerDidTap(_ sticker: TextStickerView)
    func stickerDidTapEdit(_ sticker: TextStickerView)
    func stickerDidTapDelete(_ sticker: TextStickerView)
}

class TextStickerView: UIView {
    
    weak var delegate: TextStickerViewDelegate?
    
    // MARK: - Constants
    
    private static let handleSize: CGFloat = 26
    private static let contentPadding: CGFloat = 16
    /// Shared hit-test expansion for all handle buttons (negative = expand)
    private static let handleHitPadding: CGFloat = -12
    
    // MARK: - Public Properties
    
    var text: String = "" {
        didSet {
            label.text = text
            emojiView.emoji = text
            updateSize()
        }
    }

    /// true 이면 GoogleEmojiImageView를 사용하여 이모지 렌더링
    var isEmojiSticker: Bool = false {
        didSet {
            guard isEmojiSticker != oldValue else { return }
            label.isHidden = isEmojiSticker
            emojiView.isHidden = !isEmojiSticker
            // 이모지 스티커는 편집(연필) 버튼 숨김
            editButton.isHidden = isEmojiSticker ? true : !isActive
            updateSize()
        }
    }

    var textColor: UIColor = .white {
        didSet {
            guard !isEmojiSticker else { return } // 이모지는 색상 변경 없음
            label.textColor = textColor
        }
    }
    
    var isActive: Bool = false {
        didSet {
            borderView.isHidden = !isActive
            editButton.isHidden = isEmojiSticker ? true : !isActive  // 이모지는 편집 버튼 없음
            deleteButton.isHidden = !isActive
            resizeButton.isHidden = !isActive
        }
    }
    
    // MARK: - Zoom-Aware Transform
    
    /// When true (text editing mode): sticker is counter-scaled so it stays the same visual size during pinch zoom.
    /// When false (normal viewing mode): sticker scales naturally with the container — WYSIWYG preview.
    var isEditingMode: Bool = true {
        didSet {
            guard isEditingMode != oldValue else { return }
            
            // Adjust stickerTransform to maintain visual size seamlessly during the mode transition
            let zoom = max(containerZoomScale, 0.001)
            if isEditingMode {
                // False -> True: Scale UP internal transform to counteract the new counter-scale in view
                stickerTransform = stickerTransform.scaledBy(x: zoom, y: zoom)
            } else {
                // True -> False: Scale DOWN internal transform to bake the counter-scale permanently into the image coordinate space
                stickerTransform = stickerTransform.scaledBy(x: 1.0 / zoom, y: 1.0 / zoom)
            }
            
            setNeedsCombinedTransformUpdate()
        }
    }
    
    var containerZoomScale: CGFloat = 1.0 {
        didSet {
            guard containerZoomScale != oldValue else { return }
            setNeedsCombinedTransformUpdate()
        }
    }
    
    var stickerTransform: CGAffineTransform = .identity {
        didSet {
            cachedInverseHandleScale = nil  // invalidate cache
            setNeedsCombinedTransformUpdate()
        }
    }
    
    // We override transform to intercept external sets (like initial creation)
    override var transform: CGAffineTransform {
        get { return stickerTransform }
        set { stickerTransform = newValue }
    }
    
    // MARK: - UI Elements
    
    private let borderView = UIView()
    private let label = UILabel()              // 일반 텍스트 렌더링
    private let emojiView = GoogleEmojiImageView()
    private let editButton = UIButton(type: .custom)
    private let deleteButton = UIButton(type: .custom)
    private let resizeButton = UIButton(type: .custom)
    
    // MARK: - Gesture State
    
    private var initialTransform: CGAffineTransform = .identity
    private var initialCenter: CGPoint = .zero
    private var initialDistance: CGFloat = 0
    private var initialAngle: CGFloat = 0
    
    // MARK: - Internal Cache
    
    /// Cached inverse scale for handle buttons; invalidated when stickerTransform changes
    private var cachedInverseHandleScale: CGAffineTransform?
    
    /// Coalesces multiple transform updates into a single pass per run-loop cycle
    private var needsCombinedTransformUpdate = false
    
    // MARK: - Init
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    // MARK: - Setup
    
    private func setup() {
        backgroundColor = .clear
        
        // Border
        borderView.layer.borderColor = UIColor.white.cgColor
        borderView.layer.borderWidth = 1.5
        borderView.layer.cornerRadius = 8.0
        borderView.backgroundColor = .clear
        addSubview(borderView)
        
        // 일반 텍스트 레이블 (Pretendard)
        label.numberOfLines = 0
        label.font = UIFont(name: "Pretendard-SemiBold", size: 28) ?? .systemFont(ofSize: 28, weight: .semibold)
        label.textAlignment = .center
        addSubview(label)
        
        emojiView.translatesAutoresizingMaskIntoConstraints = false
        emojiView.contentMode = .scaleAspectFit
        emojiView.isHidden = true
        addSubview(emojiView)
        
        // Handles
        setupHandle(button: editButton, imageName: "pencil", action: #selector(editTapped))
        setupHandle(button: deleteButton, imageName: "xmark", action: #selector(deleteTapped))
        setupHandle(button: resizeButton, imageName: "arrow.up.left.and.arrow.down.right", action: nil)
        
        // Resize handle pan
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleResizePan(_:)))
        resizeButton.addGestureRecognizer(panGesture)
        
        // Main gestures
        let mainPan = UIPanGestureRecognizer(target: self, action: #selector(handleMainPan(_:)))
        mainPan.delegate = self
        addGestureRecognizer(mainPan)
        
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinch)
        
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
        addGestureRecognizer(rotate)
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(mainTapped))
        tap.delegate = self
        addGestureRecognizer(tap)
        
        isActive = true
    }
    
    private func setupHandle(button: UIButton, imageName: String, action: Selector?) {
        let cfg = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        let img = UIImage(systemName: imageName, withConfiguration: cfg)
        button.setImage(img, for: .normal)
        button.tintColor = .black
        button.backgroundColor = .white
        button.alpha = 0.8
        button.layer.cornerRadius = Self.handleSize / 2
        
        // Shadow for visibility
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.3
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.layer.shadowRadius = 2
        button.layer.masksToBounds = false
        
        if let act = action {
            button.addTarget(self, action: act, for: .touchUpInside)
        }
        addSubview(button)
    }
    
    // MARK: - Size Calculation
    
    private func updateSize() {
        let maxWidth = (superview?.bounds.width ?? UIScreen.main.bounds.width) - 40

        let expectedSize: CGSize
        if isEmojiSticker {
            expectedSize = CGSize(width: 100, height: 100)
            let side = max(expectedSize.width, expectedSize.height, 100)
            let width = side + Self.contentPadding * 2
            let height = side + Self.contentPadding * 2
            bounds = CGRect(x: 0, y: 0, width: width + Self.handleSize, height: height + Self.handleSize)
        } else {
            let maxSize = CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)
            expectedSize = label.sizeThatFits(maxSize)
            let width = expectedSize.width + Self.contentPadding * 2
            let height = expectedSize.height + Self.contentPadding * 2
            bounds = CGRect(x: 0, y: 0, width: width + Self.handleSize, height: height + Self.handleSize)
        }
        setNeedsLayout()
    }
    
    // MARK: - Transform Coalescing
    
    /// Schedules a combined transform update on the next run-loop pass,
    /// preventing redundant computation when multiple properties change together.
    private func setNeedsCombinedTransformUpdate() {
        guard !needsCombinedTransformUpdate else { return }
        needsCombinedTransformUpdate = true
        DispatchQueue.main.async { [weak self] in
            self?.applyCombinedTransformIfNeeded()
        }
    }
    
    private func applyCombinedTransformIfNeeded() {
        guard needsCombinedTransformUpdate else { return }
        needsCombinedTransformUpdate = false
        
        if isEditingMode {
            // Editing mode: counter-scale so sticker visual size stays constant during image pinch zoom
            let inverseZoom = 1.0 / max(containerZoomScale, 0.001)
            super.transform = stickerTransform.scaledBy(x: inverseZoom, y: inverseZoom)
        } else {
            // Viewing mode: sticker scales naturally with the image (WYSIWYG)
            super.transform = stickerTransform
        }
        updateHandleTransforms()
    }
    
    // MARK: - Handle Inverse Scale (cached)
    
    private func updateHandleTransforms() {
        if cachedInverseHandleScale == nil {
            let scaleX = sqrt(stickerTransform.a * stickerTransform.a + stickerTransform.c * stickerTransform.c)
            let scaleY = sqrt(stickerTransform.b * stickerTransform.b + stickerTransform.d * stickerTransform.d)
            
            let safeScaleX = max(scaleX, 0.001)
            let safeScaleY = max(scaleY, 0.001)
            
            cachedInverseHandleScale = CGAffineTransform(scaleX: 1.0 / safeScaleX, y: 1.0 / safeScaleY)
        }
        
        let scale = cachedInverseHandleScale!
        editButton.transform = scale
        deleteButton.transform = scale
        resizeButton.transform = scale
        
        // 가이드라인(border) 두께: 화면에서 일정하게 보이도록 획 두께 보정
        // editing mode에서 스티커는 inverseZoom으로 이미 카운터-스케일되므로
        // zoomFactor를 곱하지 않아야 확대 시 border가 굵어지지 않음
        let scaleValue = min(scale.a, scale.d) // scale = 1.0 / stickerScale
        borderView.layer.borderWidth = 1.5 * scaleValue
    }
    
    // MARK: - Layout
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let hs = Self.handleSize
        let contentRect = bounds.insetBy(dx: hs / 2, dy: hs / 2)
        borderView.frame = contentRect
        label.frame = contentRect
        emojiView.frame = contentRect
        
        editButton.bounds = CGRect(origin: .zero, size: CGSize(width: hs, height: hs))
        editButton.center = CGPoint(x: hs / 2, y: hs / 2)
        
        deleteButton.bounds = CGRect(origin: .zero, size: CGSize(width: hs, height: hs))
        deleteButton.center = CGPoint(x: bounds.width - hs / 2, y: hs / 2)
        
        resizeButton.bounds = CGRect(origin: .zero, size: CGSize(width: hs, height: hs))
        resizeButton.center = CGPoint(x: bounds.width - hs / 2, y: bounds.height - hs / 2)
    }
    
    // MARK: - Actions
    
    @objc private func mainTapped() {
        delegate?.stickerDidTap(self)
    }
    
    @objc private func editTapped() {
        delegate?.stickerDidTapEdit(self)
    }
    
    @objc private func deleteTapped() {
        delegate?.stickerDidTapDelete(self)
    }
    
    // MARK: - Gestures
    
    @objc private func handleMainPan(_ gesture: UIPanGestureRecognizer) {
        guard let superview = superview else { return }
        
        if gesture.state == .began {
            initialCenter = center
            delegate?.stickerDidTap(self)
        } else if gesture.state == .changed {
            let translation = gesture.translation(in: superview)
            center = CGPoint(x: initialCenter.x + translation.x, y: initialCenter.y + translation.y)
        }
    }
    
    @objc private func handleResizePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview = superview else { return }
        let location = gesture.location(in: superview)
        
        if gesture.state == .began {
            initialTransform = stickerTransform
            let dx = location.x - center.x
            let dy = location.y - center.y
            initialDistance = sqrt(dx*dx + dy*dy)
            initialAngle = atan2(dy, dx)
            delegate?.stickerDidTap(self)
        } else if gesture.state == .changed {
            let dx = location.x - center.x
            let dy = location.y - center.y
            let currentDistance = sqrt(dx*dx + dy*dy)
            let currentAngle = atan2(dy, dx)
            
            let scale = currentDistance / initialDistance
            let angleDiff = currentAngle - initialAngle
            
            var newTransform = initialTransform.scaledBy(x: scale, y: scale)
            newTransform = newTransform.rotated(by: angleDiff)
            stickerTransform = newTransform
        }
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began {
            initialTransform = stickerTransform
            delegate?.stickerDidTap(self)
        } else if gesture.state == .changed {
            stickerTransform = initialTransform.scaledBy(x: gesture.scale, y: gesture.scale)
        }
    }
    
    @objc private func handleRotate(_ gesture: UIRotationGestureRecognizer) {
        if gesture.state == .began {
            initialTransform = stickerTransform
            delegate?.stickerDidTap(self)
        } else if gesture.state == .changed {
            stickerTransform = initialTransform.rotated(by: gesture.rotation)
        }
    }
    
    // MARK: - High-Resolution Baking

    func drawHighRes(in ctx: CGContext) {
        let ctm = ctx.ctm
        let effectiveScale = sqrt(ctm.a * ctm.a + ctm.c * ctm.c)

        let scaledWidth  = bounds.width  * effectiveScale
        let scaledHeight = bounds.height * effectiveScale

        ctx.saveGState()
        ctx.scaleBy(x: 1.0 / effectiveScale, y: 1.0 / effectiveScale)

        if isEmojiSticker {
            let image = emojiView.image ?? UIImage()
            let hs = Self.handleSize
            let inset = (hs / 2.0) * effectiveScale
            let rect = CGRect(
                x: inset,
                y: inset,
                width: scaledWidth - inset * 2.0,
                height: scaledHeight - inset * 2.0
            )
            image.draw(in: rect)
        } else {
            let scaledFont = label.font.withSize(label.font.pointSize * effectiveScale)

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = label.textAlignment

            let attrs: [NSAttributedString.Key: Any] = [
                .font: scaledFont,
                .foregroundColor: label.textColor,
                .paragraphStyle: paragraphStyle
            ]

            let textStr  = label.text ?? ""
            let scaledRect = CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight)
            let measured = textStr.boundingRect(
                with: scaledRect.size,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs,
                context: nil
            )

            let yOffset  = (scaledHeight - measured.height) / 2
            let drawRect = CGRect(x: 0, y: yOffset, width: scaledWidth, height: scaledHeight - yOffset)
            (textStr as NSString).draw(in: drawRect, withAttributes: attrs)
        }

        ctx.restoreGState()
    }


    
    // MARK: - Hit Testing
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha >= 0.01 else { return nil }
        
        if !isEditingMode {
            return bounds.contains(point) ? self : nil
        }
        
        let pad = Self.handleHitPadding
        if editButton.frame.insetBy(dx: pad, dy: pad).contains(point) && !editButton.isHidden {
            return editButton
        }
        if deleteButton.frame.insetBy(dx: pad, dy: pad).contains(point) && !deleteButton.isHidden {
            return deleteButton
        }
        if resizeButton.frame.insetBy(dx: pad, dy: pad).contains(point) && !resizeButton.isHidden {
            return resizeButton
        }
        if bounds.contains(point) {
            return self
        }
        return nil
    }
}

extension TextStickerView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let loc = touch.location(in: self)
        let pad = Self.handleHitPadding
        if !editButton.isHidden && editButton.frame.insetBy(dx: pad, dy: pad).contains(loc) { return false }
        if !deleteButton.isHidden && deleteButton.frame.insetBy(dx: pad, dy: pad).contains(loc) { return false }
        if !resizeButton.isHidden && resizeButton.frame.insetBy(dx: pad, dy: pad).contains(loc) { return false }
        
        if gestureRecognizer is UIPanGestureRecognizer {
            // Allow panning inactive stickers to select and move them automatically
            return true
        }
        
        return true
    }
}
