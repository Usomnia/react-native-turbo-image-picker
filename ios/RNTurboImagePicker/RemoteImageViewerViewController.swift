import UIKit
import Photos

class ViewerImageCache {
    static let shared = ViewerImageCache()
    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private var diskCacheURL: URL?
    
    init() {
        if let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            diskCacheURL = cacheDir.appendingPathComponent("ViewerImageCache")
            if let diskCacheURL = diskCacheURL, !fileManager.fileExists(atPath: diskCacheURL.path) {
                try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true, attributes: nil)
            }
            cleanupOldCache()
        }
    }
    
    private func getSafeFilename(for url: String) -> String {
        var cacheKey = url
        
        // URL 파싱을 통해 변동성이 있는 인증 토큰(쿼리 파라미터) 제거
        if let urlComponents = URLComponents(string: url) {
            var comps = urlComponents
            
            // 캐시 키에서 제외할 파라미터 키 목록
            let ignoreParams = ["auth", "secret", "apikey"]
            
            let filteredQueryItems = comps.queryItems?.filter { !ignoreParams.contains($0.name) }
            comps.queryItems = filteredQueryItems?.isEmpty == true ? nil : filteredQueryItems
            
            if let consistentString = comps.string {
                cacheKey = consistentString
            }
        }
        
        // 일관된 cacheKey를 바탕으로 해시/Base64 파일명 생성
        guard let data = cacheKey.data(using: .utf8) else { return "\(cacheKey.hashValue)" }
        return data.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }
    
    func getMemoryImage(for url: String) -> UIImage? {
        return memoryCache.object(forKey: url as NSString)
    }
    
    func getDiskImageSynchronously(for url: String) -> UIImage? {
        guard let diskCacheURL = diskCacheURL else { return nil }
        let fileURL = diskCacheURL.appendingPathComponent(getSafeFilename(for: url))
        if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
            return image
        }
        return nil
    }
    
    func setMemoryImage(_ image: UIImage, for url: String) {
        memoryCache.setObject(image, forKey: url as NSString)
    }
    
    func getDiskImage(for url: String, completion: @escaping (UIImage?) -> Void) {
        guard let diskCacheURL = diskCacheURL else {
            completion(nil)
            return
        }
        
        let fileURL = diskCacheURL.appendingPathComponent(getSafeFilename(for: url))
        DispatchQueue.global(qos: .userInitiated).async {
            if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
                if #available(iOS 15.0, *) {
                    image.prepareForDisplay { preparedImage in
                        DispatchQueue.main.async {
                            completion(preparedImage ?? image)
                        }
                    }
                } else {
                    UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
                    image.draw(at: .zero)
                    let decodedImage = UIGraphicsGetImageFromCurrentImageContext()
                    UIGraphicsEndImageContext()
                    DispatchQueue.main.async {
                        completion(decodedImage ?? image)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    func saveImageToMemory(_ image: UIImage, for url: String) {
        memoryCache.setObject(image, forKey: url as NSString)
    }
    
    func saveImage(_ image: UIImage, for url: String) {
        saveImageToMemory(image, for: url)
        
        guard let diskCacheURL = diskCacheURL else { return }
        let fileURL = diskCacheURL.appendingPathComponent(getSafeFilename(for: url))
        
        DispatchQueue.global(qos: .background).async {
            if let data = image.jpegData(compressionQuality: 0.9) {
                try? data.write(to: fileURL)
            }
        }
    }
    
    private func cleanupOldCache() {
        guard let diskCacheURL = diskCacheURL else { return }
        DispatchQueue.global(qos: .background).async {
            let expirationDate = Date().addingTimeInterval(-7 * 24 * 60 * 60) // 7 days
            guard let enumerator = self.fileManager.enumerator(at: diskCacheURL, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else { return }
            
            for case let fileURL as URL in enumerator {
                if let attr = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                   let modificationDate = attr.contentModificationDate {
                    if modificationDate < expirationDate {
                        try? self.fileManager.removeItem(at: fileURL)
                    }
                }
            }
        }
    }
}

class ViewerImageDownloader {
    static let shared = ViewerImageDownloader()
    
    private var callbacks: [String: [(UIImage?) -> Void]] = [:]
    private let lock = NSLock()
    
    func downloadImage(from urlString: String, completion: @escaping (UIImage?) -> Void) {
        if let cached = ViewerImageCache.shared.getMemoryImage(for: urlString) {
            completion(cached)
            return
        }
        
        lock.lock()
        if callbacks[urlString] != nil {
            callbacks[urlString]?.append(completion)
            lock.unlock()
            return
        }
        callbacks[urlString] = [completion]
        lock.unlock()
        
        ViewerImageCache.shared.getDiskImage(for: urlString) { [weak self] diskImage in
            if let diskImage = diskImage {
                ViewerImageCache.shared.saveImageToMemory(diskImage, for: urlString)
                self?.notify(urlString: urlString, image: diskImage)
            } else {
                guard let url = URL(string: urlString) else {
                    self?.notify(urlString: urlString, image: nil)
                    return
                }
                
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    if let data = data, let image = UIImage(data: data) {
                        if #available(iOS 15.0, *) {
                            image.prepareForDisplay { preparedImage in
                                let finalImage = preparedImage ?? image
                                ViewerImageCache.shared.saveImage(finalImage, for: urlString)
                                self?.notify(urlString: urlString, image: finalImage)
                            }
                        } else {
                            UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
                            image.draw(at: .zero)
                            let decodedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
                            UIGraphicsEndImageContext()
                            ViewerImageCache.shared.saveImage(decodedImage, for: urlString)
                            self?.notify(urlString: urlString, image: decodedImage)
                        }
                    } else {
                        self?.notify(urlString: urlString, image: nil)
                    }
                }.resume()
            }
        }
    }
    
    private func notify(urlString: String, image: UIImage?) {
        lock.lock()
        let blocks = callbacks[urlString] ?? []
        callbacks.removeValue(forKey: urlString)
        lock.unlock()
        
        DispatchQueue.main.async {
            for block in blocks {
                block(image)
            }
        }
    }
}


public class RemoteImageViewerViewController: UIViewController {
    
    let imageUrls: [String]
    var currentIndex: Int
    public var onPageChanged: ((Int) -> Void)?
    public var themeColor: UIColor = UIColor(red: 16/255.0, green: 185/255.0, blue: 129/255.0, alpha: 1.0)
    public var languageCode: String = "en"
    public var viewerTitle: String?
    
    public static func prefetchImage(from urlString: String, completion: @escaping (UIImage?) -> Void) {
        if let cached = ViewerImageCache.shared.getMemoryImage(for: urlString) {
            completion(cached)
            return
        }
        
        if urlString.hasPrefix("ph://") {
            let localIdentifier = urlString.replacingOccurrences(of: "ph://", with: "")
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let asset = fetchResult.firstObject else { 
                completion(nil)
                return 
            }
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 800, height: 800),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                if let img = image {
                    // Cache the thumbnail into memory so animator can grab it immediately
                    ViewerImageCache.shared.setMemoryImage(img, for: urlString)
                }
                completion(image)
            }
        } else if urlString.hasPrefix("file://") {
            ViewerImageCache.shared.getDiskImage(for: urlString) { image in
                if let img = image {
                    ViewerImageCache.shared.setMemoryImage(img, for: urlString)
                }
                completion(image)
            }
        } else {
            completion(nil)
        }
    }
    
    let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.isPagingEnabled = true
        sv.showsHorizontalScrollIndicator = false
        sv.backgroundColor = .clear
        return sv
    }()
    
    let topBar: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 13.0, *) {
            view.backgroundColor = UIColor { t in t.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.8) : UIColor.white.withAlphaComponent(0.8) }
        } else {
            view.backgroundColor = UIColor.white.withAlphaComponent(0.8)
        }
        return view
    }()
    
    private let closeButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setImage(UIImage(systemName: "xmark"), for: .normal)
        btn.tintColor = UIColor { t in t.userInterfaceStyle == .dark ? .white : .black }
        return btn
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = UIColor { t in t.userInterfaceStyle == .dark ? .white : .black }
        label.font = .systemFont(ofSize: 15, weight: .bold)
        label.textAlignment = .center
        return label
    }()
    
    // Bottom Section
    let bottomContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 13.0, *) {
            view.backgroundColor = UIColor { t in t.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.8) : UIColor.white.withAlphaComponent(0.8) }
        } else {
            view.backgroundColor = UIColor.white.withAlphaComponent(0.8)
        }
        return view
    }()
    
    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 50, height: 65)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.dataSource = self
        cv.delegate = self
        cv.register(ThumbnailCell.self, forCellWithReuseIdentifier: "ThumbnailCell")
        return cv
    }()
    
    private let counterContainer: UIStackView = {
        let sv = UIStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .horizontal
        sv.spacing = 6
        sv.alignment = .center
        return sv
    }()
    
    private let galleryIcon: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "photo.on.rectangle"))
        iv.tintColor = UIColor { t in t.userInterfaceStyle == .dark ? .white : .black }
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    
    private let counterLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor { t in t.userInterfaceStyle == .dark ? .white : .black }
        label.font = .systemFont(ofSize: 14, weight: .medium)
        return label
    }()
    
    public init(imageUrls: [String], initialIndex: Int) {
        self.imageUrls = imageUrls
        self.currentIndex = initialIndex
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .overFullScreen
        self.modalTransitionStyle = .coverVertical
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var isInitialScrollDone = false
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupUI()
        setupScrollView()
        updateCounterAndSelection()
        setupDismissPanGesture()
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if !isInitialScrollDone, scrollView.bounds.width > 0 {
            isInitialScrollDone = true
            
            // Adjust frames of zoom views in case UIScreen.main.bounds was different
            let width = scrollView.bounds.width
            let height = scrollView.bounds.height
            scrollView.contentSize = CGSize(width: width * CGFloat(imageUrls.count), height: height)
            
            var zoomViews: [ZoomableImageItemView] = []
            for subview in scrollView.subviews {
                if let z = subview as? ZoomableImageItemView { zoomViews.append(z) }
            }
            // Sort by origin.x just in case they are out of order
            zoomViews.sort { $0.frame.origin.x < $1.frame.origin.x }
            for (i, z) in zoomViews.enumerated() {
                z.frame = CGRect(x: width * CGFloat(i), y: 0, width: width, height: height)
            }
            
            if currentIndex > 0 {
                let offsetX = CGFloat(currentIndex) * width
                scrollView.setContentOffset(CGPoint(x: offsetX, y: 0), animated: false)
            }
            
            if currentIndex < imageUrls.count {
                DispatchQueue.main.async {
                    self.collectionView.scrollToItem(at: IndexPath(item: self.currentIndex, section: 0), at: .centeredHorizontally, animated: false)
                }
            }
        }
    }
    
    private func setupUI() {
        view.addSubview(scrollView)
        view.addSubview(topBar)
        topBar.addSubview(closeButton)
        topBar.addSubview(titleLabel)
        
        if let title = viewerTitle {
            titleLabel.text = title
        }
        
        view.addSubview(bottomContainer)
        bottomContainer.addSubview(collectionView)
        bottomContainer.addSubview(counterContainer)
        
        counterContainer.addArrangedSubview(galleryIcon)
        counterContainer.addArrangedSubview(counterLabel)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            closeButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 20),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            
            titleLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            
            topBar.bottomAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 16),
            
            bottomContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            counterContainer.topAnchor.constraint(equalTo: bottomContainer.topAnchor, constant: 16),
            counterContainer.centerXAnchor.constraint(equalTo: bottomContainer.centerXAnchor),
            
            collectionView.topAnchor.constraint(equalTo: counterContainer.bottomAnchor, constant: 16),
            collectionView.leadingAnchor.constraint(equalTo: bottomContainer.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: bottomContainer.trailingAnchor),
            collectionView.heightAnchor.constraint(equalToConstant: 70),
            collectionView.bottomAnchor.constraint(equalTo: bottomContainer.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
        
        closeButton.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
        

    }
    
    private func setupScrollView() {
        scrollView.delegate = self
        
        let width = UIScreen.main.bounds.width
        let height = UIScreen.main.bounds.height
        
        scrollView.contentSize = CGSize(width: width * CGFloat(imageUrls.count), height: height)
        
        for (i, _) in imageUrls.enumerated() {
            let zoomView = ZoomableImageItemView(frame: CGRect(x: width * CGFloat(i), y: 0, width: width, height: height))
            zoomView.tag = 1000 + i
            scrollView.addSubview(zoomView)
        }
    }
    
    private func loadVisibleImages() {
        let indices = [currentIndex - 1, currentIndex, currentIndex + 1]
        for idx in indices {
            guard idx >= 0 && idx < imageUrls.count else { continue }
            if let zoomView = scrollView.viewWithTag(1000 + idx) as? ZoomableImageItemView {
                if !zoomView.isLoaded {
                    zoomView.loadImage(from: imageUrls[idx])
                }
            }
        }
    }
    
    private func updateCounterAndSelection() {
        if languageCode.hasPrefix("ko") {
            counterLabel.text = "\(imageUrls.count)장 중 \(currentIndex + 1)번"
        } else if languageCode.hasPrefix("ja") {
            counterLabel.text = "\(imageUrls.count)枚中 \(currentIndex + 1)枚目"
        } else if languageCode.hasPrefix("zh") {
            counterLabel.text = "共 \(imageUrls.count) 张，第 \(currentIndex + 1) 张"
        } else {
            counterLabel.text = "\(currentIndex + 1) of \(imageUrls.count)"
        }
        collectionView.reloadData()
        
        let indexPath = IndexPath(item: currentIndex, section: 0)
        if currentIndex < imageUrls.count {
            collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: true)
        }
        
        loadVisibleImages()
    }
    
    @objc private func handleClose() {
        dismiss(animated: true, completion: nil)
    }

    // MARK: - Pull to Dismiss
    private var dismissPanGesture: UIPanGestureRecognizer!
    
    private func setupDismissPanGesture() {
        dismissPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan(_:)))
        dismissPanGesture.delegate = self
        view.addGestureRecognizer(dismissPanGesture)
    }

    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        // 현재 보이는 줌 뷰의 확대 상태 체크 (확대 중이면 무시)
        let visibleZoomView = scrollView.subviews.compactMap { $0 as? ZoomableImageItemView }.first { 
            $0.frame.origin.x == scrollView.contentOffset.x 
        }
        if let zoomView = visibleZoomView, zoomView.zoomScale > 1.0 {
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

            // 바 UI들은 빠르게 투명해짐
            let barAlpha = max(0.0, 1.0 - (translation.y / (view.bounds.height * 0.3)))
            topBar.alpha = barAlpha
            bottomContainer.alpha = barAlpha

        case .ended, .cancelled:
            let shouldDismiss = translation.y > 150 || velocity.y > 500
            if shouldDismiss {
                if self.transitioningDelegate != nil {
                    // 줌 트랜지션이 설정된 경우 애니메이터가 원래 위치로 돌려보내도록 위임
                    self.dismiss(animated: true, completion: nil)
                } else {
                    UIView.animate(withDuration: 0.25, animations: {
                        self.view.transform = CGAffineTransform(translationX: translation.x, y: self.view.bounds.height)
                        self.view.alpha = 0.0
                        self.view.layer.cornerRadius = 0
                    }) { _ in
                        self.dismiss(animated: false)
                    }
                }
            } else {
                UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0, options: .curveEaseOut) {
                    self.view.transform = .identity
                    self.view.alpha = 1.0
                    self.view.layer.cornerRadius = 0
                    self.topBar.alpha = 1.0
                    self.bottomContainer.alpha = 1.0
                }
            }
        default:
            break
        }
    }
}

