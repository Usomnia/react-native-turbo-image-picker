# Android Studio 모듈 인식 문제 해결

## 문제
Module 드롭다운에 "app" 모듈이 표시되지 않음

## 해결 방법

### 1단계: Gradle 프로젝트 동기화
1. Android Studio 상단 메뉴: **File → Sync Project with Gradle Files**
2. 또는 툴바에서 Gradle 아이콘 클릭 후 "Sync Project with Gradle Files"

### 2단계: 프로젝트 새로고침 (필요시)
1. **File → Invalidate Caches / Restart...**
2. "Invalidate and Restart" 클릭
3. Android Studio가 재시작되면 자동으로 프로젝트를 다시 인덱싱합니다

### 3단계: Run Configuration 확인
1. **Run → Edit Configurations...**
2. Module 드롭다운을 열어 확인
3. 이제 **"app"** 모듈이 보여야 합니다
4. "app" 모듈 선택
5. Apply 및 OK 클릭

### 4단계: 실행
1. Run 버튼 클릭
2. 또는 **Run → Run 'app'**

## 참고
- `.idea/gradle.xml` 파일에 `app` 모듈이 추가되어 있습니다
- 프로젝트 구조: `app` (실행 가능) + `rnturboimagepicker` (라이브러리)
- `settings.gradle`에 두 모듈이 모두 포함되어 있습니다


