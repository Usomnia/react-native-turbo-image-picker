import UIKit

class GoogleEmojiImageView: UIImageView {
    
    private static let imageCache = NSCache<NSString, UIImage>()
    private var currentTask: URLSessionDataTask?
    
    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.color = UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor.darkGray
            } else {
                return UIColor.lightGray
            }
        }
        return indicator
    }()
    
    convenience init() {
        self.init(frame: .zero)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupIndicator()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupIndicator()
    }
    
    private func setupIndicator() {
        addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    var emoji: String? {
        didSet {
            loadEmoji()
        }
    }
    
    private func getEmojiUrlString(for emoji: String) -> String? {
        let hexString = emoji.unicodeScalars
            .map { String($0.value, radix: 16) }
            .joined(separator: "_")
        return "https://fonts.gstatic.com/s/e/notoemoji/latest/\(hexString)/512.png"
    }
    
    private func loadEmoji() {
        // 취소 처리
        currentTask?.cancel()
        self.image = nil
        activityIndicator.startAnimating()
        
        guard let emoji = emoji, let urlString = getEmojiUrlString(for: emoji), let url = URL(string: urlString) else {
            activityIndicator.stopAnimating()
            return
        }
        
        // 캐시 확인
        if let cachedImage = GoogleEmojiImageView.imageCache.object(forKey: urlString as NSString) {
            self.image = cachedImage
            activityIndicator.stopAnimating()
            return
        }
        
        // 다운로드
        currentTask = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            guard let data = data, let downloadedImage = UIImage(data: data) else {
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                }
                return
            }
            
            // 캐시 저장
            GoogleEmojiImageView.imageCache.setObject(downloadedImage, forKey: urlString as NSString)
            
            // UI 업데이트
            DispatchQueue.main.async {
                self.image = downloadedImage
                self.activityIndicator.stopAnimating()
            }
        }
        currentTask?.resume()
    }
}
