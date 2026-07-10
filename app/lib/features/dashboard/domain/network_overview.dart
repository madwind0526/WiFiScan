import 'package:wifi_scan/features/inventory/domain/network_device.dart';
import 'package:wifi_scan/features/security/domain/security_finding.dart';

class NetworkOverview {
  const NetworkOverview({
    required this.devices,
    required this.findings,
    this.lastScannedAt,
  });

  const NetworkOverview.empty()
    : devices = const [],
      findings = const [],
      lastScannedAt = null;

  final List<NetworkDevice> devices;
  final List<SecurityFinding> findings;
  final DateTime? lastScannedAt;

  int get unconfirmedDeviceCount => devices
      .where((device) => device.ownershipStatus == OwnershipStatus.unconfirmed)
      .length;

  int get warningCount => findings
      .where((finding) => finding.severity == FindingSeverity.warning)
      .length;

  int get criticalCount => findings
      .where((finding) => finding.severity == FindingSeverity.critical)
      .length;
}
