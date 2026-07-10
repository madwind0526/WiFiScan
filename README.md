# WifiScan

현재 로컬 Wi-Fi/LAN에 연결된 장비를 확인하고 잠재적인 보안 문제를 알려주는 Flutter 기반 네트워크 보안 프로젝트입니다.

## 목표

- 휴대폰, PC, TV, 카메라, 스피커, 일반 가전, IoT 등 연결 장비 목록화
- 처음 보는 장비와 장기간 보이지 않던 장비 구분
- 노출 서비스와 잘못된 보안 설정을 비침투 방식으로 점검
- 위험 근거와 신뢰도를 포함한 경고 제공
- 제조사 공식 업데이트 또는 공유기 관리 API가 지원될 때만 사용자 승인 후 대응

## 안전 원칙

WifiScan은 사용자가 관리 권한을 가진 네트워크만 점검합니다. 비밀번호 대입, 취약점 악용, 서비스 중단, 무단 패치는 수행하지 않습니다. 스캔 데이터는 기본적으로 기기 내부에만 보관합니다.

단말 한 대에서 수행한 탐색은 잠든 장비, 방화벽 적용 장비, AP 격리 또는 다른 VLAN의 장비를 놓칠 수 있습니다. 공유기 정보와 여러 탐색 방식을 결합하고 탐지 범위와 한계를 함께 표시하는 방향으로 개발합니다.

## 현재 상태

- Flutter Android/Windows 기본 타깃
- 네트워크 보안 대시보드 골격
- 장비 인벤토리와 보안 발견사항 도메인 모델
- Windows에서 활성 IPv4 네트워크와 neighbor 장비 탐색 PoC 연결
- Android 네트워크 탐색은 다음 단계에서 구현 예정

## 실행

```powershell
Set-Location C:\Claude\WifiScan\app
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

자세한 범위와 단계는 [docs/DESIGN.md](docs/DESIGN.md), 작업 규칙은 [AGENTS.md](AGENTS.md)를 참고하세요.
