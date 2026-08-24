//
//  ImageEditorViewController.swift
//  RNTurboImagePicker
//
//  UICollectionView + PHCachingImageManager 기반 고성능 에디터
//  - 핀치/더블탭 줌
//  - 확대 상태 경계 도달 시 자동 페이지 전환
//  - NSCache 공유 이미지 캐시
//

import UIKit
import Photos
#if canImport(SDWebImageWebPCoder)
@_implementationOnly import SDWebImageWebPCoder
#endif

// MARK: - Adaptive Color Palette (Dark / Light mode)

internal extension UIColor {
    /// 배경: 다크=블랙, 라이트=흰색
    static var editorBackground: UIColor {
        UIColor { t in t.userInterfaceStyle == .dark ? .black : .white }
    }
    /// 바(Bar) 배경: 다크=거의 검정, 라이트=거의 흰색
    static var editorBarBackground: UIColor {
        UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 0.08, alpha: 0.95)
                : UIColor(white: 0.97, alpha: 0.95)
        }
    }
    /// 필터/슬라이더 반투명 오버레이
    static var editorOverlay: UIColor {
        UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(white: 0.0, alpha: 0.6)
                : UIColor(white: 1.0, alpha: 0.75)
        }
    }
    /// 기본 전경(아이콘/텍스트): 다크=흰색, 라이트=블랙
    static var editorForeground: UIColor {
        UIColor { t in t.userInterfaceStyle == .dark ? .white : .black }
    }
    /// 슬라이더 최대값 트랙: 다크=darkGray, 라이트=lightGray
    static var editorSliderTrack: UIColor {
        UIColor { t in t.userInterfaceStyle == .dark ? .darkGray : .lightGray }
    }
    /// 컬렉션뷰 셀 배경
    static var editorCellBackground: UIColor {
        UIColor { t in t.userInterfaceStyle == .dark ? .black : .white }
    }
}

// MARK: - Asset Bundle Helper
// xcassets 대신 ToolbarIcons 폴더의 파일을 직접 로드
// 파일명 규칙: ic_editor_xxx~light.webp / ic_editor_xxx~dark.webp
enum AssetBundle {
    static func bundle() -> Bundle {
        let bundle = Bundle(for: ImageEditorViewController.self)
        if let url = bundle.url(forResource: "RNTurboImagePickerAssets", withExtension: "bundle"),
           let resourceBundle = Bundle(url: url) {
            return resourceBundle
        }
        return bundle
    }

    static func image(named baseName: String,
                      for traitCollection: UITraitCollection? = nil) -> UIImage? {
        let isDark = (traitCollection ?? UITraitCollection.current).userInterfaceStyle == .dark
        let suffix = isDark ? "~dark" : "~light"
        let fileName = baseName + suffix
        let bundle = self.bundle()

        // 1) RNTurboImagePickerAssets 번들 내에서 조회
        if let path = bundle.path(forResource: fileName, ofType: "webp") ??
                      bundle.path(forResource: fileName, ofType: "webp", inDirectory: "ToolbarIcons"),
           let img = UIImage(contentsOfFile: path) {
            return img
        }

        // 2) 기존 메인 번들 직접 조회 (하위 호환성)
        if let path = Bundle.main.path(forResource: fileName, ofType: "webp",
                                       inDirectory: "ToolbarIcons"),
           let img = UIImage(contentsOfFile: path) {
            return img
        }
        // 3) xcassets 방식 fallback
        if let img = UIImage(named: baseName, in: bundle, compatibleWith: nil) { return img }
        if let img = UIImage(named: baseName) { return img }
        // 4) SF Symbol fallback은 호출부에서 처리
        return nil
    }
}


public struct FilterState {
    public var filterId: String
    public var intensity: CGFloat
    
    public init(filterId: String, intensity: CGFloat) {
        self.filterId = filterId
        self.intensity = intensity
    }
}

public class ImageEditorViewController: UIViewController {
    public var languageCode: String = "en"

    public init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    public var allAssets: [PHAsset] = []
    public var standaloneImage: UIImage?

    public var currentIndex: Int = 0
    public var filterStates: [Int: FilterState] = [:]
    public var croppedImages: [Int: UIImage] = [:]

    /// true이면 좌우 스와이프 비활성화 + 카운터 숨김 (1장 편집 모드)
    public var singlePhotoMode: Bool = false

    /// true이면 크롭 버튼을 숨김 (프로필 모드 등 크롭이 이미 완료된 경우)
    public var disableCrop: Bool = false

    /// 멀티+편집 모드: 갤러리에서 주입되는 선택 상태
    public var selectedAssets: [PHAsset] = []
    /// 선택 토글 시 갤러리에 알림 (asset, 선택 여부)
    public var onSelectionToggled: ((PHAsset, Bool) -> Void)?
    public var onEditDeleted: ((PHAsset) -> Void)?
    
    // Callbacks
    public var onConfirm: ((PHAsset?, UIImage?, FilterState, String) -> Void)?
    public var onConfirmMulti: (([PHAsset], [PHAsset: UIImage], [PHAsset: FilterState]) -> Void)?
    public var onCancel: (() -> Void)?
    
    /// Live sticker components per page index — persisted across cell reuse
    private var stickersByIndex: [Int: [TextStickerView]] = [:]
    
    // Thumbnail generator
    private var filterThumbnailCache: [String: UIImage] = [:]
    private var currentThumbnailOriginal: UIImage?
    private let filterQueue = DispatchQueue(label: "com.rnturboimagepicker.filterQueue", qos: .userInteractive)

    // MARK: - Selection Badge UI

    /// 우측 상단 선택 배지 (선택 안 됨: 빈 원, 선택됨: 리도색 원+번호)
    private lazy var selectionBadgeContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true   // 멀티+편집 모드에서만 표시
        let tap = UITapGestureRecognizer(target: self, action: #selector(selectionBadgeTapped))
        v.addGestureRecognizer(tap)
        return v
    }()

