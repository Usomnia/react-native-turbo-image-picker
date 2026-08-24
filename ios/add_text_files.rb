require 'xcodeproj'

project_path = '/Users/mike/source/ZemTalk/RNturboImagePicker/ios/RNTurboImagePicker.xcodeproj'
project = Xcodeproj::Project.open(project_path)
group = project.main_group.find_subpath(File.join('RNTurboImagePicker'), true)

files_to_add = [
  'TextInputViewController.swift',
  'TextStickerView.swift'
]

target = project.targets.first

files_to_add.each do |file_name|
  file_path = File.join('/Users/mike/source/ZemTalk/RNturboImagePicker/ios/RNTurboImagePicker', file_name)
  unless group.files.any? { |f| f.path == file_name }
    file_ref = group.new_reference(file_path)
    target.add_file_references([file_ref])
    puts "Added #{file_name} to project"
  end
end

project.save
