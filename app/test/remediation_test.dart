import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/remediation/application/remediation_planner.dart';
import 'package:wifi_scan/features/remediation/domain/remediation_plan.dart';
import 'package:wifi_scan/features/security/domain/security_finding.dart';

void main() {
  test('creates manual guidance plans without automatic execution', () {
    const finding = SecurityFinding(
      id: 'finding-1',
      title: '소유자 확인이 필요한 장비',
      description: '확인되지 않은 장비입니다.',
      evidence: 'neighbor 관측',
      severity: FindingSeverity.warning,
      confidence: 0.8,
      recommendedActions: ['공유기 접속 목록 확인'],
      remediationMode: RemediationMode.guidanceOnly,
      deviceId: 'device-1',
    );

    final plans = const ManualRemediationPlanner().build([finding]);

    expect(plans, hasLength(1));
    expect(plans.single.mode, RemediationMode.guidanceOnly);
    expect(plans.single.actionType, RemediationActionType.reviewRouterBlock);
  });

  test('blocks connector execution without explicit approval', () {
    const plan = RemediationPlan(
      id: 'router:block',
      findingId: 'finding-1',
      title: '장비 차단',
      summary: '공유기에서 장비를 차단합니다.',
      steps: ['변경 미리보기'],
      actionType: RemediationActionType.reviewRouterBlock,
      mode: RemediationMode.approvedConnector,
      reversible: true,
    );
    const request = RemediationRequest(plan: plan, explicitlyApproved: false);

    expect(
      () => const RemediationExecutionGuard().validate(
        request: request,
        connectorAvailable: true,
      ),
      throwsA(isA<RemediationNotAllowedException>()),
    );
  });
}