    private lazy var selectionEmptyCircle: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0.6, alpha: 0.8)
        v.layer.borderWidth = 1.0
        v.layer.borderColor = UIColor(white: 0.8, alpha: 0.9).cgColor
        v.layer.cornerRadius = 18
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isUserInteractionEnabled = false
        return v
    }()

    private lazy var selectionFilledCircle: UIView = {
        let v = UIView()
        v.backgroundColor = self.themeColor ?? UIColor(red: 236/255, green: 73/255, blue: 38/255, alpha: 1.0)
        v.layer.borderWidth = 0
        v.layer.borderColor = UIColor.clear.cgColor
        v.layer.cornerRadius = 18
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        v.isUserInteractionEnabled = false
        return v
    }()

    private lazy var selectionNumberLabel: UILabel = {
        let l = UILabel()
        l.textColor = .white
        l.font = .systemFont(ofSize: 15, weight: .bold)
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isUserInteractionEnabled = false
        return l
    }()

    public var themeColor: UIColor?

    // MARK: - Shared Cache & Caching Manager

    /// 셀 간 공유 이미지 캐시 — prefetch 결과를 cellForItem에서 재사용
    private let imageCache = NSCache<NSNumber, UIImage>()
    private let cachingManager = PHCachingImageManager()

    /// 전체 화면 이미지 사이즈 (포인트 × 스케일)
    private lazy var fullPixelSize: CGSize = {
        let s = UIScreen.main.scale
        let b = UIScreen.main.bounds
        return CGSize(width: b.width * s, height: b.height * s)
    }()

    private let imageRequestOptions: PHImageRequestOptions = {
        let o = PHImageRequestOptions()
        o.deliveryMode = .opportunistic
        o.isNetworkAccessAllowed = true
        o.resizeMode = .fast
        return o
    }()

    // MARK: - UI

    lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.isPagingEnabled = true
        cv.showsHorizontalScrollIndicator = false
        cv.backgroundColor = .editorBackground
        cv.bounces = true
        cv.dataSource = self
        cv.delegate = self
        cv.prefetchDataSource = self
        cv.register(EditorPageCell.self, forCellWithReuseIdentifier: EditorPageCell.id)
        cv.translatesAutoresizingMaskIntoConstraints = false
        // 초기에는 숨김 — 레이아웃 + 스크롤 완료 후 표시
        cv.alpha = 0
        return cv
    }()

    
    // MARK: - Filter UI
    
    private var initialFilterState: FilterState?
    
    private lazy var filterContainerView: UIView = {
        let v = UIView()
        v.backgroundColor = .clear
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    private lazy var filterActionBarView: UIView = {
        let v = UIView()
        v.backgroundColor = .editorBarBackground
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    private lazy var filterCloseButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        btn.setImage(UIImage(systemName: "xmark", withConfiguration: cfg), for: .normal)
        btn.tintColor = .editorForeground
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(filterCloseTapped), for: .touchUpInside)
        return btn
    }()
    
    private lazy var filterCheckButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        btn.setImage(UIImage(systemName: "checkmark", withConfiguration: cfg), for: .normal)
        btn.tintColor = .editorForeground
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(filterCheckTapped), for: .touchUpInside)
        return btn
    }()
    
    private lazy var filterTitleLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = Localizer.getString(key: "effect", languageCode: languageCode)
        lbl.font = .systemFont(ofSize: 16, weight: .semibold)
        lbl.textColor = .editorForeground
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()
    
    private lazy var filterListBackgroundView: UIView = {
        let v = UIView()
        v.backgroundColor = .editorBarBackground
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    private lazy var sliderBackgroundView: UIView = {
        let v = UIView()
        v.backgroundColor = .editorBarBackground
        v.layer.cornerRadius = 17
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    private lazy var tickStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.distribution = .equalSpacing
        sv.isUserInteractionEnabled = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        let color = self.themeColor ?? .systemYellow
        for _ in 0..<5 {
            let dot = UIView()
            dot.backgroundColor = color
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 2).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 6).isActive = true
            sv.addArrangedSubview(dot)
        }
        return sv
    }()
    
    private lazy var intensitySlider: UISlider = {
        let s = UISlider()
        s.minimumValue = 0
        s.maximumValue = 1
        s.value = 1.0
        s.minimumTrackTintColor = self.themeColor ?? .systemYellow
        s.maximumTrackTintColor = .editorSliderTrack
        s.translatesAutoresizingMaskIntoConstraints = false
        s.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        s.addTarget(self, action: #selector(sliderDidEndSliding(_:)), for: [.touchUpInside, .touchUpOutside])
        return s
    }()
    
    private lazy var filterCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 70, height: 82)
        layout.minimumLineSpacing = 4
        layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.dataSource = self
        cv.delegate = self
        cv.register(FilterThumbnailCell.self, forCellWithReuseIdentifier: FilterThumbnailCell.id)
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()
    
    private var isFilterActive = false {
        didSet {
            filterContainerView.isHidden = !isFilterActive
            updateUIForMode()
            if isFilterActive {
                let state = filterStates[currentIndex] ?? FilterState(filterId: "original", intensity: 1.0)
                intensitySlider.value = Float(state.intensity)
                sliderBackgroundView.isHidden = (state.filterId == "original")
                generateThumbnailsForCurrent()
            }
        }
    }

    private lazy var topBarView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.editorOverlay
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var backButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.setImage(UIImage(named: "ic_back"), for: .normal)
        btn.imageView?.contentMode = .scaleAspectFit
        btn.contentHorizontalAlignment = .fill
        btn.contentVerticalAlignment = .fill
        btn.imageEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var counterLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = .systemFont(ofSize: 16, weight: .semibold)
        lbl.textColor = .editorForeground
        lbl.textAlignment = .center
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()
    

    private lazy var sendButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle(Localizer.getString(key: "send", languageCode: languageCode), for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        btn.setTitleColor(.editorForeground, for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var bottomBarView: UIView = {
        let v = UIView()
        v.backgroundColor = .editorBarBackground
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // MARK: - Text Mode UI

    private lazy var textModeTopBar: UIView = {
        let v = UIView()
        v.backgroundColor = .clear
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    private lazy var textAddButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        btn.setImage(UIImage(systemName: "plus", withConfiguration: cfg), for: .normal)
        btn.tintColor = .editorForeground
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(textAddTapped), for: .touchUpInside)
        return btn
    }()
    
    private lazy var textTrashButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        btn.setImage(UIImage(systemName: "trash", withConfiguration: cfg), for: .normal)
        btn.tintColor = .editorForeground
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(textTrashTapped), for: .touchUpInside)
        return btn
    }()
    
    private lazy var textModeBottomBar: UIView = {
        let v = UIView()
        v.backgroundColor = .editorBarBackground
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    private lazy var textModeCancelBtn: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        btn.setImage(UIImage(systemName: "xmark", withConfiguration: cfg), for: .normal)
        btn.tintColor = .editorForeground
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(textCancelTapped), for: .touchUpInside)
        return btn
    }()
    
    private lazy var textModeTitle: UILabel = {
        let lbl = UILabel()
        lbl.text = Localizer.getString(key: "text", languageCode: languageCode)
        lbl.font = .systemFont(ofSize: 16, weight: .semibold)
        lbl.textColor = .editorForeground
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()
    
    private lazy var textModeConfirmBtn: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        btn.setImage(UIImage(systemName: "checkmark", withConfiguration: cfg), for: .normal)
        btn.tintColor = .editorForeground
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(textConfirmTapped), for: .touchUpInside)
        return btn
    }()
    
    private var isEmojiModeActive = false {
        didSet {
            updateUIForMode()
            setAllStickersEditingMode(isTextModeActive || isEmojiModeActive)
            updateAllStickersInteractivity()
        }
    }
    
    private var isTextModeActive = false {
        didSet {
            updateUIForMode()
            textModeTopBar.isHidden = !isTextModeActive
            textModeBottomBar.isHidden = !isTextModeActive
            
            // Switch sticker mode: editing=counter-scaled (fixed visual size), viewing=natural zoom
            setAllStickersEditingMode(isTextModeActive || isEmojiModeActive)
            updateAllStickersInteractivity()
            
            if isTextModeActive {
                deselectAllStickers()
            }
        }
    }
    
    private func updateUIForMode() {
        let isAnyModeActive = isTextModeActive || isEmojiModeActive
        topBarView.isHidden = isAnyModeActive || isFilterActive
        bottomBarView.isHidden = isAnyModeActive
        collectionView.isScrollEnabled = !isAnyModeActive
        
        if !singlePhotoMode {
            selectionBadgeContainer.isHidden = isAnyModeActive
        }
    }
    
    private func updateAllStickersInteractivity() {
        for stickers in stickersByIndex.values {
            for sticker in stickers {
                if sticker.isEmojiSticker {
                    sticker.isUserInteractionEnabled = isEmojiModeActive
                } else {
                    sticker.isUserInteractionEnabled = isTextModeActive
                }
            }
        }
    }
    
    struct TextStickerState {
        let text: String
        let textColor: UIColor
        let transform: CGAffineTransform
        let center: CGPoint
        let bounds: CGRect
    }
    private var preTextModeStickerStates: [TextStickerView: TextStickerState] = [:]
    private var preTextModeStickerList: [TextStickerView] = []
    
    private func saveStickerStates() {
        preTextModeStickerStates.removeAll()
        preTextModeStickerList.removeAll()
        
        guard let cell = currentEditorCell else { return }
        for view in cell.stickerContainerView.subviews {
            if let sticker = view as? TextStickerView {
                preTextModeStickerList.append(sticker)
                preTextModeStickerStates[sticker] = TextStickerState(
                    text: sticker.text,
                    textColor: sticker.textColor,
                    transform: sticker.transform,
                    center: sticker.center,
                    bounds: sticker.bounds
                )
            }
        }
    }
    
    private func restoreStickerStates() {
        guard let cell = currentEditorCell else { return }
        
        // Remove stickers that were added during this session or revert modifications
        for view in cell.stickerContainerView.subviews {
            if let sticker = view as? TextStickerView {
                if let state = preTextModeStickerStates[sticker] {
                    sticker.text = state.text
                    sticker.textColor = state.textColor
                    sticker.transform = state.transform
                    sticker.center = state.center
                    sticker.bounds = state.bounds
                } else {
                    sticker.removeFromSuperview()
                }
            }
        }
        
        // Restore stickers that were deleted during this session
        for sticker in preTextModeStickerList {
            if sticker.superview == nil {
                cell.stickerContainerView.addSubview(sticker)
                if let state = preTextModeStickerStates[sticker] {
                    sticker.text = state.text
                    sticker.textColor = state.textColor
                    sticker.transform = state.transform
                    sticker.center = state.center
                    sticker.bounds = state.bounds
                }
            }
        }
    }
    
    private func beginTextMode() {
        if isTextModeActive { return }
        isTextModeActive = true
        
        saveStickerStates()
        
    }



    private lazy var toolbarStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.distribution = .fillEqually
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    // MARK: - Layout State

    private var hasAppliedInitialScroll = false
    private var lastLayoutSize: CGSize = .zero
    private weak var topBarGradientLayer: CAGradientLayer?

    private func refreshTopBarGradient() {
        let isDark = traitCollection.userInterfaceStyle != .light
        // 라이트 모드: 그라데이션 완전히 숨김
        // 다크 모드: 검정→투명 그라데이션 표시
        if isDark {
            topBarGradientLayer?.opacity = 1.0
            topBarGradientLayer?.colors = [
                UIColor.black.withAlphaComponent(0.75).cgColor,
                UIColor.black.withAlphaComponent(0.45).cgColor,
                UIColor.clear.cgColor
            ]
        } else {
            topBarGradientLayer?.opacity = 0.0
        }
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .editorBackground

        imageCache.countLimit = 30
        imageCache.totalCostLimit = 200 * 1024 * 1024
        cachingManager.allowsCachingHighQualityImages = true

        setupCollectionView()
        setupDismissPanGesture()
        setupTopBar()
        setupBottomBar()
        updateCounter()

        // 1장 편집 모드: 스와이프 잠금 + 카운터 숨김 + 백버튼을 취소 텍스트로 변경
        if singlePhotoMode {
            collectionView.isScrollEnabled = false
            counterLabel.isHidden = true
            
            backButton.setImage(nil, for: .normal)
            backButton.setTitle(Localizer.getString(key: "cancel", languageCode: languageCode), for: .normal)
            backButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            backButton.setTitleColor(.editorForeground, for: .normal)
            backButton.contentHorizontalAlignment = .left
            backButton.imageEdgeInsets = .zero
            
            // 너비 제약조건 변경 (텍스트가 다 보이도록)
            if let widthConstraint = backButton.constraints.first(where: { $0.firstAttribute == .width }) {
                widthConstraint.constant = 60
            }
        }

        // 멀티+편집: 선택 배지 설정
        if !singlePhotoMode {
            setupSelectionBadge()
        }

        // 현재 선택 이미지를 먼저 캐시에 적재
        warmUpInitialCache()
        updateSendButtonState()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        // 다크/라이트 전환 시 ToolbarIcons 파일명 suffix(~dark/~light)에 맞게 이미지 재로드
        let assetNames = ["ic_editor_effect", "ic_editor_crop", "ic_editor_text",
                          "ic_editor_emoji", "ic_editor_drawing"]
        for (idx, btn) in toolbarStack.arrangedSubviews.compactMap({ $0 as? UIButton }).enumerated() {
            if idx < assetNames.count,
               let img = AssetBundle.image(named: assetNames[idx], for: traitCollection) {
                btn.setImage(img, for: .normal)
            }
        }
        // gradient 색상 갱신
        refreshTopBarGradient()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let size = collectionView.bounds.size
        guard size.width > 0, size.height > 0 else { return }

        // 사이즈 변경 시에만 레이아웃 갱신
        if size != lastLayoutSize {
            lastLayoutSize = size
            if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
                layout.itemSize = size
                layout.invalidateLayout()
            }
        }

        // 최초 1회: 올바른 인덱스로 스크롤 후 표시
        if !hasAppliedInitialScroll {
            hasAppliedInitialScroll = true
            collectionView.layoutIfNeeded()
            if currentIndex > 0 {
                collectionView.contentOffset = CGPoint(x: size.width * CGFloat(currentIndex), y: 0)
            }
            // 스크롤 확정 후 부드럽게 노출
            UIView.animate(withDuration: 0.15) {
                self.collectionView.alpha = 1
            }
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cachingManager.stopCachingImagesForAllAssets()
    }

    deinit {
        cachingManager.stopCachingImagesForAllAssets()
        imageCache.removeAllObjects()
    }

    // MARK: - Initial Cache Warm-up

    /// 선택 사진 ± 앞뒤 2장을 동기적으로 미리 로드
    private func warmUpInitialCache() {
        if standaloneImage != nil { return }
        guard allAssets.count > 0 else { return }
        let range = max(0, currentIndex - 2)...min(allAssets.count - 1, currentIndex + 2)
        for idx in range {
            let key = NSNumber(value: idx)
            guard imageCache.object(forKey: key) == nil else { continue }
            let asset = allAssets[idx]
            cachingManager.requestImage(
                for: asset, targetSize: fullPixelSize,
                contentMode: .aspectFit, options: imageRequestOptions
            ) { [weak self] img, info in
                guard let self = self, let img = img else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    self.imageCache.setObject(img, forKey: key)
                }
            }
        }
    }

    // MARK: - Setup

    private func setupCollectionView() {
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupTopBar() {
        view.addSubview(topBarView)
        [backButton, counterLabel, sendButton].forEach { topBarView.addSubview($0) }
        NSLayoutConstraint.activate([
            // status bar 영역까지 포함
            topBarView.topAnchor.constraint(equalTo: view.topAnchor),
            topBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBarView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 52),
            // 버튼/라벨은 safe area 기준
            backButton.leadingAnchor.constraint(equalTo: topBarView.leadingAnchor, constant: 12),
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),
            
            counterLabel.centerXAnchor.constraint(equalTo: topBarView.centerXAnchor),
            counterLabel.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            
            sendButton.trailingAnchor.constraint(equalTo: topBarView.trailingAnchor, constant: -16),
            sendButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
        ])
        
        view.addSubview(textModeTopBar)
        [textAddButton, textTrashButton].forEach { textModeTopBar.addSubview($0) }
        NSLayoutConstraint.activate([
            textModeTopBar.topAnchor.constraint(equalTo: view.topAnchor),
            textModeTopBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textModeTopBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textModeTopBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 52),
            
            textAddButton.leadingAnchor.constraint(equalTo: textModeTopBar.leadingAnchor, constant: 12),
            textAddButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            textAddButton.widthAnchor.constraint(equalToConstant: 44),
            textAddButton.heightAnchor.constraint(equalToConstant: 44),
            
            textTrashButton.trailingAnchor.constraint(equalTo: textModeTopBar.trailingAnchor, constant: -16),
            textTrashButton.centerYAnchor.constraint(equalTo: textAddButton.centerYAnchor),
            textTrashButton.widthAnchor.constraint(equalToConstant: 44),
            textTrashButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        let g = CAGradientLayer()
        topBarGradientLayer = g
        refreshTopBarGradient()
        g.locations = [0, 0.6, 1.0]
        g.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 140)
        topBarView.layer.insertSublayer(g, at: 0)
    }

    private func setupBottomBar() {
        view.addSubview(bottomBarView)
        bottomBarView.addSubview(toolbarStack)
        NSLayoutConstraint.activate([
            bottomBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            toolbarStack.topAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: 4),
            toolbarStack.leadingAnchor.constraint(equalTo: bottomBarView.leadingAnchor),
            toolbarStack.trailingAnchor.constraint(equalTo: bottomBarView.trailingAnchor),
            toolbarStack.heightAnchor.constraint(equalToConstant: 56),
            toolbarStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        
        view.addSubview(textModeBottomBar)
        [textModeCancelBtn, textModeTitle, textModeConfirmBtn].forEach { textModeBottomBar.addSubview($0) }
        NSLayoutConstraint.activate([
            textModeBottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textModeBottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textModeBottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textModeBottomBar.topAnchor.constraint(equalTo: bottomBarView.topAnchor),
            
            textModeCancelBtn.leadingAnchor.constraint(equalTo: textModeBottomBar.leadingAnchor, constant: 16),
            textModeCancelBtn.centerYAnchor.constraint(equalTo: textModeBottomBar.topAnchor, constant: 28),
            textModeCancelBtn.widthAnchor.constraint(equalToConstant: 44),
            textModeCancelBtn.heightAnchor.constraint(equalToConstant: 44),
            
            textModeTitle.centerXAnchor.constraint(equalTo: textModeBottomBar.centerXAnchor),
            textModeTitle.centerYAnchor.constraint(equalTo: textModeCancelBtn.centerYAnchor),
            
            textModeConfirmBtn.trailingAnchor.constraint(equalTo: textModeBottomBar.trailingAnchor, constant: -16),
            textModeConfirmBtn.centerYAnchor.constraint(equalTo: textModeCancelBtn.centerYAnchor),
            textModeConfirmBtn.widthAnchor.constraint(equalToConstant: 44),
            textModeConfirmBtn.heightAnchor.constraint(equalToConstant: 44)
        ])
        // (아이콘이름, 에셋카탈로그키) 매핑
        let toolIcons: [(tag: Int, assetName: String)] = [
            (0, "ic_editor_effect"),
            (1, "ic_editor_crop"),
            (2, "ic_editor_text"),
            (3, "ic_editor_emoji"),
            (4, "ic_editor_drawing")
        ]
        for item in toolIcons {
            let btn = UIButton(type: .custom)
            // 크롭 버튼은 disableCrop 일 때 숨김
            if item.tag == 1 && disableCrop {
                // 자리를 차지하지 않도록 완전히 제거
                continue
            }
            if let img = AssetBundle.image(named: item.assetName) {
                btn.setImage(img.withRenderingMode(.alwaysTemplate), for: .normal)
                btn.tintColor = .editorForeground
            } else {
                let fallbacks = ["camera.filters", "crop", "textformat", "face.smiling", "pencil.tip"]
                let cfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
                btn.setImage(UIImage(systemName: fallbacks[item.tag], withConfiguration: cfg), for: .normal)
                btn.tintColor = .editorForeground
            }
            btn.imageView?.contentMode = .scaleAspectFit
            btn.imageEdgeInsets = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
            btn.tag = item.tag
            btn.addTarget(self, action: #selector(toolbarButtonTapped(_:)), for: .touchUpInside)
            toolbarStack.addArrangedSubview(btn)
        }
        
        // Setup Filter Container
        view.addSubview(filterContainerView)
        filterContainerView.addSubview(filterListBackgroundView)
        filterContainerView.addSubview(sliderBackgroundView)
        sliderBackgroundView.addSubview(tickStackView)
        sliderBackgroundView.addSubview(intensitySlider)
        filterContainerView.addSubview(filterCollectionView)
        filterContainerView.addSubview(filterActionBarView)
        filterActionBarView.addSubview(filterCloseButton)
        filterActionBarView.addSubview(filterTitleLabel)
        filterActionBarView.addSubview(filterCheckButton)
        
        NSLayoutConstraint.activate([
            filterContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            filterActionBarView.leadingAnchor.constraint(equalTo: filterContainerView.leadingAnchor),
            filterActionBarView.trailingAnchor.constraint(equalTo: filterContainerView.trailingAnchor),
            filterActionBarView.topAnchor.constraint(equalTo: bottomBarView.topAnchor),
            filterActionBarView.bottomAnchor.constraint(equalTo: filterContainerView.bottomAnchor),
            
            filterCloseButton.leadingAnchor.constraint(equalTo: filterActionBarView.leadingAnchor, constant: 16),
            filterCloseButton.centerYAnchor.constraint(equalTo: filterActionBarView.topAnchor, constant: 28),
            filterCloseButton.widthAnchor.constraint(equalToConstant: 44),
            filterCloseButton.heightAnchor.constraint(equalToConstant: 44),
            
            filterTitleLabel.centerXAnchor.constraint(equalTo: filterActionBarView.centerXAnchor),
            filterTitleLabel.centerYAnchor.constraint(equalTo: filterCloseButton.centerYAnchor),
            
            filterCheckButton.trailingAnchor.constraint(equalTo: filterActionBarView.trailingAnchor, constant: -16),
            filterCheckButton.centerYAnchor.constraint(equalTo: filterCloseButton.centerYAnchor),
            filterCheckButton.widthAnchor.constraint(equalToConstant: 44),
            filterCheckButton.heightAnchor.constraint(equalToConstant: 44),
            
            filterListBackgroundView.leadingAnchor.constraint(equalTo: filterContainerView.leadingAnchor),
            filterListBackgroundView.trailingAnchor.constraint(equalTo: filterContainerView.trailingAnchor),
            filterListBackgroundView.bottomAnchor.constraint(equalTo: filterActionBarView.topAnchor),
            filterListBackgroundView.topAnchor.constraint(equalTo: filterCollectionView.topAnchor, constant: -8),
            
            sliderBackgroundView.topAnchor.constraint(equalTo: filterContainerView.topAnchor, constant: 4),
            sliderBackgroundView.centerXAnchor.constraint(equalTo: filterContainerView.centerXAnchor),
            sliderBackgroundView.widthAnchor.constraint(equalTo: filterContainerView.widthAnchor, constant: -80),
            sliderBackgroundView.heightAnchor.constraint(equalToConstant: 34),
            
            intensitySlider.leadingAnchor.constraint(equalTo: sliderBackgroundView.leadingAnchor, constant: 16),
            intensitySlider.trailingAnchor.constraint(equalTo: sliderBackgroundView.trailingAnchor, constant: -16),
            intensitySlider.centerYAnchor.constraint(equalTo: sliderBackgroundView.centerYAnchor),
            
            tickStackView.leadingAnchor.constraint(equalTo: intensitySlider.leadingAnchor, constant: 14),
            tickStackView.trailingAnchor.constraint(equalTo: intensitySlider.trailingAnchor, constant: -14),
            tickStackView.centerYAnchor.constraint(equalTo: intensitySlider.centerYAnchor),
            
            filterCollectionView.topAnchor.constraint(equalTo: sliderBackgroundView.bottomAnchor, constant: 16),
            filterCollectionView.leadingAnchor.constraint(equalTo: filterContainerView.leadingAnchor),
            filterCollectionView.trailingAnchor.constraint(equalTo: filterContainerView.trailingAnchor),
            filterCollectionView.bottomAnchor.constraint(equalTo: filterActionBarView.topAnchor, constant: -8),
            filterCollectionView.heightAnchor.constraint(equalToConstant: 90)
        ])
    }

    // MARK: - Helpers

    private func updateCounter() {
        counterLabel.text = "\(currentIndex + 1) / \(standaloneImage != nil ? 1 : allAssets.count)"
        updateSelectionBadge()
    }

    /// 다중+편집 모드 선택 배지 레이아웃 초기화
    private func setupSelectionBadge() {
        selectionBadgeContainer.isHidden = false
        selectionBadgeContainer.addSubview(selectionEmptyCircle)
        selectionBadgeContainer.addSubview(selectionFilledCircle)
        selectionFilledCircle.addSubview(selectionNumberLabel)

        view.addSubview(selectionBadgeContainer)
        NSLayoutConstraint.activate([
            selectionBadgeContainer.widthAnchor.constraint(equalToConstant: 64),
            selectionBadgeContainer.heightAnchor.constraint(equalToConstant: 64),
            selectionBadgeContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            // 전송 버튼과 겹치지 않도록 아래로 이동 (topBar 아래쪽)
            selectionBadgeContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),

            selectionEmptyCircle.widthAnchor.constraint(equalToConstant: 36),
            selectionEmptyCircle.heightAnchor.constraint(equalToConstant: 36),
            selectionEmptyCircle.centerXAnchor.constraint(equalTo: selectionBadgeContainer.centerXAnchor),
            selectionEmptyCircle.centerYAnchor.constraint(equalTo: selectionBadgeContainer.centerYAnchor),

            selectionFilledCircle.widthAnchor.constraint(equalToConstant: 36),
            selectionFilledCircle.heightAnchor.constraint(equalToConstant: 36),
            selectionFilledCircle.centerXAnchor.constraint(equalTo: selectionBadgeContainer.centerXAnchor),
            selectionFilledCircle.centerYAnchor.constraint(equalTo: selectionBadgeContainer.centerYAnchor),

            selectionNumberLabel.leadingAnchor.constraint(equalTo: selectionFilledCircle.leadingAnchor),
            selectionNumberLabel.trailingAnchor.constraint(equalTo: selectionFilledCircle.trailingAnchor),
            selectionNumberLabel.topAnchor.constraint(equalTo: selectionFilledCircle.topAnchor),
            selectionNumberLabel.bottomAnchor.constraint(equalTo: selectionFilledCircle.bottomAnchor),
        ])
        updateSelectionBadge()
    }

    private func updateSelectionBadge() {
        guard currentIndex < allAssets.count else { return }
        let asset = allAssets[currentIndex]
        if let idx = selectedAssets.firstIndex(of: asset) {
            // 선택됨: 제외된 원 + 번호
            selectionEmptyCircle.isHidden = true
            selectionFilledCircle.isHidden = false
            selectionNumberLabel.text = "\(idx + 1)"
        } else {
            // 선택 안됨: 빈 원
            selectionEmptyCircle.isHidden = false
            selectionFilledCircle.isHidden = true
        }
    }

    @objc private func selectionBadgeTapped() {
        guard currentIndex < allAssets.count else { return }
        let asset = allAssets[currentIndex]
        let isSelected = selectedAssets.contains(asset)
        
        let hasEdits = croppedImages[currentIndex] != nil || 
                       (filterStates[currentIndex] != nil && filterStates[currentIndex]!.filterId != "original") ||
                       (stickersByIndex[currentIndex] != nil && !stickersByIndex[currentIndex]!.isEmpty)
        
        if isSelected && hasEdits {
            let title = Localizer.getString(key: "delete_edits_title", languageCode: languageCode)
            let message = Localizer.getString(key: "delete_edits_message", languageCode: languageCode)
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Localizer.getString(key: "no", languageCode: languageCode), style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: Localizer.getString(key: "yes", languageCode: languageCode), style: .destructive) { [weak self] _ in
                guard let self = self else { return }
                // 편집 데이터 삭제
                self.croppedImages.removeValue(forKey: self.currentIndex)
                self.filterStates.removeValue(forKey: self.currentIndex)
                self.stickersByIndex.removeValue(forKey: self.currentIndex)
                
                // 원본으로 UI 복구
                if let cell = self.currentEditorCell {
                    // cell에 원본 로딩 재요청 또는 캐시된 원본 적용
                    cell.originalImage = nil // 초기화
                    cell.configure(
                        with: asset,
                        index: self.currentIndex,
                        targetSize: self.fullPixelSize,
                        cache: self.imageCache,
                        manager: self.cachingManager,
                        options: self.imageRequestOptions,
                        collectionView: self.collectionView,
                        filterState: FilterState(filterId: "original", intensity: 1.0),
                        croppedImage: nil,
                        onImageLoaded: nil
                    )
                    // 기존 스티커 제거
                    for view in cell.stickerContainerView.subviews {
                        view.removeFromSuperview()
                    }
                }
                
                // 외부(GalleryVC)에 편집 삭제 알림
                self.onEditDeleted?(asset)
                
                // 선택 해제 로직
                self.performSelectionToggle(asset: asset, isSelected: isSelected)
            })
            present(alert, animated: true)
        } else {
            performSelectionToggle(asset: asset, isSelected: isSelected)
        }
    }
    
    private func performSelectionToggle(asset: PHAsset, isSelected: Bool) {
        onSelectionToggled?(asset, !isSelected)
        if isSelected {
            selectedAssets.removeAll { $0 == asset }
        } else {
            selectedAssets.append(asset)
        }
        UIView.animate(withDuration: 0.15) {
            self.updateSelectionBadge()
        }
    }

    private func autoSelectCurrentPhoto() {
        if singlePhotoMode { return }
        if standaloneImage != nil { return }
        guard currentIndex >= 0 && currentIndex < allAssets.count else { return }
        let asset = allAssets[currentIndex]
        if !selectedAssets.contains(asset) {
            selectedAssets.append(asset)
            onSelectionToggled?(asset, true)
            UIView.animate(withDuration: 0.15) {
                self.updateSelectionBadge()
            }
        }
        updateSendButtonState()
    }

    private func updateSendButtonState() {
        if singlePhotoMode {
            sendButton.isHidden = false
            sendButton.setTitle(Localizer.getString(key: "send", languageCode: languageCode), for: .normal)
        } else {
            var hasAnyEdits = false
            if !filterStates.isEmpty { hasAnyEdits = true }
            else if stickersByIndex.values.contains(where: { !$0.isEmpty }) { hasAnyEdits = true }
            else if !croppedImages.isEmpty { hasAnyEdits = true }
            else {
                for cell in collectionView.visibleCells {
                    if let editorCell = cell as? EditorPageCell {
                        if editorCell.stickerContainerView.subviews.count > 0 {
                            hasAnyEdits = true
                            break
                        }
                    }
                }
            }
            
            if hasAnyEdits {
                sendButton.isHidden = false
                sendButton.setTitle(Localizer.getString(key: "editor_apply", languageCode: languageCode), for: .normal)
            } else {
                sendButton.isHidden = true
            }
        }
    }

    private func resetFilterButton() {
        isFilterActive = false
        filterContainerView.isHidden = true
        if let filterBtn = toolbarStack.arrangedSubviews.first as? UIButton {
            filterBtn.alpha = 1.0
            filterBtn.tintColor = .editorForeground
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut, animations: {
                filterBtn.transform = .identity
            }, completion: nil)
        }
    }

    // MARK: - Filter Actions
    
    @objc private func filterCloseTapped() {
        if let state = initialFilterState {
            filterStates[currentIndex] = state
            if let cell = currentEditorCell {
                cell.applyFilterFinal(state)
            }
        }
        resetFilterButton()
    }
    
    @objc private func filterCheckTapped() {
        guard let cell = currentEditorCell, let filtered = cell.imageView.image else {
            resetFilterButton()
            return
        }
        
        // 필터를 이미지에 구워서 새 원본으로 설정
        cell.originalImage = filtered
        croppedImages[currentIndex] = filtered
        filterStates[currentIndex] = FilterState(filterId: "original", intensity: 1.0)
        cell.applyFilterFinal(filterStates[currentIndex]!)
        
        resetFilterButton()
    }
    
    @objc private func toolbarButtonTapped(_ sender: UIButton) {
        if sender.tag == 0 { // Filters
            if !isFilterActive {
                initialFilterState = filterStates[currentIndex] ?? FilterState(filterId: "original", intensity: 1.0)
                isFilterActive = true
                filterContainerView.isHidden = false
                sender.alpha = 1.0
                sender.tintColor = themeColor ?? .systemYellow
                UIView.animate(withDuration: 0.2) {
                    sender.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
                }
                
                generateThumbnailsForCurrent()
                let state = filterStates[currentIndex] ?? FilterState(filterId: "original", intensity: 1.0)
                intensitySlider.value = Float(state.intensity)
                sliderBackgroundView.isHidden = (state.filterId == "original")
                filterCollectionView.reloadData()
            }
        } else if sender.tag == 1 { // Crop
            resetFilterButton()
            guard let cell = currentEditorCell,
                  let orig = cell.originalImage else { return }
            
            if !singlePhotoMode { selectionBadgeContainer.isHidden = true }
            
            let cropVC = CropViewController(image: orig)
            CropViewController.currentLanguageCode = self.languageCode
            cropVC.modalTransitionStyle = .crossDissolve
            cropVC.onCancel = { [weak self] in
                self?.updateUIForMode()
            }
            cropVC.onCropComplete = { [weak self] cropped in
                guard let self = self else { return }
                self.croppedImages[self.currentIndex] = cropped
                cell.originalImage = cropped
                self.autoSelectCurrentPhoto()
                
                let state = self.filterStates[self.currentIndex] ?? FilterState(filterId: "original", intensity: 1.0)
                cell.applyFilterFinal(state)
                self.updateUIForMode()
            }
            self.present(cropVC, animated: true)
        } else if sender.tag == 2 { // Text
            resetFilterButton()
            beginTextMode()
            openTextInput()
        } else if sender.tag == 3 { // Emoji
            resetFilterButton()
            openEmojiPicker()
        } else if sender.tag == 4 { // Drawing
            resetFilterButton()
            guard let cell = currentEditorCell else { return }

            // ── 스티커가 있으면 먼저 이미지에 bake하고 그 결과를 그리기 베이스로 사용 ──
            // 이렇게 해야 그리기 화면에서 이전에 추가한 텍스트/이모지도 표시됨
            let baseForDrawing: UIImage
            if let bakedWithStickers = bakeStickersIntoImage(cell: cell) {
                // 스티커 있음: 필터 + 스티커가 합쳐진 이미지를 그리기 베이스로 사용
                baseForDrawing = bakedWithStickers

                // 스티커는 이미지에 베이킹되었으므로 UIView 레이어에서 제거
                cell.stickerContainerView.subviews
                    .compactMap { $0 as? TextStickerView }
                    .forEach { $0.removeFromSuperview() }
                stickersByIndex.removeValue(forKey: currentIndex)

                // originalImage 및 filterState도 bake 결과로 업데이트
                cell.originalImage = bakedWithStickers
                let resetState = FilterState(filterId: "original", intensity: 1.0)
                filterStates[currentIndex] = resetState
                cell.applyFilterFinal(resetState)
            } else {
                // 스티커 없음: 현재 화면에 표시된 이미지(필터 적용 상태)를 그대로 사용
                guard let img = cell.imageView.image ?? cell.originalImage else { return }
                baseForDrawing = img
            }

            if !singlePhotoMode { selectionBadgeContainer.isHidden = true }

            let drawingVC = DrawingViewController(image: baseForDrawing)
            if let tc = themeColor {
                drawingVC.themeColor = tc
            }
            drawingVC.onCancel = { [weak self] in
                self?.updateUIForMode()
            }
            drawingVC.onDrawingComplete = { [weak self] merged in
                guard let self = self else { return }
                // 드로잉 결과(필터+스티커+그리기 합성)를 새 원본으로 설정
                self.croppedImages[self.currentIndex] = merged
                cell.originalImage = merged
                self.autoSelectCurrentPhoto()

                // 모든 편집이 이미지에 베이킹되었으므로 필터 상태를 'original'로 초기화
                let resetState = FilterState(filterId: "original", intensity: 1.0)
                self.filterStates[self.currentIndex] = resetState
                cell.applyFilterFinal(resetState)
                self.updateUIForMode()
            }
            self.present(drawingVC, animated: false)
        } else {
            resetFilterButton()
        }
    }

    // MARK: - Emoji Picker

    private func openEmojiPicker() {
        isEmojiModeActive = true
        saveStickerStates()
        
        let pickerVC = EmojiPickerViewController()
        pickerVC.themeColor = themeColor ?? .systemYellow

        // 이모지 탭 → 피커를 닫지 않고 스티커만 배치
        pickerVC.onEmojiSelected = { [weak self] emoji in
            self?.placeEmojiSticker(emoji)
        }
        // ✓ 버튼 → 피커 닫기 및 스티커 확정 (가이드 해제)
        pickerVC.onDone = { [weak self, weak pickerVC] in
            self?.deselectAllStickers()
            self?.preTextModeStickerStates.removeAll()
            self?.preTextModeStickerList.removeAll()
            self?.isEmojiModeActive = false
            self?.currentEditorCell?.zoomScrollView.setZoomScale(1.0, animated: true)
            pickerVC?.willMove(toParent: nil)
            pickerVC?.view.removeFromSuperview()
            pickerVC?.removeFromParent()
            // ✅ 이모지 확인 → 이미지에 bake (이후 편집에 누적 반영)
            self?.bakeAndClearCurrentStickers()
        }
        pickerVC.onCancel = { [weak self, weak pickerVC] in
            self?.restoreStickerStates()
            self?.deselectAllStickers()
            self?.preTextModeStickerStates.removeAll()
            self?.preTextModeStickerList.removeAll()
            self?.isEmojiModeActive = false
            self?.currentEditorCell?.zoomScrollView.setZoomScale(1.0, animated: true)
            pickerVC?.willMove(toParent: nil)
            pickerVC?.view.removeFromSuperview()
            pickerVC?.removeFromParent()
        }

        self.addChild(pickerVC)
        self.view.addSubview(pickerVC.view)
        pickerVC.view.frame = self.view.bounds
        pickerVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pickerVC.didMove(toParent: self)
    }

    private func placeEmojiSticker(_ emoji: String) {
        // 이모지는 텍스트 모드 진입 없이 바로 스티커로 배치
        guard let cell = currentEditorCell else { return }
        
        deselectAllStickers()

        let sticker = TextStickerView()
        sticker.delegate = self
        sticker.isEmojiSticker = true
        sticker.text = emoji
        sticker.isActive = true
        sticker.isUserInteractionEnabled = isEmojiModeActive
        sticker.isEditingMode = isTextModeActive || isEmojiModeActive

        let zoomScale = cell.zoomScrollView.zoomScale
        sticker.containerZoomScale = zoomScale

        let visibleRect = cell.zoomScrollView.convert(cell.zoomScrollView.bounds, to: cell.stickerContainerView)
        sticker.center = CGPoint(x: visibleRect.midX, y: visibleRect.midY)

        cell.stickerContainerView.addSubview(sticker)

        // 이모지 스티커 저장 (페이지 전환 시 유지)
        if stickersByIndex[currentIndex] == nil {
            stickersByIndex[currentIndex] = []
        }
        stickersByIndex[currentIndex]?.append(sticker)
        
        setAllStickersEditingMode(isTextModeActive || isEmojiModeActive)
        autoSelectCurrentPhoto()
    }

    
    // MARK: - Text Mode Actions
    
    private func openTextInput(initialText: String = "", initialColor: UIColor = .white, stickerToEdit: TextStickerView? = nil) {
        let textVC = TextInputViewController()
        textVC.languageCode = self.languageCode
        textVC.initialText = initialText
        textVC.initialColor = initialColor
        textVC.modalPresentationStyle = .overFullScreen
        textVC.modalTransitionStyle = .crossDissolve
        textVC.onConfirm = { [weak self] text, color in
            guard let self = self else { return }
            self.beginTextMode()
            
            guard let cell = self.currentEditorCell else { return }
            
            if let existingSticker = stickerToEdit {
                existingSticker.text = text
                existingSticker.textColor = color
                existingSticker.isActive = true
            } else {
                let sticker = TextStickerView()
                sticker.delegate = self
                sticker.text = text
                sticker.textColor = color
                sticker.isActive = true
                let zoomScale = cell.zoomScrollView.zoomScale
                sticker.containerZoomScale = zoomScale
                
                // Initial placement in center of the currently visible area
                let visibleRect = cell.zoomScrollView.convert(cell.zoomScrollView.bounds, to: cell.stickerContainerView)
                sticker.center = CGPoint(x: visibleRect.midX, y: visibleRect.midY)
                
                cell.stickerContainerView.addSubview(sticker)
                
                if self.stickersByIndex[self.currentIndex] == nil {
                    self.stickersByIndex[self.currentIndex] = []
                }
                self.stickersByIndex[self.currentIndex]?.append(sticker)
            }
            self.setAllStickersEditingMode(self.isTextModeActive || self.isEmojiModeActive)
            self.beginTextMode()
            self.autoSelectCurrentPhoto()
        }
        textVC.onCancel = { [weak self] in
            guard let self = self else { return }
            guard let cell = self.currentEditorCell else { return }
            
            // Exit editing mode if there are NO stickers
            let stickerCount = cell.stickerContainerView.subviews.compactMap { $0 as? TextStickerView }.count
            if stickerCount == 0 {
                self.textCancelTapped()
            }
        }
        present(textVC, animated: true)
    }
    
    @objc private func textAddTapped() {
        deselectAllStickers()
        openTextInput()
    }
    
    @objc private func textTrashTapped() {
        guard let cell = currentEditorCell else { return }
        for view in cell.stickerContainerView.subviews {
            if let sticker = view as? TextStickerView {
                sticker.removeFromSuperview()
            }
        }
        // Also clear persisted stickers for this page
        stickersByIndex[currentIndex] = nil
    }
    
    @objc private func textCancelTapped() {
        restoreStickerStates()
        
        deselectAllStickers()
        preTextModeStickerStates.removeAll()
        preTextModeStickerList.removeAll()
        isTextModeActive = false
    }
    
    @objc private func textConfirmTapped() {
        deselectAllStickers()
        preTextModeStickerStates.removeAll()
        preTextModeStickerList.removeAll()
        isTextModeActive = false

        currentEditorCell?.zoomScrollView.setZoomScale(1.0, animated: true)
        // ✅ 텍스트 확인 → 이미지에 bake (이후 편집에 누적 반영)
        bakeAndClearCurrentStickers()
    }
    
    private func deselectAllStickers() {
        guard let cell = currentEditorCell else { return }
        for view in cell.stickerContainerView.subviews {
            if let sticker = view as? TextStickerView {
                sticker.isActive = false
            }
        }
        setAllStickersEditingMode(isTextModeActive || isEmojiModeActive)
    }
    
    // MARK: - Shared Helpers
    
    /// Returns the currently visible EditorPageCell, if any.
    var currentEditorCell: EditorPageCell? {
        collectionView.cellForItem(at: IndexPath(item: currentIndex, section: 0)) as? EditorPageCell
    }
    
    /// Save the live sticker views from the current cell into the persistence dictionary.
    private func saveStickersForCurrentIndex() {
        guard let cell = currentEditorCell else { return }
        let stickers = cell.stickerContainerView.subviews.compactMap { $0 as? TextStickerView }
        stickersByIndex[currentIndex] = stickers.isEmpty ? nil : stickers
    }
    
    /// Restore previously saved stickers into a cell.
    private func restoreStickers(for index: Int, into cell: EditorPageCell) {
        guard let stickers = stickersByIndex[index], !stickers.isEmpty else { return }
        for sticker in stickers {
            // Apply current editing mode before adding to view hierarchy
            sticker.isEditingMode = isTextModeActive
            if sticker.superview == nil {
                cell.stickerContainerView.addSubview(sticker)
            }
        }
    }
    
    /// Set isEditingMode on all stickers in the current cell.
    /// - editing=true: counter-scaled — sticker stays same visual size during image pinch zoom (text edit UI)
    /// - editing=false: natural zoom — sticker scales with the image (WYSIWYG preview)
    private func setAllStickersEditingMode(_ editing: Bool) {
        guard let cell = currentEditorCell else { return }
        for view in cell.stickerContainerView.subviews {
            if let sticker = view as? TextStickerView {
                sticker.isEditingMode = editing && sticker.isActive
            }
        }
    }
    
    /// Bakes all TextStickerViews in the cell's stickerContainer onto the current image.
    /// Returns the composited image, or nil if there are no stickers or no base image.
    /// Uses UIGraphicsImageRenderer for automatic memory management and Wide Color support.
    private func bakeStickersIntoImage(cell: EditorPageCell) -> UIImage? {
        let stickers = cell.stickerContainerView.subviews.compactMap { $0 as? TextStickerView }
        guard !stickers.isEmpty, let baseImage = cell.imageView.image else { return nil }
        
        for sticker in stickers { sticker.isActive = false }
        
        let scaleX = baseImage.size.width / cell.stickerContainerView.bounds.width
        let scaleY = baseImage.size.height / cell.stickerContainerView.bounds.height
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = baseImage.scale
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: baseImage.size, format: format)
        return renderer.image { ctx in
            baseImage.draw(at: .zero)
            
            // 이미지 스케일에 맞게 컨텍스트 기준을 컨테이너 좌표계와 동기화
            ctx.cgContext.scaleBy(x: scaleX, y: scaleY)
            
            let stickers = cell.stickerContainerView.subviews.compactMap { $0 as? TextStickerView }
            for sticker in stickers {
                ctx.cgContext.saveGState()
                
                // 스티커의 중앙 위치로 이동
                ctx.cgContext.translateBy(x: sticker.center.x, y: sticker.center.y)
                
                // 스티커에 적용된 회전/스케일 변환 적용
                ctx.cgContext.concatenate(sticker.stickerTransform)
                
                // 스티커 뷰의 좌상단으로 이동하여 렌더링을 위한 좌표 보정 (bounds 기준 그리기 위함)
                ctx.cgContext.translateBy(x: -sticker.bounds.width / 2, y: -sticker.bounds.height / 2)
                
                // 고해상도 직접 렌더링 (CGAffineTransform 스케일을 폰트 크기에 반영하여 선명하게)
                sticker.drawHighRes(in: ctx.cgContext)
                
                ctx.cgContext.restoreGState()
            }
        }
    }
    
    /// Off-screen baking: 현재 화면에 없는 페이지의 스티커를 이미지에 합성.
    /// 임시 컨테이너 뷰를 생성해 스티커를 렌더링한 후 정리.
    private func bakeStickersOffScreen(stickers: [TextStickerView],
                                       onto baseImage: UIImage,
                                       containerSize: CGSize) -> UIImage {
        stickers.forEach { $0.isActive = false }
        
        // 임시 컨테이너에 스티커를 배치해 렌더링
        let container = UIView(frame: CGRect(origin: .zero, size: containerSize))
        for sticker in stickers {
            sticker.removeFromSuperview()
            container.addSubview(sticker)
        }
        
        let scaleX = baseImage.size.width / containerSize.width
        let scaleY = baseImage.size.height / containerSize.height
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = baseImage.scale
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: baseImage.size, format: format)
        let result = renderer.image { ctx in
            baseImage.draw(at: .zero)
            
            ctx.cgContext.scaleBy(x: scaleX, y: scaleY)
            
            for sticker in stickers {
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: sticker.center.x, y: sticker.center.y)
                ctx.cgContext.concatenate(sticker.stickerTransform)
                ctx.cgContext.translateBy(x: -sticker.bounds.width / 2, y: -sticker.bounds.height / 2)
                
                sticker.drawHighRes(in: ctx.cgContext)
                ctx.cgContext.restoreGState()
            }
        }
        
        // 렌더링 후 임시 컨테이너에서 스티커 제거 (메모리 정리)
        stickers.forEach { $0.removeFromSuperview() }
        return result
    }
    
    /// 현재 페이지의 스티커를 이미지에 bake하고 UIView 레이어를 정리.
    /// 이모지/텍스트 확인 시 호출해 이후 편집(그리기, 다른 이모지 등)에서 누적 반영되게 함.
    private func bakeAndClearCurrentStickers() {
        guard let cell = currentEditorCell,
              let baked = bakeStickersIntoImage(cell: cell) else { return }

        croppedImages[currentIndex] = baked
        cell.originalImage = baked

        // 스티커 UIView 제거 (이미 이미지에 베이킹됨)
        cell.stickerContainerView.subviews
            .compactMap { $0 as? TextStickerView }
            .forEach { $0.removeFromSuperview() }
        stickersByIndex.removeValue(forKey: currentIndex)

        // 필터는 이미 bake에 포함되었으므로 original로 초기화
        let resetState = FilterState(filterId: "original", intensity: 1.0)
        filterStates[currentIndex] = resetState
        cell.applyFilterFinal(resetState)
    }

    @objc private func sliderValueChanged(_ sender: UISlider) {
        var state = filterStates[currentIndex] ?? FilterState(filterId: "original", intensity: 1.0)
        state.intensity = CGFloat(sender.value)
        filterStates[currentIndex] = state
        
        if let idx = FilterManager.shared.filters.firstIndex(where: { $0.id == state.filterId }) {
            if let thumbCell = filterCollectionView.cellForItem(at: IndexPath(item: idx, section: 0)) as? FilterThumbnailCell {
                thumbCell.updateIntensity(state.intensity)
            }
        }
        
        // Update cell preview immediately if possible, but debounce or throttle for performance
        if let cell = currentEditorCell {
            cell.applyFilterLive(state)
        }
    }
    
    @objc private func sliderDidEndSliding(_ sender: UISlider) {
        // Refresh collection view to show updated intensity on the thumbnail
        filterCollectionView.reloadData()
        updateSendButtonState()
        
        // Apply high res filter
        if let cell = currentEditorCell {
            cell.applyFilterFinal(filterStates[currentIndex]!)
        }
        autoSelectCurrentPhoto()
    }
    
    private func generateThumbnailsForCurrent() {
        guard let cell = currentEditorCell,
              let image = cell.originalImage else { return }
        
        // Resize to small thumbnail (e.g., 100x100)
        let targetSize = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        self.currentThumbnailOriginal = thumbnail
        self.filterThumbnailCache.removeAll()
        self.filterCollectionView.reloadData()
        
        let ciThumb = CIImage(image: thumbnail)
        guard let ciImg = ciThumb else { return }
        
        for filter in FilterManager.shared.filters {
            filterQueue.async {
                if let out = filter.apply(ciImg, 1.0), let cgImg = FilterManager.shared.context.createCGImage(out, from: out.extent) {
                    let finalThumb = UIImage(cgImage: cgImg)
                    DispatchQueue.main.async {
                        self.filterThumbnailCache[filter.id] = finalThumb
                        // Only update the specific item if visible
                        if let idx = FilterManager.shared.filters.firstIndex(where: { $0.id == filter.id }) {
                            let ip = IndexPath(item: idx, section: 0)
                            if let cell = self.filterCollectionView.cellForItem(at: ip) as? FilterThumbnailCell {
                                cell.updateImage(finalThumb)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func backTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onCancel?()
        }
    }
    @objc private func sendTapped() {

        
        if standaloneImage == nil {
            guard currentIndex >= 0 && currentIndex < allAssets.count else { return }
        }

        // ── STEP 1: 현재 페이지 스티커를 저장 후 bake ────────────────────
        saveStickersForCurrentIndex()
        if let cell = currentEditorCell, let baked = bakeStickersIntoImage(cell: cell) {
            croppedImages[currentIndex] = baked
            stickersByIndex.removeValue(forKey: currentIndex)  // bake 완료 후 제거
        }

        // ── STEP 2: off-screen 페이지의 스티커도 모두 bake ───────────────
        // 스와이프로 이동하지 않은 페이지는 cell이 없으므로 별도 처리 필요
        let containerSize = collectionView.bounds.size  // 모든 셀은 동일한 크기
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        for (pageIndex, stickers) in stickersByIndex {
            guard !stickers.isEmpty else { continue }

            // 베이스 이미지: croppedImages에 있으면 사용, 없으면 원본 로드
            var baseImage: UIImage? = croppedImages[pageIndex]
            if baseImage == nil, pageIndex < allAssets.count {
                PHImageManager.default().requestImage(
                    for: allAssets[pageIndex],
                    targetSize: fullPixelSize,
                    contentMode: .aspectFit,
                    options: options
                ) { img, _ in baseImage = img }
            }

            // 필터 적용 (이미지가 로드된 경우)
            if let base = baseImage,
               let state = filterStates[pageIndex],
               state.filterId != "original",
               let filter = FilterManager.shared.filters.first(where: { $0.id == state.filterId }),
               let ciImage = CIImage(image: base),
               let out = filter.apply(ciImage, state.intensity),
               let cgImg = FilterManager.shared.context.createCGImage(out, from: out.extent) {
                baseImage = UIImage(cgImage: cgImg, scale: base.scale, orientation: base.imageOrientation)
                // 필터가 이미 베이킹되므로 filterState를 original로 초기화
                filterStates[pageIndex] = FilterState(filterId: "original", intensity: 1.0)
            }

            guard let finalBase = baseImage else { continue }

            // 스티커를 이미지에 합성
            let baked = bakeStickersOffScreen(stickers: stickers,
                                              onto: finalBase,
                                              containerSize: containerSize)
            croppedImages[pageIndex] = baked
        }
        stickersByIndex.removeAll()  // 모든 bake 완료 후 정리

        // ── STEP 3: 결과 수집 및 콜백 호출 ──────────────────────────────
        var finalAssets = selectedAssets
        if finalAssets.isEmpty {
            if standaloneImage == nil {
                finalAssets = [allAssets[currentIndex]]
            }
        }

        var outCrops: [PHAsset: UIImage] = [:]
        var outFilters: [PHAsset: FilterState] = [:]

        for asset in finalAssets {
            if let idx = allAssets.firstIndex(of: asset) {
                if let c = croppedImages[idx] { outCrops[asset] = c }
                let state = filterStates[idx] ?? FilterState(filterId: "original", intensity: 1.0)
                outFilters[asset] = state
            }
        }

        let state = filterStates[currentIndex] ?? FilterState(filterId: "original", intensity: 1.0)
        let cropped = croppedImages[currentIndex]

        if let multi = onConfirmMulti, !singlePhotoMode {
            multi(finalAssets, outCrops, outFilters)
        } else {
            onConfirm?(standaloneImage != nil ? nil : allAssets[currentIndex], cropped, state, "")
        }
    }
    
    // MARK: - Pull to Dismiss
    private var dismissPanGesture: UIPanGestureRecognizer!
    
    private func setupDismissPanGesture() {
        dismissPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        dismissPanGesture.delegate = self
        view.addGestureRecognizer(dismissPanGesture)
    }

    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        guard !isTextModeActive, !isEmojiModeActive, !isFilterActive else { return }
        
        if let cell = currentEditorCell, cell.zoomScrollView.zoomScale > 1.0 {
            return
        }

        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        switch gesture.state {
        case .began, .changed:
            if translation.y < 0 && view.transform == .identity {
                return
            }
            let scale = max(0.85, 1.0 - (translation.y / (view.bounds.height * 2)))
            view.transform = CGAffineTransform(translationX: translation.x, y: translation.y).scaledBy(x: scale, y: scale)
            
            // 투명도가 너무 빨리 떨어지지 않도록 조정 (최소 투명도 0.4 제한, 변화율 감소)
            let alpha = max(0.4, 1.0 - (translation.y / (view.bounds.height * 1.5)))
            view.alpha = alpha
            
            // 당긴 만큼 테두리 둥글게 처리
            view.layer.masksToBounds = true
            view.layer.cornerRadius = min(40, max(0, translation.y / 5.0))

        case .ended, .cancelled:
            let shouldDismiss = translation.y > 150 || velocity.y > 500
            if shouldDismiss {
                self.dismiss(animated: true) {
                    self.onCancel?()
                }
            } else {
                UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: .curveEaseOut) {
                    self.view.transform = .identity
                    self.view.alpha = 1.0
                    self.view.layer.cornerRadius = 0
                }
            }
        default:
            break
        }
    }
}

extension ImageEditorViewController: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == dismissPanGesture {
            let pan = gestureRecognizer as! UIPanGestureRecognizer
            let velocity = pan.velocity(in: view)
            
            // Only allow vertical pull down
            if velocity.y > 0 && abs(velocity.y) > abs(velocity.x) {
                if let cell = currentEditorCell, cell.zoomScrollView.zoomScale > 1.0 {
                    return false
                }
                if isTextModeActive || isEmojiModeActive || isFilterActive {
                    return false
                }
                return true
            }
            return false
        }
        return true
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == dismissPanGesture {
            return false
        }
        return false
    }
}

