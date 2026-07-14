# WifiScan Design

## Product Definition

WifiScan은 사용자가 소유하거나 관리 권한을 가진 로컬 Wi-Fi/LAN에서 다음 질문에 답한다.

1. 지금 또는 최근에 어떤 장비가 연결되었는가?
2. 새롭거나 신원을 확인하지 못한 장비가 있는가?
3. 각 장비에서 관측 가능한 잠재적 보안 위험은 무엇인가?
4. 사용자가 안전하게 취할 수 있는 방어 조치는 무엇인가?

주요 사용자는 가정 또는 소규모 네트워크 관리자다. 휴대폰, 컴퓨터, TV, 셋톱박스, 카메라, 스피커, 프린터, 공유기, 생활가전, 기타 IoT 장비를 대상으로 한다.

## UI Direction

Bluetooth-Comm과 Connection-map의 사용성을 참고해 화면은 모바일 세로 캔버스를 기준으로 한다. Windows도 기본 창을 560x900 세로형으로 열고 콘텐츠 폭을 560px 이하로 제한해 휴대폰과 같은 정보 밀도와 조작 흐름을 유지한다.

- 상단: 장비 검색 입력창, 메시/카드/목록 보기 전환, 설정
- 중앙: 나를 중심으로 일정 거리 안에 장비를 배치한 메시 결과 맵
- 하단: 홈·장비·경고 메뉴와 중앙 스캔 버튼
- 장비 클릭: 반투명 정보 대화상자에서 IP, MAC, 제조사, 탐색 근거, 신뢰도, 확인 시각 표시
- 네트워크 프로필: 연결 가능한 SSID를 등록하고 전체 네트워크를 순차적으로 스캔

아이콘 중심 표현을 유지하되 Tooltip과 Semantics label을 함께 제공한다. 설정의 Theme 선택은 Light/Dark 두 가지를 유지하며 향후 표시 옵션과 탐색 옵션을 확장할 수 있게 한다.

## Scope and Completeness

“모든 장비”는 제품 목표지만 단일 단말 스캔으로 100% 보장할 수는 없다. 다음 상황에서는 장비가 보이지 않을 수 있다.

- 장비가 절전 또는 오프라인 상태
- 단말 방화벽이 탐색 요청을 무시함
- 공유기의 AP/client isolation이 적용됨
- 장비가 다른 VLAN, 게스트망, 메시 노드 뒤에 있음
- IPv4와 IPv6 관측 범위가 다름
- 공유기 제조사가 접속 목록 API를 제공하지 않음

따라서 결과에는 마지막 확인 시각, 관측 소스, 신뢰도, 탐지 한계를 표시한다. “탐지되지 않음”을 “안전함”으로 간주하지 않는다.

## Discovery Strategy

관측 결과를 공통 `DeviceObservation` 형식으로 정규화하고 하나의 장비 자산으로 연결한다.

1. **공유기 관측**: DHCP lease, ARP/neighbor, 현재 접속 목록. 사용자 인증과 제조사별 공식/허용 API가 있을 때 사용한다.
2. **로컬 호스트 탐색**: 현재 서브넷에 속도 제한된 연결 가능성 확인. 사용자 시작 방식이 기본이다.
3. **서비스 탐색**: Android NSD/mDNS, SSDP 등 장비가 스스로 공개한 서비스 수집.
4. **수동 확인**: 사용자가 장비 이름, 유형, 소유 여부를 확인해 식별 정확도를 높인다.
5. **변화 감지**: 이전 스냅샷과 비교해 신규, 사라짐, 주소 변경, 서비스 변경을 표시한다.

### Wave 2 Windows PoC

현재 PoC는 Windows에서 기본 게이트웨이가 있는 활성 사설 IPv4 인터페이스를 선택한다. 현재 주소가 포함된 네트워크를 최대 `/24`로 제한하고, 호스트별 ICMP 요청 1회로 neighbor cache를 갱신한 다음 `Get-NetNeighbor` 결과를 공통 장비 모델로 변환한다. 로컬 Windows 장비와 기본 게이트웨이도 결과에 포함한다.

이 단계에서는 mDNS/SSDP, 공유기 제조사 API, Android native 탐색을 아직 연결하지 않았다. 장비가 응답하지 않거나 다른 네트워크 세그먼트에 있으면 결과에 나타나지 않을 수 있다.

### 정보 확장 계획

현재 기본 결과는 IP, MAC(플랫폼이 제공하는 경우), 장비 유형, 관측 근거, 신뢰도, 확인 시각이다. 다음 정보를 추가하면 운영체제 기본 목록보다 풍부한 장비 설명을 제공할 수 있다.

- 로컬 역방향 DNS와 mDNS/SSDP 이름
- 제한된 TCP 연결 확인을 통한 공개 서비스/포트 목록
- 로컬 OUI 데이터베이스를 이용한 MAC 제조사 추정
- 사용자가 승인한 공유기 공식 API의 DHCP lease, 무선 연결 품질, 펌웨어 정보
- 장비가 공개한 모델·펌웨어 문자열과 공식 지원 상태 비교

