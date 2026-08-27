//
//  RNTurboImagePicker.swift
//  RNTurboImagePicker
//
//  Supports both Turbo Module (New Architecture) and Legacy Native Module
//

import UIKit
import Photos
import ImageIO
import RNTurboImagePicker

#if RCT_NEW_ARCH_ENABLED
import React
#else
import React
#endif

#if canImport(SDWebImageWebPCoder)
import SDWebImageWebPCoder
#endif

@objc(RNTurboImagePicker)
class RNTurboImagePicker: RCTEventEmitter {
    
    public static var shared: RNTurboImagePicker?
    
    private var zoomAnimator = ZoomTransitionAnimator()
    private weak var activeViewerVC: RemoteImageViewerViewController?
    
    override init() {
        super.init()
        RNTurboImagePicker.shared = self
    }
    
    // 현재 표시 중인 갤러리 참조
    private weak var currentGalleryVC: GalleryViewController?
    private var editorTransitionDelegate: ImageEditorTransitionDelegate?
    
    // MARK: - Module Setup
    
    @objc
    override static func moduleName() -> String! {
        return "RNTurboImagePicker"
    }
    
    @objc
    override static func requiresMainQueueSetup() -> Bool {
        return true
    }
    
    @objc
    override func supportedEvents() -> [String]! {
        return ["onSelectionChange", "onImageProcessed", "onPageSelected"]
    }
    
    // MARK: - Public Methods
    
    @objc
    func `init`(_ licenseKey: String,
                resolve: @escaping RCTPromiseResolveBlock,
                reject: @escaping RCTPromiseRejectBlock) -> Void {
        let result = LicenseManager.shared.initialize(with: licenseKey)
        resolve(result)
    }
    
    // MARK: - Public Methods
    
    @objc
    func updateSourceRect(_ options: NSDictionary,
                          resolve: @escaping RCTPromiseResolveBlock,
                          reject: @escaping RCTPromiseRejectBlock) -> Void {
        let optDict = options as? [String: Any] ?? [:]
        let x = (optDict["x"] as? NSNumber).map { CGFloat(truncating: $0) } ?? (optDict["x"] as? Double).map { CGFloat($0) }
        let y = (optDict["y"] as? NSNumber).map { CGFloat(truncating: $0) } ?? (optDict["y"] as? Double).map { CGFloat($0) }
        let w = (optDict["width"] as? NSNumber).map { CGFloat(truncating: $0) } ?? (optDict["width"] as? Double).map { CGFloat($0) }
        let h = (optDict["height"] as? NSNumber).map { CGFloat(truncating: $0) } ?? (optDict["height"] as? Double).map { CGFloat($0) }
        
        if let x = x, let y = y, let w = w, let h = h {
            DispatchQueue.main.async {
                self.zoomAnimator.sourceRect = CGRect(x: x, y: y, width: w, height: h)
                resolve(true)
            }
        } else {
            reject("ERROR", "Invalid coordinates", nil)
        }
    }
    
