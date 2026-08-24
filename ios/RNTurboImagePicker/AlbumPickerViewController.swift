//
//  AlbumPickerViewController.swift
//  ImageGalleryTest
//
//  중앙 팝업 스타일 앨범 선택 화면
//

import UIKit
import Photos

protocol AlbumPickerDelegate: AnyObject {
    func albumPicker(_ picker: AlbumPickerViewController, didSelectAlbum album: Album)
    func albumPickerDidDismiss(_ picker: AlbumPickerViewController)
}

class AlbumPickerViewController: UIViewController {
    
    // MARK: - Properties
    
    weak var delegate: AlbumPickerDelegate?
    
    // 테마 컬러
    var themeColor: UIColor?
    
    var albums: [Album] = []
    var selectedAlbum: Album?
    
    // 그라데이션 레이어 참조
    private var gradientLayer: CAGradientLayer?
    
    // MARK: - UI Components
    
    private lazy var backgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = .clear  // 완전 투명
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alpha = 0
        view.isUserInteractionEnabled = true  // 터치 이벤트 허용
        return view
    }()
    
    private lazy var popupContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.layer.cornerRadius = 16
        view.layer.masksToBounds = false
        view.translatesAutoresizingMaskIntoConstraints = false
        view.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        view.alpha = 0
        
        // 블러 효과 추가 (시스템 테마에 맞게)
        let blurStyle: UIBlurEffect.Style
        if #available(iOS 13.0, *) {
            blurStyle = .systemMaterial
        } else {
            blurStyle = .dark
        }
        let blurEffect = UIBlurEffect(style: blurStyle)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = 16
        blurView.layer.masksToBounds = true
        view.addSubview(blurView)
        
        // 그라데이션 오버레이 추가 (시스템 테마에 맞게)
        let gradientLayer = CAGradientLayer()
        if #available(iOS 13.0, *) {
            if self.traitCollection.userInterfaceStyle == .dark {
                gradientLayer.colors = [
                    UIColor.black.withAlphaComponent(0.2).cgColor,
                    UIColor.black.withAlphaComponent(0.05).cgColor
                ]
            } else {
                gradientLayer.colors = [
                    UIColor.white.withAlphaComponent(0.1).cgColor,
                    UIColor.white.withAlphaComponent(0.0).cgColor
                ]
            }
        } else {
            gradientLayer.colors = [
                UIColor.black.withAlphaComponent(0.2).cgColor,
                UIColor.black.withAlphaComponent(0.05).cgColor
            ]
        }
        gradientLayer.locations = [0.0, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        gradientLayer.cornerRadius = 16
        view.layer.addSublayer(gradientLayer)
        
        // 그림자 효과 추가
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 8)
        view.layer.shadowRadius = 20
        view.layer.shadowOpacity = 0.3
        
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: view.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // 그라데이션 레이어를 저장하여 나중에 프레임 업데이트
        self.gradientLayer = gradientLayer
        
        return view
    }()
    
    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.backgroundColor = .clear
        tv.delegate = self
        tv.dataSource = self
        tv.register(AlbumCell.self, forCellReuseIdentifier: AlbumCell.identifier)
        tv.rowHeight = 70  // 더 컴팩트한 크기
        tv.separatorStyle = .none  // 구분선 제거로 더 깔끔하게
        tv.showsVerticalScrollIndicator = true
        tv.showsHorizontalScrollIndicator = false
        tv.bounces = true
        tv.alwaysBounceVertical = false
        tv.scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: -8)
        tv.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0) // 상하 여백
        return tv
    }()
    
    // Cancel 버튼 제거됨
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 🚀 성능 최적화: TableView 최적화
        tableView.estimatedRowHeight = 70
        
        setupUI()
        setupTapGesture()
        updatePopupHeight()
    }
    
    private func updatePopupHeight() {
        // 팝업 높이를 앨범 개수에 따라 동적으로 조정 (개선된 디자인)
        let maxHeight: CGFloat = 400  // 작은 팝업 크기
        let minHeight: CGFloat = 200
        let calculatedHeight = CGFloat(albums.count * 70) + 32 // 셀 높이 + 여백
        
        let finalHeight = min(max(calculatedHeight, minHeight), maxHeight)
        
        // 높이 제약 조건 업데이트
        popupContainer.constraints.forEach { constraint in
            if constraint.firstAttribute == .height {
                constraint.constant = finalHeight
            }
        }
        
        // 테이블뷰가 스크롤 가능하도록 설정
        tableView.isScrollEnabled = calculatedHeight > maxHeight
        tableView.bounces = tableView.isScrollEnabled
        tableView.alwaysBounceVertical = tableView.isScrollEnabled
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showPopup()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 그라데이션 레이어 프레임과 cornerRadius 업데이트
        gradientLayer?.frame = popupContainer.bounds
        gradientLayer?.cornerRadius = 16
    }
    
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = .clear
        
        view.addSubview(backgroundView)
        view.addSubview(popupContainer)
        popupContainer.addSubview(tableView)
        
        // 화면 크기에 따른 위치 조정
        let screenHeight = UIScreen.main.bounds.height
        let isCompactScreen = screenHeight < 700 // iPhone SE, mini 등 작은 화면
        
        // 네비게이션 바 바로 아래 위치 계산
        let navigationBarHeight = navigationController?.navigationBar.frame.height ?? 44
        let statusBarHeight = view.safeAreaInsets.top
        let topOffset = navigationBarHeight + statusBarHeight + (isCompactScreen ? 4 : 8)
        
        NSLayoutConstraint.activate([
            // Background view
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Popup container - 네비게이션 바 바로 아래 위치
            popupContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            popupContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: topOffset),
            popupContainer.widthAnchor.constraint(equalToConstant: isCompactScreen ? 260 : 280),
            popupContainer.heightAnchor.constraint(equalToConstant: 250), // 임시 높이, updatePopupHeight에서 업데이트됨
            
            // Table view - Cancel 버튼 없이 전체 영역 사용
            tableView.topAnchor.constraint(equalTo: popupContainer.topAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: popupContainer.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: popupContainer.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: popupContainer.bottomAnchor, constant: -16)
        ])
    }
    
    private func setupTapGesture() {
        // 팝업 외부 터치 시 닫기
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        backgroundView.addGestureRecognizer(tapGesture)
        
        // 스크롤 제스처 차단
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(backgroundPanned))
        panGesture.delegate = self
        backgroundView.addGestureRecognizer(panGesture)
    }
    
    // MARK: - Actions
    
    @objc private func backgroundTapped() {
        hidePopup()
    }
    
    @objc private func backgroundPanned(_ gesture: UIPanGestureRecognizer) {
        // 스크롤 제스처 차단 - 아무것도 하지 않음
        return
    }
    
    // MARK: - Animation
    
    private func showPopup() {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: .curveEaseOut) {
            self.backgroundView.alpha = 1
            self.popupContainer.alpha = 1
            self.popupContainer.transform = .identity
        }
    }
    
    private func hidePopup() {
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseIn) {
            self.backgroundView.alpha = 0
            self.popupContainer.alpha = 0
            self.popupContainer.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        } completion: { _ in
            self.delegate?.albumPickerDidDismiss(self)
            self.dismiss(animated: false)
        }
    }

    // MARK: - Deinit

    deinit {
        debugPrint("🧹 [Deinit] AlbumPickerViewController 해제 시작")
        
        // Gesture Recognizers 정리
        backgroundView.gestureRecognizers?.forEach { backgroundView.removeGestureRecognizer($0) }
        
        // TableView delegate 해제
        tableView.delegate = nil
        tableView.dataSource = nil
        
        // Albums 배열 정리
        albums.removeAll()
        selectedAlbum = nil
        
        // Delegate 해제 (weak이므로 자동 해제되지만 명시적으로)
        delegate = nil
        
        // Gradient layer 정리
        gradientLayer?.removeFromSuperlayer()
        gradientLayer = nil
        
        debugPrint("✅ [Deinit] AlbumPickerViewController 해제 완료")
    }
}

