# WifiScan Design

## Product Definition

WifiScan은 사용자가 소유하거나 관리 권한을 가진 로컬 Wi-Fi/LAN에서 다음 질문에 답한다.

1. 지금 또는 최근에 어떤 장비가 연결되었는가?
2. 새롭거나 신원을 확인하지 못한 장비가 있는가?
3. 각 장비에서 관측 가능한 잠재적 보안 위험은 무엇인가?
4. 사용자가 안전하게 취할 수 있는 방어 조치는 무엇인가?

주요 사용자는 가정 또는 소규모 네트워크 관리자다. 휴대폰, 컴퓨터, TV, 셋톱박스, 카메라, 스피커, 프린터, 공유기, 생활가전, 기타 IoT 장비를 대상으로 한다.

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
| 3 | 장비 식별, 스냅샷, 신규 장비 감지 | 예정 |
| 4 | 근거 기반 위험 분석과 경고 | 예정 |
| 5 | 공유기 커넥터와 승인 기반 방어 조치 | 예정 |
| 6 | Android 실기기 권한/성능/회귀 검증 | 예정 |

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
