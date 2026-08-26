# RNTurboImagePicker - Android Setup

## Installation

1. Add the module to your React Native project:

```bash
npm install react-native-turbo-image-picker
# or
yarn add react-native-turbo-image-picker
```

2. Update your `android/app/build.gradle`:

```gradle
dependencies {
    implementation project(':react-native-turbo-image-picker')
    // ... other dependencies
}
```

3. Update your `android/settings.gradle`:

```gradle
include ':react-native-turbo-image-picker'
project(':react-native-turbo-image-picker').projectDir = new File(rootProject.projectDir, '../node_modules/react-native-turbo-image-picker/android')
```

## MainActivity Configuration

### Add Activity Result Handling

Update your `MainActivity.java` or `MainActivity.kt`:

#### For Kotlin:

```kotlin
package com.yourapp

import android.content.Intent
import android.os.Bundle
import com.facebook.react.ReactActivity
import com.facebook.react.ReactActivityDelegate
import com.facebook.react.defaults.DefaultNewArchitectureEntryPoint.fabricEnabled
import com.facebook.react.defaults.DefaultReactActivityDelegate
import com.rnturboimagepicker.RNTurboImagePickerModule

class MainActivity : ReactActivity() {

    override fun getMainComponentName(): String = "YourAppName"

    override fun createReactActivityDelegate(): ReactActivityDelegate =
        DefaultReactActivityDelegate(this, mainComponentName, fabricEnabled)

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        // Handle image picker result
        val reactInstanceManager = reactNativeHost.reactInstanceManager
        val currentActivity = reactInstanceManager.currentReactContext?.currentActivity
        
        if (currentActivity != null) {
            val modules = reactInstanceManager.currentReactContext?.getNativeModule(
                RNTurboImagePickerModule::class.java
            )
            modules?.handleActivityResult(requestCode, resultCode, data)
        }
    }
}
```

#### For Java:

```java
package com.yourapp;

import android.content.Intent;
import android.os.Bundle;
import com.facebook.react.ReactActivity;
import com.facebook.react.ReactActivityDelegate;
import com.facebook.react.defaults.DefaultNewArchitectureEntryPoint;
import com.facebook.react.defaults.DefaultReactActivityDelegate;
import com.rnturboimagepicker.RNTurboImagePickerModule;

public class MainActivity extends ReactActivity {

    @Override
    protected String getMainComponentName() {
        return "YourAppName";
    }

    @Override
    protected ReactActivityDelegate createReactActivityDelegate() {
        return new DefaultReactActivityDelegate(
            this,
            getMainComponentName(),
            DefaultNewArchitectureEntryPoint.getFabricEnabled()
        );
    }

    @Override
    public void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        
        // Handle image picker result
        if (getReactNativeHost().getReactInstanceManager().getCurrentReactContext() != null) {
            RNTurboImagePickerModule module = getReactNativeHost()
                .getReactInstanceManager()
                .getCurrentReactContext()
                .getNativeModule(RNTurboImagePickerModule.class);
                
            if (module != null) {
                module.handleActivityResult(requestCode, resultCode, data);
            }
        }
    }
}
```

## Permissions

The module automatically declares the required permissions in its `AndroidManifest.xml`:

- `READ_MEDIA_IMAGES` (Android 13+)
- `READ_EXTERNAL_STORAGE` (Android 12 and below)

### Runtime Permission Request

You need to request permissions at runtime. Example:

```typescript
import { PermissionsAndroid, Platform } from 'react-native';

async function requestStoragePermission() {
  if (Platform.OS !== 'android') {
    return true;
  }

  if (Platform.Version >= 33) {
    const granted = await PermissionsAndroid.request(
      PermissionsAndroid.PERMISSIONS.READ_MEDIA_IMAGES,
      {
        title: 'Photo Access Permission',
        message: 'This app needs access to your photos',
        buttonNeutral: 'Ask Me Later',
        buttonNegative: 'Cancel',
        buttonPositive: 'OK',
      }
    );
    return granted === PermissionsAndroid.RESULTS.GRANTED;
  } else {
    const granted = await PermissionsAndroid.request(
      PermissionsAndroid.PERMISSIONS.READ_EXTERNAL_STORAGE,
      {
        title: 'Photo Access Permission',
        message: 'This app needs access to your photos',
        buttonNeutral: 'Ask Me Later',
        buttonNegative: 'Cancel',
        buttonPositive: 'OK',
      }
    );
    return granted === PermissionsAndroid.RESULTS.GRANTED;
  }
}
```

## Usage Example

```typescript
import TurboImagePicker from 'react-native-turbo-image-picker';

// Single image selection
const pickSingleImage = async () => {
  try {
    const hasPermission = await requestStoragePermission();
    if (!hasPermission) {
      console.log('Permission denied');
      return;
    }

    const result = await TurboImagePicker.openGallery({
      maxSelection: 1,
      mediaType: 'image',
      quality: 0.8,
    });

    console.log('Selected image:', result);
  } catch (error) {
    console.error('Error picking image:', error);
  }
};

// Multiple image selection
const pickMultipleImages = async () => {
  try {
    const hasPermission = await requestStoragePermission();
    if (!hasPermission) {
      console.log('Permission denied');
      return;
    }

    const result = await TurboImagePicker.openGallery({
      maxSelection: 10,
      mediaType: 'image',
      quality: 0.8,
    });

    console.log(`Selected ${result.length} images:`, result);
  } catch (error) {
    console.error('Error picking images:', error);
  }
};
```

## Troubleshooting

### Module not found error

If you get a "Module not found" error, make sure:

1. You've run `cd android && ./gradlew clean` and rebuilt the app
2. The module is properly linked in `settings.gradle`
3. You've restarted the Metro bundler

### Activity result not received

If the activity result is not being received:

1. Make sure you've added the `onActivityResult` override in MainActivity
2. Check that the module is properly getting the ReactContext
3. Verify that the app has the required permissions

### Build errors

If you encounter build errors:

1. Make sure your `compileSdkVersion` is 34 or higher
2. Check that you have the required dependencies in your app's `build.gradle`
3. Clean the build: `cd android && ./gradlew clean`

## New Architecture Support

This module supports both the Old and New Architecture of React Native. The module will automatically use the appropriate implementation based on your React Native configuration.

To enable New Architecture, set `newArchEnabled=true` in your `gradle.properties`.

## Minimum Requirements

- React Native >= 0.73.0
- Android SDK 24+
- Kotlin 1.9.0+
- Java 17
