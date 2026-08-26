# Android Studio에서 앱 실행하기

## 🚀 실행 방법 (단계별)

### 방법 1: Android Studio GUI 사용 (추천)

#### 1단계: Android Studio에서 프로젝트 열기
- 이미 열려있다면 다음 단계로
- 아니면: **File > Open** → `android` 폴더 선택

#### 2단계: 실행 구성 확인
- 상단 툴바에서 **Run/Debug Configurations** 드롭다운 확인
- **"app"** 모듈이 선택되어 있는지 확인
- 없으면 **"Edit Configurations..."** → **"+"** 버튼 → **"Android App"** 선택
  - Name: `app`
  - Module: `app`
  - Launch: `Default Activity`

#### 3단계: 기기 선택
- 상단 툴바의 기기 선택 드롭다운에서:
  - **에뮬레이터**: AVD Manager에서 생성한 에뮬레이터 선택
  - **실제 기기**: USB로 연결된 기기 선택 (USB 디버깅 활성화 필요)

#### 4단계: 실행
- 상단 툴바의 **▶️ Run** 버튼 클릭
- 또는 키보드: `Shift+F10` (Mac: `Ctrl+R`)

### 방법 2: 터미널에서 ADB로 직접 설치

#### 1단계: APK 파일 확인
```bash
cd /Users/mike/source/KoraProject/NativeModules/RNTurboImagePicker/android
find app/build/outputs/apk/debug -name "*.apk"
```

#### 2단계: 기기 연결 확인
```bash
adb devices
```
기기가 목록에 표시되어야 합니다.

#### 3단계: APK 설치 및 실행
```bash
# APK 설치
adb install -r app/build/outputs/apk/debug/app-debug.apk

# 앱 실행
adb shell am start -n com.rnturboimagepicker.app/.MainActivity
```

### 방법 3: Gradle로 직접 실행

```bash
cd /Users/mike/source/KoraProject/NativeModules/RNTurboImagePicker/android

# 디버그 APK 빌드 및 설치 (기기가 연결되어 있어야 함)
./gradlew installDebug
```

## 📱 기기 준비

### 에뮬레이터 사용
1. Android Studio 상단 메뉴: **Tools > Device Manager**
2. **Create Device** 클릭
3. 기기 선택 (예: Pixel 6)
4. 시스템 이미지 선택 (예: API 33, 34)
5. 에뮬레이터 생성 완료

### 실제 기기 사용
1. 기기의 **개발자 옵션** 활성화
   - 설정 > 휴대전화 정보 > 빌드 번호를 7번 탭
2. **USB 디버깅** 활성화
   - 설정 > 시스템 > 개발자 옵션 > USB 디버깅
3. USB로 컴퓨터에 연결
4. 기기에서 "USB 디버깅 허용" 확인 팝업 승인

## 🔍 실행 확인

앱이 실행되면:
- 앱 이름: "Image Picker Test"
- 화면에 두 개의 버튼 표시:
  - "Select Single Image"
  - "Select Multiple Images (up to 10)"

## ⚠️ 문제 해결

### "No device selected" 오류
- 기기 선택 드롭다운에서 기기 선택
- 에뮬레이터가 실행 중인지 확인
- 실제 기기의 USB 디버깅 활성화 확인

### "Module 'app' is not specified" 오류
- 상단 툴바에서 **app** 모듈 선택
- 또는 **Run > Edit Configurations...** → Module: `app` 선택

### 앱이 실행되지 않음
- Logcat에서 오류 확인
- `./gradlew clean` 후 다시 빌드
- 기기의 저장소 권한 확인

## 💡 빠른 실행 단축키

- **Run**: `Shift+F10` (Mac: `Ctrl+R`)
- **Debug**: `Shift+F9` (Mac: `Ctrl+D`)
- **Stop**: `Ctrl+F2`

## 📝 다음 단계

앱이 실행되면:
1. 권한 요청 승인 (저장소 접근 권한)
2. "Select Single Image" 버튼 클릭
3. 갤러리에서 이미지 선택
4. 선택한 이미지가 화면에 표시됨

---

**가장 쉬운 방법**: Android Studio에서 상단의 **▶️ Run** 버튼 클릭!

