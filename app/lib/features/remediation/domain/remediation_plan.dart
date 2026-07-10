import 'package:wifi_scan/features/security/domain/security_finding.dart';

enum RemediationActionType {
  confirmOwnership,
  reviewRouterBlock,
  moveToIsolatedNetwork,
  updateFirmware,
  changeCredentials,
  disableService,
}

class RemediationPlan {
  const RemediationPlan({
    required this.id,
    required this.findingId,
    required this.title,
    required this.summary,
    required this.steps,
    required this.actionType,
    required this.mode,
    required this.reversible,
    this.deviceId,
  });

  final String id;
  final String findingId;
  final String title;
  final String summary;
  final List<String> steps;
  final RemediationActionType actionType;
  final RemediationMode mode;
  final bool reversible;
  final String? deviceId;
}

class RemediationRequest {
  const RemediationRequest({
    required this.plan,
    required this.explicitlyApproved,
    this.confirmationText,
  });

  final RemediationPlan plan;
  final bool explicitlyApproved;
  final String? confirmationText;
}

class RemediationExecutionGuard {
  const RemediationExecutionGuard();

  void validate({
    required RemediationRequest request,
    required bool connectorAvailable,
  }) {
    if (request.plan.mode != RemediationMode.approvedConnector) {
      throw const RemediationNotAllowedException(
        '공식 관리 커넥터가 없는 안내 조치는 자동 실행할 수 없습니다.',
      );
    }
    if (!connectorAvailable) {
      throw const RemediationNotAllowedException('사용 가능한 공유기 관리 커넥터가 없습니다.');
    }
    if (!request.explicitlyApproved) {
      throw const RemediationNotAllowedException('사용자의 명시적 확인이 필요합니다.');
    }
    if (request.confirmationText != '변경을 승인합니다') {
      throw const RemediationNotAllowedException('확인 문구가 일치하지 않습니다.');
    }
  }
}

class RemediationNotAllowedException implements Exception {
  const RemediationNotAllowedException(this.message);

  final String message;

  @override
  String toString() => message;
}
