//
//  ImageViewerViewController.swift
//  ImageGalleryTest
//
//  텔레그램 스타일 하단 모달 - 이미지 뷰어
//  모달 높이: 50% 고정, 줌 기능 없음
//

import UIKit
import Photos

class ImageViewerViewController: UIViewController {
    public var languageCode: String = "en"
    
    // MARK: - Properties
    
    private let asset: PHAsset
    private let photoManager = PhotoManager.shared
    private var imageRequestID: PHImageRequestID?
    private var initialTouchPoint: CGPoint = .zero
    
    // MARK: - UI Components
    
    private let dimmedView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alpha = 0
        return view
    }()
    
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 16
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.clipsToBounds = true
        return view
    }()
    
    private let handleBar: UIView = {
        let view = UIView()
        view.backgroundColor = .systemGray3
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 2.5
        return view
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "사진"
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(Localizer.getString(key: "cancel", languageCode: languageCode), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.backgroundColor = .clear
        return iv
    }()
    
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    // Constraints
    private var containerViewHeightConstraint: NSLayoutConstraint!
    private var containerViewBottomConstraint: NSLayoutConstraint!
    
    // MARK: - Initialization
    
    init(asset: PHAsset) {
        self.asset = asset
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupGestures()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animatePresent()
        loadImage()
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.backgroundColor = .clear
        
        view.addSubview(dimmedView)
        view.addSubview(containerView)
        containerView.addSubview(handleBar)
        containerView.addSubview(titleLabel)
        containerView.addSubview(closeButton)
        containerView.addSubview(imageView)
        containerView.addSubview(loadingIndicator)
        
        // 🔥 화면 높이의 정확히 50%
        let screenHeight = UIScreen.main.bounds.height
        let containerHeight = screenHeight * 0.5
        
        print("📏 화면 높이: \(screenHeight)pt")
        print("📏 모달 높이: \(containerHeight)pt (50%)")
        
        containerViewHeightConstraint = containerView.heightAnchor.constraint(equalToConstant: containerHeight)
        containerViewBottomConstraint = containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: containerHeight)
        
        NSLayoutConstraint.activate([
            // Dimmed View
            dimmedView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmedView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Container View
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerViewHeightConstraint,
            containerViewBottomConstraint,
            
            // Handle Bar
            handleBar.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            handleBar.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            handleBar.widthAnchor.constraint(equalToConstant: 36),
            handleBar.heightAnchor.constraint(equalToConstant: 5),
            
            // Title Label
            titleLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: handleBar.bottomAnchor, constant: 12),
            
            // Close Button
            closeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            
            // Image View
            imageView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),
            
            // Loading Indicator
            loadingIndicator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])
        
        
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
    }
    
    private func setupGestures() {
        // Dimmed view 탭으로 닫기
        let dimmedTapGesture = UITapGestureRecognizer(target: self, action: #selector(dimmedViewTapped))
        dimmedView.addGestureRecognizer(dimmedTapGesture)
        
        // Pan gesture로 아래로 스와이프해서 닫기
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        containerView.addGestureRecognizer(panGesture)
    }
    
    // MARK: - Image Loading
    
    private func loadImage() {
        loadingIndicator.startAnimating()
        fetchAssetMetadata()
        
        let targetSize = CGSize(
            width: UIScreen.main.bounds.width * UIScreen.main.scale,
            height: UIScreen.main.bounds.height * UIScreen.main.scale
        )
        
        imageRequestID = photoManager.requestFullImage(
            for: asset,
            targetSize: targetSize,
            progressHandler: nil
        ) { [weak self] image in
            guard let self = self, let image = image else { return }
            
            DispatchQueue.main.async {
                self.imageView.image = image
                self.loadingIndicator.stopAnimating()
            }
        }
    }
    
    private func fetchAssetMetadata() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let resources = PHAssetResource.assetResources(for: self.asset)
            if let resource = resources.first {
                let filename = resource.originalFilename
                let ext = (filename as NSString).pathExtension.uppercased()
                
                var sizeString = ""
                if let fileSize = resource.value(forKey: "fileSize") as? Int64 {
                    let sizeInKB = Double(fileSize) / 1024.0
                    if sizeInKB > 1024 {
                        sizeString = String(format: "%.1fMB", sizeInKB / 1024.0)
                    } else {
                        sizeString = String(format: "%.1fKB", sizeInKB)
                    }
                }
                
                let width = self.asset.pixelWidth
                let height = self.asset.pixelHeight
                
                DispatchQueue.main.async {
                    self.titleLabel.text = "\(width)x\(height) • \(ext)\(sizeString.isEmpty ? "" : " • \(sizeString)")"
                    self.titleLabel.font = .systemFont(ofSize: 14, weight: .regular)
                    self.titleLabel.textColor = .secondaryLabel
                }
            }
        }
    }
    
    // MARK: - Animations
    
    private func animatePresent() {
        containerViewBottomConstraint.constant = 0
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
            self.dimmedView.alpha = 1
            self.view.layoutIfNeeded()
        }
    }
    
    private func animateDismiss(completion: @escaping () -> Void) {
        containerViewBottomConstraint.constant = containerViewHeightConstraint.constant
        
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseIn) {
            self.dimmedView.alpha = 0
            self.view.layoutIfNeeded()
        } completion: { _ in
            completion()
        }
    }
    
    // MARK: - Actions
    
    @objc private func closeButtonTapped() {
        animateDismiss { [weak self] in
            self?.dismiss(animated: false)
        }
    }
    
    @objc private func dimmedViewTapped() {
        animateDismiss { [weak self] in
            self?.dismiss(animated: false)
        }
    }
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        
        switch gesture.state {
        case .began:
            initialTouchPoint = gesture.location(in: view)
            
        case .changed:
            if translation.y > 0 {
                containerViewBottomConstraint.constant = -translation.y
                let progress = min(translation.y / 300, 1.0)
                dimmedView.alpha = 1 - progress
            }
            
        case .ended, .cancelled:
            if translation.y > 150 || velocity.y > 500 {
                animateDismiss { [weak self] in
                    self?.dismiss(animated: false)
                }
            } else {
                containerViewBottomConstraint.constant = 0
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
                    self.dimmedView.alpha = 1
                    self.view.layoutIfNeeded()
                }
            }
            
        default:
            break
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        debugPrint("🧹 [Deinit] ImageViewerViewController 해제 시작")
        
        // Gesture Recognizers 정리
        dimmedView.gestureRecognizers?.forEach { dimmedView.removeGestureRecognizer($0) }
        containerView.gestureRecognizers?.forEach { containerView.removeGestureRecognizer($0) }
        
        // 이미지 해제
        imageView.image = nil
        
        debugPrint("✅ [Deinit] ImageViewerViewController 해제 완료")
    }
}
