import UIKit
import CoreText

final class FontHelper {
    /// Thread-safe one-time font registration using static let + closure.
    /// The closure executes exactly once, even across multiple threads.
    private static let _register: Void = {
        let bundle = Bundle(for: FontHelper.self)

        // Register Pretendard-SemiBold
        if let url = bundle.url(forResource: "Pretendard-SemiBold", withExtension: "otf") {
            var errorRef: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &errorRef) {
                #if DEBUG
                print("FontHelper: Failed to register Pretendard-SemiBold: \(String(describing: errorRef))")
                #endif
            } else {
                #if DEBUG
                print("FontHelper: Successfully registered Pretendard-SemiBold")
                #endif
            }
        } else {
            #if DEBUG
            print("FontHelper: Pretendard-SemiBold.otf not found in bundle")
            #endif
        }

    }()

    static func registerFontIfNeeded() {
        _ = _register
    }
}
