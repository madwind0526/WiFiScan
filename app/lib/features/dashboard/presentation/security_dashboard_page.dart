import 'package:flutter/material.dart';
import 'package:wifi_scan/features/dashboard/domain/network_overview.dart';
import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/domain/discovery_result.dart';
import 'package:wifi_scan/features/discovery/infrastructure/platform_network_discovery_service.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';
import 'package:wifi_scan/features/security/domain/security_finding.dart';
import 'package:wifi_scan/features/discovery/domain/network_context.dart';

class SecurityDashboardPage extends StatefulWidget {
  const SecurityDashboardPage({super.key, this.discoveryService});

  final NetworkDiscoveryService? discoveryService;

  @override
  State<SecurityDashboardPage> createState() => _SecurityDashboardPageState();
}

class _SecurityDashboardPageState extends State<SecurityDashboardPage> {
  late final NetworkDiscoveryService _discoveryService;
  NetworkOverview _overview = const NetworkOverview.empty();
  DiscoveryResult? _lastResult;
  DiscoveryProgress? _progress;
  DiscoveryCancellationToken? _cancellationToken;
  String? _message;
  bool _messageIsError = false;
  bool _isScanning = false;
  bool _hasCompletedScan = false;

  @override
  void initState() {
    super.initState();
    _discoveryService =
        widget.discoveryService ?? createNetworkDiscoveryService();
  }

