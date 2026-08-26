# Android Studio에서 프로젝트 열기 가이드

이 프로젝트를 Android Studio에서 열고 빌드할 수 있습니다.

## 📋 사전 요구사항

- Android Studio Hedgehog (2023.1.1) 이상
- JDK 17 이상
- Android SDK (API 34)
- Kotlin 플러그인

## 🚀 Android Studio에서 열기

### 방법 1: Android Studio에서 직접 열기

1. **Android Studio 실행**
2. **File > Open** 선택
3. `/Users/mike/source/KoraProject/NativeModules/RNTurboImagePicker/android` 디렉토리 선택
4. Android Studio가 자동으로 프로젝트를 동기화합니다

### 방법 2: 터미널에서 열기

```bash
cd /Users/mike/source/KoraProject/NativeModules/RNTurboImagePicker/android
open -a "Android Studio" .
```

## 🔧 프로젝트 구조

```
android/
├── build.gradle                    # 루트 빌드 설정
├── settings.gradle                 # 프로젝트 설정
├── gradle.properties              # Gradle 속성
└── rnturboimagepicker/            # 라이브러리 모듈
    ├── build.gradle               # 모듈 빌드 설정
    ├── proguard-rules.pro
    └── src/
        ├── main/                  # 메인 소스 코드
        ├── newarch/               # New Architecture
        └── oldarch/               # Old Architecture
```

## 📦 빌드하기

### Gradle을 사용한 빌드

프로젝트가 Android Studio에서 열리면:

1. **Build > Make Project** (Cmd+F9 / Ctrl+F9)
2. 또는 터미널에서:
   ```bash
   cd android
   ./gradlew build
   ```

### AAR 파일 생성

라이브러리를 AAR 파일로 빌드:

```bash
cd android
./gradlew :rnturboimagepicker:assembleRelease
```

생성된 AAR 파일은:
`android/rnturboimagepicker/build/outputs/aar/rnturboimagepicker-release.aar`

## ⚠️ 중요: 실행 구성 안내

**이 프로젝트는 라이브러리 모듈이므로 실행할 수 없습니다!**

Android Studio에서 실행 구성을 설정하려고 하면 "Module not specified" 오류가 발생합니다. 
이는 정상이며, 이 프로젝트는 독립적으로 실행되지 않도록 설계되었습니다.

**실행 구성은 삭제하세요** - 필요하지 않습니다!

자세한 내용은 `EXECUTION_GUIDE.md`를 참고하세요.

## ⚠️ 주의사항

### 1. React Native 종속성

이 프로젝트는 React Native 라이브러리 모듈이므로:
- **독립적으로 실행할 수 없습니다** (실행 가능한 앱이 아닙니다)
- React Native 앱에 통합되어야 테스트할 수 있습니다
- 단독으로는 **빌드와 컴파일 확인**만 가능합니다

### 2. Gradle 동기화 문제

만약 Gradle 동기화 오류가 발생하면:

1. **File > Invalidate Caches / Restart**
2. **Tools > SDK Manager**에서 필요한 SDK 설치 확인
3. **File > Sync Project with Gradle Files**

### 3. React Native 종속성 오류

`com.facebook.react:react-native:+` 종속성이 해결되지 않으면:

1. React Native 프로젝트에서 이 모듈을 사용하거나
2. `local.properties`에서 React Native 경로를 설정하거나
3. 테스트용으로 mock 종속성을 사용할 수 있습니다

## 🧪 실제 테스트 방법

이 모듈을 실제로 테스트하려면:

### 옵션 1: React Native 앱에 통합

```bash
# React Native 프로젝트에서
npm install /path/to/RNTurboImagePicker
# 또는
yarn add /path/to/RNTurboImagePicker
```

### 옵션 2: 기존 Kora 프로젝트 사용

프로젝트 구조를 보면 `Kora.ReactNative` 프로젝트가 있습니다:

```bash
cd /Users/mike/source/KoraProject/Kora.ReactNative
# 이 프로젝트에 모듈을 연결하고 테스트
```

## 📝 코드 확인

Android Studio에서:
- ✅ Kotlin 코드 확인 가능
- ✅ 코드 컴파일 확인 가능
- ✅ 구문 오류 확인 가능
- ✅ 코드 포맷팅 및 리팩토링 가능
- ❌ 실제 실행 불가 (앱이 아니므로)

## 🎯 유용한 기능

### 코드 탐색
- `Cmd+B` (Mac) / `Ctrl+B` (Windows): 심볼로 이동
- `Cmd+Click`: 정의로 이동
- `Cmd+Shift+F`: 전체 프로젝트 검색

### 디버깅
- 코드에 브레이크포인트 설정 가능
- 하지만 실제 실행은 React Native 앱에서만 가능

### 리팩토링
- `Shift+F6`: 이름 바꾸기
- `Cmd+Alt+L`: 코드 포맷팅

## 🔍 프로젝트 설정 확인

### Android Studio 설정 확인

1. **File > Project Structure**
2. **SDK Location** 확인:
   - Android SDK Location
   - JDK Location (17 이상)
3. **Modules** 탭에서 `rnturboimagepicker` 모듈 확인

## 💡 팁

1. **Gradle 동기화**: 프로젝트를 열면 자동으로 동기화됩니다
2. **오류 확인**: 하단의 **Build** 탭에서 빌드 오류 확인
3. **Logcat**: 실제 테스트 시 `adb logcat`으로 로그 확인 가능

## 📞 문제 해결

### "SDK not found" 오류
- **Tools > SDK Manager**에서 Android SDK 설치

### "Gradle sync failed" 오류
- **File > Invalidate Caches / Restart**
- 인터넷 연결 확인 (의존성 다운로드 필요)

### "Cannot resolve symbol" 오류
- React Native 종속성이 없어서 발생할 수 있습니다
- 이는 정상입니다 (실제 React Native 앱에서만 해결됨)

---

**설정 완료!** 이제 Android Studio에서 프로젝트를 열고 코드를 확인할 수 있습니다.

