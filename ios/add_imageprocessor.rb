require 'xcodeproj'
project_path = 'RNTurboImagePicker.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# RNTurboImagePicker group should exist
group = project.main_group.find_subpath('RNTurboImagePicker', true)

file_name = 'ImageProcessor.swift'

# Check if it's already added
unless group.files.any? { |f| f.path == file_name }
  file_ref = group.new_file(file_name)
  target.add_file_references([file_ref])
  project.save
  puts "Added #{file_name} to project"
else
  puts "#{file_name} already in project"
end
