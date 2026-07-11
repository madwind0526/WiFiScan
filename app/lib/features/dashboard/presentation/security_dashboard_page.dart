import 'dart:io' as io;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wifi_scan/features/dashboard/domain/network_overview.dart';
import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/domain/discovery_result.dart';
import 'package:wifi_scan/features/discovery/infrastructure/platform_network_discovery_service.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';
import 'package:wifi_scan/features/inventory/application/inventory_repository.dart';
import 'package:wifi_scan/features/security/domain/security_finding.dart';
import 'package:wifi_scan/features/discovery/domain/network_context.dart';
import 'package:wifi_scan/features/security/application/security_risk_analyzer.dart';
import 'package:wifi_scan/features/remediation/application/remediation_planner.dart';
import 'package:wifi_scan/features/remediation/domain/remediation_plan.dart';

enum _DashboardSection { overview, devices, findings }

class SecurityDashboardPage extends StatefulWidget {
  const SecurityDashboardPage({
    super.key,
    this.discoveryService,
    this.inventoryRepository,
    this.securityRiskAnalyzer,
  });

  final NetworkDiscoveryService? discoveryService;
  final InventoryRepository? inventoryRepository;
  final SecurityRiskAnalyzer? securityRiskAnalyzer;

  @override
  State<SecurityDashboardPage> createState() => _SecurityDashboardPageState();
}

class _SecurityDashboardPageState extends State<SecurityDashboardPage> {
  late final NetworkDiscoveryService _discoveryService;
  late final InventoryRepository _inventoryRepository;
  late final SecurityRiskAnalyzer _securityRiskAnalyzer;
  NetworkOverview _overview = const NetworkOverview.empty();
  DiscoveryResult? _lastResult;
  DiscoveryProgress? _progress;
  DiscoveryCancellationToken? _cancellationToken;
  String? _message;
  bool _messageIsError = false;
  bool _isScanning = false;
  bool _hasCompletedScan = false;
  bool _securityAnalysisCompleted = false;
  Set<String> _newDeviceIds = const {};
  List<RemediationPlan> _remediationPlans = const [];
  _DashboardSection _section = _DashboardSection.overview;

  @override
  void initState() {
    super.initState();
    _discoveryService =
        widget.discoveryService ?? createNetworkDiscoveryService();
    _inventoryRepository =
        widget.inventoryRepository ??
        const InventoryRepository(store: FileInventorySnapshotStore());
    _securityRiskAnalyzer =
        widget.securityRiskAnalyzer ?? const SecurityRiskAnalyzer();
  }

