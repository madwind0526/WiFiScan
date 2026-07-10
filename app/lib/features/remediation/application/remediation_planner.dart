import 'package:wifi_scan/features/remediation/domain/remediation_plan.dart';
import 'package:wifi_scan/features/security/domain/security_finding.dart';

class ManualRemediationPlanner {
  const ManualRemediationPlanner();

  List<RemediationPlan> build(Iterable<SecurityFinding> findings) {
    return findings
        .map(
          (finding) => RemediationPlan(
            id: 'manual:${finding.id}',
            findingId: finding.id,
            deviceId: finding.deviceId,
            title: _titleFor(finding),
            summary: '공식 공유기 커넥터가 없어 사용자가 직접 확인해야 합니다.',
            steps: finding.recommendedActions,
            actionType: finding.deviceId == null
                ? RemediationActionType.moveToIsolatedNetwork
                : RemediationActionType.reviewRouterBlock,
            mode: RemediationMode.guidanceOnly,
            reversible: true,
          ),
        )
        .toList(growable: false);
  }

  static String _titleFor(SecurityFinding finding) {
    return '${finding.title} 대응 안내';
  }
}
