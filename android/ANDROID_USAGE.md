# RNTurboImagePicker - Android Usage Guide

## Complete Integration Example

### 1. Installation

```bash
cd /path/to/your/react-native-project
npm install react-native-turbo-image-picker
# or
yarn add react-native-turbo-image-picker
```

### 2. Android Configuration

The module uses **ActivityEventListener** so you **DON'T need to modify MainActivity**!

Just make sure the module is linked properly in your `android/app/build.gradle`:

```gradle
dependencies {
    implementation project(':react-native-turbo-image-picker')
    // ... other dependencies
}
```

And in `android/settings.gradle`:

```gradle
include ':react-native-turbo-image-picker'
project(':react-native-turbo-image-picker').projectDir = new File(rootProject.projectDir, '../node_modules/react-native-turbo-image-picker/android')
```

### 3. Permission Handling Component

Create a `PermissionHelper.ts`:

```typescript
import { PermissionsAndroid, Platform } from 'react-native';

export class PermissionHelper {
  static async requestImagePermission(): Promise<boolean> {
    if (Platform.OS !== 'android') {
      return true;
    }

    try {
      // Android 13+ uses READ_MEDIA_IMAGES
      if (Platform.Version >= 33) {
        const granted = await PermissionsAndroid.request(
          PermissionsAndroid.PERMISSIONS.READ_MEDIA_IMAGES,
          {
            title: 'Photo Access Permission',
            message: 'This app needs access to your photos to let you select images',
            buttonNeutral: 'Ask Me Later',
            buttonNegative: 'Cancel',
            buttonPositive: 'OK',
          }
        );
        return granted === PermissionsAndroid.RESULTS.GRANTED;
      } 
      // Android 12 and below use READ_EXTERNAL_STORAGE
      else {
        const granted = await PermissionsAndroid.request(
          PermissionsAndroid.PERMISSIONS.READ_EXTERNAL_STORAGE,
          {
            title: 'Storage Access Permission',
            message: 'This app needs access to your storage to let you select images',
            buttonNeutral: 'Ask Me Later',
            buttonNegative: 'Cancel',
            buttonPositive: 'OK',
          }
        );
        return granted === PermissionsAndroid.RESULTS.GRANTED;
      }
    } catch (err) {
      console.warn('Permission request error:', err);
      return false;
    }
  }

  static async checkImagePermission(): Promise<boolean> {
    if (Platform.OS !== 'android') {
      return true;
    }

    try {
      if (Platform.Version >= 33) {
        const granted = await PermissionsAndroid.check(
          PermissionsAndroid.PERMISSIONS.READ_MEDIA_IMAGES
        );
        return granted;
      } else {
        const granted = await PermissionsAndroid.check(
          PermissionsAndroid.PERMISSIONS.READ_EXTERNAL_STORAGE
        );
        return granted;
      }
    } catch (err) {
      console.warn('Permission check error:', err);
      return false;
    }
  }
}
```

### 4. Image Picker Hook

Create a `useImagePicker.ts` hook:

```typescript
import { useState, useCallback } from 'react';
import TurboImagePicker, { ImageResult, GalleryOptions } from 'react-native-turbo-image-picker';
import { PermissionHelper } from './PermissionHelper';
import { Alert, Platform } from 'react-native';

export interface UseImagePickerResult {
  images: ImageResult[];
  isLoading: boolean;
  error: string | null;
  pickImages: (options?: GalleryOptions) => Promise<void>;
  clearImages: () => void;
}

export const useImagePicker = (): UseImagePickerResult => {
  const [images, setImages] = useState<ImageResult[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const pickImages = useCallback(async (options?: GalleryOptions) => {
    setError(null);
    setIsLoading(true);

    try {
      // Check/request permission first
      const hasPermission = await PermissionHelper.checkImagePermission();
      
      if (!hasPermission) {
        const granted = await PermissionHelper.requestImagePermission();
        
        if (!granted) {
          setError('Permission denied');
          Alert.alert(
            'Permission Required',
            'Please grant photo access permission in Settings',
            [
              { text: 'Cancel', style: 'cancel' },
              { 
                text: 'Open Settings', 
                onPress: () => {
                  if (Platform.OS === 'android') {
                    // Open app settings
                    // You'll need to install react-native-permissions or similar
                  }
                }
              }
            ]
          );
          return;
        }
      }

      // Open image picker
      const result = await TurboImagePicker.openGallery({
        maxSelection: options?.maxSelection || 1,
        mediaType: options?.mediaType || 'image',
        quality: options?.quality || 0.8,
        ...options
      });

      setImages(result);
      console.log(`Selected ${result.length} images`);
      
    } catch (err: any) {
      const errorMessage = err?.message || 'Failed to pick images';
      setError(errorMessage);
      
      if (errorMessage.includes('cancelled')) {
        console.log('User cancelled image picker');
      } else {
        Alert.alert('Error', errorMessage);
      }
    } finally {
      setIsLoading(false);
    }
  }, []);

  const clearImages = useCallback(() => {
    setImages([]);
    setError(null);
  }, []);

  return {
    images,
    isLoading,
    error,
    pickImages,
    clearImages
  };
};
```

