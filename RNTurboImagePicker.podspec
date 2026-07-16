require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "RNTurboImagePicker"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => "15.1" }
  s.source       = { :git => package["repository"]["url"], :tag => "v#{s.version}" }

  s.vendored_frameworks = "ios/RNTurboImagePicker.xcframework"

  # Assets bundle
  s.resource_bundles = {
    'RNTurboImagePickerAssets' => [
      'ios/RNTurboImagePickerAssets/Assets.xcassets',
      'ios/RNTurboImagePickerAssets/ToolbarIcons/*',
      'ios/RNTurboImagePickerAssets/Fonts/*'
    ]
  }

  s.dependency "React-Core"
  s.dependency "SDWebImageWebPCoder"
  
  # Note: The compiled binary already contains the logic for React Native
  # We just need to make sure the app can link against the XCFramework
end
