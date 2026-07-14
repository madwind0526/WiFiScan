import 'package:wifi_scan/features/inventory/application/inventory_repository.dart';
import 'package:wifi_scan/features/inventory/domain/inventory_snapshot.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';
import 'package:wifi_scan/features/security/domain/security_finding.dart';

class SecurityAnalysis {
  const SecurityAnalysis({required this.findings});

  final List<SecurityFinding> findings;
}

class SecurityRiskAnalyzer {
  const SecurityRiskAnalyzer();

  SecurityAnalysis analyze({
    required InventorySnapshot snapshot,
    required InventoryUpdate inventoryUpdate,
  }) {
    final findings = <SecurityFinding>[];
    final newDeviceIds = inventoryUpdate.newDevices
        .map((device) => device.id)
        .toSet();

    for (final device in snapshot.devices) {
      if (device.ownershipStatus == OwnershipStatus.unconfirmed) {
        final isNew = newDeviceIds.contains(device.id);
        findings.add(
          SecurityFinding(
            id: 'unconfirmed:${device.id}',
            title: isNew ? '새로 탐지된 장비 확인 필요' : '소유자 확인이 필요한 장비',
            description: isNew
                ? '${device.displayName}가 이전 기준선에 없었습니다.'
                : '${device.displayName}의 소유자와 사용 목적이 확인되지 않았습니다.',
            evidence: _evidenceFor(device),
            severity: FindingSeverity.warning,
            confidence: device.identityConfidence.clamp(0.0, 1.0).toDouble(),
            recommendedActions: const [
              '장비의 소유자와 사용 목적을 확인하세요.',
              '모르는 장비라면 공유기 접속 목록에서 차단을 검토하세요.',
            ],
            remediationMode: RemediationMode.guidanceOnly,
            deviceId: device.id,
          ),
        );
      }
      findings.addAll(_serviceFindings(device));
      final model = device.modelName?.toUpperCase();
      if (device.category == DeviceCategory.router &&
          model != null &&
          model.contains('A6004NS-M')) {
        findings.add(
          SecurityFinding(
            id: 'firmware-check:${device.id}',
            title: 'ipTIME A6004NS-M 펌웨어 확인 필요',
            description:
                '${device.displayName}에서 A6004NS-M 모델 정보가 확인되었습니다. '
                '현재 펌웨어 버전은 원격 탐색만으로 확정할 수 없습니다.',
            evidence: '장비 공개 모델 정보: ${device.modelName}',
            severity: FindingSeverity.information,
            confidence: 0.9,
            recommendedActions: const [
              '공유기 관리 화면에서 현재 펌웨어 버전을 확인하세요.',
              'ipTIME 공식 지원 페이지의 최신 정식 펌웨어와 비교하세요.',
            ],
            remediationMode: RemediationMode.guidanceOnly,
            deviceId: device.id,
          ),
        );
      }
    }

    if (snapshot.context.coverageLimited) {
      findings.add(
        const SecurityFinding(
          id: 'coverage:limited',
          title: '검색 범위가 제한되었습니다',
          description: '현재 네트워크가 넓어 일부 주소만 탐색했습니다.',
          evidence: '능동 탐색은 최대 /24 범위로 제한됩니다.',
          severity: FindingSeverity.information,
          confidence: 1,
          recommendedActions: [
            '다른 VLAN이나 게스트망을 별도로 점검하세요.',
            '공유기의 전체 접속 목록과 결과를 비교하세요.',
          ],
          remediationMode: RemediationMode.guidanceOnly,
        ),
      );
    }

    return SecurityAnalysis(findings: findings);
  }

  static String _evidenceFor(NetworkDevice device) {
    final sources = device.sources.map((source) => source.name).join(', ');
    final addresses = device.ipAddresses.join(', ');
    return '관측 출처: $sources · 주소: $addresses · 식별 신뢰도: '
        '${(device.identityConfidence * 100).round()}%';
  }

  static List<SecurityFinding> _serviceFindings(NetworkDevice device) {
    final findings = <SecurityFinding>[];
    final ports = device.services.map((service) => service.port).toSet();
    final plaintextRemote = device.services
        .where((service) => service.port == 21 || service.port == 23)
        .toList();
    if (plaintextRemote.isNotEmpty) {
      findings.add(
        SecurityFinding(
          id: 'plaintext-remote:${device.id}',
          title: '평문 원격 접속 서비스 노출',
          description: '${device.displayName}에서 FTP 또는 Telnet 연결 포트가 열려 있습니다.',
          evidence: _serviceEvidence(plaintextRemote),
          severity: FindingSeverity.warning,
          confidence: 0.85,
          recommendedActions: const [
            '사용하지 않는 FTP/Telnet 서비스를 비활성화하세요.',
            '필요한 경우 SSH, SFTP 또는 HTTPS 기반 관리 방식으로 전환하세요.',
          ],
          remediationMode: RemediationMode.guidanceOnly,
          deviceId: device.id,
        ),
      );
    }
    if (ports.contains(80) && !ports.contains(443) && !ports.contains(8443)) {
      findings.add(
        SecurityFinding(
          id: 'http-without-https:${device.id}',
          title: 'HTTPS 없이 웹 서비스가 열려 있습니다',
          description:
              '${device.displayName}에서 HTTP 연결은 확인됐지만 HTTPS 연결은 확인되지 않았습니다.',
          evidence: _serviceEvidence(
            device.services.where((service) => service.port == 80),
          ),
          severity: FindingSeverity.warning,
          confidence: 0.65,
          recommendedActions: const [
            '해당 웹 화면이 관리 기능인지 확인하세요.',
            '지원한다면 HTTPS를 활성화하고 HTTP 관리를 비활성화하세요.',
          ],
          remediationMode: RemediationMode.guidanceOnly,
          deviceId: device.id,
        ),
      );
    }
    if (ports.contains(1883)) {
      findings.add(
        SecurityFinding(
          id: 'mqtt-review:${device.id}',
          title: 'MQTT 서비스 접근 통제 확인 필요',
          description:
              '${device.displayName}에서 MQTT 기본 포트가 열려 있습니다. '
              '인증 적용 여부는 추가 확인이 필요합니다.',
          evidence: _serviceEvidence(
            device.services.where((service) => service.port == 1883),
          ),
          severity: FindingSeverity.information,
          confidence: 0.75,
          recommendedActions: const [
            'MQTT 익명 접속이 비활성화되어 있는지 확인하세요.',
            'IoT 네트워크 외부에서 접근할 수 없도록 제한하세요.',
          ],
          remediationMode: RemediationMode.guidanceOnly,
          deviceId: device.id,
        ),
      );
    }
    return findings;
  }

  static String _serviceEvidence(Iterable<NetworkServiceObservation> services) {
    return services
        .map(
          (service) =>
              '${service.protocol.toUpperCase()} ${service.port}/${service.transport.name}',
        )
        .join(', ');
  }
}