서비스 확인은 속도 제한, 연결 시간 제한, 사용자 중단, 외부 전송 금지를 기본으로 하며, 포트가 열려 있다는 사실만으로 취약점이나 침해를 확정하지 않는다.

### 다중 네트워크 순회

현재 연결된 Wi-Fi 하나만으로는 별도 공유기·서브넷의 장비를 볼 수 없다. 사용자가 등록한 네트워크 프로필을 순서대로 연결하고 각 네트워크를 독립적으로 검색한 뒤 결과를 통합한다. Windows는 OS에 저장된 WLAN 프로필을 사용한다. 사용자가 WifiScan에 직접 입력한 Wi-Fi 암호는 일반 프로필 JSON과 분리해 운영체제 보안 저장소에 보관하고 연결 시에만 메모리로 불러온다. Android는 `WifiNetworkSpecifier` 시스템 승인 흐름을 사용하며 기기별 동시 연결 지원 여부에 따라 결과가 달라질 수 있다.

각 순회 작업은 시작 전 현재 SSID를 기억하고, 완료·취소·실패 후 원래 연결 복원을 시도한다. 복원이 실패하면 사용자에게 즉시 표시하고 자동으로 다른 네트워크를 계속 변경하지 않는다.

### 프로필 보안 저장과 백업

로컬 `network_profiles.json`에는 SSID, 표시 이름, 최근 검색 시각만 저장하고 Wi-Fi 암호는 저장하지 않는다. Wi-Fi 암호는 프로필 ID에서 해시한 저장 키로 `flutter_secure_storage`에 보관한다. 기존 앱 파일의 `passwordEnc` 값은 최초 로드 시 복호화해 보안 저장소로 옮기고, 모든 이전이 성공한 뒤 파일에서 제거한다. Android 자동 백업은 비활성화해 다른 기기의 Keystore와 맞지 않는 암호문이 복원되는 상황을 피한다.

내보내기 파일은 Bluetooth-Comm의 신원 백업 구조를 참고한 버전형 JSON 봉투를 사용한다. 사용자가 8자 이상의 내보내기 암호를 입력하고 한 번 더 확인하면, 무작위 16바이트 salt와 PBKDF2-HMAC-SHA256 600,000회로 256비트 키를 만들고 무작위 12바이트 nonce의 AES-256-GCM으로 전체 프로필 payload를 암호화한다. 내보내기 암호 자체는 앱에 저장하지 않는다. 불러오기는 파일 선택 후 같은 암호를 입력해야 하며, 잘못된 암호와 파일 손상은 동일한 오류로 처리한다.

### Wave 3 Inventory

탐색 결과는 로컬 JSON 스냅샷으로 저장하며 최근 30개만 유지한다. 장비 식별은 MAC 주소를 우선하고, MAC이 없는 관측은 IP 주소를 보조 키로 사용한다. 첫 검색은 기준선으로만 저장해 기존 장비를 신규 경고하지 않는다. 같은 네트워크의 다음 검색부터 신규, 사라짐, 주소/서비스 변경을 계산한다.

### Wave 4 Risk Analysis

현재 위험 규칙은 관측 가능한 사실만 경고한다. 소유자 미확인 장비, 기준선 이후 새로 나타난 장비, 검색 범위 제한을 발견사항으로 만들고 각 항목에 근거, 신뢰도, 영향, 권장 조치를 포함한다. 제품/펌웨어 정보가 없는 장비에는 CVE나 침해 여부를 확정하지 않는다.

### Wave 5 Remediation Boundary

공식 공유기 커넥터가 없는 상태에서는 자동 차단·격리·설정 변경을 수행하지 않고 수동 대응 절차만 제공한다. 커넥터를 추가할 때도 변경 미리보기, 사용자 명시 승인, 확인 문구, 복구 가능성을 통과해야 실행할 수 있다.

### Wave 6 Android Path

Android는 권한 안내 화면 뒤에 플랫폼 채널로 로컬 네트워크 권한을 요청하고, 현재 연결된 사설 IPv4 컨텍스트를 읽은 뒤 최대 `/24` 범위의 제한된 호스트 탐색을 수행한다. 응답 가능한 호스트만 확인하며 MAC 주소와 mDNS/SSDP는 후속 확장 대상이다. 실제 Android 실기기는 현재 연결되지 않아 빌드와 자동 테스트까지만 검증했다.

## Device Inventory Model

- 내부 장비 ID
- 사용자 지정 이름
- 장비 유형
- 소유/확인 상태
- IPv4/IPv6 주소와 MAC 주소
- 제조사 추정값과 근거
- 관측된 서비스와 포트
- 최초/마지막 확인 시각
- 관측 소스 목록
- 식별 신뢰도

네트워크 식별자는 민감한 로컬 정보로 취급한다. 외부 전송은 기본적으로 금지한다.

## Security Findings

초기 비침투 점검 범위는 다음과 같다.

