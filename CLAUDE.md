# WifiScan

> **Working directory: `C:\Claude\WifiScan`**

## Project Overview

WifiScan은 사용자가 관리하는 현재 로컬 Wi-Fi/LAN에 연결된 휴대폰, PC, 일반 가전, IoT 장비를 식별하고 잠재적인 보안 위험을 알려주는 로컬 네트워크 보안 도구다.

- 네트워크 장비 인벤토리와 신규/미확인 장비 탐지
- 비침투 방식의 서비스 노출과 보안 설정 점검
- 위험 근거, 신뢰도, 권장 대응 표시
- 공식 관리 경로가 있는 장비에 한정한 승인 기반 대응
- 스캔 데이터는 기본적으로 로컬에서만 처리

## Product Boundary

- 단말 스캔만으로 모든 장비를 100% 보장할 수 없다.
- 공유기 DHCP/접속 장비 정보, 로컬 호스트 탐색, mDNS/SSDP 등 여러 관측 소스를 합쳐 탐지 범위를 높인다.
- 잠든 장비, 방화벽, AP 격리, 별도 VLAN/게스트망은 누락될 수 있으며 UI에 이 한계를 표시한다.
- 취약점 악용, 비밀번호 대입, 무단 패치, 강제 설정 변경은 범위 밖이다.

## Tech Stack

- UI: Flutter
- Initial targets: Android, Windows
- Android integration: Kotlin platform code when required
- State/storage/scanner packages: 구현 Wave에서 검증 후 선택
- Data: 로컬 우선, 외부 전송 기본 금지

## Commands

```powershell
Set-Location C:\Claude\WifiScan\app
flutter pub get
flutter analyze
flutter test
flutter run -d windows
flutter run
```

## Architecture

```text
Discovery sources
  -> normalized device observations
  -> identity correlation and device inventory
  -> non-invasive security checks
  -> findings with evidence and confidence
  -> warning and guided remediation
  -> approved connector action when safely supported
```

```text
app/lib/features/
├─ dashboard/            Network status overview
├─ inventory/            Devices and observations
├─ discovery/            Router, subnet, and service discovery adapters
├─ security/             Findings, evidence, and risk policy
└─ remediation/          Guidance and approved management connectors
```

## Current Wave

Wave 3~6의 장비 이력, 근거 기반 위험 경고, 대응 경계, Android 권한/탐색 경로를 완료했다.

- 활성 사설 IPv4 인터페이스와 기본 게이트웨이를 선택한다.
- 현재 주소가 속한 최대 `/24` 범위만 속도 제한된 ICMP 탐색을 수행한다.
- Windows `Get-NetNeighbor` 결과를 로컬 장비 모델로 정규화한다.
- MAC 주소를 우선 식별 키로 사용하고, 없으면 IP 기반 낮은 신뢰도 키를 사용한다.
- 첫 검색은 기준선으로 저장하고 이후 검색부터 신규·사라짐·변경 장비를 계산한다.
- 로컬 애플리케이션 지원 디렉터리에 최근 스냅샷을 저장한다.
- 미확인 장비와 제한된 검색 범위를 근거·신뢰도와 함께 경고한다.
- 공식 공유기 커넥터가 없으면 수동 대응 안내만 제공한다.
- Android는 권한 안내 후 Kotlin 플랫폼 채널을 통해 제한된 로컬 호스트 탐색을 수행한다.
- Android와 비-Windows 플랫폼은 명시적인 미지원 상태를 반환한다.

## Memory Bank

작업 시작 시 `memory-bank/active-context.md`, `memory-bank/STATE.md`, `memory-bank/CACHE.md`를 확인한다.
