# WifiScan Design

## Status

이 문서는 WifiScan 자체의 요구사항을 새로 정의하기 위한 초기 템플릿이다. 기존 프로젝트의 제품 내용이나 기술 결정을 복사하지 않는다.

## Product Definition

- 해결하려는 문제: 미정
- 주요 사용자: 미정
- 핵심 사용자 흐름: 미정
- 지원 플랫폼: 미정
- 오프라인 동작 범위: 미정

## Functional Requirements

요구사항 협의 후 작성한다.

1. 미정

## Data and Privacy

- 수집할 데이터: 미정
- 로컬 저장 여부: 미정
- 외부 전송 여부: 미정
- 보존 및 삭제 정책: 미정

## Technical Decisions

현재 확정된 내용은 Flutter 기본 앱 골격뿐이다. 상태 관리, 저장소, 플랫폼 API, 외부 패키지는 요구사항을 바탕으로 결정한다.

## Verification Gates

- `flutter analyze` 통과
- `flutter test` 통과
- 선택한 타깃에서 기본 앱 실행
- 기능 구현 후 프로젝트 규칙에 맞는 회귀 검증 추가

## Roadmap

| Wave | 내용 | 상태 |
|---|---|---|
| 0 | 독립 프로젝트 구조, 문서, Flutter 기본 앱 | 완료 |
| 1 | WifiScan 요구사항과 지원 플랫폼 확정 | 예정 |
| 2 | 첫 번째 기능 구현 | 예정 |