extension RemoteImageViewerViewController: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == dismissPanGesture {
            let pan = gestureRecognizer as! UIPanGestureRecognizer
            let velocity = pan.velocity(in: view)
            
            // 수직 방향 드래그만 허용
            if velocity.y > 0 && abs(velocity.y) > abs(velocity.x) {
                let visibleZoomView = scrollView.subviews.compactMap { $0 as? ZoomableImageItemView }.first { 
                    $0.frame.origin.x == scrollView.contentOffset.x 
                }
                if let zoomView = visibleZoomView, zoomView.zoomScale > 1.0 {
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

extension RemoteImageViewerViewController: UIScrollViewDelegate {
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if scrollView == self.scrollView {
            let page = Int(scrollView.contentOffset.x / scrollView.bounds.width)
            if page != currentIndex {
                currentIndex = page
                onPageChanged?(currentIndex)
                updateCounterAndSelection()
                
                // Reset zoom for all other pages
                for subview in scrollView.subviews {
                    if let zoomView = subview as? ZoomableImageItemView, zoomView.frame.origin.x != scrollView.contentOffset.x {
                        zoomView.resetZoom()
                    }
                }
            }
        }
    }
}

extension RemoteImageViewerViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return imageUrls.count
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ThumbnailCell", for: indexPath) as! ThumbnailCell
        cell.loadImage(from: imageUrls[indexPath.item])
        cell.setHighlight(indexPath.item == currentIndex, color: themeColor)
        return cell
    }
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if currentIndex != indexPath.item {
            currentIndex = indexPath.item
            onPageChanged?(currentIndex)
            let offsetX = CGFloat(currentIndex) * scrollView.bounds.width
            scrollView.setContentOffset(CGPoint(x: offsetX, y: 0), animated: true)
            updateCounterAndSelection()
            
            for subview in scrollView.subviews {
                if let zoomView = subview as? ZoomableImageItemView, zoomView.frame.origin.x != offsetX {
                    zoomView.resetZoom()
                }
            }
        }
    }
}

