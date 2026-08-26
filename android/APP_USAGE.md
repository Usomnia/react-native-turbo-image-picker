# Android Studio에서 직접 실행하기

## ✅ 빌드 완료!

이제 Android Studio에서 직접 앱을 실행하고 테스트할 수 있습니다.

## 🚀 실행 방법

### 1. Android Studio에서 프로젝트 열기

```bash
cd /Users/mike/source/KoraProject/NativeModules/RNTurboImagePicker/android
open -a "Android Studio" .
```

### 2. 앱 실행

1. 상단 툴바에서 **Run/Debug Configurations** 선택
2. **app** 모듈 선택 (자동으로 생성됨)
3. 에뮬레이터나 실제 기기 선택
4. **Run** 버튼 클릭 (▶️) 또는 `Shift+F10` / `Cmd+R`

### 3. 테스트 기능

앱이 실행되면:
- **"Select Single Image"** 버튼: 단일 이미지 선택
- **"Select Multiple Images"** 버튼: 최대 10개 이미지 선택

선택한 이미지는 화면에 표시되고, 상세 정보가 다이얼로그로 표시됩니다.

## 📱 테스트 시나리오

### 단일 이미지 선택
1. "Select Single Image" 버튼 클릭
2. 갤러리에서 이미지 선택
3. 선택한 이미지가 화면에 표시됨

### 여러 이미지 선택
1. "Select Multiple Images" 버튼 클릭
2. 갤러리에서 여러 이미지 선택 (최대 10개)
3. 선택한 이미지 개수와 URI 정보 확인

### 권한 테스트
- 앱 실행 시 저장소 권한 요청
- 권한 거부 시 이미지 선택 불가

## 🔧 프로젝트 구조

```
android/
├── app/                          # 실행 가능한 Android 앱
│   ├── src/main/
│   │   ├── java/.../MainActivity.kt   # 메인 액티비티
│   │   ├── res/
│   │   └── AndroidManifest.xml
│   └── build.gradle
│
└── rnturboimagepicker/          # 라이브러리 모듈
    └── src/main/java/.../ImagePickerActivity.kt  # 이미지 선택 액티비티
```

## 💡 디버깅

### Logcat 확인
Android Studio의 하단 **Logcat** 탭에서 로그 확인:
- `adb logcat | grep ImagePicker`

### 브레이크포인트
- `MainActivity.kt`에 브레이크포인트 설정
- `ImagePickerActivity.kt`에 브레이크포인트 설정
- 실제 실행 중 디버깅 가능

### 디버그 모드
1. **Run > Debug 'app'** 선택
2. 브레이크포인트에서 멈춤
3. 변수 값 확인 및 단계별 실행

## ⚡ 빠른 테스트 사이클

React Native 없이도 빠르게 테스트 가능:

1. 코드 수정
2. **Build > Make Project** (Cmd+F9)
3. **Run** (Shift+F10)
4. 즉시 테스트

React Native 빌드 사이클(10-30초) 대신 Android 빌드(2-5초)로 빠르게 테스트!

## 📝 참고사항

### React Native 의존성 파일
- `RNTurboImagePickerModule.kt`와 `RNTurboImagePickerPackage.kt`는 
  `.bak` 확장자로 백업되어 있습니다
- React Native 프로젝트에서 사용할 때는 복원하면 됩니다
- 현재는 `ImagePickerActivity`만 사용합니다 (순수 Android 코드)

### 복원 방법
```bash
cd android/rnturboimagepicker/src/main/java/com/rnturboimagepicker
mv RNTurboImagePickerModule.kt.bak RNTurboImagePickerModule.kt
mv RNTurboImagePickerPackage.kt.bak RNTurboImagePickerPackage.kt
```

## 🎯 이점

✅ **빠른 테스트 사이클**: React Native 빌드 없이 2-5초  
✅ **직접 디버깅**: Android Studio에서 바로 브레이크포인트 사용  
✅ **즉시 확인**: 코드 수정 → 빌드 → 실행 → 확인  
✅ **독립적 테스트**: React Native 환경 없이도 네이티브 코드 테스트  

---

**이제 Android Studio에서 바로 실행해서 빠르게 테스트하세요!** 🚀

