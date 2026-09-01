# ⚠️ RNTurboImagePicker-Dist — 빌드 산출물입니다. 여기서 코드를 고치지 마세요.

이 폴더는 `RNTurboImagePicker`(형제 폴더, 진짜 소스) 코드를 코드를 숨기기 위해 컴파일한 **배포판**입니다.

- Android: `android/src/main/libs/rnturboimagepicker-release.aar` (컴파일된 바이너리)
- iOS: `ios/RNTurboImagePicker.xcframework` (컴파일된 바이너리)

`ZemTalk.ReactNative`의 `node_modules/react-native-turbo-image-picker`는 이 폴더로 심볼릭 링크돼 있어서, 앱은 실제로 이 폴더를 참조합니다. **하지만 이 폴더의 내용은 빌드 스크립트가 통째로 덮어쓰므로, 여기서 직접 수정한 내용은 다음 빌드 때 사라집니다.**

## 여기서 버그를 발견했다면

1. 실제 수정은 `../RNTurboImagePicker/`(소스 프로젝트)에서 하세요. 그 폴더의 `CLAUDE.md`를 먼저 읽으세요.
2. 수정 후 `ruby scripts/build_and_distribute.rb`(이 폴더 기준)를 실행해서 이 폴더를 다시 동기화하세요.
3. 상세 배포 절차는 `../.agents/rules/deployment_process.md` 참조.
