#!/usr/bin/env ruby
require 'xcodeproj'
project_path = File.join(__dir__, 'RNTurboImagePicker.xcodeproj')
project = Xcodeproj::Project.open(project_path)
target = project.targets.first
target.product_type = 'com.apple.product-type.application'
target.build_configurations.each do |config|
  config.build_settings.delete('MACH_O_TYPE')
  config.build_settings.delete('EXECUTABLE_EXTENSION')
  config.build_settings.delete('WRAPPER_EXTENSION')
  config.build_settings.delete('BUILD_LIBRARY_FOR_DISTRIBUTION')
  config.build_settings.delete('SKIP_INSTALL')
  config.build_settings.delete('DEFINES_MODULE')
end
project.save

app_delegate_path = File.join(__dir__, 'RNTurboImagePicker/AppDelegate.swift')
if File.exist?(app_delegate_path)
  content = File.read(app_delegate_path)
  content = content.gsub(/^\/\/ @main$/, '@main')
  File.write(app_delegate_path, content)
end

puts "Restored to application"
