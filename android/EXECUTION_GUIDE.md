# Android Studio 실행 구성 안내

## ⚠️ 중요: 이 프로젝트는 실행할 수 없습니다

이 프로젝트는 **React Native 라이브러리 모듈**이므로 **독립적으로 실행할 수 없습니다**.

라이브러리 모듈은 다음을 위해 사용됩니다:
- ✅ 코드 편집 및 확인
- ✅ 컴파일 오류 확인
- ✅ AAR 파일 빌드
- ❌ 직접 실행 (앱이 아니므로 불가능)

## 🔧 실행 구성 삭제하기

Android Studio에서 실행 구성을 삭제하려면:

1. **Run/Debug Configurations** 드롭다운에서 **Edit Configurations...** 선택
2. `RNTurboImagePickerModule` 구성 선택
3. **-** 버튼을 클릭하여 삭제
4. **OK** 클릭

또는:

1. 상단 툴바의 실행 구성 드롭다운 클릭
2. **Edit Configurations...** 선택
3. 해당 구성 삭제

## ✅ Android Studio에서 할 수 있는 것

### 1. 코드 확인 및 편집
- Kotlin 소스 코드 확인
- 코드 편집 및 리팩토링
- 구문 오류 확인

### 2. 빌드 확인
- **Build > Make Project** (Cmd+F9 / Ctrl+F9)
- 또는 터미널에서: `./gradlew :rnturboimagepicker:build`

### 3. AAR 파일 생성
터미널에서:
```bash
cd /Users/mike/source/KoraProject/NativeModules/RNTurboImagePicker/android
./gradlew :rnturboimagepicker:assembleRelease
```

생성된 AAR 파일 위치:
```
android/rnturboimagepicker/build/outputs/aar/rnturboimagepicker-release.aar
```

## 🧪 실제 테스트 방법

이 모듈을 실제로 테스트하려면 React Native 앱에 통합해야 합니다:

### 옵션 1: 기존 React Native 프로젝트에 통합

```bash
# React Native 프로젝트로 이동
cd /path/to/your/react-native-project

# 모듈 추가 (로컬 경로)
npm install /Users/mike/source/KoraProject/NativeModules/RNTurboImagePicker

# 또는 package.json에 추가
"react-native-turbo-image-picker": "file:../NativeModules/RNTurboImagePicker"
```

### 옵션 2: Kora.ReactNative 프로젝트 사용

프로젝트 구조를 보면 `Kora.ReactNative` 프로젝트가 있습니다:

```bash
cd /Users/mike/source/KoraProject/Kora.ReactNative
# 이 프로젝트에 모듈을 통합하고 테스트
```

### 옵션 3: 새로운 React Native 앱 생성

```bash
npx react-native init TestApp
cd TestApp
npm install /Users/mike/source/KoraProject/NativeModules/RNTurboImagePicker
# android/app/build.gradle에 모듈 추가
# android/settings.gradle에 모듈 포함
```

## 📝 Android Studio 사용 가이드

### 유용한 단축키

- **Cmd+B** (Mac) / **Ctrl+B** (Windows): 심볼 정의로 이동
- **Cmd+Click**: 정의로 이동
- **Cmd+Shift+F**: 전체 프로젝트 검색
- **Cmd+F9** / **Ctrl+F9**: 프로젝트 빌드
- **Cmd+Alt+L**: 코드 포맷팅

### 디버깅

코드에 브레이크포인트를 설정할 수 있지만, 실제 실행은 React Native 앱에서만 가능합니다.

## 💡 추천 워크플로우

1. **Android Studio에서**: 코드 편집 및 컴파일 확인
2. **React Native 앱에서**: 실제 테스트 및 실행

## ❓ FAQ

### Q: 왜 실행이 안 되나요?
A: 이 프로젝트는 라이브러리 모듈이므로 실행 가능한 앱이 아닙니다. React Native 앱에 통합해야 테스트할 수 있습니다.

### Q: 실행 구성이 계속 나타나요
A: Android Studio가 자동으로 생성할 수 있습니다. 삭제하면 됩니다. 필요하지 않습니다.

### Q: 어떻게 테스트하나요?
A: React Native 앱 프로젝트에 이 모듈을 추가하고, 해당 앱을 실행하여 테스트합니다.

---

**요약**: 이 프로젝트는 코드 편집과 빌드를 위한 것이며, 실제 실행은 React Native 앱에서 해야 합니다.

