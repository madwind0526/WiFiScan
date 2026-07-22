# Active Context

## 다음 작업: RouterConnector 인터페이스 리팩터링 (사용자 승인, 미착수)

목적: 공유기 로그인/조회를 "브랜드 하드코딩"에서 "캡차 유무 기준 라우팅 + 커넥터 레지스트리"로 일반화. 기능은 현재와 동일, 구조만 개선해 새 공유기 추가를 쉽게.

현재 상태(리팩터 전): `_openRouterAdmin(host)`가 `_isSkGateway(host)` 브랜드 감지로 `_showSkLogin`(SK) vs `_showRouterLogin`(ipTIME) 분기. 커넥터는 `IptimeRouterConnector`, `SkGatewayConnector` 각각 별도 시그니처.

단계별 계획(순서대로, 각 단계 후 analyze+test+commit 권장):
1. `discovery/domain/router_connector.dart`에 공통 인터페이스 정의:
   - `abstract interface class RouterConnector { String get id; bool get requiresCaptcha; Future<bool> matches(String host); Future<Uint8List>? fetchCaptcha(String host); Future<String> login({host, username, password, captcha}); Future<List<RouterDhcpClient>> readDevices({host, session}); void close(); }`
   - captcha 없는 커넥터는 `requiresCaptcha=false`, `fetchCaptcha`는 null/미사용, `login`의 captcha 인자 무시.
2. `IptimeRouterConnector`가 `RouterConnector` 구현하도록 조정: `requiresCaptcha=false`, `matches`는 `/`나 login 페이지에 `sess-bin`/`login_session` 표식 확인, `login` 시그니처 통일(captcha 무시), `readDevices` 유지.
3. `SkGatewayConnector`가 `RouterConnector` 구현: `requiresCaptcha=true`, `matches`는 `start.asp`/`captchalogin`/`/asp/` 표식, `fetchCaptcha` 구현(이미 있음), `login`/`readDevices` 유지.
4. `RouterConnectorRegistry` (또는 top-level `detectRouterConnector(host)`): 등록된 커넥터들의 `matches(host)`를 순서대로 시도해 첫 매칭 반환, 없으면 null(미지원).
5. 대시보드 `_openRouterAdmin(host)` 재작성:
   - `final connector = await detectRouterConnector(host);`
   - null(미지원) → 스낵바/메시지 "이 공유기는 자동 조회를 지원하지 않습니다. 장비 상세에서 이름을 직접 지정하세요." (수동 라벨링 폴백)
   - `connector.requiresCaptcha` true → 캡차 팝업(현재 `_SkLoginDialog`를 커넥터 주입형 `_CaptchaLoginDialog`로 일반화), false → 자동 로그인(저장 자격증명 시 팝업 skip, 현재 `_showRouterLogin` 로직) + 실패 시 팝업.
   - 로그인 결과 `List<RouterDhcpClient>` → 기존 `_applyDhcpClients(host, result)` 재사용(공통).
6. `_isSkGateway` 제거, `_SkLoginDialog`/`_RouterLoginDialog`를 커넥터 주입형으로 통합(캡차 유무로 UI만 분기). 자동 로그인은 `requiresCaptcha=false`일 때만.
7. 테스트: 레지스트리 감지(모의 커넥터), 인터페이스 준수. 기존 파서/해싱 테스트 유지. widget_test의 GW 탭은 감지 실패 시 미지원 폴백 or ipTIME 경로 — fake 조정 필요할 수 있음.

주의: "최신 ipTIME 캡차" 지원은 별개 작업(ipTIME 커넥터에 캡차 방식 추가; SK와 다름). 이번 리팩터 범위 밖.

## Current Focus

- Wave 22에서 읽기 전용 ipTIME 공유기 커넥터를 추가했다. 라이브 A6004NS-M로 검증: Dart HttpClient가 비표준 HTTP/1.0을 처리하고, 로그인은 POST `/sess-bin/login_handler.cgi`→`efm_session_id` 쿠키, 관리 페이지는 `timepro.cgi`. 자격증명은 `.env`(DotEnv, gitignore) 또는 공유기별 보안 저장소(`SecureRouterCredentialStore`, 게이트웨이 IP 키)에서 로드하고 절대 추측하지 않는다. 메시의 GW 노드를 클릭하면 해당 게이트웨이 로그인 팝업(`_RouterLoginDialog`)이 뜨고, 로그인 성공 시 DHCP 목록을 읽어 MAC 기준으로 `_dhcpHostnames`에 저장→`_composeDevices`가 자동 이름 위에 호스트네임을 오버레이(사용자 라벨 > DHCP 호스트네임 > 자동). DHCP 파서는 여러 후보 엔드포인트+범용 IP/MAC 레코드 파싱으로 firmware 형식차를 흡수하되, 실제 페이지로 재검증 필요. 사용자 공유기 2대는 서로 다른 서브넷(192.168.0.1, 192.168.45.1)이며 둘 다 현재 위치에서 도달 가능.
- Wave 21에서 MAC(없으면 IP) 기준으로 사용자 지정 이름·소유 상태를 `device_labels.json`에 영구 저장하는 `DeviceLabelRepository`를 추가했다. 장비 상세의 "이름·소유 편집"에서 수정하고, 사용자 이름이 자동 식별보다 우선한다.
- Wave 20에서 조용한 장비의 MAC 제조사 식별을 구현: IEEE 전체 레지스트리(Wireshark manuf, 39,510개 /24 블록)를 `assets/oui/oui_manuf.tsv`로 내장하고 첫 보강 시 1회 로드한다. 큐레이션 시드는 바인딩 없는 테스트 폴백 + 친숙한 라벨(ipTIME 등) 오버라이드로 유지. 랜덤(로컬 관리) MAC은 "임의 MAC 장비"로 구분한다.
- Wave 19에서 전체 스캔이 SSID 전환 직후 DHCP 완료 전에 "활성 Wi-Fi 없음"으로 0장비 실패하던 경쟁 상태를 컨텍스트 읽기 재시도(최대 ~10.5초)로 수정했다. 사용자 실기기 전체 스캔 재검증 대기 중.
- 원격 git 저장소가 없어 push가 불가능하다. gh CLI도 미설치. 사용자에게 원격 URL 또는 GitHub 저장소 생성 여부 확인 필요.
- Wave 18에서 중앙 스캔 버튼과 동일한 앱 아이콘, 중앙 정렬 명사형 배너 문구를 적용한 `1.3.0+9`을 Windows와 Android에 빌드하고 Android 실기기에 설치했다.
- Wave 17에서 모든 동적 상태 배너를 반투명 검정/빨강 배경, 고대비 글씨, 오른쪽 `X` 구조로 통일한 `1.2.3+8`을 빌드했다.
- Wave 16에서 홈 왼쪽 요약을 그래프와 같은 필터 장비 목록에 연결하고, 경고 수도 현재 표시 장비의 warning/critical 기준으로 고친 `1.2.2+7`을 빌드했다.
- Wave 15에서 여러 GW 성단을 하나의 Obsidian형 클라우드에 배치하고 단색 원·5자 라벨·오른쪽 아래 영문 범례·닫을 수 있는 반투명 오류 배너를 적용한 `1.2.1+6`을 빌드했다.
