//
//  GalleryViewController.swift
//  ImageGalleryTest
//
//  텔레그램급 이미지 갤러리 - 초고속 로딩 + 앨범 선택 + 스마트 모달
//  전략: 초기 30장 즉시 표시 → 나머지 백그라운드 로딩
//  기본값: 최근 항목 (Recents)
//

import UIKit
import Photos

public class GalleryBaseViewController: UIViewController {
    
    // MARK: - Properties
    
    let photoManager = PhotoManager.shared
    private let imageCache = TurboImageCache.shared
    
    public var onImagesSelected: (([(PHAsset?, UIImage)]) -> Void)?
    public var onSelectionChanged: ((Int, Int) -> Void)?  // (selectedCount, maxSelection)
    /// 편집 모드: 사진 탭 즉시 호출 (갤러리 닫힘 없음)
    public var onSingleImageTappedForEdit: ((PHAsset, CGRect, UIImage?) -> Void)?

    // 편집 기능 on/off 옵션 (기본값: false)
    // - false: 기존 동작 (선택 후 완료 버튼)
    // - true:  단일선택 → 탭 즉시 편집, 다중선택 → 선택 후 탭으로 편집
    public var allowsEditing: Bool = false

    // 프로필 모드: true이면 사진 선택 즉시 1:1 원형 크롭 화면 표시 후 편집기로 이동
    public var profileMode: Bool = false
    /// profileMode에서 크롭 완료된 UIImage와 원본 PHAsset을 전달하는 콜백
    public var onProfileCropComplete: ((PHAsset, UIImage) -> Void)?

    // 편집 중인 asset 추적 (갤러리로 복귀 시 선택 유지용)
    public var editingAsset: PHAsset?
    
    // 트랜지션 애니메이터 유지용 강한 참조
    public var profileCropTransitionDelegate: UIViewControllerTransitioningDelegate?
    
    // 최대 선택 가능한 이미지 수 (0 = 무제한)
    public var maxSelection: Int = 0

    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // 이미지 리사이징 옵션 (0 = 원본 크기 유지)
    public var maxWidth: Int = 0
    public var maxHeight: Int = 0

    // 출력 포맷: "webp" | "jpg" | "png" (기본값: "webp")
    public var outputFormat: String = "webp"
    
    // 세그먼트 컨트롤 텍스트 (커스터마이징 가능)
    public var allItemsText: String = "All"
    public var selectedItemsText: String = "Selected"
    public var doneButtonText: String = "Done"
    public var recentsAlbumText: String = "Recents"
    
    // 언어 코드 (기본값: 영문)
    public var languageCode: String = "en" {
        didSet {
            applyLanguageTexts()
            cachedDateFormatter = Self.buildDateFormatter(for: languageCode)
        }
    }

    // 테마 컬러 (HEX 문자열)
    public var themeColorHex: String?
    
    public var parsedThemeColor: UIColor {
        let defaultThemeColor = UIColor(red: 236/255, green: 73/255, blue: 38/255, alpha: 1.0) // #EC4926
        if let hex = themeColorHex {
            var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            hexSanitized = hexSanitized.hasPrefix("#") ? String(hexSanitized.dropFirst()) : hexSanitized
            var rgb: UInt64 = 0
            if Scanner(string: hexSanitized).scanHexInt64(&rgb) {
                let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
                let g = CGFloat((rgb >>  8) & 0xFF) / 255.0
                let b = CGFloat( rgb        & 0xFF) / 255.0
                return UIColor(red: r, green: g, blue: b, alpha: 1.0)
            }
        }
        return defaultThemeColor
    }

    // 📁 코드 관리: extension 파일에서 접근 필요한 프로퍼티는 internal
    var assets: [PHAsset] = []
    public var allAssets: [PHAsset] { return assets }
    private var isLoadingInitial = false
    private var isLoadingRemaining = false
    
    // 고유 ID (카메라 세션 강제 종료 시 식별용)
    public let galleryID = UUID().uuidString
    
    // 🚀 싱글톤처럼 갤러리 내에서 하나만 유지하는 카메라 프리뷰 (스크롤 끊김 방지용)
    lazy var sharedCameraView: CameraPreviewView = {
        let view = CameraPreviewView(frame: .zero)
        view.galleryID = self.galleryID // 🚀 노티피케이션 응답을 위해 반드시 매핑
        view.translatesAutoresizingMaskIntoConstraints = true
        view.isHidden = true
        return view
    }()
    
    // 선택된 사진 배열 (순서 유지)
    public var selectedAssets: [PHAsset] = []
    
    // 🚀 편집된 사진을 갤러리에 유지하기 위한 Dictionary (localIdentifier: UIImage)
    public var editedImages: [String: UIImage] = [:]
    
    // 🚀 앱 세션 중 촬영된 카메라 사진들의 ID 추적 (삭제 기능 등에 사용)
    static var sessionCapturedIdentifiers: Set<String> = []
    
    // 🚀 성능 최적화: O(1) 선택 상태 조회용 Set (selectedAssets와 동기화)
    public var selectedAssetsSet: Set<String> = []
    
    // 🚀 성능 최적화: DateFormatter 캐시 (스크롤마다 재생성 방지)
    private lazy var cachedDateFormatter: DateFormatter = Self.buildDateFormatter(for: languageCode)
    
    // 필터 모드 (All / Selected)
    var isShowingOnlySelected = false
    
    // 앨범 관련
    var albums: [Album] = []
    var selectedAlbum: Album? = nil
    var albumsLoaded = false
    
    // 성능 최적화: 고품질 썸네일
    var thumbnailSize: CGSize = .zero
    
    // 셀 너비 캐시 (레이아웃 점프 방지)
    // - 최초 계산 후 고정, 화면 크기 변경 시 nil로 초기화
    var cachedCellWidth: CGFloat? = nil
    
    // Preheating 최적화
    var previousPreheatRect: CGRect = .zero
    
    // 시트 전환(half↔full) 중 updateCachedAssets 억제용 (두둑 방지)
    var isSheetTransitioning: Bool = false
    var sheetTransitionEndWorkItem: DispatchWorkItem?
    var previousViewHeight: CGFloat = 0
    var previousViewWidth: CGFloat = 0
    // half→full 10% 지점 자동 스냅용
    var initialSheetHeight: CGFloat = 0    // half 상태의 기준 높이
    var hasTriggeredAutoExpand: Bool = false
    var isPresentationCompleted: Bool = false // 첫 실행 시 애니메이션 충돌 방지용
    // 카메라 표시 여부 (최근 항목일 때만)
    var shouldShowCamera: Bool {
        guard let album = selectedAlbum else { return true } // 기본값은 true (최근 항목)
        return album.collection.assetCollectionSubtype == .smartAlbumUserLibrary
    }
    
    // MARK: - UI Components
    
    private lazy var albumButton: UIButton = {
        // 🎨 UI 개선: iOS 15+ Configuration 사용
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.plain()
            
            // 텍스트 설정
            config.title = recentsAlbumText
            
            // 시스템 테마에 따라 텍스트 색상 설정
            if #available(iOS 13.0, *) {
                config.baseForegroundColor = .label
            } else {
                config.baseForegroundColor = .darkText
            }
            
            // 폰트 크기 증대 (15 -> 17)
            var titleAttr = AttributedString(recentsAlbumText)
            titleAttr.font = .systemFont(ofSize: 17, weight: .bold)
            config.attributedTitle = titleAttr
            
            // 🔧 수정: 화살표 아이콘 반투명 (50% 불투명도)
            let imageConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
            config.image = UIImage(systemName: "chevron.down", withConfiguration: imageConfig)
            config.imagePlacement = .trailing
            config.imagePadding = 6
            