  Future<void> _startScan() async {
    if (_isScanning) return;

    final token = DiscoveryCancellationToken();
    setState(() {
      _isScanning = true;
      _cancellationToken = token;
      _progress = null;
      _message = null;
      _messageIsError = false;
    });

    try {
      final result = await _discoveryService.discover(
        cancellationToken: token,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _overview = NetworkOverview(
          devices: result.devices,
          findings: const [],
          lastScannedAt: DateTime.now(),
        );
        _lastResult = result;
        _hasCompletedScan = true;
        _message = '검색이 완료되었습니다.';
        _messageIsError = false;
      });
    } on DiscoveryCancelledException {
      if (!mounted) return;
      setState(() {
        _message = '검색을 중지했습니다.';
        _messageIsError = false;
      });
    } on DiscoveryUnavailableException catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.message;
        _messageIsError = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = '네트워크 정보를 읽지 못했습니다. 잠시 후 다시 시도하세요.';
        _messageIsError = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _cancellationToken = null;
        });
      }
    }
  }

  void _cancelScan() {
    _cancellationToken?.cancel();
    setState(() {
      _message = '검색 중지를 요청했습니다.';
      _messageIsError = false;
    });
  }

  @override
  void dispose() {
    _cancellationToken?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('와이파이 보안 점검')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _StatusHeader(
                  lastScannedAt: _overview.lastScannedAt,
                  networkContext: _lastResult?.context,
                ),
                const SizedBox(height: 16),
                _MetricGrid(overview: _overview),
                const SizedBox(height: 24),
                _ScanControls(
                  isScanning: _isScanning,
                  progress: _progress,
                  onScan: _startScan,
                  onCancel: _cancelScan,
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  _MessagePanel(message: _message!, isError: _messageIsError),
                ],
                const SizedBox(height: 28),
                const _SectionTitle(
                  title: '연결 장비',
                  description: '휴대폰, 컴퓨터, 가전, IoT 장비를 한곳에서 확인합니다.',
                ),
                const SizedBox(height: 12),
                if (_overview.devices.isEmpty)
                  _EmptyPanel(
                    icon: Icons.devices_other,
                    title: '확인된 장비가 없습니다.',
                    description: _hasCompletedScan
                        ? '이번 검색에서 관측 가능한 장비가 없었습니다.'
                        : '첫 검색이 완료되면 장비와 마지막 확인 시각이 표시됩니다.',
                  )
                else
                  _DeviceList(devices: _overview.devices),
                const SizedBox(height: 28),
                const _SectionTitle(
                  title: '보안 경고',
                  description: '발견 근거와 신뢰도를 확인한 뒤 안전한 대응을 선택합니다.',
                ),
                const SizedBox(height: 12),
                _overview.findings.isEmpty
                    ? _EmptyPanel(
                        icon: Icons.verified_user_outlined,
                        title: _hasCompletedScan
                            ? '보안 분석은 다음 단계에서 연결됩니다.'
                            : '분석된 경고가 없습니다.',
                        description: _hasCompletedScan
                            ? '장비 검색은 완료되었지만 위험 규칙은 아직 적용하지 않았습니다.'
                            : '아직 네트워크를 검색하지 않았으므로 안전 판정 전입니다.',
                      )
                    : _FindingList(findings: _overview.findings),
                if (_lastResult != null) ...[
                  const SizedBox(height: 28),
                  _LimitationsPanel(limitations: _lastResult!.limitations),
                ],
                const SizedBox(height: 28),
                const _SafetyNotice(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.lastScannedAt, this.networkContext});

  final DateTime? lastScannedAt;
  final NetworkContext? networkContext;

  @override
  Widget build(BuildContext context) {
    final hasScan = lastScannedAt != null;
    final contextInfo = networkContext;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.shield_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasScan ? '네트워크 검색을 완료했습니다.' : '현재 네트워크를 아직 점검하지 않았습니다.',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hasScan
                        ? '마지막 검색: ${_formatTimestamp(lastScannedAt!)}'
                        : '탐지되지 않은 장비가 있을 수 있으므로 검색 결과와 탐지 범위를 함께 확인하세요.',
                  ),
                  if (contextInfo != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '검색 범위: ${contextInfo.scannedSubnet} · 인터페이스 ${contextInfo.interfaceName}',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanControls extends StatelessWidget {
  const _ScanControls({
    required this.isScanning,
    required this.progress,
    required this.onScan,
    required this.onCancel,
  });

  final bool isScanning;
  final DiscoveryProgress? progress;
  final VoidCallback onScan;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final progressValue = progress?.fraction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: isScanning ? onCancel : onScan,
          icon: Icon(isScanning ? Icons.stop_circle_outlined : Icons.radar),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(isScanning ? '검색 중지 요청' : '현재 네트워크 검색 시작'),
          ),
        ),
        if (isScanning) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: progressValue),
          const SizedBox(height: 8),
          Text(_progressLabel(progress)),
        ],
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.overview});

  final NetworkOverview overview;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth < 520
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              width: itemWidth,
              label: '탐지된 장비',
              value: overview.devices.length.toString(),
              icon: Icons.devices,
            ),
            _MetricCard(
              width: itemWidth,
              label: '미확인 장비',
              value: overview.unconfirmedDeviceCount.toString(),
              icon: Icons.device_unknown,
            ),
            _MetricCard(
              width: itemWidth,
              label: '주의 경고',
              value: overview.warningCount.toString(),
              icon: Icons.warning_amber,
            ),
            _MetricCard(
              width: itemWidth,
              label: '긴급 경고',
              value: overview.criticalCount.toString(),
              icon: Icons.gpp_bad_outlined,
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
  });

  final double width;
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(child: Text(label)),
              const SizedBox(width: 12),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(description),
      ],
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.devices});

  final List<NetworkDevice> devices;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < devices.length; index++) ...[
            ListTile(
              leading: Icon(_deviceIcon(devices[index].category)),
              title: Text(devices[index].displayName),
              subtitle: Text(
                '${devices[index].ipAddresses.join(', ')} · ${_ownershipLabel(devices[index].ownershipStatus)}',
              ),
              trailing: Text(_categoryLabel(devices[index].category)),
            ),
            if (index < devices.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _FindingList extends StatelessWidget {
  const _FindingList({required this.findings});

  final List<SecurityFinding> findings;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: findings
          .map(
            (finding) => Card(
              child: ListTile(
                leading: const Icon(Icons.warning_amber),
                title: Text(finding.title),
                subtitle: Text(finding.description),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _LimitationsPanel extends StatelessWidget {
  const _LimitationsPanel({required this.limitations});

  final List<String> limitations;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('탐지 범위와 한계', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final limitation in limitations)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $limitation'),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(description),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: isError
          ? colorScheme.errorContainer
          : colorScheme.secondaryContainer,
      child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
    );
  }
}

class _SafetyNotice extends StatelessWidget {
  const _SafetyNotice();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.admin_panel_settings_outlined),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'WifiScan은 관리 권한이 있는 네트워크만 비침투 방식으로 점검합니다. '
                '패치나 설정 변경은 공식 관리 경로와 사용자의 명시적 승인이 있을 때만 진행합니다.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _progressLabel(DiscoveryProgress? progress) {
  if (progress == null) return '네트워크 정보를 준비하는 중입니다.';
  final stage = switch (progress.stage) {
    DiscoveryStage.preparing => '네트워크 정보를 확인하는 중입니다.',
    DiscoveryStage.probing => '장비 응답을 확인하는 중입니다.',
    DiscoveryStage.collecting => '장비 정보를 정리하는 중입니다.',
    DiscoveryStage.complete => '검색을 마무리하는 중입니다.',
  };
  if (progress.total == 0) return stage;
  return '$stage ${progress.completed}/${progress.total}';
}

String _formatTimestamp(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

String _categoryLabel(DeviceCategory category) => switch (category) {
  DeviceCategory.router => '공유기',
  DeviceCategory.phone => '휴대폰',
  DeviceCategory.computer => '컴퓨터',
  DeviceCategory.television => 'TV',
  DeviceCategory.appliance => '가전',
  DeviceCategory.camera => '카메라',
  DeviceCategory.speaker => '스피커',
  DeviceCategory.printer => '프린터',
  DeviceCategory.iot => 'IoT',
  DeviceCategory.unknown => '미확인',
};

String _ownershipLabel(OwnershipStatus status) => switch (status) {
  OwnershipStatus.confirmed => '확인됨',
  OwnershipStatus.unconfirmed => '소유자 미확인',
  OwnershipStatus.blocked => '차단됨',
};

IconData _deviceIcon(DeviceCategory category) => switch (category) {
  DeviceCategory.router => Icons.router,
  DeviceCategory.phone => Icons.phone_android,
  DeviceCategory.computer => Icons.computer,
  DeviceCategory.television => Icons.tv,
  DeviceCategory.appliance => Icons.home_repair_service,
  DeviceCategory.camera => Icons.videocam_outlined,
  DeviceCategory.speaker => Icons.speaker,
  DeviceCategory.printer => Icons.print,
  DeviceCategory.iot => Icons.memory,
  DeviceCategory.unknown => Icons.device_unknown,
};
