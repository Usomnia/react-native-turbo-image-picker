import Foundation
import UIKit

public class ImageProcessor {
    public static let shared = ImageProcessor()
    
    /// Checks license and applies evaluation watermark if license is invalid.
    /// This method is intended to be called from the RN bridge layer.
    public func applyWatermarkIfNeeded(_ image: UIImage) -> UIImage {
        if !LicenseManager.shared.isValidLicense() {
            return applyEvaluationWatermark(to: image)
        }
        return image
    }
    
    /// Applies a repeating diagonal "Turbo Image Picker" watermark pattern.
    public func applyEvaluationWatermark(to image: UIImage) -> UIImage {
        let text = "Turbo Image Picker"
        let fontSize = max(20.0, min(image.size.width, image.size.height) / 15.0)
        
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.5)
        shadow.shadowOffset = CGSize(width: 1, height: 1)
        shadow.shadowBlurRadius = 3
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: UIColor.white.withAlphaComponent(0.25),
            .shadow: shadow
        ]
        
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // Prevent massive memory inflation on Retina devices
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { context in
            image.draw(at: .zero)
            
            let cgContext = context.cgContext
            
            let diagonal = hypot(image.size.width, image.size.height)
            
            cgContext.saveGState()
            cgContext.translateBy(x: image.size.width / 2, y: image.size.height / 2)
            cgContext.rotate(by: -35.0 * .pi / 180.0)
            cgContext.translateBy(x: -diagonal / 2, y: -diagonal / 2)
            
            let stepX = textSize.width * 1.5
            let stepY = textSize.height * 3.5
            
            var y: CGFloat = 0
            var row = 0
            while y < diagonal + stepY {
                var x: CGFloat = 0
                let offset = (row % 2 == 0) ? 0 : stepX / 2
                while x < diagonal + stepX {
                    attributedText.draw(at: CGPoint(x: x + offset, y: y))
                    x += stepX
                }
                y += stepY
                row += 1
            }
            
            cgContext.restoreGState()
        }
    }
}
