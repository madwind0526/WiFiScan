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
