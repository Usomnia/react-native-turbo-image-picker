import UIKit
import Photos

class ImageEditorTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let isPresenting: Bool
    let sourceFrame: CGRect
    let sourceImage: UIImage?
    let uncroppedImage: UIImage?
    let assetAspectRatio: CGFloat
    let asset: PHAsset?
    let frameProvider: ((PHAsset) -> CGRect?)?

    init(isPresenting: Bool, sourceFrame: CGRect, sourceImage: UIImage?, uncroppedImage: UIImage?, assetAspectRatio: CGFloat, asset: PHAsset? = nil, frameProvider: ((PHAsset) -> CGRect?)? = nil) {
        self.isPresenting = isPresenting
        self.sourceFrame = sourceFrame
        self.sourceImage = sourceImage
        self.uncroppedImage = uncroppedImage
        self.assetAspectRatio = assetAspectRatio
        self.asset = asset
        self.frameProvider = frameProvider
        super.init()
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.35
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let containerView = transitionContext.containerView
        
        if isPresenting {
            guard let toView = transitionContext.view(forKey: .to) else {
                transitionContext.completeTransition(false)
                return
            }
            
            // 배경 페이드인을 위한 딤 뷰 (에디터 배경색과 동일하게 맞춤)
            let dimView = UIView(frame: containerView.bounds)
            dimView.backgroundColor = UIColor.editorBackground
            let imageView = UIImageView(image: uncroppedImage ?? sourceImage)
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            
            imageView.frame = containerView.convert(sourceFrame, from: nil)
            
            // 💡 뷰 추가 순서: dimView -> imageView -> toView
            // 이렇게 하면 toView(에디터)의 상/하단 툴바가 애니메이션되는 이미지 위로 올라옵니다.
            dimView.alpha = 0
            containerView.addSubview(dimView)
            containerView.addSubview(imageView)
            
            containerView.addSubview(toView)
            toView.alpha = 1.0 // 투명도를 1로 유지하여 내부 구조를 활용
            
            // 1. toView의 배경색을 일시적으로 투명하게 만듦 (배경은 dimView가 담당)
            let originalToViewBg = toView.backgroundColor
            toView.backgroundColor = .clear
            
            // 2. 에디터의 툴바 및 collectionView 초기화
            var toolbars = [UIView]()
            var collectionView: UICollectionView? = nil
            if let editorVC = transitionContext.viewController(forKey: .to) as? ImageEditorViewController {
                editorVC.view.layoutIfNeeded() // UI 레이아웃 강제 갱신
                collectionView = editorVC.collectionView
                // 트랜지션 중에는 목적지(에디터)의 이미지가 미리 보이지 않도록 숨김
                collectionView?.isHidden = true
                for subview in toView.subviews {
                    if subview != collectionView {
                        toolbars.append(subview)
                        subview.alpha = 0
                    }
                }
            }
            
            // 고해상도 이미지를 비동기로 불러와 애니메이션 도중에 바꿔치기 (해상도 저하 방지)
            if let asset = self.asset {
                let options = PHImageRequestOptions()
                options.deliveryMode = .opportunistic
                options.isSynchronous = false
                let targetSize = CGSize(width: containerView.bounds.width * 2, height: containerView.bounds.height * 2)
                PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { img, info in
                    if let img = img {
                        imageView.image = img
                    }
                }
            }
            
            // 화면 크기에 맞게 aspect fit 했을 때의 최종 프레임 계산
            let screenBounds = containerView.bounds
            var finalWidth = screenBounds.width
            var finalHeight = finalWidth / assetAspectRatio
            
            if finalHeight > screenBounds.height {
                finalHeight = screenBounds.height
                finalWidth = finalHeight * assetAspectRatio
            }
            let finalX = (screenBounds.width - finalWidth) / 2.0
            let finalY = (screenBounds.height - finalHeight) / 2.0
            
            var absoluteFinalFrame = CGRect(x: finalX, y: finalY, width: finalWidth, height: finalHeight)
            
            UIView.animate(withDuration: transitionDuration(using: transitionContext), delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: .curveEaseInOut) {
                dimView.alpha = 1.0
                for tb in toolbars {
                    tb.alpha = 1.0
                }
                // frame을 최종 이미지 크기로 변경하면 scaleAspectFill 속성 덕분에 잘렸던 원본의 좌우/상하가 자연스럽게 나타남
                imageView.frame = absoluteFinalFrame
                imageView.contentMode = .scaleAspectFit
            } completion: { _ in
                toView.backgroundColor = originalToViewBg
                // 트랜지션 완료 후 목적지의 이미지뷰 렌더링 활성화
                collectionView?.isHidden = false
                dimView.removeFromSuperview()
                imageView.removeFromSuperview()
                transitionContext.completeTransition(true)
            }
        } else {
            guard let fromView = transitionContext.view(forKey: .from) else {
                transitionContext.completeTransition(false)
                return
            }
            
            // 줌 아웃 트랜지션을 위한 임시 이미지 뷰
            // 편집 화면에서 돌아올 때는 편집 화면의 고해상도 이미지를 최우선으로 사용
            var dismissImage = uncroppedImage ?? sourceImage
            if let fromVC = transitionContext.viewController(forKey: .from) as? ImageEditorViewController,
               let highResImage = fromVC.currentEditorCell?.imageView.image {
                dismissImage = highResImage
            }
            
            let imageView = UIImageView(image: dismissImage)
            // 에디터 뷰의 이미지 뷰와 동일한 aspect ratio의 뷰에서 시작
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            
            // 편집 화면의 fromView.bounds 크기 중 실제 이미지가 표시되는 영역(aspectFit) 계산
            let screenBounds = fromView.bounds
            var startWidth = screenBounds.width
            var startHeight = startWidth / assetAspectRatio
            if startHeight > screenBounds.height {
                startHeight = screenBounds.height
                startWidth = startHeight * assetAspectRatio
            }
            let startX = (screenBounds.width - startWidth) / 2.0
            let startY = (screenBounds.height - startHeight) / 2.0
            
            imageView.bounds = CGRect(x: 0, y: 0, width: startWidth, height: startHeight)
            imageView.center = CGPoint(x: startX + startWidth / 2.0, y: startY + startHeight / 2.0)
            
            // 사용자가 드래그한 트랜스폼 적용
            imageView.transform = fromView.transform
            
            // 💡 뷰 추가 위치: fromView(에디터) 뒤쪽으로 추가해서 에디터 툴바 뒤로 애니메이션 되게 함
            containerView.insertSubview(imageView, belowSubview: fromView)
            
            // 원본 이미지 숨기기 (고스트 현상 방지)
            var currentAsset: PHAsset? = self.asset
            if let fromVC = transitionContext.viewController(forKey: .from) as? ImageEditorViewController {
                fromVC.currentEditorCell?.imageView.isHidden = true
                if !fromVC.allAssets.isEmpty && fromVC.currentIndex < fromVC.allAssets.count {
                    currentAsset = fromVC.allAssets[fromVC.currentIndex]
                }
            } else if let fromVC = transitionContext.viewController(forKey: .from) as? ProfileCropViewController {
                fromVC.imageView.isHidden = true
            }
            
            var targetFrame: CGRect?
            if let currentAsset = currentAsset {
                targetFrame = self.frameProvider?(currentAsset)
            }
            
            let isOffscreen = (targetFrame == nil)
            // 화면 밖이면 그냥 아래로 떨어지도록 프레임 설정
            let finalFrame = targetFrame ?? CGRect(x: startX, y: screenBounds.height, width: startWidth, height: startHeight)
            
            UIView.animate(withDuration: transitionDuration(using: transitionContext), delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: .curveEaseInOut) {
                fromView.alpha = 0
                imageView.transform = .identity
                imageView.frame = finalFrame
                if !isOffscreen {
                    imageView.contentMode = .scaleAspectFill
                }
            } completion: { _ in
                imageView.removeFromSuperview()
                transitionContext.completeTransition(true)
            }
        }
    }
}

@objc public class ImageEditorTransitionDelegate: NSObject, UIViewControllerTransitioningDelegate {
    public var sourceFrame: CGRect = .zero
    public var sourceImage: UIImage?
    public var uncroppedImage: UIImage?
    public var assetAspectRatio: CGFloat = 1.0
    public var asset: PHAsset?
    public var frameProvider: ((PHAsset) -> CGRect?)?
    public var disablePresentationAnimation: Bool = false

    public override init() {
        super.init()
    }

    public func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        if presented is ProfileCropViewController || disablePresentationAnimation {
            return nil
        }
        return ImageEditorTransitionAnimator(isPresenting: true, sourceFrame: sourceFrame, sourceImage: sourceImage, uncroppedImage: uncroppedImage, assetAspectRatio: assetAspectRatio, asset: asset, frameProvider: frameProvider)
    }

    public func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return ImageEditorTransitionAnimator(isPresenting: false, sourceFrame: sourceFrame, sourceImage: sourceImage, uncroppedImage: uncroppedImage, assetAspectRatio: assetAspectRatio, asset: asset, frameProvider: frameProvider)
    }
}
