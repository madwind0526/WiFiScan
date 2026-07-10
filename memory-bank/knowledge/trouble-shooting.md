# Trouble Shooting

확인된 문제와 재현 가능한 해결법을 이 파일에 누적한다.

## Windows runner 한국어 문자열 빌드 오류

- 확인일: 2026-07-10
- 증상: `main.cpp`의 한국어 창 제목 때문에 MSVC 경고 `C4819`가 발생하고, 경고가 오류로 처리되어 Windows 빌드가 실패했다.
- 원인: MSVC가 소스 파일을 기본 코드페이지 CP949로 해석했다.
- 해결: `windows/runner/CMakeLists.txt`의 runner target에 MSVC `/utf-8` 컴파일 옵션을 추가했다.
- 검증: `flutter build windows --debug`가 성공하고 `build/windows/x64/runner/Debug/wifi_scan.exe`가 생성됐다.
