# WifiScan

> **Working directory: `C:\Claude\WifiScan`**

## Project Status

WifiScan은 기존 프로젝트와 분리된 새 프로젝트다. 현재는 프로젝트 운영 구조와 실행 가능한 Flutter 기본 앱만 준비되어 있다.

- 제품 요구사항: 미정
- 상세 기능: 미정
- 데이터 모델과 저장 방식: 미정
- 외부 패키지와 플랫폼 연동 방식: 미정
- 기존 프로젝트에서는 구조와 작업 절차만 참고한다.

## Initial Scaffold

- Flutter application: `app/`
- Generated targets: Android, Windows
- Tests: Flutter widget tests
- Project context: `docs/`, `memory-bank/`

생성된 타깃은 초기 골격이며 실제 지원 플랫폼은 요구사항 확정 후 결정한다.

## Commands

```powershell
Set-Location C:\Claude\WifiScan\app
flutter pub get
flutter analyze
flutter test
flutter run -d windows
flutter run
```

## Source Layout

```text
app/lib/
├─ app/                  App shell
├─ features/             Product features added from WifiScan requirements
└─ main.dart             Application entry point
```

## Next Step

`docs/DESIGN.md`의 질문에 답하며 WifiScan 자체의 목적, 사용자 흐름, 지원 플랫폼, 데이터 처리 방식을 확정한다.

## Memory Bank

작업 시작 시 `memory-bank/active-context.md`, `memory-bank/STATE.md`, `memory-bank/CACHE.md`를 확인한다.
