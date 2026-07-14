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

## file_picker 11.x API 변경

- 확인일: 2026-07-14
- 증상: `FilePicker.platform.pickFiles(...)` 호출 시 `The getter 'platform' isn't defined` 컴파일 오류.
- 원인: file_picker 11.0부터 `FilePicker.platform` 인스턴스 접근이 제거되고 `FilePicker.pickFiles(...)`, `FilePicker.saveFile(...)` 정적 메서드로 바뀌었다.
- 해결: 정적 메서드로 직접 호출. `saveFile`은 데스크톱에서 경로만 반환하므로 파일 쓰기는 직접 수행한다(모바일은 `bytes` 파라미터로 저장됨).
- 검증: flutter analyze 통과, Windows 빌드 성공.

## 고정 높이 아이콘 바의 큰 글자 배율 오버플로

- 확인일: 2026-07-14
- 증상: textScaleFactor 2 환경(접근성 테스트)에서 고정 높이(58/66px) 상단 바와 하단 탭 바가 RenderFlex overflow를 발생시켰다.
- 원인: 고정 높이 컨테이너 안의 라벨 텍스트가 배율에 비례해 커진다.
- 해결: 바 내부를 `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, ...)`으로 감싸고, 제목 텍스트는 `Expanded` + ellipsis로 처리했다.
- 검증: 320×568 + textScale 2 위젯 테스트 통과.

## file_picker 11 + AGP 9 legacy Kotlin에서 Android 플러그인 클래스 누락

- 확인일: 2026-07-14
- 증상: `flutter build apk --debug`에서 `GeneratedPluginRegistrant.java`가 `FilePickerPlugin`을 찾지 못해 실패했다.
- 원인: 프로젝트는 다른 플러그인 호환성을 위해 `android.builtInKotlin=false`를 사용하지만, file_picker 11.0.2는 AGP 9 이상이면 Kotlin Gradle Plugin과 JVM target 설정을 생략해 Kotlin 소스가 컴파일되지 않았다.
- 해결: 루트 `android/build.gradle.kts`에서 `file_picker` 서브프로젝트에만 `org.jetbrains.kotlin.android`를 적용하고 Kotlin JVM target을 17로 지정했다. 보안 수정이 포함된 file_picker 11.0.2는 유지했다.
- 검증: `flutter build apk --debug` 성공, `build/app/outputs/flutter-apk/app-debug.apk` 생성.
- 후속: 모든 Android 플러그인이 AGP 9 built-in Kotlin을 지원하면 이 한정 우회를 제거하고 built-in Kotlin으로 전환한다.

## 다이얼로그 닫힘 중 TextEditingController 조기 dispose

- 확인일: 2026-07-14
- 증상: 프로필 편집창에서 키보드를 연 채 취소하면 `A TextEditingController was used after being disposed` 예외가 발생했다.
- 원인: `showDialog` Future는 route 역방향 애니메이션이 완전히 끝나기 전에 완료될 수 있는데, 호출 메서드가 Future 완료 직후 controller를 dispose했다.
- 해결: 프로필 편집 UI를 전용 `StatefulWidget`으로 분리하고 controller를 State가 소유하도록 했다. 저장 결과만 `Navigator.pop`으로 반환하고 controller는 State의 실제 `dispose` 시점에 정리한다.
- 검증: 320×568, textScale 2, viewInsets bottom 260 조건에서 입력 후 취소와 저장 모두 통과하고 전체 위젯 테스트 통과.

## 앱 고정 키 passwordEnc를 OS 보안 저장소로 이전

- 확인일: 2026-07-15
- 증상: 프로필 JSON의 `passwordEnc`는 평문은 아니지만 앱에 포함된 고정 seed로 복호화할 수 있어 기기 보안 경계와 분리되지 않았다.
- 원인: 로컬 저장과 기기 간 내보내기가 같은 앱 고정 키 암호화 경로를 공유했다.
- 해결: 새 암호는 `flutter_secure_storage`에 프로필별로 저장하고 메타데이터 JSON에는 암호 필드를 쓰지 않는다. 기존 `passwordEnc`는 로드 시 복호화해 보안 저장소로 옮긴 뒤 모든 이전이 성공한 경우에만 JSON에서 제거한다. 내보내기는 별도의 사용자 암호 기반 PBKDF2-HMAC-SHA256 + AES-256-GCM 포맷으로 분리했다.
- 검증: 메타데이터 비밀값 부재, 보안 저장소 복원, 프로필 삭제, 기존 형식 이전 단위 테스트와 암호 내보내기/불러오기 위젯 테스트 통과. Android debug APK 및 Windows release 빌드 성공.

## Windows multicast_dns reusePort 소켓 오류

- 확인일: 2026-07-15
- 증상: 실제 Windows 네트워크에서 `multicast_dns` 기본 소켓 팩터리로 mDNS 조회를 시작하면 `reusePort` 관련 소켓 오류가 발생했다.
- 원인: Windows의 UDP 소켓 구현이 패키지 기본 `reusePort: true` 조합을 지원하지 않는다.
- 해결: Windows에서만 `RawDatagramSocket.bind`를 `reuseAddress: true`, `reusePort: false`로 호출하는 소켓 팩터리를 주입하고 다른 플랫폼은 패키지 기본값을 사용한다. Android는 조회 기간에만 `WifiManager.MulticastLock`을 획득하고 `finally`에서 해제한다.
- 검증: 실제 Windows 보강 통합 테스트에서 소켓 오류 없이 완료하고, 전체 22개 테스트와 Windows release 및 Android debug APK 빌드가 통과했다.