  Future<void> _startScan() async {
    if (_isScanning) return;

    if (io.Platform.isAndroid) {
      final shouldContinue = await _showAndroidPermissionRationale();
      if (shouldContinue != true || !mounted) return;
    }

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
      InventoryUpdate? inventoryUpdate;
      var storageWarning = false;
      try {
        inventoryUpdate = await _inventoryRepository.record(result);
      } catch (_) {
        storageWarning = true;
      }
      final devices = inventoryUpdate?.snapshot.devices ?? result.devices;
      final newDevices = inventoryUpdate?.newDevices ?? const [];
      final findings = inventoryUpdate == null
          ? const <SecurityFinding>[]
          : _securityRiskAnalyzer
                .analyze(
                  snapshot: inventoryUpdate.snapshot,
                  inventoryUpdate: inventoryUpdate,
                )
                .findings;
      final remediationPlans = const ManualRemediationPlanner().build(findings);
      setState(() {
        _overview = NetworkOverview(
          devices: devices,
          findings: findings,
          lastScannedAt: DateTime.now(),
          newDeviceCount: newDevices.length,
        );
        _lastResult = result;
        _newDeviceIds = newDevices.map((device) => device.id).toSet();
        _remediationPlans = remediationPlans;
        _hasCompletedScan = true;
        _securityAnalysisCompleted = inventoryUpdate != null;
        _message = storageWarning
            ? '검색은 완료되었지만 장비 기록을 저장하지 못했습니다.'
            : inventoryUpdate?.isBaseline == true
            ? '검색이 완료되었습니다. 이번 결과를 기준선으로 저장했습니다.'
            : '검색이 완료되었습니다. 신규 장비 ${newDevices.length}개를 확인했습니다.';
        _messageIsError = storageWarning;
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

  Future<bool?> _showAndroidPermissionRationale() {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '로컬 네트워크 권한 안내',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  '현재 Wi-Fi에 연결된 장비를 확인하려면 로컬 네트워크 접근 권한이 필요합니다. '
                  '검색 결과는 기본적으로 기기 안에서만 처리합니다.',
                ),
                const SizedBox(height: 12),
                const Text('권한을 거부하면 장비 검색 없이 대시보드만 사용할 수 있습니다.'),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      child: const Text('취소'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      child: const Text('권한 요청 계속'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
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
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi,
              size: 19,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            const Text('와이파이 보안', style: TextStyle(fontSize: 15)),
          ],
        ),
        actions: [
          Tooltip(
            message: _isScanning ? '검색 중지 요청' : '현재 네트워크 검색 시작',
            child: IconButton(
              onPressed: _isScanning ? _cancelScan : _startScan,
              icon: Icon(
                _isScanning ? Icons.stop_circle_outlined : Icons.radar,
              ),
            ),
          ),
          Tooltip(
            message: '설정 및 안전 원칙',
            child: IconButton(
              onPressed: _showSettingsSheet,
              icon: const Icon(Icons.settings_outlined),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: _sectionChildren(context),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigation(context),
    );
  }

  List<Widget> _sectionChildren(BuildContext context) {
    return switch (_section) {
      _DashboardSection.overview => _overviewChildren(context),
      _DashboardSection.devices => _devicesChildren(context),
      _DashboardSection.findings => _findingsChildren(context),
    };
  }

  List<Widget> _overviewChildren(BuildContext context) {
    return [
      _StatusHeader(
        lastScannedAt: _overview.lastScannedAt,
        networkContext: _lastResult?.context,
      ),
      const SizedBox(height: 16),
      _MetricGrid(overview: _overview),
      const SizedBox(height: 20),
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
      const SizedBox(height: 20),
      _QuickSectionTile(
        icon: Icons.devices_other,
        title: '연결 장비',
        subtitle: '${_overview.devices.length}개 탐지됨',
        onTap: () => setState(() => _section = _DashboardSection.devices),
      ),
      const SizedBox(height: 10),
      _QuickSectionTile(
        icon: _overview.findings.isEmpty
            ? Icons.verified_user_outlined
            : Icons.warning_amber,
        title: '보안 경고',
        subtitle: _overview.findings.isEmpty
            ? '확인할 경고 없음'
            : '${_overview.findings.length}개 확인 필요',
        onTap: () => setState(() => _section = _DashboardSection.findings),
      ),
      const SizedBox(height: 20),
      const _SafetyNotice(),
    ];
  }

  List<Widget> _devicesChildren(BuildContext context) {
    return [
      const _SectionTitle(
        icon: Icons.devices_other,
        title: '연결 장비',
        description: '휴대폰, 컴퓨터, 가전, IoT 장비를 한곳에서 확인합니다.',
      ),
      const SizedBox(height: 12),
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
      const SizedBox(height: 16),
      if (_overview.devices.isEmpty)
        _EmptyPanel(
          icon: Icons.devices_other,
          title: '탐지된 장비가 없습니다.',
          description: _hasCompletedScan
              ? '이번 검색에서 관측 가능한 장비가 없었습니다.'
              : '검색 아이콘을 눌러 장비를 확인하세요.',
        )
      else ...[
        _NetworkTopologyCard(
          devices: _overview.devices,
          newDeviceIds: _newDeviceIds,
          onDeviceTap: _showDeviceDetails,
        ),
        const SizedBox(height: 16),
        _DeviceList(devices: _overview.devices, newDeviceIds: _newDeviceIds),
      ],
      if (_lastResult != null) ...[
        const SizedBox(height: 20),
        _LimitationsPanel(limitations: _lastResult!.limitations),
      ],
    ];
  }

  List<Widget> _findingsChildren(BuildContext context) {
    return [
      const _SectionTitle(
        icon: Icons.shield_outlined,
        title: '보안 경고',
        description: '발견 근거와 신뢰도를 확인한 뒤 안전한 대응을 선택합니다.',
      ),
      const SizedBox(height: 16),
      if (_overview.findings.isEmpty)
        _EmptyPanel(
          icon: Icons.verified_user_outlined,
          title: _securityAnalysisCompleted
              ? '현재 규칙에서 추가 확인 항목이 없습니다.'
              : _hasCompletedScan
              ? '보안 분석을 완료하지 못했습니다.'
              : '분석된 경고가 없습니다.',
          description: _securityAnalysisCompleted
              ? '현재 탐지 결과가 안전하다는 확정 판정은 아닙니다.'
              : _hasCompletedScan
              ? '장비 목록은 표시되지만 로컬 기록을 저장하지 못해 분석을 건너뛰었습니다.'
              : '먼저 네트워크 검색을 실행하세요.',
        )
      else
        _FindingList(findings: _overview.findings),
      if (_remediationPlans.isNotEmpty) ...[
        const SizedBox(height: 20),
        _RemediationPanel(
          plans: _remediationPlans,
          onOpen: _openRemediationPlan,
        ),
      ],
      const SizedBox(height: 20),
      const _SafetyNotice(),
    ];
  }

  Widget _buildBottomNavigation(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        height: 62,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
            size: 21,
          ),
        ),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
      child: NavigationBar(
        selectedIndex: _section.index,
        onDestinationSelected: (index) {
          setState(() => _section = _DashboardSection.values[index]);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '홈'),
          NavigationDestination(icon: Icon(Icons.devices_other), label: '장비'),
          NavigationDestination(icon: Icon(Icons.shield_outlined), label: '경고'),
        ],
      ),
    );
  }