// MARK: - UICollectionViewDataSource

extension ImageEditorViewController: UICollectionViewDataSource {
        public func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if cv == filterCollectionView {
            return FilterManager.shared.filters.count
        }
        if standaloneImage != nil { return 1 }
        return allAssets.count
    }

    public func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if cv == filterCollectionView {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: FilterThumbnailCell.id, for: indexPath) as! FilterThumbnailCell
            let filter = FilterManager.shared.filters[indexPath.item]
            let thumb = filterThumbnailCache[filter.id] ?? currentThumbnailOriginal
            let state = filterStates[currentIndex] ?? FilterState(filterId: "original", intensity: 1.0)
            let isSelected = state.filterId == filter.id
            cell.configure(with: thumb, name: Localizer.getString(key: "filter_" + filter.id, languageCode: languageCode), isSelected: isSelected, intensity: state.intensity, themeColor: themeColor)
            return cell
        }
        let cell = cv.dequeueReusableCell(withReuseIdentifier: EditorPageCell.id, for: indexPath) as! EditorPageCell
        let state = filterStates[indexPath.item] ?? FilterState(filterId: "original", intensity: 1.0)
        let cropped = croppedImages[indexPath.item]
        if let sImg = standaloneImage {
            cell.configure(withImage: cropped ?? sImg, filterState: state)
            return cell
        }
        cell.configure(
            with: allAssets[indexPath.item],
            index: indexPath.item,
            targetSize: fullPixelSize,
            cache: imageCache,
            manager: cachingManager,
            options: imageRequestOptions,
            collectionView: cv,
            filterState: state,
            croppedImage: cropped
        ) { [weak self] in
            guard let self = self else { return }
            if indexPath.item == self.currentIndex && self.isFilterActive {
                self.generateThumbnailsForCurrent()
            }
        }
        // Restore live sticker components that survived cell reuse
        restoreStickers(for: indexPath.item, into: cell)
        return cell
    }

}

