#!/bin/bash
adb logcat -c
adb shell am start -n com.rnturboimagepicker.app/.MainActivity
sleep 2
adb shell input tap 540 1800 # Click 'Profile Crop'
sleep 3
# Click the first image
adb shell input tap 200 400
sleep 2
# Now in ProfileCropActivity, click OK
adb shell input tap 900 150
sleep 2
# Now in ImageEditorActivity, click OK
adb shell input tap 950 150
sleep 2
adb logcat -d | grep -i "MainActivity\|ImagePicker\|processImage\|decodeStream\|Received" > flow_logs.txt
