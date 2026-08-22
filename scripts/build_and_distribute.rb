#!/usr/bin/env ruby

require 'fileutils'

def run_command(command)
  puts "Running: #{command}"
  unless system(command)
    puts "Error: Command failed - #{command}"
    exit 1
  end
end

ROOT_DIR = File.expand_path('..', __dir__)
ANDROID_DIR = File.join(ROOT_DIR, 'android')
IOS_DIR = File.join(ROOT_DIR, 'ios')

puts "--- Starting Build and Distribution ---"

# --- ANDROID BUILD ---
puts "\n--- Building Android AAR ---"
app_android_dir = File.join(ROOT_DIR, '../RNTurboImagePickerApp/android')
Dir.chdir(app_android_dir) do
  run_command('./gradlew :react-native-turbo-image-picker:clean :react-native-turbo-image-picker:assembleRelease')
  
  aar_source = File.join(app_android_dir, '../node_modules/react-native-turbo-image-picker/android/build/outputs/aar/react-native-turbo-image-picker-release.aar')
  aar_dest = File.join(ANDROID_DIR, 'src/main/libs/react-native-turbo-image-picker.aar')
  
  if File.exist?(aar_source)
    FileUtils.mkdir_p(File.dirname(aar_dest))
    FileUtils.cp(aar_source, aar_dest)
    puts "Android AAR copied to #{aar_dest}"
  else
    puts "Error: Android AAR not found at #{aar_source}"
    exit 1
  end
end

# --- IOS BUILD ---
puts "\n--- Building iOS XCFramework ---"
app_ios_dir = File.join(ROOT_DIR, '../RNTurboImagePickerApp/ios')
Dir.chdir(app_ios_dir) do
  # Run pod install with dynamic frameworks to ensure we get a .framework instead of .a
  run_command('USE_FRAMEWORKS=dynamic pod install')
  
  workspace = 'RNTurboImagePickerApp.xcworkspace'
  scheme = 'react-native-turbo-image-picker'
  
  unless File.exist?(workspace)
    puts "Error: Workspace #{workspace} not found. Did you run pod install?"
    exit 1
  end
  
  # Build for Simulator
  run_command("xcodebuild build -workspace #{workspace} -scheme #{scheme} -configuration Release -sdk iphonesimulator -arch x86_64 -arch arm64 BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO -derivedDataPath derived_data")
  
  # Build for Device
  run_command("xcodebuild build -workspace #{workspace} -scheme #{scheme} -configuration Release -sdk iphoneos -arch arm64 BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO -derivedDataPath derived_data")
  
  # Extract built frameworks
  sim_framework = Dir.glob("derived_data/Build/Products/Release-iphonesimulator/#{scheme}/*.framework").first
  dev_framework = Dir.glob("derived_data/Build/Products/Release-iphoneos/#{scheme}/*.framework").first
  
  if sim_framework && dev_framework
    xcframework_dest = File.join(IOS_DIR, 'RNTurboImagePicker.xcframework')
    FileUtils.rm_rf(xcframework_dest)
    
    run_command("xcodebuild -create-xcframework -framework #{sim_framework} -framework #{dev_framework} -output #{xcframework_dest}")
    puts "iOS XCFramework created at #{xcframework_dest}"
  else
    puts "Error: Frameworks not built correctly."
    exit 1
  end
  
  # Clean up derived data
  FileUtils.rm_rf('derived_data')
  
  # Revert pod install to static to not break the app for the user
  run_command('pod install')
end

puts "\n--- Build and Distribution Complete ---"