// MARK: - UICollectionViewDelegateFlowLayout

extension ImageEditorViewController: UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView == filterCollectionView {
            let filter = FilterManager.shared.filters[indexPath.item]
            var state = filterStates[currentIndex] ?? FilterState(filterId: "original", intensity: 1.0)
            
            state.filterId = filter.id
            state.intensity = 1.0
            
            intensitySlider.value = Float(state.intensity)
            sliderBackgroundView.isHidden = (filter.id == "original")
            filterStates[currentIndex] = state
            collectionView.reloadData() // update selection UI
            
            // Apply to main image
            if let cell = self.collectionView.cellForItem(at: IndexPath(item: self.currentIndex, section: 0)) as? EditorPageCell {
                cell.applyFilterFinal(state)
            }
            autoSelectCurrentPhoto()
        }
    }

    public func collectionView(_ cv: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        if cv == filterCollectionView {
            return CGSize(width: 70, height: 82)
        }
        return cv.bounds.size
    }
}

// MARK: - Scroll Tracking

extension ImageEditorViewController {
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { updateCurrentIndex() }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { updateCurrentIndex() }
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { updateCurrentIndex() }

    private func updateCurrentIndex() {
        let w = collectionView.bounds.width
        guard w > 0 else { return }
        let count = standaloneImage != nil ? 1 : allAssets.count
        guard count > 0 else { return }
        let idx = max(0, min(Int(round(collectionView.contentOffset.x / w)), count - 1))
        if idx != currentIndex {
            // Save stickers for the page we are leaving
            saveStickersForCurrentIndex()
            currentIndex = idx
            updateCounter()
            
            if isFilterActive {
                let state = filterStates[currentIndex] ?? FilterState(filterId: "original", intensity: 1.0)
                intensitySlider.value = Float(state.intensity)
                sliderBackgroundView.isHidden = (state.filterId == "original")
                generateThumbnailsForCurrent()
            }
        }
        updateSendButtonState()
    }
}

