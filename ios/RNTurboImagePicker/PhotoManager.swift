//
//  PhotoManager.swift
//  ImageGalleryTest
//
//  텔레그램급 성능을 위한 최적화된 사진 관리자
//  - 배치 로딩: 초기 화면만 먼저 로딩
//  - 점진적 로딩: 백그라운드에서 나머지 로딩
//  - 앨범 그룹 선택 지원
//

import Photos
import UIKit

// MARK: - Album Model

public struct Album {
    public let collection: PHAssetCollection
    public let title: String
    public let count: Int
    
    public var identifier: String {
        return collection.localIdentifier
    }
    
    public var isRecents: Bool {
        return collection.assetCollectionSubtype == .smartAlbumUserLibrary
    }
}

public class PhotoManager {
    public var languageCode: String = "en"

    public static let shared = PhotoManager()
    
    private var cachingImageManager: PHCachingImageManager
    private let fetchQueue = DispatchQueue(label: "com.kora.photoFetch", qos: .userInitiated)
    
    // 성능 최적화: 배치 크기
    private let initialBatchSize = 30  // 첫 화면 (3열 x 10행)
    private let subsequentBatchSize = 100  // 이후 배치
    
    private init() {
        cachingImageManager = PHCachingImageManager()
        
        // 🚀 성능 최적화: 고품질 캐싱 + 동시 요청 수 증가
        cachingImageManager.allowsCachingHighQualityImages = true
        
        // 더 많은 동시 이미지 요청 허용 (기본값보다 증가)
        if #available(iOS 13.0, *) {
            cachingImageManager.allowsCachingHighQualityImages = true
        }
    }
    
    // 🧹 캐싱 매니저를 완전히 재생성하여 모든 캐시 강제 정리
    public func resetCachingManager() {
        cachingImageManager.stopCachingImagesForAllAssets()
        cachingImageManager = PHCachingImageManager()
        cachingImageManager.allowsCachingHighQualityImages = true
        debugPrint("🧹 PHCachingImageManager 재생성 완료")
    }
    
    // MARK: - 앨범 가져오기
    
    /// 모든 앨범 (스마트 앨범 + 사용자 앨범) 가져오기
    public func fetchAlbums(completion: @escaping ([Album]) -> Void) {
        fetchQueue.async {
            var smartAlbums: [Album] = []
            var userAlbums: [Album] = []
            
            // 1. 스마트 앨범 (Recents, Favorites, Screenshots 등)
            let smartCollections = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: .any,
                options: nil
            )
            
            smartCollections.enumerateObjects { collection, _, _ in
                let fetchOptions = PHFetchOptions()
                fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
                let count = PHAsset.fetchAssets(in: collection, options: fetchOptions).count
                
                // 사진이 있는 앨범만 추가 (단, "최근 항목"은 항상 포함)
                let isRecents = collection.assetCollectionSubtype == .smartAlbumUserLibrary
                if count > 0 || isRecents {
                    let title = self.localizedAlbumTitle(collection)
                    let album = Album(collection: collection, title: title, count: count)
                    smartAlbums.append(album)
                }
            }
            
            // 2. 사용자가 만든 앨범
            let userCollections = PHAssetCollection.fetchAssetCollections(
                with: .album,
                subtype: .albumRegular,
                options: nil
            )
            
            userCollections.enumerateObjects { collection, _, _ in
                let fetchOptions = PHFetchOptions()
                fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
                let count = PHAsset.fetchAssets(in: collection, options: fetchOptions).count
                
                if count > 0 {
                    userAlbums.append(Album(
                        collection: collection,
                        title: collection.localizedTitle ?? Localizer.getString(key: "album_default", languageCode: self.languageCode),
                        count: count
                    ))
                }
            }
            
            // 3. 스마트 앨범을 올바른 순서로 정렬
            let sortedSmartAlbums = self.sortSmartAlbums(smartAlbums)
            
            // 4. 사용자 앨범을 이름순으로 정렬
            userAlbums.sort { $0.title < $1.title }
            
            // 5. 최종 앨범 리스트: 스마트 앨범 + 사용자 앨범
            let finalAlbums = sortedSmartAlbums + userAlbums
            
            DispatchQueue.main.async {
                completion(finalAlbums)
            }
        }
    }
    
    /// 스마트 앨범을 올바른 순서로 정렬
    private func sortSmartAlbums(_ albums: [Album]) -> [Album] {
        // 이미지에서 보신 순서대로 (비디오 제외)
        let desiredOrder: [PHAssetCollectionSubtype] = [
            .smartAlbumUserLibrary,      // 최근 항목
            .smartAlbumFavorites,        // 즐겨찾기
            .smartAlbumRecentlyAdded,     // 최근 추가됨
            .smartAlbumSelfPortraits,    // 셀피
            .smartAlbumDepthEffect,       // 인물 사진 (Depth Effect)
            .smartAlbumPanoramas,        // 파노라마
            .smartAlbumTimelapses,       // 타임랩스
            .smartAlbumSlomoVideos,      // 슬로모션 (비디오는 제외)
            .smartAlbumScreenshots,      // 스크린샷
            .smartAlbumBursts,           // 연사
            .smartAlbumLivePhotos        // Live Photo
        ]
        
        // 비디오 앨범 제외
        let filteredAlbums = albums.filter { album in
            album.collection.assetCollectionSubtype != .smartAlbumVideos
        }
        
        var sortedAlbums: [Album] = []
        
        // 원하는 순서대로 앨범 추가
        for subtype in desiredOrder {
            if let album = filteredAlbums.first(where: { $0.collection.assetCollectionSubtype == subtype }) {
                sortedAlbums.append(album)
            }
        }
        
        return sortedAlbums
    }
    
    /// 앨범 이름 로컬라이징
    private func localizedAlbumTitle(_ collection: PHAssetCollection) -> String {
        switch collection.assetCollectionSubtype {
        case .smartAlbumUserLibrary:
            return Localizer.getString(key: "album_recents", languageCode: languageCode)
        case .smartAlbumFavorites:
            return Localizer.getString(key: "album_favorites", languageCode: languageCode)
        case .smartAlbumSelfPortraits:
            return Localizer.getString(key: "album_selfies", languageCode: languageCode)
        case .smartAlbumLivePhotos:
            return Localizer.getString(key: "album_live_photos", languageCode: languageCode)
        case .smartAlbumPanoramas:
            return Localizer.getString(key: "album_panoramas", languageCode: languageCode)
        case .smartAlbumTimelapses:
            return Localizer.getString(key: "album_timelapses", languageCode: languageCode)
        case .smartAlbumSlomoVideos:
            return Localizer.getString(key: "album_slow_mo", languageCode: languageCode)
        case .smartAlbumVideos:
            return Localizer.getString(key: "album_videos", languageCode: languageCode)
        case .smartAlbumScreenshots:
            return Localizer.getString(key: "album_screenshots", languageCode: languageCode)
        case .smartAlbumRecentlyAdded:
            return Localizer.getString(key: "album_recently_added", languageCode: languageCode)
        case .smartAlbumBursts:
            return Localizer.getString(key: "album_bursts", languageCode: languageCode)
        case .smartAlbumDepthEffect:
            return Localizer.getString(key: "album_portrait", languageCode: languageCode)
        default:
            return collection.localizedTitle ?? Localizer.getString(key: "album_default", languageCode: languageCode)
        }
    }
    
    // MARK: - 앨범별 사진 가져오기
    
    /// 특정 앨범의 초기 사진만 가져오기
    public func fetchInitialPhotos(
        from album: Album? = nil,
        completion: @escaping ([PHAsset]) -> Void
    ) {
        // 🚀 성능 최적화: 고우선순위 큐에서 즉시 실행
        DispatchQueue.global(qos: .userInteractive).async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [
                NSSortDescriptor(key: "creationDate", ascending: false)
            ]
            fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
            fetchOptions.fetchLimit = self.initialBatchSize
            
            let result: PHFetchResult<PHAsset>
            if let album = album {
                result = PHAsset.fetchAssets(in: album.collection, options: fetchOptions)
            } else {
                result = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            }
            
            var assets: [PHAsset] = []
            // 🚀 성능 최적화: 배열 미리 할당
            assets.reserveCapacity(result.count)
            
            result.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }
            
            DispatchQueue.main.async {
                completion(assets)
            }
        }
    }
    
    /// 특정 앨범의 모든 사진 메타데이터 가져오기
    public func fetchAllPhotosMetadata(
        from album: Album? = nil,
        skip: Int = 0,
        completion: @escaping ([PHAsset]) -> Void
    ) {
        fetchQueue.async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [
                NSSortDescriptor(key: "creationDate", ascending: false)
            ]
            fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
            
            let result: PHFetchResult<PHAsset>
            if let album = album {
                result = PHAsset.fetchAssets(in: album.collection, options: fetchOptions)
            } else {
                result = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            }
            
            var assets: [PHAsset] = []
            let startIndex = skip
            let endIndex = result.count
            
            // 메타데이터만 가져옴 (매우 빠름)
            for index in startIndex..<endIndex {
                let asset = result.object(at: index)
                assets.append(asset)
            }
            
            DispatchQueue.main.async {
                completion(assets)
            }
        }
    }
    
    // MARK: - 배치 로딩 (Phase 1: 초기 로딩) - 하위 호환성
    
    /// 초기 화면에 필요한 최소한의 사진만 빠르게 로딩
    public func fetchInitialPhotos(completion: @escaping ([PHAsset]) -> Void) {
        fetchInitialPhotos(from: nil, completion: completion)
    }
    
    // MARK: - 전체 사진 메타데이터만 가져오기 (Phase 2: 백그라운드) - 하위 호환성
    
    /// 백그라운드에서 모든 사진의 메타데이터만 로딩 (이미지는 로딩하지 않음)
    public func fetchAllPhotosMetadata(
        skip: Int = 0,
        completion: @escaping ([PHAsset]) -> Void
    ) {
        fetchAllPhotosMetadata(from: nil, skip: skip, completion: completion)
    }
    
    // MARK: - 구버전 호환 (기존 코드용)
    
    public func fetchAllPhotos(completion: @escaping ([PHAsset]) -> Void) {
        fetchAllPhotosMetadata(skip: 0, completion: completion)
    }
    
    // MARK: - 썸네일 로딩 (품질 개선)
    
    /// 품질과 속도의 균형을 맞춘 썸네일 로딩
    public func requestThumbnail(
        for asset: PHAsset,
        targetSize: CGSize,
        completion: @escaping (UIImage?) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        
        // 🎨 품질 개선: opportunistic 모드 사용
        // - 캐시된 이미지가 있으면 즉시 반환 (빠름)
        // - 없으면 고품질 이미지 생성 (품질 좋음)
        options.deliveryMode = .opportunistic
        
        // 정확한 리사이징 (품질 향상)
        options.resizeMode = .exact
        
        // 동기 처리 비활성화
        options.isSynchronous = false
        
        // iCloud 다운로드는 여전히 비활성화 (속도 유지)
        options.isNetworkAccessAllowed = false
        
        return cachingImageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image)
        }
    }
    
    // MARK: - 고해상도 이미지 로딩 (이미지 뷰어용)
    
    /// 이미지 뷰어용 고해상도 이미지 로딩
    public func requestFullImage(
        for asset: PHAsset,
        targetSize: CGSize,
        progressHandler: ((Double) -> Void)? = nil,
        completion: @escaping (UIImage?) -> Void
    ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true
        
        // 진행률 핸들러
        options.progressHandler = { progress, _, _, _ in
            DispatchQueue.main.async {
                progressHandler?(progress)
            }
        }
        
        return cachingImageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }
    
    // MARK: - Preheating (미리 캐싱)
    
    public func startCachingImages(for assets: [PHAsset], targetSize: CGSize) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic  // 품질 향상
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = false
        
        cachingImageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        )
    }
    
    public func stopCachingImages(for assets: [PHAsset], targetSize: CGSize) {
        cachingImageManager.stopCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: nil
        )
    }
    
    public func stopCachingAllImages() {
        cachingImageManager.stopCachingImagesForAllAssets()
    }
}
