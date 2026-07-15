# Patterns

## Observation Normalization

공유기, 서브넷 탐색, mDNS, SSDP, 수동 확인에서 얻은 값은 관측 소스별 원본을 바로 UI에 노출하지 않는다. 공통 observation 형식으로 정규화한 뒤 신뢰도와 근거를 유지하면서 하나의 장비 자산에 연결한다.

## Evidence-Based Findings

보안 발견사항은 심각도만 저장하지 않는다. 근거, 탐지 신뢰도, 영향, 권장 조치, 허용된 대응 방식을 함께 보관한다.

## Windows Neighbor Discovery

Windows PoC는 기본 게이트웨이가 있는 활성 사설 IPv4 인터페이스를 선택하고, 현재 주소가 속한 최대 `/24` 호스트에 속도 제한된 ICMP 요청을 보낸다. 이후 `Get-NetNeighbor` 결과를 관측 소스와 신뢰도를 포함한 `NetworkDevice`로 정규화한다.

## Inventory Baseline and Correlation

첫 검색은 기준선으로 저장하고 신규 장비 경고를 만들지 않는다. 이후 검색은 MAC 주소를 우선 키로 상관시키고, MAC이 없는 관측만 IP 보조 키로 비교한다. 기존 장비의 `firstSeenAt`은 유지하고 현재 관측의 주소와 `lastSeenAt`을 반영한다.

## Evidence-Based Risk Analysis

위험 분석기는 확정적 취약점 문자열 대신 관측 사실을 발견사항으로 변환한다. 각 항목은 근거, 신뢰도, 권장 조치, 허용된 대응 모드를 함께 가진다.

## Minimal Icon-Driven Dashboard

상단 검색/설정 아이콘과 하단 홈·장비·경고 NavigationBar를 사용한다. 숫자 지표는 아이콘과 값 위주로 줄이고, Tooltip과 Semantics label로 의미와 접근성을 보완한다. 긴 설명과 대응 절차는 상세 탭과 스크롤 콘텐츠에 둔다.

## Portrait Icon Shell (MeshComm/SNS-Downloader 스타일)

Windows 창을 480×920 세로형으로 고정하고, 상단 58px 아이콘 바(타이틀 + 전체 스캔/프로필/설정 아이콘), 하단 66px 4탭 아이콘 바(홈·네트워크·장비·경고) 사이에 중앙 스크롤 콘텐츠를 배치한다. 중앙 도킹 FAB(radar)가 현재 네트워크 스캔을 담당하고, 하단 바 가운데 76px 공간을 비워 FAB와 겹치지 않게 한다. 다크 팔레트: scaffold `#0A0B10`, card `#14151F`, 보라 계열 accent seed `#8A7CFF`.

## Per-Network Scan Records

멀티 Wi-Fi 스캔 결과는 프로필 id → `_NetworkScanRecord(deviceIds, scannedAt, failed)` 맵으로 저장한다. SSID의 밴드(2.4G/5G)는 정규식 휴리스틱으로 판별하고, 밴드 접미사를 제거한 기본 이름으로 공유기 단위 그룹핑을 한다. 장비 탭은 이 레코드의 deviceIds로 네트워크별 필터링을 한다.

## Keyboard-Safe Translucent Dialog

입력 다이얼로그는 `Dialog` 안에 화면 높이와 `MediaQuery.viewInsets.bottom`을 반영한 `ConstrainedBox`를 두고, 본문은 `Flexible(SingleChildScrollView)`로 감싼다. `TextEditingController`는 다이얼로그 전용 `StatefulWidget`이 소유하고 해당 State의 `dispose`에서 정리해 route 닫힘 애니메이션보다 먼저 폐기되지 않게 한다. 작은 화면, 2배 글꼴, 키보드 표시 상태에서 입력·저장·취소를 모두 위젯 테스트한다.

## Split Profile Metadata, Credentials, and Backups

프로필 저장을 세 계층으로 나눈다. SSID와 표시 이름 같은 메타데이터는 로컬 JSON, Wi-Fi 암호는 `flutter_secure_storage`, 기기 간 이동용 파일은 사용자 암호 기반 PBKDF2 + AES-GCM 암호문으로 저장한다. 백업 코덱과 파일 선택 서비스를 UI에 주입 가능하게 분리하면 실제 파일 선택 플러그인 없이도 암호 확인, 취소, 저장, 불러오기 흐름을 위젯 테스트할 수 있다.

