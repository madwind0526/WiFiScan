import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:ui' as ui;

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
import 'package:wifi_scan/features/network_profiles/application/network_connection_service.dart';
import 'package:wifi_scan/features/network_profiles/application/network_profile_repository.dart';
import 'package:wifi_scan/features/network_profiles/domain/network_profile.dart';
import 'package:wifi_scan/features/network_profiles/infrastructure/platform_network_connection_service.dart';
import 'package:wifi_scan/features/network_profiles/infrastructure/profile_backup_codec.dart';
import 'package:wifi_scan/features/network_profiles/infrastructure/profile_transfer_file_service.dart';

const String _buildVersion = 'v1.0.0';

enum _DashboardSection { overview, networks, devices, findings }

enum _DashboardView { mesh, cards, list }

class _NetworkScanRecord {
  const _NetworkScanRecord({
    required this.deviceIds,
    required this.scannedAt,
    this.failed = false,
  });

  final Set<String> deviceIds;
  final DateTime scannedAt;
  final bool failed;
}

class SecurityDashboardPage extends StatefulWidget {
  const SecurityDashboardPage({
    super.key,
    this.discoveryService,
    this.inventoryRepository,
    this.securityRiskAnalyzer,
    this.connectionService,
    this.profileRepository,
    this.profileBackupCodec,
    this.profileTransferFileService,
    this.onThemeModeChanged,
  });

  final NetworkDiscoveryService? discoveryService;
  final InventoryRepository? inventoryRepository;
  final SecurityRiskAnalyzer? securityRiskAnalyzer;
  final NetworkConnectionService? connectionService;
  final NetworkProfileRepository? profileRepository;
  final ProfileBackupCodec? profileBackupCodec;
  final ProfileTransferFileService? profileTransferFileService;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  State<SecurityDashboardPage> createState() => _SecurityDashboardPageState();
}

