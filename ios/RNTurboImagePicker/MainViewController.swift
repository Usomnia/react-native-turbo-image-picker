//
//  MainViewController.swift
//  RNTurboImagePicker — Test Harness
//
//  4가지 케이스 테스트용 버튼 구성
//  ┌─────────────────────────────┬────────────────────────────────┐
//  │  📷 1개 선택 (편집 OFF)      │  ✏️ 1개 선택 (편집 ON)          │
//  │  📸 멀티 선택 (편집 OFF)     │  🎨 멀티 선택 (편집 ON)          │
//  └─────────────────────────────┴────────────────────────────────┘

import UIKit
import Photos
#if canImport(SDWebImageWebPCoder)
@_implementationOnly import SDWebImageWebPCoder
#endif

class MainViewController: UIViewController {

    // MARK: - UI

    private lazy var titleLabel: UILabel = {
        let l = UILabel()
        l.text = "이미지 피커 테스트"
        l.font = .systemFont(ofSize: 26, weight: .bold)
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var subtitleLabel: UILabel = {
        let l = UILabel()
        l.text = "4가지 케이스를 각각 테스트하세요"
        l.font = .systemFont(ofSize: 14, weight: .regular)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // 섹션 라벨
    private func makeSectionLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.textColor = .tertiaryLabel
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    // 버튼 팩토리
    private func makeButton(title: String, color: UIColor, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        btn.titleLabel?.numberOfLines = 2
        btn.titleLabel?.textAlignment = .center
        btn.backgroundColor = color
        btn.setTitleColor(.white, for: .normal)
        btn.layer.cornerRadius = 14
        if #available(iOS 13.0, *) {
            btn.layer.cornerCurve = .continuous
        }
        // 그림자
        btn.layer.shadowColor = color.cgColor
        btn.layer.shadowOffset = CGSize(width: 0, height: 3)
        btn.layer.shadowRadius = 6
        btn.layer.shadowOpacity = 0.25
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: action, for: .touchUpInside)
        // 터치 피드백
        btn.addTarget(self, action: #selector(btnTouchDown(_:)), for: .touchDown)
        btn.addTarget(self, action: #selector(btnTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        return btn
    }

    // 4개 버튼 (lazy)
    private lazy var singleOffBtn = makeButton(
        title: "📷  1개 선택\n편집 OFF",
        color: UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1),
        action: #selector(singleOffTapped)
    )
    private lazy var singleOnBtn = makeButton(
        title: "✏️  1개 선택\n편집 ON",
        color: UIColor(red: 0.1, green: 0.75, blue: 0.55, alpha: 1),
        action: #selector(singleOnTapped)
    )
    private lazy var multiOffBtn = makeButton(
        title: "📸  멀티 선택 (최대 10)\n편집 OFF",
        color: UIColor(red: 0.6, green: 0.4, blue: 1.0, alpha: 1),
        action: #selector(multiOffTapped)
    )
    private lazy var multiOnBtn = makeButton(
        title: "🎨  멀티 선택 (최대 10)\n편집 ON",
        color: UIColor(red: 0.95, green: 0.45, blue: 0.15, alpha: 1),
        action: #selector(multiOnTapped)
    )
    private lazy var profileOffBtn = makeButton(
        title: "👤  프로필 사진\n1:1 크롭",
        color: UIColor(red: 0.47, green: 0.27, blue: 0.96, alpha: 1),
        action: #selector(profileOffTapped)
    )
    private lazy var profileOnBtn = makeButton(
        title: "👤  프로필 사진\n크롭 + 편집",
        color: UIColor(red: 0.35, green: 0.15, blue: 0.85, alpha: 1),
        action: #selector(profileOnTapped)
    )
    // 결과 표시 라벨
    private lazy var resultLabel: UILabel = {
        let l = UILabel()
        l.text = "결과가 여기 표시됩니다"
        l.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.numberOfLines = 4
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var imageScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = true
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var imageStackView: UIStackView = {
        let s = UIStackView()
        s.axis = .horizontal
        s.spacing = 8
        s.alignment = .fill
        s.distribution = .fill
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
    }

    // MARK: - Layout

    private func setupUI() {
        // 2×2 그리드: 각 행에 StackView 사용
        let topRow = makeHStack([singleOffBtn, singleOnBtn])
        let bottomRow = makeHStack([multiOffBtn, multiOnBtn])

        let singleLabel  = makeSectionLabel("── 단일 선택 ──")
        let multiLabel   = makeSectionLabel("── 멀티 선택 ──")
        let profileLabel = makeSectionLabel("── 프로필 모드 ──")
        let profileRow   = makeHStack([profileOffBtn, profileOnBtn])

        let vStack = UIStackView(arrangedSubviews: [
            singleLabel, topRow,
            multiLabel,  bottomRow,
            profileLabel, profileRow
        ])
        vStack.axis = .vertical
        vStack.spacing = 10
        vStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(vStack)
        view.addSubview(resultLabel)
        view.addSubview(imageScrollView)
        imageScrollView.addSubview(imageStackView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 36),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            vStack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -60),
            vStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            vStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            singleOffBtn.heightAnchor.constraint(equalToConstant: 88),
            singleOnBtn.heightAnchor.constraint(equalToConstant: 88),
            multiOffBtn.heightAnchor.constraint(equalToConstant: 88),
            multiOnBtn.heightAnchor.constraint(equalToConstant: 88),
            profileOffBtn.heightAnchor.constraint(equalToConstant: 88),
            profileOnBtn.heightAnchor.constraint(equalToConstant: 88),

            resultLabel.topAnchor.constraint(equalTo: vStack.bottomAnchor, constant: 20),
            resultLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            resultLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            
            imageScrollView.topAnchor.constraint(equalTo: resultLabel.bottomAnchor, constant: 16),
            imageScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            imageScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            imageScrollView.heightAnchor.constraint(equalToConstant: 120),
            
            imageStackView.topAnchor.constraint(equalTo: imageScrollView.contentLayoutGuide.topAnchor),
            imageStackView.leadingAnchor.constraint(equalTo: imageScrollView.contentLayoutGuide.leadingAnchor),
            imageStackView.trailingAnchor.constraint(equalTo: imageScrollView.contentLayoutGuide.trailingAnchor),
            imageStackView.bottomAnchor.constraint(equalTo: imageScrollView.contentLayoutGuide.bottomAnchor),
            imageStackView.heightAnchor.constraint(equalTo: imageScrollView.frameLayoutGuide.heightAnchor)
        ])
    }

    private func makeHStack(_ views: [UIView]) -> UIStackView {
        let s = UIStackView(arrangedSubviews: views)
        s.axis = .horizontal
        s.spacing = 12
        s.distribution = .fillEqually
        return s
    }

    // MARK: - Touch Feedback

    @objc private func btnTouchDown(_ sender: UIButton) {
        UIView.animate(withDuration: 0.1) {
            sender.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            sender.alpha = 0.85
        }
    }
    @objc private func btnTouchUp(_ sender: UIButton) {
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8, options: .allowUserInteraction) {
            sender.transform = .identity
            sender.alpha = 1
        }
    }

    // MARK: - Actions

    /// 1개 선택 / 편집 OFF
    @objc private func singleOffTapped() {
        openPicker(maxSelection: 1, enableEditor: false)
    }

    /// 1개 선택 / 편집 ON → 탭 즉시 편집 화면
    @objc private func singleOnTapped() {
        openPicker(maxSelection: 1, enableEditor: true)
    }

    /// 멀티 선택 / 편집 OFF → 선택 후 완료
    @objc private func multiOffTapped() {
        openPicker(maxSelection: 10, enableEditor: false)
    }

    /// 멀티 선택 / 편집 ON → 선택 아이콘 탭으로 선택, 선택된 사진 탭으로 편집
    @objc private func multiOnTapped() {
        openPicker(maxSelection: 10, enableEditor: true)
    }

    /// 프로필 모드: 1:1 크롭만
    @objc private func profileOffTapped() {
        openProfilePicker(enableEditor: false)
    }

    /// 프로필 모드: 1:1 크롭 후 편집
    @objc private func profileOnTapped() {
        openProfilePicker(enableEditor: true)
    }

    // MARK: - Core Picker

    // transitioningDelegate는 weak 참조이므로 프로퍼티로 유지
    private let galleryTransitionDelegate = GalleryTransitionDelegate()

    private func openPicker(maxSelection: Int, enableEditor: Bool) {
        let galleryVC = GalleryViewController()
        galleryVC.maxSelection = maxSelection
        galleryVC.languageCode = "ko"

        // ── 출력 옵션 ────────────────────────────────────────────────
        // maxWidth/maxHeight: 0이면 원본 크기 유지, 양수면 해당 크기로 리사이즈
        galleryVC.maxWidth    = 1024
        galleryVC.maxHeight   = 1024
        galleryVC.outputFormat = "webp"  // "webp" | "jpg" | "png"

        // ── 편집 ON ────────────────────────────────────────────────
        if enableEditor {
            galleryVC.allowsEditing = true
            let isMultiSelect = maxSelection > 1

            galleryVC.onSingleImageTappedForEdit = { [weak self, weak galleryVC] (asset, sourceFrame, sourceImage) in
                guard let self = self, let galleryVC = galleryVC else { return }
                self.presentEditor(asset: asset, galleryVC: galleryVC, isMultiSelect: isMultiSelect, sourceFrame: sourceFrame, sourceImage: sourceImage)
            }

            // 다중+편집: 완료 버튼이 눌리면 선택된 사진들 목록만 출력 (편집은 개별 탭으로)
            if isMultiSelect {
                galleryVC.onImagesSelected = { [weak self] images in
                    let t0 = CFAbsoluteTimeGetCurrent()
                    self?.showResult(images: images, label: "멀티+편집 완료", startTime: t0)
                }
            }
            // 단일+편집: onConfirm에서 처리하므로 onImagesSelected는 취소 시만 호출
        }

        // ── 편집 OFF ───────────────────────────────────────────────
        galleryVC.onImagesSelected = { [weak self] images in
            let t0 = CFAbsoluteTimeGetCurrent()  // Done 탭 → 콜백 진입 시각
            guard !images.isEmpty else {
                self?.resultLabel.text = "❌ 취소됨"
                return
            }
            self?.showResult(images: images, label: enableEditor ? "편집 완료" : "선택 완료", startTime: t0)
        }

        // ── Sheet 표시 ─────────────────────────────────────────────
        let nav = UINavigationController(rootViewController: galleryVC)
        nav.modalPresentationStyle = .custom
        nav.transitioningDelegate = galleryTransitionDelegate
        present(nav, animated: true)
    }

    // MARK: - Profile Picker

    private func openProfilePicker(enableEditor: Bool) {
        let galleryVC = GalleryViewController()
        galleryVC.maxSelection = 1
        galleryVC.languageCode = "ko"
        galleryVC.maxWidth     = 1024
        galleryVC.maxHeight    = 1024
        galleryVC.outputFormat = "webp"
        galleryVC.profileMode  = true
        // allowsEditing should be passed if we want GalleryViewController to be aware, 
        // but since we handle it here on crop finish, it might not be strictly needed. 
        // We set it anyway to be consistent.
        galleryVC.allowsEditing = enableEditor

        // When crop finishes → open editor with cropped image or just finish
        galleryVC.onProfileCropComplete = { [weak self, weak galleryVC] asset, croppedImage in
            guard let self = self, let galleryVC = galleryVC else { return }
            
            if enableEditor {
                self.presentEditorForProfile(asset: asset,
                                             croppedImage: croppedImage,
                                             galleryVC: galleryVC)
            } else {
                galleryVC.dismiss(animated: true) {
                    self.showResult(images: [(asset, croppedImage)], label: "프로필 크롭 완료")
                }
            }
        }

        // Cancelled (empty array)
        galleryVC.onImagesSelected = { [weak self] images in
            guard !images.isEmpty else {
                self?.resultLabel.text = "❌ 취소됨"
                return
            }
            // in case the crop wasn't used but somehow it fell through
            self?.showResult(images: images, label: "프로필 선택 완료")
        }

        // ── Sheet 표시 ─────────────────────────────────────────────
        let nav = UINavigationController(rootViewController: galleryVC)
        nav.modalPresentationStyle = .custom
        nav.transitioningDelegate = galleryTransitionDelegate
        present(nav, animated: true)
    }

    private func presentEditorForProfile(asset: PHAsset,
                                          croppedImage: UIImage,
                                          galleryVC: GalleryViewController) {
        // maxWidth/maxHeight 적용 (갤러리와 동일하게 1024 제한)
        let maxSide: CGFloat = 1024
        let resized = resizeIfNeeded(croppedImage, maxWidth: maxSide, maxHeight: maxSide)

        let editorVC = ImageEditorViewController()
        editorVC.languageCode = galleryVC.languageCode
        editorVC.allAssets       = [asset]
        editorVC.currentIndex    = 0
        editorVC.singlePhotoMode = true
        editorVC.disableCrop     = true   // 이미 프로필 크롭 완료 → 크롭 버튼 비활성화
        editorVC.modalPresentationStyle = .overFullScreen

        // 리사이즈된 크롭 이미지 주입
        editorVC.croppedImages = [0: resized]

        if let cellFrame = galleryVC.frameForAsset(asset) {
            let delegate = ImageEditorTransitionDelegate()
            delegate.sourceFrame = cellFrame
            delegate.sourceImage = resized
            delegate.uncroppedImage = resized
            let ratio = CGFloat(asset.pixelWidth) / CGFloat(max(1, asset.pixelHeight))
            delegate.assetAspectRatio = ratio
            delegate.asset = asset
            delegate.disablePresentationAnimation = true
            delegate.frameProvider = { [weak galleryVC] currentAsset in
                return galleryVC?.frameForAsset(currentAsset)
            }
            self.editorTransitionDelegate = delegate
            editorVC.transitioningDelegate = self.editorTransitionDelegate
        }


        editorVC.onCancel = { [weak galleryVC] in
            galleryVC?.selectedAssets.removeAll()
            galleryVC?.refreshSelectionAfterEdit()
            
            // editorVC가 닫혔을 때 (취소 등), 숨겨져 있던 cropVC도 같이 닫아주어야 갤러리를 정상적으로 터치할 수 있습니다.
            if let presented = galleryVC?.presentedViewController {
                presented.dismiss(animated: false)
            }
        }

        editorVC.onConfirm = { [weak self, weak galleryVC, weak editorVC] (editedAsset, editedImage, filterState, caption) in
            editorVC?.dismiss(animated: true) {
                let navToDismiss = galleryVC?.navigationController ?? galleryVC
                let presenter = navToDismiss?.presentingViewController ?? navToDismiss
                presenter?.dismiss(animated: true) {
                    self?.resultLabel.text = "✅ 프로필 편집 완료"
                    var processImage = editedImage ?? resized
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        guard let self = self else { return }
                        var ext = "WEBP"; var sizeStr = ""
                        if let webpData = self.encodeWebP(image: processImage, quality: 0.85) {
                            let kb = Double(webpData.count) / 1024.0
                            sizeStr = kb > 1024 ? String(format: "%.1fMB", kb/1024) : String(format: "%.1fKB", kb)
                            processImage = UIImage(data: webpData) ?? processImage
                        }
                        let w = Int(processImage.size.width); let h = Int(processImage.size.height)
                        DispatchQueue.main.async {
                            self.resultLabel.text = "✅ 프로필 편집 완료\n\(w)×\(h) • \(ext) • \(sizeStr)"
                            self.updateImageViews(with: [processImage])
                        }
                    }
                }
            }
        }

        var topController: UIViewController = galleryVC.navigationController ?? galleryVC
        while let presented = topController.presentedViewController {
            topController = presented
        }
        topController.present(editorVC, animated: true)
    }

    /// 이미지를 maxWidth×maxHeight 이내로 비율 유지하며 리사이즈
    private func resizeIfNeeded(_ image: UIImage, maxWidth: CGFloat, maxHeight: CGFloat) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        guard w > maxWidth || h > maxHeight else { return image }
        let scale = min(maxWidth / w, maxHeight / h)
        let newSize = CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }


    // MARK: - Editor

    private func presentEditor(asset: PHAsset, galleryVC: GalleryViewController, isMultiSelect: Bool, sourceFrame: CGRect = .zero, sourceImage: UIImage? = nil) {
        var assets: [PHAsset] = []
        var startIndex = 0
        
        if isMultiSelect {
            // 🚀 성능 최적화: 갤러리가 이미 로드해 둔 배열을 재사용 (DB 재검색 방지, 딜레이 제거)
            assets = galleryVC.assets
            if let idx = assets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
                startIndex = idx
            } else {
                // 새로 촬영한 사진이 배열에 없으면 임시로 앞에 추가
                assets.insert(asset, at: 0)
                startIndex = 0
            }
        } else {
            assets = [asset]
            startIndex = 0
        }

        let editorVC = ImageEditorViewController()
        editorVC.languageCode = galleryVC.languageCode
        editorVC.allAssets = assets
        editorVC.currentIndex = startIndex
        editorVC.modalPresentationStyle = .overFullScreen
        editorVC.singlePhotoMode = !isMultiSelect  // 1장 모드: 스와이프 비활성화
        
        var initialCroppedImages: [Int: UIImage] = [:]
        for (i, a) in assets.enumerated() {
            if let editedImg = galleryVC.editedImages[a.localIdentifier] {
                initialCroppedImages[i] = editedImg
            }
        }
        editorVC.croppedImages = initialCroppedImages

        if sourceFrame != .zero {
            self.editorTransitionDelegate = ImageEditorTransitionDelegate()
            self.editorTransitionDelegate?.sourceFrame = sourceFrame
            self.editorTransitionDelegate?.sourceImage = sourceImage
            
            if let editedImg = galleryVC.editedImages[asset.localIdentifier] {
                self.editorTransitionDelegate?.uncroppedImage = editedImg
                self.editorTransitionDelegate?.asset = nil // 편집된 경우 원본 고해상도 패치 방지
            } else {
                let options = PHImageRequestOptions()
                options.deliveryMode = .fastFormat
                options.isSynchronous = true
                options.resizeMode = .fast
                var fastUncropped: UIImage? = nil
                PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 400, height: 400), contentMode: .aspectFit, options: options) { img, _ in
                    fastUncropped = img
                }
                self.editorTransitionDelegate?.uncroppedImage = fastUncropped ?? sourceImage
                self.editorTransitionDelegate?.asset = asset
            }
            
            var ratio = CGFloat(asset.pixelWidth) / CGFloat(max(1, asset.pixelHeight))
            if let editedImg = galleryVC.editedImages[asset.localIdentifier] {
                ratio = editedImg.size.width / max(1, editedImg.size.height)
            }
            self.editorTransitionDelegate?.assetAspectRatio = ratio
            self.editorTransitionDelegate?.frameProvider = { [weak galleryVC] currentAsset in
                return galleryVC?.frameForAsset(currentAsset)
            }
            
            editorVC.transitioningDelegate = self.editorTransitionDelegate
        }

        // 멀티 모드: 현재 갤러리 선택 상태 주입
        if isMultiSelect {
            editorVC.selectedAssets = galleryVC.selectedAssets
            editorVC.onSelectionToggled = { [weak galleryVC] asset, select in
                galleryVC?.toggleSelectionFromEditor(asset: asset, select: select)
            }
            editorVC.onEditDeleted = { [weak galleryVC] asset in
                galleryVC?.editedImages.removeValue(forKey: asset.localIdentifier)
            }
        }

        editorVC.onConfirmMulti = { [weak galleryVC] (assets, croppedImages, filterStates) in
            guard let galleryVC = galleryVC else { return }
            
            // 🚀 에디터만 닫고 갤러리는 유지
            editorVC.dismiss(animated: true) {
                DispatchQueue.global(qos: .userInitiated).async {
                    var newlyEditedAssets: [PHAsset] = []
                    
                    for asset in assets {
                        if let baseImage = croppedImages[asset] {
                            var finalImage = baseImage
                            if let state = filterStates[asset],
                               state.filterId != "original",
                               let filter = FilterManager.shared.filters.first(where: { $0.id == state.filterId }),
                               let ciImage = CIImage(image: baseImage),
                               let out = filter.apply(ciImage, state.intensity),
                               let cgImg = FilterManager.shared.context.createCGImage(out, from: out.extent) {
                                finalImage = UIImage(cgImage: cgImg, scale: baseImage.scale, orientation: baseImage.imageOrientation)
                            }
                            
                            DispatchQueue.main.async {
                                galleryVC.editedImages[asset.localIdentifier] = finalImage
                            }
                            newlyEditedAssets.append(asset)
                        }
                    }
                    
                    DispatchQueue.main.async {
                        // 편집된 사진을 자동으로 선택 상태로 만듦
                        for asset in newlyEditedAssets {
                            if !galleryVC.selectedAssetsSet.contains(asset.localIdentifier) {
                                // maxSelection 체크
                                if galleryVC.maxSelection == 0 || galleryVC.selectedAssets.count < galleryVC.maxSelection {
                                    galleryVC.selectedAssets.append(asset)
                                    galleryVC.selectedAssetsSet.insert(asset.localIdentifier)
                                }
                            }
                        }
                        galleryVC.updateSelectedCellNumbers()
                        galleryVC.notifySelectionChanged()
                        galleryVC.updateNavigationBarForSelection()
                        galleryVC.collectionView.reloadData()
                    }
                }
            }
        }
        
        editorVC.onCancel = { [weak galleryVC] in
            if !isMultiSelect {
                galleryVC?.selectedAssetsSet.removeAll()
                galleryVC?.selectedAssets.removeAll()
                galleryVC?.refreshSelectionAfterEdit()
            }
        }

        editorVC.onConfirm = { [weak self, weak galleryVC, weak editorVC] (editedAsset, croppedImage, filterState, caption) in
            if isMultiSelect {
                // 다중 선택 모드: 편집 완료 후 갤러리로 복귀 (선택 유지)
                editorVC?.dismiss(animated: true) {
                    galleryVC?.refreshSelectionAfterEdit()
                    self?.resultLabel.text = "✅ 편집 완료 — 갤러리로 복귀\n캡션: \(caption)"
                }
            } else {
                // 단일 선택 모드: 2-step dismiss → 에디터 닫고, 갤러리 닫음
                editorVC?.dismiss(animated: true) {
                    self?.dismiss(animated: true) {
                        self?.resultLabel.text = "✅ 편집 완료 (1장)\n불러오는 중..."
                        
                        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                            var ext = "JPG"
                            var sizeString = ""
                            
                            var targetImage = croppedImage
                            if targetImage == nil, let asset = editedAsset {
                                targetImage = self?.getImageSync(for: asset)
                            }
                            
                            // 필터 적용 로직 추가
                            if let base = targetImage,
                               filterState.filterId != "original",
                               let filter = FilterManager.shared.filters.first(where: { $0.id == filterState.filterId }),
                               let ciImage = CIImage(image: base),
                               let out = filter.apply(ciImage, filterState.intensity),
                               let cgImg = FilterManager.shared.context.createCGImage(out, from: out.extent) {
                                targetImage = UIImage(cgImage: cgImg, scale: base.scale, orientation: base.imageOrientation)
                            }
                            
                            var finalImage = targetImage
                            var finalWidth = Int(targetImage?.size.width ?? 0)
                            var finalHeight = Int(targetImage?.size.height ?? 0)
                            
                            if let img = targetImage, let webpData = self?.encodeWebP(image: img, quality: 0.85) {
                                ext = "WEBP"
                                let sizeInKB = Double(webpData.count) / 1024.0
                                sizeString = sizeInKB > 1024 ? String(format: "%.1fMB", sizeInKB / 1024.0) : String(format: "%.1fKB", sizeInKB)
                                if let decoded = UIImage(data: webpData) { finalImage = decoded }
                                finalWidth = Int(img.size.width)
                                finalHeight = Int(img.size.height)
                            } else if let img = targetImage, let jpgData = img.jpegData(compressionQuality: 0.85) {
                                ext = "JPG"
                                let sizeInKB = Double(jpgData.count) / 1024.0
                                sizeString = sizeInKB > 1024 ? String(format: "%.1fMB", sizeInKB / 1024.0) : String(format: "%.1fKB", sizeInKB)
                                if let decoded = UIImage(data: jpgData) { finalImage = decoded }
                                finalWidth = Int(img.size.width)
                                finalHeight = Int(img.size.height)
                            }
                            
                            let sizePart = sizeString.isEmpty ? "" : " • \(sizeString)"
                            let finalResultText = "✅ 편집 완료 (1장)\n  1. \(finalWidth)×\(finalHeight) • \(ext)\(sizePart)\n캡션: \(caption)"
                            
                            DispatchQueue.main.async {
                                self?.resultLabel.text = finalResultText
                                if let img = finalImage {
                                    self?.updateImageViews(with: [img])
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // 갤러리 Nav 위에 fullScreen 에디터 올리기
        if let galNav = presentedViewController {
            var savedDetent: UISheetPresentationController.Detent.Identifier? = nil
            if #available(iOS 15.0, *) {
                if let nav = galNav as? UINavigationController {
                    savedDetent = nav.sheetPresentationController?.selectedDetentIdentifier
                } else {
                    savedDetent = galNav.sheetPresentationController?.selectedDetentIdentifier
                }
            }
            galNav.present(editorVC, animated: true) {
                if #available(iOS 15.0, *) {
                    if let saved = savedDetent {
                        if let nav = galNav as? UINavigationController {
                            nav.sheetPresentationController?.selectedDetentIdentifier = saved
                        } else {
                            galNav.sheetPresentationController?.selectedDetentIdentifier = saved
                        }
                    }
                }
            }
        } else {
            present(editorVC, animated: true)
        }
    }
    
    private func getImageSync(for asset: PHAsset, maxPx: Int = 1024) -> UIImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        var resultImage: UIImage?
        let targetSize = maxPx > 0
            ? CGSize(width: maxPx, height: maxPx)
            : CGSize(width: 2500, height: 2500)
        PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { img, _ in
            resultImage = img
        }
        return resultImage
    }

    // MARK: - Result

    private func encodeWebP(image: UIImage, quality: CGFloat) -> Data? {
        #if canImport(SDWebImageWebPCoder)
        return SDImageWebPCoder.shared.encodedData(with: image, format: .webP, options: [.encodeCompressionQuality: quality])
        #else
        return nil
        #endif
    }

    private func showResult(images: [(PHAsset?, UIImage)], label: String, startTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) {
        resultLabel.text = "✅ \(label) — \(images.count)장\n처리 중..."
        // 처리 전에는 비워두거나 이전 이미지를 유지 (여기서는 처리 완료 후 교체)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var lineResults: [Int: String] = [:]
            var processedImages: [Int: UIImage] = [:] // 처리된 이미지 저장용
            let lock = NSLock()
            let group = DispatchGroup()
            
            for (i, pair) in images.enumerated() {
                group.enter()
                DispatchQueue.global(qos: .default).async {
                    let image = pair.1
                    let width  = Int(image.size.width)
                    let height = Int(image.size.height)

                    var ext = "JPG"
                    var sizeString = ""
                    var finalImage = image

                    // 1. 인코딩 수행
                    if let webpData = self.encodeWebP(image: image, quality: 0.85) {
                        ext = "WEBP"
                        let sizeInKB = Double(webpData.count) / 1024.0
                        sizeString = sizeInKB > 1024 ? String(format: "%.1fMB", sizeInKB / 1024.0) : String(format: "%.1fKB", sizeInKB)
                        
                        // 2. 인코딩된 데이터를 다시 이미지로 변환 (작업된 결과물)
                        if let decoded = UIImage(data: webpData) {
                            finalImage = decoded
                        }
                    } else if let jpgData = image.jpegData(compressionQuality: 0.85) {
                        ext = "JPG"
                        let sizeInKB = Double(jpgData.count) / 1024.0
                        sizeString = sizeInKB > 1024 ? String(format: "%.1fMB", sizeInKB / 1024.0) : String(format: "%.1fKB", sizeInKB)
                        
                        if let decoded = UIImage(data: jpgData) {
                            finalImage = decoded
                        }
                    }

                    let sizePart = sizeString.isEmpty ? "" : " • \(sizeString)"
                    let line = "  \(i + 1). \(width)×\(height) • \(ext)\(sizePart)"
                    
                    lock.lock()
                    lineResults[i] = line
                    processedImages[i] = finalImage
                    lock.unlock()
                    group.leave()
                }
            }
            
            group.wait()
            
            let sortedLines = lineResults.keys.sorted().compactMap { lineResults[$0] }.joined(separator: "\n")
            let sortedImages = processedImages.keys.sorted().compactMap { processedImages[$0] }
            
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let timeStr = String(format: "⏱ 총 소요: %.2f초", elapsed)

            DispatchQueue.main.async {
                self.resultLabel.text = "✅ \(label) — \(images.count)장  \(timeStr)\n\(sortedLines)"
                // 실제 처리된(인코딩된) 이미지들로 하단 뷰 업데이트
                self.updateImageViews(with: sortedImages)
            }
        }
    }

    private var currentTestGroup: Int = 1
    
    private var editorTransitionDelegate: ImageEditorTransitionDelegate?
    private var currentDisplayImages: [UIImage] = []

    private func updateImageViews(with images: [UIImage]) {
        self.currentDisplayImages = images
        
        // 기존 뷰 제거
        imageStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // 새 이미지 추가
        for (index, img) in images.enumerated() {
            let iv = UIImageView(image: img)
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            iv.layer.cornerRadius = 8
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.widthAnchor.constraint(equalToConstant: 120).isActive = true
            
            iv.isUserInteractionEnabled = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(imageTapped(_:)))
            iv.addGestureRecognizer(tap)
            iv.tag = index
            
            imageStackView.addArrangedSubview(iv)
        }
    }
    
    @objc private func imageTapped(_ sender: UITapGestureRecognizer) {
        guard let view = sender.view else { return }
        let index = view.tag
        
        var imageUrls: [String] = []
        for (i, img) in currentDisplayImages.enumerated() {
            let fakeUrl = "memory_test_img_\(i)_\(Date().timeIntervalSince1970)"
            imageUrls.append(fakeUrl)
            ViewerImageCache.shared.saveImage(img, for: fakeUrl)
        }
        
        let viewerVC = RemoteImageViewerViewController(imageUrls: imageUrls, initialIndex: index)
        viewerVC.languageCode = "ko"
        present(viewerVC, animated: true)
    }
}