### 5. Example Screen Component

```typescript
import React from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  Image,
  StyleSheet,
  ScrollView,
  ActivityIndicator,
  Dimensions
} from 'react-native';
import { useImagePicker } from './useImagePicker';

const { width } = Dimensions.get('window');
const imageSize = (width - 48) / 3; // 3 columns with padding

export const ImagePickerScreen = () => {
  const { images, isLoading, error, pickImages, clearImages } = useImagePicker();

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Image Picker Example</Text>
      
      <View style={styles.buttonContainer}>
        <TouchableOpacity
          style={[styles.button, styles.primaryButton]}
          onPress={() => pickImages({ maxSelection: 1 })}
          disabled={isLoading}
        >
          <Text style={styles.buttonText}>Pick Single Image</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={[styles.button, styles.secondaryButton]}
          onPress={() => pickImages({ maxSelection: 10 })}
          disabled={isLoading}
        >
          <Text style={styles.buttonText}>Pick Multiple Images (Max 10)</Text>
        </TouchableOpacity>

        {images.length > 0 && (
          <TouchableOpacity
            style={[styles.button, styles.dangerButton]}
            onPress={clearImages}
            disabled={isLoading}
          >
            <Text style={styles.buttonText}>Clear All</Text>
          </TouchableOpacity>
        )}
      </View>

      {isLoading && (
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color="#007AFF" />
          <Text style={styles.loadingText}>Loading images...</Text>
        </View>
      )}

      {error && (
        <View style={styles.errorContainer}>
          <Text style={styles.errorText}>{error}</Text>
        </View>
      )}

      {images.length > 0 && (
        <View style={styles.resultContainer}>
          <Text style={styles.resultTitle}>
            Selected {images.length} image{images.length > 1 ? 's' : ''}
          </Text>
          
          <ScrollView style={styles.scrollView}>
            <View style={styles.imageGrid}>
              {images.map((image, index) => (
                <View key={index} style={styles.imageContainer}>
                  <Image
                    source={{ uri: image.uri }}
                    style={styles.image}
                    resizeMode="cover"
                  />
                  <View style={styles.imageInfo}>
                    <Text style={styles.imageInfoText} numberOfLines={1}>
                      {image.width} × {image.height}
                    </Text>
                    <Text style={styles.imageInfoText} numberOfLines={1}>
                      {image.type}
                    </Text>
                  </View>
                </View>
              ))}
            </View>
          </ScrollView>
        </View>
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#F5F5F5',
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    textAlign: 'center',
    marginVertical: 20,
    color: '#333',
  },
  buttonContainer: {
    paddingHorizontal: 16,
    gap: 12,
  },
  button: {
    paddingVertical: 14,
    paddingHorizontal: 20,
    borderRadius: 8,
    alignItems: 'center',
  },
  primaryButton: {
    backgroundColor: '#007AFF',
  },
  secondaryButton: {
    backgroundColor: '#34C759',
  },
  dangerButton: {
    backgroundColor: '#FF3B30',
  },
  buttonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '600',
  },
  loadingContainer: {
    alignItems: 'center',
    marginTop: 40,
  },
  loadingText: {
    marginTop: 12,
    fontSize: 14,
    color: '#666',
  },
  errorContainer: {
    margin: 16,
    padding: 16,
    backgroundColor: '#FFE5E5',
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#FF3B30',
  },
  errorText: {
    color: '#FF3B30',
    fontSize: 14,
    textAlign: 'center',
  },
  resultContainer: {
    flex: 1,
    marginTop: 20,
  },
  resultTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#333',
    paddingHorizontal: 16,
    marginBottom: 12,
  },
  scrollView: {
    flex: 1,
  },
  imageGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    padding: 12,
    gap: 12,
  },
  imageContainer: {
    width: imageSize,
    marginBottom: 8,
  },
  image: {
    width: imageSize,
    height: imageSize,
    borderRadius: 8,
    backgroundColor: '#E5E5E5',
  },
  imageInfo: {
    marginTop: 4,
    paddingHorizontal: 4,
  },
  imageInfoText: {
    fontSize: 11,
    color: '#666',
  },
});
```

