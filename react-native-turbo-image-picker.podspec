require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "react-native-turbo-image-picker"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"] || package["repository"]["url"] || "https://github.com/Usomnia/react-native-turbo-image-picker"
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => "15.1" }
  s.source       = { :git => package["repository"]["url"], :tag => "v#{s.version}" }

  s.source_files = "ios/*.{h,m,mm,swift}"
  s.swift_version = "5.0"

  # Assets bundle
  s.resource_bundles = {
    'RNTurboImagePickerAssets' => [
      'ios/RNTurboImagePickerAssets/Assets.xcassets',
      'ios/RNTurboImagePickerAssets/ToolbarIcons/*',
      'ios/RNTurboImagePickerAssets/Fonts/*'
    ]
  }

  s.vendored_frameworks = "ios/RNTurboImagePicker.xcframework"

  # s.dependency "SDWebImageWebPCoder"

  if respond_to?(:install_modules_dependencies, true)
    install_modules_dependencies(s)
  else
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
end
