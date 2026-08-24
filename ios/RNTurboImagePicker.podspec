require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "RNTurboImagePicker"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => "15.0" }
  s.source       = { :git => "https://github.com/yourusername/RNTurboImagePicker.git", :tag => "#{s.version}" }

  # RNTurboImagePicker 폴더의 Swift 파일들
  s.source_files = "RNTurboImagePicker/**/*.{h,m,mm,swift}", "ios/**/*.{h,m,mm,swift}"
  
  # Resources (Assets, Storyboards 등)
  s.resources = "RNTurboImagePicker/**/*.{storyboard,xib,xcassets}"

  s.swift_version = "5.0"

  # Dependencies
  s.dependency "React-Core"
  
  # New Architecture (Fabric) 지원
  if ENV['RCT_NEW_ARCH_ENABLED'] == '1' then
    s.compiler_flags = "-DRCT_NEW_ARCH_ENABLED=1"
    s.pod_target_xcconfig = {
        "HEADER_SEARCH_PATHS" => "\"$(PODS_ROOT)/boost\"",
        "CLANG_CXX_LANGUAGE_STANDARD" => "c++17"
    }
    s.dependency "React-Codegen"
    s.dependency "RCT-Folly"
    s.dependency "RCTRequired"
    s.dependency "RCTTypeSafety"
    s.dependency "ReactCommon/turbomodule/core"
  end
end
