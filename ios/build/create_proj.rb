    require 'xcodeproj'
    proj = Xcodeproj::Project.new('TempTarget.xcodeproj')
    target = proj.new_target(:application, 'TempTarget', :ios, '15.1')
    proj.save
