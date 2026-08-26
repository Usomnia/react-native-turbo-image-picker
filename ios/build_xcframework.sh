#!/bin/bash
set -e

PROJECT="RNTurboImagePicker.xcodeproj"
SCHEME="RNTurboImagePicker"
ARCHIVE_DIR="build/Archives"
FRAMEWORK_NAME="RNTurboImagePicker"

echo "Building iOS Archive..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_DIR/iOS.xcarchive" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    MACH_O_TYPE=staticlib

echo "Building iOS Simulator Archive..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS Simulator' \
    -archivePath "$ARCHIVE_DIR/iOS_Simulator.xcarchive" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    MACH_O_TYPE=staticlib

echo "Creating XCFramework..."
rm -rf build/RNTurboImagePicker.xcframework
xcodebuild -create-xcframework \
    -framework "$ARCHIVE_DIR/iOS.xcarchive/Products/Library/Frameworks/$FRAMEWORK_NAME.framework" \
    -framework "$ARCHIVE_DIR/iOS_Simulator.xcarchive/Products/Library/Frameworks/$FRAMEWORK_NAME.framework" \
    -output "build/RNTurboImagePicker.xcframework"

echo "Copying to Dist..."
rm -rf ../../RNTurboImagePicker-Dist/ios/RNTurboImagePicker.xcframework
cp -R build/RNTurboImagePicker.xcframework ../../RNTurboImagePicker-Dist/ios/
echo "Done!"
