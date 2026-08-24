import Foundation
import UIKit
import CryptoKit

public class LicenseManager {
    public static let shared = LicenseManager()
    
    private let secretKey = "43664971c55c33ac701caa010c3ddcd12ef6ba082c0e83cf6aa8f5ba3c600340"
    private(set) var isLicensed = false
    
    public func initialize(with key: String) -> Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else { return false }
        
        let secretData = Data(secretKey.utf8)
        let symmetricKey = SymmetricKey(data: secretData)
        let messageData = Data(bundleId.utf8)
        
        let hmac = HMAC<SHA256>.authenticationCode(for: messageData, using: symmetricKey)
        let expectedKey = hmac.map { String(format: "%02hhx", $0) }.joined()
        
        if key == expectedKey {
            isLicensed = true
            return true
        }
        
        isLicensed = false
        return false
    }
    
    public func isValidLicense() -> Bool {
        return isLicensed
    }
    
    func showLicenseAlert(in viewController: UIViewController) {
        let alert = UIAlertController(title: "Unauthorized License", message: "This RNTurboImagePicker library is strictly licensed By Usomnia. Contact: contact@usomnia.co.kr", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        
        var topController = viewController
        while let presented = topController.presentedViewController {
            topController = presented
        }
        topController.present(alert, animated: true)
    }
}