    @objc
    func openViewer(_ options: NSDictionary,
                    resolve: @escaping RCTPromiseResolveBlock,
                    reject: @escaping RCTPromiseRejectBlock) -> Void {
        guard let images = options["images"] as? [String] else {
            reject("ERROR", "images array is required", nil)
            return
        }
        
        let initialIndex = options["initialIndex"] as? Int ?? 0
        let placeholderImages = options["placeholderImages"] as? [String]
        let themeColorHex = options["themeColor"] as? String
        let languageCode = options["languageCode"] as? String ?? "en"
        let viewerTitle = options["title"] as? String
        let animationType = options["animationType"] as? String ?? (options["sourceRect"] != nil ? "zoom" : "slide")
        let closeAnimationType = options["closeAnimationType"] as? String
        
        var parsedRect: CGRect?
        if let sourceRectDict = options["sourceRect"] as? NSDictionary {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var w: CGFloat = 0
            var h: CGFloat = 0
            if let xNum = sourceRectDict["x"] as? NSNumber { x = CGFloat(truncating: xNum) } else if let xDbl = sourceRectDict["x"] as? Double { x = CGFloat(xDbl) }
            if let yNum = sourceRectDict["y"] as? NSNumber { y = CGFloat(truncating: yNum) } else if let yDbl = sourceRectDict["y"] as? Double { y = CGFloat(yDbl) }
            if let wNum = sourceRectDict["width"] as? NSNumber { w = CGFloat(truncating: wNum) } else if let wDbl = sourceRectDict["width"] as? Double { w = CGFloat(wDbl) }
            if let hNum = sourceRectDict["height"] as? NSNumber { h = CGFloat(truncating: hNum) } else if let hDbl = sourceRectDict["height"] as? Double { h = CGFloat(hDbl) }
            parsedRect = CGRect(x: x, y: y, width: w, height: h)
        }
        
        var sourceBorderRadius: CGFloat = 0
        if let radiusNum = options["sourceBorderRadius"] as? NSNumber {
            sourceBorderRadius = CGFloat(truncating: radiusNum)
        } else if let radiusDbl = options["sourceBorderRadius"] as? Double {
            sourceBorderRadius = CGFloat(radiusDbl)
        }
        
        var mask: CACornerMask = []
        if let corners = options["sourceBorderCorners"] as? [String] {
            if corners.contains("topLeft") { mask.insert(.layerMinXMinYCorner) }
            if corners.contains("topRight") { mask.insert(.layerMaxXMinYCorner) }
            if corners.contains("bottomLeft") { mask.insert(.layerMinXMaxYCorner) }
            if corners.contains("bottomRight") { mask.insert(.layerMaxXMaxYCorner) }
            if mask.isEmpty { mask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner] }
        } else {
            mask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
        
        DispatchQueue.main.async {
            guard let rootViewController = self.getRootViewController() else {
                let error = NSError(domain: "RNTurboImagePicker", code: 0, userInfo: nil)
                reject("ERROR", "Unable to get root view controller", error)
                return
            }
            
            let viewerVC = RemoteImageViewerViewController(imageUrls: images, initialIndex: initialIndex)
            viewerVC.languageCode = languageCode
            viewerVC.viewerTitle = viewerTitle
            if let hex = themeColorHex, let color = UIColor(hexString: hex) {
                viewerVC.themeColor = color
            }
            
            self.zoomAnimator.animationType = animationType
            self.zoomAnimator.closeAnimationType = closeAnimationType
            if let rect = parsedRect {
                self.zoomAnimator.sourceRect = rect
                if let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) {
                    let format = UIGraphicsImageRendererFormat()
                    format.opaque = false
                    format.scale = window.screen.scale
                    let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
                    let snapshotImage = renderer.image { context in
                        window.drawHierarchy(in: CGRect(x: -rect.origin.x, y: -rect.origin.y, width: window.bounds.width, height: window.bounds.height), afterScreenUpdates: false)
                    }
                    self.zoomAnimator.sourceImage = snapshotImage
                }
            }
            self.zoomAnimator.sourceBorderRadius = sourceBorderRadius
            self.zoomAnimator.sourceBorderCorners = mask
            
            viewerVC.modalPresentationStyle = .custom
            viewerVC.transitioningDelegate = self
            
            self.activeViewerVC = viewerVC
            viewerVC.onPageChanged = { [weak self] (index: Int) -> Void in
                guard let self = self else { return }
                let eventBody: [String: Any] = ["index": index]
                self.sendEvent(withName: "onPageSelected", body: eventBody)
            }
            
            let resolveResult: [String: Any] = ["success": true]
            
            if images.indices.contains(initialIndex) {
                let initialUrl = images[initialIndex]
                RemoteImageViewerViewController.prefetchImage(from: initialUrl) { _ in
                    DispatchQueue.main.async {
                        rootViewController.present(viewerVC, animated: true, completion: {
                            resolve(resolveResult)
                        })
                    }
                }
            } else {
                rootViewController.present(viewerVC, animated: true, completion: {
                    resolve(resolveResult)
                })
            }
        }
    }

    @objc
    func updateViewerSourceRect(_ rect: NSDictionary,
                                resolve: @escaping RCTPromiseResolveBlock,
                                reject: @escaping RCTPromiseRejectBlock) -> Void {
        DispatchQueue.main.async {
            let x = (rect["x"] as? NSNumber).map { CGFloat(truncating: $0) } ?? (rect["x"] as? Double).map { CGFloat($0) } ?? 0
            let y = (rect["y"] as? NSNumber).map { CGFloat(truncating: $0) } ?? (rect["y"] as? Double).map { CGFloat($0) } ?? 0
            let w = (rect["width"] as? NSNumber).map { CGFloat(truncating: $0) } ?? (rect["width"] as? Double).map { CGFloat($0) } ?? 0
            let h = (rect["height"] as? NSNumber).map { CGFloat(truncating: $0) } ?? (rect["height"] as? Double).map { CGFloat($0) } ?? 0
            self.zoomAnimator.sourceRect = CGRect(x: x, y: y, width: w, height: h)
            resolve(nil)
        }
    }

    @objc
    func openEditor(_ options: NSDictionary,
                    resolve: @escaping RCTPromiseResolveBlock,
                    reject: @escaping RCTPromiseRejectBlock) -> Void {
        guard let uri = options["uri"] as? String else {
            reject("ERROR", "uri is required", nil)
            return
        }
        
        var themeColor: UIColor? = nil
        if let themeColorHex = options["themeColor"] as? String {
            themeColor = UIColor(hexString: themeColorHex)
        }
        
        var parsedMaxWidth: Int? = nil
        var parsedMaxHeight: Int? = nil
        if let maxW = options["maxWidth"] as? Int { parsedMaxWidth = maxW }
        if let maxH = options["maxHeight"] as? Int { parsedMaxHeight = maxH }
        
        DispatchQueue.main.async {
            guard let rootViewController = self.getRootViewController() else {
                reject("ERROR", "Unable to get root view controller", nil)
                return
            }
            
            
            if uri.hasPrefix("ph://") {
                let localIdentifier = uri.replacingOccurrences(of: "ph://", with: "")
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
                
                guard let asset = fetchResult.firstObject else {
                    reject("ERROR", "Asset not found", nil)
                    return
                }
                
                let editorVC = ImageEditorViewController()
                editorVC.languageCode = options["languageCode"] as? String ?? "en"
                editorVC.allAssets = [asset]
                editorVC.currentIndex = 0
                editorVC.modalPresentationStyle = .fullScreen
                editorVC.singlePhotoMode = true
                if let color = themeColor {
                    editorVC.themeColor = color
                }
                
                if let editedUriStr = options["editedFileUri"] as? String,
                   let url = URL(string: editedUriStr) ?? URL(string: "file://" + editedUriStr.replacingOccurrences(of: "file://", with: "")),
                   let imgData = try? Data(contentsOf: url),
                   let img = UIImage(data: imgData) {
                    editorVC.croppedImages[0] = img
                }
                
                editorVC.onConfirm = { [weak self, weak editorVC] (editedAsset, editedImage, filterState, caption) in
                    editorVC?.dismiss(animated: true) {
                        self?.processEditorResult(asset: editedAsset, croppedImage: editedImage, filterState: filterState, caption: caption, galleryVC: nil, targetMaxWidth: parsedMaxWidth, targetMaxHeight: parsedMaxHeight, resolve: { resultArr in
                            if let arr = resultArr as? [[String: Any]], let first = arr.first {
                                resolve(first)
                            } else {
                                resolve(resultArr)
                            }
                        }, reject: reject)
                    }
                }
                
                editorVC.onCancel = { [weak editorVC] in
                    editorVC?.dismiss(animated: true) {
                        reject("CANCELLED", "User cancelled editor", nil)
                    }
                }
                
                var topController = rootViewController
                while let presented = topController.presentedViewController {
                    topController = presented
                }
                topController.present(editorVC, animated: true)
                
            } else {
                guard let url = URL(string: uri) ?? URL(string: "file://" + uri.replacingOccurrences(of: "file://", with: "")) else {
                    reject("ERROR", "Invalid URI format", nil)
                    return
                }
                
                DispatchQueue.global().async {
                    if let imgData = try? Data(contentsOf: url), let image = UIImage(data: imgData) {
                        DispatchQueue.main.async {
                            let editorVC = ImageEditorViewController()
                editorVC.languageCode = options["languageCode"] as? String ?? "en"
                            editorVC.standaloneImage = image
                            editorVC.currentIndex = 0
                            editorVC.modalPresentationStyle = .fullScreen
                            editorVC.singlePhotoMode = true
                            if let color = themeColor {
                                editorVC.themeColor = color
                            }
                            
                            editorVC.onConfirm = { [weak self, weak editorVC] (editedAsset, editedImage, filterState, caption) in
                                editorVC?.dismiss(animated: true) {
                                    self?.processEditorResult(asset: editedAsset, croppedImage: editedImage, filterState: filterState, caption: caption, galleryVC: nil, targetMaxWidth: parsedMaxWidth, targetMaxHeight: parsedMaxHeight, resolve: { resultArr in
                                        var resultDict = (resultArr as? [[String: Any]])?.first ?? (resultArr as? [String: Any]) ?? [:]
                                        // For remote URLs, we preserve originalUri if editedFileUri isn't provided
                                        let originalRemoteUrl = (options["editedFileUri"] as? String) ?? uri
                                        resultDict["originalUri"] = originalRemoteUrl
                                        resolve(resultDict)
                                    }, reject: reject)
                                }
                            }
                            
                            editorVC.onCancel = { [weak editorVC] in
                                editorVC?.dismiss(animated: true) {
                                    reject("CANCELLED", "User cancelled editor", nil)
                                }
                            }
                            
                            var topController = rootViewController
                            while let presented = topController.presentedViewController {
                                topController = presented
                            }
                            topController.present(editorVC, animated: true)
                        }
                    } else {
                        DispatchQueue.main.async {
                            reject("ERROR", "Failed to load image from URI", nil)
                        }
                    }
                }
            }

        }
    }

    @objc
    func openGallery(_ options: NSDictionary,
                     resolve: @escaping RCTPromiseResolveBlock,
                     reject: @escaping RCTPromiseRejectBlock) -> Void {
        let startTime = CFAbsoluteTimeGetCurrent()
        print("✅ [DEBUG] received options: \(options)")
        print("🔵 [DEBUG] openGallery 시작 - 시간: \(startTime)")
        
        // Main thread에서 실행
        DispatchQueue.main.async { [weak self] () -> Void in
            guard let self = self else {
                reject("ERROR", "Module deallocated", nil)
                return
            }
            
            print("🔵 [DEBUG] workItem 실행 시작 - 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime))초")
            
            let step1 = CFAbsoluteTimeGetCurrent()
            guard let rootViewController = self.getRootViewController() else {
                print("❌ [DEBUG] getRootViewController 실패")
                reject("ERROR", "Unable to get root view controller", nil)
                return
            }
            print("🔵 [DEBUG] getRootViewController 완료 - 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - step1))초")
            
            let step2 = CFAbsoluteTimeGetCurrent()
            print("🔵 [DEBUG] GalleryViewController 생성 시작...")
            let galleryVC = GalleryViewController()
            print("🔵 [DEBUG] GalleryViewController 생성 완료 - 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - step2))초")
            
            // 현재 갤러리 참조 저장
            self.currentGalleryVC = galleryVC
            
            // 선택 변경 이벤트 콜백 설정
            galleryVC.onSelectionChanged = { [weak self] selectedCount, maxSelection in
                self?.sendEvent(withName: "onSelectionChange", body: [
                    "selectedCount": selectedCount,
                    "maxSelection": maxSelection
                ])
            }
            
            // maxSelection 설정 (autoCloseOnSelect가 true면 0으로 설정하여 단일 선택 자동 닫기 처리)
            let autoCloseOnSelect = options["autoCloseOnSelect"] as? Bool ?? false
            if autoCloseOnSelect {
                galleryVC.maxSelection = 0
            } else if let maxSelection = options["maxSelection"] as? Int {
                galleryVC.maxSelection = maxSelection
            }
            
            // maxWidth, maxHeight 옵션 (미설정 또는 0이면 원본 크기 유지)
            galleryVC.maxWidth = (options["maxWidth"] as? Int) ?? 0
            galleryVC.maxHeight = (options["maxHeight"] as? Int) ?? 0

            // outputFormat: "webp" | "jpg" | "png" (기본값: "webp")
            let fmt = (options["outputFormat"] as? String)?.lowercased() ?? "webp"
            galleryVC.outputFormat = ["webp", "jpg", "png"].contains(fmt) ? fmt : "webp"
            
            if let themeColorHex = options["themeColor"] as? String {
                galleryVC.themeColorHex = themeColorHex
            }
            
            // 언어 코드 설정 (기본값: "en") - 이것이 먼저 설정되어 텍스트 자동 적용
            galleryVC.languageCode = options["languageCode"] as? String ?? "en" 
            
            // 개별 텍스트 커스터마이징 (옵션, languageCode 오버라이드)
            if let allText = options["allItemsText"] as? String {
                galleryVC.allItemsText = allText
            }
            if let selectedText = options["selectedItemsText"] as? String {
                galleryVC.selectedItemsText = selectedText
            }
            if let doneText = options["doneButtonText"] as? String {
                galleryVC.doneButtonText = doneText
            }
            if let recentsText = options["recentsAlbumText"] as? String {
                galleryVC.recentsAlbumText = recentsText
            }
            
            let enableEditor = options["enableEditor"] as? Bool ?? false
            galleryVC.profileMode = options["profileMode"] as? Bool ?? false
            
            if galleryVC.profileMode {
                galleryVC.allowsEditing = enableEditor
                galleryVC.onProfileCropComplete = { [weak self, weak galleryVC] asset, croppedImage in
                    guard let self = self, let currentGallery = galleryVC else { return }
                    
                    if enableEditor {
                        let editorVC = ImageEditorViewController()
                editorVC.languageCode = options["languageCode"] as? String ?? "en"
                        editorVC.allAssets = [asset]
                        editorVC.currentIndex = 0
                        editorVC.singlePhotoMode = true
                        editorVC.disableCrop = true
                        editorVC.croppedImages = [0: croppedImage]
                        editorVC.modalPresentationStyle = .overFullScreen
                        
                        if let hex = currentGallery.themeColorHex, let color = UIColor(hexString: hex) {
                            editorVC.themeColor = color
                        }
                        
                        editorVC.onConfirm = { [weak self] (editedAsset: PHAsset?, finalCroppedImage: UIImage?, filterState: FilterState, caption: String) in
                            guard let self = self else { return }
                            let navToDismiss = currentGallery.navigationController ?? currentGallery
                            let presenter = navToDismiss.presentingViewController ?? navToDismiss
                            presenter.dismiss(animated: true) {
                                self.processEditorResult(asset: editedAsset, croppedImage: finalCroppedImage ?? croppedImage, filterState: filterState, caption: caption, galleryVC: currentGallery, resolve: resolve, reject: reject)
                            }
                        }
                        
                        editorVC.onCancel = { [weak currentGallery] in
                            currentGallery?.selectedAssets.removeAll()
                            currentGallery?.refreshSelectionAfterEdit()
                        }
                        
                        var savedDetent: UISheetPresentationController.Detent.Identifier? = nil
                        if #available(iOS 15.0, *) {
                            savedDetent = currentGallery.navigationController?.sheetPresentationController?.selectedDetentIdentifier
                        }

                        let presenterVC = currentGallery.presentedViewController ?? currentGallery
                        presenterVC.present(editorVC, animated: true) {
                            if #available(iOS 15.0, *) {
                                if let saved = savedDetent {
                                    currentGallery.navigationController?.sheetPresentationController?.selectedDetentIdentifier = saved
                                }
                            }
                        }
                    } else {
                        // Edit is disabled, directly process the cropped image
                        let navToDismiss = currentGallery.navigationController ?? currentGallery
                        let presenter = navToDismiss.presentingViewController ?? navToDismiss
                        presenter.dismiss(animated: true) {
                            self.processEditorResult(asset: asset, croppedImage: croppedImage, filterState: FilterState(filterId: "original", intensity: 1.0), caption: "", galleryVC: currentGallery, resolve: resolve, reject: reject)
                        }
                    }
                }
            }

            if enableEditor {
                // allowsEditing 활성화: GalleryVC 내 탭 동작 변경
                galleryVC.allowsEditing = true

                galleryVC.onSingleImageTappedForEdit = { [weak self] (asset: PHAsset, sourceFrame: CGRect, sourceImage: UIImage?) -> Void in
                    self?._turbo_handleSingleImageTappedForEdit(asset: asset, sourceFrame: sourceFrame, sourceImage: sourceImage, options: options, resolve: resolve, reject: reject)
                }
            }

            galleryVC.onImagesSelected = { [weak self] selectedImages in
                guard let self = self else { resolve([]); return }

                guard !selectedImages.isEmpty else {
                    self.currentGalleryVC = nil
                    reject("CANCELLED", "User cancelled the image picker", nil)
                    return
                }

                var results: [[String: Any]] = []
                let tempDir    = self.prepareCacheDirectory()
                let maxWidth   = galleryVC.maxWidth
                let maxHeight  = galleryVC.maxHeight
                let format     = galleryVC.outputFormat       // "webp" | "jpg" | "png"
                let mimeType   = self.mimeType(for: format)
                let needResize = (maxWidth > 0 || maxHeight > 0)

                let resultsLock = NSLock()
                
                DispatchQueue.global(qos: .userInitiated).async {
                    for (index, pair) in selectedImages.enumerated() {
                            let (asset, image) = pair
                            let timestamp    = Int(Date().timeIntervalSince1970 * 1000)
                            let originalSize = image.size

                            if let phAsset = asset {
                                // ✅ 1순위: PHAsset
                                let originalUri = "ph://\(phAsset.localIdentifier)"

                                var targetImage: UIImage
                                if needResize, let resized = self.resizeImage(image, maxWidth: maxWidth, maxHeight: maxHeight) {
                                    targetImage = resized
                                } else {
                                    targetImage = image
                                }
                                targetImage = ImageProcessor.shared.applyWatermarkIfNeeded(targetImage)

                                var result: [String: Any] = [
                                    "originalUri":    originalUri,
                                    "originalWidth":  Int(originalSize.width),
                                    "originalHeight": Int(originalSize.height),
                                    "type": mimeType
                                ]

                                if let savedUri = self.saveImage(targetImage, format: format,
                                                                 prefix: "resized",
                                                                 index: index, timestamp: timestamp,
                                                                 tempDir: tempDir) {
                                    result["uri"]           = savedUri
                                    result["width"]         = Int(targetImage.size.width)
                                    result["height"]        = Int(targetImage.size.height)
                                    let meta = self.fileMetadata(fromPath: savedUri)
                                    result["fileName"]      = meta.fileName
                                    result["fileExtension"] = meta.fileExtension
                                    result["fileSize"]      = meta.fileSize
                                }

                                resultsLock.lock()
                                results.append(result)
                                let currentResult = result
                                resultsLock.unlock()
                                
                                self.sendEvent(withName: "onImageProcessed", body: [
                                    "index": index,
                                    "total": selectedImages.count,
                                    "image": currentResult
                                ])
                            } else {
                                // ✅ 2순위: 카메라 촬영본
                                guard let originalFilePath = self.saveOriginalImageAsJPEG(
                                        image, index: index, timestamp: timestamp, tempDir: tempDir) else {
                                    return
                                }

                                var targetImage: UIImage
                                if needResize, let resized = self.resizeImage(image, maxWidth: maxWidth, maxHeight: maxHeight) {
                                    targetImage = resized
                                } else {
                                    targetImage = image
                                }
                                targetImage = ImageProcessor.shared.applyWatermarkIfNeeded(targetImage)

                                var result: [String: Any] = [
                                    "originalUri":     originalFilePath,
                                    "originalFileUri": originalFilePath,
                                    "originalWidth":   Int(originalSize.width),
                                    "originalHeight":  Int(originalSize.height),
                                    "type": mimeType
                                ]
                                let origMeta = self.fileMetadata(fromPath: originalFilePath)
                                result["fileName"]      = origMeta.fileName
                                result["fileExtension"] = origMeta.fileExtension
                                result["fileSize"]      = origMeta.fileSize

                                if let savedUri = self.saveImage(targetImage, format: format,
                                                                 prefix: "resized",
                                                                 index: index, timestamp: timestamp,
                                                                 tempDir: tempDir) {
                                    result["uri"]           = savedUri
                                    result["width"]         = Int(targetImage.size.width)
                                    result["height"]        = Int(targetImage.size.height)
                                    let meta = self.fileMetadata(fromPath: savedUri)
                                    result["fileName"]      = meta.fileName
                                    result["fileExtension"] = meta.fileExtension
                                    result["fileSize"]      = meta.fileSize
                                }

                                resultsLock.lock()
                                results.append(result)
                                let currentResult = result
                                resultsLock.unlock()
                                
                                self.sendEvent(withName: "onImageProcessed", body: [
                                    "index": index,
                                    "total": selectedImages.count,
                                    "image": currentResult
                                ])
                            }
                    } // end for

                    DispatchQueue.main.async {
                        self.currentGalleryVC = nil
                        resolve(results)
                    }
                }
            }

            let navigationController = UINavigationController(rootViewController: galleryVC)
            navigationController.modalPresentationStyle = .custom
            navigationController.transitioningDelegate = galleryVC.customTransitioningDelegate
            
            // navigationController.view.backgroundColor 설정 제거 (투명한 탑바 지원을 위함)
            
            let step3 = CFAbsoluteTimeGetCurrent()
            // Configure sheet presentation - 최소 설정만 사용 (기본 iOS 동작 보장)
            if #available(iOS 15.0, *) {
                if let sheet = navigationController.sheetPresentationController {
                    if #available(iOS 16.0, *) {
                        // iOS 16+: Use custom 60% detent
                        let customDetent = UISheetPresentationController.Detent.custom { context in
                            return context.maximumDetentValue * 0.6
                        }
                        
                        sheet.detents = [customDetent, .large()]
                    } else {
                        // iOS 15: Use medium and large detents
                        sheet.detents = [.medium(), .large()]
                    }
                    
                    sheet.prefersGrabberVisible = false
                    sheet.prefersScrollingExpandsWhenScrolledToEdge = true
                    
                    if #available(iOS 16.0, *) {
                        sheet.preferredCornerRadius = 20
                    }
                    sheet.largestUndimmedDetentIdentifier = nil
                    
                    if #available(iOS 16.0, *) {
                        sheet.preferredCornerRadius = 20
                    }
                }
            }
            print("🔵 [DEBUG] Sheet 설정 완료 - 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - step3))초")
            
            let step4 = CFAbsoluteTimeGetCurrent()
            print("🔵 [DEBUG] present 시작...")
            rootViewController.present(navigationController, animated: true)
            print("🔵 [DEBUG] present 완료 - 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - step4))초")
            print("✅ [DEBUG] openGallery 전체 완료 - 총 경과: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime))초")
        }
    }
    
    @objc
    func closeGallery(_ resolve: @escaping RCTPromiseResolveBlock,
                      reject: @escaping RCTPromiseRejectBlock) -> Void {
        
        DispatchQueue.main.async { [weak self] () -> Void in
            guard let self = self else {
                reject("ERROR", "Module deallocated", nil)
                return
            }
            
            guard let galleryVC = self.currentGalleryVC else {
                reject("ERROR", "Gallery is not open", nil)
                return
            }
            
            // 갤러리 닫기 전 강제 정리
            galleryVC.forceCleanupBeforeDismiss()
            
            // 갤러리 닫기
            galleryVC.dismiss(animated: true) { [weak self] in
                // dismiss 완료 후 참조 정리
                self?.currentGalleryVC = nil
                resolve(true)
            }
        }
    }
    
    // MARK: - Private Methods

    /// iOS가 저장 공간 부족 시 자동으로 정리하는 캐시 디렉토리
    /// picker 결과물은 일시적으로만 필요하므로 cache 사용
    private var cacheDirectory: String {
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("RNTurboImagePicker").path
            ?? NSTemporaryDirectory()
    }

    /// 캐시 디렉토리 준비 (없으면 생성)
    private func prepareCacheDirectory() -> String {
        let dir = cacheDirectory
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // 이미지 리사이징 (비율 유지)
    private func resizeImage(_ image: UIImage, maxWidth: Int, maxHeight: Int) -> UIImage? {
        let originalSize = image.size
        var targetSize = originalSize
        
        // maxWidth와 maxHeight 둘 다 사용 (기본값 500이므로 항상 리사이징)
        if maxWidth > 0 && maxHeight > 0 {
            // 둘 다 설정된 경우: 더 작은 비율로 리사이징
            let widthRatio = CGFloat(maxWidth) / originalSize.width
            let heightRatio = CGFloat(maxHeight) / originalSize.height
            let ratio = min(widthRatio, heightRatio, 1.0) // 1.0 이상이면 리사이징 안 함
            
            if ratio < 1.0 {
                targetSize = CGSize(width: originalSize.width * ratio, height: originalSize.height * ratio)
            }
        } else if maxWidth > 0 && originalSize.width > CGFloat(maxWidth) {
            // maxWidth만 설정된 경우
            let ratio = CGFloat(maxWidth) / originalSize.width
            targetSize = CGSize(width: CGFloat(maxWidth), height: originalSize.height * ratio)
        } else if maxHeight > 0 && originalSize.height > CGFloat(maxHeight) {
            // maxHeight만 설정된 경우
            let ratio = CGFloat(maxHeight) / originalSize.height
            targetSize = CGSize(width: originalSize.width * ratio, height: CGFloat(maxHeight))
        } else {
            // 리사이징 불필요
            return nil
        }
        
        // 같은 크기면 리사이징 안 함
        if targetSize.width >= originalSize.width && targetSize.height >= originalSize.height {
            return nil
        }
        
        // 이미지 리사이징 (UIGraphicsImageRenderer 방식 - 메모리 최적화)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // 실제 픽셀 크기로 저장하기 위함
        format.opaque = false
        if #available(iOS 12.0, *) {
            format.preferredRange = .standard // 광색역 대신 표준 색역 사용으로 메모리 절약
        }
        
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    // ✅ 2순위: 원본 이미지를 JPEG으로 저장 (WebP 인코딩 없음 → 빠름)
    // 카메라 촬영본 및 에디터 결과물에 사용
    private func saveOriginalImageAsJPEG(_ image: UIImage, index: Int, timestamp: Int, tempDir: String) -> String? {
        let fileName = "turbo_picker_original_\(timestamp)_\(index).jpg"
        let filePath = (tempDir as NSString).appendingPathComponent(fileName)
        let fileURL = URL(fileURLWithPath: filePath)

        if let jpegData = image.jpegData(compressionQuality: 0.9) {
            do {
                try jpegData.write(to: fileURL, options: [.atomic])
                return fileURL.absoluteString
            } catch {
                print("❌ [TurboImagePicker] JPEG 원본 이미지 저장 실패: \(error)")
            }
        }
        return nil
    }
    
    // 리사이즈된 이미지 저장 (WebP 포맷)
    private func saveResizedImage(_ image: UIImage, index: Int, timestamp: Int, tempDir: String) -> String? {
        let fileName = "turbo_picker_resized_\(timestamp)_\(index).webp"
        let filePath = (tempDir as NSString).appendingPathComponent(fileName)
        let fileURL = URL(fileURLWithPath: filePath)
        
        if let data = encodeWebP(image: image, quality: 0.85) {
            do {
                try data.write(to: fileURL, options: [.atomic])
                return fileURL.absoluteString
            } catch {
                print("❌ [TurboImagePicker] WebP 리사이즈 이미지 저장 실패: \(error)")
            }
        }
        // Fallback to JPEG
        if let jpegData = image.jpegData(compressionQuality: 0.85) {
            let fallbackPath = (tempDir as NSString).appendingPathComponent("turbo_picker_resized_\(timestamp)_\(index).jpg")
            let fallbackURL = URL(fileURLWithPath: fallbackPath)
            do {
                try jpegData.write(to: fallbackURL, options: [.atomic])
                return fallbackURL.absoluteString
            } catch {}
        }
        return nil
    }
    // WebP 인코딩 - iOS 16+ 네이티브 CGImageDestination 사용 또는 런타임 Fallback
    private func encodeWebP(image: UIImage, quality: CGFloat) -> Data? {
        if #available(iOS 16.0, *) {
            if let cgImage = image.cgImage {
                let data = NSMutableData()
                if let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.webp" as CFString, 1, nil) {
                    let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
                    CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
                    if CGImageDestinationFinalize(destination) {
                        NSLog("✅ [encodeWebP] iOS 16 네이티브 WebP 인코딩 성공 - %d bytes", data.length)
                        return data as Data
                    }
                }
            }
        }
        
        NSLog("🟣 [encodeWebP] SDImageWebPCoder 런타임 폴백 시도")
        // iOS 14, 15이거나 네이티브 실패 시 SDImageWebPCoder 런타임 호출
        if let coderClass = NSClassFromString("SDImageWebPCoder") as? NSObject.Type {
            if coderClass.responds(to: NSSelectorFromString("sharedCoder")) {
                let sharedCoder = coderClass.perform(NSSelectorFromString("sharedCoder")).takeUnretainedValue()
                let encodeSel = NSSelectorFromString("encodedDataWithImage:format:options:")
                
                if sharedCoder.responds(to: encodeSel),
                   let method = class_getInstanceMethod(type(of: sharedCoder), encodeSel) {
                    
                    // ObjC method signature: - (NSData *)encodedDataWithImage:(UIImage *)image format:(NSInteger)format options:(NSDictionary *)options
                    typealias EncodeFunc = @convention(c) (AnyObject, Selector, UIImage?, Int, [String: Any]?) -> Data?
                    let implementation = method_getImplementation(method)
                    let encode = unsafeBitCast(implementation, to: EncodeFunc.self)
                    
                    // format: 3 (SDImageFormatWebP)
                    let options: [String: Any] = ["encodeCompressionQuality": quality]
                    if let data = encode(sharedCoder, encodeSel, image, 3, options) {
                        NSLog("✅ [encodeWebP] SDImageWebPCoder 런타임 인코딩 성공 - %d bytes", data.count)
                        return data
                    } else {
                        NSLog("❌ [encodeWebP] SDImageWebPCoder 런타임 인코딩 실패 (nil 반환)")
                    }
                } else {
                    NSLog("❌ [encodeWebP] SDImageWebPCoder에 encodedDataWithImage:format:options: 메서드가 없습니다.")
                }
            } else {
                NSLog("❌ [encodeWebP] SDImageWebPCoder에 sharedCoder가 없습니다.")
            }
        } else {
            NSLog("❌ [encodeWebP] SDImageWebPCoder 클래스를 찾을 수 없습니다.")
        }

        NSLog("❌ [encodeWebP] 모든 WebP 인코딩 실패 → nil 반환")
        return nil
    }


    // MARK: - Format-aware save helpers

    /// outputFormat("webp"|"jpg"|"png")에 맞는 MIME 타입 반환
    private func mimeType(for format: String) -> String {
        switch format {
        case "png":  return "image/png"
        case "jpg":  return "image/jpeg"
        default:     return "image/webp"
        }
    }

    /// 이미지를 지정 포맷으로 저장하고 file:// URI 반환
    /// - Parameters:
    ///   - image: 저장할 UIImage
    ///   - format: "webp" | "jpg" | "png"
    ///   - prefix: 파일명 prefix (e.g. "resized", "original")
    ///   - index: 배치 내 인덱스
    ///   - timestamp: 타임스탬프(ms)
    ///   - tempDir: 저장 디렉토리 경로
    private func saveImage(_ image: UIImage, format: String,
                           prefix: String, index: Int,
                           timestamp: Int, tempDir: String, forceJPEG: Bool = false) -> String? {
        let ext: String
        let data: Data?

        let actualFormat = forceJPEG ? "jpg" : format

        switch actualFormat {
        case "png":
            ext = "png"
            data = image.pngData()
        case "jpg":
            ext = "jpg"
            data = image.jpegData(compressionQuality: 0.9)
        default: // "webp"
            ext = "webp"
            data = encodeWebP(image: image, quality: 0.85)
        }

        guard let imageData = data else {
            // WebP 인코딩 실패 시 JPEG fallback
            if format == "webp", let fallbackData = image.jpegData(compressionQuality: 0.85) {
                let path = (tempDir as NSString).appendingPathComponent(
                    "turbo_picker_\(prefix)_\(timestamp)_\(index).jpg")
                let url = URL(fileURLWithPath: path)
                try? fallbackData.write(to: url)
                return url.absoluteString
            }
            return nil
        }

        let fileName = "turbo_picker_\(prefix)_\(timestamp)_\(index).\(ext)"
        let filePath = (tempDir as NSString).appendingPathComponent(fileName)
        let fileURL  = URL(fileURLWithPath: filePath)

        do {
            try imageData.write(to: fileURL)
            return fileURL.absoluteString
        } catch {
            print("❌ [TurboImagePicker] \(format.uppercased()) 저장 실패: \(error)")
            return nil
        }
    }

    
    /// 저장된 파일 경로에서 fileName, fileExtension, fileSize 반환
    private func fileMetadata(fromPath filePath: String) -> (fileName: String, fileExtension: String, fileSize: Int64) {
        let url = URL(fileURLWithPath: filePath.hasPrefix("file://")
            ? String(filePath.dropFirst(7))
            : filePath)
        let fileName = url.lastPathComponent
        let fileExtension = url.pathExtension.lowercased()
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        return (fileName, fileExtension, fileSize)
    }
    
    private func getRootViewController() -> UIViewController? {
        var rootViewController: UIViewController?
        
        if #available(iOS 13.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
               let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
                rootViewController = window.rootViewController
            }
        }
        
        if rootViewController == nil {
            rootViewController = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController
        }
        
        if rootViewController == nil {
            rootViewController = UIApplication.shared.keyWindow?.rootViewController
        }
        
        // Handle presented view controllers
        while let presented = rootViewController?.presentedViewController {
            rootViewController = presented
        }
        
        return rootViewController
    }
    
    // MARK: - Editor Result Processing
    
    private func processEditorResult(asset: PHAsset?, croppedImage: UIImage?, filterState: FilterState, caption: String, galleryVC: GalleryViewController?, targetMaxWidth: Int? = nil, targetMaxHeight: Int? = nil, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        let tempDir = prepareCacheDirectory()
        let maxWidth = targetMaxWidth ?? galleryVC?.maxWidth ?? 1024
        let maxHeight = targetMaxHeight ?? galleryVC?.maxHeight ?? 1024
        let format = galleryVC?.outputFormat ?? "webp"
        
        DispatchQueue.global(qos: .userInitiated).async {
            let photoManager = PhotoManager.shared
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            
            let originalUri = asset != nil ? "ph://\(asset!.localIdentifier)" : ""
            var originalFilePath: String? = nil
            var resultImage: UIImage? = nil
            
            let dispatchGroup = DispatchGroup()
            dispatchGroup.enter()
            
            let handleBaseImage = { (baseImage: UIImage) in
                var finalImage = baseImage
                
                if filterState.filterId != "original", let filter = FilterManager.shared.filters.first(where: { $0.id == filterState.filterId }) {
                    if let ciImage = CIImage(image: baseImage),
                       let out = filter.apply(ciImage, filterState.intensity),
                       let cgImg = FilterManager.shared.context.createCGImage(out, from: out.extent) {
                        finalImage = UIImage(cgImage: cgImg, scale: baseImage.scale, orientation: baseImage.imageOrientation)
                    }
                }
                
                finalImage = ImageProcessor.shared.applyWatermarkIfNeeded(finalImage)
                resultImage = finalImage
                // ✅ 2순위: 에디터 결과 원본 저장 (WebP 소프트웨어 인코딩 방지를 위해 하드웨어 가속되는 JPG 강제 사용)
                originalFilePath = self.saveImage(finalImage, format: format, prefix: "original", index: 0, timestamp: timestamp, tempDir: tempDir, forceJPEG: true)
                dispatchGroup.leave()
            }
            
            let targetSize = (maxWidth > 0 && maxHeight > 0) ? CGSize(width: maxWidth, height: maxHeight) : PHImageManagerMaximumSize
            
            if let cropped = croppedImage {
                handleBaseImage(cropped)
            } else {
                _ = photoManager.requestFullImage(for: asset!, targetSize: targetSize, progressHandler: nil) { fullImage in
                    if let fullImage = fullImage {
                        handleBaseImage(fullImage)
                    } else {
                        dispatchGroup.leave()
                    }
                }
            }
            
            dispatchGroup.wait()
            
            guard let image = resultImage else {
                DispatchQueue.main.async {
                    self.currentGalleryVC = nil
                    reject("ERROR", "Failed to load image from editor", nil)
                }
                return
            }
            
            let originalSize = image.size
            
            var result: [String: Any] = [
                "originalUri": originalUri,
                "originalWidth": Int(originalSize.width),
                "originalHeight": Int(originalSize.height),
                "type": self.mimeType(for: format),
                "caption": caption
            ]
            
            if let originalFilePath = originalFilePath {
                result["originalFileUri"] = originalFilePath
                result["uri"] = originalFilePath // 기본적으로 uri에도 파일 경로 저장
                let meta = self.fileMetadata(fromPath: originalFilePath)
                result["fileName"] = meta.fileName
                result["fileExtension"] = meta.fileExtension
                result["fileSize"] = meta.fileSize
            }
            
            let finalImageForFormat = self.resizeImage(image, maxWidth: maxWidth, maxHeight: maxHeight) ?? image
            
            if let finalUri = self.saveImage(finalImageForFormat, format: format, prefix: "final", index: 0, timestamp: timestamp, tempDir: tempDir) {
                result["uri"] = finalUri
                result["width"] = Int(finalImageForFormat.size.width)
                result["height"] = Int(finalImageForFormat.size.height)
                let finalMeta = self.fileMetadata(fromPath: finalUri)
                result["fileName"] = finalMeta.fileName
                result["fileExtension"] = finalMeta.fileExtension
                result["fileSize"] = finalMeta.fileSize
            }
            
            DispatchQueue.main.async {
                self.currentGalleryVC = nil
                resolve([result])
            }
        }
    }


    private func processEditorResultMulti(assets: [PHAsset], croppedImages: [PHAsset: UIImage], filterStates: [PHAsset: FilterState], galleryVC: GalleryViewController, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        let tempDir = prepareCacheDirectory()
        let maxWidth = galleryVC.maxWidth
        let maxHeight = galleryVC.maxHeight
        let format = galleryVC.outputFormat
        
        DispatchQueue.global(qos: .userInitiated).async {
            let photoManager = PhotoManager.shared
            var results: [[String: Any]] = []
            let dispatchGroup = DispatchGroup()
            let resultsLock = NSLock()
            
            for (index, asset) in assets.enumerated() {
                dispatchGroup.enter()
                let timestamp = Int(Date().timeIntervalSince1970 * 1000)
                let originalUri = "ph://\(asset.localIdentifier)"
                let filterState = filterStates[asset] ?? FilterState(filterId: "original", intensity: 1.0)
                let croppedImage = croppedImages[asset]
                
                let handleBaseImage = { (baseImage: UIImage) in
                    var finalImage = baseImage
                    
                    if filterState.filterId != "original", let filter = FilterManager.shared.filters.first(where: { $0.id == filterState.filterId }) {
                        if let ciImage = CIImage(image: baseImage),
                           let out = filter.apply(ciImage, filterState.intensity),
                           let cgImg = FilterManager.shared.context.createCGImage(out, from: out.extent) {
                            finalImage = UIImage(cgImage: cgImg, scale: baseImage.scale, orientation: baseImage.imageOrientation)
                        }
                    }
                    
                    finalImage = ImageProcessor.shared.applyWatermarkIfNeeded(finalImage)
                    
                    var result: [String: Any] = [
                        "originalUri": originalUri,
                        "originalWidth": Int(finalImage.size.width),
                        "originalHeight": Int(finalImage.size.height),
                        "type": self.mimeType(for: format)
                    ]
                    
                    // ✅ 2순위: 에디터 다중 결과 원본 저장 (JPG 강제 사용으로 속도 최적화)
                    if let originalFilePath = self.saveImage(finalImage, format: format, prefix: "original", index: index, timestamp: timestamp, tempDir: tempDir, forceJPEG: true) {
                        result["originalFileUri"] = originalFilePath
                        result["uri"] = originalFilePath // 기본적으로 uri에도 파일 경로 저장
                        let meta = self.fileMetadata(fromPath: originalFilePath)
                        result["fileName"] = meta.fileName
                        result["fileExtension"] = meta.fileExtension
                        result["fileSize"] = meta.fileSize
                    }
                    
                    if (maxWidth > 0 || maxHeight > 0), let resizedImage = self.resizeImage(finalImage, maxWidth: maxWidth, maxHeight: maxHeight) {
                        if let resizedUri = self.saveImage(resizedImage, format: format, prefix: "resized", index: index, timestamp: timestamp, tempDir: tempDir) {
                            result["uri"] = resizedUri
                            result["width"] = Int(resizedImage.size.width)
                            result["height"] = Int(resizedImage.size.height)
                            let resizedMeta = self.fileMetadata(fromPath: resizedUri)
                            result["fileName"] = resizedMeta.fileName
                            result["fileExtension"] = resizedMeta.fileExtension
                            result["fileSize"] = resizedMeta.fileSize
                        }
                    }
                    
                    resultsLock.lock()
                    results.append(result)
                    let currentResult = result
                    resultsLock.unlock()
                    
                    self.sendEvent(withName: "onImageProcessed", body: [
                        "index": index,
                        "total": assets.count,
                        "image": currentResult
                    ])
                    dispatchGroup.leave()
                }
                
                let targetSize = (maxWidth > 0 && maxHeight > 0) ? CGSize(width: maxWidth, height: maxHeight) : PHImageManagerMaximumSize
                
                if let cropped = croppedImage {
                    handleBaseImage(cropped)
                } else {
                    _ = photoManager.requestFullImage(for: asset, targetSize: targetSize, progressHandler: nil) { fullImage in
                        if let fullImage = fullImage {
                            handleBaseImage(fullImage)
                        } else {
                            dispatchGroup.leave()
                        }
                    }
                }
            }
            
            dispatchGroup.wait()
            
            DispatchQueue.main.async {
                self.currentGalleryVC = nil
                if results.isEmpty {
                    reject("ERROR", "Failed to load images from editor", nil)
                } else {
                    // 순서를 유지하기 위해
                    resolve(results)
                }
            }
        }
    }
}

