require 'xcodeproj'
project_path = 'RNTurboImagePicker.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

group = project.main_group.find_subpath('RNTurboImagePicker', true)

unless group.files.any? { |f| f.path == 'Localizer.swift' }
  file_ref = group.new_file('Localizer.swift')
  target.add_file_references([file_ref])
  project.save
  puts "Added Localizer.swift to project"
else
  puts "Localizer.swift already in project"
end