            // 버튼 영역 확대 (좌우 여백 추가)
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 24, bottom: 8, trailing: 24)
            
            let button = UIButton(configuration: config, primaryAction: nil)
            button.addTarget(self, action: #selector(albumButtonTapped), for: .touchUpInside)
            
            // 화살표 색상
            if #available(iOS 13.0, *) {
                button.tintColor = UIColor.label.withAlphaComponent(0.5)
            } else {
                button.tintColor = UIColor.darkText.withAlphaComponent(0.5)
            }
            
            // 네비게이션 타이틀 뷰는 intrinsic content size를 사용하게 둠
            
            // 텍스트 말줄임표 처리 (항상 1줄 유지)
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.titleLabel?.numberOfLines = 1
            button.titleLabel?.adjustsFontSizeToFitWidth = false
            
            return button
        } else {
            // iOS 14 이하 호환
            let button = UIButton(type: .system)
            button.setTitle(recentsAlbumText, for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
            button.semanticContentAttribute = .forceRightToLeft
            
            let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
            let chevronImage = UIImage(systemName: "chevron.down", withConfiguration: config)
            button.setImage(chevronImage, for: .normal)
            
            // 🔧 수정: 화살표 색상 반투명 (50% 불투명도)
            button.tintColor = UIColor.white.withAlphaComponent(0.5)
            
            button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 0)
            button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 6)
            button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 24, bottom: 8, right: 24)
            
            // 네비게이션 타이틀 뷰는 intrinsic content size를 사용하게 둠
            
            // 텍스트 말줄임표 처리
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.titleLabel?.numberOfLines = 1
            button.titleLabel?.adjustsFontSizeToFitWidth = false
            
            button.addTarget(self, action: #selector(albumButtonTapped), for: .touchUpInside)
            return button
        }
    }()
    
    public lazy var collectionView: UICollectionView = {
        let layout = TelegramGalleryLayout()
        layout.numberOfColumns = 3
        layout.cellPadding = 1
        layout.delegate = self
        
        // 3열 그리드 계산
        let screenWidth = UIScreen.main.bounds.width
        let spacing: CGFloat = 1
        let availableWidth = screenWidth - (spacing * 2)
        let itemWidth = floor(availableWidth / 3)
        // itemSize는 sizeForItemAt에서 동적으로 설정
        
        // 셀 너비 캐시 초기화 (레이아웃 점프 방지)
        cachedCellWidth = itemWidth
        
        // 🎨 품질 개선: 고해상도 썸네일 사용
        let scale = UIScreen.main.scale
        thumbnailSize = CGSize(
            width: itemWidth * scale,
            height: itemWidth * scale
        )
        
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        if #available(iOS 13.0, *) {
            cv.backgroundColor = UIColor { traitCollection in
                return traitCollection.userInterfaceStyle == .dark ? UIColor(red: 29/255, green: 29/255, blue: 29/255, alpha: 1.0) : .white
            }
        } else {
            cv.backgroundColor = .white
        }
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.register(GalleryCell.self, forCellWithReuseIdentifier: GalleryCell.identifier)
        cv.delegate = self
        cv.dataSource = self
        cv.prefetchDataSource = self
        
        cv.isPrefetchingEnabled = true
        cv.showsVerticalScrollIndicator = true
        cv.contentInsetAdjustmentBehavior = .never
        cv.alwaysBounceVertical = true
        cv.bounces = true
        
        return cv
    }()
    
    private let loadingIndicator: UIActivityIndicatorView = {
        // 🔧 수정: 작은 인디케이터로 변경 (.large → .medium)
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        indicator.color = UIColor { t in t.userInterfaceStyle == .dark ? .white : .gray }
        return indicator
    }()
    
    private let permissionLabel: UILabel = {
        let label = UILabel()
        label.text = "사진 접근 권한이 필요합니다"
        label.textAlignment = .center
        label.textColor = .white
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()
    
    // MARK: - 날짜 스크롤바
    
    private lazy var scrollBarTrack: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 2
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alpha = 0
        return view
    }()
    
    private lazy var scrollBarThumb: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 3
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alpha = 0
        return view
    }()
    
    private lazy var dateScrollIndicator: UIView = {
        let container = UIView()
        container.layer.cornerRadius = 16
        container.translatesAutoresizingMaskIntoConstraints = false
        container.alpha = 0
        return container
    }()
    
    private let dateLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private var scrollBarThumbTopConstraint: NSLayoutConstraint?
    private var dateHideTimer: Timer?
    private var isDraggingScrollBar = false
    private var scrollUpdateTimer: Timer?
    private var targetScrollOffset: CGFloat = 0
    private var lastSnapshotTime: TimeInterval = 0
    
    // 완료 버튼 애니메이션 진행 플래그
    private var isDoneButtonAnimating = false
    
    // 햅틱 피드백
    private let hapticFeedback = UISelectionFeedbackGenerator()
    private var lastHapticDate: String = ""
    
    // 날짜 인디케이터 위치 제약
    private var dateIndicatorTrailingConstraint: NSLayoutConstraint?
    private var dateIndicatorCenterYConstraint: NSLayoutConstraint?
    
    // 완료 버튼 (UIBarButtonItem)
    lazy var doneButton: UIBarButtonItem = {
        let btn = UIButton(type: .custom)
        
        btn.backgroundColor = parsedThemeColor
        btn.layer.cornerRadius = 16
        btn.layer.masksToBounds = true
        btn.clipsToBounds = true
        btn.tintColor = .white
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        
        let checkImage = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))?.withTintColor(.white, renderingMode: .alwaysOriginal)
        btn.setImage(checkImage, for: .normal)
        btn.setTitle(" 1", for: .normal)
        
        // 버튼 텍스트 양옆 여백 추가
        btn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        btn.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
        
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 32).isActive = true
        btn.widthAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        
        btn.addTarget(self, action: #selector(doneButtonTapped), for: .touchUpInside)
        
        return UIBarButtonItem(customView: btn)
    }()
    

    // 필터 세그먼트 컨트롤 (All / Selected) - Top Bar용
    lazy var filterSegmentControl: UISegmentedControl = {
        let items = [allItemsText, "99 \(selectedItemsText)"] // 최대 크기로 초기화
        let segment = UISegmentedControl(items: items)
        segment.selectedSegmentIndex = 0
        
        // iOS 13+ 스타일
        if #available(iOS 13.0, *) {
            segment.backgroundColor = UIColor.secondarySystemBackground
            segment.selectedSegmentTintColor = UIColor.systemBackground
            
            // 텍스트 색상 (숫자가 바뀔 때 너비가 변하지 않도록 고정폭 숫자 폰트 사용)
            segment.setTitleTextAttributes([
                .foregroundColor: UIColor.secondaryLabel,
                .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            ], for: .normal)
            
            segment.setTitleTextAttributes([
                .foregroundColor: UIColor.label,
                .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            ], for: .selected)
        } else {
            segment.tintColor = .darkText
        }
        
        segment.addTarget(self, action: #selector(filterSegmentChanged(_:)), for: .valueChanged)
        
        segment.translatesAutoresizingMaskIntoConstraints = false
        segment.apportionsSegmentWidthsByContent = true // 텍스트 크기에 맞게 너비 조절하여 우측 침범 방지
        // 네비게이션 바 공간 부족 시 우측 버튼 침범을 막고 텍스트를 줄임(Truncate)
        segment.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        // 실제 텍스트로 다시 설정 (레이아웃 변경 없이)
        segment.setTitle("0 \(selectedItemsText)", forSegmentAt: 1)
        
        return segment
    }()
    
    private var isShowingFilterSegment = false
    
    private lazy var titleContainerView: UIView = { [unowned self] in
        let view = UIView()
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        
        albumButton.translatesAutoresizingMaskIntoConstraints = false
        filterSegmentControl.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(albumButton)
        view.addSubview(filterSegmentControl)
        
        NSLayoutConstraint.activate([
            albumButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            albumButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            filterSegmentControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            filterSegmentControl.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            view.widthAnchor.constraint(equalTo: filterSegmentControl.widthAnchor),
            view.heightAnchor.constraint(equalToConstant: 44) // Navigation bar standard height
        ])
        
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        // 초기 상태 설정
        filterSegmentControl.alpha = 0
        filterSegmentControl.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        
        return view
    }()
    
    // MARK: - Lifecycle
    
    public override func viewDidLoad() {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("🟢 [DEBUG] viewDidLoad 시작")
        
        super.viewDidLoad()
        photoManager.languageCode = languageCode
        print("🟢 [DEBUG] super.viewDidLoad 완료 - 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime))초")
        
        let step1 = CFAbsoluteTimeGetCurrent()
        // 언어 텍스트 먼저 적용
        applyLanguageTexts()
        print("🟢 [DEBUG] applyLanguageTexts 완료 - 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - step1))초")
        
        let step2 = CFAbsoluteTimeGetCurrent()
        // 🚀 성능 최적화: UI 먼저 표시 (즉시)
        setupUI()
        print("🟢 [DEBUG] setupUI 완료 - 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - step2))초")
        
        let step3 = CFAbsoluteTimeGetCurrent()
        setupCloseButton()
        setupAlbumSelector()
        print("🟢 [DEBUG] setupCloseButton/AlbumSelector 완료 - 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - step3))초")
        
        let step4 = CFAbsoluteTimeGetCurrent()
        // 스와이프로 dismiss 감지를 위한 delegate 설정
        navigationController?.presentationController?.delegate = self
        print("🟢 [DEBUG] delegate 설정 완료 - 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - step4))초")
        
        print("🟢 [DEBUG] viewDidLoad 기본 작업 완료 - 총 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime))초")
        
        // 🚀 성능 최적화: 무거운 작업은 다음 runloop에서 비동기 실행
        DispatchQueue.main.async { [weak self] in
            let asyncStart = CFAbsoluteTimeGetCurrent()
            print("🟡 [DEBUG] 비동기 작업 시작")
            self?.checkPhotoLibraryPermission()
            print("🟡 [DEBUG] checkPhotoLibraryPermission 완료 - 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - asyncStart))초")
            self?.loadAlbumsInBackground() // 앨범 미리 로딩
            print("🟡 [DEBUG] loadAlbumsInBackground 호출 완료")
        }
        
        print("✅ [DEBUG] viewDidLoad 종료 - 총 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime))초")
    }
    
    // MARK: - Language Support
    
    /// 언어 코드에 따라 모든 텍스트를 자동 설정
    private func applyLanguageTexts() {
        switch languageCode {
        case "ko":
            allItemsText = "전체"
            selectedItemsText = "선택됨"
            doneButtonText = Localizer.getString(key: "done", languageCode: languageCode)
            recentsAlbumText = "최근 항목"
        case "ja":
            allItemsText = "すべて"
            selectedItemsText = "選択済み"
            doneButtonText = "完了"
            recentsAlbumText = "最近の項目"
        case "zh":
            allItemsText = "全部"
            selectedItemsText = "已选"
            doneButtonText = "完成"
            recentsAlbumText = "最近项目"
        case "de":
            allItemsText = "Alle"
            selectedItemsText = "Ausgewählt"
            doneButtonText = "Fertig"
            recentsAlbumText = "Zuletzt"
        case "es":
            allItemsText = "Todos"
            selectedItemsText = "Seleccionados"
            doneButtonText = "Listo"
            recentsAlbumText = "Recientes"
        case "fr":
            allItemsText = "Tous"
            selectedItemsText = "Sélectionnés"
            doneButtonText = "Terminé"
            recentsAlbumText = "Récents"
        case "hi":
            allItemsText = "सभी"
            selectedItemsText = "चयनित"
            doneButtonText = "पूर्ण"
            recentsAlbumText = "हाल का"
        case "id":
            allItemsText = "Semua"
            selectedItemsText = "Dipilih"
            doneButtonText = "Selesai"
            recentsAlbumText = "Terbaru"
        case "it":
            allItemsText = "Tutti"
            selectedItemsText = "Selezionati"
            doneButtonText = "Fine"
            recentsAlbumText = "Recenti"
        case "ms":
            allItemsText = "Semua"
            selectedItemsText = "Dipilih"
            doneButtonText = "Selesai"
            recentsAlbumText = "Terkini"
        case "nl":
            allItemsText = "Alle"
            selectedItemsText = "Geselecteerd"
            doneButtonText = "Klaar"
            recentsAlbumText = "Recenten"
        case "pl":
            allItemsText = "Wszystkie"
            selectedItemsText = "Wybrane"
            doneButtonText = "Gotowe"
            recentsAlbumText = "Niedawne"
        case "pt":
            allItemsText = "Todos"
            selectedItemsText = "Selecionados"
            doneButtonText = "Concluído"
            recentsAlbumText = "Recentes"
        case "ru":
            allItemsText = "Все"
            selectedItemsText = "Выбрано"
            doneButtonText = "Готово"
            recentsAlbumText = "Недавние"
        case "th":
            allItemsText = "ทั้งหมด"
            selectedItemsText = "เลือกแล้ว"
            doneButtonText = "เสร็จสิ้น"
            recentsAlbumText = "ล่าสุด"
        case "tr":
            allItemsText = "Tümü"
            selectedItemsText = "Seçili"
            doneButtonText = "Tamam"
            recentsAlbumText = "Son Eklenenler"
        case "vi":
            allItemsText = "Tất cả"
            selectedItemsText = "Đã chọn"
            doneButtonText = "Xong"
            recentsAlbumText = "Gần đây"
        case "da":
            allItemsText = "Alle"
            selectedItemsText = "Valgt"
            doneButtonText = "Færdig"
            recentsAlbumText = "Seneste"
        case "en":
            fallthrough
        default:
            allItemsText = Localizer.getString(key: "all_photos", languageCode: languageCode)
            selectedItemsText = Localizer.getString(key: "selected", languageCode: languageCode)
            doneButtonText = Localizer.getString(key: "done", languageCode: languageCode)
            recentsAlbumText = Localizer.getString(key: "recents", languageCode: languageCode)
        }
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        updateNavigationBarAppearance()
        
        // old SDK (커스텀 프레젠테이션) 사용 시 상단 네비게이션 바 높이(여백) 추가
        if navigationController?.modalPresentationStyle == .custom {
            navigationController?.additionalSafeAreaInsets.top = 16
        }

        // 투명한 탑바/반투명 배경 지원을 위해 backgroundColor 설정을 제거하고 isTranslucent를 true로 유지합니다.
        navigationController?.view.backgroundColor = .clear
        navigationController?.navigationBar.isTranslucent = true
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isPresentationCompleted = true
        updateCachedAssets()
        // 시트가 large detent에 완전히 안착했을 때 즉시 플래그 해제하기 위해 delegate 등록
        if #available(iOS 15.0, *) {
            navigationController?.sheetPresentationController?.delegate = self
        }
    }
    
    // 시스템 테마 변경 감지
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        if #available(iOS 13.0, *) {
            if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
                // 테마가 변경되면 네비게이션 바 업데이트
                updateNavigationBarAppearance()
            }
        }
    }
    
    // 🧹 뷰가 사라지기 시작할 때: 즉시 캐싱 중단
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // 날짜 인디케이터 타이머 정리
        dateHideTimer?.invalidate()
        dateHideTimer = nil
        scrollUpdateTimer?.invalidate()
        scrollUpdateTimer = nil
        
        // 모든 이미지 캐싱 즉시 중단
        photoManager.stopCachingAllImages()
        
        // Prefetching 즉시 비활성화
        collectionView.isPrefetchingEnabled = false
        
        debugPrint("🧹 [ViewWillDisappear] 갤러리 닫힘 시작: 캐싱 중단")
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        // dismiss된 경우에만 메모리 정리 및 카메라 강제 종료 알림 발송
        let isDismissing = isBeingDismissed || isMovingFromParent || (navigationController?.isBeingDismissed ?? false)
        guard isDismissing else {
            // UIImagePickerController 등 자식 VC가 화면을 덮은 경우 → 카메라 유지
            debugPrint("ℹ️ [ViewDidDisappear] Navigation 전환이므로 메모리 유지")
            return
        }
        
        // 🚀 갤러리가 실제로 닫힐 때 카메라 강제 종료 알림 발송 (고유 ID 포함)
        // 카메라는 어찌됐든 무조건 꺼져야 하므로 최우선으로 발송합니다!
        NotificationCenter.default.post(
            name: NSNotification.Name("GalleryDidDismissNotification"),
            object: nil,
            userInfo: ["galleryID": self.galleryID]
        )
        
        // 🚀 만약 완료 버튼을 눌러서 이미지를 전달 중이라면(hasReturnedImages == true), 
        // 클로저나 네트워크 요청을 끊지 않도록 메모리 정리를 deinit으로 미룹니다.
        if hasReturnedImages {
            debugPrint("ℹ️ [ViewDidDisappear] 이미지 전달 중이므로 메모리 정리를 보류합니다.")
            return
        }
        
        debugPrint("🧹 [ViewDidDisappear] 갤러리 완전 닫힘: 메모리 정리 시작")
        
        // 즉시 메모리 정리
        cleanupMemory()
        
        // PhotoManager 캐싱 매니저 재생성 (강제 정리)
        photoManager.resetCachingManager()
        
        // 추가 메모리 정리 (약간의 딜레이 후)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.forceMemoryCleanup()
        }
    }
    
    // 🧹 강제 정리 (closeGallery 호출 시 사용)
    public func forceCleanupBeforeDismiss() {
        debugPrint("🧹 [ForceCleanupBeforeDismiss] 시작")
        
        // 메모리 정리
        cleanupMemory()
        
        debugPrint("✅ [ForceCleanupBeforeDismiss] 완료")
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        let uiStart = CFAbsoluteTimeGetCurrent()
        print("🟠 [DEBUG] setupUI 시작")
        
        // 배경색 (완전 불투명 색상 지정)
        if #available(iOS 13.0, *) {
            view.backgroundColor = UIColor { traitCollection in
                return traitCollection.userInterfaceStyle == .dark ? UIColor(red: 29/255, green: 29/255, blue: 29/255, alpha: 1.0) : .white
            }
        } else {
            view.backgroundColor = .white
        }
        
        let step1 = CFAbsoluteTimeGetCurrent()
        // 네비게이션 바 초기 설정
        updateNavigationBarAppearance()
        print("🟠 [DEBUG] updateNavigationBarAppearance 완료 - 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - step1))초")
        
        let step2 = CFAbsoluteTimeGetCurrent()
        // 스크롤바 색상 초기 설정
        updateScrollBarColors()
        print("🟠 [DEBUG] updateScrollBarColors 완료 - 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - step2))초")
        
        let step3 = CFAbsoluteTimeGetCurrent()
        view.addSubview(collectionView)
        view.addSubview(loadingIndicator)
        view.addSubview(permissionLabel)
        view.addSubview(scrollBarTrack)
        view.addSubview(scrollBarThumb)
        view.addSubview(dateScrollIndicator)
        dateScrollIndicator.addSubview(dateLabel)
        print("🟠 [DEBUG] 서브뷰 추가 완료 - 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - step3))초")
        
        let thumbTopConstraint = scrollBarThumb.topAnchor.constraint(equalTo: scrollBarTrack.topAnchor)
        scrollBarThumbTopConstraint = thumbTopConstraint
        
        // 날짜 인디케이터 제약 (애니메이션 가능하도록 변수로 저장)
        let dateTrailingConstraint = dateScrollIndicator.trailingAnchor.constraint(equalTo: scrollBarTrack.leadingAnchor, constant: -8)
        let dateCenterYConstraint = dateScrollIndicator.centerYAnchor.constraint(equalTo: scrollBarThumb.centerYAnchor)
        dateIndicatorTrailingConstraint = dateTrailingConstraint
        dateIndicatorCenterYConstraint = dateCenterYConstraint
        
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            permissionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            permissionLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            permissionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            permissionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            
            // 스크롤바 트랙 (오른쪽 끝)
            scrollBarTrack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            scrollBarTrack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            scrollBarTrack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            scrollBarTrack.widthAnchor.constraint(equalToConstant: 4),
            
            // 스크롤바 Thumb (드래그 가능한 부분)
            scrollBarThumb.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -3),
            thumbTopConstraint,
            scrollBarThumb.widthAnchor.constraint(equalToConstant: 6),
            scrollBarThumb.heightAnchor.constraint(equalToConstant: 50),
            
            // 날짜 스크롤 인디케이터 (스크롤바 왼쪽)
            dateTrailingConstraint,
            dateCenterYConstraint,
            dateScrollIndicator.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            dateScrollIndicator.heightAnchor.constraint(equalToConstant: 36),
            
            dateLabel.leadingAnchor.constraint(equalTo: dateScrollIndicator.leadingAnchor, constant: 16),
            dateLabel.trailingAnchor.constraint(equalTo: dateScrollIndicator.trailingAnchor, constant: -16),
            dateLabel.topAnchor.constraint(equalTo: dateScrollIndicator.topAnchor, constant: 8),
            dateLabel.bottomAnchor.constraint(equalTo: dateScrollIndicator.bottomAnchor, constant: -8)
        ])
        
        // 스크롤바 제스처 추가
        setupScrollBarGesture()
    }
    
    private func setupCloseButton() {
        let closeButton = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeButtonTapped)
        )
        navigationItem.leftBarButtonItem = closeButton
    }
    
    private func setupAlbumSelector() {
        navigationItem.titleView = titleContainerView
    }
    
    // 🎨 UI 개선: 앨범 버튼 텍스트 업데이트 (iOS 15+ Configuration 지원)
    func updateAlbumButtonTitle(_ title: String) {
        if #available(iOS 15.0, *) {
            var config = albumButton.configuration ?? UIButton.Configuration.plain()
            
            var titleAttr = AttributedString(title)
            titleAttr.font = .systemFont(ofSize: 17, weight: .bold)
            config.attributedTitle = titleAttr
            
            albumButton.configuration = config
            
            // 텍스트 말줄임표 처리 (항상 1줄 유지)
            albumButton.titleLabel?.lineBreakMode = .byTruncatingTail
            albumButton.titleLabel?.numberOfLines = 1
            albumButton.titleLabel?.adjustsFontSizeToFitWidth = false
        } else {
            albumButton.setTitle(title, for: .normal)
        }
    }
    
    // 네비게이션 바 외형 업데이트 (테마 변경 시 호출)
    private func updateNavigationBarAppearance() {
        guard let navigationBar = navigationController?.navigationBar else { return }
        
        if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            if self.traitCollection.userInterfaceStyle == .dark {
                appearance.backgroundColor = UIColor(red: 29/255, green: 29/255, blue: 29/255, alpha: 1.0)
            } else {
                appearance.backgroundColor = UIColor.systemGroupedBackground
            }
            appearance.shadowColor = nil
            
            navigationBar.standardAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
            navigationBar.compactAppearance = appearance
            if #available(iOS 15.0, *) {
                navigationBar.compactScrollEdgeAppearance = appearance
            }
            
            navigationBar.tintColor = .systemBlue
            
            updateAlbumButtonColor()
            updateScrollBarColors()
        } else {
            navigationBar.barStyle = .default
            navigationBar.isTranslucent = true
            navigationBar.backgroundColor = UIColor(white: 0.95, alpha: 1.0)
            navigationBar.tintColor = UIColor(red: 0, green: 122/255, blue: 1, alpha: 1)
        }
    }
    
    // 앨범 버튼 텍스트 색상 업데이트
    private func updateAlbumButtonColor() {
        if #available(iOS 15.0, *) {
            var config = albumButton.configuration ?? UIButton.Configuration.plain()
            
            // 시스템 테마에 따라 텍스트 색상 설정
            if #available(iOS 13.0, *) {
                if self.traitCollection.userInterfaceStyle == .dark {
                    config.baseForegroundColor = .white
                    albumButton.tintColor = UIColor.white.withAlphaComponent(0.5)
                } else {
                    config.baseForegroundColor = .label
                    albumButton.tintColor = UIColor.label.withAlphaComponent(0.5)
                }
            }
            
            albumButton.configuration = config
        } else {
            albumButton.setTitleColor(.darkText, for: .normal)
        }
    }
    
    // 스크롤바 색상 업데이트 (테마에 따라)
    private func updateScrollBarColors() {
        if #available(iOS 13.0, *) {
            if self.traitCollection.userInterfaceStyle == .dark {
                // 다크 모드: 밝은 색
                scrollBarTrack.backgroundColor = UIColor.white.withAlphaComponent(0.3)
                scrollBarThumb.backgroundColor = UIColor.white.withAlphaComponent(0.7)
                dateScrollIndicator.backgroundColor = UIColor.black.withAlphaComponent(0.5)
                dateLabel.textColor = .white
            } else {
                // 라이트 모드: 어두운 색
                scrollBarTrack.backgroundColor = UIColor.black.withAlphaComponent(0.3)
                scrollBarThumb.backgroundColor = UIColor.black.withAlphaComponent(0.7)
                dateScrollIndicator.backgroundColor = UIColor.white.withAlphaComponent(0.7)
                dateLabel.textColor = .black
            }
        } else {
            scrollBarTrack.backgroundColor = UIColor.darkGray.withAlphaComponent(0.3)
            scrollBarThumb.backgroundColor = UIColor.darkGray.withAlphaComponent(0.7)
            dateScrollIndicator.backgroundColor = UIColor.black.withAlphaComponent(0.5)
            dateLabel.textColor = .white
        }
    }
    
    private func setupScrollBarGesture() {
        // Thumb에 Pan 제스처 추가
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleScrollBarPan(_:)))
        scrollBarThumb.addGestureRecognizer(panGesture)
        scrollBarThumb.isUserInteractionEnabled = true
        
        // 트랙에 Pan 제스처 추가 (드래그 시작 지점이 트랙일 때도 작동)
        let trackPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleScrollBarPan(_:)))
        scrollBarTrack.addGestureRecognizer(trackPanGesture)
        scrollBarTrack.isUserInteractionEnabled = true
        
        // 트랙 탭 제스처
        let trackTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleScrollBarTrackTap(_:)))
        scrollBarTrack.addGestureRecognizer(trackTapGesture)
        
        // 날짜 인디케이터에도 Pan 제스처 추가 (터치 영역 확장)
        let datePanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleScrollBarPan(_:)))
        dateScrollIndicator.addGestureRecognizer(datePanGesture)
        dateScrollIndicator.isUserInteractionEnabled = true
    }
    
    // MARK: - Actions
    
    @objc private func closeButtonTapped() {
        // 닫기 버튼 탭 시 빈 배열 전달
        debugPrint("❌ 취소: 빈 배열 전달")
        hasReturnedImages = true  // 중복 전달 방지
        onImagesSelected?([])  // 빈 배열 전달 (타입: [(PHAsset?, UIImage)])
        dismiss(animated: true)
    }
    
    @objc private func doneButtonTapped() {
        
        // 완료 버튼 탭 시에만 선택된 사진들을 전달
        debugPrint("✅ 완료: \(selectedAssets.count)장의 사진 선택됨")

        // 프로필 모드 + 단일 선택: 크롭 화면으로 이동
        if profileMode && selectedAssets.count == 1, let asset = selectedAssets.first {
            presentProfileCrop(for: asset)
            return
        }

        // editing 모드 + 단일 선택: 편집 화면으로 이동
        if allowsEditing && maxSelection <= 1 && selectedAssets.count == 1 {
            if let asset = selectedAssets.first {
                editingAsset = asset
                // We don't have the cell frame/image here (since it's from done button). Just pass zero/nil.
                onSingleImageTappedForEdit?(asset, .zero, nil)
            }
            return
        }

        // 즉시 dismiss (빠른 반응)
        dismiss(animated: true)

        // 이미지 변환은 백그라운드에서 진행
        returnSelectedImages(shouldDismiss: false)
    }

    // MARK: - Profile Crop

    func presentProfileCrop(for asset: PHAsset) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        // 작업용(Working) 해상도: 화질과 회전 성능의 균형점으로 4096 고정
        // ※ 최종 크롭 출력(maxWidth/maxHeight)은 cropCurrentView()에서 따로 적용
        let workingCap: CGFloat = 4096
        let pxW  = CGFloat(asset.pixelWidth)
        let pxH  = CGFloat(asset.pixelHeight)
        let capScale  = min(workingCap / pxW, workingCap / pxH, 1.0)
        let targetSize = CGSize(width:  (pxW * capScale).rounded(),
                                height: (pxH * capScale).rounded())

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, _ in
            guard let self = self, let image = image else { return }
            DispatchQueue.main.async {
                let cropVC = ProfileCropViewController(image: image)
                cropVC.languageCode = self.languageCode
                // maxWidth / maxHeight — 크롭 출력 사이즈 제한
                cropVC.maxWidth  = self.maxWidth
                cropVC.maxHeight = self.maxHeight
                // themeColor 파싱 후 전달
                cropVC.themeColor = self.parsedThemeColor
                
                var sourceFrame = CGRect.zero
                if let cellFrame = self.frameForAsset(asset) {
                    sourceFrame = cellFrame
                }
                let delegate = ImageEditorTransitionDelegate()
                delegate.sourceFrame = sourceFrame
                delegate.sourceImage = image
                delegate.uncroppedImage = image
                let ratio = CGFloat(asset.pixelWidth) / CGFloat(max(1, asset.pixelHeight))
                delegate.assetAspectRatio = ratio
                delegate.asset = asset
                delegate.frameProvider = { [weak self] currentAsset in
                    return self?.frameForAsset(currentAsset)
                }
                self.profileCropTransitionDelegate = delegate
                cropVC.transitioningDelegate = delegate
                cropVC.modalPresentationStyle = .overFullScreen
                
                var savedDetent: UISheetPresentationController.Detent.Identifier? = nil
                if #available(iOS 15.0, *) {
                    savedDetent = self.navigationController?.sheetPresentationController?.selectedDetentIdentifier
                }
                
                cropVC.onCropComplete = { [weak self, weak cropVC] croppedImage in
                    if self?.allowsEditing == true {
                        self?.onProfileCropComplete?(asset, croppedImage)
                        // 편집 화면이 완전히 열릴 때까지 기다린 후 크롭 화면을 숨김 (닫는 효과)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            cropVC?.view.isHidden = true
                            cropVC?.transitioningDelegate = nil // 중복 애니메이션 방지
                        }
                    } else {
                        cropVC?.dismiss(animated: true) {
                            self?.onProfileCropComplete?(asset, croppedImage)
                        }
                    }
                }
                cropVC.onCancel = { [weak cropVC] in
                    cropVC?.dismiss(animated: true)
                }
                
                self.present(cropVC, animated: true) {
                    if #available(iOS 15.0, *) {
                        if let saved = savedDetent {
                            self.navigationController?.sheetPresentationController?.selectedDetentIdentifier = saved
                        }
                    }
                }
            }
        }
    }

    
    // 이미지 전달 플래그 (중복 전달 방지)
    var hasReturnedImages = false
    
    // MARK: - Image Return Helper
    
    func returnSelectedImages(shouldDismiss: Bool = true) {

        
        // 중복 전달 방지
        guard !hasReturnedImages else {
            if shouldDismiss {
                dismiss(animated: true)
            }
            return
        }
        
        hasReturnedImages = true
        
        // 선택된 이미지가 없으면 빈 배열 전달
        guard !selectedAssets.isEmpty else {
            debugPrint("📤 선택된 이미지 없음 - 빈 배열 전달")
            onImagesSelected?([])
            if shouldDismiss {
                dismiss(animated: true)
            }
            return
        }
        
        debugPrint("📤 \(selectedAssets.count)장의 이미지를 RN으로 전달 시작")

        // ✅ PHImageManager.targetSize는 픽셀(pixel) 단위
        // screen scale을 곱하면 안 됨 (1024 * 3 * 1.2 = 3686px 버그 수정)
        let requestSize: CGSize
        let targetPx = max(maxWidth, maxHeight)
        if targetPx > 0 {
            // 정확히 목적 픽셀 크기로 요청 → Photos가 GPU로 효율적으로 리사이즈
            requestSize = CGSize(width: CGFloat(targetPx), height: CGFloat(targetPx))
        } else {
            // maxWidth/maxHeight 미설정 → OOM 방지를 위해 모바일 최대 안전 해상도(2500px) 캡 적용
            requestSize = CGSize(width: 2500, height: 2500)
        }

        var assetImagePairs: [(PHAsset?, UIImage)] = []
        let lock = NSLock()
        let dispatchGroup = DispatchGroup()
        
        // 메모리 스파이크(OOM) 방지를 위해 시리얼 큐를 활용하여 다중 이미지를 순차 로드합니다.
        let serialQueue = DispatchQueue(label: "com.turboimagepicker.serialLoad", qos: .userInitiated)

        for asset in selectedAssets {
            dispatchGroup.enter()
            
            serialQueue.async {
                let semaphore = DispatchSemaphore(value: 0)
                
                if let editedImg = self.editedImages[asset.localIdentifier] {
                    lock.lock()
                    assetImagePairs.append((asset, editedImg))
                    lock.unlock()
                    semaphore.signal()
                    dispatchGroup.leave()
                } else {
                    _ = self.photoManager.requestFullImage(
                        for: asset,
                        targetSize: requestSize,
                        progressHandler: nil
                    ) { image in
                        if let image = image {
                            lock.lock()
                            assetImagePairs.append((asset, image))
                            lock.unlock()
                        }
                        semaphore.signal()
                        dispatchGroup.leave()
                    }
                }
                
                semaphore.wait()
            }
        }

        dispatchGroup.notify(queue: .main) {
            // 강한 참조를 유지하여 백그라운드 작업 도중 컨트롤러가 해제되지 않게 함

            debugPrint("✅ \(assetImagePairs.count)장의 이미지 변환 완료")

            // 선택 순서 복원 (비동기 응답은 순서가 보장되지 않음)
            let orderedPairs: [(PHAsset?, UIImage)] = self.selectedAssets.compactMap { asset in
                assetImagePairs.first(where: { $0.0 == asset })
            }

            // onImagesSelected 클로저 호출
            self.onImagesSelected?(orderedPairs)

            // 갤러리 닫기
            if shouldDismiss {
                self.dismiss(animated: true)
            }
        }
    }
    
    @objc private func filterSegmentChanged(_ sender: UISegmentedControl) {
        let wasShowingSelected = isShowingOnlySelected
        isShowingOnlySelected = (sender.selectedSegmentIndex == 1)
        
        // 필터 모드가 실제로 변경된 경우에만 갤러리 업데이트
        if wasShowingSelected != isShowingOnlySelected {
            updateGalleryForFilter()
        }
    }
    
    // 🎨 UI 업데이트: 선택 상태에 따라 네비게이션 바 업데이트
    public func updateNavigationBarForSelection() {
        if selectedAssets.isEmpty {
            // 선택 없음: 앨범 버튼 표시, 완료 버튼 숨김
            
            // 선택 없음: 완료 버튼 숨김
            if self.navigationItem.rightBarButtonItem != nil && !self.isDoneButtonAnimating {
                self.isDoneButtonAnimating = true
                
                let targetViewToAnimate = self.doneButton.customView?.superview ?? self.doneButton.customView
                
                // 완벽한 애니메이션 보장을 위해 스냅샷 기법 사용
                // 시스템의 네비게이션바 레이아웃 갱신(UIBarButtonItem 제거 등)에 의해 애니메이션이 씹히는 것을 원천 차단합니다.
                if let targetView = targetViewToAnimate,
                   let navBar = self.navigationController?.navigationBar,
                   let snapshot = targetView.snapshotView(afterScreenUpdates: false) {
                    
                    // 스냅샷을 네비게이션 바에 동일한 위치에 추가
                    snapshot.frame = targetView.convert(targetView.bounds, to: navBar)
                    navBar.addSubview(snapshot)
                    
                    // 실제 버튼은 즉시 제거하여 레이아웃 충돌 방지
                    self.navigationItem.setRightBarButton(nil, animated: false)
                    self.isDoneButtonAnimating = false
                    
                    // 스냅샷으로 애니메이션 진행 (절대 취소되지 않음)
                    UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseIn, animations: {
                        snapshot.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
                        snapshot.alpha = 0
                    }) { _ in
                        snapshot.removeFromSuperview()
                    }
                } else {
                    self.navigationItem.setRightBarButton(nil, animated: false)
                    self.isDoneButtonAnimating = false
                }
                
                UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseIn, animations: {
                    self.filterSegmentControl.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                    self.filterSegmentControl.alpha = 0
                }) { _ in
                    // 앨범 버튼으로 전환 (페이드 인)
                    self.albumButton.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                    self.albumButton.alpha = 0
                    
                    UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: .curveEaseOut) {
                        self.albumButton.transform = .identity
                        self.albumButton.alpha = 1
                    }
                    
                    self.isShowingOnlySelected = false
                    self.filterSegmentControl.selectedSegmentIndex = 0
                    self.filterSegmentControl.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                    self.filterSegmentControl.alpha = 0
                }
                
                self.isShowingFilterSegment = false
            } else if isShowingFilterSegment {
                self.isShowingFilterSegment = false
                
                UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseIn, animations: {
                    self.filterSegmentControl.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                    self.filterSegmentControl.alpha = 0
                }) { _ in
                    // 앨범 버튼으로 전환 (페이드 인)
                    self.albumButton.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                    self.albumButton.alpha = 0
                    
                    UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: .curveEaseOut) {
                        self.albumButton.transform = .identity
                        self.albumButton.alpha = 1
                    }
                    
                    self.isShowingOnlySelected = false
                    self.filterSegmentControl.selectedSegmentIndex = 0
                    self.filterSegmentControl.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                    self.filterSegmentControl.alpha = 0
                }
            }
            
        } else {
            // 선택 있음: 세그먼트 컨트롤 표시, 완료 버튼 표시
            
            // 세그먼트 컨트롤 텍스트 업데이트 (레이아웃 변경 없이)
            UIView.performWithoutAnimation {
                self.filterSegmentControl.setTitle("\(self.selectedAssets.count) \(self.selectedItemsText)", forSegmentAt: 1)
                self.filterSegmentControl.layoutIfNeeded()
            }
            
            // 커스텀 버튼 텍스트 업데이트 (숫자)
            let newCountStr = "\(selectedAssets.count)"
            if let btn = doneButton.customView as? UIButton {
                let currentTitle = btn.title(for: .normal)?.trimmingCharacters(in: .whitespaces) ?? ""
                
                if currentTitle != newCountStr {
                    let currentCount = Int(currentTitle) ?? 0
                    let newCount = selectedAssets.count
                    
                    // 텍스트(숫자)만 위/아래로 이동하는 애니메이션
                    if let titleLayer = btn.titleLabel?.layer {
                        let transition = CATransition()
                        transition.type = .push
                        transition.subtype = newCount > currentCount ? .fromTop : .fromBottom
                        transition.duration = 0.2
                        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        titleLayer.add(transition, forKey: "pushText")
                    }
                    
                    btn.setTitle(" \(newCountStr)", for: .normal)
                }
            }
            
            // 🎨 재미있는 등장 애니메이션
            let isFirstSelection = !isShowingFilterSegment
            
            if isFirstSelection {
                self.isShowingFilterSegment = true
                
                // 처음 선택 시: 바운스 애니메이션
                
                // 앨범 버튼 축소 애니메이션
                UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn, animations: {
                    self.albumButton.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                    self.albumButton.alpha = 0
                }) { _ in
                    // 세그먼트 컨트롤과 완료 버튼 동시 등장 (바운스)
                    self.filterSegmentControl.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
                    self.filterSegmentControl.alpha = 0
                    
                    if self.navigationItem.rightBarButtonItem == nil {
                        self.navigationItem.setRightBarButton(self.doneButton, animated: false)
                        self.navigationController?.navigationBar.layoutIfNeeded()
                    }
                    
                    let targetViewToAnimate = self.doneButton.customView
                    targetViewToAnimate?.superview?.clipsToBounds = false
                    
                    targetViewToAnimate?.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
                    targetViewToAnimate?.alpha = 0
                    
                    UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: .curveEaseOut) {
                        self.filterSegmentControl.transform = .identity
                        self.filterSegmentControl.alpha = 1
                        
                        targetViewToAnimate?.transform = .identity
                        targetViewToAnimate?.alpha = 1
                    }
                    
                    self.albumButton.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                    self.albumButton.alpha = 0
                }
            }
        }
    }
    
    // 🔄 필터에 따라 갤러리 업데이트
    func updateGalleryForFilter() {
        UIView.transition(
            with: collectionView,
            duration: 0.25,
            options: .transitionCrossDissolve,
            animations: {
                self.collectionView.reloadData()
                self.collectionView.contentOffset = .zero  // 맨 위로 스크롤
            }
        )
    }
    
    @objc private func albumButtonTapped() {
        // 앨범 로딩이 완료될 때까지 기다린 후 표시
        loadAlbumsAndShowPicker()
    }
    
    @objc private func handleScrollBarPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            isDraggingScrollBar = true
            showScrollBarAndDate()
            dateHideTimer?.invalidate()
            
            // 날짜 인디케이터를 화면 중앙으로 애니메이션
            moveDateIndicatorToCenter(animated: true)
            
            // 햅틱 준비
            hapticFeedback.prepare()
            lastHapticDate = ""
            
            // 캐싱 중단 (스냅샷 성능 향상)
            photoManager.stopCachingAllImages()
            collectionView.isPrefetchingEnabled = false
            
            // 스냅샷 시간 초기화
            lastSnapshotTime = CACurrentMediaTime()
            
            // 제스처가 트랙이나 날짜 인디케이터에서 시작된 경우, thumb 위치로 점프
            if gesture.view == scrollBarTrack || gesture.view == dateScrollIndicator {
                let location = gesture.location(in: scrollBarTrack)
                updateScrollBarThumbOnly(location.y)
                // 시작 시 즉시 스냅샷
                scrollToThumbPositionSnapshot(withHaptic: true)
            }
            
        case .changed:
            let translation = gesture.translation(in: view)
            updateScrollBarThumbWithTranslation(translation.y)
            gesture.setTranslation(.zero, in: view)
            
            // 0.05초마다 스냅샷 표시
            let currentTime = CACurrentMediaTime()
            if currentTime - lastSnapshotTime >= 0.05 {
                scrollToThumbPositionSnapshot(withHaptic: true)
                lastSnapshotTime = currentTime
            }
            
        case .ended, .cancelled:
            isDraggingScrollBar = false
            
            // 날짜 인디케이터를 원래 위치로 애니메이션
            moveDateIndicatorToEdge(animated: true)
            
            // 드래그 종료 시 최종 위치로 이동
            scrollToThumbPosition()
            
            // 햅틱 초기화
            lastHapticDate = ""
            
            // 캐싱 재개
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.collectionView.isPrefetchingEnabled = true
                self?.updateCachedAssets()
            }
            
            scheduleDateIndicatorHide()
            
        default:
            break
        }
    }
    
    
    @objc private func handleScrollBarTrackTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: scrollBarTrack)
        let trackHeight = scrollBarTrack.bounds.height
        
        // 트랙 내에서의 비율 계산
        let ratio = max(0, min(1, location.y / trackHeight))
        
        // CollectionView 스크롤
        let contentHeight = collectionView.contentSize.height
        let visibleHeight = collectionView.bounds.height
        let maxOffset = contentHeight - visibleHeight
        let targetOffset = maxOffset * ratio
        
        collectionView.setContentOffset(
            CGPoint(x: 0, y: targetOffset),
            animated: true
        )
        
        showScrollBarAndDate()
        scheduleDateIndicatorHide()
    }
    
    private func updateScrollBarThumbOnly(_ y: CGFloat) {
        guard let constraint = scrollBarThumbTopConstraint else { return }
        
        let trackHeight = scrollBarTrack.bounds.height
        let thumbHeight = scrollBarThumb.bounds.height
        let maxOffset = trackHeight - thumbHeight
        
        // Thumb 중앙이 터치 지점에 오도록 조정
        let newConstant = max(0, min(maxOffset, y - thumbHeight / 2))
        constraint.constant = newConstant
        
        // 날짜만 업데이트 (스크롤은 하지 않음)
        updateDateForThumbPosition()
    }
    
    private func updateScrollBarThumbWithTranslation(_ translationY: CGFloat) {
        guard let constraint = scrollBarThumbTopConstraint else { return }
        
        let trackHeight = scrollBarTrack.bounds.height
        let thumbHeight = scrollBarThumb.bounds.height
        let maxOffset = trackHeight - thumbHeight
        
        // 새로운 thumb 위치 계산 (즉시 업데이트)
        let newConstant = max(0, min(maxOffset, constraint.constant + translationY))
        constraint.constant = newConstant
        
        // 날짜만 업데이트 (스크롤은 하지 않음)
        scrollUpdateTimer?.invalidate()
        scrollUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            self?.updateDateForThumbPosition()
        }
    }
    
    private func scrollToThumbPositionSnapshot(withHaptic: Bool = false) {
        guard let constraint = scrollBarThumbTopConstraint else { return }
        
        let trackHeight = scrollBarTrack.bounds.height
        let thumbHeight = scrollBarThumb.bounds.height
        let maxOffset = trackHeight - thumbHeight
        
        // 비율 계산
        let ratio = maxOffset > 0 ? constraint.constant / maxOffset : 0
        
        // CollectionView 스크롤 (스냅샷 - 즉시 이동)
        let contentHeight = collectionView.contentSize.height
        let visibleHeight = collectionView.bounds.height
        let maxContentOffset = max(0, contentHeight - visibleHeight)
        let targetOffset = maxContentOffset * ratio
        
        collectionView.setContentOffset(
            CGPoint(x: 0, y: targetOffset),
            animated: false
        )
        
        // 날짜 업데이트 및 햅틱
        let currentDate = getCurrentDateForThumbPosition()
        updateDateForThumbPosition()
        
        // 날짜가 변경되었을 때만 햅틱 발생
        if withHaptic && currentDate != lastHapticDate {
            hapticFeedback.selectionChanged()
            hapticFeedback.prepare()  // 다음 햅틱 준비
            lastHapticDate = currentDate
        }
    }
    
    private func getCurrentDateForThumbPosition() -> String {
        guard let constraint = scrollBarThumbTopConstraint else { return "" }
        
        let trackHeight = scrollBarTrack.bounds.height
        let thumbHeight = scrollBarThumb.bounds.height
        let maxOffset = trackHeight - thumbHeight
        
        // 비율 계산
        let ratio = maxOffset > 0 ? constraint.constant / maxOffset : 0
        
        // 해당 위치의 asset index 계산
        let totalAssets = assets.count
        guard totalAssets > 0 else { return "" }
        
        let estimatedIndex = Int(CGFloat(totalAssets - 1) * ratio)
        let safeIndex = max(0, min(totalAssets - 1, estimatedIndex))
        
        let asset = assets[safeIndex]
        return formatDate(asset.creationDate)
    }
    
    private func scrollToThumbPosition() {
        guard let constraint = scrollBarThumbTopConstraint else { return }
        
        let trackHeight = scrollBarTrack.bounds.height
        let thumbHeight = scrollBarThumb.bounds.height
        let maxOffset = trackHeight - thumbHeight
        
        // 비율 계산
        let ratio = maxOffset > 0 ? constraint.constant / maxOffset : 0
        
        // CollectionView 스크롤 (최종 위치)
        let contentHeight = collectionView.contentSize.height
        let visibleHeight = collectionView.bounds.height
        let maxContentOffset = max(0, contentHeight - visibleHeight)
        let targetOffset = maxContentOffset * ratio
        
        collectionView.setContentOffset(
            CGPoint(x: 0, y: targetOffset),
            animated: false
        )
        
        // 날짜 업데이트
        updateDateForThumbPosition()
    }
    
    private func updateDateForThumbPosition() {
        guard let constraint = scrollBarThumbTopConstraint else { return }
        
        let trackHeight = scrollBarTrack.bounds.height
        let thumbHeight = scrollBarThumb.bounds.height
        let maxOffset = trackHeight - thumbHeight
        
        // 비율 계산
        let ratio = maxOffset > 0 ? constraint.constant / maxOffset : 0
        
        // 해당 위치의 asset index 계산
        let totalAssets = assets.count
        guard totalAssets > 0 else { return }
        
        let estimatedIndex = Int(CGFloat(totalAssets - 1) * ratio)
        let safeIndex = max(0, min(totalAssets - 1, estimatedIndex))
        
        let asset = assets[safeIndex]
        let dateString = formatDate(asset.creationDate)
        
        if dateLabel.text != dateString {
            dateLabel.text = dateString
            // 🔧 수정: 날짜 정보가 없으면 dateScrollIndicator 숨김
            let isDateEmpty = dateString.isEmpty
            UIView.animate(withDuration: 0.2) {
                self.dateScrollIndicator.alpha = (isDateEmpty || self.scrollBarTrack.alpha == 0) ? 0 : 1
            }
        }
    }
    
    // MARK: - Album Selection
    
    private func loadAlbumsInBackground() {
        // 🚀 성능 최적화: 백그라운드에서 앨범 로딩 (지연 제거 - 더 빠른 로딩)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            self.photoManager.fetchAlbums { [weak self] albums in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.albums = albums
                    self.albumsLoaded = true
                    
                    if self.selectedAlbum == nil {
                        if let recentsAlbum = albums.first(where: { $0.collection.assetCollectionSubtype == .smartAlbumUserLibrary }) {
                            self.selectedAlbum = recentsAlbum
                            // 최근 항목 앨범은 언어 설정에 따른 텍스트 사용
                            self.updateAlbumButtonTitle(self.recentsAlbumText)
                        }
                    }
                    
                    debugPrint("📸 앨범 \(albums.count)개 미리 로딩 완료")
                }
            }
        }
    }
    
    private func loadAlbumsAndShowPicker() {
        // 이미 로딩된 경우 바로 표시
        if albumsLoaded && !albums.isEmpty {
            showAlbumPicker()
            return
        }
        
        // 아직 로딩 중인 경우 완료될 때까지 대기
        // 최대 2초까지 대기 (타임아웃 방지)
        var retryCount = 0
        let maxRetries = 20 // 0.1초 * 20 = 최대 2초
        
        func checkAndShow() {
            if albumsLoaded && !albums.isEmpty {
                showAlbumPicker()
            } else {
                retryCount += 1
                if retryCount < maxRetries {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        checkAndShow()
                    }
                } else {
                    // 타임아웃: 빈 앨범으로라도 표시 (오류 방지)
                    debugPrint("⚠️ 앨범 로딩 타임아웃 - 빈 리스트로 표시")
                    showAlbumPicker()
                }
            }
        }
        
        checkAndShow()
    }
    
    private func showAlbumPicker() {
        let albumPicker = AlbumPickerViewController()
        albumPicker.albums = albums
        albumPicker.selectedAlbum = selectedAlbum
        albumPicker.delegate = self
        albumPicker.themeColor = parsedThemeColor
        
        // 중앙 팝업으로 표시
        albumPicker.modalPresentationStyle = .overCurrentContext
        albumPicker.modalTransitionStyle = .crossDissolve
        
        // 뒤 화면 스크롤 방지
        collectionView.isScrollEnabled = false
        
        present(albumPicker, animated: false)
    }
    
    // MARK: - Photo Library
    
    private func checkPhotoLibraryPermission() {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("🔴 [DEBUG] checkPhotoLibraryPermission 시작")
        
        let step1 = CFAbsoluteTimeGetCurrent()
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        print("🔴 [DEBUG] authorizationStatus 확인 완료 - 상태: \(status.rawValue), 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - step1))초")
        
        switch status {
        case .authorized, .limited:
            print("🔴 [DEBUG] 권한 있음 - loadPhotosInPhases 호출")
            loadPhotosInPhases()
        case .notDetermined:
            print("🔴 [DEBUG] 권한 미확정 - requestPhotoLibraryPermission 호출")
            requestPhotoLibraryPermission()
        case .denied, .restricted:
            print("🔴 [DEBUG] 권한 거부됨 - showPermissionDenied 호출")
            showPermissionDenied()
        @unknown default:
            print("🔴 [DEBUG] 알 수 없는 상태 - showPermissionDenied 호출")
            showPermissionDenied()
        }
        
        print("🔴 [DEBUG] checkPhotoLibraryPermission 완료 - 총 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime))초")
    }
    
    private func requestPhotoLibraryPermission() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .limited:
                    self?.loadPhotosInPhases()
                case .denied, .restricted:
                    self?.showPermissionDenied()
                default:
                    break
                }
            }
        }
    }
    
    private func showPermissionDenied() {
        permissionLabel.isHidden = false
        collectionView.isHidden = true
        
        let settingsButton = UIBarButtonItem(
            title: "설정",
            style: .plain,
            target: self,
            action: #selector(openSettings)
        )
        navigationItem.rightBarButtonItem = settingsButton
    }
    
    @objc private func openSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(settingsUrl) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    // MARK: - 🚀 텔레그램 방식: 2단계 로딩
    
    private func loadPhotosInPhases() {
        let phaseStartTime = CFAbsoluteTimeGetCurrent()
        print("🟣 [DEBUG] loadPhotosInPhases 시작")
        
        guard !isLoadingInitial else {
            print("🟣 [DEBUG] 이미 로딩 중 - 중복 호출 방지")
            return
        }
        isLoadingInitial = true
        loadingIndicator.startAnimating()
        print("🟣 [DEBUG] 로딩 인디케이터 시작")
        
        // 🚀 성능 최적화: 첫 로딩인지 확인 (assets가 비어있으면 첫 로딩)
        let isFirstLoad = assets.isEmpty
        print("🟣 [DEBUG] 첫 로딩 여부: \(isFirstLoad)")
        
        // 첫 로딩이 아닐 때만 cleanup 실행
        if !isFirstLoad {
            let cleanupStart = CFAbsoluteTimeGetCurrent()
            cleanupBeforeReload()
            print("🟣 [DEBUG] cleanupBeforeReload 완료 - 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - cleanupStart))초")
        } else {
            print("🟣 [DEBUG] 첫 로딩이므로 cleanup 스킵")
        }
        
        // 🚀 성능 최적화: 백그라운드에서 즉시 로딩 시작
        let fetchStartTime = CFAbsoluteTimeGetCurrent()
        print("🟣 [DEBUG] fetchInitialPhotos 호출 시작")
        photoManager.fetchInitialPhotos(from: selectedAlbum) { [weak self] initialAssets in
            guard let self = self else {
                print("🟣 [DEBUG] self가 nil - fetch 완료")
                return
            }
            
            let fetchTime = CFAbsoluteTimeGetCurrent() - fetchStartTime
            print("🟣 [DEBUG] fetchInitialPhotos 완료 - \(initialAssets.count)장, 경과: \(String(format: "%.3f", fetchTime))초")
            debugPrint("⚡️ 초기 \(initialAssets.count)장 로딩: \(String(format: "%.2f", fetchTime))초")
            
            let mainStart = CFAbsoluteTimeGetCurrent()
            DispatchQueue.main.async {
                print("🟣 [DEBUG] 메인 스레드에서 UI 업데이트 시작")
                self.assets = initialAssets
                self.collectionView.reloadData()
                self.loadingIndicator.stopAnimating()
                self.isLoadingInitial = false
                self.permissionLabel.isHidden = true
                self.collectionView.isHidden = false
                print("🟣 [DEBUG] UI 업데이트 완료 - 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - mainStart))초")
                
                // 우선순위: 1. 이니셜 이미지 → 2. 대량 이미지 로딩 → 3. 캐싱 시작
                self.loadRemainingPhotosInBackground()
                print("✅ [DEBUG] loadPhotosInPhases 전체 완료 - 총 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - phaseStartTime))초")
            }
        }
    }
    
    func loadPhotosWithTransition() {
        guard !isLoadingInitial else { return }
        isLoadingInitial = true
        
        // 인디케이터 표시 (작게)
        loadingIndicator.startAnimating()
        
        // 백그라운드에서 새 이미지 로딩
        let startTime = CFAbsoluteTimeGetCurrent()
        photoManager.fetchInitialPhotos(from: selectedAlbum) { [weak self] initialAssets in
            guard let self = self else { return }
            
            let loadTime = CFAbsoluteTimeGetCurrent() - startTime
            debugPrint("⚡️ 초기 \(initialAssets.count)장 로딩: \(String(format: "%.2f", loadTime))초")
            
            DispatchQueue.main.async {
                // 페이드 애니메이션으로 전환
                UIView.transition(with: self.collectionView,
                                duration: 0.25,
                                options: .transitionCrossDissolve,
                                animations: {
                    // 선택 배열 초기화
                    self.selectedAssets.removeAll()
                    self.selectedAssetsSet.removeAll()
                    
                    // 새 데이터 설정
                    self.assets = initialAssets
                    self.collectionView.reloadData()
                    self.collectionView.contentOffset = .zero  // 맨 위로 스크롤
                }) { _ in
                    self.loadingIndicator.stopAnimating()
                    self.isLoadingInitial = false
                    
                    // 대량 이미지 로딩
                    self.loadRemainingPhotosInBackground()
                }
            }
        }
    }
    
    private func loadRemainingPhotosInBackground() {
        guard !isLoadingRemaining else { return }
        isLoadingRemaining = true
        
        let currentCount = assets.count
        
        // 우선순위 높게 설정 (userInitiated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            self.photoManager.fetchAllPhotosMetadata(
                from: self.selectedAlbum,
                skip: currentCount
            ) { [weak self] remainingAssets in
                guard let self = self else { return }
                
                debugPrint("📦 추가 \(remainingAssets.count)장 메타데이터 로딩 완료 (총: \(currentCount + remainingAssets.count)장)")
                
                DispatchQueue.main.async {
                    // 뷰가 여전히 표시 중인지 확인
                    guard self.isViewLoaded && self.view.window != nil else {
                        print(" 뷰가 닫혀서 로딩 취소")
                        return
                    }
                    
                    self.assets.append(contentsOf: remainingAssets)
                    
                    self.collectionView.performBatchUpdates {
                        let startIndex = currentCount
                        let endIndex = self.assets.count
                        let newIndexPaths = (startIndex..<endIndex).map { IndexPath(item: $0, section: 0) }
                        self.collectionView.insertItems(at: newIndexPaths)
                    } completion: { _ in
                        // 대량 이미지 로딩 완료 후 캐싱 시작
                        self.updateCachedAssets()
                    }
                    
                    self.isLoadingRemaining = false
                }
            }
        }
    }
    
    // MARK: - Asset Caching
    
    func updateCachedAssets() {
        guard isViewLoaded && view.window != nil else { return }
        
        let visibleRect = CGRect(
            origin: collectionView.contentOffset,
            size: collectionView.bounds.size
        )
        
        // 🚀 성능 최적화: 캐싱 범위 확대 (0.5 → 1.0)
        // 더 넓은 범위를 미리 캐싱하여 빠른 스크롤 시에도 이미지가 준비됨
        let preheatRect = visibleRect.insetBy(
            dx: 0,
            dy: -1.0 * visibleRect.height
        )
        
        // 🚀 성능 최적화: 업데이트 임계값 감소 (1/3 → 1/4)
        // 더 자주 캐싱 업데이트하여 스크롤 시 이미지 로딩 지연 감소
        let delta = abs(preheatRect.midY - previousPreheatRect.midY)
        guard delta > view.bounds.height / 4 else { return }
        
        let (addedAssets, removedAssets) = differencesBetweenRects(
            previousPreheatRect,
            preheatRect
        )
        
        // 백그라운드에서 캐싱 (메인 스레드 부담 감소)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            self.photoManager.startCachingImages(
                for: addedAssets,
                targetSize: self.thumbnailSize
            )
            self.photoManager.stopCachingImages(
                for: removedAssets,
                targetSize: self.thumbnailSize
            )
        }
        
        previousPreheatRect = preheatRect
    }
    
    private func differencesBetweenRects(
        _ old: CGRect,
        _ new: CGRect
    ) -> ([PHAsset], [PHAsset]) {
        let oldIndexPaths = indexPathsForElements(in: old)
        let newIndexPaths = indexPathsForElements(in: new)
        
        let added = newIndexPaths.subtracting(oldIndexPaths)
        let removed = oldIndexPaths.subtracting(newIndexPaths)
        
        let addedAssets = added.compactMap { indexPath -> PHAsset? in
            guard indexPath.item < assets.count else { return nil }
            return assets[indexPath.item]
        }
        
        let removedAssets = removed.compactMap { indexPath -> PHAsset? in
            guard indexPath.item < assets.count else { return nil }
            return assets[indexPath.item]
        }
        
        return (addedAssets, removedAssets)
    }
    
    private func indexPathsForElements(in rect: CGRect) -> Set<IndexPath> {
        guard let layoutAttributes = collectionView.collectionViewLayout
            .layoutAttributesForElements(in: rect) else {
            return []
        }
        return Set(layoutAttributes.map { $0.indexPath })
    }
    
    // MARK: - 날짜 스크롤바 로직
    
    func updateDateScrollIndicator() {
        // 드래그 중이 아닐 때만 자동 업데이트
        guard !isDraggingScrollBar else { return }
        
        // 스크롤바 위치 업데이트
        updateScrollBarThumbPosition()
        
        // 날짜 업데이트
        updateDateForCurrentScroll()
        
        // 인디케이터 표시
        showScrollBarAndDate()
        
        // 🔧 수정: 스크롤 중에도 타이머 재스케줄링
        scheduleDateIndicatorHide()
    }
    
    private func updateScrollBarThumbPosition() {
        guard let constraint = scrollBarThumbTopConstraint else { return }
        
        let contentHeight = collectionView.contentSize.height
        let visibleHeight = collectionView.bounds.height
        let contentOffset = collectionView.contentOffset.y
        
        guard contentHeight > visibleHeight else { return }
        
        let trackHeight = scrollBarTrack.bounds.height
        let thumbHeight = scrollBarThumb.bounds.height
        let maxThumbOffset = trackHeight - thumbHeight
        
        // 스크롤 비율 계산
        let scrollRatio = contentOffset / (contentHeight - visibleHeight)
        let newConstant = maxThumbOffset * scrollRatio
        
        constraint.constant = max(0, min(maxThumbOffset, newConstant))
    }
    
    private func updateDateForCurrentScroll() {
        // 현재 화면에 보이는 첫 번째 셀의 날짜 가져오기
        guard let visibleIndexPaths = collectionView.indexPathsForVisibleItems.sorted(by: { $0.item < $1.item }).first else {
            return
        }
        
        // 카메라 셀은 스킵
        let assetIndex = shouldShowCamera ? visibleIndexPaths.item - 1 : visibleIndexPaths.item
        guard assetIndex >= 0 && assetIndex < assets.count else {
            return
        }
        
        let asset = assets[assetIndex]
        let dateString = formatDate(asset.creationDate)
        
        // 날짜가 변경된 경우에만 업데이트
        if dateLabel.text != dateString {
            dateLabel.text = dateString
            // 🔧 수정: 날짜 정보가 없으면 dateScrollIndicator 숨김
            let isDateEmpty = dateString.isEmpty
            UIView.animate(withDuration: 0.2) {
                self.dateScrollIndicator.alpha = (isDateEmpty || self.scrollBarTrack.alpha == 0) ? 0 : 1
            }
        }
    }
    
    private func moveDateIndicatorToCenter(animated: Bool) {
        guard let trailingConstraint = dateIndicatorTrailingConstraint else { return }
        
        // 화면 중앙으로 이동 (오른쪽 끝에서 중앙으로)
        trailingConstraint.isActive = false
        dateIndicatorTrailingConstraint = dateScrollIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        dateIndicatorTrailingConstraint?.isActive = true
        
        if animated {
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                usingSpringWithDamping: 0.8,
                initialSpringVelocity: 0.5,
                options: [.curveEaseOut],
                animations: {
                    self.view.layoutIfNeeded()
                }
            )
        } else {
            view.layoutIfNeeded()
        }
    }
    
    private func moveDateIndicatorToEdge(animated: Bool) {
        guard let constraint = dateIndicatorTrailingConstraint else { return }
        
        // 원래 위치로 복귀 (스크롤바 왼쪽)
        constraint.isActive = false
        dateIndicatorTrailingConstraint = dateScrollIndicator.trailingAnchor.constraint(equalTo: scrollBarTrack.leadingAnchor, constant: -8)
        dateIndicatorTrailingConstraint?.isActive = true
        
        if animated {
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                usingSpringWithDamping: 0.8,
                initialSpringVelocity: 0.5,
                options: [.curveEaseOut],
                animations: {
                    self.view.layoutIfNeeded()
                }
            )
        } else {
            view.layoutIfNeeded()
        }
    }
    
    private func showScrollBarAndDate() {
        let isDateEmpty = dateLabel.text?.isEmpty ?? true
        
        UIView.animate(withDuration: 0.2) {
            self.scrollBarTrack.alpha = 1
            self.scrollBarThumb.alpha = 1
            self.dateScrollIndicator.alpha = isDateEmpty ? 0 : 1
        }
    }
    
    func scheduleDateIndicatorHide() {
        dateHideTimer?.invalidate()
        dateHideTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.hideScrollBarAndDate()
        }
    }
    
    private func hideScrollBarAndDate() {
        // 🔧 수정: 드래그 중이거나 이미 숨겨진 상태면 스킵
        guard !isDraggingScrollBar else { return }
        guard scrollBarTrack.alpha > 0 || scrollBarThumb.alpha > 0 || dateScrollIndicator.alpha > 0 else {
            return
        }
        
        UIView.animate(withDuration: 0.3) {
            self.scrollBarTrack.alpha = 0
            self.scrollBarThumb.alpha = 0
            self.dateScrollIndicator.alpha = 0
        }
    }
    
    // 🚀 성능 최적화: languageCode별 locale/format 매핑 테이블
    private static let localeMap: [String: String] = [
        "ko": "ko_KR", "ja": "ja_JP", "zh": "zh_CN", "de": "de_DE",
        "es": "es_ES", "fr": "fr_FR", "hi": "hi_IN", "id": "id_ID",
        "it": "it_IT", "ms": "ms_MY", "nl": "nl_NL", "pl": "pl_PL",
        "pt": "pt_PT", "ru": "ru_RU", "th": "th_TH", "tr": "tr_TR",
        "vi": "vi_VN", "da": "da_DK", "en": "en_US"
    ]
    
    private static let formatMap: [String: String] = [
        "ko": "yyyy년 M월", "ja": "yyyy年M月", "zh": "yyyy年M月"
        // 나머지 언어는 기본값 "MMM yyyy" 사용
    ]
    
    /// DateFormatter를 languageCode 기반으로 생성 (캐싱용)
    private static func buildDateFormatter(for languageCode: String) -> DateFormatter {
        let df = DateFormatter()
        let localeId = localeMap[languageCode] ?? "en_US"
        df.locale = Locale(identifier: localeId)
        df.dateFormat = formatMap[languageCode] ?? "MMM yyyy"
        return df
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "" }
        return cachedDateFormatter.string(from: date)
    }
    
    // MARK: - Memory Management
    
    // 🧹 앨범 변경이나 재로딩 전 정리
    private func cleanupBeforeReload() {
        debugPrint("🧹 [CleanupBeforeReload] 시작")
        
        // 1. PHCachingImageManager 캐시 정리
        photoManager.stopCachingAllImages()
        
        // 2. Assets 배열 비우기
        assets.removeAll(keepingCapacity: false)
        
        // 3. 선택 배열 비우기
        selectedAssets.removeAll(keepingCapacity: false)
        selectedAssetsSet.removeAll()
        
        // 4. CollectionView 리로드 (재사용 풀에 모든 셀 반환)
        collectionView.reloadData()
        
        // 5. Preheat rect 리셋
        previousPreheatRect = .zero
        
        debugPrint("🧹 [CleanupBeforeReload] 완료")
    }
    
    // 🧹 뷰가 닫힐 때 적극적인 메모리 정리 (최우선순위: 닫힐 때 특히 중요!)
    private func cleanupMemory() {
        debugPrint("🧹 [CleanupMemory] 시작 - 갤러리 닫힘")
        
        // === 0단계: Timer 즉시 정리 (메모리 누수 방지) ===
        dateHideTimer?.invalidate()
        dateHideTimer = nil
        scrollUpdateTimer?.invalidate()
        scrollUpdateTimer = nil
        debugPrint("   ✓ Timer 정리")
        
        // === 1단계: 이미지 캐싱 즉시 중단 ===
        photoManager.stopCachingAllImages()
        debugPrint("   ✓ PHCachingImageManager 캐시 중단")
        
        // === 2단계: CollectionView Delegate/DataSource 해제 (순환 참조 방지) ===
        collectionView.delegate = nil
        collectionView.dataSource = nil
        collectionView.prefetchDataSource = nil
        debugPrint("   ✓ CollectionView delegates 해제")
        
        // === 3단계: 모든 셀을 재사용 풀로 반환 + 셀의 이미지 즉시 해제 ===
        // 먼저 visible cells의 이미지를 명시적으로 해제
        collectionView.visibleCells.forEach { cell in
            if let galleryCell = cell as? GalleryCell {
                galleryCell.prepareForReuse()
            }
        }
        
        // reloadData()로 모든 셀을 재사용 풀에 반환
        collectionView.reloadData()
        debugPrint("   ✓ CollectionView 셀 정리 및 재사용 풀 반환")
        
        // === 4단계: TurboImageCache 완전히 비우기 ===
        imageCache.clearCache()
        debugPrint("   ✓ TurboImageCache 비움")
        
        // === 5단계: PHAsset 배열 비우기 (큰 메모리 차지) ===
        let assetCount = assets.count
        assets.removeAll(keepingCapacity: false)  // capacity도 해제
        debugPrint("   ✓ PHAsset 배열 해제 (\(assetCount)개)")
        
        // === 6단계: 앨범 데이터 비우기 ===
        let albumCount = albums.count
        albums.removeAll(keepingCapacity: false)
        selectedAlbum = nil
        albumsLoaded = false
        debugPrint("   ✓ 앨범 데이터 해제 (\(albumCount)개)")
        
        // === 7단계: Gesture Recognizers 제거 (메모리 누수 방지) ===
        scrollBarThumb.gestureRecognizers?.forEach { scrollBarThumb.removeGestureRecognizer($0) }
        scrollBarTrack.gestureRecognizers?.forEach { scrollBarTrack.removeGestureRecognizer($0) }
        dateScrollIndicator.gestureRecognizers?.forEach { dateScrollIndicator.removeGestureRecognizer($0) }
        scrollBarThumb.isUserInteractionEnabled = false
        scrollBarTrack.isUserInteractionEnabled = false
        dateScrollIndicator.isUserInteractionEnabled = false
        debugPrint("   ✓ Gesture Recognizers 제거")
        
        // === 8단계: 선택된 사진 배열 비우기 ===
        selectedAssets.removeAll(keepingCapacity: false)
        selectedAssetsSet.removeAll()
        debugPrint("   ✓ 선택 배열 해제")
        
        // === 9단계: NavigationItem UI 컴포넌트 해제 ===
        navigationItem.titleView = nil
        navigationItem.leftBarButtonItem = nil
        navigationItem.rightBarButtonItem = nil
        debugPrint("   ✓ NavigationItem UI 해제")
        
        // === 10단계: Presentation Controller Delegate 해제 ===
        navigationController?.presentationController?.delegate = nil
        debugPrint("   ✓ Presentation Controller Delegate 해제")
        
        // === 11단계: 기타 참조 및 플래그 리셋 ===
        previousPreheatRect = .zero
        isLoadingInitial = false
        isLoadingRemaining = false
        thumbnailSize = .zero
        hasReturnedImages = false
        isDoneButtonAnimating = false
        isShowingOnlySelected = false
        debugPrint("   ✓ 내부 상태 리셋")
        
        // === 12단계: Closure 참조 해제 ===
        onImagesSelected = nil
        onSelectionChanged = nil
        debugPrint("   ✓ Closure 참조 해제")
        
        debugPrint("✅ [CleanupMemory] 완료 - 모든 메모리 해제됨")
    }
    
    private func forceMemoryCleanup() {
        debugPrint("🧹🧹 [ForceCleanup] 추가 메모리 정리 시작")
        
        // 1. CollectionView 완전 정리
        collectionView.visibleCells.forEach { cell in
            if let galleryCell = cell as? GalleryCell {
                galleryCell.prepareForReuse()
            }
        }
        debugPrint("   ✓ CollectionView 셀 최종 정리")
        
        // 2. PHImageManager 캐시 완전 정리
        photoManager.stopCachingAllImages()
        debugPrint("   ✓ PHImageManager 캐시 최종 정리")
        
        // 3. TurboImageCache 재확인
        imageCache.clearCache()
        debugPrint("   ✓ TurboImageCache 최종 정리")
        
        debugPrint("✅ [ForceCleanup] 추가 메모리 정리 완료")
    }
    
    public override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        
        print(" [MemoryWarning] 메모리 경고 발생!")
        
        // 1. 이미지 캐시 완전 비우기
        imageCache.clearCache()
        photoManager.stopCachingAllImages()
        debugPrint("   ✓ 캐시 비움")
        
        // 2. 화면에 보이지 않는 셀들의 이미지 해제
        let visibleIndexPaths = Set(collectionView.indexPathsForVisibleItems)
        collectionView.visibleCells.forEach { cell in
            if let galleryCell = cell as? GalleryCell,
               let indexPath = collectionView.indexPath(for: galleryCell),
               !visibleIndexPaths.contains(indexPath) {
                galleryCell.prepareForReuse()
            }
        }
        debugPrint("   ✓ 비가시 셀 이미지 해제")
        
        // 3. Preheat 범위 초기화 (다음 스크롤 시 다시 계산)
        previousPreheatRect = .zero
        
        // 🔧 수정: selectedAssets는 사용자 UX 상태이므로 메모리 경고에서 삭제하지 않음
        // (PHAsset 참조는 경량 객체)
        
        debugPrint("✅ [MemoryWarning] 긴급 메모리 정리 완료")
    }
    
    deinit {
        debugPrint("🧹 [Deinit] GalleryViewController 해제 시작")
        
        // === 최종 안전 장치: 모든 리소스 정리 ===
        
        // 1. Timer 정리 (메모리 누수 방지)
        dateHideTimer?.invalidate()
        dateHideTimer = nil
        scrollUpdateTimer?.invalidate()
        scrollUpdateTimer = nil
        debugPrint("   ✓ Timer 해제")
        
        // 2. Gesture Recognizers 정리 (메모리 누수 방지)
        scrollBarThumb.gestureRecognizers?.forEach { scrollBarThumb.removeGestureRecognizer($0) }
        scrollBarTrack.gestureRecognizers?.forEach { scrollBarTrack.removeGestureRecognizer($0) }
        dateScrollIndicator.gestureRecognizers?.forEach { dateScrollIndicator.removeGestureRecognizer($0) }
        debugPrint("   ✓ Gesture Recognizers 해제")
        
        // 3. 최종 정리 - 혹시라도 남은 참조들 해제
        photoManager.stopCachingAllImages()
        imageCache.clearCache()
        assets.removeAll()
        selectedAssets.removeAll()
        selectedAssetsSet.removeAll()
        albums.removeAll()
        debugPrint("   ✓ 이미지 및 앨범 데이터 해제")
        
        // 4. Delegates 해제 (순환 참조 방지)
        collectionView.delegate = nil
        collectionView.dataSource = nil
        collectionView.prefetchDataSource = nil
        navigationController?.presentationController?.delegate = nil
        debugPrint("   ✓ Delegates 해제")
        
        // 5. Closure 참조 해제 (순환 참조 방지)
        onImagesSelected = nil
        onSelectionChanged = nil
        debugPrint("   ✓ Closure 참조 해제")
        
        debugPrint("✅ [Deinit] GalleryViewController 해제 완료 - 모든 리소스 반납됨")
    }
}

