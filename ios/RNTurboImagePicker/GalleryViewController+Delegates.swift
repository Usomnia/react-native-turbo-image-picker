//
//  GalleryViewController+Delegates.swift
//  RNTurboImagePicker
//
//  📁 코드 관리: GalleryViewController에서 분리된 외부 Delegate 구현
//  - AlbumPickerDelegate
//  - UIImagePickerControllerDelegate (카메라)
//  - UIAdaptivePresentationControllerDelegate (스와이프 dismiss)
//

import UIKit
import Photos

// MARK: - AlbumPickerDelegate

extension GalleryBaseViewController: AlbumPickerDelegate {
    func albumPicker(_ picker: AlbumPickerViewController, didSelectAlbum album: Album) {
        // 같은 앨범 선택 시 무시
        if selectedAlbum?.collection == album.collection {
            collectionView.isScrollEnabled = true
            return
        }
        
        selectedAlbum = album
        
        // 최근 항목 앨범은 언어 설정에 따른 텍스트 사용, 다른 앨범은 원래 이름 사용
        if album.collection.assetCollectionSubtype == .smartAlbumUserLibrary {
            updateAlbumButtonTitle(recentsAlbumText)
        } else {
            updateAlbumButtonTitle(album.title)
        }
        
        debugPrint("📸 앨범 변경: \(album.title) (\(album.count)장)")
        
        // 스크롤 다시 활성화
        collectionView.isScrollEnabled = true
        
        // 자연스러운 전환으로 로딩
        loadPhotosWithTransition()
    }
    
    // 팝업이 닫힐 때 스크롤 다시 활성화
    func albumPickerDidDismiss(_ picker: AlbumPickerViewController) {
        collectionView.isScrollEnabled = true
    }
}

// MARK: - UIImagePickerControllerDelegate

extension GalleryBaseViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        guard let image = info[.originalImage] as? UIImage else {
            picker.dismiss(animated: true)
            return
        }
        
        debugPrint("📸 카메라로 사진 촬영 완료, 갤러리 저장 시도...")
        
        var placeholder: PHObjectPlaceholder?
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
            placeholder = request.placeholderForCreatedAsset
        }) { [weak self] success, error in
            DispatchQueue.main.async {
                picker.dismiss(animated: true) {
                    guard let self = self else { return }
                    var finalAsset: PHAsset? = nil
                    if success, let id = placeholder?.localIdentifier {
                        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
                        finalAsset = fetchResult.firstObject
                        debugPrint("✅ 카메라 사진 갤러리 저장 성공, PHAsset 취득 완료: \(id)")
                    } else {
                        debugPrint("❌ 카메라 사진 갤러리 저장 실패: \(String(describing: error))")
                    }
                    
                    self.hasReturnedImages = true
                    self.onImagesSelected?([(finalAsset, image)])
                    self.dismiss(animated: true)
                }
            }
        }
    }
    
    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        // 카메라만 닫기 (갤러리는 유지)
        picker.dismiss(animated: true) { [weak self] in
            self?.restoreSheetAndCameraCell()
        }
        debugPrint("📸 카메라 취소 - 갤러리는 유지")
    }
    
    /// 카메라 앱 dismiss 후 sheet detent 복원 & 카메라 셀 갱신
    private func restoreSheetAndCameraCell() {
        // 카메라 셀 다시 설정 (카메라 프리뷰 재시작)
        if shouldShowCamera {
            let indexPath = IndexPath(item: 0, section: 0)
            if let cell = collectionView.cellForItem(at: indexPath) as? GalleryCell,
               let galleryVC = self as? GalleryViewController {
                cell.configureCameraIcon(galleryID: self.galleryID, sharedPreview: galleryVC.sharedCameraView)
            }
        }
    }
}

// MARK: - UIAdaptivePresentationControllerDelegate

extension GalleryBaseViewController: UIAdaptivePresentationControllerDelegate {
    // 스와이프로 dismiss가 완전히 완료된 후 호출됨
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        // 스와이프로 닫을 때 빈 배열 전달
        debugPrint("❌ 스와이프로 닫힘: 빈 배열 전달")
        if !hasReturnedImages {
            hasReturnedImages = true
            onImagesSelected?([])  // 빈 배열 전달 (타입: [(PHAsset?, UIImage)])
        }
    }
}