class ThumbnailCell: UICollectionViewCell {
    private let imageView = UIImageView()
    private let highlightBorder = UIView()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 4
        // 다크 모드일 때 기존 .darkGray 보다 더 어두운 회색(0.15) -> 한층 더 어두운 0.08 로 변경
        // 라이트 모드일 때 기존 .lightGray 보다 더 밝은 회색(0.9)으로 변경
        imageView.backgroundColor = UIColor { t in t.userInterfaceStyle == .dark ? UIColor(white: 0.08, alpha: 1.0) : UIColor(white: 0.9, alpha: 1.0) }
        contentView.addSubview(imageView)
        
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        activityIndicator.color = UIColor { t in t.userInterfaceStyle == .dark ? .lightGray : .gray }
        contentView.addSubview(activityIndicator)
        
        highlightBorder.translatesAutoresizingMaskIntoConstraints = false
        highlightBorder.layer.borderWidth = 2
        highlightBorder.layer.borderColor = UIColor(red: 16/255.0, green: 185/255.0, blue: 129/255.0, alpha: 1.0).cgColor
        highlightBorder.layer.cornerRadius = 6
        highlightBorder.isHidden = true
        contentView.addSubview(highlightBorder)
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            
            activityIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            highlightBorder.topAnchor.constraint(equalTo: contentView.topAnchor),
            highlightBorder.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            highlightBorder.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            highlightBorder.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func loadImage(from urlString: String) {
        imageView.image = nil
        
        if let cachedImage = ViewerImageCache.shared.getMemoryImage(for: urlString) {
            self.imageView.image = cachedImage
            self.activityIndicator.stopAnimating()
            return
        }
        
        activityIndicator.startAnimating()
        
        if urlString.hasPrefix("ph://") {
            let localIdentifier = urlString.replacingOccurrences(of: "ph://", with: "")
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let asset = fetchResult.firstObject else { 
                activityIndicator.stopAnimating()
                return 
            }
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 100, height: 130),
                contentMode: .aspectFill,
                options: options
            ) { [weak self] image, _ in
                guard let image = image else {
                    DispatchQueue.main.async { self?.activityIndicator.stopAnimating() }
                    return 
                }
                ViewerImageCache.shared.saveImage(image, for: urlString)
                DispatchQueue.main.async { 
                    self?.imageView.image = image
                    self?.activityIndicator.stopAnimating()
                }
            }
        } else if urlString.hasPrefix("file://") {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                if let url = URL(string: urlString), let image = UIImage(contentsOfFile: url.path) {
                    ViewerImageCache.shared.saveImage(image, for: urlString)
                    DispatchQueue.main.async { 
                        self?.imageView.image = image
                        self?.activityIndicator.stopAnimating()
                    }
                } else {
                    DispatchQueue.main.async { self?.activityIndicator.stopAnimating() }
                }
            }
        } else {
            ViewerImageDownloader.shared.downloadImage(from: urlString) { [weak self] image in
                guard let image = image else {
                    self?.activityIndicator.stopAnimating()
                    return
                }
                self?.imageView.image = image
                self?.activityIndicator.stopAnimating()
            }
        }
    }
    
    func setHighlight(_ isHighlighted: Bool, color: UIColor = UIColor(red: 16/255.0, green: 185/255.0, blue: 129/255.0, alpha: 1.0)) {
        highlightBorder.isHidden = !isHighlighted
        highlightBorder.layer.borderColor = color.cgColor
    }
}