// MARK: - Extension files
// 📁 CollectionView DataSource/Delegate → GalleryViewController+CollectionView.swift
// 📁 AlbumPicker, Camera, Presentation Delegates → GalleryViewController+Delegates.swift

// MARK: - Merged from NewGalleryViewController.swift
//
//  GalleryViewController.swift
//  RNTurboImagePicker
//
//  [Collapsed 60%]  Y = containerH * 0.40
//  [Expanded  90%]  Y = safeAreaInsets.top
//
//  90% 상태에서 최상단 + 아래 스크롤 → 손가락 따라 실시간 frame 이동 → 60% snap
//


// MARK: - Presentation Controller

final class GalleryPresentationController: UIPresentationController {

    enum SheetState { case collapsed, expanded }
    private(set) var state: SheetState = .collapsed
    
    private lazy var dimmingView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        view.alpha = 0.0
        return view
    }()

    // 상단 여백 보장 (노치가 없는 기기에서도 최소 50pt 유지)
    private func getSafeTop(in c: UIView) -> CGFloat {
        let safeTop = c.window?.safeAreaInsets.top ?? 0
        return max(safeTop, 50)
    }

    // height는 항상 동일 (최소 여백 제외 전체) → 내부 레이아웃 변화 없음 → 잘림 없음
    private func sheetHeight(in c: UIView) -> CGFloat {
        c.bounds.height - getSafeTop(in: c)
    }

    // 60%: Y만 아래로, height 고정
    func collapsedFrame(in c: UIView) -> CGRect {
        CGRect(x: 0, y: c.bounds.height * 0.40,
               width: c.bounds.width, height: sheetHeight(in: c))
    }
    // 90%: Y = safeTop, height 동일
    func expandedFrame(in c: UIView) -> CGRect {
        return CGRect(x: 0, y: getSafeTop(in: c), width: c.bounds.width, height: sheetHeight(in: c))
    }

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let c = containerView else { return .zero }
        return collapsedFrame(in: c)
    }

    override func presentationTransitionWillBegin() {
        super.presentationTransitionWillBegin()
        presentedView?.layer.cornerRadius = 40
        presentedView?.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        presentedView?.clipsToBounds = true
        containerView?.backgroundColor = .clear
        
        if let container = containerView {
            dimmingView.frame = container.bounds
            dimmingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.insertSubview(dimmingView, at: 0)
            
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleDimmingTap))
            dimmingView.addGestureRecognizer(tap)
            
            if let coordinator = presentingViewController.transitionCoordinator {
                coordinator.animate(alongsideTransition: { _ in
                    self.dimmingView.alpha = 1.0
                }, completion: nil)
            } else {
                dimmingView.alpha = 1.0
            }
        }
    }
    
    @objc private func handleDimmingTap() {
        presentingViewController.dismiss(animated: true)
    }
    
    override func dismissalTransitionWillBegin() {
        super.dismissalTransitionWillBegin()
        if let coordinator = presentingViewController.transitionCoordinator {
            coordinator.animate(alongsideTransition: { _ in
                self.dimmingView.alpha = 0.0
            }, completion: nil)
        } else {
            dimmingView.alpha = 0.0
        }
    }

    func expand(velocity: CGFloat = 0, completion: (() -> Void)? = nil) {
        guard state == .collapsed, let pv = presentedView, let c = containerView else { return }
        state = .expanded
        UIView.animate(withDuration: 0.36, delay: 0,
                       usingSpringWithDamping: 0.82,
                       initialSpringVelocity: min(velocity / max(c.bounds.height, 1), 3),
                       options: .allowUserInteraction) {
            pv.frame = self.expandedFrame(in: c); pv.layer.cornerRadius = 40
            self.dimmingView.alpha = 1.0
        } completion: { _ in completion?() }
    }

    func collapse(velocity: CGFloat = 0, completion: (() -> Void)? = nil) {
        guard state == .expanded, let pv = presentedView, let c = containerView else { return }
        state = .collapsed
        UIView.animate(withDuration: 0.34, delay: 0,
                       usingSpringWithDamping: 0.85,
                       initialSpringVelocity: min(velocity / max(c.bounds.height, 1), 3),
                       options: .allowUserInteraction) {
            pv.frame = self.collapsedFrame(in: c); pv.layer.cornerRadius = 40
            self.dimmingView.alpha = 1.0
        } completion: { _ in completion?() }
    }

    /// expanded ↔ collapsed 실시간 드래그 (Y만 변경, height 고정)
    func interactiveDrag(newY: CGFloat) {
        guard let pv = presentedView, let c = containerView else { return }
        let minY = c.window?.safeAreaInsets.top ?? 50
        let maxY = c.bounds.height * 0.40
        let y    = max(minY, min(maxY, newY))
        pv.frame = CGRect(x: 0, y: y, width: c.bounds.width, height: sheetHeight(in: c))
        pv.layer.cornerRadius = 40
        self.dimmingView.alpha = 1.0
    }

    /// 닫기 방향 드래그 (Y만 변경, height 고정)
    func closingDrag(newY: CGFloat) {
        guard let pv = presentedView, let c = containerView else { return }
        let startY = c.bounds.height * 0.40
        let y = max(startY, newY)
        pv.frame = CGRect(x: 0, y: y, width: c.bounds.width, height: sheetHeight(in: c))
        pv.layer.cornerRadius = 40
        
        let progress = (y - startY) / (c.bounds.height - startY)
        self.dimmingView.alpha = max(0.0, 1.0 - progress)
    }

    /// 애니메이션 없이 즉시 expanded 상태로 (gesture 중 top 도달 시)
    func snapToExpanded() {
        guard let pv = presentedView, let c = containerView else { return }
        state = .expanded
        pv.frame = expandedFrame(in: c)
        pv.layer.cornerRadius = 40
        self.dimmingView.alpha = 1.0
    }
}