  Future<void> _showSettingsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('설정 및 안전 원칙', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.lock_outline),
                title: Text('로컬 우선 처리'),
                subtitle: Text('스캔 결과는 기본적으로 기기 안에서만 처리합니다.'),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.policy_outlined),
                title: Text('비침투 점검'),
                subtitle: Text('비밀번호 대입, 취약점 악용, 무단 설정 변경을 수행하지 않습니다.'),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('닫기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openRemediationPlan(RemediationPlan plan) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                Text(plan.summary),
                const SizedBox(height: 16),
                for (final step in plan.steps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text('• $step'),
                  ),
                const SizedBox(height: 12),
                const Text(
                  '현재는 자동 변경을 수행하지 않습니다. 공유기 관리 화면에서 내용을 확인한 뒤 직접 적용하세요.',
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('닫기'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showDeviceDetails(NetworkDevice device) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_deviceIcon(device.category), size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        device.displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _DetailRow(label: '유형', value: _categoryLabel(device.category)),
                _DetailRow(
                  label: '소유 상태',
                  value: _ownershipLabel(device.ownershipStatus),
                ),
                _DetailRow(label: '주소', value: device.ipAddresses.join(', ')),
                _DetailRow(
                  label: '식별 신뢰도',
                  value: '${(device.identityConfidence * 100).round()}%',
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('닫기'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
    return Row(
      children: [
        Tooltip(
          message: isScanning ? '검색 중지 요청' : '현재 네트워크 검색 시작',
          child: IconButton.filled(
            onPressed: isScanning ? onCancel : onScan,
            icon: Icon(isScanning ? Icons.stop_circle_outlined : Icons.radar),
          ),
        ),
        if (isScanning) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: progressValue),
                const SizedBox(height: 6),
                Text(_progressLabel(progress)),
              ],
            ),
          ),
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
              label: '신규 장비',
              value: overview.newDeviceCount.toString(),
              icon: Icons.fiber_new,
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
    return Tooltip(
      message: label,
      child: Semantics(
        label: '$label $value',
        child: SizedBox(
          width: width,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: Theme.of(context).colorScheme.primary),
                  Text(value, style: Theme.of(context).textTheme.headlineSmall),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        Tooltip(
          message: description,
          child: const Icon(Icons.info_outline, size: 18),
        ),
      ],
    );
  }
}

class _QuickSectionTile extends StatelessWidget {
  const _QuickSectionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Tooltip(
          message: '$title 열기',
          child: IconButton(
            onPressed: onTap,
            icon: const Icon(Icons.chevron_right),
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 84, child: Text(label)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _NetworkTopologyCard extends StatelessWidget {
  const _NetworkTopologyCard({
    required this.devices,
    required this.newDeviceIds,
    required this.onDeviceTap,
  });

  final List<NetworkDevice> devices;
  final Set<String> newDeviceIds;
  final ValueChanged<NetworkDevice> onDeviceTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 430,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final center = Offset(width / 2, height / 2 + 12);
            final local = devices.cast<NetworkDevice?>().firstWhere(
              (device) =>
                  device!.sources.contains(DiscoverySource.localInterface),
              orElse: () => null,
            );
            final gateway = devices.cast<NetworkDevice?>().firstWhere(
              (device) => device!.category == DeviceCategory.router,
              orElse: () => null,
            );
            final others = devices
                .where((device) => device != local && device != gateway)
                .toList(growable: false);
            final positions = <String, Offset>{};
            if (local != null) positions[local.id] = center;
            if (gateway != null) {
              positions[gateway.id] = Offset(width / 2, 76);
            }
            final radius = (width < height ? width : height) * 0.34;
            for (var index = 0; index < others.length; index++) {
              final angle =
                  -math.pi / 2 +
                  (math.pi * 2 * index / math.max(others.length, 1));
              positions[others[index].id] = Offset(
                center.dx + math.cos(angle) * radius,
                center.dy + math.sin(angle) * radius,
              );
            }
            return Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    boundaryMargin: const EdgeInsets.all(80),
                    minScale: 0.8,
                    maxScale: 2.5,
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _NetworkTopologyPainter(
                                devices: devices,
                                positions: positions,
                                centerId: local?.id,
                                scheme: Theme.of(context).colorScheme,
                              ),
                            ),
                          ),
                          for (final device in devices)
                            if (positions[device.id] != null)
                              Positioned(
                                left: positions[device.id]!.dx - 34,
                                top: positions[device.id]!.dy - 34,
                                child: _TopologyNode(
                                  device: device,
                                  isNew: newDeviceIds.contains(device.id),
                                  onTap: () => onDeviceTap(device),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  top: 12,
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_tree_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      const Text('네트워크 맵'),
                    ],
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 8,
                  child: Tooltip(
                    message: '마우스 휠 또는 두 손가락으로 확대/축소',
                    child: IconButton(
                      onPressed: null,
                      icon: const Icon(Icons.zoom_out_map, size: 18),
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  bottom: 12,
                  child: Text(
                    '노드를 눌러 장비 상세 정보 확인',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TopologyNode extends StatelessWidget {
  const _TopologyNode({
    required this.device,
    required this.isNew,
    required this.onTap,
  });

  final NetworkDevice device;
  final bool isNew;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = device.sources.contains(DiscoverySource.localInterface)
        ? Theme.of(context).colorScheme.primary
        : device.category == DeviceCategory.router
        ? Colors.orange
        : Theme.of(context).colorScheme.secondary;
    return Tooltip(
      message: '${device.displayName}\n${device.ipAddresses.join(', ')}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(36),
        child: SizedBox(
          width: 68,
          height: 68,
          child: Stack(
            alignment: Alignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.16),
                  border: Border.all(color: color, width: 2),
                ),
                child: SizedBox.square(
                  dimension: 52,
                  child: Icon(_deviceIcon(device.category), color: color),
                ),
              ),
              if (isNew)
                Positioned(
                  right: 2,
                  top: 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox.square(dimension: 10),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NetworkTopologyPainter extends CustomPainter {
  const _NetworkTopologyPainter({
    required this.devices,
    required this.positions,
    required this.centerId,
    required this.scheme,
  });

  final List<NetworkDevice> devices;
  final Map<String, Offset> positions;
  final String? centerId;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final center = centerId == null ? null : positions[centerId];
    if (center == null) return;
    final line = Paint()
      ..color = scheme.outlineVariant.withValues(alpha: 0.7)
      ..strokeWidth = 1.5;
    for (final device in devices) {
      if (device.id == centerId) continue;
      final position = positions[device.id];
      if (position != null) canvas.drawLine(center, position, line);
    }
    final centerGlow = Paint()
      ..color = scheme.primary.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 48, centerGlow);
  }

  @override
  bool shouldRepaint(covariant _NetworkTopologyPainter oldDelegate) {
    return oldDelegate.devices != devices || oldDelegate.positions != positions;
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.devices, required this.newDeviceIds});

  final List<NetworkDevice> devices;
  final Set<String> newDeviceIds;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < devices.length; index++) ...[
            ListTile(
              leading: Icon(_deviceIcon(devices[index].category)),
              title: Row(
                children: [
                  Expanded(child: Text(devices[index].displayName)),
                  if (newDeviceIds.contains(devices[index].id))
                    const Chip(label: Text('신규')),
                ],
              ),
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
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            finding.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(_severityLabel(finding.severity)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(finding.description),
                    const SizedBox(height: 8),
                    Text('근거: ${finding.evidence}'),
                    const SizedBox(height: 8),
                    Text('탐지 신뢰도: ${(finding.confidence * 100).round()}%'),
                    const SizedBox(height: 8),
                    Text('권장 조치: ${finding.recommendedActions.join(' · ')}'),
                  ],
                ),
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

class _RemediationPanel extends StatelessWidget {
  const _RemediationPanel({required this.plans, required this.onOpen});

  final List<RemediationPlan> plans;
  final ValueChanged<RemediationPlan> onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('대응 안내', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text('현재 연결된 자동 변경 커넥터가 없어 수동 확인 절차만 제공합니다.'),
            const SizedBox(height: 12),
            for (final plan in plans)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed: () => onOpen(plan),
                    child: Text(plan.title),
                  ),
                ),
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

String _severityLabel(FindingSeverity severity) => switch (severity) {
  FindingSeverity.information => '정보',
  FindingSeverity.warning => '주의',
  FindingSeverity.critical => '긴급',
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