## API Reference

### `openGallery(options: GalleryOptions): Promise<ImageResult[]>`

Opens the native image picker.

#### Options

```typescript
interface GalleryOptions {
  maxSelection?: number;        // Max number of images (default: 1)
  mediaType?: string;           // 'image' (default) or 'video'
  quality?: number;             // 0.0 - 1.0 (default: 0.8)
  allItemsText?: string;        // Custom text (not used on Android)
  selectedItemsText?: string;   // Custom text (not used on Android)
  doneButtonText?: string;      // Custom text (not used on Android)
  recentsAlbumText?: string;    // Custom text (not used on Android)
  languageCode?: string;        // Language code (not used on Android)
}
```

#### Result

```typescript
interface ImageResult {
  uri: string;      // Content URI (e.g., content://media/external/images/media/123)
  width: number;    // Image width in pixels
  height: number;   // Image height in pixels
  type: string;     // MIME type (e.g., 'image/jpeg', 'image/png')
}
```

## Error Handling

The module throws errors with these codes:

- `E_NO_ACTIVITY` - Activity doesn't exist
- `E_PICKER_CANCELLED` - User cancelled the picker
- `E_FAILED_TO_PICK` - Failed to pick or process images

## Testing

### Manual Testing Checklist

- [ ] Single image selection
- [ ] Multiple image selection
- [ ] Permission denied scenario
- [ ] Cancel picker
- [ ] Large images (> 10MB)
- [ ] Different image formats (JPEG, PNG, WebP)
- [ ] Low memory device
- [ ] Android 13+ (READ_MEDIA_IMAGES)
- [ ] Android 12 and below (READ_EXTERNAL_STORAGE)

## Troubleshooting

### Images not loading

Make sure you're using the content URI correctly. Android returns `content://` URIs which need to be used with React Native's Image component:

```typescript
<Image source={{ uri: image.uri }} />
```

### Permission issues

If permissions are not working:

1. Check `AndroidManifest.xml` includes the permissions
2. Verify runtime permission request is working
3. Check Android version-specific permissions (33+ vs 32-)

### Build errors

If you get build errors:

```bash
cd android
./gradlew clean
cd ..
npx react-native run-android
```

### Module not found

Make sure:
1. Module is in `node_modules`
2. `settings.gradle` includes the module
3. `build.gradle` has implementation line
4. Metro bundler is restarted

## Performance Tips

1. **Limit max selection** - Don't allow too many images at once
2. **Quality setting** - Use lower quality (0.6-0.8) for uploads
3. **Async processing** - The module processes images asynchronously
4. **Memory management** - Clear images when not needed

## Advanced Usage

### Custom Image Processing

```typescript
const processSelectedImages = async (images: ImageResult[]) => {
  for (const image of images) {
    // Upload to server
    const formData = new FormData();
    formData.append('photo', {
      uri: image.uri,
      type: image.type,
      name: `photo_${Date.now()}.jpg`,
    });

    await fetch('https://your-api.com/upload', {
      method: 'POST',
      body: formData,
    });
  }
};
```

### Integration with Image Libraries

```typescript
import FastImage from 'react-native-fast-image';

<FastImage
  source={{ uri: image.uri }}
  style={styles.image}
  resizeMode={FastImage.resizeMode.cover}
/>
```