class ZoomableImageItemView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private var imageSize: CGSize = .zero
    var isLoaded = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        delegate = self
        minimumZoomScale = 1.0
        maximumZoomScale = 4.0
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        if #available(iOS 11.0, *) {
            contentInsetAdjustmentBehavior = .never
        }
        
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)
        
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        // 인디케이터도 다크모드일 때 너무 튀지 않게 .lightGray나 어두운 색상으로 변경 -> 더 어두운 .darkGray로 변경
        // 라이트 모드일 때는 더 밝게 처리
        activityIndicator.color = UIColor { t in t.userInterfaceStyle == .dark ? .darkGray : UIColor(white: 0.8, alpha: 1.0) }
        activityIndicator.hidesWhenStopped = true
        addSubview(activityIndicator)
        
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        centerImage()
    }
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    public func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }
    
    private func centerImage() {
        let boundsSize = bounds.size
        var frameToCenter = imageView.frame
        
        if frameToCenter.size.width < boundsSize.width {
            frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2
        } else {
            frameToCenter.origin.x = 0
        }
        
        if frameToCenter.size.height < boundsSize.height {
            frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2
        } else {
            frameToCenter.origin.y = 0
        }
        
        imageView.frame = frameToCenter
    }
    
    func resetZoom() {
        setZoomScale(1.0, animated: false)
    }
    
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1.0 {
            setZoomScale(1.0, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let size = CGSize(width: bounds.width / 2.0, height: bounds.height / 2.0)
            let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
            zoom(to: CGRect(origin: origin, size: size), animated: true)
        }
    }
    
    func loadImage(from urlString: String) {
        if isLoaded { return }
        isLoaded = true
        
        if let cachedImage = ViewerImageCache.shared.getMemoryImage(for: urlString) {
            self.setImage(cachedImage)
            return
        }
        
        activityIndicator.startAnimating()
        
        if urlString.hasPrefix("ph://") {
            // Photos Library asset
            let localIdentifier = urlString.replacingOccurrences(of: "ph://", with: "")
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
            guard let asset = fetchResult.firstObject else {
                DispatchQueue.main.async { self.activityIndicator.stopAnimating() }
                return
            }
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 2500, height: 2500),
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, _ in
                guard let image = image else {
                    DispatchQueue.main.async { self?.activityIndicator.stopAnimating() }
                    return
                }
                ViewerImageCache.shared.saveImage(image, for: urlString)
                DispatchQueue.main.async {
                    self?.setImage(image)
                    self?.activityIndicator.stopAnimating()
                }
            }
        } else if urlString.hasPrefix("file://") {
            // Local file
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                if let url = URL(string: urlString), let image = UIImage(contentsOfFile: url.path) {
                    ViewerImageCache.shared.saveImage(image, for: urlString)
                    DispatchQueue.main.async {
                        self?.setImage(image)
                        self?.activityIndicator.stopAnimating()
                    }
                } else {
                    DispatchQueue.main.async { self?.activityIndicator.stopAnimating() }
                }
            }
        } else {
            // Remote URL
            ViewerImageDownloader.shared.downloadImage(from: urlString) { [weak self] image in
                if let image = image {
                    self?.setImage(image)
                }
                self?.activityIndicator.stopAnimating()
            }
        }
    }
    
    private func setImage(_ image: UIImage) {
        imageView.image = image
        imageSize = image.size
        configureForImageSize()
    }
    
    private func blurImage(_ image: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        
        // Use a strong blur by combining downscaling and gaussian blur
        let scaleFilter = CIFilter(name: "CILanczosScaleTransform")!
        scaleFilter.setValue(ciImage, forKey: kCIInputImageKey)
        scaleFilter.setValue(0.1, forKey: kCIInputScaleKey)
        
        guard let scaledImage = scaleFilter.outputImage else { return nil }
        
        let blurFilter = CIFilter(name: "CIGaussianBlur")!
        blurFilter.setValue(scaledImage, forKey: kCIInputImageKey)
        blurFilter.setValue(5.0, forKey: kCIInputRadiusKey)
        
        guard let blurredScaledImage = blurFilter.outputImage else { return nil }
        
        let upScaleFilter = CIFilter(name: "CILanczosScaleTransform")!
        upScaleFilter.setValue(blurredScaledImage, forKey: kCIInputImageKey)
        upScaleFilter.setValue(10.0, forKey: kCIInputScaleKey)
        
        guard let output = upScaleFilter.outputImage else { return nil }
        let context = FilterManager.shared.context
        guard let cgImage = context.createCGImage(output, from: ciImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
    
    private func addTextToImage(_ image: UIImage, text: String) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let fontSize = min(image.size.width, image.size.height) / 20.0
            
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black
            shadow.shadowOffset = CGSize(width: 2, height: 2)
            shadow.shadowBlurRadius = 5
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: fontSize),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle,
                .shadow: shadow
            ]
            
            let padding: CGFloat = image.size.width * 0.1
            let textRect = CGRect(x: padding, y: 0, width: image.size.width - padding * 2, height: image.size.height)
            
            // Calculate actual height needed for text
            let attributedText = NSAttributedString(string: text, attributes: attributes)
            let boundingBox = attributedText.boundingRect(with: CGSize(width: textRect.width, height: .greatestFiniteMagnitude), options: .usesLineFragmentOrigin, context: nil)
            
            let centeredRect = CGRect(
                x: padding,
                y: (image.size.height - boundingBox.height) / 2.0,
                width: textRect.width,
                height: boundingBox.height
            )
            
            attributedText.draw(in: centeredRect)
        }
    }
    
    private func configureForImageSize() {
        guard imageSize != .zero else { return }
        
        let boundsSize = bounds.size
        
        let widthScale = boundsSize.width / imageSize.width
        let heightScale = boundsSize.height / imageSize.height
        let minScale = min(widthScale, heightScale)
        let maxScale = max(widthScale, heightScale)
        
        minimumZoomScale = 1.0
        maximumZoomScale = max(5.0, (maxScale / minScale) * 2.0)
        zoomScale = 1.0
        
        imageView.frame = CGRect(x: 0, y: 0, width: imageSize.width * minScale, height: imageSize.height * minScale)
        contentSize = imageView.frame.size
        centerImage()
    }
}