## Failure-Isolated Network Enrichment

ICMP/neighbor 결과만으로 부족한 장비 정보를 역방향 DNS, mDNS/DNS-SD, SSDP/UPnP, 제한된 TCP 연결 확인 제공자로 보강한다. 각 제공자는 동일한 IP 기반 증거 모델을 반환하고 병렬 실행하며, 개별 실패는 전체 탐색을 실패시키지 않는다. SSDP 설명 문서는 기존 탐색 대상 IP의 HTTP 주소만 허용하고 리디렉션을 따르지 않아 임의 외부 요청을 막으며, TCP 확인은 연결 여부만 수집하고 애플리케이션 payload를 전송하지 않는다.

## Suppression Tombstone for Auto-Discovered Profiles

외부 소스에서 자동 병합하는 항목을 사용자가 삭제할 수 있어야 하면 단순 목록 삭제만으로는 부족하다. 삭제된 외부 키를 로컬 suppression tombstone으로 저장하고 자동 병합에서 제외한다. 사용자가 같은 키를 직접 추가하거나 가져올 때만 tombstone을 해제한다.

## Deterministic Force-Directed Device Graph

네트워크 메시는 노드 ID 기반 초기 위치와 고정 반복 횟수의 반발력·스프링·클러스터 중력을 결합한다. 결정론적 배치를 사용하면 데이터가 바뀌지 않은 재빌드·호버·선택에서 노드가 흔들리지 않는다. 그래프는 `InteractiveViewer` 안의 하나의 캔버스로 배치해 간선·노드·라벨이 같이 줌과 이동을 따르게 한다. 유형별 색상, 공유기 크기, 세로 범례는 시각 코딩을 담당하고 호버 시 이웃 노드와 간선만 강조한다.

## Layered Public Device Identification

장비 식별은 역방향 DNS, DNS-SD 서비스 유형 열거와 SRV/TXT, SSDP/UPnP 설명, Windows NetBIOS 이름표, 제한된 서비스 관측을 실패 격리된 제공자로 병렬 결합한다. RFC 6763의 `_services._dns-sd._udp.local` 메타 질의를 먼저 수행하면 미리 아는 서비스 유형 밖의 광고도 후속 조회할 수 있다. 이름·모델·호스트·서비스 키워드 분류는 명확한 근거가 있을 때만 기존 `unknown` 유형을 보강하며, 응답이 없는 장비는 추측하지 않는다.

## Multi-Gateway Organic Graph Cloud

여러 네트워크를 하나의 Obsidian형 클라우드에 표시할 때는 그룹별 초기 중심과 전체 중심 중력을 함께 사용한다. 인접한 GW 사이에 화면에 그리지 않는 배치 전용 스프링을 넣으면 성단이 완전히 분리되지 않으면서 각 GW의 별 모양 구조를 유지할 수 있다. Painter에는 실제 관측 간선만 전달해 배치용 관계가 네트워크 연결로 오해되지 않게 한다. 동적 결과가 `InteractiveViewer`를 처음 만든 프레임과 겹치면 변환이 초기화될 수 있으므로 다음 프레임에도 전체 맞춤을 재적용한다.

## Dismissible Overlay Status Banner

그래프 위에 동적으로 나타나는 진행·완료·중지·오류 메시지는 하나의 공통 배너 컴포넌트로 처리한다. 일반 상태는 반투명 검정과 흰색 글씨, 오류는 반투명 오류색과 대비 글씨를 사용한다. `Stack` 중앙에 좌우 여백을 둔 본문을 배치하고 닫기 버튼은 오른쪽에 독립적으로 정렬하면, 작은 화면과 큰 글꼴에서 여러 줄 문구가 중앙을 유지하면서 버튼과 겹치지 않는다. 닫기는 메시지와 오류 상태를 함께 초기화한다.

## Reproducible Multi-Platform App Icon

Flutter UI에서 사용하는 Material 아이콘을 앱 아이콘으로 재사용할 때는 Flutter SDK의 `materialicons-regular.otf`와 `IconData` 코드포인트를 사용해 고해상도 원본을 생성한다. 하나의 생성 도구가 Windows 다중 해상도 ICO와 Android mdpi~xxxhdpi PNG를 모두 출력하게 하면 플랫폼별 아이콘 모양과 색상이 어긋나지 않는다. 고해상도 원본과 생성 도구를 함께 저장해 바이너리 자산을 재현 가능하게 유지한다.
