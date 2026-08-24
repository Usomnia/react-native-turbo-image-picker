//
//  GalleryViewController+CollectionView.swift
//  RNTurboImagePicker
//
//  📁 코드 관리: GalleryViewController에서 분리된 CollectionView 관련 로직
//  - UICollectionViewDataSource
//  - UICollectionViewDelegate + UICollectionViewDelegateFlowLayout
//  - UICollectionViewDataSourcePrefetching
//  - 선택 관리 헬퍼 메서드
//

import UIKit
import Photos

// UIViewController에 트랜지션 딜리게이트를 유지하기 위한 Associated Object 키
private enum AssociatedKeys {
    static var transitionDelegate: UInt8 = 0
}

// MARK: - UICollectionViewDataSource

extension GalleryBaseViewController: UICollectionViewDataSource {
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        // 🔄 필터링: Selected 모드일 때는 선택된 사진만 표시
        if isShowingOnlySelected {
            return selectedAssets.count
        }
        
        // All 모드: 최근 항목일 때만 카메라 셀 추가
        return shouldShowCamera ? assets.count + 1 : assets.count
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: GalleryCell.identifier,
            for: indexPath
        ) as? GalleryCell else {
            return UICollectionViewCell()
        }
        
        // 🔄 필터링: Selected 모드일 때는 선택된 사진만 표시
        if isShowingOnlySelected {
            let asset = selectedAssets[indexPath.item]
            if let editedImg = editedImages[asset.localIdentifier] {
                cell.setEditedImage(editedImg, themeColor: parsedThemeColor, isCaptured: GalleryBaseViewController.sessionCapturedIdentifiers.contains(asset.localIdentifier))
            } else {
                cell.configure(with: asset, targetSize: thumbnailSize, themeColor: parsedThemeColor)
            }
            
            // maxSelection이 0이면 선택 UI 숨김
            if maxSelection == 0 {
                cell.hideSelectionUI()
            } else {
                // Selected 모드에서는 모든 항목이 선택됨 (번호 표시)
                cell.setSelected(true, number: indexPath.item + 1)
            }
            
            return cell
        }
        
        // All 모드: 최근 항목일 때만 첫 번째 셀을 카메라 아이콘으로
        if shouldShowCamera && indexPath.item == 0 {
            cell.configureCameraIcon(galleryID: self.galleryID, sharedPreview: self.sharedCameraView)
            // setSelected(false) 호출 제거 - configureCameraIcon()에서 이미 hideSelectionUI() 호출됨
        } else {
            // 나머지는 사진 표시
            let assetIndex = shouldShowCamera ? indexPath.item - 1 : indexPath.item
            let asset = assets[assetIndex]
            
            if let editedImg = editedImages[asset.localIdentifier] {
                cell.setEditedImage(editedImg, themeColor: parsedThemeColor, isCaptured: GalleryBaseViewController.sessionCapturedIdentifiers.contains(asset.localIdentifier))
            } else {
                cell.configure(with: asset, targetSize: thumbnailSize, themeColor: parsedThemeColor)
            }
            
            // maxSelection 0: 즉시선택, maxSelection 1: 단일모드 (편집ON/OFF 모두) → 선택 UI 숨김
            if maxSelection == 0 || maxSelection == 1 {
                cell.hideSelectionUI()
            } else {
                // 🚀 성능 최적화: Set으로 O(1) 존재 확인 후 필요 시에만 index 조회
                if selectedAssetsSet.contains(asset.localIdentifier),
                   let index = selectedAssets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
                    cell.setSelected(true, number: index + 1)
                } else {
                    cell.setSelected(false)
                }
            }
            
            // 전용 선택 버튼 콜백
            cell.onSelectTapped = { [weak self, weak cell] in
                guard let self = self, let cell = cell else { return }
                guard let indexPath = self.collectionView.indexPath(for: cell) else { return }
                self.handleSelectionButtonTap(at: indexPath)
            }
            
            // 삭제 버튼 콜백
            cell.onDeleteTapped = { [weak self, weak cell] in
                guard let self = self, let cell = cell else { return }
                guard let indexPath = self.collectionView.indexPath(for: cell) else { return }
                
                let assetIndex = self.shouldShowCamera ? indexPath.item - 1 : indexPath.item
                let assetToDelete = self.assets[assetIndex]
                
                // 삭제 권한 요청 및 사진 앱에서 삭제
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.deleteAssets([assetToDelete] as NSFastEnumeration)
                }) { success, error in
                    if success {
                        DispatchQueue.main.async {
                            GalleryViewController.sessionCapturedIdentifiers.remove(assetToDelete.localIdentifier)
                            
                            // 🚀 직접 수동 갱신 처리 (해당 프로젝트에는 PHPhotoLibraryChangeObserver가 없으므로)
                            if let index = self.assets.firstIndex(where: { $0.localIdentifier == assetToDelete.localIdentifier }) {
                                self.assets.remove(at: index)
                            }
                            
                            if let selectedIndex = self.selectedAssets.firstIndex(where: { $0.localIdentifier == assetToDelete.localIdentifier }) {
                                self.selectedAssets.remove(at: selectedIndex)
                                self.selectedAssetsSet.remove(assetToDelete.localIdentifier)
                            }
                            
                            // 갤러리 UI 업데이트
                            if self.isShowingOnlySelected {
                                self.updateGalleryForFilter()
                            } else {
                                self.collectionView.deleteItems(at: [indexPath])
                                self.updateSelectedCellNumbers()
                            }
                            
                            self.notifySelectionChanged()
                            self.updateNavigationBarForSelection()
                        }
                    } else if let error = error {
                        debugPrint("❌ 카메라 사진 삭제 실패: \(error)")
                    }
                }
            }
        }
        
        return cell
    }
}

