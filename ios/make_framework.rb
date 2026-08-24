require 'xcodeproj'
project_path = 'ios/RNTurboImagePicker.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first
target.product_type = 'com.apple.product-type.framework'
target.build_configurations.each do |config|
  config.build_settings['MACH_O_TYPE'] = 'staticlib'
  config.build_settings['EXECUTABLE_EXTENSION'] = 'framework'
  config.build_settings['WRAPPER_EXTENSION'] = 'framework'
  config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
  config.build_settings['SKIP_INSTALL'] = 'NO'
  config.build_settings['DEFINES_MODULE'] = 'YES'
end
project.save

app_delegate_path = 'ios/RNTurboImagePicker/AppDelegate.swift'
if File.exist?(app_delegate_path)
  content = File.read(app_delegate_path)
  content = content.gsub(/^@main$/, '// @main')
  File.write(app_delegate_path, content)
end

puts "Changed to framework"
