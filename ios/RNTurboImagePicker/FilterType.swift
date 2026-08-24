import UIKit
import CoreImage

public struct ImageFilter {
    public let id: String
    public let name: String
    
    // intensity is 0.0 to 1.0
    public let apply: (CIImage, CGFloat) -> CIImage?
}

public class FilterManager {
    public static let shared = FilterManager()
    
    public let context = CIContext(options: [.useSoftwareRenderer: false])
    
    // 🚀 성능 최적화: CIFilter 인스턴스 캐시 (슬라이더 드래그마다 재생성 방지)
    private var filterCache: [String: CIFilter] = [:]
    
    /// 캐시된 CIFilter 인스턴스를 반환하거나 새로 생성
    func getOrCreateFilter(named name: String) -> CIFilter? {
        if let cached = filterCache[name] {
            return cached
        }
        guard let filter = CIFilter(name: name) else { return nil }
        filterCache[name] = filter
        return filter
    }
    public let filters: [ImageFilter] = [
        ImageFilter(id: "original", name: "원본") { image, _ in return image },
        
        ImageFilter(id: "soft", name: "부드러운") { image, intensity in
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(1.0 - (intensity * 0.1), forKey: kCIInputContrastKey)
            filter?.setValue(1.0 + (intensity * 0.05), forKey: kCIInputSaturationKey)
            return filter?.outputImage
        },
        
        ImageFilter(id: "clean", name: "깨끗한") { image, intensity in
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(1.0 + (intensity * 0.15), forKey: kCIInputContrastKey)
            filter?.setValue(1.0 + (intensity * 0.1), forKey: kCIInputSaturationKey)
            return filter?.outputImage
        },
        
        ImageFilter(id: "winter", name: "그 겨울") { image, intensity in
            // Use CIColorMatrix for color tinting (cool blue)
            let filter = CIFilter(name: "CIColorMatrix")
            filter?.setValue(image, forKey: kCIInputImageKey)
            let b = intensity * 0.2
            filter?.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
            filter?.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
            filter?.setValue(CIVector(x: 0, y: 0, z: 1+b, w: 0), forKey: "inputBVector")
            return filter?.outputImage
        },
        
        ImageFilter(id: "warm", name: "따스한") { image, intensity in
            let filter = CIFilter(name: "CITemperatureAndTint")
            filter?.setValue(image, forKey: kCIInputImageKey)
            // Neutral is 6500, Warm is higher
            let targetTemp = 6500.0 + (intensity * 2000.0)
            filter?.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            filter?.setValue(CIVector(x: targetTemp, y: 0), forKey: "inputTargetNeutral")
            return filter?.outputImage
        },
        
        ImageFilter(id: "shining", name: "빛나는") { image, intensity in
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(intensity * 0.1, forKey: kCIInputBrightnessKey)
            filter?.setValue(1.0 + (intensity * 0.1), forKey: kCIInputContrastKey)
            filter?.setValue(1.0 + (intensity * 0.2), forKey: kCIInputSaturationKey)
            return filter?.outputImage
        },
        
        ImageFilter(id: "mono", name: "흑백") { image, intensity in
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(1.0 - intensity, forKey: kCIInputSaturationKey)
            return filter?.outputImage
        },
        
        ImageFilter(id: "vintage", name: "빈티지") { image, intensity in
            let filter = CIFilter(name: "CISepiaTone")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(intensity * 0.8, forKey: kCIInputIntensityKey)
            return filter?.outputImage
        },
        
        ImageFilter(id: "fade", name: "페이드") { image, intensity in
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(1.0 - (intensity * 0.2), forKey: kCIInputContrastKey)
            return filter?.outputImage
        },
        
        ImageFilter(id: "dramatic", name: "극적인") { image, intensity in
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(1.0 + (intensity * 0.4), forKey: kCIInputContrastKey)
            filter?.setValue(1.0 - (intensity * 0.2), forKey: kCIInputBrightnessKey)
            return filter?.outputImage
        },
        
        ImageFilter(id: "fresh", name: "싱그러운") { image, intensity in
            let filter = CIFilter(name: "CIVibrance")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(intensity * 1.5, forKey: "inputAmount")
            return filter?.outputImage
        },
        
        ImageFilter(id: "vibrant", name: "생동감") { image, intensity in
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(1.0 + (intensity * 0.5), forKey: kCIInputSaturationKey)
            return filter?.outputImage
        },
        
        ImageFilter(id: "cinematic", name: "영화같은") { image, intensity in
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(1.0 + (intensity * 0.2), forKey: kCIInputContrastKey)
            filter?.setValue(1.0 - (intensity * 0.1), forKey: kCIInputSaturationKey)
            return filter?.outputImage
        },
        
        ImageFilter(id: "instant", name: "아날로그") { image, intensity in
            return FilterManager.blendEffect("CIPhotoEffectInstant", image: image, intensity: intensity)
        },
        
        ImageFilter(id: "noir", name: "누아르") { image, intensity in
            return FilterManager.blendEffect("CIPhotoEffectNoir", image: image, intensity: intensity)
        },
        
        ImageFilter(id: "process", name: "프로세스") { image, intensity in
            return FilterManager.blendEffect("CIPhotoEffectProcess", image: image, intensity: intensity)
        },
        
        ImageFilter(id: "tonal", name: "토널") { image, intensity in
            return FilterManager.blendEffect("CIPhotoEffectTonal", image: image, intensity: intensity)
        },
        
        ImageFilter(id: "transfer", name: "트랜스퍼") { image, intensity in
            return FilterManager.blendEffect("CIPhotoEffectTransfer", image: image, intensity: intensity)
        },
        
        ImageFilter(id: "chrome", name: "크롬") { image, intensity in
            return FilterManager.blendEffect("CIPhotoEffectChrome", image: image, intensity: intensity)
        },
        
        ImageFilter(id: "vignette", name: "비네팅") { image, intensity in
            let filter = CIFilter(name: "CIVignette")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(intensity * 1.5, forKey: kCIInputIntensityKey)
            filter?.setValue(intensity * 1.0, forKey: kCIInputRadiusKey)
            return filter?.outputImage
        }
    ]
    
    static func blendEffect(_ name: String, image: CIImage, intensity: CGFloat) -> CIImage? {
        guard let filter = FilterManager.shared.getOrCreateFilter(named: name) else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        guard let fgImage = filter.outputImage else { return image }
        
        if intensity >= 1.0 { return fgImage }
        if intensity <= 0.0 { return image }
        
        // Use CIColorMatrix to adjust alpha of fgImage
        guard let alphaFilter = FilterManager.shared.getOrCreateFilter(named: "CIColorMatrix") else { return fgImage }
        alphaFilter.setValue(fgImage, forKey: kCIInputImageKey)
        alphaFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: intensity), forKey: "inputAVector")
        guard let blendedFg = alphaFilter.outputImage else { return fgImage }
        
        guard let composite = FilterManager.shared.getOrCreateFilter(named: "CISourceOverCompositing") else { return fgImage }
        composite.setValue(blendedFg, forKey: kCIInputImageKey)
        composite.setValue(image, forKey: kCIInputBackgroundImageKey)
        return composite.outputImage
    }
}