// MARK: - Transition Delegate

final class GalleryTransitionDelegate: NSObject, UIViewControllerTransitioningDelegate {
    private var pc: GalleryPresentationController?
    func presentationController(forPresented p: UIViewController, presenting: UIViewController?,
                                 source: UIViewController) -> UIPresentationController? {
        let c = GalleryPresentationController(presentedViewController: p, presenting: presenting)
        pc = c; return c
    }
    func animationController(forPresented p: UIViewController, presenting: UIViewController,
                              source: UIViewController) -> UIViewControllerAnimatedTransitioning? { GallerySlideInAnimator(pc: pc) }
    func animationController(forDismissed d: UIViewController) -> UIViewControllerAnimatedTransitioning? { GallerySlideOutAnimator() }
}

// MARK: - Animators

final class GallerySlideInAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private weak var pc: GalleryPresentationController?
    init(pc: GalleryPresentationController?) { self.pc = pc }
    func transitionDuration(using _: UIViewControllerContextTransitioning?) -> TimeInterval { 0.42 }
    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        guard let toView = ctx.view(forKey: .to) else { return }
        let cb  = ctx.containerView.bounds
        let dst = pc?.frameOfPresentedViewInContainerView
                  ?? CGRect(x: 0, y: cb.height * 0.40, width: cb.width, height: cb.height * 0.60)
        toView.frame = CGRect(x: 0, y: cb.height, width: dst.width, height: dst.height)
        ctx.containerView.addSubview(toView)
        UIView.animate(withDuration: transitionDuration(using: ctx),
                       delay: 0, usingSpringWithDamping: 0.88, initialSpringVelocity: 0.4) {
            toView.frame = dst
        } completion: { _ in ctx.completeTransition(!ctx.transitionWasCancelled) }
    }
}
final class GallerySlideOutAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using _: UIViewControllerContextTransitioning?) -> TimeInterval { 0.18 }
    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        guard let fv = ctx.view(forKey: .from) else { return }
        UIView.animate(withDuration: transitionDuration(using: ctx), delay: 0,
                       options: [.curveEaseIn, .allowUserInteraction]) {
            fv.frame.origin.y = ctx.containerView.bounds.height
        } completion: { _ in ctx.completeTransition(!ctx.transitionWasCancelled) }
    }
}

