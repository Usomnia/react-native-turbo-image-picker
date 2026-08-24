require 'xcodeproj'
project_path = 'RNTurboImagePicker.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# RNTurboImagePicker group should exist
group = project.main_group.find_subpath('RNTurboImagePicker', true)

file_path = 'RNTurboImagePicker/CropViewController.swift'

# Check if it's already added
unless group.files.any? { |f| f.path == 'CropViewController.swift' }
  file_ref = group.new_file('CropViewController.swift')
  target.add_file_references([file_ref])
  project.save
  puts "Added CropViewController.swift to project"
else
  puts "CropViewController.swift already in project"
end
