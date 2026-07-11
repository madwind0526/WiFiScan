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

enum _DashboardView { mesh, cards, list }

class SecurityDashboardPage extends StatefulWidget {
  const SecurityDashboardPage({
    super.key,
    this.discoveryService,
    this.inventoryRepository,
    this.securityRiskAnalyzer,
    this.onThemeModeChanged,
  });

  final NetworkDiscoveryService? discoveryService;
  final InventoryRepository? inventoryRepository;
  final SecurityRiskAnalyzer? securityRiskAnalyzer;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

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
  _DashboardView _view = _DashboardView.mesh;
  String _searchQuery = '';
  ThemeMode _themeMode = ThemeMode.system;

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
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                _TopControlBar(
                  query: _searchQuery,
                  view: _view,
                  onQueryChanged: (value) =>
                      setState(() => _searchQuery = value.trim()),
                  onViewChanged: (view) => setState(() {
                    _view = view;
                    _section = _DashboardSection.devices;
                  }),
                  onSettings: _showSettingsSheet,
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 112),
                    children: _mainChildren(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigation(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isScanning ? _cancelScan : _startScan,
        icon: Icon(_isScanning ? Icons.stop_rounded : Icons.radar),
        label: Text(_isScanning ? '중지' : '스캔'),
        tooltip: _isScanning ? '검색 중지 요청' : '현재 네트워크 검색 시작',
      ),
    );
  }

  List<Widget> _mainChildren(BuildContext context) {
    return switch (_section) {
      _DashboardSection.overview => _homeMainChildren(context),
      _DashboardSection.devices => _deviceMainChildren(context),
      _DashboardSection.findings => _findingsChildren(context),
    };
  }

  List<Widget> _homeMainChildren(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return [
      const SizedBox(height: 8),
      Text('내 네트워크', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      Text(
        _lastResult?.context.scannedSubnet ?? '스캔을 시작하면 연결된 장비가 표시됩니다.',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 18),
      _SummaryPanel(
        deviceCount: _overview.devices.length,
        warningCount: _overview.findings.length,
        isScanning: _isScanning,
        message: _message,
      ),
      if (_message != null) ...[
        const SizedBox(height: 12),
        _MessagePanel(message: _message!, isError: _messageIsError),
      ],
      if (_progress != null) ...[
        const SizedBox(height: 10),
        Text(
          _progressLabel(_progress),
          style: Theme.of(context).textTheme.labelMedium,
          textAlign: TextAlign.center,
        ),
      ],
      const SizedBox(height: 16),
      if (_overview.devices.isNotEmpty)
        _MeshNetworkView(
          devices: _filteredDevices,
          newDeviceIds: _newDeviceIds,
          onDeviceTap: _showDeviceDetails,
        )
      else
        _EmptyPanel(
          icon: Icons.radar,
          title: '아직 스캔 결과가 없습니다.',
          description: '하단의 스캔 버튼을 눌러 현재 Wi-Fi 장비를 확인하세요.',
        ),
      const SizedBox(height: 16),
      _NetworkContextCard(context: _lastResult?.context),
    ];
  }

  List<Widget> _deviceMainChildren(BuildContext context) {
    final devices = _filteredDevices;
    if (devices.isEmpty) {
      return [
        const SizedBox(height: 8),
        _EmptyPanel(
          icon: Icons.devices_other,
          title: _overview.devices.isEmpty ? '연결된 장비가 없습니다.' : '검색 결과가 없습니다.',
          description: _overview.devices.isEmpty
              ? '하단의 스캔 버튼으로 장비를 확인하세요.'
              : '검색어를 바꾸거나 지워 보세요.',
        ),
      ];
    }
    return [
      const SizedBox(height: 8),
      _DeviceCountHeader(count: devices.length, query: _searchQuery),
      const SizedBox(height: 12),
      switch (_view) {
        _DashboardView.mesh => _MeshNetworkView(
          devices: devices,
          newDeviceIds: _newDeviceIds,
          onDeviceTap: _showDeviceDetails,
        ),
        _DashboardView.cards => _DeviceCardGrid(
          devices: devices,
          newDeviceIds: _newDeviceIds,
          onDeviceTap: _showDeviceDetails,
        ),
        _DashboardView.list => _DeviceList(
          devices: devices,
          newDeviceIds: _newDeviceIds,
          onDeviceTap: _showDeviceDetails,
        ),
      },
      if (_lastResult != null) ...[
        const SizedBox(height: 16),
        _NetworkContextCard(context: _lastResult!.context),
        const SizedBox(height: 12),
        _LimitationsPanel(limitations: _lastResult!.limitations),
      ],
    ];
  }

  List<NetworkDevice> get _filteredDevices {
    final query = _searchQuery.toLowerCase();
    if (query.isEmpty) return _overview.devices;
    return _overview.devices
        .where((device) {
          final fields = [
            device.displayName,
            device.vendor ?? '',
            device.macAddress ?? '',
            ...device.ipAddresses,
          ];
          return fields.any((field) => field.toLowerCase().contains(query));
        })
        .toList(growable: false);
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
              Text('설정', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Text('화면', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 10),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('시스템')),
                  ButtonSegment(value: ThemeMode.light, label: Text('라이트')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('다크')),
                ],
                selected: {_themeMode},
                onSelectionChanged: (selection) {
                  final value = selection.first;
                  setState(() => _themeMode = value);
                  widget.onThemeModeChanged?.call(value);
                },
                showSelectedIcon: false,
              ),
              const Divider(height: 24),
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
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        final media = MediaQuery.of(dialogContext);
        final maxHeight = (media.size.height - media.viewInsets.bottom - 48)
            .clamp(300.0, 620.0)
            .toDouble();
        return Dialog(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surface.withValues(alpha: 0.94),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 520, maxHeight: maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        child: Icon(_deviceIcon(device.category)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          device.displayName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: '닫기',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _DetailRow(
                    label: '유형',
                    value: _categoryLabel(device.category),
                  ),
                  _DetailRow(
                    label: '소유 상태',
                    value: _ownershipLabel(device.ownershipStatus),
                  ),
                  _DetailRow(
                    label: 'IP 주소',
                    value: device.ipAddresses.join(', '),
                  ),
                  _DetailRow(
                    label: 'MAC 주소',
                    value: device.macAddress ?? '확인되지 않음',
                  ),
                  _DetailRow(label: '제조사', value: device.vendor ?? '확인되지 않음'),
                  _DetailRow(
                    label: '탐색 근거',
                    value: device.sources.map(_sourceLabel).join(', '),
                  ),
                  _DetailRow(
                    label: '식별 신뢰도',
                    value: '${(device.identityConfidence * 100).round()}%',
                  ),
                  _DetailRow(
                    label: '처음 확인',
                    value: _formatDateTime(device.firstSeenAt),
                  ),
                  _DetailRow(
                    label: '최근 확인',
                    value: _formatDateTime(device.lastSeenAt),
                  ),
                  const SizedBox(height: 16),
                  _InfoCallout(
                    icon: Icons.info_outline,
                    text:
                        '현재 탐색은 로컬 네트워크에서 확인 가능한 주소·이웃 테이블 중심입니다. '
                        '서비스 포트, mDNS/SSDP 이름, 제조사 정보는 별도 탐색을 추가하면 더 풍부해집니다.',
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('닫기'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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

class _TopControlBar extends StatelessWidget {
  const _TopControlBar({
    required this.query,
    required this.view,
    required this.onQueryChanged,
    required this.onViewChanged,
    required this.onSettings,
  });

  final String query;
  final _DashboardView view;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_DashboardView> onViewChanged;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.wifi_tethering, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  onChanged: onQueryChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: '장비 검색',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () => onQueryChanged(''),
                            icon: const Icon(Icons.clear, size: 18),
                            tooltip: '검색어 지우기',
                          ),
                    isDense: true,
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.55,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: onSettings,
                icon: const Icon(Icons.settings_outlined),
                tooltip: '설정',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('보기', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(width: 10),
              Expanded(
                child: SegmentedButton<_DashboardView>(
                  segments: const [
                    ButtonSegment(
                      value: _DashboardView.mesh,
                      icon: Icon(Icons.hub_outlined, size: 17),
                      label: Text('메시'),
                    ),
                    ButtonSegment(
                      value: _DashboardView.cards,
                      icon: Icon(Icons.grid_view_rounded, size: 17),
                      label: Text('카드'),
                    ),
                    ButtonSegment(
                      value: _DashboardView.list,
                      icon: Icon(Icons.view_list_rounded, size: 17),
                      label: Text('목록'),
                    ),
                  ],
                  selected: {view},
                  onSelectionChanged: (selection) =>
                      onViewChanged(selection.first),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.deviceCount,
    required this.warningCount,
    required this.isScanning,
    required this.message,
  });

  final int deviceCount;
  final int warningCount;
  final bool isScanning;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _SummaryValue(
                icon: Icons.devices_other,
                value: '$deviceCount',
                label: '연결 장비',
              ),
            ),
            Expanded(
              child: _SummaryValue(
                icon: warningCount == 0
                    ? Icons.verified_user_outlined
                    : Icons.warning_amber,
                value: '$warningCount',
                label: '보안 경고',
                color: warningCount == 0 ? scheme.primary : scheme.error,
              ),
            ),
            Expanded(
              child: _SummaryValue(
                icon: isScanning ? Icons.radar : Icons.check_circle_outline,
                value: isScanning ? '진행' : '대기',
                label: message == null ? '상태' : '최근 결과',
                color: isScanning ? scheme.tertiary : scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.icon,
    required this.value,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(height: 6),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _DeviceCountHeader extends StatelessWidget {
  const _DeviceCountHeader({required this.count, required this.query});

  final int count;
  final String query;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('장비 $count개', style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        if (query.isNotEmpty)
          Text('검색: $query', style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _NetworkContextCard extends StatelessWidget {
  const _NetworkContextCard({required this.context});

  final NetworkContext? context;

  @override
  Widget build(BuildContext buildContext) {
    final network = context;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: network == null
            ? const Row(
                children: [
                  Icon(Icons.info_outline),
                  SizedBox(width: 10),
                  Expanded(child: Text('스캔 후 인터페이스, 게이트웨이, 검색 범위가 표시됩니다.')),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.router_outlined, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '네트워크 정보',
                        style: Theme.of(buildContext).textTheme.titleSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _DetailRow(label: '인터페이스', value: network.interfaceName),
                  _DetailRow(label: '내 주소', value: network.ipv4Address),
                  _DetailRow(label: '게이트웨이', value: network.gateway),
                  _DetailRow(label: '검색 범위', value: network.scannedSubnet),
                  _DetailRow(
                    label: '범위 상태',
                    value: network.coverageLimited ? '일부 제한됨' : '전체 확인 시도',
                  ),
                ],
              ),
      ),
    );
  }
}

class _InfoCallout extends StatelessWidget {
  const _InfoCallout({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: scheme.primary),
          const SizedBox(width: 9),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _DeviceCardGrid extends StatelessWidget {
  const _DeviceCardGrid({
    required this.devices,
    required this.newDeviceIds,
    required this.onDeviceTap,
  });

  final List<NetworkDevice> devices;
  final Set<String> newDeviceIds;
  final ValueChanged<NetworkDevice> onDeviceTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 430 ? 2 : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: devices.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: columns == 1 ? 2.8 : 1.5,
          ),
          itemBuilder: (context, index) {
            final device = devices[index];
            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onDeviceTap(device),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_deviceIcon(device.category), size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    device.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                ),
                                if (newDeviceIds.contains(device.id))
                                  Icon(
                                    Icons.fiber_new,
                                    size: 16,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              device.ipAddresses.join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              device.vendor ?? _categoryLabel(device.category),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MeshNetworkView extends StatelessWidget {
  const _MeshNetworkView({
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
        height: 440,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final center = Offset(constraints.maxWidth / 2, 220);
            final positions = <String, Offset>{};
            final local = devices.cast<NetworkDevice?>().firstWhere(
              (device) =>
                  device!.sources.contains(DiscoverySource.localInterface),
              orElse: () => null,
            );
            if (local != null) positions[local.id] = center;
            final others = devices
                .where((device) => device != local)
                .toList(growable: false);
            final radiusBase = math.min(constraints.maxWidth, 360.0);
            for (var index = 0; index < others.length; index++) {
              final hash = others[index].id.codeUnits.fold<int>(
                0,
                (sum, item) => sum + item,
              );
              final angle = (index * 2.399963) + (hash % 31) / 100;
              final distance = radiusBase * (0.24 + (hash % 23) / 100);
              positions[others[index].id] = Offset(
                center.dx + math.cos(angle) * distance,
                center.dy + math.sin(angle) * distance,
              );
            }
            return Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    boundaryMargin: const EdgeInsets.all(100),
                    minScale: 0.75,
                    maxScale: 2.5,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: 440,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _MeshNetworkPainter(
                                positions: positions,
                                center: center,
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
                  left: 16,
                  top: 14,
                  child: Row(
                    children: [
                      Icon(
                        Icons.hub_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      const Text('메시 보기'),
                    ],
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Text(
                    '노드를 눌러 상세 정보',
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

class _MeshNetworkPainter extends CustomPainter {
  const _MeshNetworkPainter({
    required this.positions,
    required this.center,
    required this.scheme,
  });

  final Map<String, Offset> positions;
  final Offset center;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final ringPaint = Paint()
      ..color = scheme.outlineVariant.withValues(alpha: 0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final radius in [70.0, 140.0, 210.0]) {
      canvas.drawCircle(center, math.min(radius, size.width * 0.46), ringPaint);
    }
    final edgePaint = Paint()
      ..color = scheme.primary.withValues(alpha: 0.26)
      ..strokeWidth = 1.3;
    for (final position in positions.values) {
      if (position != center) canvas.drawLine(center, position, edgePaint);
    }
    final centerPaint = Paint()
      ..color = scheme.primary.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 54, centerPaint);
  }

  @override
  bool shouldRepaint(covariant _MeshNetworkPainter oldDelegate) =>
      oldDelegate.positions != positions || oldDelegate.center != center;
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

// ignore: unused_element
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

// ignore: unused_element
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
  const _DeviceList({
    required this.devices,
    required this.newDeviceIds,
    this.onDeviceTap,
  });

  final List<NetworkDevice> devices;
  final Set<String> newDeviceIds;
  final ValueChanged<NetworkDevice>? onDeviceTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < devices.length; index++) ...[
            ListTile(
              leading: Icon(_deviceIcon(devices[index].category)),
              onTap: onDeviceTap == null
                  ? null
                  : () => onDeviceTap!(devices[index]),
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

String _sourceLabel(DiscoverySource source) => switch (source) {
  DiscoverySource.localInterface => '내 인터페이스',
  DiscoverySource.router => '공유기',
  DiscoverySource.neighbor => '이웃 테이블',
  DiscoverySource.subnet => '서브넷 탐색',
  DiscoverySource.mdns => 'mDNS',
  DiscoverySource.ssdp => 'SSDP',
  DiscoverySource.manual => '수동 등록',
};

String _formatDateTime(DateTime value) => _formatTimestamp(value);

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
