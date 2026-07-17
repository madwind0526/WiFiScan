# State

## Current Wave

- **Wave:** 21
- **Status:** Complete
- **Cache Status:** CLEAN
- **Last Checkpoint:** 2026-07-17 Wave 21 MAC 기준 사용자 지정 장비 이름·소유 상태 영구 저장(DeviceLabelRepository)과 상세 편집 UI 추가, analyze/56 tests 통과. GitHub origin 연결 및 push 완료

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
| 13 | 삭제한 Windows 자동 탐색 프로필의 재등록 방지 | Done |
| 14 | 장비 유형별 입체 구와 Obsidian 스타일 힘 기반 메시 그래프 | Done |
| 15 | 단색 다중 GW 메시, 닫을 수 있는 오류 배너, DNS-SD/NetBIOS 식별 보강 | Done |
| 16 | 현재 표시 장비·경고와 홈 요약 숫자의 데이터 범위 일치 | Done |
| 17 | 모든 동적 상태 배너의 반투명 배경·고대비 글씨·닫기 동작 통일 | Done |
| 18 | 중앙 스캔 앱 아이콘과 중앙 정렬 명사형 상태 배너 | Done |
| 19 | Wi-Fi 전환 직후 DHCP 경쟁으로 인한 0장비 스캔 실패 수정 | Done |
| 20 | 오프라인 OUI 제조사 사전으로 조용한 장비 MAC 제조사 식별 | Done |
| 21 | MAC 기준 사용자 지정 장비 이름·소유 상태 영구 저장과 편집 UI | Done |

## Session Notes

- 모든 장비 탐지를 목표로 하지만 단일 스캔의 100% 완전성을 주장하지 않는다.
- 스캔 결과는 근거와 신뢰도를 포함한다.
- 패치/설정 변경은 공식 관리 경로와 사용자 승인이 있는 경우로 제한한다.
- Android 17 target SDK 37 이상에서는 로컬 LAN 접근 권한 대응이 필요하다.
