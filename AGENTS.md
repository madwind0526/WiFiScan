# WifiScan Agent Instructions

이 파일은 `C:\Claude\WifiScan`에서 작업하는 모든 에이전트가 따라야 하는 프로젝트 규칙이다.

## Project Independence

- WifiScan은 기존 프로젝트에서 분리된 완전히 새로운 프로젝트다.
- 다른 프로젝트에서는 폴더 구조와 검증된 작업 절차만 참고한다.
- 다른 프로젝트의 기능, 비즈니스 규칙, 패키지, 데이터 모델을 명시적 근거 없이 가져오지 않는다.
- 새로운 기술 또는 제품 결정을 내리기 전에 WifiScan의 요구사항 문서에 근거를 남긴다.

## Mandatory Rules

- 코드 주석은 영어만 사용한다.
- 사용자에게 보이는 UI 텍스트는 한국어로 작성한다.
- 비밀값, 계정 정보, 기기 식별자 등 민감한 정보는 로그나 Git에 평문으로 남기지 않는다.
- 사용자가 지정한 작업 경로를 쓰기 전에 현재 경로를 확인한다.

## Network Security Safety Rules

- 사용자가 소유하거나 명시적으로 관리 권한을 가진 로컬 네트워크만 점검한다.
- 기본 탐색은 비침투 방식으로 제한한다. 비밀번호 대입, 취약점 악용, 서비스 중단, 패킷 변조를 구현하지 않는다.
- 탐지된 장비에 설정 변경이나 업데이트를 자동 적용하지 않는다.
- 자동 대응은 공식 관리 API, 사용자 인증, 변경 미리보기, 명시적 확인, 실패 복구 경로가 모두 있을 때만 허용한다.
- 버전과 공식 근거가 확인되지 않은 장비에는 확정적인 취약점 판정을 내리지 않는다. 위험도와 탐지 신뢰도를 함께 표시한다.
- MAC 주소, IP 주소, SSID, 장비 이름은 민감한 로컬 데이터로 취급하고 기본적으로 외부 전송하지 않는다.
- 스캔 요청은 속도를 제한하고 사용자가 언제든 중단할 수 있어야 한다.
- 장비가 탐지되지 않았다는 사실을 안전하다는 의미로 표현하지 않는다.

## UI Rules

- 텍스트 입력이 있는 dialog, modal, bottom sheet는 키보드와 큰 시스템 글꼴에서도 overflow가 없어야 한다.
- Flutter 입력 폼은 `Dialog` + `ConstrainedBox` + `Flexible(SingleChildScrollView)` 구조를 우선한다.
- UI 수정 전후에 기존 클릭, 열림, 입력, 저장, 취소 흐름을 회귀 검증한다.
- 작은 화면, 큰 글꼴, 키보드 표시 상태를 기본 검증 항목에 포함한다.

## Project Structure

```text
WifiScan/
├─ app/                  Flutter application scaffold
├─ docs/                 Requirements and technical decisions
├─ memory-bank/          Current context and accumulated knowledge
├─ tools/                Development and verification helpers
├─ AGENTS.md             Agent rules
├─ CLAUDE.md             Working context and commands
└─ README.md             Project introduction
```

## Memory-Bank Protocol

세션 시작 시 다음 파일을 순서대로 확인한다.

1. `memory-bank/active-context.md`
2. `memory-bank/STATE.md`
3. `memory-bank/CACHE.md`

작업 중 발견사항은 `CACHE.md`에 기록한다. Wave가 끝나면 다음 위치로 이동한다.

- 코드 패턴: `memory-bank/knowledge/PATTERNS.md`
- 규칙과 결정: `memory-bank/knowledge/RULES.md`
- 버그와 해결법: `memory-bank/knowledge/trouble-shooting.md`

Wave 완료 시 `CACHE.md`의 Active Findings를 비우고 `STATE.md`의 Wave와 Cache Status를 갱신한다.