// MARK: - UICollectionViewDelegate & FlowLayout

extension GalleryBaseViewController: UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        // 🔄 필터링: Selected 모드일 때는 선택된 사진 배열 사용
        if isShowingOnlySelected {
            let asset = selectedAssets[indexPath.item]
            
            // Selected 모드에서도 선택 해제 가능
            if let index = selectedAssets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
                if self.editedImages[asset.localIdentifier] != nil {
                    let title = Localizer.getString(key: "delete_edits_message", languageCode: languageCode)
                    let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: Localizer.getString(key: "no", languageCode: languageCode), style: .cancel))
                    alert.addAction(UIAlertAction(title: Localizer.getString(key: "yes", languageCode: languageCode), style: .destructive) { [weak self] _ in
                        guard let self = self else { return }
                        self.editedImages.removeValue(forKey: asset.localIdentifier)
                        self.selectedAssetsSet.remove(asset.localIdentifier)
                        self.selectedAssets.remove(at: index)
                        self.notifySelectionChanged()
                        if self.selectedAssets.isEmpty {
                            self.isShowingOnlySelected = false
                            self.filterSegmentControl.selectedSegmentIndex = 0
                        }
                        self.updateNavigationBarForSelection()
                        self.updateGalleryForFilter()
                    })
                    present(alert, animated: true)
                    return
                }

                selectedAssetsSet.remove(asset.localIdentifier)
                selectedAssets.remove(at: index)
                
                // 선택 변경 이벤트 전송
                notifySelectionChanged()
                
                // 모든 선택이 해제되면 자동으로 All 모드로 전환
                if selectedAssets.isEmpty {
                    isShowingOnlySelected = false
                    filterSegmentControl.selectedSegmentIndex = 0
                }
                
                // UI 업데이트
                updateNavigationBarForSelection()
                updateGalleryForFilter()
            }
            return
        }
        
        // All 모드: 최근 항목이고 첫 번째 셀(카메라)을 탭한 경우
        if shouldShowCamera && indexPath.item == 0 {
            showCameraCapture()
            return
        }
        
        // 사진 선택/해제 토글
        let assetIndex = shouldShowCamera ? indexPath.item - 1 : indexPath.item
        let asset = assets[assetIndex]

        // ── 프로필 모드: 탭 즉시 크롭 화면 ──────────────────────────────────
        if profileMode {
            selectedAssets = [asset]
            presentProfileCrop(for: asset)
            return
        }

        // ── editing ON, 단일(0 or 1) 선택 모드 ────────────────────────────────
        if allowsEditing && maxSelection <= 1 {
            // 갤러리를 닫지 않고 바로 편집 화면
            editingAsset = asset
            // 편집이 끝나고 갤러리로 돌아왔을 때 선택 상태 저장을 위해 selectedAssets 갱신 (단일 선택이므로 UI 표시는 안함)
            if selectedAssets.first != asset {
                selectedAssets = [asset]
                notifySelectionChanged()
                updateNavigationBarForSelection()
            }
            if let cell = collectionView.cellForItem(at: indexPath) as? GalleryCell {
                let rect = cell.convert(cell.bounds, to: nil)
                let image = cell.imageView.image
                onSingleImageTappedForEdit?(asset, rect, image)
            } else {
                onSingleImageTappedForEdit?(asset, .zero, nil)
            }
            return
        }

        // ── editing ON, 다중 선택 모드 ───────────────────────────────────────
        if allowsEditing && maxSelection != 1 {
            // 사진 탭 시 무조건 편집 화면 진입
            editingAsset = asset
            if let cell = collectionView.cellForItem(at: indexPath) as? GalleryCell {
                let rect = cell.convert(cell.bounds, to: nil)
                let image = cell.imageView.image
                onSingleImageTappedForEdit?(asset, rect, image)
            } else {
                onSingleImageTappedForEdit?(asset, .zero, nil)
            }
            return
        }

        // ── 기존 동작 (allowsEditing == false) ──────────────────────────────
        if let index = selectedAssets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
            if self.editedImages[asset.localIdentifier] != nil {
                let title = Localizer.getString(key: "delete_edits_message", languageCode: languageCode)
                let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: Localizer.getString(key: "no", languageCode: languageCode), style: .cancel))
                alert.addAction(UIAlertAction(title: Localizer.getString(key: "yes", languageCode: languageCode), style: .destructive) { [weak self] _ in
                    guard let self = self else { return }
                    self.editedImages.removeValue(forKey: asset.localIdentifier)
                    self.selectedAssetsSet.remove(asset.localIdentifier)
                    self.selectedAssets.remove(at: index)
                    if let cell = self.collectionView.cellForItem(at: indexPath) as? GalleryCell {
                        cell.configure(with: asset, targetSize: self.thumbnailSize, themeColor: self.parsedThemeColor)
                        cell.setSelected(false)
                    }
                    self.updateSelectedCellNumbers()
                    self.notifySelectionChanged()
                    self.updateNavigationBarForSelection()
                })
                present(alert, animated: true)
                return
            }

            // 🚀 성능 최적화: 이미 선택된 경우 해제
            selectedAssetsSet.remove(asset.localIdentifier)
            selectedAssets.remove(at: index)

            // 🔧 수정: reloadItems 대신 직접 셀 UI 업데이트 (빠른 연속 탭 지원)
            // 1. 현재 탭한 셀 즉시 업데이트
            if let cell = collectionView.cellForItem(at: indexPath) as? GalleryCell {
                cell.setSelected(false)
            }

            // 2. 선택된 나머지 셀들의 번호 업데이트 (performBatchUpdates 없이 직접)
            updateSelectedCellNumbers()
        } else {
            // 편집 모드: 갤러리를 닫지 않고 즉시 콜백 (에디터가 위에 올라옴)
            if let editCallback = onSingleImageTappedForEdit, maxSelection == 0 {
                if let cell = collectionView.cellForItem(at: indexPath) as? GalleryCell {
                    let rect = cell.convert(cell.bounds, to: nil)
                    let image = cell.imageView.image
                    editCallback(asset, rect, image)
                } else {
                    editCallback(asset, .zero, nil)
                }
                return
            }

            // maxSelection이 0이면, 또는 1이고 편집 OFF면 즉시 선택 후 닫기
            if maxSelection == 0 || (maxSelection == 1 && !allowsEditing) {
                selectedAssets.removeAll()
                selectedAssetsSet.removeAll()
                selectedAssets.append(asset)
                selectedAssetsSet.insert(asset.localIdentifier)

                debugPrint("✅ 즉시 선택: 1장의 사진 선택됨")

                dismiss(animated: true)
                returnSelectedImages(shouldDismiss: false)
                return
            }

            // maxSelection 체크 (0 = 단일 선택, 양수 = 제한, 음수 = 무제한)
            if maxSelection > 0 && selectedAssets.count >= maxSelection {
                debugPrint("⚠️ 최대 \(maxSelection)장까지만 선택 가능합니다")
                // TODO: 사용자에게 알림 표시 (선택적)
                return
            }

            // 🚀 성능 최적화: 선택되지 않은 경우 추가
            selectedAssets.append(asset)
            selectedAssetsSet.insert(asset.localIdentifier)

            // 🔧 수정: 현재 셀만 직접 업데이트
            if let cell = collectionView.cellForItem(at: indexPath) as? GalleryCell {
                cell.setSelected(true, number: selectedAssets.count)
            }
        }

        debugPrint("📸 선택된 사진 수: \(selectedAssets.count)")

        // 선택 변경 이벤트 전송
        notifySelectionChanged()

        // 🎨 UI 업데이트: 선택 상태에 따라 네비게이션 바 업데이트
        updateNavigationBarForSelection()
    }
    
    /// 셀 내의 선택 아이콘(원형) 전용 탭 처리
    func handleSelectionButtonTap(at indexPath: IndexPath) {
        let assetIndex = shouldShowCamera ? indexPath.item - 1 : indexPath.item
        guard assetIndex >= 0, assetIndex < assets.count else { return }
        let asset = assets[assetIndex]
        
        if let index = selectedAssets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
            if self.editedImages[asset.localIdentifier] != nil {
                let title = Localizer.getString(key: "delete_edits_message", languageCode: languageCode)
                let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: Localizer.getString(key: "no", languageCode: languageCode), style: .cancel))
                alert.addAction(UIAlertAction(title: Localizer.getString(key: "yes", languageCode: languageCode), style: .destructive) { [weak self] _ in
                    guard let self = self else { return }
                    self.editedImages.removeValue(forKey: asset.localIdentifier)
                    self.selectedAssetsSet.remove(asset.localIdentifier)
                    self.selectedAssets.remove(at: index)
                    if let cell = self.collectionView.cellForItem(at: indexPath) as? GalleryCell {
                        cell.configure(with: asset, targetSize: self.thumbnailSize, themeColor: self.parsedThemeColor)
                        cell.setSelected(false)
                    }
                    self.updateSelectedCellNumbers()
                    self.notifySelectionChanged()
                    self.updateNavigationBarForSelection()
                })
                present(alert, animated: true)
                return
            }

            // 🚀 선택 해제
            selectedAssetsSet.remove(asset.localIdentifier)
            selectedAssets.remove(at: index)
            if let cell = collectionView.cellForItem(at: indexPath) as? GalleryCell {
                cell.setSelected(false)
            }
            updateSelectedCellNumbers()
        } else {
            // 🚀 선택 추가
            let limit = maxSelection == 0 ? 1 : maxSelection
            if limit > 0 && selectedAssets.count >= limit {
                debugPrint("⚠️ 최대 \(limit)장까지만 선택 가능합니다")
                return
            }
            selectedAssets.append(asset)
            selectedAssetsSet.insert(asset.localIdentifier)
            if let cell = collectionView.cellForItem(at: indexPath) as? GalleryCell {
                cell.setSelected(true, number: selectedAssets.count)
            }
        }
        
        debugPrint("📸 선택된 사진 수: \(selectedAssets.count)")
        notifySelectionChanged()
        updateNavigationBarForSelection()
    }

    /// 에디터에서 선택 토글 시 호출 (다중+편집 모드)
    func toggleSelectionFromEditor(asset: PHAsset, select: Bool) {
        if select {
            if maxSelection <= 0 || selectedAssets.count < maxSelection {
                selectedAssets.append(asset)
                selectedAssetsSet.insert(asset.localIdentifier)
            }
        } else {
            selectedAssetsSet.remove(asset.localIdentifier)
            selectedAssets.removeAll { $0 == asset }
        }
        notifySelectionChanged()
        updateNavigationBarForSelection()
        // 셀 UI도 동기화
        if let index = assets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
            let itemIndex = shouldShowCamera ? index + 1 : index
            let indexPath = IndexPath(item: itemIndex, section: 0)
            if let cell = collectionView.cellForItem(at: indexPath) as? GalleryCell {
                if select {
                    cell.setSelected(true, number: selectedAssets.count)
                } else {
                    cell.setSelected(false)
                }
            }
        }
        updateSelectedCellNumbers()
    }

    /// 편집 화면에서 갤러리로 돌아왔을 때 선택 상태 갱신
    /// ImageEditorViewController dismiss 완료 후 호출
    public func refreshSelectionAfterEdit() {
        var indexPathsToReload = [IndexPath]()
        for indexPath in collectionView.indexPathsForVisibleItems {
            if shouldShowCamera && indexPath.item == 0 {
                continue
            }
            indexPathsToReload.append(indexPath)
        }
        
        if !indexPathsToReload.isEmpty {
            UIView.performWithoutAnimation {
                self.collectionView.reloadItems(at: indexPathsToReload)
            }
        }
        
        updateNavigationBarForSelection()
    }
    
    // 🚀 성능 최적화: 선택된 셀들의 번호만 직접 업데이트 (reloadItems 없이)
    public func updateSelectedCellNumbers() {
        // 단일 선택 모드(0 또는 1)에서는 선택 UI를 그리지 않음
        if maxSelection == 0 || maxSelection == 1 {
            return
        }
        
        for (index, asset) in selectedAssets.enumerated() {
            guard let assetIndex = assets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) else { continue }
            let itemIndex = shouldShowCamera ? assetIndex + 1 : assetIndex
            let indexPath = IndexPath(item: itemIndex, section: 0)
            
            // 화면에 보이는 셀만 업데이트 (성능 최적화)
            if let cell = collectionView.cellForItem(at: indexPath) as? GalleryCell {
                cell.setSelected(true, number: index + 1)
            }
        }
    }
    
    // MARK: - Selection Event
    
    /// 선택 변경 이벤트를 React Native로 전송
    public func notifySelectionChanged() {
        onSelectionChanged?(selectedAssets.count, maxSelection)
    }
    
    func getSelectedCellIndexPaths() -> [IndexPath] {
        return selectedAssets.compactMap { asset -> IndexPath? in
            guard let assetIndex = assets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) else { return nil }
            let itemIndex = shouldShowCamera ? assetIndex + 1 : assetIndex
            return IndexPath(item: itemIndex, section: 0)
        }
    }
    
    /// 특정 에셋의 갤러리 내 화면 위치(프레임)를 윈도우 좌표계로 반환합니다.
    /// 화면에 보이지 않는 경우 nil을 반환합니다.
    public func frameForAsset(_ asset: PHAsset) -> CGRect? {
        guard let assetIndex = assets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) else { return nil }
        let itemIndex = shouldShowCamera ? assetIndex + 1 : assetIndex
        let indexPath = IndexPath(item: itemIndex, section: 0)
        
        guard let cell = collectionView.cellForItem(at: indexPath) as? GalleryCell else {
            return nil
        }
        
        // 셀 내부의 imageView 프레임을 윈도우 좌표계로 변환
        return cell.imageView.convert(cell.imageView.bounds, to: nil)
    }
    
    func showCameraCapture() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            print("카메라를 사용할 수 없습니다")
            return
        }

        let cameraIndexPath = IndexPath(item: 0, section: 0)
        guard let cell = collectionView.cellForItem(at: cameraIndexPath) as? GalleryCell,
              let window = view.window else {
            showLegacyCameraCapture()
            return
        }

        let cellFrameInWindow = cell.convert(cell.bounds, to: window)

        // ✅ 갤러리 셀의 CameraPreviewView 인스턴스를 그대로 빌려옴 (동일 컴포넌트)
        guard let cameraView = cell.detachCameraPreviewView() else { return }

        let overlay = CameraExpandOverlay()
        overlay.onPhotoCaptured = { [weak self] image in
            self?.handleCapturedPhoto(image)
        }
        overlay.onDismiss = { [weak self, weak cameraView] in
            guard let self = self else { return }
            // CameraPreviewView를 원래 셀에 즉시 복귀 (세션은 이미 살아있으므로 재시작 불필요)
            let indexPath = IndexPath(item: 0, section: 0)
            if let cell = self.collectionView.cellForItem(at: indexPath) as? GalleryCell {
                // 셀이 재사용되어 참조를 잃었을 수 있으므로 다시 할당
                if let cameraView = cameraView {
                    cell.sharedCameraPreviewView = cameraView
                }
                cell.reattachCameraPreviewView()
                // ✅ configureCameraIcon() 재호출 없음 - 이미 라이브 상태이므로 회색 깜박임 방지
            } else {
                // 셀이 화면에 없는 경우 메모리에서 해제되도록 superview에서 제거
                cameraView?.removeFromSuperview()
            }
        }
        overlay.show(in: window, from: cellFrameInWindow, cameraView: cameraView)
    }

    /// 카메라 세션을 사용할 수 없을 때의 폴백 (UIImagePickerController)
    private func showLegacyCameraCapture() {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = self
        picker.modalPresentationStyle = .fullScreen
        present(picker, animated: true)
    }

    /// 촬영된 이미지 처리 (갤러리 저장 후 콜백)
    func handleCapturedPhoto(_ image: UIImage) {
        debugPrint("📸 커스텀 카메라로 사진 촬영 완료, 갤러리 저장 시도...")
        var placeholder: PHObjectPlaceholder?
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetChangeRequest.creationRequestForAsset(from: image)
            placeholder = request.placeholderForCreatedAsset
        }) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                var finalAsset: PHAsset? = nil
                if success, let id = placeholder?.localIdentifier {
                    let result = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
                    finalAsset = result.firstObject
                    if let finalId = finalAsset?.localIdentifier {
                        GalleryViewController.sessionCapturedIdentifiers.insert(finalId)
                        debugPrint("✅ 캡처된 에셋 ID 세션에 저장됨: \(finalId)")
                    }
                    debugPrint("✅ 카메라 사진 갤러리 저장 성공: \(id)")
                } else {
                    debugPrint("❌ 카메라 사진 갤러리 저장 실패: \(String(describing: error))")
                }
                if let asset = finalAsset {
                    let shouldCrop = self.profileMode
                    let shouldEdit = self.allowsEditing
                    
                    if shouldCrop || shouldEdit {
                        if !self.assets.contains(asset) {
                            self.assets.insert(asset, at: 0)
                            if !self.isShowingOnlySelected {
                                let itemIndex = self.shouldShowCamera ? 1 : 0
                                self.collectionView.insertItems(at: [IndexPath(item: itemIndex, section: 0)])
                            }
                        }
                        
                        let openEditor = {
                            if shouldCrop {
                                self.presentProfileCrop(for: asset)
                            } else {
                                self.editingAsset = asset
                                self.onSingleImageTappedForEdit?(asset, .zero, nil)
                            }
                        }
                        
                        // 현재 떠 있는 카메라 화면을 닫고, 그 직후에 편집기를 엽니다.
                        if self.presentedViewController != nil {
                            self.dismiss(animated: false, completion: openEditor)
                        } else {
                            openEditor()
                        }
                        return
                    }
                    
                    // 🚀 멀티 선택 모드(maxSelection != 1)이면서 편집 OFF인 경우
                    if self.maxSelection != 1 {
                        var willSelect = false
                        if !self.selectedAssetsSet.contains(asset.localIdentifier) {
                            if self.maxSelection <= 0 || self.selectedAssets.count < self.maxSelection {
                                willSelect = true
                            }
                        }
                        
                        // 1. 상태 업데이트 먼저 수행 (UI 업데이트 시 올바른 선택 상태 반영을 위해)
                        if !self.assets.contains(asset) {
                            self.assets.insert(asset, at: 0)
                        }
                        
                        if willSelect {
                            self.selectedAssets.append(asset)
                            self.selectedAssetsSet.insert(asset.localIdentifier)
                            self.notifySelectionChanged()
                            self.updateNavigationBarForSelection()
                        }
                        
                        // 2. UI 업데이트
                        if !self.isShowingOnlySelected {
                            let itemIndex = self.shouldShowCamera ? 1 : 0
                            self.collectionView.performBatchUpdates({
                                self.collectionView.insertItems(at: [IndexPath(item: itemIndex, section: 0)])
                            }, completion: { _ in
                                // 배치 업데이트 완료 후, 기존 선택된 셀들의 번호도 확실히 갱신
                                self.updateSelectedCellNumbers()
                            })
                        } else {
                            self.collectionView.reloadData()
                        }
                        
                        // 구형(Legacy) 카메라인 경우 닫아주기 (커스텀 카메라는 알아서 닫힘)
                        if let pvc = self.presentedViewController, pvc is UIImagePickerController {
                            self.dismiss(animated: true)
                        }
                        return
                    }
                    
                    // 단일 선택 모드(maxSelection == 1)인 경우: 상태 추가 후 즉시 반환
                    if !self.assets.contains(asset) {
                        self.assets.insert(asset, at: 0)
                    }
                }
                
                // 단일 선택 모드(maxSelection == 1)인 경우: 기존처럼 즉시 반환하고 갤러리 종료
                self.hasReturnedImages = true
                self.onImagesSelected?([(finalAsset, image)])
                self.dismiss(animated: true)
            }
        }
    }


    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // 시트 전환 중에는 PHImageManager 호출만 억제 (두둑 방지)
        // 날짜 인디케이터는 항상 업데이트 (첫 스크롤에서도 정보가 표시돼야 함)
        if !isSheetTransitioning {
            updateCachedAssets()
        }
        updateDateScrollIndicator()
    }
    
    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            scheduleDateIndicatorHide()
        }
        // 손가락을 뉀 순간: 시트가 10% 이상 올라가 있으면 full로 스냅
        // (viewDidLayoutSubviews에서 실행하면 제스처 충돌로 ‘턴’ 현상 발생와 주의)
        guard #available(iOS 15.0, *),
              let sheet = navigationController?.sheetPresentationController,
              sheet.selectedDetentIdentifier != .large,
              initialSheetHeight > 0 else { return }
        
        let screenH = UIScreen.main.bounds.height
        let snapThreshold = initialSheetHeight + (screenH - initialSheetHeight) * 0.10
        
        guard view.bounds.height > snapThreshold else { return }
        
        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 1.0,   // 임계 감쇼: 오버슈트/spring-back 없음
            initialSpringVelocity: 0.5,
            options: [.allowUserInteraction]
        ) {
            sheet.animateChanges {
                sheet.selectedDetentIdentifier = .large
            }
        }
    }
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // 🔧 수정: 스크롤이 완전히 멈춘 후 타이머 재설정
        // (updateDateScrollIndicator에서 이미 설정되지만 최종 확인용)
        scheduleDateIndicatorHide()
    }
    
    // 모든 셀은 정사각형
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        // 캐싱된 너비 우선 사용 (레이아웃 점프 방지)
        // - 하프 모달 → 풀스크린 전환 중 bounds가 변하는 동안에도 일관된 크기 유지
        if let cached = cachedCellWidth {
            return CGSize(width: cached, height: cached)
        }
        
        // 캐시가 없는 경우 계산 후 저장 (floor 필수)
        // view.bounds.width 기준 사용: collectionView.bounds는 애니메이션 중간 프레임에서
        // 잘못된 값이 캐싱될 수 있어 안정적인 view.bounds를 사용
        let spacing: CGFloat = 1
        let columns: CGFloat = 3
        let totalSpacing = spacing * (columns - 1)
        let baseWidth = view.bounds.width > 0 ? view.bounds.width : collectionView.bounds.width
        let width = floor((baseWidth - totalSpacing) / columns)
        cachedCellWidth = width
        
        return CGSize(width: width, height: width)
    }
    
    // 시트 높이/너비 변화 감지
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        let currentHeight = view.bounds.height
        let currentWidth = view.bounds.width
        
        // 너비 변화 시 cachedCellWidth 즉시 갱신
        if currentWidth > 0 && currentWidth != previousViewWidth {
            previousViewWidth = currentWidth
            let spacing: CGFloat = 1
            let columns: CGFloat = 3
            let totalSpacing = spacing * (columns - 1)
            let newCellWidth = floor((currentWidth - totalSpacing) / columns)
            cachedCellWidth = newCellWidth
            let scale = UIScreen.main.scale
            thumbnailSize = CGSize(width: newCellWidth * scale, height: newCellWidth * scale)
            collectionView.collectionViewLayout.invalidateLayout()
        }
        
        guard currentHeight > 0, currentHeight != previousViewHeight else { return }
        previousViewHeight = currentHeight
        
        // 성능 최적화: 시트 전환 중 버벅거림 방지를 위한 플래그만 유지
        // 억지로 애니메이션을 조작(animateChanges)하면 네이티브 제스처와 충돌하여
        // 결국 점프하거나 동작이 꼬이는 현상이 발생하므로 네이티브 동작에 맡김.
        
        // isSheetTransitioning 플래그 세팅
        isSheetTransitioning = true
        sheetTransitionEndWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.isSheetTransitioning = false
        }
        sheetTransitionEndWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
    
    // 기기 회전 시 셀 너비 캐시 갱신
    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self = self else { return }
            let spacing: CGFloat = 1
            let columns: CGFloat = 3
            let totalSpacing = spacing * (columns - 1)
            let newWidth = floor((size.width - totalSpacing) / columns)
            self.cachedCellWidth = newWidth
            let scale = UIScreen.main.scale
            self.thumbnailSize = CGSize(width: newWidth * scale, height: newWidth * scale)
            self.collectionView.collectionViewLayout.invalidateLayout()
        })
    }
}

