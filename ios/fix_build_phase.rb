require 'xcodeproj'
project_path = 'ios/RNTurboImagePicker.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

group = project.main_group.find_subpath('RNTurboImagePicker', true)
file_ref = group.files.find { |f| f.path == 'GoogleEmojiImageView.swift' }

unless target.source_build_phase.files_references.include?(file_ref)
  target.source_build_phase.add_file_reference(file_ref)
  project.save
  puts "Added GoogleEmojiImageView.swift to compile sources build phase!"
else
  puts "Already in build phase"
end