// MARK: - GalleryViewController

public final class GalleryViewController: GalleryBaseViewController {
    
    public lazy var customTransitioningDelegate: UIViewControllerTransitioningDelegate = GalleryTransitionDelegate()


    private var sheetPresenter: GalleryPresentationController? {
        navigationController?.presentationController as? GalleryPresentationController
    }

    private weak var galleryCV: UICollectionView?
    private var expansionPan:   UIPanGestureRecognizer?  // Collapsed 전체뷰
    private var navBarPan:      UIPanGestureRecognizer?  // 항상 활성

    // 스크롤 기반 실시간 축소 상태
    private var scrollPanAdded        = false
    private var isInteractiveCollapse = false
    private var lastScrollTrans:  CGFloat = 0
    private var cumulativePull:   CGFloat = 0

    // 60%로 올릴 때 스크롤 전환
    private var isScrollingContent      = false
    private var scrollContentLastTrans: CGFloat = 0
    private var scrollContentExcessPull: CGFloat = 0  // 최상단에서 추가 아래 드래그량 → sheet 이동

    // CADisplayLink 기반 fling 관성
    private var scrollDecelerator: ScrollDecelerator?

    // 탑바 그라데이션 오버레이
    private var topGradientView:  UIView?
    private var topGradientLayer: CAGradientLayer?

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        edgesForExtendedLayout           = [.top]
        extendedLayoutIncludesOpaqueBars = true
        setupGradientNavBar()
        // collectionView top constraint를 view.topAnchor로 재설정
        // → CV가 navBar 뒤까지 확장, 스크롤 시 이미지가 navBar 뒤로 올라감
        stretchCollectionViewToTop()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 부모(GalleryViewController)에서 설정한 불투명 배경 덮어쓰기
        navigationController?.navigationBar.isTranslucent = true
        navigationController?.view.backgroundColor = .clear
        setupGradientNavBar()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // 다크모드 등 테마 변경 시에도 투명 네비게이션 바 유지
        setupGradientNavBar()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTopGradientFrame()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if galleryCV == nil { galleryCV = findCV(in: view) }
        setupNavBarPan()
        enterCollapsedMode()
        addGrabIndicatorIfNeeded()
    }

    /// collectionView top constraint를 safeArea → view.topAnchor로 교체 및 inset 자동 조절 활성화
    private func stretchCollectionViewToTop() {
        let cv = findCV(in: view)
        guard let cv = cv else { return }
        // 기존 safeArea top constraint 제거
        for c in view.constraints {
            if (c.firstItem as? UIView) == cv && c.firstAttribute == .top {
                c.isActive = false
            }
            if (c.secondItem as? UIView) == cv && c.secondAttribute == .top {
                c.isActive = false
            }
        }
        // view.topAnchor에 연결 (navBar 뒤까지 확장)
        cv.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        
        // 부모에서 .never로 설정된 것을 .always로 변경하여, 
        // 네비게이션 바 높이만큼 자동으로 정확한 inset이 들어가도록 위임
        cv.contentInsetAdjustmentBehavior = .always
    }

    private var grabIndicatorAdded = false
    private func addGrabIndicatorIfNeeded() {
        guard !grabIndicatorAdded, let navBar = navigationController?.navigationBar else { return }
        grabIndicatorAdded = true

        let pill = UIView()
        pill.backgroundColor = UIColor.white.withAlphaComponent(0.20)
        pill.layer.cornerRadius = 2
        pill.isUserInteractionEnabled = false
        pill.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(pill)
        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: navBar.centerXAnchor),
            pill.topAnchor.constraint(equalTo: navBar.topAnchor, constant: 0),
            pill.widthAnchor.constraint(equalToConstant: 36),
            pill.heightAnchor.constraint(equalToConstant: 4)
        ])
    }

    private func findCV(in v: UIView) -> UICollectionView? {
        if let cv = v as? UICollectionView { return cv }
        for sub in v.subviews { if let cv = findCV(in: sub) { return cv } }
        return nil
    }

    // MARK: - NavBar (Telegram style: scroll-through gradient)

    private func setupGradientNavBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        
        navigationController?.navigationBar.standardAppearance   = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance    = appearance
        
        topGradientView?.removeFromSuperview()
        topGradientView = nil
    }

    private func updateTopGradientFrame() {
        guard let gv = topGradientView,
              let navBar  = navigationController?.navigationBar,
              let navView = navigationController?.view else { return }
        let h = navBar.frame.maxY + 16
        gv.frame             = CGRect(x: 0, y: 0, width: navView.bounds.width, height: h)
        topGradientLayer?.frame = gv.bounds
    }

    // MARK: - Nav Bar Pan (항상 활성: 양 상태 모두)

    private func setupNavBarPan() {
        guard navBarPan == nil, let nb = navigationController?.navigationBar else { return }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleNavBarPan(_:)))
        pan.cancelsTouchesInView = false
        nb.addGestureRecognizer(pan)
        navBarPan = pan
    }

    // MARK: - Mode Switch

    private func enterCollapsedMode() {
        galleryCV?.isScrollEnabled = false

        // 스크롤 pan target 제거
        if scrollPanAdded, let cv = galleryCV {
            cv.panGestureRecognizer.removeTarget(self, action: #selector(handleScrollPan(_:)))
            scrollPanAdded = false
        }
        resetScrollCollapse()

        // 전체뷰 expansion pan 추가
        if expansionPan == nil {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleExpansionPan(_:)))
            view.addGestureRecognizer(pan)
            expansionPan = pan
        }
    }

    private func enterExpandedMode() {
        galleryCV?.isScrollEnabled = true

        // 전체뷰 expansion pan 제거
        if let p = expansionPan { view.removeGestureRecognizer(p); expansionPan = nil }

        // ✅ 스크롤 pan target 추가 → 최상단 아래 드래그 감지
        if !scrollPanAdded, let cv = galleryCV {
            cv.panGestureRecognizer.addTarget(self, action: #selector(handleScrollPan(_:)))
            scrollPanAdded = true
        }
    }

    // MARK: - ① Collapsed: 전체뷰 Pan (위→확장/스크롤, 아래→닫기)

    @objc private func handleExpansionPan(_ gesture: UIPanGestureRecognizer) {
        guard let presenter = sheetPresenter,
              let pv = presenter.presentedView,
              let c  = presenter.containerView else { return }

        let trans      = gesture.translation(in: c).y
        let vel        = gesture.velocity(in: c).y
        let safeTop    = c.window?.safeAreaInsets.top ?? 50
        let collapsedY = c.bounds.height * 0.40
        let range      = collapsedY - safeTop

        switch gesture.state {
        case .began:
            isScrollingContent      = false
            scrollContentLastTrans  = trans

        case .changed:
            if isScrollingContent {
                guard let cv = galleryCV else { return }
                let delta    = trans - scrollContentLastTrans
                scrollContentLastTrans = trans
                let topInset = cv.adjustedContentInset.top
                let maxY     = max(0, cv.contentSize.height - cv.bounds.height + cv.contentInset.bottom)

                if scrollContentExcessPull > 0 {
                    // 이미 sheet를 아래로 끌고 있는 중 → 계속 sheet 이동
                    scrollContentExcessPull = max(0, scrollContentExcessPull + delta)
                    let newY = safeTop + scrollContentExcessPull
                    if newY <= collapsedY { presenter.interactiveDrag(newY: newY) }
                    else { presenter.closingDrag(newY: newY) }
                    if scrollContentExcessPull == 0 {
                        // sheet가 90%로 돌아왔으면 다시 content scroll 재개
                        presenter.interactiveDrag(newY: safeTop)
                    }
                } else if delta > 0 && cv.contentOffset.y <= -topInset + 3 {
                    // 최상단 + 아래로 → sheet를 아래로 드래그
                    scrollContentExcessPull += delta
                    cv.contentOffset = CGPoint(x: 0, y: -topInset)
                    presenter.interactiveDrag(newY: safeTop + scrollContentExcessPull)
                } else {
                    // 정상 콘텐츠 스크롤
                    let newY = max(-topInset, min(maxY, cv.contentOffset.y - delta))
                    cv.contentOffset = CGPoint(x: 0, y: newY)
                }
            } else {
                if trans < 0 {
                    let newY = collapsedY + trans
                    if newY <= safeTop {
                        presenter.snapToExpanded()
                        galleryCV?.isScrollEnabled = true
                        isScrollingContent     = true
                        scrollContentLastTrans = trans
                        scrollContentExcessPull = 0
                    } else {
                        presenter.interactiveDrag(newY: newY)
                    }
                } else {
                    presenter.closingDrag(newY: collapsedY + trans)
                }
            }

        case .ended, .cancelled:
            let currentY = pv.frame.minY
            let excess   = scrollContentExcessPull
            scrollContentExcessPull = 0

            if isScrollingContent {
                isScrollingContent = false
                if excess > 0 {
                    // Sheet을 아래로 끌다가 손 뗌 → collapse/dismiss 판단
                    if currentY < collapsedY {
                        let moved = currentY - safeTop
                        if moved > range * 0.25 || vel > 400 {
                            presenter.collapse(velocity: abs(vel)) { [weak self] in self?.enterCollapsedMode() }
                        } else {
                            snap(pv: pv, to: presenter.expandedFrame(in: c))
                            enterExpandedMode()
                        }
                    } else {
                        if vel > 500 { navigationController?.dismiss(animated: true) }
                        else { presenter.collapse(velocity: abs(vel)) { [weak self] in self?.enterCollapsedMode() } }
                    }
                } else {
                    applyScrollMomentum(velocity: vel)
                    enterExpandedMode()
                }
            } else if currentY < collapsedY {
                let moved = collapsedY - currentY
                if moved > range * 0.25 || vel < -400 {
                    enterExpandedMode()
                    applyScrollMomentum(velocity: vel)
                    presenter.expand(velocity: abs(vel))
                } else { snap(pv: pv, to: presenter.collapsedFrame(in: c)) }
            } else {
                let moved = currentY - collapsedY
                if moved > 80 || vel > 500 { navigationController?.dismiss(animated: true) }
                else { snap(pv: pv, to: presenter.collapsedFrame(in: c)) }
            }
            isScrollingContent = false

        default:
            isScrollingContent = false
            scrollContentExcessPull = 0
        }
    }

    /// CADisplayLink 기반 물리 감속 — 최상단에서도 적용
    private func applyScrollMomentum(velocity vel: CGFloat) {
        guard vel < -100, let cv = galleryCV else { return }
        scrollDecelerator?.stop()
        scrollDecelerator = ScrollDecelerator(scrollView: cv, velocityPerSec: vel)
        scrollDecelerator?.start()
    }

    // MARK: - ② Nav Bar Pan: 양 상태 자유 이동

    @objc private func handleNavBarPan(_ gesture: UIPanGestureRecognizer) {
        guard let presenter = sheetPresenter,
              let pv = presenter.presentedView,
              let c  = presenter.containerView else { return }

        let trans      = gesture.translation(in: c).y
        let vel        = gesture.velocity(in: c).y
        let safeTop    = c.window?.safeAreaInsets.top ?? 50
        let collapsedY = c.bounds.height * 0.40
        let range      = collapsedY - safeTop

        switch gesture.state {
        case .changed:
            if presenter.state == .collapsed {
                // Collapsed: 위→확장, 아래→자유 닫기
                if trans < 0 { presenter.interactiveDrag(newY: collapsedY + trans) }
                else          { presenter.closingDrag(newY: collapsedY + trans) }
            } else {
                // Expanded: 아래→자유 이동 (60% 이하로도 계속)
                if trans > 0 {
                    let newY = safeTop + trans
                    if newY <= collapsedY {
                        presenter.interactiveDrag(newY: newY)   // 90%→60% 구간
                    } else {
                        presenter.closingDrag(newY: newY)       // 60% 아래 (닫기 방향)
                    }
                }
                // 위로는 이미 최대(safe area) — 무시
            }

        case .ended, .cancelled:
            let currentY = pv.frame.minY
            if presenter.state == .collapsed {
                if currentY < collapsedY {
                    let moved = collapsedY - currentY
                    if moved > range * 0.25 || vel < -400 {
                        presenter.expand(velocity: abs(vel)) { [weak self] in self?.enterExpandedMode() }
                    } else { snap(pv: pv, to: presenter.collapsedFrame(in: c)) }
                } else {
                    let moved = currentY - collapsedY
                    if moved > 80 || vel > 500 { navigationController?.dismiss(animated: true) }
                    else { snap(pv: pv, to: presenter.collapsedFrame(in: c)) }
                }
            } else {
                // Expanded 상태에서 release
                if currentY < collapsedY {
                    // 60%보다 위 → snap back or collapse
                    let moved = currentY - safeTop
                    if vel < -300 {
                        // ✅ 위로 던지기 → 90%로 스냅 백 (위치 무관)
                        snap(pv: pv, to: presenter.expandedFrame(in: c))
                    } else if moved > range * 0.25 || vel > 400 {
                        presenter.collapse(velocity: abs(vel)) { [weak self] in self?.enterCollapsedMode() }
                    } else { snap(pv: pv, to: presenter.expandedFrame(in: c)) }
                } else {
                    // 60%보다 아래 → 닫기 또는 60%로 축소
                    let moved = currentY - collapsedY
                    if moved > 80 || vel > 500 { navigationController?.dismiss(animated: true) }
                    else { presenter.collapse(velocity: abs(vel)) { [weak self] in self?.enterCollapsedMode() } }
                }
            }
        default: break
        }
    }

    // MARK: - ③ Expanded: 스크롤 Pan (최상단 아래 드래그 → 실시간 축소)

    @objc private func handleScrollPan(_ gesture: UIPanGestureRecognizer) {
        guard let presenter = sheetPresenter, presenter.state == .expanded else { return }
        guard let cv = galleryCV,
              let pv = presenter.presentedView,
              let c  = presenter.containerView else { return }

        let topInset   = cv.adjustedContentInset.top
        let trans      = gesture.translation(in: c).y
        let vel        = gesture.velocity(in: c).y
        let safeTop    = c.window?.safeAreaInsets.top ?? 50
        let collapsedY = c.bounds.height * 0.40
        let range      = collapsedY - safeTop

        switch gesture.state {
        case .began:
            lastScrollTrans = trans
            cumulativePull  = 0
            isInteractiveCollapse = false

        case .changed:
            let atTop  = cv.contentOffset.y <= -topInset + 5
            let delta  = trans - lastScrollTrans
            lastScrollTrans = trans

            if isInteractiveCollapse {
                cumulativePull = max(0, cumulativePull + delta)
                if cumulativePull <= 0 {
                    // ✅ 실트 다시 최상단으로 복귀 → interactive collapse 종료, 스크롤 재개
                    isInteractiveCollapse = false
                    cumulativePull = 0
                    presenter.interactiveDrag(newY: safeTop)  // 시트 원위 snap
                    // contentOffset 잠금 해제 → 자연스럽게 스크롤 재개
                } else {
                    cv.contentOffset = CGPoint(x: 0, y: -topInset)  // 스크롤 고정
                    let newY = safeTop + cumulativePull
                    if newY <= collapsedY {
                        presenter.interactiveDrag(newY: newY)
                    } else {
                        presenter.closingDrag(newY: newY)
                    }
                }
            } else if atTop && delta > 0 {
                // 최상단 + 아래로 드래그 → interactive collapse 시작
                isInteractiveCollapse = true
                cumulativePull = delta
                cv.contentOffset = CGPoint(x: 0, y: -topInset)
                presenter.interactiveDrag(newY: safeTop + cumulativePull)
            }

        case .ended, .cancelled:
            defer { resetScrollCollapse() }
            guard isInteractiveCollapse else { return }

            let currentY = pv.frame.minY
            if currentY < collapsedY {
                // 60%보다 위 → collapse 또는 snap back
                let moved = currentY - safeTop
                if moved > range * 0.25 || vel > 400 {
                    presenter.collapse(velocity: abs(vel)) { [weak self] in self?.enterCollapsedMode() }
                } else {
                    snap(pv: pv, to: presenter.expandedFrame(in: c))
                }
            } else {
                // ✅ 60%보다 아래 → 닫기 또는 60%로 축소
                let movedPast = currentY - collapsedY
                if movedPast > 80 || vel > 500 {
                    navigationController?.dismiss(animated: true)
                } else {
                    presenter.collapse(velocity: abs(vel)) { [weak self] in self?.enterCollapsedMode() }
                }
            }

        default:
            if isInteractiveCollapse {
                if let pv = presenter.presentedView, let c = presenter.containerView {
                    snap(pv: pv, to: presenter.expandedFrame(in: c))
                }
            }
            resetScrollCollapse()
        }
    }

    private func resetScrollCollapse() {
        isInteractiveCollapse = false
        lastScrollTrans       = 0
        cumulativePull        = 0
    }

    // MARK: - 스크롤 고정 (실시간 축소 중)

    public override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        super.scrollViewDidScroll(scrollView)
        guard isInteractiveCollapse, let cv = galleryCV else { return }
        scrollView.contentOffset = CGPoint(x: 0, y: -cv.adjustedContentInset.top)
    }

    // MARK: - Helper

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // 새 드래그 시작 → 관성 애니메이션 중단
        scrollDecelerator?.stop()
        scrollDecelerator = nil
        if galleryCV == nil { galleryCV = scrollView as? UICollectionView }
        if !scrollPanAdded,
           let presenter = sheetPresenter, presenter.state == .expanded {
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(handleScrollPan(_:)))
            scrollPanAdded = true
        }
    }

    private func snap(pv: UIView, to frame: CGRect) {
        UIView.animate(withDuration: 0.3, delay: 0,
                       usingSpringWithDamping: 0.85, initialSpringVelocity: 0.3,
                       options: .allowUserInteraction) {
            pv.frame = frame; pv.layer.cornerRadius = 40
        }
    }
}