// MARK: - UISheetPresentationControllerDelegate

@available(iOS 15.0, *)
extension GalleryBaseViewController: UISheetPresentationControllerDelegate {
    public func sheetPresentationControllerDidChangeSelectedDetentIdentifier(
        _ sheetPresentationController: UISheetPresentationController
    ) {
        // 시트가 특정 detent에 완전히 안착했을 때 즉시 전환 플래그 해제
        // → 0.2s 타이머 대기 없이 즉시 updateCachedAssets() 재개 (스냅 현상 제거)
        sheetTransitionEndWorkItem?.cancel()
        isSheetTransitioning = false
        updateCachedAssets()
    }
}

// MARK: - UICollectionViewDataSourcePrefetching

extension GalleryBaseViewController: UICollectionViewDataSourcePrefetching {
    public func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let assets = indexPaths.compactMap { indexPath -> PHAsset? in
            guard indexPath.item < self.assets.count else { return nil }
            return self.assets[indexPath.item]
        }
        
        photoManager.startCachingImages(for: assets, targetSize: thumbnailSize)
    }
    
    public func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let assets = indexPaths.compactMap { indexPath -> PHAsset? in
            guard indexPath.item < self.assets.count else { return nil }
            return self.assets[indexPath.item]
        }
        
        photoManager.stopCachingImages(for: assets, targetSize: thumbnailSize)
    }
}