// MARK: - UIColor Extension for Hex Support
extension UIColor {
    convenience init?(hexString: String) {
        var cString: String = hexString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if cString.hasPrefix("#") {
            cString.remove(at: cString.startIndex)
        }

        if cString.count != 6 {
            return nil
        }

        var rgbValue: UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)

        self.init(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: 1.0
        )
    }
}

#if RCT_NEW_ARCH_ENABLED
// MARK: - Turbo Module Protocol Conformance (New Architecture)
// extension RNTurboImagePicker: RCTTurboModule {
//    // Turbo Module specific implementation if needed
// }
#endif
import Foundation
import UIKit


fileprivate func _turbo_handleConfirmMulti(assets: [PHAsset], croppedImages: [PHAsset: UIImage], filterStates: [PHAsset: FilterState], currentGallery: GalleryViewController) {
    DispatchQueue.global(qos: .userInitiated).async {
        var newlyEditedAssets: [PHAsset] = []
        for asset in assets {
            if let baseImage = croppedImages[asset] {
                var finalImage = baseImage
                if let state = filterStates[asset], state.filterId != "original" {
                    if let filter = FilterManager.shared.filters.first(where: { (f: ImageFilter) -> Bool in return f.id == state.filterId }) {
                        if let ciImage = CIImage(image: baseImage) {
                            if let out = filter.apply(ciImage, state.intensity) {
                                if let cgImg = FilterManager.shared.context.createCGImage(out, from: out.extent) {
                                    finalImage = UIImage(cgImage: cgImg, scale: baseImage.scale, orientation: baseImage.imageOrientation)
                                }
                            }
                        }
                    }
                }
                DispatchQueue.main.async {
                    currentGallery.editedImages[asset.localIdentifier] = finalImage
                }
                newlyEditedAssets.append(asset)
            }
        }
        DispatchQueue.main.async {
            for asset in newlyEditedAssets {
                if !currentGallery.selectedAssetsSet.contains(asset.localIdentifier) {
                    if currentGallery.maxSelection == 0 || currentGallery.selectedAssets.count < currentGallery.maxSelection {
                        currentGallery.selectedAssets.append(asset)
                        currentGallery.selectedAssetsSet.insert(asset.localIdentifier)
                    }
                }
            }
            currentGallery.refreshSelectionAfterEdit()
            
            // These updates are required per the original code
            currentGallery.updateSelectedCellNumbers()
            currentGallery.notifySelectionChanged()
            currentGallery.updateNavigationBarForSelection()
        }
    }
}

