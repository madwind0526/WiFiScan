# Trouble Shooting

확인된 문제와 재현 가능한 해결법을 이 파일에 누적한다.

## Windows runner 한국어 문자열 빌드 오류

- 확인일: 2026-07-10
- 증상: `main.cpp`의 한국어 창 제목 때문에 MSVC 경고 `C4819`가 발생하고, 경고가 오류로 처리되어 Windows 빌드가 실패했다.
- 원인: MSVC가 소스 파일을 기본 코드페이지 CP949로 해석했다.
- 해결: `windows/runner/CMakeLists.txt`의 runner target에 MSVC `/utf-8` 컴파일 옵션을 추가했다.
- 검증: `flutter build windows --debug`가 성공하고 `build/windows/x64/runner/Debug/wifi_scan.exe`가 생성됐다.

## 위젯 테스트에서 실제 netsh 프로세스 호출로 인한 실패

- 확인일: 2026-07-14
- 증상: `_startScan` 경로에 `Process.run('netsh', ...)`(currentSsid 조회)이 추가되자 `pumpAndSettle` 이후에도 완료 메시지가 나타나지 않고 위젯 테스트가 실패했다.
- 원인: `testWidgets`는 FakeAsync 존에서 실행되므로 실제 프로세스 IO의 완료 이벤트가 `pumpAndSettle` 안에서 전달되지 않는다. fire-and-forget 호출은 티가 안 나지만, UI 상태 갱신의 critical path에 들어가면 테스트가 멈춘다.
- 해결: `NetworkConnectionService`를 `WifiScanApp`/`SecurityDashboardPage` 생성자 파라미터로 주입 가능하게 만들고, 테스트에서는 즉시 반환하는 `_FakeConnectionService`를 전달했다.
- 검증: `flutter test` 전체 통과.

## 고정 높이 아이콘 바의 큰 글자 배율 오버플로

- 확인일: 2026-07-14
- 증상: textScaleFactor 2 환경(접근성 테스트)에서 고정 높이(58/66px) 상단 바와 하단 탭 바가 RenderFlex overflow를 발생시켰다.
- 원인: 고정 높이 컨테이너 안의 라벨 텍스트가 배율에 비례해 커진다.
- 해결: 바 내부를 `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, ...)`으로 감싸고, 제목 텍스트는 `Expanded` + ellipsis로 처리했다.
- 검증: 320×568 + textScale 2 위젯 테스트 통과.
