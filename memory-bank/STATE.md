# State

## Current Wave

- **Wave:** 12
- **Status:** Complete
- **Cache Status:** CLEAN
- **Last Checkpoint:** 2026-07-15 Wave 12 Wi-Fi 출발 주소 고정, 버전 1.1.1+3, analyze/31 tests/Windows 빌드 검증 완료

## Wave History

| Wave | 작업 내용 | 상태 |
|---|---|---|
| 0 | 루트 문서, memory-bank, Flutter 기본 앱 | Done |
| 1 | 제품 범위, 안전 경계, 도메인 모델, 대시보드 | Done |
| 2 | 현재 네트워크 정보와 비침투 장비 탐색 PoC | Done |
| 3 | 장비 식별, 스냅샷, 신규 장비 감지 | Done |
| 4 | 근거 기반 위험 분석과 경고 | Done |
| 5 | 공유기 커넥터와 승인 기반 방어 조치 | Done |
| 6 | Android 권한/성능/회귀 검증 흐름 | Done |
| 7 | 세로형 아이콘 셸 UI 리디자인과 네트워크 탭 | Done |
| 8 | Android APK 빌드 복구와 프로필 입력 다이얼로그 회귀 수정 | Done |
| 9 | OS 보안 저장소와 암호 기반 프로필 가져오기/내보내기 | Done |
| 10 | 비침투 네트워크 정보 보강과 서비스 기반 보안 안내 | Done |
| 11 | Windows Wi-Fi 전용 탐색과 게이트웨이 오선택 수정 | Done |
| 12 | 동일 서브넷 탐색 패킷의 Ethernet 우회 수정 | Done |

## Session Notes

- 모든 장비 탐지를 목표로 하지만 단일 스캔의 100% 완전성을 주장하지 않는다.
- 스캔 결과는 근거와 신뢰도를 포함한다.
- 패치/설정 변경은 공식 관리 경로와 사용자 승인이 있는 경우로 제한한다.
- Android 17 target SDK 37 이상에서는 로컬 LAN 접근 권한 대응이 필요하다.