// MARK: - TelegramGalleryLayoutDelegate

extension GalleryBaseViewController: TelegramGalleryLayoutDelegate {
    public func isCameraCell(at indexPath: IndexPath) -> Bool {
        return shouldShowCamera && indexPath.item == 0 && !isShowingOnlySelected
    }
}

// MARK: - TelegramGalleryLayout

public protocol TelegramGalleryLayoutDelegate: AnyObject {
    func isCameraCell(at indexPath: IndexPath) -> Bool
}

public class TelegramGalleryLayout: UICollectionViewLayout {
    
    public weak var delegate: TelegramGalleryLayoutDelegate?
    
    public var numberOfColumns: Int = 3
    public var cellPadding: CGFloat = 1
    
    private var cache: [UICollectionViewLayoutAttributes] = []
    private var contentHeight: CGFloat = 0
    private var contentWidth: CGFloat {
        guard let collectionView = collectionView else { return 0 }
        let insets = collectionView.contentInset
        return collectionView.bounds.width - (insets.left + insets.right)
    }
    
    public override func prepare() {
        guard let collectionView = collectionView else { return }
        
        cache.removeAll()
        contentHeight = 0
        
        // 3열일 때 간격이 2개이므로: 전체 너비에서 간격(2*cellPadding)을 빼고 3으로 나눔
        let columnWidth = (contentWidth - cellPadding * CGFloat(numberOfColumns - 1)) / CGFloat(numberOfColumns)
        var yOffset: [CGFloat] = Array(repeating: 0, count: numberOfColumns)
        
        for item in 0..<collectionView.numberOfItems(inSection: 0) {
            let indexPath = IndexPath(item: item, section: 0)
            let isCamera = delegate?.isCameraCell(at: indexPath) ?? false
            
            // 카메라는 폭은 1칸, 높이는 2칸(+간격) 크기
            let height = isCamera ? (columnWidth * 2 + cellPadding) : columnWidth
            let width = columnWidth
            
            var column = 0
            if isCamera {
                column = 0 // 카메라는 항상 첫 번째 열에 강제
            } else {
                // 가장 높이가 낮은(짧은) 열을 찾아서 배치
                var minOffset = yOffset[0]
                column = 0
                for i in 1..<numberOfColumns {
                    if yOffset[i] < minOffset {
                        minOffset = yOffset[i]
                        column = i
                    }
                }
            }
            
            let x = CGFloat(column) * (columnWidth + cellPadding)
            let y = yOffset[column]
            
            let frame = CGRect(x: x, y: y, width: width, height: height)
            let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            attributes.frame = frame
            cache.append(attributes)
            
            contentHeight = max(contentHeight, frame.maxY)
            yOffset[column] = y + height + cellPadding
        }
    }
    
    public override var collectionViewContentSize: CGSize {
        return CGSize(width: contentWidth, height: contentHeight)
    }
    
    public override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        return cache.filter { $0.frame.intersects(rect) }
    }
    
    public override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.item < cache.count else { return nil }
        return cache[indexPath.item]
    }
    
    public override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView = collectionView else { return false }
        // 가로 폭이 변경되었을 때만 레이아웃 재계산 (스크롤 시에는 재계산 방지)
        return newBounds.width != collectionView.bounds.width
    }
    
    public override func invalidateLayout() {
        super.invalidateLayout()
        cache.removeAll()
    }
}