// MARK: - UICollectionViewDataSourcePrefetching

extension ImageEditorViewController: UICollectionViewDataSourcePrefetching {

    public func collectionView(_ cv: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        var assetsToCache: [PHAsset] = []
        for ip in indexPaths {
            let key = NSNumber(value: ip.item)
            guard ip.item < allAssets.count,
                  imageCache.object(forKey: key) == nil else { continue }
            assetsToCache.append(allAssets[ip.item])
        }
        guard !assetsToCache.isEmpty else { return }
        cachingManager.startCachingImages(
            for: assetsToCache, targetSize: fullPixelSize,
            contentMode: .aspectFit, options: imageRequestOptions
        )
    }

    public func collectionView(_ cv: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        var assetsToCancel: [PHAsset] = []
        for ip in indexPaths {
            guard ip.item < allAssets.count else { continue }
            assetsToCancel.append(allAssets[ip.item])
        }
        guard !assetsToCancel.isEmpty else { return }
        cachingManager.stopCachingImages(
            for: assetsToCancel, targetSize: fullPixelSize,
            contentMode: .aspectFit, options: imageRequestOptions
        )
    }
}

// MARK: - ZoomScrollView (확대 상태 경계 → 페이지 전환 위임)

class ZoomScrollView: UIScrollView {
    override func gestureRecognizerShouldBegin(_ gr: UIGestureRecognizer) -> Bool {
        guard zoomScale > 1.0,
              gr === panGestureRecognizer,
              let pan = gr as? UIPanGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gr)
        }
        let v = pan.velocity(in: self)
        guard abs(v.x) > abs(v.y) else {
            return super.gestureRecognizerShouldBegin(gr)
        }
        let atLeft  = contentOffset.x <= 0
        let atRight = contentOffset.x >= contentSize.width - bounds.width - 1
        if atLeft  && v.x > 0 { return false }
        if atRight && v.x < 0 { return false }
        return super.gestureRecognizerShouldBegin(gr)
    }
}