// MARK: - UITableViewDataSource

extension AlbumPickerViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return albums.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: AlbumCell.identifier,
            for: indexPath
        ) as? AlbumCell else {
            return UITableViewCell()
        }
        
        let album = albums[indexPath.row]
        let isSelected = selectedAlbum?.identifier == album.identifier
        
        // Pass the themeColor to the cell
        cell.themeColor = self.themeColor
        
        cell.configure(with: album, isSelected: isSelected, index: indexPath.row)
        
        return cell
    }
}

// MARK: - UIGestureRecognizerDelegate

extension AlbumPickerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
}

// MARK: - UITableViewDelegate

extension AlbumPickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let album = albums[indexPath.row]
        delegate?.albumPicker(self, didSelectAlbum: album)
        
        hidePopup()
    }
}

// MARK: - Album Cell (iOS Photos 스타일)

class AlbumCell: UITableViewCell {
    
    static let identifier = "AlbumCell"
    
    // 테마 컬러
    var themeColor: UIColor?
    
    // 🚀 성능 최적화: 이미지 요청 ID 추적 (셀 재사용 시 취소용)
    private var imageRequestID: PHImageRequestID?
    
    // MARK: - UI Components
    
    private var cellBackgroundView: UIView?
    
    private let thumbnailImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .systemGray5
        iv.layer.cornerRadius = 8  // 더 둥글게
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    
    private let albumTitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 18, weight: .regular)
        if #available(iOS 13.0, *) {
            label.textColor = .label
        } else {
            label.textColor = .white
        }
        // 텍스트 말줄임표 처리
        label.lineBreakMode = .byTruncatingTail
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let photoCountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let checkmarkImageView: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "checkmark")
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        return iv
    }()
    
    // MARK: - Initialization
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        // 배경 뷰 추가 (선택 효과용)
        let cellBackgroundView = UIView()
        cellBackgroundView.backgroundColor = .clear
        cellBackgroundView.layer.cornerRadius = 8
        cellBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        
        contentView.addSubview(cellBackgroundView)
        contentView.addSubview(thumbnailImageView)
        contentView.addSubview(albumTitleLabel)
        contentView.addSubview(photoCountLabel)
        contentView.addSubview(checkmarkImageView)
        
        NSLayoutConstraint.activate([
            // 배경 뷰
            cellBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            cellBackgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            cellBackgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            cellBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            // 썸네일 이미지: 더 작고 깔끔하게 (50x50)
            thumbnailImageView.leadingAnchor.constraint(equalTo: cellBackgroundView.leadingAnchor, constant: 12),
            thumbnailImageView.centerYAnchor.constraint(equalTo: cellBackgroundView.centerYAnchor),
            thumbnailImageView.widthAnchor.constraint(equalToConstant: 50),
            thumbnailImageView.heightAnchor.constraint(equalToConstant: 50),
            
            // 앨범 제목
            albumTitleLabel.leadingAnchor.constraint(equalTo: thumbnailImageView.trailingAnchor, constant: 12),
            albumTitleLabel.topAnchor.constraint(equalTo: cellBackgroundView.topAnchor, constant: 16),
            albumTitleLabel.trailingAnchor.constraint(equalTo: checkmarkImageView.leadingAnchor, constant: -12),
            
            // 사진 개수
            photoCountLabel.leadingAnchor.constraint(equalTo: albumTitleLabel.leadingAnchor),
            photoCountLabel.topAnchor.constraint(equalTo: albumTitleLabel.bottomAnchor, constant: 2),
            photoCountLabel.trailingAnchor.constraint(equalTo: albumTitleLabel.trailingAnchor),
            
            // 체크마크
            checkmarkImageView.trailingAnchor.constraint(equalTo: cellBackgroundView.trailingAnchor, constant: -16),
            checkmarkImageView.centerYAnchor.constraint(equalTo: cellBackgroundView.centerYAnchor),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 18),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 18)
        ])
        
        // 선택 효과를 위한 배경 뷰 참조 저장
        self.cellBackgroundView = cellBackgroundView
        
        // 셀 배경을 완전히 투명하게 설정
        self.backgroundColor = .clear
        self.contentView.backgroundColor = .clear
    }
    
    // MARK: - Configuration
    
    func configure(with album: Album, isSelected: Bool, index: Int) {
        albumTitleLabel.text = album.title
        photoCountLabel.text = "\(album.count)"
        checkmarkImageView.isHidden = !isSelected
        
        // 선택 상태에 따른 배경 색상 변경
        let effectiveThemeColor = self.themeColor ?? UIColor(red: 236/255, green: 73/255, blue: 38/255, alpha: 1.0)
        
        if isSelected {
            cellBackgroundView?.backgroundColor = effectiveThemeColor.withAlphaComponent(0.2)
            albumTitleLabel.textColor = effectiveThemeColor
            photoCountLabel.textColor = effectiveThemeColor
            checkmarkImageView.tintColor = effectiveThemeColor
            checkmarkImageView.isHidden = false
        } else {
            cellBackgroundView?.backgroundColor = .clear
            // 시스템 테마에 맞는 텍스트 색상 사용
            if #available(iOS 13.0, *) {
                albumTitleLabel.textColor = .label
                photoCountLabel.textColor = .secondaryLabel
                checkmarkImageView.tintColor = effectiveThemeColor
            } else {
                albumTitleLabel.textColor = .white
                photoCountLabel.textColor = .white.withAlphaComponent(0.8)
            }
        }
        
        // 앨범의 첫 번째 사진을 썸네일로 표시
        loadThumbnail(for: album)
    }
    
    private func loadThumbnail(for album: Album) {
        // 🚀 성능 최적화: 이전 요청 취소 (셀 재사용 시 잘못된 이미지 방지)
        if let prevID = imageRequestID {
            PHImageManager.default().cancelImageRequest(prevID)
            imageRequestID = nil
        }
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.fetchLimit = 1
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let assets = PHAsset.fetchAssets(in: album.collection, options: fetchOptions)
        
        guard let asset = assets.firstObject else {
            thumbnailImageView.image = nil
            return
        }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true
        
        // 팝업에 맞는 썸네일 크기 (50x50)
        let scale = UIScreen.main.scale
        let targetSize = CGSize(width: 50 * scale, height: 50 * scale)
        
        imageRequestID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, _ in
            DispatchQueue.main.async {
                self?.thumbnailImageView.image = image
            }
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        // 🚀 성능 최적화: 진행 중인 이미지 요청 취소
        if let prevID = imageRequestID {
            PHImageManager.default().cancelImageRequest(prevID)
            imageRequestID = nil
        }
        
        thumbnailImageView.image = nil
        checkmarkImageView.isHidden = true
        checkmarkImageView.tintColor = UIColor(red: 236/255, green: 73/255, blue: 38/255, alpha: 1.0) // #EC4926
        cellBackgroundView?.backgroundColor = .clear
        
        // 시스템 테마에 맞는 텍스트 색상 사용
        if #available(iOS 13.0, *) {
            albumTitleLabel.textColor = .label
            photoCountLabel.textColor = .secondaryLabel
        } else {
            albumTitleLabel.textColor = .white
            photoCountLabel.textColor = .white.withAlphaComponent(0.8)
        }
    }
}
