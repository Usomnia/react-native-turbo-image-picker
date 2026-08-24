require 'xcodeproj'

project_path = '/Users/mike/source/ZemTalk/RNTurboImagePicker/ios/RNTurboImagePicker.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'RNTurboImagePicker' } || project.targets.first

dep = target.package_product_dependencies.find { |d| d.product_name == 'SDWebImageWebPCoder' }

unless target.frameworks_build_phase.files.any? { |f| f.product_ref == dep }
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = dep
  target.frameworks_build_phase.files << build_file
  puts "Added to frameworks_build_phase"
end

project.save
