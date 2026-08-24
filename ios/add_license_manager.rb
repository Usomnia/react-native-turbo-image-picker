require 'xcodeproj'
project_path = 'ios/RNTurboImagePicker.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first
group = project.main_group.find_subpath('RNTurboImagePicker', true)

unless group.files.any? { |f| f.path == 'LicenseManager.swift' }
  file_ref = group.new_file('LicenseManager.swift')
  target.add_file_references([file_ref])
  project.save
  puts "Added LicenseManager.swift to project"
else
  puts "LicenseManager.swift already in project"
end
