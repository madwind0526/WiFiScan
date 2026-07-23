# Active Context

## Current Focus

- Wave 23에서 RouterConnector 인터페이스 리팩터링을 완료했다(계획 7단계 전부). `discovery/domain/router_connector.dart`의 공통 인터페이스(`id`/`displayName`/`requiresCaptcha`/`matches`/`fetchCaptcha`/`login`/`readDevices`/`close`)를 ipTIME·SK 커넥터가 구현하고, `RouterConnectorRegistry.detect(host)`가 등록 순서대로 `matches`를 시도해 첫 매칭 커넥터를 돌려준다(비매칭은 즉시 close, 매칭분은 호출자가 소유·close). 대시보드 `_openRouterAdmin`은 브랜드 분기 없이 `requiresCaptcha`로만 갈라지고, 팝업은 `_RouterLoginDialog` 하나로 통합(캡차면 이미지+캡차 입력칸 표시, 아니면 저장 자격증명으로 무팝업 자동 로그인). `_isSkGateway`·`_SkLoginDialog` 삭제. 새 공유기 지원 = 인터페이스 구현 + `defaultFactories` 등록만.
- 라이브 검증(실기기): 192.168.0.1은 최신 펌웨어라 `/`가 `login/login.cgi`로 meta-refresh만 하고 ipTIME 표식이 없어 감지에 실패했다 → 탐지 경로를 `/`, `/login/login.cgi`, `/sess-bin/login_session.cgi` 3개로 넓혀 해결. 리팩터된 경로로 감지→로그인→DHCP 5개(호스트네임 4개) 조회까지 실제 성공 확인.
- 192.168.45.1은 gnt2400 펌웨어(login.html + app.js, `goform`/`mcr_verifyLoginPasswd`/`captcha.png`/`szIPInfo` 전부 없음)로 ipTIME도 SK도 아니다. 이제 "자동 조회 미지원, 이름 직접 지정" 안내가 뜬다(예전에는 ipTIME 팝업이 떴다가 로그인 실패). gnt2400 전용 커넥터는 별도 작업 후보.
- `windows_network_discovery_test.dart`, `enriched_windows_network_discovery_test.dart`는 활성 Wi-Fi가 있어야 통과하는 환경 의존 테스트다(현재 유선 연결이라 실패). 라우터 리팩터와 무관.


- Wave 22에서 읽기 전용 ipTIME 공유기 커넥터를 추가했다. 라이브 A6004NS-M로 검증: Dart HttpClient가 비표준 HTTP/1.0을 처리하고, 로그인은 POST `/sess-bin/login_handler.cgi`→`efm_session_id` 쿠키, 관리 페이지는 `timepro.cgi`. 자격증명은 `.env`(DotEnv, gitignore) 또는 공유기별 보안 저장소(`SecureRouterCredentialStore`, 게이트웨이 IP 키)에서 로드하고 절대 추측하지 않는다. 메시의 GW 노드를 클릭하면 해당 게이트웨이 로그인 팝업(`_RouterLoginDialog`)이 뜨고, 로그인 성공 시 DHCP 목록을 읽어 MAC 기준으로 `_dhcpHostnames`에 저장→`_composeDevices`가 자동 이름 위에 호스트네임을 오버레이(사용자 라벨 > DHCP 호스트네임 > 자동). DHCP 파서는 여러 후보 엔드포인트+범용 IP/MAC 레코드 파싱으로 firmware 형식차를 흡수하되, 실제 페이지로 재검증 필요. 사용자 공유기 2대는 서로 다른 서브넷(192.168.0.1, 192.168.45.1)이며 둘 다 현재 위치에서 도달 가능.
- Wave 21에서 MAC(없으면 IP) 기준으로 사용자 지정 이름·소유 상태를 `device_labels.json`에 영구 저장하는 `DeviceLabelRepository`를 추가했다. 장비 상세의 "이름·소유 편집"에서 수정하고, 사용자 이름이 자동 식별보다 우선한다.
- Wave 20에서 조용한 장비의 MAC 제조사 식별을 구현: IEEE 전체 레지스트리(Wireshark manuf, 39,510개 /24 블록)를 `assets/oui/oui_manuf.tsv`로 내장하고 첫 보강 시 1회 로드한다. 큐레이션 시드는 바인딩 없는 테스트 폴백 + 친숙한 라벨(ipTIME 등) 오버라이드로 유지. 랜덤(로컬 관리) MAC은 "임의 MAC 장비"로 구분한다.
- Wave 19에서 전체 스캔이 SSID 전환 직후 DHCP 완료 전에 "활성 Wi-Fi 없음"으로 0장비 실패하던 경쟁 상태를 컨텍스트 읽기 재시도(최대 ~10.5초)로 수정했다. 사용자 실기기 전체 스캔 재검증 대기 중.
- 원격 git 저장소가 없어 push가 불가능하다. gh CLI도 미설치. 사용자에게 원격 URL 또는 GitHub 저장소 생성 여부 확인 필요.
- Wave 18에서 중앙 스캔 버튼과 동일한 앱 아이콘, 중앙 정렬 명사형 배너 문구를 적용한 `1.3.0+9`을 Windows와 Android에 빌드하고 Android 실기기에 설치했다.
- Wave 17에서 모든 동적 상태 배너를 반투명 검정/빨강 배경, 고대비 글씨, 오른쪽 `X` 구조로 통일한 `1.2.3+8`을 빌드했다.
- Wave 16에서 홈 왼쪽 요약을 그래프와 같은 필터 장비 목록에 연결하고, 경고 수도 현재 표시 장비의 warning/critical 기준으로 고친 `1.2.2+7`을 빌드했다.
- Wave 15에서 여러 GW 성단을 하나의 Obsidian형 클라우드에 배치하고 단색 원·5자 라벨·오른쪽 아래 영문 범례·닫을 수 있는 반투명 오류 배너를 적용한 `1.2.1+6`을 빌드했다.
