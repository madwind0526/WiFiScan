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

## 동시 활성 Ethernet 때문에 Wi-Fi 게이트웨이를 잘못 선택

- 확인일: 2026-07-15
- 증상: Wi-Fi를 `192.168.45.x` 네트워크로 전환해도 검색 결과 게이트웨이와 장비가 Ethernet의 `192.168.0.1` 기준으로 반복됐다.
- 원인: `Get-NetIPConfiguration` 결과에서 기본 게이트웨이가 있는 첫 인터페이스를 골라, Ethernet과 Wi-Fi가 동시에 활성일 때 Ethernet이 선택됐다.
- 해결: `NetAdapter.NdisPhysicalMedium == 9`인 활성 Wi-Fi 후보만 선택하고 Wi-Fi가 없으면 명시적 오류를 반환한다. 네트워크 행에는 서브넷 관측 수와 게이트웨이를 함께 표시한다.
- 검증: Ethernet `192.168.0.1`과 Wi-Fi `192.168.45.1` 후보 단위 테스트, Ethernet-only 거부 테스트, 실제 Windows Wi-Fi 탐색, 전체 30개 테스트와 Windows release 빌드 통과.

## 화면과 실행 파일의 빌드 버전 불일치

- 확인일: 2026-07-15
- 증상: 기능을 추가해 재빌드해도 대시보드가 계속 `v1.0.0`을 표시했다.
- 원인: pubspec 버전과 대시보드 표시 상수가 별도로 고정되어 있었고 기능 빌드 과정에서 버전을 올리지 않았다.
- 해결: 릴리스 버전을 `1.1.0+2`로 올리고 화면 표시, 위젯 테스트, Windows 실행 파일 버전을 일치시켰다.
- 검증: Windows 실행 파일의 ProductVersion과 FileVersion이 모두 `1.1.0+2`이며 실행 프로세스가 정상 응답했다.

## 같은 서브넷의 Ethernet으로 Wi-Fi 탐색 ping이 우회

- 확인일: 2026-07-15
- 증상: `Madwind-H/L` 검색에는 현재 PC만 보이지만 같은 SSID에 연결된 모니터와 휴대폰이 누락됐다.
- 원인: Ethernet과 Wi-Fi가 모두 `192.168.0.0/24`이고 인터페이스 메트릭이 Ethernet 25, Wi-Fi 40이었다. 출발 주소를 지정하지 않은 ping은 Ethernet으로 나가지만 결과 수집은 Wi-Fi 이웃 테이블에서 수행해 이웃 항목이 충분히 생성되지 않았다.
- 해결: `ping.exe -S <Wi-Fi IPv4>`로 모든 probe를 현재 Wi-Fi 주소에 바인딩한다.
- 검증: ping 인자 단위 테스트, 실제 Windows Wi-Fi 탐색, 전체 31개 테스트와 Windows release 빌드 통과. 유효한 Wi-Fi 동적 이웃은 진단 시 2개에서 4개로 증가했고 실행 파일 버전은 `1.1.1+3`이다.

## 삭제한 네트워크 프로필이 앱 시작 시 다시 생성

- 확인일: 2026-07-15
- 증상: WifiScan 프로필 관리에서 SSID를 삭제해도 앱을 다시 열면 같은 항목이 생성됐다.
- 원인: 삭제는 로컬 메타데이터와 보안 저장소에서 정상 처리됐지만, 시작 시 Windows 저장 WLAN 프로필 전체를 다시 탐색해 누락된 SSID를 자동 병합했다.
- 해결: 삭제 SSID를 별도 로컬 suppression 목록에 기록하고 자동 탐색 병합에서 제외한다. 직접 추가 또는 암호화 백업 가져오기는 명시적 복원으로 처리해 suppression을 해제한다. Windows WLAN 프로필은 변경하지 않는다.
- 검증: suppression 저장·재로드·해제 단위 테스트, 삭제 후 앱 재시작 위젯 테스트, 전체 33개 테스트와 Windows release 빌드 통과. 실행 파일 버전은 `1.1.2+4`이다.

## 메시 간선이 원 중심에서 벗어남

- 확인일: 2026-07-16
- 증상: 그래프 간선은 배치 좌표에서 끝나지만 원은 해당 좌표보다 위에 보여 중심이 맞지 않았고, 입체 그라데이션과 신규 장비 점이 화면을 복잡하게 만들었다.
- 원인: 72px 노드 위젯을 배치 좌표에서 28px 위로 옮겼지만 위젯 내부 원 중심은 상단에서 21px 위치에 있어 7px 오차가 생겼다.
- 해결: 노드 위젯 상단을 배치 좌표에서 21px 위로 맞추고 단색 원으로 변경했다. 미확인 라벨과 신규 점을 제거하고 오른쪽 아래 영문 범례를 라벨 오른쪽 정렬 + 원 구조로 바꿨다.
- 검증: 560×900 Windows 실제 화면에서 간선 중심, `GW`, `내 PC`, 이름 없는 미확인 원, `WiFi/PC/Phone/TV/Home` 범례를 확인했고 전체 40개 테스트가 통과했다.

## 동적 메시 갱신 후 그래프가 확대 상태로 남음