class _SecurityDashboardPageState extends State<SecurityDashboardPage> {
  late final NetworkDiscoveryService _discoveryService;
  late final InventoryRepository _inventoryRepository;
  late final SecurityRiskAnalyzer _securityRiskAnalyzer;
  late final NetworkConnectionService _connectionService;
  late final NetworkProfileRepository _profileRepository;
  late final ProfileBackupCodec _profileBackupCodec;
  late final ProfileTransferFileService _profileTransferFileService;
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
  ThemeMode _themeMode = ThemeMode.dark;
  List<NetworkProfile> _networkProfiles = const [];
  bool _isScanningAllNetworks = false;
  final Map<String, _NetworkScanRecord> _networkScans = {};
  String? _networkFilterId;
  String? _currentSsid;

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
    _connectionService =
        widget.connectionService ?? createNetworkConnectionService();
    _profileRepository = widget.profileRepository ?? NetworkProfileRepository();
    _profileBackupCodec = widget.profileBackupCodec ?? ProfileBackupCodec();
    _profileTransferFileService =
        widget.profileTransferFileService ??
        const PlatformProfileTransferFileService();
    _loadNetworkProfiles();
  }

  Future<void> _loadNetworkProfiles() async {
    final stored = await _profileRepository.load();
    List<NetworkProfile> profiles = stored;
    try {
      final available = await _connectionService.discoverAvailableProfiles();
      final known = {for (final profile in stored) profile.ssid: profile};
      for (final profile in available) {
        known.putIfAbsent(profile.ssid, () => profile);
      }
      profiles = known.values.toList(growable: false);
      await _profileRepository.save(profiles);
    } catch (_) {
      // The profile list is optional and should not block the main dashboard.
    }
    String? ssid;
    try {
      ssid = await _connectionService.currentSsid();
    } catch (_) {
      // The current SSID is informational only.
    }
    if (!mounted) return;
    setState(() {
      _networkProfiles = profiles;
      _currentSsid = ssid;
    });
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
      String? scannedSsid;
      try {
        scannedSsid = await _connectionService.currentSsid();
      } catch (_) {
        // Tagging the scan with its network is best-effort.
      }
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
      final matchedProfiles = scannedSsid == null
          ? const <NetworkProfile>[]
          : _networkProfiles
                .where((profile) => profile.ssid == scannedSsid)
                .toList(growable: false);
      setState(() {
        if (scannedSsid != null) _currentSsid = scannedSsid;
        if (matchedProfiles.isNotEmpty) {
          _networkScans[matchedProfiles.first.id] = _NetworkScanRecord(
            deviceIds: result.devices.map((device) => device.id).toSet(),
            scannedAt: DateTime.now(),
          );
        }
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

  Future<void> _scanAllNetworks() async {
    if (_isScanning || _networkProfiles.isEmpty) return;
    if (io.Platform.isAndroid) {
      final shouldContinue = await _showAndroidPermissionRationale();
      if (shouldContinue != true || !mounted) return;
    }

    final token = DiscoveryCancellationToken();
    final originalSsid = await _connectionService.currentSsid();
    final devicesById = <String, NetworkDevice>{};
    final findings = <SecurityFinding>[];
    final newDeviceIds = <String>{};
    DiscoveryResult? lastResult;
    var completedNetworks = 0;
    var failures = 0;
    setState(() {
      _isScanning = true;
      _isScanningAllNetworks = true;
      _cancellationToken = token;
      _progress = null;
      _message = '등록된 네트워크를 준비하는 중입니다.';
      _messageIsError = false;
    });

    try {
      for (final profile in _networkProfiles) {
        if (token.isCancelled) throw const DiscoveryCancelledException();
        setState(() {
          _message = '${profile.displayName}에 연결하는 중입니다.';
        });
        try {
          await _connectionService.connect(profile);
          final result = await _discoveryService.discover(
            cancellationToken: token,
            onProgress: (progress) {
              if (!mounted) return;
              setState(() => _progress = progress);
            },
          );
          lastResult = result;
          final update = await _inventoryRepository.record(result);
          devicesById.addAll({
            for (final device in result.devices) device.id: device,
          });
          newDeviceIds.addAll(update.newDevices.map((device) => device.id));
          findings.addAll(
            _securityRiskAnalyzer
                .analyze(snapshot: update.snapshot, inventoryUpdate: update)
                .findings,
          );
          completedNetworks += 1;
          _networkScans[profile.id] = _NetworkScanRecord(
            deviceIds: result.devices.map((device) => device.id).toSet(),
            scannedAt: DateTime.now(),
          );
        } on NetworkConnectionException {
          failures += 1;
          _networkScans[profile.id] = _NetworkScanRecord(
            deviceIds: const {},
            scannedAt: DateTime.now(),
            failed: true,
          );
        } on DiscoveryUnavailableException {
          failures += 1;
          _networkScans[profile.id] = _NetworkScanRecord(
            deviceIds: const {},
            scannedAt: DateTime.now(),
            failed: true,
          );
        }
      }
      if (!mounted) return;
      final plans = const ManualRemediationPlanner().build(findings);
      setState(() {
        _overview = NetworkOverview(
          devices: devicesById.values.toList(growable: false),
          findings: findings,
          lastScannedAt: DateTime.now(),
          newDeviceCount: newDeviceIds.length,
        );
        _lastResult = lastResult;
        _newDeviceIds = newDeviceIds;
        _remediationPlans = plans;
        _hasCompletedScan = completedNetworks > 0;
        _securityAnalysisCompleted = completedNetworks > 0;
        _message = failures == 0
            ? '$completedNetworks개 네트워크 검색을 완료했습니다.'
            : '$completedNetworks개 네트워크를 확인했습니다. $failures개 네트워크는 연결하지 못했습니다.';
        _messageIsError = failures > 0;
      });
    } on DiscoveryCancelledException {
      if (mounted) {
        setState(() {
          _message = '전체 네트워크 검색을 중지했습니다.';
          _messageIsError = false;
        });
      }
    } finally {
      try {
        await _connectionService.restore(originalSsid);
      } catch (_) {
        if (mounted) {
          setState(() {
            _message = '검색은 끝났지만 원래 Wi-Fi로 자동 복원하지 못했습니다.';
            _messageIsError = true;
          });
        }
      }
      if (mounted) {
        setState(() {
          _isScanning = false;
          _isScanningAllNetworks = false;
          _cancellationToken = null;
        });
      }
    }
  }

  Future<void> _scanNetwork(NetworkProfile profile) async {
    if (_isScanning) return;
    if (io.Platform.isAndroid) {
      final shouldContinue = await _showAndroidPermissionRationale();
      if (shouldContinue != true || !mounted) return;
    }

    final token = DiscoveryCancellationToken();
    String? originalSsid;
    try {
      originalSsid = await _connectionService.currentSsid();
    } catch (_) {
      // Restoring the original network is best-effort.
    }
    final needsConnect = originalSsid != profile.ssid;
    setState(() {
      _isScanning = true;
      _cancellationToken = token;
      _progress = null;
      _message = '${profile.displayName}에 연결하는 중입니다.';
      _messageIsError = false;
    });

    try {
      if (needsConnect) await _connectionService.connect(profile);
      final result = await _discoveryService.discover(
        cancellationToken: token,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      final update = await _inventoryRepository.record(result);
      final analyzed = _securityRiskAnalyzer.analyze(
        snapshot: update.snapshot,
        inventoryUpdate: update,
      );
      final plans = const ManualRemediationPlanner().build(analyzed.findings);
      setState(() {
        _networkScans[profile.id] = _NetworkScanRecord(
          deviceIds: result.devices.map((device) => device.id).toSet(),
          scannedAt: DateTime.now(),
        );
        _overview = NetworkOverview(
          devices: update.snapshot.devices,
          findings: analyzed.findings,
          lastScannedAt: DateTime.now(),
          newDeviceCount: update.newDevices.length,
        );
        _lastResult = result;
        _newDeviceIds = update.newDevices.map((device) => device.id).toSet();
        _remediationPlans = plans;
        _hasCompletedScan = true;
        _securityAnalysisCompleted = true;
        _message = '${profile.displayName} 검색을 완료했습니다.';
        _messageIsError = false;
      });
    } on DiscoveryCancelledException {
      if (mounted) {
        setState(() {
          _message = '검색을 중지했습니다.';
          _messageIsError = false;
        });
      }
    } on NetworkConnectionException catch (error) {
      if (mounted) {
        setState(() {
          _networkScans[profile.id] = _NetworkScanRecord(
            deviceIds: const {},
            scannedAt: DateTime.now(),
            failed: true,
          );
          _message = error.message;
          _messageIsError = true;
        });
      }
    } on DiscoveryUnavailableException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message;
          _messageIsError = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = '네트워크 정보를 읽지 못했습니다. 잠시 후 다시 시도하세요.';
          _messageIsError = true;
        });
      }
    } finally {
      if (needsConnect) {
        try {
          await _connectionService.restore(originalSsid);
        } catch (_) {
          if (mounted) {
            setState(() {
              _message = '검색은 끝났지만 원래 Wi-Fi로 자동 복원하지 못했습니다.';
              _messageIsError = true;
            });
          }
        }
      }
      if (mounted) {
        setState(() {
          _isScanning = false;
          _cancellationToken = null;
        });
      }
    }
  }

  Future<void> _showNetworkProfiles() async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black38,
      builder: (dialogContext) {
        return _TranslucentDialog(
          child: StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '네트워크 프로필',
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
                  const SizedBox(height: 6),
                  if (_networkProfiles.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        '등록된 프로필이 없습니다. 아래 추가 버튼으로 등록하세요.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  else
                    for (final profile in _networkProfiles)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.wifi,
                              size: 19,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    profile.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    profile.ssid,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () async {
                                await _showProfileEditor(profile);
                                setDialogState(() {});
                              },
                              icon: const Icon(Icons.edit_outlined, size: 19),
                              tooltip: '편집',
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              onPressed: () async {
                                await _deleteProfile(profile);
                                setDialogState(() {});
                              },
                              icon: const Icon(Icons.delete_outline, size: 19),
                              tooltip: '삭제',
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        await _showProfileEditor(null);
                        setDialogState(() {});
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('추가'),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _deleteProfile(NetworkProfile profile) async {
    final profiles = _networkProfiles
        .where((item) => item.id != profile.id)
        .toList(growable: false);
    await _profileRepository.save(profiles);
    if (!mounted) return;
    setState(() {
      _networkProfiles = profiles;
      _networkScans.remove(profile.id);
      if (_networkFilterId == profile.id) _networkFilterId = null;
    });
  }

  Future<void> _showProfileEditor(NetworkProfile? existing) async {
    final profile = await showDialog<NetworkProfile>(
      context: context,
      barrierColor: Colors.black38,
      builder: (dialogContext) => _ProfileEditorDialog(existing: existing),
    );
    if (profile == null) return;
    final merged = [
      ..._networkProfiles.where(
        (item) => item.ssid != profile.ssid && item.id != existing?.id,
      ),
      profile,
    ];
    await _profileRepository.save(merged);
    if (!mounted) return;
    setState(() => _networkProfiles = merged);
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
                _TopBar(
                  isScanning: _isScanning,
                  currentSsid: _currentSsid,
                  onScanAll: _networkProfiles.isEmpty || _isScanning
                      ? null
                      : _scanAllNetworks,
                  onNetworks: _showNetworkProfiles,
                  onSettings: _showSettingsSheet,
                ),
                Expanded(
                  child: _section == _DashboardSection.overview
                      ? _homeBody(context)
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: _mainChildren(context),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigation(context),
    );
  }

  List<Widget> _mainChildren(BuildContext context) {
    return switch (_section) {
      _DashboardSection.overview => const [],
      _DashboardSection.networks => _networksChildren(context),
      _DashboardSection.devices => _deviceMainChildren(context),
      _DashboardSection.findings => _findingsChildren(context),
    };
  }

  Widget _homeBody(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? const Color(0xFF1E2029)
        : const Color(0xFFEFEFF4);
    final network = _lastResult?.context;
    final footerText = network == null
        ? '스캔 후 인터페이스, 게이트웨이, 검색 범위가 표시됩니다.'
        : '${network.interfaceName} · ${network.ipv4Address} · '
              'GW ${network.gateway} · ${network.scannedSubnet}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            if (_overview.devices.isNotEmpty)
              Positioned.fill(
                child: _MeshNetworkView(
                  devices: _filteredDevices,
                  newDeviceIds: _newDeviceIds,
                  onDeviceTap: _showDeviceDetails,
                  framed: false,
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: Column(
                children: [
                  if (_message != null)
                    _MessagePanel(message: _message!, isError: _messageIsError),
                  if (_progress != null && _isScanning) ...[
                    const SizedBox(height: 8),
                    Text(
                      _progressLabel(_progress),
                      style: Theme.of(context).textTheme.labelMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              left: 16,
              bottom: 36,
              child: _MiniSummary(
                deviceCount: _overview.devices.length,
                warningCount: _overview.findings.length,
                networkCount: _networkProfiles.length,
                scannedNetworkCount: _networkScans.values
                    .where((record) => !record.failed)
                    .length,
                onNetworksTap: () =>
                    setState(() => _section = _DashboardSection.networks),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Text(
                footerText,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _networksChildren(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groups = <String, List<NetworkProfile>>{};
    for (final profile in _networkProfiles) {
      groups.putIfAbsent(_routerGroupName(profile.ssid), () => []).add(profile);
    }
    return [
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: Text(
              '네트워크',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          IconButton(
            onPressed: _showNetworkProfiles,
            icon: const Icon(Icons.tune),
            tooltip: '네트워크 프로필 관리',
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        _networkProfiles.isEmpty
            ? '접속 가능한 Wi-Fi 프로필을 추가하면 여기에 표시됩니다.'
            : '공유기 ${groups.length}대 · Wi-Fi ${_networkProfiles.length}개',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _networkProfiles.isEmpty || _isScanning
              ? null
              : _scanAllNetworks,
          icon: Icon(
            _isScanningAllNetworks ? Icons.sync : Icons.travel_explore,
          ),
          label: Text(_isScanningAllNetworks ? '전체 네트워크 검색 중' : '전체 네트워크 스캔'),
        ),
      ),
      if (_message != null) ...[
        const SizedBox(height: 12),
        _MessagePanel(message: _message!, isError: _messageIsError),
      ],
      if (_isScanning && _progress != null) ...[
        const SizedBox(height: 10),
        Text(
          _progressLabel(_progress),
          style: Theme.of(context).textTheme.labelMedium,
          textAlign: TextAlign.center,
        ),
      ],
      const SizedBox(height: 16),
      if (_networkProfiles.isEmpty)
        _EmptyPanel(
          icon: Icons.wifi_find,
          title: '등록된 네트워크가 없습니다.',
          description: '오른쪽 위의 관리 버튼으로 SSID와 암호를 추가하세요.',
        )
      else
        for (final entry in groups.entries) ...[
          _RouterGroupCard(
            groupName: entry.key,
            profiles: entry.value,
            currentSsid: _currentSsid,
            scans: _networkScans,
            isScanning: _isScanning,
            onScan: _scanNetwork,
            onShowDevices: (profile) => setState(() {
              _networkFilterId = profile.id;
              _section = _DashboardSection.devices;
            }),
          ),
          const SizedBox(height: 12),
        ],
    ];
  }

  List<Widget> _deviceMainChildren(BuildContext context) {
    final devices = _filteredDevices;
    final header = [
      const SizedBox(height: 8),
      _DeviceControlBar(
        query: _searchQuery,
        view: _view,
        onQueryChanged: (value) => setState(() => _searchQuery = value.trim()),
        onViewChanged: (view) => setState(() => _view = view),
      ),
      if (_networkScans.isNotEmpty) ...[
        const SizedBox(height: 10),
        _NetworkFilterChips(
          profiles: _networkProfiles
              .where((profile) => _networkScans.containsKey(profile.id))
              .toList(growable: false),
          selectedId: _networkFilterId,
          onSelected: (id) => setState(() => _networkFilterId = id),
        ),
      ],
      const SizedBox(height: 12),
    ];
    if (devices.isEmpty) {
      return [
        ...header,
        _EmptyPanel(
          icon: Icons.devices_other,
          title: _overview.devices.isEmpty ? '연결된 장비가 없습니다.' : '검색 결과가 없습니다.',
          description: _overview.devices.isEmpty
              ? '하단의 스캔 버튼으로 장비를 확인하세요.'
              : '검색어 또는 네트워크 필터를 바꿔 보세요.',
        ),
      ];
    }
    return [
      ...header,
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
    var devices = _overview.devices;
    final filterRecord = _networkFilterId == null
        ? null
        : _networkScans[_networkFilterId];
    if (filterRecord != null) {
      devices = devices
          .where((device) => filterRecord.deviceIds.contains(device.id))
          .toList(growable: false);
    }
    final query = _searchQuery.toLowerCase();
    if (query.isEmpty) return devices;
    return devices
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
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _NavItem(
            icon: Icons.home_outlined,
            tooltip: '홈',
            selected: _section == _DashboardSection.overview,
            onTap: () => setState(() => _section = _DashboardSection.overview),
          ),
          _NavItem(
            icon: Icons.wifi,
            tooltip: '네트워크',
            selected: _section == _DashboardSection.networks,
            onTap: () => setState(() => _section = _DashboardSection.networks),
          ),
          _ScanButton(
            isScanning: _isScanning,
            onTap: _isScanning ? _cancelScan : _startScan,
          ),
          _NavItem(
            icon: Icons.devices_other,
            tooltip: '장비',
            selected: _section == _DashboardSection.devices,
            onTap: () => setState(() => _section = _DashboardSection.devices),
          ),
          _NavItem(
            icon: Icons.shield_outlined,
            tooltip: '경고',
            selected: _section == _DashboardSection.findings,
            onTap: () => setState(() => _section = _DashboardSection.findings),
          ),
        ],
      ),
    );
  }

  Future<void> _showSettingsSheet() async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black38,
      builder: (dialogContext) {
        return _TranslucentDialog(
          child: StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('설정', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Text('Theme', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode_outlined, size: 17),
                          label: Text('Light'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode_outlined, size: 17),
                          label: Text('Dark'),
                        ),
                      ],
                      selected: {
                        _themeMode == ThemeMode.light
                            ? ThemeMode.light
                            : ThemeMode.dark,
                      },
                      onSelectionChanged: (selection) {
                        final value = selection.first;
                        setDialogState(() {});
                        setState(() => _themeMode = value);
                        widget.onThemeModeChanged?.call(value);
                      },
                      showSelectedIcon: false,
                    ),
                  ),
                  const Divider(height: 28),
                  Text(
                    '네트워크 프로필 파일',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.of(dialogContext).pop();
                            await _importProfiles();
                          },
                          icon: const Icon(Icons.file_download_outlined),
                          label: const Text('가져오기'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.of(dialogContext).pop();
                            await _exportProfiles();
                          },
                          icon: const Icon(Icons.file_upload_outlined),
                          label: const Text('내보내기'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '저장된 Wi-Fi 프로필을 파일로 내보내거나 불러옵니다. '
                    '내보내기 파일은 입력한 암호로 암호화됩니다.',
                    style: Theme.of(context).textTheme.labelSmall,
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
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _exportProfiles() async {
    if (_networkProfiles.isEmpty) {
      setState(() {
        _message = '내보낼 네트워크 프로필이 없습니다.';
        _messageIsError = true;
      });
      return;
    }
    final password = await _askProfileBackupPassword(confirm: true);
    if (password == null) return;
    try {
      final content = await _profileBackupCodec.exportProfiles(
        _networkProfiles,
        password: password,
      );
      final saved = await _profileTransferFileService.save(content);
      if (!saved) return;
      if (!mounted) return;
      setState(() {
        _message = '네트워크 프로필 ${_networkProfiles.length}개를 내보냈습니다.';
        _messageIsError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = '네트워크 프로필을 내보내지 못했습니다.';
        _messageIsError = true;
      });
    }
  }

  Future<void> _importProfiles() async {
    try {
      final content = await _profileTransferFileService.pick();
      if (content == null || !mounted) return;
      final password = await _askProfileBackupPassword(confirm: false);
      if (password == null) return;
      final imported = await _profileBackupCodec.importProfiles(
        content,
        password: password,
      );
      final merged = {
        for (final profile in _networkProfiles) profile.ssid: profile,
      };
      for (final profile in imported) {
        merged[profile.ssid] = profile;
      }
      final profiles = merged.values.toList(growable: false);
      await _profileRepository.save(profiles);
      if (!mounted) return;
      setState(() {
        _networkProfiles = profiles;
        _message = '네트워크 프로필 ${imported.length}개를 가져왔습니다.';
        _messageIsError = false;
      });
    } on ProfileBackupException {
      if (!mounted) return;
      setState(() {
        _message = '암호가 올바르지 않거나 파일이 손상되었습니다.';
        _messageIsError = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = '네트워크 프로필을 가져오지 못했습니다.';
        _messageIsError = true;
      });
    }
  }

  Future<String?> _askProfileBackupPassword({required bool confirm}) {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black38,
      builder: (_) => _ProfileBackupPasswordDialog(confirm: confirm),
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

class _ProfileEditorDialog extends StatefulWidget {
  const _ProfileEditorDialog({required this.existing});

  final NetworkProfile? existing;

  @override
  State<_ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends State<_ProfileEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _ssidController;
  late final TextEditingController _passwordController;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existing?.displayName ?? '',
    );
    _ssidController = TextEditingController(text: widget.existing?.ssid ?? '');
    _passwordController = TextEditingController(
      text: widget.existing?.password ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _save() {
    final ssid = _ssidController.text.trim();
    if (ssid.isEmpty) return;
    final name = _nameController.text.trim();
    final password = _passwordController.text;
    Navigator.of(context).pop(
      NetworkProfile(
        id: ssid,
        ssid: ssid,
        displayName: name.isEmpty ? ssid : name,
        password: password.isEmpty ? widget.existing?.password : password,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _TranslucentDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.existing == null ? '프로필 추가' : '프로필 편집',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '표시 이름',
              hintText: '예: 거실 공유기 5G',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ssidController,
            decoration: const InputDecoration(labelText: 'Wi-Fi 이름(SSID)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Wi-Fi 암호',
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
                tooltip: _obscurePassword ? '암호 표시' : '암호 숨기기',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '암호는 운영체제 보안 저장소에 저장됩니다.',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('취소'),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _save, child: const Text('저장')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileBackupPasswordDialog extends StatefulWidget {
  const _ProfileBackupPasswordDialog({required this.confirm});

  final bool confirm;

  @override
  State<_ProfileBackupPasswordDialog> createState() =>
      _ProfileBackupPasswordDialogState();
}

class _ProfileBackupPasswordDialogState
    extends State<_ProfileBackupPasswordDialog> {
  late final TextEditingController _passwordController;
  late final TextEditingController _confirmationController;
  bool _obscurePassword = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _passwordController = TextEditingController();
    _confirmationController = TextEditingController();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _passwordController.text;
    if (password.length < ProfileBackupCodec.minimumPasswordLength) {
      setState(() => _errorText = '암호는 8자 이상이어야 합니다.');
      return;
    }
    if (widget.confirm && password != _confirmationController.text) {
      setState(() => _errorText = '입력한 암호가 서로 다릅니다.');
      return;
    }
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    return _TranslucentDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.confirm ? '내보내기 암호 설정' : '내보내기 암호 입력',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            widget.confirm
                ? '이 암호는 파일을 불러올 때 필요하며 앱에는 저장되지 않습니다.'
                : '파일을 내보낼 때 사용한 암호를 입력하세요.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('profile-backup-password'),
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofocus: true,
            textInputAction: widget.confirm
                ? TextInputAction.next
                : TextInputAction.done,
            onSubmitted: widget.confirm ? null : (_) => _submit(),
            decoration: InputDecoration(
              labelText: '내보내기 암호',
              helperText: '8자 이상',
              errorText: _errorText,
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                tooltip: _obscurePassword ? '암호 표시' : '암호 숨기기',
              ),
            ),
          ),
          if (widget.confirm) ...[
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('profile-backup-password-confirmation'),
              controller: _confirmationController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: '암호 확인'),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('취소'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _submit,
                child: Text(widget.confirm ? '내보내기' : '불러오기'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TranslucentDialog extends StatelessWidget {
  const _TranslucentDialog({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final maxHeight = (media.size.height - media.viewInsets.bottom - 48)
        .clamp(200.0, 680.0)
        .toDouble();
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: maxHeight),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: SingleChildScrollView(child: child)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isScanning,
    required this.currentSsid,
    required this.onScanAll,
    required this.onNetworks,
    required this.onSettings,
  });

  final bool isScanning;
  final String? currentSsid;
  final VoidCallback? onScanAll;
  final VoidCallback onNetworks;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Row(
          children: [
            Icon(Icons.wifi_tethering, color: scheme.primary, size: 22),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WifiScan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  Text(
                    _buildVersion,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(child: _CurrentNetworkChip(ssid: currentSsid)),
            ),
            IconButton(
              onPressed: onScanAll,
              icon: Icon(isScanning ? Icons.sync : Icons.travel_explore),
              tooltip: '전체 네트워크 스캔',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: onNetworks,
              icon: const Icon(Icons.wifi_find_outlined),
              tooltip: '네트워크 프로필',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: onSettings,
              icon: const Icon(Icons.settings_outlined),
              tooltip: '설정',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.expand(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Icon(icon, size: 24, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanButton extends StatefulWidget {
  const _ScanButton({required this.isScanning, required this.onTap});

  final bool isScanning;
  final VoidCallback onTap;

  @override
  State<_ScanButton> createState() => _ScanButtonState();
}

class _ScanButtonState extends State<_ScanButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isScanning) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _ScanButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isScanning && !oldWidget.isScanning) {
      _controller.repeat();
    } else if (!widget.isScanning && oldWidget.isScanning) {
      _controller
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Tooltip(
        message: widget.isScanning ? '검색 중지 요청' : '현재 네트워크 검색 시작',
        child: InkWell(
          onTap: widget.onTap,
          child: SizedBox.expand(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: RotationTransition(
                  turns: _controller,
                  child: ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: widget.isScanning
                          ? [scheme.tertiary, scheme.primary]
                          : [scheme.primary, scheme.secondary],
                    ).createShader(bounds),
                    child: const Icon(
                      Icons.track_changes,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeviceControlBar extends StatelessWidget {
  const _DeviceControlBar({
    required this.query,
    required this.view,
    required this.onQueryChanged,
    required this.onViewChanged,
  });

  final String query;
  final _DashboardView view;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_DashboardView> onViewChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
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
              fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        for (final entry in const [
          (_DashboardView.mesh, Icons.hub_outlined, '메시'),
          (_DashboardView.cards, Icons.grid_view_rounded, '카드'),
          (_DashboardView.list, Icons.view_list_rounded, '목록'),
        ])
          IconButton(
            onPressed: () => onViewChanged(entry.$1),
            icon: Icon(entry.$2, size: 20),
            tooltip: entry.$3,
            color: view == entry.$1 ? scheme.primary : scheme.onSurfaceVariant,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

class _NetworkFilterChips extends StatelessWidget {
  const _NetworkFilterChips({
    required this.profiles,
    required this.selectedId,
    required this.onSelected,
  });

  final List<NetworkProfile> profiles;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('전체'),
            selected: selectedId == null,
            onSelected: (_) => onSelected(null),
            visualDensity: VisualDensity.compact,
          ),
          for (final profile in profiles) ...[
            const SizedBox(width: 6),
            ChoiceChip(
              avatar: Icon(
                _is5GhzSsid(profile.ssid) ? Icons.network_wifi : Icons.wifi,
                size: 15,
              ),
              label: Text(profile.displayName),
              selected: selectedId == profile.id,
              onSelected: (_) => onSelected(profile.id),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}

class _RouterGroupCard extends StatelessWidget {
  const _RouterGroupCard({
    required this.groupName,
    required this.profiles,
    required this.currentSsid,
    required this.scans,
    required this.isScanning,
    required this.onScan,
    required this.onShowDevices,
  });

  final String groupName;
  final List<NetworkProfile> profiles;
  final String? currentSsid;
  final Map<String, _NetworkScanRecord> scans;
  final bool isScanning;
  final ValueChanged<NetworkProfile> onScan;
  final ValueChanged<NetworkProfile> onShowDevices;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Icon(Icons.router_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    groupName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  'Wi-Fi ${profiles.length}개',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          for (final profile in profiles)
            _NetworkRow(
              profile: profile,
              isConnected: currentSsid == profile.ssid,
              record: scans[profile.id],
              isScanning: isScanning,
              onScan: () => onScan(profile),
              onTap: () => onShowDevices(profile),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _NetworkRow extends StatelessWidget {
  const _NetworkRow({
    required this.profile,
    required this.isConnected,
    required this.record,
    required this.isScanning,
    required this.onScan,
    required this.onTap,
  });

  final NetworkProfile profile;
  final bool isConnected;
  final _NetworkScanRecord? record;
  final bool isScanning;
  final VoidCallback onScan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final is5Ghz = _is5GhzSsid(profile.ssid);
    final status = record == null
        ? '아직 스캔하지 않았습니다.'
        : record!.failed
        ? '연결하지 못했습니다.'
        : '장비 ${record!.deviceIds.length}개 · ${_formatTimestamp(record!.scannedAt)}';
    return InkWell(
      onTap: record != null && !record!.failed ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: (is5Ghz ? scheme.primary : scheme.tertiary).withValues(
                  alpha: 0.16,
                ),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                is5Ghz ? '5G' : '2.4G',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: is5Ghz ? scheme.primary : scheme.tertiary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          profile.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (isConnected) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.shade400,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    status,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: record?.failed == true
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: isScanning ? null : onScan,
              icon: const Icon(Icons.radar, size: 20),
              tooltip: '${profile.displayName} 스캔',
              color: scheme.primary,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentNetworkChip extends StatelessWidget {
  const _CurrentNetworkChip({required this.ssid});

  final String? ssid;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? const Color(0xFF2E3038)
        : const Color(0xFFE4E4EA);
    final connected = ssid != null && ssid!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(22),
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              connected ? Icons.wifi : Icons.wifi_off,
              size: 16,
              color: connected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                connected ? ssid! : '연결된 네트워크 없음',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniSummary extends StatelessWidget {
  const _MiniSummary({
    required this.deviceCount,
    required this.warningCount,
    required this.networkCount,
    required this.scannedNetworkCount,
    required this.onNetworksTap,
  });

  final int deviceCount;
  final int warningCount;
  final int networkCount;
  final int scannedNetworkCount;
  final VoidCallback onNetworksTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MiniSummaryRow(
          icon: Icons.devices_other,
          value: '$deviceCount',
          tooltip: '연결 장비',
          color: scheme.primary,
        ),
        const SizedBox(height: 8),
        _MiniSummaryRow(
          icon: warningCount == 0
              ? Icons.verified_user_outlined
              : Icons.warning_amber,
          value: '$warningCount',
          tooltip: '보안 경고',
          color: warningCount == 0 ? scheme.primary : scheme.error,
        ),
        const SizedBox(height: 8),
        _MiniSummaryRow(
          icon: Icons.wifi,
          value: '$scannedNetworkCount/$networkCount',
          tooltip: '네트워크',
          color: scheme.primary,
          onTap: onNetworksTap,
        ),
      ],
    );
  }
}

class _MiniSummaryRow extends StatelessWidget {
  const _MiniSummaryRow({
    required this.icon,
    required this.value,
    required this.tooltip,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String tooltip;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 23, color: color),
            const SizedBox(width: 7),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
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
    this.framed = true,
  });

  final List<NetworkDevice> devices;
  final Set<String> newDeviceIds;
  final ValueChanged<NetworkDevice> onDeviceTap;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    if (!framed) return _content(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(height: 440, child: _content(context)),
    );
  }

  Widget _content(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 440.0;
        final center = Offset(constraints.maxWidth / 2, viewHeight / 2);
        final positions = <String, Offset>{};
        final local = devices.cast<NetworkDevice?>().firstWhere(
          (device) => device!.sources.contains(DiscoverySource.localInterface),
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
                  height: viewHeight,
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
          ],
        );
      },
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

bool _is5GhzSsid(String ssid) =>
    RegExp(r'5\s*g(hz)?', caseSensitive: false).hasMatch(ssid);

String _routerGroupName(String ssid) {
  final base = ssid
      .replaceFirst(
        RegExp(r'[\s_-]*(2[.,]?4|5)\s*g(hz)?\s*$', caseSensitive: false),
        '',
      )
      .trim();
  return base.isEmpty ? ssid : base;
}

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