- 새 장비 또는 사용자가 확인하지 않은 장비
- 불필요하거나 평문인 관리 서비스의 노출 가능성
- 장비가 공개한 제품/펌웨어 정보와 공식 지원 상태의 불일치
- 공유기에서 확인 가능한 취약한 Wi-Fi/관리 설정
- IoT 장비와 개인 단말이 분리되지 않은 네트워크 구성
- 과거 기준선과 비교한 서비스 또는 통신 특성 변화

각 발견사항은 `심각도 + 근거 + 신뢰도 + 영향 + 권장 조치`를 포함한다. 제품과 버전이 확인되지 않으면 특정 CVE 취약 판정을 확정하지 않는다.

## Remediation Policy

### 기본 대응

- 즉시 경고
- 장비 소유 여부 확인
- 공식 펌웨어 업데이트 안내
- 공유기에서 장비 차단 또는 게스트/IoT 네트워크로 이동 안내
- 기본 관리자 암호 변경과 불필요 서비스 비활성화 안내

### 승인 기반 자동 대응

다음 조건을 모두 만족할 때만 자동 조치를 제공한다.

- 사용자가 대상 장비 또는 공유기의 관리 권한을 보유함
- 제조사 공식 관리 API 또는 검증된 로컬 관리 인터페이스 사용
- 적용할 변경과 예상 영향을 미리 표시
- 사용자가 명시적으로 확인
- 실패 처리와 가능한 복구 절차 존재
- 실행 결과와 시간 기록

임의 펌웨어 설치, 취약점 악용, 비밀번호 대입, 트래픽 차단 공격은 구현하지 않는다.

## Android Platform Requirements

- Android 13 이상에서 주변 Wi-Fi API 사용 시 `NEARBY_WIFI_DEVICES` 런타임 권한을 고려한다.
- Wi-Fi scan result 관련 일부 API는 위치 권한 요구가 남아 있으므로 실제 사용하는 API별로 분리한다.
- Android 17/API 37 이상을 타깃으로 로컬 LAN 소켓을 사용하면 `ACCESS_LOCAL_NETWORK` 런타임 권한 또는 시스템 중개 탐색 경로가 필요하다.
- 권한 요청 전에 한국어 근거 화면을 보여주고 거부/철회 상태에서도 앱이 정상 동작해야 한다.

## Architecture

```text
Router / subnet / NSD / mDNS / SSDP observations
                    |
                    v
         Observation normalization
                    |
                    v
       Device identity correlation
                    |
          +---------+---------+
          |                   |
          v                   v
  Inventory snapshots    Security checks
          |                   |
          +---------+---------+
                    v
       Evidence-based findings
                    |
          +---------+---------+
          |                   |
          v                   v
   Warning/guidance    Approved connectors
```

## Delivery Roadmap

| Wave | 내용 | 상태 |
|---|---|---|
| 0 | 독립 프로젝트 구조와 Flutter 기본 앱 | 완료 |
| 1 | 제품 범위, 안전 경계, 도메인 모델, 대시보드 | 완료 |
| 2 | 현재 네트워크 정보와 비침투 장비 탐색 PoC | 완료 |
| 3 | 장비 식별, 스냅샷, 신규 장비 감지 | 완료 |
| 4 | 근거 기반 위험 분석과 경고 | 완료 |
| 5 | 공유기 커넥터와 승인 기반 방어 조치 | 완료 |
| 6 | Android 권한/성능/회귀 검증 흐름 | 완료 |
| 7 | 세로형 아이콘 셸 UI와 네트워크별 스캔 | 완료 |
| 8 | Android APK 빌드 및 프로필 입력 다이얼로그 회귀 수정 | 완료 |
| 9 | OS 보안 저장소와 암호 기반 프로필 가져오기/내보내기 | 완료 |

## Verification Gates

- 권한 허용, 거부, 철회 흐름
- 스캔 시작, 진행, 취소, 재시도
- 작은 서브넷과 큰 서브넷에서 속도 제한과 UI 응답성
- IPv4/IPv6, 게스트망, AP 격리 환경의 한계 표시
- 작은 화면, 큰 시스템 글꼴에서 overflow 없음
- 민감한 네트워크 식별자가 로그나 외부 요청에 포함되지 않음
- 자동 대응 전 미리보기와 명시적 확인
- `flutter analyze`, `flutter test`, Android/Windows 빌드 통과
- Windows 실제 네트워크에서 식별자를 로그로 출력하지 않고 탐색 결과 구조만 검증

## Authoritative References

- [Android local network permission](https://developer.android.com/privacy-and-security/local-network-permission)
- [Android Wi-Fi permissions](https://developer.android.com/develop/connectivity/wifi/wifi-permissions)
- [Android wireless connectivity and NSD](https://developer.android.com/develop/connectivity/wifi)
- [NIST IoT device cybersecurity capabilities](https://pages.nist.gov/IoT-Device-Cybersecurity-Requirement-Catalogs/technical/)
- [NIST IoT software update baseline](https://pages.nist.gov/FederalProfile-8259A/technical/update/)