- 확인일: 2026-07-16
- 증상: 여러 네트워크 스캔이 끝난 직후 일부 큰 노드만 보이고 나머지 노드가 화면 밖으로 잘렸다. 수동 전체 맞춤을 누르면 정상 크기로 표시됐다.
- 원인: 새 레이아웃의 첫 전체 맞춤과 `InteractiveViewer`의 초기 변환 연결 시점이 같은 프레임에서 겹쳐 맞춤 변환이 초기값으로 돌아갔다.
- 해결: 레이아웃 변경 직후 전체 맞춤을 적용하고 다음 프레임에도 한 번 더 적용한다. 여러 GW에는 표시하지 않는 배치용 스프링만 사용해 한 클라우드 안에서 성단 간격을 유지한다.
- 검증: 자동 맞춤과 다중 GW 거리 단위 테스트, Windows release 실행 화면의 전체 노드 표시를 확인했다.

## 홈 요약 장비 수가 현재 그래프와 다름

- 확인일: 2026-07-16
- 증상: 검색 또는 네트워크 필터로 그래프에 일부 장비만 표시해도 왼쪽 아래 장비 수와 경고 수는 전체 누적 인벤토리 값을 유지했다.
- 원인: 그래프는 `_filteredDevices`를 사용했지만 `_MiniSummary`는 `_overview.devices`와 전체 findings를 직접 참조했다.
- 해결: 홈 빌드에서 한 번 계산한 `visibleDevices`를 그래프와 요약에 함께 전달한다. 경고는 표시 장비 ID에 귀속된 warning/critical만 계산하고, 필터가 없을 때만 네트워크 수준 경고를 포함한다.
- 검증: 장비 검색으로 2개 중 1개만 표시한 뒤 홈 요약이 장비 `1`, 경고 `0`으로 바뀌는 위젯 회귀 테스트와 전체 40개 테스트를 통과했다.

## Wi-Fi 프로필 전환 직후 스캔이 장비 0개로 즉시 실패

- 확인일: 2026-07-17
- 증상: 전체 네트워크 스캔이 SSID를 전환하며 돌 때 4개 네트워크 모두 "연결하지 못했습니다"로 즉시 빠지고 장비 0개가 기록됐다. 같은 코드가 안정 연결 상태에서는 통과했다.
- 원인: `netsh wlan connect`는 SSID 연결(association)까지만 확인하고 반환하는데, DHCP 주소 할당은 그 뒤 몇 초가 더 걸린다. 그 사이 `Get-NetIPConfiguration`은 Wi-Fi 어댑터에 유효한 사설 IPv4가 없다고 보고하고(APIPA 169.254.*는 필터됨), 탐색이 "활성 Wi-Fi 연결을 찾지 못했습니다"로 즉시 실패했다.
- 해결: `WindowsNetworkDiscoveryService._readPrimaryNetworkContext`를 재시도 루프로 감쌌다(`contextReadAttempts` 기본 7회 × `contextRetryDelay` 1.5초 ≈ 최대 10.5초). 재시도 사이에 취소 토큰을 확인한다.
- 검증: flutter analyze 통과, 실제 Windows 라이브 스캔 통합 테스트 포함 41개 테스트 전체 통과.

## ipTIME(A6004NS-M) 읽기 전용 커넥터 — 실제 로그인/DHCP 흐름

- 확인일: 2026-07-18 (라이브 A6004NS-M, 펌웨어 12.07.8)
- 증상: Dart 커넥터 로그인이 "로그인은 되었지만 세션 정보를 읽지 못했습니다"로 실패. 브라우저·curl 로그인은 정상.
- 원인 1 (400): Dart HttpClient가 POST 본문을 chunked 전송으로 보내는데 공유기의 `Httpd/1.0` 서버가 chunked를 거부하고 `400 Bad Request` 반환. → `request.contentLength = bodyBytes.length; request.add(bodyBytes);`로 Content-Length 고정.
- 원인 2 (세션): 이 공유기는 세션을 Set-Cookie 헤더가 아니라 응답 본문의 JS `setCookie('<16자 영숫자>')`로 전달(브라우저가 실행해 `efm_session_id` 쿠키 설정). → 본문에서 `setCookie\('([^']+)'\)` 정규식으로 추출.
- 로그인: `POST /sess-bin/login_handler.cgi`, 필드 `init_status=1&captcha_on=0&username&passwd&default_passwd=&captcha_file=&captcha_code=`, Referer=`/sess-bin/login_session.cgi`. 로그인 폼 페이지는 gzip 강제라 `Accept-Encoding: gzip` 필요(Dart autoUncompress 기본 처리). 실패 시 본문이 `login_session.cgi?noauto=1`로 되돌림.
- DHCP 목록: `GET /sess-bin/timepro.cgi?tmenu=iframe&smenu=lan_pcinfo_status`(중첩 iframe), Referer=`...smenu=lan_pcinfo`, 쿠키 `efm_session_id`. 데이터는 인덱스별 숨김 input `name=m<N>`(MAC)/`i<N>`(IP)/`h<N>`(호스트네임). 반복 로그인은 캡차를 유발할 수 있음.
- 검증: 실제 로그인으로 호스트네임 5개(madwind99, Samsung, hyojeong-ui-Z-Flip7, SM-L505N 등) 조회. 파서 단위 테스트 + 전체 70 tests 통과.
