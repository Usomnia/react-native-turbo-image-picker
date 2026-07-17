# React Native Turbo Image Picker 🚀

A highly customizable, high-performance, and purely native image picker and editor for React Native.

## ✨ Features
- **Pure Native UI**: Built with native iOS and Android for the fastest and smoothest performance.
- **Built-in Editor & Viewer**: Includes an integrated image editor (cropping, filtering) and a highly optimized image viewer.
- **Smooth Animations**: Carefully crafted interactions for a premium user experience (e.g., iOS-like smooth thumbnail centering).
- **Customizable**: Easily configure theme colors, maximum selection limits, and more.
- **New Architecture Ready**: Fully supports React Native's New Architecture (Turbo Modules).

---

## 📦 Installation

```bash
# Install directly from the GitHub repository
yarn add git+https://github.com/Usomnia/RNTurboImagePicker.git

# or using npm
npm install git+https://github.com/Usomnia/RNTurboImagePicker.git
```

If you are using iOS, don't forget to install pods:
```bash
cd ios && pod install
```

---

## 🛠 Usage Example

```javascript
import { RNTurboImagePicker } from 'react-native-turbo-image-picker';

// Example: Open Image Picker
const handleOpenPicker = async () => {
  try {
    const result = await RNTurboImagePicker.openGallery({
      maxSelection: 10,
      themeColor: '#FF6B35',
      enableEditor: true,
      profileMode: false,
    });
    console.log('Selected Images:', result);
  } catch (error) {
    console.error(error);
  }
};
```

---

## 📖 API Reference

### `RNTurboImagePicker.openGallery(options?: GalleryOptions): Promise<ImageResult[]>`
Opens the native image gallery for selecting photos and videos.

**GalleryOptions (Key Properties):**
- `maxSelection` (number): Maximum number of images a user can select.
- `maxWidth` / `maxHeight` (number): Maximum dimensions to scale the image.
- `mediaType` ("photo" | "video" | "all"): Type of media to show.
- `quality` (number): Compression quality (0 to 1).
- `enableEditor` (boolean): If `true`, opens the image editor after a single image selection.
- `profileMode` (boolean): If `true`, enables a 1:1 circular crop mode for profile pictures.
- `themeColor` (string): The primary hex color for the UI (e.g., `"#FFEB3B"`).
- `autoCloseOnSelect` (boolean): Close picker automatically on single selection.
- *Also includes various text overrides for localization (e.g., `doneButtonText`, `languageCode`).*

### `RNTurboImagePicker.openEditor(options: EditorOptions): Promise<ImageResult>`
Directly opens the built-in image editor for a specific image.

**EditorOptions:**
- `uri` (string): The URI of the image to edit.
- `editedFileUri` (string, optional): Path to a previously edited version.
- `themeColor` (string): UI theme color.
- `maxWidth` / `maxHeight` (number): Maximum bounds for the edited image.

### `RNTurboImagePicker.openViewer(options: ViewerOptions): Promise<void>`
Opens a high-performance, full-screen image viewer with smooth swiping, thumbnail navigation, and pinch-to-zoom capabilities.

**ViewerOptions:**
- `images` (string[]): Array of image URIs to view.
- `initialIndex` (number): The starting index.
- `themeColor` (string): UI theme color.

### `ImageResult` (Returned Object)
When an image is selected or edited, the promise resolves to an array of `ImageResult` objects containing:
- `originalUri` / `uri`: The original and resized/edited file URIs.
- `originalWidth` / `width`: Dimensions of the image.
- `type`, `fileName`, `fileExtension`, `fileSize`: Meta information.

---

## 🎥 Demo
*(You can upload a video or GIF to GitHub and place the URL here!)*

<!-- Example of embedding a video in GitHub Markdown: -->
<!-- <video src="YOUR_VIDEO_URL_HERE.mp4" width="300"></video> -->

---

## 📜 License & Contact

This `RNTurboImagePicker` library is strictly licensed by **Usomnia**. 
It is a proprietary asset of Usomnia company.

📧 **Contact**: [contact@usomnia.co.kr](mailto:contact@usomnia.co.kr)