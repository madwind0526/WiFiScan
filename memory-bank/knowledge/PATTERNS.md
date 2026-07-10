# Patterns

## Observation Normalization

공유기, 서브넷 탐색, mDNS, SSDP, 수동 확인에서 얻은 값은 관측 소스별 원본을 바로 UI에 노출하지 않는다. 공통 observation 형식으로 정규화한 뒤 신뢰도와 근거를 유지하면서 하나의 장비 자산에 연결한다.

## Evidence-Based Findings

보안 발견사항은 심각도만 저장하지 않는다. 근거, 탐지 신뢰도, 영향, 권장 조치, 허용된 대응 방식을 함께 보관한다.

## Windows Neighbor Discovery

Windows PoC는 기본 게이트웨이가 있는 활성 사설 IPv4 인터페이스를 선택하고, 현재 주소가 속한 최대 `/24` 호스트에 속도 제한된 ICMP 요청을 보낸다. 이후 `Get-NetNeighbor` 결과를 관측 소스와 신뢰도를 포함한 `NetworkDevice`로 정규화한다.