fileprivate extension RNTurboImagePicker {
    func _turbo_handleSingleImageTappedForEdit(asset: PHAsset, sourceFrame: CGRect, sourceImage: UIImage?, options: NSDictionary, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        guard let currentGallery = self.currentGalleryVC else { return }
        let galleryNav = currentGallery.navigationController
        let isMultiSelect = currentGallery.maxSelection != 1 && currentGallery.maxSelection != 0

        let editorVC = ImageEditorViewController()
        editorVC.languageCode = options["languageCode"] as? String ?? "en"
        var editorAssets = currentGallery.allAssets
        var targetIndex = 0
        if let idx = editorAssets.firstIndex(of: asset) {
            targetIndex = idx
        } else {
            editorAssets.insert(asset, at: 0)
            targetIndex = 0
        }
        
        editorVC.allAssets = editorAssets
        editorVC.currentIndex = targetIndex
        editorVC.selectedAssets = currentGallery.selectedAssets
        
        editorVC.onSelectionToggled = { [weak currentGallery] (toggledAsset, isSelected) in
            guard let currentGallery = currentGallery else { return }
            if isSelected {
                if !currentGallery.selectedAssets.contains(toggledAsset) {
                    currentGallery.selectedAssets.append(toggledAsset)
                    currentGallery.selectedAssetsSet.insert(toggledAsset.localIdentifier)
                }
            } else {
                currentGallery.selectedAssetsSet.remove(toggledAsset.localIdentifier)
                currentGallery.selectedAssets.removeAll(where: { $0.localIdentifier == toggledAsset.localIdentifier })
            }
            currentGallery.refreshSelectionAfterEdit()
            currentGallery.updateSelectedCellNumbers()
            currentGallery.notifySelectionChanged()
            currentGallery.updateNavigationBarForSelection()
        }
        
        editorVC.onEditDeleted = { [weak currentGallery] asset in
            currentGallery?.editedImages.removeValue(forKey: asset.localIdentifier)
        }
        
        editorVC.modalPresentationStyle = .overFullScreen
        editorVC.singlePhotoMode = !isMultiSelect
        
        var initialCroppedImages: [Int: UIImage] = [:]
        for (i, a) in editorAssets.enumerated() {
            if let editedImg = currentGallery.editedImages[a.localIdentifier] {
                initialCroppedImages[i] = editedImg
            }
        }
        editorVC.croppedImages = initialCroppedImages
        
        if sourceFrame != .zero {
            self.editorTransitionDelegate = ImageEditorTransitionDelegate()
            self.editorTransitionDelegate?.sourceFrame = sourceFrame
            self.editorTransitionDelegate?.sourceImage = sourceImage
            
            if let editedImg = currentGallery.editedImages[asset.localIdentifier] {
                self.editorTransitionDelegate?.uncroppedImage = editedImg
                self.editorTransitionDelegate?.asset = nil
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
            if let editedImg = currentGallery.editedImages[asset.localIdentifier] {
                ratio = editedImg.size.width / max(1.0, editedImg.size.height)
            }
            self.editorTransitionDelegate?.assetAspectRatio = ratio
            self.editorTransitionDelegate?.frameProvider = { [weak currentGallery] currentAsset in
                return currentGallery?.frameForAsset(currentAsset)
            }
            
            editorVC.transitioningDelegate = self.editorTransitionDelegate
        }

        if let hex = currentGallery.themeColorHex, let color = UIColor(hexString: hex) {
            editorVC.themeColor = color
        }

        editorVC.onConfirmMulti = { [weak currentGallery] (assets, croppedImages, filterStates) in
            guard let currentGallery = currentGallery else { return }
            
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
                                currentGallery.editedImages[asset.localIdentifier] = finalImage
                            }
                            newlyEditedAssets.append(asset)
                        }
                    }
                    
                    DispatchQueue.main.async {
                        for asset in newlyEditedAssets {
                            if !currentGallery.selectedAssetsSet.contains(asset.localIdentifier) {
                                if currentGallery.maxSelection == 0 || currentGallery.selectedAssets.count < currentGallery.maxSelection {
                                    currentGallery.selectedAssets.append(asset)
                                    currentGallery.selectedAssetsSet.insert(asset.localIdentifier)
                                }
                            }
                        }
                        currentGallery.updateSelectedCellNumbers()
                        currentGallery.notifySelectionChanged()
                        currentGallery.updateNavigationBarForSelection()
                        currentGallery.collectionView.reloadData()
                    }
                }
            }
        }

        editorVC.onConfirm = { [weak self, weak galleryNav, weak currentGallery] (editedAsset: PHAsset?, croppedImage: UIImage?, filterState: FilterState, caption: String) in
            guard let self = self else { return }
            let navToDismiss = galleryNav ?? currentGallery
            let presenter = navToDismiss?.presentingViewController ?? navToDismiss
            presenter?.dismiss(animated: true) {
                self.processEditorResult(asset: editedAsset, croppedImage: croppedImage, filterState: filterState, caption: caption, galleryVC: currentGallery, resolve: resolve, reject: reject)
            }
        }

        editorVC.onCancel = { [weak editorVC] in
            // 에디터만 닫고 갤러리의 선택 상태는 유지합니다.
            editorVC?.dismiss(animated: true, completion: nil)
        }

        var savedDetent: UISheetPresentationController.Detent.Identifier? = nil
        if #available(iOS 15.0, *) {
            savedDetent = galleryNav?.sheetPresentationController?.selectedDetentIdentifier
        }

        let presenterVC = currentGallery.presentedViewController ?? currentGallery
        presenterVC.present(editorVC, animated: true) {
            if #available(iOS 15.0, *) {
                if let saved = savedDetent {
                    galleryNav?.sheetPresentationController?.selectedDetentIdentifier = saved
                }
            }
        }
    }
}

extension RNTurboImagePicker: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        zoomAnimator.isPresenting = true
        return zoomAnimator
    }
    
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        zoomAnimator.isPresenting = false
        return zoomAnimator
    }
}