// MARK: - ScrollDecelerator (UIScrollView 물리 감속 모방)

/// CADisplayLink 기반 감속 — UIScrollView normal deceleration (0.998/ms ≈ 0.967/frame @ 60fps)
private final class ScrollDecelerator {
    private weak var scrollView: UIScrollView?
    private var velPerFrame: CGFloat          // pts/frame, 음수=위로 스크롤
    private var displayLink: CADisplayLink?
    private let factor: CGFloat = 0.967       // UIScrollView normal 감속 계수/frame

    init(scrollView: UIScrollView, velocityPerSec: CGFloat) {
        self.scrollView = scrollView
        // velocityPerSec < 0 (위 방향) → contentOffset 증가 → -velPerSec/60
        self.velPerFrame = -velocityPerSec / 60.0
    }

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        guard let sv = scrollView else { stop(); return }
        velPerFrame *= factor
        guard abs(velPerFrame) > 0.3 else { stop(); return }

        let topInset = sv.adjustedContentInset.top
        let maxY     = max(0, sv.contentSize.height - sv.bounds.height + sv.contentInset.bottom)
        let newY     = sv.contentOffset.y + velPerFrame
        sv.contentOffset = CGPoint(x: 0, y: max(-topInset, min(maxY, newY)))

        if newY <= -topInset || newY >= maxY { stop() }
    }
}
