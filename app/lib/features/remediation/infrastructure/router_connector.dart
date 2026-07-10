import 'package:wifi_scan/features/remediation/domain/remediation_plan.dart';

abstract interface class RouterConnector {
  String get connectorId;

  String get displayName;

  Future<bool> isAvailable();

  Future<RouterActionPreview> preview(RemediationPlan plan);

  Future<RouterActionResult> execute(RemediationRequest request);
}

class RouterActionPreview {
  const RouterActionPreview({
    required this.title,
    required this.impact,
    required this.rollback,
  });

  final String title;
  final String impact;
  final String rollback;
}

class RouterActionResult {
  const RouterActionResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class UnsupportedRouterConnector implements RouterConnector {
  const UnsupportedRouterConnector();

  @override
  String get connectorId => 'unsupported';

  @override
  String get displayName => '지원되지 않는 공유기';

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<RouterActionPreview> preview(RemediationPlan plan) {
    throw const RemediationNotAllowedException('공식 공유기 관리 커넥터가 연결되지 않았습니다.');
  }

  @override
  Future<RouterActionResult> execute(RemediationRequest request) {
    throw const RemediationNotAllowedException('공식 공유기 관리 커넥터가 연결되지 않았습니다.');
  }
}
