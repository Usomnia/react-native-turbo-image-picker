require 'xcodeproj'

project_path = '/Users/mike/source/ZemTalk/RNTurboImagePicker/ios/RNTurboImagePicker.xcodeproj'
project = Xcodeproj::Project.open(project_path)
group = project.main_group.find_subpath(File.join('RNTurboImagePicker'), true)

target = project.targets.first

swift_files = [
  'TossFaceLabel.swift',
]

swift_files.each do |file_name|
  file_path = File.join('/Users/mike/source/ZemTalk/RNTurboImagePicker/ios/RNTurboImagePicker', file_name)
  unless group.files.any? { |f| f.path == file_name }
    file_ref = group.new_reference(file_path)
    target.add_file_references([file_ref])
    puts "Added #{file_name} to project"
  else
    puts "#{file_name} already in project"
  end
end

project.save
puts "Project saved."