// MARK: - EditorPageCell

class EditorPageCell: UICollectionViewCell, UIScrollViewDelegate {
    static let id = "EditorPageCell"

    let zoomScrollView: ZoomScrollView = {
        let sv = ZoomScrollView()
        sv.minimumZoomScale = 1.0
        sv.maximumZoomScale = 5.0
        sv.showsVerticalScrollIndicator = false
        sv.showsHorizontalScrollIndicator = false
        sv.bounces = true
        sv.bouncesZoom = true
        sv.contentInsetAdjustmentBehavior = .never
        return sv
    }()

    let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.isUserInteractionEnabled = true
        return iv
    }()

    let stickerContainerView: UIView = {
        let v = UIView()
        v.backgroundColor = .clear
        v.clipsToBounds = true
        return v
    }()

    weak var parentCollectionView: UICollectionView?
    private var requestID: PHImageRequestID = PHInvalidImageRequestID
    private var loadedIndex: Int = -1

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .editorCellBackground
        contentView.backgroundColor = .editorCellBackground

        zoomScrollView.delegate = self
        contentView.addSubview(zoomScrollView)
        zoomScrollView.addSubview(imageView)
        imageView.addSubview(stickerContainerView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        zoomScrollView.addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        zoomScrollView.frame = contentView.bounds
        if zoomScrollView.zoomScale == 1.0 {
            updateImageAndStickerFrame()
        }
    }
    
    func updateImageAndStickerFrame() {
        if zoomScrollView.zoomScale != 1.0 { return }
        
        guard let img = imageView.image else {
            imageView.frame = zoomScrollView.bounds
            stickerContainerView.frame = imageView.bounds
            zoomScrollView.contentSize = zoomScrollView.bounds.size
            return
        }
        
        let viewSize = zoomScrollView.bounds.size
        let imageSize = img.size
        
        if viewSize.width == 0 || viewSize.height == 0 { return }
        
        let widthRatio = viewSize.width / imageSize.width
        let heightRatio = viewSize.height / imageSize.height
        let scale = min(widthRatio, heightRatio)
        
        let displayWidth = imageSize.width * scale
        let displayHeight = imageSize.height * scale
        
        UIView.performWithoutAnimation {
            self.imageView.frame = CGRect(x: 0, y: 0, width: displayWidth, height: displayHeight)
            self.stickerContainerView.frame = self.imageView.bounds
            self.zoomScrollView.contentSize = self.imageView.frame.size
        }
        
        // 정렬을 위해 호출
        scrollViewDidZoom(zoomScrollView)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelLoad()
        imageView.image = nil
        zoomScrollView.zoomScale = 1.0
        zoomScrollView.contentOffset = .zero
        loadedIndex = -1
        
        for subview in stickerContainerView.subviews {
            subview.removeFromSuperview()
        }
    }

    private func cancelLoad() {
        if requestID != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(requestID)
            requestID = PHInvalidImageRequestID
        }
    }

    // MARK: Configure


    
    func configure(withImage image: UIImage, filterState: FilterState) {
        cancelLoad()
        self.originalImage = image
        self.applyFilterFinal(filterState)
        loadedIndex = 0
    }

    private var currentFilterState: FilterState?
    var originalImage: UIImage?
    
    func configure(with asset: PHAsset,
                   index: Int,
                   targetSize: CGSize,
                   cache: NSCache<NSNumber, UIImage>,
                   manager: PHCachingImageManager,
                   options: PHImageRequestOptions,
                   collectionView: UICollectionView?,
                   filterState: FilterState,
                   croppedImage: UIImage?,
                   onImageLoaded: (() -> Void)? = nil) {
        parentCollectionView = collectionView
        currentFilterState = filterState
        cancelLoad()

        let key = NSNumber(value: index)

        if let cropped = croppedImage {
            self.originalImage = cropped
            self.applyFilterFinal(filterState)
            loadedIndex = index
            onImageLoaded?()
            return
        }

        if let cached = cache.object(forKey: key) {
            self.originalImage = cached
            self.applyFilterFinal(filterState)
            loadedIndex = index
            onImageLoaded?()
            return
        }

        loadedIndex = index
        requestID = manager.requestImage(
            for: asset, targetSize: targetSize,
            contentMode: .aspectFit, options: options
        ) { [weak self] img, info in
            guard let self = self, let img = img, self.loadedIndex == index else { return }
            DispatchQueue.main.async {
                self.originalImage = img
                self.applyFilterFinal(filterState)
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    cache.setObject(img, forKey: key)
                }
                onImageLoaded?()
            }
        }
    }
    
    func applyFilterLive(_ state: FilterState) {
        // For live sliding, we could resize the image or just apply if fast enough.
        // For simplicity and to prevent UI lag, we'll just apply it on a background queue.
        applyFilterAsync(state)
    }
    
    func applyFilterFinal(_ state: FilterState) {
        currentFilterState = state
        applyFilterAsync(state)
    }
    
    private func applyFilterAsync(_ state: FilterState) {
        guard let orig = originalImage else { return }
        if state.filterId == "original" {
            self.imageView.image = orig
            self.updateImageAndStickerFrame()
            return
        }
        
        guard let filter = FilterManager.shared.filters.first(where: { $0.id == state.filterId }) else { return }
        
        DispatchQueue.global(qos: .userInteractive).async {
            let ciImage = CIImage(image: orig)
            if let ciImg = ciImage,
               let out = filter.apply(ciImg, state.intensity),
               let cgImg = FilterManager.shared.context.createCGImage(out, from: out.extent) {
                let filtered = UIImage(cgImage: cgImg)
                DispatchQueue.main.async {
                    // Check if state has changed while we were processing
                    if self.currentFilterState?.filterId == state.filterId {
                        self.imageView.image = filtered
                        self.updateImageAndStickerFrame()
                    }
                }
            }
        }
    }


    // MARK: UIScrollViewDelegate — Zoom

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    public func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let bs = scrollView.bounds.size
        let cs = scrollView.contentSize
        
        let offsetX = max(0, (bs.width - cs.width) / 2)
        let offsetY = max(0, (bs.height - cs.height) / 2)
        
        scrollView.contentInset = UIEdgeInsets(top: offsetY, left: offsetX, bottom: offsetY, right: offsetX)
        
        let scale = scrollView.zoomScale
        for view in stickerContainerView.subviews {
            if let sticker = view as? TextStickerView {
                sticker.containerZoomScale = scale
            }
        }
    }

    public func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        // ZoomScrollView가 경계 감지를 하므로 별도 처리 불필요
    }

    public func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        if scale <= 1.0 {
            UIView.animate(withDuration: 0.2) {
                scrollView.zoomScale = 1.0
                self.updateImageAndStickerFrame()
            }
        }
    }

    // MARK: Double-Tap

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScrollView.zoomScale > 1.0 {
            zoomScrollView.setZoomScale(1.0, animated: true)
        } else {
            let loc = gesture.location(in: imageView)
            let z: CGFloat = 2.5
            let w = zoomScrollView.bounds.width  / z
            let h = zoomScrollView.bounds.height / z
            zoomScrollView.zoom(to: CGRect(x: loc.x - w/2, y: loc.y - h/2, width: w, height: h), animated: true)
        }
    }
}

extension ImageEditorViewController: TextStickerViewDelegate {
    func stickerDidTap(_ sticker: TextStickerView) {
        if !isTextModeActive && !sticker.isEmojiSticker { 
            beginTextMode() 
        }
        deselectAllStickers()
        sticker.isActive = true
        setAllStickersEditingMode(isTextModeActive || isEmojiModeActive)
    }
    
    func stickerDidTapEdit(_ sticker: TextStickerView) {
        if sticker.isEmojiSticker { return } // 이모지는 텍스트 수정 모드로 들어가지 않음
        openTextInput(initialText: sticker.text, initialColor: sticker.textColor, stickerToEdit: sticker)
    }
    
    func stickerDidTapDelete(_ sticker: TextStickerView) {
        sticker.removeFromSuperview()
        updateSendButtonState()
    }
}
