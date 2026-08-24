//
//  TurboImageCache.swift
//  ImageGalleryTest
//
//  메모리 캐시 관리 - NSCache 기반 이미지 캐싱
//  메모리 경고 시 자동 정리
//  
//  참고: PHCachingImageManager가 자체적으로 캐싱하므로
//  추가 메모리 캐시는 선택적으로 사용
//

import UIKit

class TurboImageCache {
    
    static let shared = TurboImageCache()
    
    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100  // 200 -> 100으로 축소 (메모리 절약)
        cache.totalCostLimit = 100 * 1024 * 1024  // 100MB로 축소
        return cache
    }()
    
    private init() {
        // 메모리 경고 시 캐시 정리
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearCache),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Cache Operations
    
    func image(for key: String) -> UIImage? {
        return cache.object(forKey: key as NSString)
    }
    
    func setImage(_ image: UIImage, for key: String) {
        // PHCachingImageManager가 이미 캐싱하므로 선택적 사용
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
    
    func removeImage(for key: String) {
        cache.removeObject(forKey: key as NSString)
    }
    
    @objc func clearCache() {
        cache.removeAllObjects()
        print("🗑️ Image cache cleared")
    }
}
