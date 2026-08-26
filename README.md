# RNTurboImagePicker

고성능 텔레그램 스타일 이미지 갤러리 피커 for React Native

## 🚀 주요 기능

- ✅ **고성능**: 배치 로딩과 캐싱으로 빠른 성능
- ✅ **다중 선택**: 여러 이미지 동시 선택 가능
- ✅ **앨범 지원**: 스마트 앨범 및 사용자 앨범 지원
- ✅ **품질 옵션**: low, medium, high 품질 선택
- ✅ **TypeScript**: 완벽한 타입 정의
- ✅ **iOS 15.1+**: 최신 iOS 지원

## 📦 설치

### 1. 프로젝트에 모듈 추가

```bash
cd /path/to/your/react-native-project

# package.json에 로컬 모듈 추가
yarn add file:../NativeModules/RNTurboImagePicker/ios
# 또는
npm install file:../NativeModules/RNTurboImagePicker/ios
```

### 2. iOS Pod 설치

```bash
cd ios
pod install
cd ..
```

### 3. iOS 권한 설정

`ios/YourApp/Info.plist` 파일에 다음 권한 추가:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>사진을 선택하기 위해 라이브러리 접근이 필요합니다.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>사진을 저장하기 위해 라이브러리 접근이 필요합니다.</string>
```

## 📱 사용법

### 기본 사용

```typescript
import { RNTurboImagePicker } from 'react-native-turbo-image-picker';

// 1. 권한 체크
const status = await RNTurboImagePicker.checkPermission();

if (status.status !== 'authorized') {
  // 2. 권한 요청
  const result = await RNTurboImagePicker.requestPermission();
  if (result.status !== 'authorized') {
    console.log('권한이 거부되었습니다.');
    return;
  }
}

// 3. 갤러리 열기
try {
  const result = await RNTurboImagePicker.openGallery({
    maxSelection: 10,
    quality: 'high',
    includeBase64: false,
  });
  
  console.log('선택된 이미지:', result.images);
} catch (error) {
  if (error.code === 'USER_CANCELLED') {
    console.log('사용자가 취소했습니다.');
  }
}
```

### 옵션

```typescript
interface ImagePickerOptions {
  maxSelection?: number;      // 최대 선택 가능 개수 (기본값: 10)
  quality?: 'low' | 'medium' | 'high';  // 이미지 품질 (기본값: 'high')
  includeBase64?: boolean;    // Base64 포함 여부 (기본값: false)
}
```

### 반환 타입

```typescript
interface ImageAsset {
  uri: string;          // 파일 경로 (file://)
  filename: string;     // 파일 이름
  width: number;        // 이미지 너비
  height: number;       // 이미지 높이
  fileSize: number;     // 파일 크기 (bytes)
  type: string;         // MIME 타입 (image/jpeg)
  base64?: string;      // Base64 문자열 (옵션)
}

interface ImagePickerResult {
  images: ImageAsset[];
}
```

## 🎨 전체 예제

전체 예제는 `/example/ImagePickerExample.tsx` 파일을 참고하세요.

## 🔧 개발

### 프로젝트 구조

```
RNTurboImagePicker/
├── ios/
│   ├── RNTurboImagePicker/        # iOS 네이티브 코드
│   │   ├── PhotoManager.swift     # 사진 관리자
│   │   ├── GalleryViewController.swift
│   │   └── ...
│   ├── ios/                       # RN 브리지
│   │   ├── RNTurboImagePickerModule.swift
│   │   └── RNTurboImagePickerModule.m
│   ├── src/                       # TypeScript 인터페이스
│   │   └── index.ts
│   ├── package.json
│   └── RNTurboImagePicker.podspec
└── android/                       # (향후 추가 예정)
```

### 로컬 개발

```bash
# 1. 네이티브 코드 수정 후
cd /path/to/PaceLap.ReactNative/ios
pod install

# 2. React Native 빌드
cd ..
yarn ios
```

## 📝 API 문서

### `requestPermission()`

포토 라이브러리 권한을 요청합니다.

```typescript
const result = await RNTurboImagePicker.requestPermission();
// { status: 'authorized' | 'denied' | 'restricted' | 'notDetermined' }
```

### `checkPermission()`

현재 권한 상태를 확인합니다.

```typescript
const result = await RNTurboImagePicker.checkPermission();
// { status: 'authorized' | 'denied' | 'restricted' | 'notDetermined' }
```

### `openGallery(options)`

이미지 갤러리를 엽니다.

```typescript
const result = await RNTurboImagePicker.openGallery({
  maxSelection: 10,
  quality: 'high',
  includeBase64: false,
});
```

## 🐛 트러블슈팅

### Pod install 실패

```bash
cd ios
rm -rf Pods Podfile.lock
pod cache clean --all
pod install
```

### 모듈을 찾을 수 없음

```bash
# node_modules 재설치
rm -rf node_modules
yarn install

# iOS 클린 빌드
cd ios
xcodebuild clean
cd ..
yarn ios
```

### 권한이 작동하지 않음

Info.plist에 `NSPhotoLibraryUsageDescription` 권한이 추가되었는지 확인하세요.

## 📄 라이선스

MIT

## 👨‍💻 Author

Mike
