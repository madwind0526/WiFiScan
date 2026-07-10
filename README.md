# WifiScan

기존 프로젝트와 분리된 새로운 프로젝트입니다. 현재는 공통 프로젝트 구조와 실행 가능한 Flutter 기본 앱만 준비되어 있습니다.

## 현재 상태

- 루트 프로젝트 문서 구성
- Flutter Android/Windows 기본 타깃 생성
- memory-bank 초기화
- 정적 분석 및 위젯 테스트 구성
- 제품 기능과 기술 선택은 아직 확정하지 않음

## 실행

```powershell
Set-Location C:\Claude\WifiScan\app
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

## 디렉터리

```text
app/          Flutter 기본 앱
docs/         요구사항과 설계 결정
memory-bank/  현재 상태와 프로젝트 지식
tools/        개발 및 검증 도구
```

요구사항 초안은 [docs/DESIGN.md](docs/DESIGN.md), 작업 규칙은 [AGENTS.md](AGENTS.md)를 참고하세요.
