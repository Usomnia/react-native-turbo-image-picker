//
//  GalleryCell.swift
//  ImageGalleryTest
//
//  텔레그램급 성능 최적화된 갤러리 셀
//  - 초고속 썸네일 로딩
//  - 메모리 효율적 재사용
//

import UIKit
import Photos

class GalleryCell: UICollectionViewCell {
    
    static let identifier = "GalleryCell"
    
    // MARK: - Properties
    
    private var currentRequestID: PHImageRequestID?
    private let photoManager = PhotoManager.shared
    
    // MARK: - UI Components
    
    let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        if #available(iOS 13.0, *) {
            iv.backgroundColor = .secondarySystemBackground
        } else {
            iv.backgroundColor = UIColor(white: 0.95, alpha: 1.0)
        }
        return iv
    }()
    
    private let placeholderView: UIView = {
        let view = UIView()
        if #available(iOS 13.0, *) {
            view.backgroundColor = .secondarySystemBackground
        } else {
            view.backgroundColor = UIColor(white: 0.95, alpha: 1.0)
        }
        view.isHidden = true
        return view
    }()
    
    // 선택 UI
    private let selectionCircle: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(white: 0.6, alpha: 0.8)
        view.layer.borderWidth = 1.0
        view.layer.borderColor = UIColor(white: 0.8, alpha: 0.9).cgColor
        view.layer.cornerRadius = 12
        return view
    }()
    
    private let selectedCircle: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(red: 236/255, green: 73/255, blue: 38/255, alpha: 1.0)  // #EC4926
        view.layer.borderWidth = 0
        view.layer.borderColor = UIColor.clear.cgColor
        view.layer.cornerRadius = 12
        view.isHidden = true
        return view
    }()
    
    private let selectionNumberLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()
    
    var onSelectTapped: (() -> Void)?
    var onDeleteTapped: (() -> Void)?
    
    private lazy var deleteButton: UIButton = {
        let btn = UIButton(type: .system)
        // 아이콘 크기를 조금 더 줄임 (12)
        let cfg = UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        btn.setImage(UIImage(systemName: "trash", withConfiguration: cfg), for: .normal)
        // 아이콘은 흰색으로
        btn.tintColor = .white
        // 배경은 반투명 붉은색
        btn.backgroundColor = UIColor(red: 236/255, green: 73/255, blue: 38/255, alpha: 0.85)
        btn.layer.cornerRadius = 14
        btn.addTarget(self, action: #selector(deleteButtonTapped), for: .touchUpInside)
        btn.isHidden = true
        return btn
    }()
    
    @objc private func deleteButtonTapped() {
        onDeleteTapped?()
    }
    
    private lazy var selectionButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.backgroundColor = .clear
        btn.addTarget(self, action: #selector(selectionButtonTapped), for: .touchUpInside)
        return btn
    }()
    
    @objc private func selectionButtonTapped() {
        onSelectTapped?()
    }
    
    // 라이브 카메라 프리뷰 뷰 (internal: 오버레이가 동일한 뷰를 재사용할 수 있도록)
    // 🚀 GalleryViewController에서 주입받는 공유 프리뷰 (스크롤 끊김 방지)
    weak var sharedCameraPreviewView: CameraPreviewView?
    
    
    // 카메라 아이콘 뷰 (프리뷰 위에 오버레이)
    private let cameraIconView: UIView = {
        let container = UIView()
        container.backgroundColor = .clear
        container.isHidden = true
        
        let iconImageView = UIImageView()
        iconImageView.image = UIImage(systemName: "camera.fill")
        iconImageView.tintColor = .white
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        
        // 카메라 피드가 밝을 때도 아이콘이 잘 보이도록 약간의 그림자 추가
        iconImageView.layer.shadowColor = UIColor.black.cgColor
        iconImageView.layer.shadowOffset = CGSize(width: 0, height: 1)
        iconImageView.layer.shadowOpacity = 0.5
        iconImageView.layer.shadowRadius = 2
        
        container.addSubview(iconImageView)
        NSLayoutConstraint.activate([
            // 상단 우측에 배치 (마진 8px)
            iconImageView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            iconImageView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            iconImageView.widthAnchor.constraint(equalToConstant: 24),
            iconImageView.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        return container
    }()
    
    private var isPhotoSelected: Bool = false {
        didSet {
            updateSelectionUI()
        }
    }
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        if #available(iOS 13.0, *) {
            contentView.backgroundColor = .secondarySystemBackground
        } else {
            contentView.backgroundColor = UIColor(white: 0.95, alpha: 1.0)
        }
        
        contentView.addSubview(placeholderView)
        placeholderView.frame = contentView.bounds
        placeholderView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        contentView.addSubview(imageView)
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // 라이브 카메라 뷰 추가
        // sharedCameraPreviewView는 configureCameraIcon에서 추가됨
        
        // 카메라 아이콘 컨테이너
        contentView.addSubview(cameraIconView)
        cameraIconView.frame = contentView.bounds
        cameraIconView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // 선택 UI - 항상 표시되는 빈 원
        contentView.addSubview(selectionCircle)
        
        // 선택된 상태 원 (숫자 배경)
        contentView.addSubview(selectedCircle)
        selectedCircle.addSubview(selectionNumberLabel)
        
        // 터치 영역을 넓게 잡은 버튼
        contentView.addSubview(selectionButton)
        
        // 삭제 버튼
        contentView.addSubview(deleteButton)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // 🚀 카메라 뷰 프레임 명시적 업데이트
        sharedCameraPreviewView?.frame = contentView.bounds
        cameraIconView.frame = contentView.bounds
        
        // 서클을 오른쪽 상단에 배치
        let circleSize: CGFloat = 24
        let margin: CGFloat = 6
        let circleFrame = CGRect(
            x: contentView.bounds.width - circleSize - margin,
            y: margin,
            width: circleSize,
            height: circleSize
        )
        
        selectionCircle.frame = circleFrame
        selectedCircle.frame = circleFrame
        selectionNumberLabel.frame = selectedCircle.bounds
        
        // 터치 영역은 셀 크기의 1/3 (우측 상단)
        let touchAreaWidth = contentView.bounds.width / 3.0
        let touchAreaHeight = contentView.bounds.height / 3.0
        selectionButton.frame = CGRect(
            x: contentView.bounds.width - touchAreaWidth,
            y: 0,
            width: touchAreaWidth,
            height: touchAreaHeight
        )
        
        // 삭제 버튼 좌측 하단에 배치
        let deleteBtnSize: CGFloat = 28
        deleteButton.frame = CGRect(
            x: margin,
            y: contentView.bounds.height - deleteBtnSize - margin,
            width: deleteBtnSize,
            height: deleteBtnSize
        )
    }
    
    private func updateSelectionUI() {
        // 카메라 아이콘이 표시 중이면 선택 UI 표시하지 않음
        if !cameraIconView.isHidden {
            selectionCircle.isHidden = true
            selectedCircle.isHidden = true
            selectionNumberLabel.isHidden = true
            selectionButton.isHidden = true
            return
        }
        
        selectionButton.isHidden = false
        if isPhotoSelected {
            // 선택됨: 빈 원 숨기고, 숫자 원 표시
            selectionCircle.isHidden = true
            selectedCircle.isHidden = false
            selectionNumberLabel.isHidden = false
        } else {
            // 선택 안됨: 빈 원 표시, 숫자 원 숨김
            selectionCircle.isHidden = false
            selectedCircle.isHidden = true
            selectionNumberLabel.isHidden = true
        }
    }
    
    func setSelected(_ selected: Bool, number: Int = 0) {
        // 카메라 아이콘이 표시 중이면 선택 상태 변경 무시
        guard cameraIconView.isHidden else {
            return
        }
        
        isPhotoSelected = selected
        if selected {
            selectionNumberLabel.text = "\(number)"
        }
        updateSelectionUI()
    }
    
    // 선택 UI를 완전히 숨기는 메서드 (maxSelection == 0일 때 사용)
    func hideSelectionUI() {
        selectionCircle.isHidden = true
        selectedCircle.isHidden = true
        selectionNumberLabel.isHidden = true
        selectionButton.isHidden = true
    }
    
    // MARK: - Configuration
    
    func configure(with asset: PHAsset, targetSize: CGSize, themeColor: UIColor) {
        // 테마 색상 적용
        selectedCircle.backgroundColor = themeColor
        
        // 🚀 핵심: 재사용 시 이전 요청 즉시 취소
        cancelCurrentRequest()
        
        // 카메라 아이콘 숨기기
        cameraIconView.isHidden = true
        
        // 방금 촬영한 사진인지 확인하여 삭제 버튼 표시 여부 결정
        let isCaptured = GalleryViewController.sessionCapturedIdentifiers.contains(asset.localIdentifier)
        deleteButton.isHidden = !isCaptured
        
        // 🚀 성능 최적화: 이전 이미지 유지 (깜빡임 방지)
        // imageView.image = nil을 제거하여 새 이미지 로딩 시까지 이전 이미지 표시
        imageView.isHidden = false
        
        // 초고속 썸네일 요청
        currentRequestID = photoManager.requestThumbnail(
            for: asset,
            targetSize: targetSize
        ) { [weak self] image in
            guard let self = self else { return }
            
            // 🚀 성능 최적화: 이미 메인 스레드면 직접 실행
            if Thread.isMainThread {
                self.imageView.image = image
            } else {
                DispatchQueue.main.async {
                    self.imageView.image = image
                }
            }
        }
    }
    
    // 🚀 편집된 이미지를 바로 설정하는 메서드
    func setEditedImage(_ image: UIImage, themeColor: UIColor, isCaptured: Bool) {
        selectedCircle.backgroundColor = themeColor
        cancelCurrentRequest()
        cameraIconView.isHidden = true
        deleteButton.isHidden = !isCaptured
        imageView.isHidden = false
        imageView.image = image
    }
    
    func configureCameraIcon(galleryID: String, sharedPreview: CameraPreviewView) {
        self.sharedCameraPreviewView = sharedPreview
        
        // 카메라 뷰에 갤러리 ID 전달 (알림 필터링용)
        sharedPreview.galleryID = galleryID
        
        // 이미지 요청 취소
        cancelCurrentRequest()
        
        // 이미지뷰 숨김
        imageView.image = nil
        imageView.isHidden = true
        
        // 선택 UI 숨기기 (카메라 셀에는 선택 UI 표시 안 함)
        hideSelectionUI()
        
        // 공유 프리뷰 뷰를 셀에 부착
        if sharedPreview.superview != contentView {
            sharedPreview.removeFromSuperview()
            contentView.insertSubview(sharedPreview, aboveSubview: imageView)
            sharedPreview.frame = contentView.bounds
            sharedPreview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
        
        // 🚀 카메라 라이브 뷰 표시 (세션은 유지됨)
        sharedPreview.isHidden = false
        // 만약 세션이 정지상태라면(초기화 직후 등) startPreview가 비동기로 켜줌
        sharedPreview.startPreview()
        
        // 카메라 아이콘 표시 (프리뷰 위 오버레이)
        cameraIconView.isHidden = false
        contentView.bringSubviewToFront(cameraIconView)
    }
    
    // MARK: - Reuse
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        // 🧹 재사용 전 정리
        // 1. 진행 중인 이미지 요청 취소
        cancelCurrentRequest()
        
        // 2. 카메라 정리 (세션 종료 없이 부착 해제만 수행하여 스크롤 랙 방지)
        cameraIconView.isHidden = true
        if sharedCameraPreviewView?.superview == contentView {
            sharedCameraPreviewView?.isHidden = true
            sharedCameraPreviewView?.removeFromSuperview()
        }
        sharedCameraPreviewView = nil
        
        // 3. 이미지뷰의 이미지 즉시 해제 (메모리 해제)
        imageView.image = nil
        imageView.isHidden = false
        
        // 4. 레이어 컨텐츠도 명시적으로 클리어 (추가 메모리 해제)
        imageView.layer.contents = nil
        
        // 5. 선택 상태 초기화
        isPhotoSelected = false
    }
    
    // MARK: - Helper
    
    private func cancelCurrentRequest() {
        if let requestID = currentRequestID {
            PHImageManager.default().cancelImageRequest(requestID)
            currentRequestID = nil
        }
    }
    
    /// 전체화면 카메라를 열 때 기존 세션을 공유하기 위한 접근자
    func getCameraSession() -> (session: AVCaptureSession, output: AVCapturePhotoOutput)? {
        return sharedCameraPreviewView?.getCameraSessionInfo()
    }
    
    /// 카메라 셀의 현재 frame을 window 좌표계로 반환
    func cameraFrameInWindow() -> CGRect {
        return convert(bounds, to: window)
    }
    
    /// 오버레이가 동일한 CameraPreviewView 인스턴스를 빌려갈 때 사용
    /// 셀에서 분리한 뒤 반환하므로, 완료 후 반드시 reattachCameraPreviewView()를 호출해야 합니다.
    func detachCameraPreviewView() -> CameraPreviewView? {
        sharedCameraPreviewView?.removeFromSuperview()
        return sharedCameraPreviewView
    }
    
    func reattachCameraPreviewView() {
        guard let preview = sharedCameraPreviewView else { return }
        // 닫기 애니메이션이 transform으로 끝나므로, frame 설정 전에 반드시 리셋
        // (transform과 frame은 동일 run-loop → 중간 상태 렌더링 없음)
        preview.transform = .identity
        preview.removeFromSuperview()
        contentView.insertSubview(preview, aboveSubview: imageView)
        preview.frame = contentView.bounds
        preview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        preview.isHidden = false  // 카메라가 살아있으므로 즉시 표시
    }

    
    // MARK: - Memory
    
    deinit {
        // 최종 정리: 혹시 남아있을 요청 취소
        cancelCurrentRequest()
        
        // 이미지 명시적 해제
        imageView.image = nil
        imageView.layer.contents = nil
    }
}
