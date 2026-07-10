enum FindingSeverity { information, warning, critical }

enum RemediationMode { guidanceOnly, approvedConnector }

class SecurityFinding {
  const SecurityFinding({
    required this.id,
    required this.title,
    required this.description,
    required this.evidence,
    required this.severity,
    required this.confidence,
    required this.recommendedActions,
    required this.remediationMode,
    this.deviceId,
  });

  final String id;
  final String title;
  final String description;
  final String evidence;
  final FindingSeverity severity;
  final double confidence;
  final List<String> recommendedActions;
  final RemediationMode remediationMode;
  final String? deviceId;
}
