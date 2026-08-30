import UIKit

public class ZoomTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    public var isPresenting: Bool = true
    public var sourceRect: CGRect = .zero
    
    // 이 정보들이 있으면 완벽한 crop -> aspectFit 전환이 가능합니다.
    public var sourceImage: UIImage? = nil
    public var imageAspectRatio: CGFloat? = nil
    public var animationType: String = "zoom"
    public var closeAnimationType: String? = nil
    
    public var sourceBorderRadius: CGFloat = 0
    public var sourceBorderCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    
    public func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.37
    }
    
    public func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let containerView = transitionContext.containerView
        
        if isPresenting {
            guard let toView = transitionContext.view(forKey: .to),
                  let toVC = transitionContext.viewController(forKey: .to) as? RemoteImageViewerViewController else {
                transitionContext.completeTransition(false)
                return
            }
            
            containerView.addSubview(toView)
            
            // 1. 필요한 정보 수집 (캐시된 이미지 또는 외부에서 주입된 이미지)
            var targetImage = self.sourceImage
            if targetImage == nil, toVC.imageUrls.indices.contains(toVC.currentIndex) {
                let urlString = toVC.imageUrls[toVC.currentIndex]
                targetImage = ViewerImageCache.shared.getMemoryImage(for: urlString) ?? ViewerImageCache.shared.getDiskImageSynchronously(for: urlString)
                if targetImage == nil, urlString.hasPrefix("file://"), let url = URL(string: urlString) {
                    targetImage = UIImage(contentsOfFile: url.path)
                }
            }
            
            // Fallback: If targetImage is still nil, capture a snapshot from the screen
            if targetImage == nil, let fromView = transitionContext.view(forKey: .from), sourceRect.width > 0, sourceRect.height > 0 {
                UIGraphicsBeginImageContextWithOptions(sourceRect.size, false, 0.0)
                if let context = UIGraphicsGetCurrentContext() {
                    context.translateBy(x: -sourceRect.origin.x, y: -sourceRect.origin.y)
                    fromView.layer.render(in: context)
                    targetImage = UIGraphicsGetImageFromCurrentImageContext()
                }
                UIGraphicsEndImageContext()
            }
            
            let ratio = imageAspectRatio ?? (targetImage != nil ? (targetImage!.size.width / max(1, targetImage!.size.height)) : 1.0)
            
            let finalScreenFrame = transitionContext.finalFrame(for: toVC)
            var finalImageFrame = finalScreenFrame
            
            let screenRatio = finalScreenFrame.width / max(1, finalScreenFrame.height)
            if ratio > screenRatio {
                let h = finalScreenFrame.width / ratio
                finalImageFrame = CGRect(x: 0, y: (finalScreenFrame.height - h) / 2, width: finalScreenFrame.width, height: h)
            } else {
                let w = finalScreenFrame.height * ratio
                finalImageFrame = CGRect(x: (finalScreenFrame.width - w) / 2, y: 0, width: w, height: finalScreenFrame.height)
            }
            
            if animationType == "fade" {
                toView.alpha = 0
                UIView.animate(withDuration: transitionDuration(using: transitionContext),
                               delay: 0,
                               options: [.curveEaseOut, .allowUserInteraction],
                               animations: {
                    toView.alpha = 1
                }, completion: { finished in
                    transitionContext.completeTransition(finished && !transitionContext.transitionWasCancelled)
                })
                return
            } else if animationType == "slide" {
                toView.frame = CGRect(x: 0, y: containerView.bounds.height, width: containerView.bounds.width, height: containerView.bounds.height)
                UIView.animate(withDuration: transitionDuration(using: transitionContext),
                               delay: 0,
                               usingSpringWithDamping: 1.0,
                               initialSpringVelocity: 0,
                               options: [.curveEaseOut, .allowUserInteraction],
                               animations: {
                    toView.frame = containerView.bounds
                }, completion: { finished in
                    transitionContext.completeTransition(finished && !transitionContext.transitionWasCancelled)
                })
                return
            }
            
            // 2. 줌 임시 뷰 생성
            let dummyView = UIImageView(frame: sourceRect)
            dummyView.contentMode = .scaleAspectFill
            dummyView.clipsToBounds = true
            dummyView.image = targetImage
            dummyView.backgroundColor = .clear
            dummyView.layer.maskedCorners = sourceBorderCorners
            dummyView.layer.cornerRadius = sourceBorderRadius // 썸네일 라운드 (옵션)
            
            toView.insertSubview(dummyView, belowSubview: toVC.topBar)
            
            // 3. ToVC 상태 초기화 (숨김)
            toVC.scrollView.alpha = 0
            toVC.topBar.alpha = 0
            toVC.bottomContainer.alpha = 0
            toView.backgroundColor = .clear
            
            UIView.animate(withDuration: transitionDuration(using: transitionContext),
                           delay: 0,
                           usingSpringWithDamping: 1.0,
                           initialSpringVelocity: 0,
                           options: [.curveEaseOut, .allowUserInteraction],
                           animations: {
                // 더미 뷰 프레임을 최종 크기로
                dummyView.frame = finalImageFrame
                dummyView.layer.cornerRadius = 0
                toView.backgroundColor = .black
                
                toVC.topBar.alpha = 1
                toVC.bottomContainer.alpha = 1
            }, completion: { finished in
                toVC.scrollView.alpha = 1
                dummyView.removeFromSuperview()
                transitionContext.completeTransition(finished && !transitionContext.transitionWasCancelled)
            })
            
        } else {
            guard let fromVC = transitionContext.viewController(forKey: .from) as? RemoteImageViewerViewController,
                  let fromView = transitionContext.view(forKey: .from) else {
                transitionContext.completeTransition(false)
                return
            }
            
            // Dismiss 
            var targetImage = self.sourceImage
            if targetImage == nil, fromVC.imageUrls.indices.contains(fromVC.currentIndex) {
                let urlString = fromVC.imageUrls[fromVC.currentIndex]
                targetImage = ViewerImageCache.shared.getMemoryImage(for: urlString) ?? ViewerImageCache.shared.getDiskImageSynchronously(for: urlString)
                if targetImage == nil, urlString.hasPrefix("file://"), let url = URL(string: urlString) {
                    targetImage = UIImage(contentsOfFile: url.path)
                }
            }
            let ratio = imageAspectRatio ?? (targetImage != nil ? (targetImage!.size.width / max(1, targetImage!.size.height)) : 1.0)
            
            let finalScreenFrame = fromView.bounds
            var finalImageFrame = finalScreenFrame
            let screenRatio = finalScreenFrame.width / max(1, finalScreenFrame.height)
            if ratio > screenRatio {
                let h = finalScreenFrame.width / ratio
                finalImageFrame = CGRect(x: 0, y: (finalScreenFrame.height - h) / 2, width: finalScreenFrame.width, height: h)
            } else {
                let w = finalScreenFrame.height * ratio
                finalImageFrame = CGRect(x: (finalScreenFrame.width - w) / 2, y: 0, width: w, height: finalScreenFrame.height)
            }
            
            let activeAnimType = closeAnimationType ?? animationType
            if activeAnimType == "fade" {
                UIView.animate(withDuration: transitionDuration(using: transitionContext),
                               delay: 0,
                               options: [.curveEaseOut, .allowUserInteraction],
                               animations: {
                    fromView.alpha = 0
                }, completion: { finished in
                    if !transitionContext.transitionWasCancelled { fromView.removeFromSuperview() }
                    transitionContext.completeTransition(finished && !transitionContext.transitionWasCancelled)
                })
                return
            } else if activeAnimType == "slide" {
                UIView.animate(withDuration: transitionDuration(using: transitionContext),
                               delay: 0,
                               usingSpringWithDamping: 1.0,
                               initialSpringVelocity: 0,
                               options: [.curveEaseOut, .allowUserInteraction],
                               animations: {
                    fromView.frame = CGRect(x: 0, y: containerView.bounds.height, width: containerView.bounds.width, height: containerView.bounds.height)
                }, completion: { finished in
                    if !transitionContext.transitionWasCancelled { fromView.removeFromSuperview() }
                    transitionContext.completeTransition(finished && !transitionContext.transitionWasCancelled)
                })
                return
            }
            
            // 줌 트랜지션 로직
            // 팬 제스처로 인해 scrollView가 이동/축소(transform) 되었을 수 있으므로 containerView 좌표계로 변환합니다.
            let startingFrame = fromVC.scrollView.convert(finalImageFrame, to: containerView)
            
            // 현재 스크롤 뷰가 확대되어 있다면 반영 (옵션)
            let dummyView = UIImageView(frame: startingFrame)
            dummyView.contentMode = .scaleAspectFill
            dummyView.clipsToBounds = true
            dummyView.image = targetImage
            if #available(iOS 11.0, *) {
                dummyView.layer.maskedCorners = sourceBorderCorners
            }
            dummyView.layer.cornerRadius = 0
            
            fromView.transform = .identity
            fromVC.scrollView.transform = .identity
            fromView.frame = containerView.bounds
            
            fromView.insertSubview(dummyView, belowSubview: fromVC.topBar)
            fromVC.scrollView.alpha = 0
            fromView.backgroundColor = .clear
            fromView.alpha = 1.0 // 팬 제스처로 인해 낮아진 투명도 복구
            
            UIView.animate(withDuration: transitionDuration(using: transitionContext),
                           delay: 0,
                           usingSpringWithDamping: 1.0,
                           initialSpringVelocity: 0,
                           options: [.curveEaseOut, .allowUserInteraction],
                           animations: {
                dummyView.frame = self.sourceRect
                dummyView.layer.cornerRadius = self.sourceBorderRadius
                
                fromVC.topBar.alpha = 0
                fromVC.bottomContainer.alpha = 0
            }, completion: { finished in
                dummyView.removeFromSuperview()
                if !transitionContext.transitionWasCancelled {
                    fromView.removeFromSuperview()
                }
                transitionContext.completeTransition(finished && !transitionContext.transitionWasCancelled)
            })
        }
    }
}
