import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/domain/discovery_result.dart';
import 'package:wifi_scan/features/discovery/domain/network_context.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';

class WindowsNetworkDiscoveryService implements NetworkDiscoveryService {
  const WindowsNetworkDiscoveryService({
    this.pingTimeoutMilliseconds = 250,
    this.maxConcurrentProbes = 24,
  });

  final int pingTimeoutMilliseconds;
  final int maxConcurrentProbes;

  @override
  Future<DiscoveryResult> discover({
    required DiscoveryCancellationToken cancellationToken,
    required void Function(DiscoveryProgress progress) onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();
    onProgress(
      const DiscoveryProgress(
        stage: DiscoveryStage.preparing,
        completed: 0,
        total: 0,
      ),
    );

    final rawContext = await _readPrimaryNetworkContext();
    _throwIfCancelled(cancellationToken);
    final scanPlan = _createScanPlan(rawContext);
    final targets = scanPlan.targets;

    onProgress(
      DiscoveryProgress(
        stage: DiscoveryStage.probing,
        completed: 0,
        total: targets.length,
      ),
    );
    await _probeTargets(
      targets,
      cancellationToken: cancellationToken,
      onProgress: onProgress,
    );
    _throwIfCancelled(cancellationToken);

    onProgress(
      DiscoveryProgress(
        stage: DiscoveryStage.collecting,
        completed: targets.length,
        total: targets.length,
      ),
    );
    final neighbors = await _readNeighbors(
      interfaceIndex: rawContext.interfaceIndex,
      scanPlan: scanPlan,
    );
    _throwIfCancelled(cancellationToken);

    final now = DateTime.now();
    final devices = <NetworkDevice>[
      NetworkDevice(
        id: 'local:${rawContext.ipv4Address}',
        displayName: '이 Windows 컴퓨터',
        category: DeviceCategory.computer,
        ownershipStatus: OwnershipStatus.confirmed,
        ipAddresses: [rawContext.ipv4Address],
        sources: const [DiscoverySource.localInterface],
        firstSeenAt: now,
        lastSeenAt: now,
        identityConfidence: 1,
      ),
      ...neighbors.map(
        (neighbor) => NetworkDevice(
          id: neighbor.macAddress ?? 'ip:${neighbor.ipAddress}',
          displayName: neighbor.ipAddress == rawContext.gateway
              ? '기본 게이트웨이'
              : '확인되지 않은 장비',
          category: neighbor.ipAddress == rawContext.gateway
              ? DeviceCategory.router
              : DeviceCategory.unknown,
          ownershipStatus: OwnershipStatus.unconfirmed,
          ipAddresses: [neighbor.ipAddress],
          sources: [
            if (neighbor.ipAddress == rawContext.gateway)
              DiscoverySource.router,
            DiscoverySource.neighbor,
            DiscoverySource.subnet,
          ],
          firstSeenAt: now,
          lastSeenAt: now,
          identityConfidence: neighbor.macAddress == null ? 0.55 : 0.85,
          macAddress: neighbor.macAddress,
        ),
      ),
    ]..sort(_compareDevices);

    stopwatch.stop();
    onProgress(
      DiscoveryProgress(
        stage: DiscoveryStage.complete,
        completed: targets.length,
        total: targets.length,
      ),
    );

    return DiscoveryResult(
      context: NetworkContext(
        interfaceName: rawContext.interfaceName,
        interfaceIndex: rawContext.interfaceIndex,
        ipv4Address: rawContext.ipv4Address,
        prefixLength: rawContext.prefixLength,
        gateway: rawContext.gateway,
        scannedNetwork: _intToIpv4(scanPlan.networkAddress),
        scannedPrefixLength: scanPlan.prefixLength,
        coverageLimited: scanPlan.coverageLimited,
      ),
      devices: devices,
      limitations: [
        if (scanPlan.coverageLimited) '네트워크가 넓어 현재 주소가 속한 /24 범위만 검색했습니다.',
        '절전, 방화벽, AP 격리 또는 다른 VLAN의 장비는 탐지되지 않을 수 있습니다.',
        '이번 검색은 Windows 이웃 테이블과 제한된 ICMP 탐색을 사용했습니다.',
        '같은 게이트웨이와 서브넷을 공유하는 SSID는 장비 목록이 겹칠 수 있습니다.',
      ],
      duration: stopwatch.elapsed,
    );
  }

  Future<WindowsNetworkContextCandidate> _readPrimaryNetworkContext() async {
    const script = r'''
$items = @(
  Get-NetIPConfiguration | Where-Object {
    $_.NetAdapter.Status -eq 'Up' -and $_.IPv4Address
  } | ForEach-Object {
    $address = $_.IPv4Address |
      Where-Object { $_.IPAddress -notlike '169.254.*' } |
      Select-Object -First 1
    if ($null -ne $address) {
      $gateway = $null
      if ($null -ne $_.IPv4DefaultGateway) {
        $gateway = $_.IPv4DefaultGateway.NextHop
      }
      [PSCustomObject]@{
        interfaceName = $_.InterfaceAlias
        interfaceIndex = $_.InterfaceIndex
        ipv4Address = $address.IPAddress
        prefixLength = $address.PrefixLength
        gateway = $gateway
        isWireless = ([int]$_.NetAdapter.NdisPhysicalMedium -eq 9)
      }
    }
  }
)
ConvertTo-Json -InputObject $items -Compress
''';
    final decoded = await _runPowerShellJson(script);
    final items = _asObjectList(decoded);
    final candidates = items
        .map(WindowsNetworkContextCandidate.fromJson)
        .where((item) => _isPrivateIpv4(item.ipv4Address))
        .toList();
    if (candidates.isEmpty) {
      throw const DiscoveryUnavailableException(
        '검색 가능한 활성 Wi-Fi IPv4 네트워크를 찾지 못했습니다.',
      );
    }

    return selectWirelessNetworkContext(candidates);
  }

  static WindowsNetworkContextCandidate selectWirelessNetworkContext(
    List<WindowsNetworkContextCandidate> candidates,
  ) {
    for (final candidate in candidates) {
      if (candidate.isWireless && candidate.gateway.isNotEmpty) {
        return candidate;
      }
    }
    for (final candidate in candidates) {
      if (candidate.isWireless) return candidate;
    }
    throw const DiscoveryUnavailableException(
      '활성 Wi-Fi 연결을 찾지 못했습니다. Wi-Fi에 연결한 뒤 다시 시도하세요.',
    );
  }

  Future<void> _probeTargets(
    List<String> targets, {
    required DiscoveryCancellationToken cancellationToken,
    required void Function(DiscoveryProgress progress) onProgress,
  }) async {
    var nextIndex = 0;
    var completed = 0;

    Future<void> worker() async {
      while (!cancellationToken.isCancelled) {
        final index = nextIndex;
        if (index >= targets.length) return;
        nextIndex += 1;

        await Process.run('ping.exe', [
          '-4',
          '-n',
          '1',
          '-w',
          pingTimeoutMilliseconds.toString(),
          targets[index],
        ]);
        completed += 1;
        if (completed == targets.length || completed % 4 == 0) {
          onProgress(
            DiscoveryProgress(
              stage: DiscoveryStage.probing,
              completed: completed,
              total: targets.length,
            ),
          );
        }
      }
    }

    final workerCount = min(maxConcurrentProbes, targets.length);
    await Future.wait(List.generate(workerCount, (_) => worker()));
    _throwIfCancelled(cancellationToken);
  }

  Future<List<_NeighborRecord>> _readNeighbors({
    required int interfaceIndex,
    required _ScanPlan scanPlan,
  }) async {
    final script =
        '''
\$items = @(Get-NetNeighbor -InterfaceIndex $interfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { \$_.State -notin @('Unreachable', 'Incomplete') } |
  Select-Object IPAddress, LinkLayerAddress, State)
ConvertTo-Json -InputObject \$items -Compress
''';
    final decoded = await _runPowerShellJson(script);
    final seen = <String>{};
    final neighbors = <_NeighborRecord>[];
    for (final item in _asObjectList(decoded)) {
      final ipAddress = item['IPAddress']?.toString() ?? '';
      final ipValue = _tryParseIpv4(ipAddress);
      if (ipValue == null ||
          !_isHostInPlan(ipValue, scanPlan) ||
          !seen.add(ipAddress)) {
        continue;
      }
      final macAddress = _normalizeMacAddress(
        item['LinkLayerAddress']?.toString(),
      );
      if (macAddress == null) continue;
      neighbors.add(
        _NeighborRecord(ipAddress: ipAddress, macAddress: macAddress),
      );
    }
    return neighbors;
  }

  Future<Object?> _runPowerShellJson(String script) async {
    final result = await Process.run('powershell.exe', [
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      script,
    ]);
    if (result.exitCode != 0) {
      throw const DiscoveryUnavailableException(
        'Windows 네트워크 정보를 읽는 중 오류가 발생했습니다.',
      );
    }
    final output = result.stdout.toString().trim();
    if (output.isEmpty) return const <Object?>[];
    try {
      return jsonDecode(output);
    } on FormatException {
      throw const DiscoveryUnavailableException(
        'Windows 네트워크 정보 형식을 해석하지 못했습니다.',
      );
    }
  }

  static _ScanPlan _createScanPlan(WindowsNetworkContextCandidate context) {
    final localAddress = _parseIpv4(context.ipv4Address);
    var prefixLength = context.prefixLength.clamp(0, 32);
    var coverageLimited = false;
    if (prefixLength < 24) {
      prefixLength = 24;
      coverageLimited = true;
    }
    if (prefixLength >= 31) {
      final gateway = _tryParseIpv4(context.gateway);
      return _ScanPlan(
        networkAddress: localAddress,
        prefixLength: 32,
        localAddress: localAddress,
        targets: gateway == null || gateway == localAddress
            ? const []
            : [_intToIpv4(gateway)],
        coverageLimited: coverageLimited,
      );
    }

    final mask = (0xffffffff << (32 - prefixLength)) & 0xffffffff;
    final networkAddress = localAddress & mask;
    final broadcastAddress = networkAddress | (~mask & 0xffffffff);
    final targets = <String>[];
    for (var value = networkAddress + 1; value < broadcastAddress; value++) {
      if (value != localAddress) targets.add(_intToIpv4(value));
    }
    return _ScanPlan(
      networkAddress: networkAddress,
      prefixLength: prefixLength,
      localAddress: localAddress,
      targets: targets.take(254).toList(growable: false),
      coverageLimited: coverageLimited || targets.length > 254,
    );
  }

  static List<Map<String, Object?>> _asObjectList(Object? decoded) {
    if (decoded is Map<String, dynamic>) {
      return [decoded.cast<String, Object?>()];
    }
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList();
    }
    return const [];
  }

  static bool _isHostInPlan(int address, _ScanPlan plan) {
    if (plan.prefixLength == 32) {
      return address == _tryParseIpv4List(plan.targets);
    }
    final mask = (0xffffffff << (32 - plan.prefixLength)) & 0xffffffff;
    return address != plan.localAddress &&
        (address & mask) == plan.networkAddress;
  }

  static int? _tryParseIpv4List(List<String> addresses) {
    if (addresses.isEmpty) return null;
    return _tryParseIpv4(addresses.first);
  }

  static bool _isPrivateIpv4(String address) {
    final value = _tryParseIpv4(address);
    if (value == null) return false;
    final first = (value >> 24) & 0xff;
    final second = (value >> 16) & 0xff;
    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }

  static int _parseIpv4(String address) {
    final value = _tryParseIpv4(address);
    if (value == null) {
      throw const DiscoveryUnavailableException('현재 네트워크의 IPv4 주소가 올바르지 않습니다.');
    }
    return value;
  }

  static int? _tryParseIpv4(String address) {
    final parts = address.split('.');
    if (parts.length != 4) return null;
    var value = 0;
    for (final part in parts) {
      final byte = int.tryParse(part);
      if (byte == null || byte < 0 || byte > 255) return null;
      value = (value << 8) | byte;
    }
    return value;
  }

  static String _intToIpv4(int value) => [
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff,
  ].join('.');

  static String? _normalizeMacAddress(String? raw) {
    if (raw == null) return null;
    final compact = raw.replaceAll(RegExp('[^0-9A-Fa-f]'), '').toUpperCase();
    if (compact.length != 12 ||
        compact == '000000000000' ||
        compact == 'FFFFFFFFFFFF' ||
        compact.startsWith('01005E')) {
      return null;
    }
    return List.generate(
      6,
      (index) => compact.substring(index * 2, index * 2 + 2),
    ).join(':');
  }

  static int _compareDevices(NetworkDevice left, NetworkDevice right) {
    final leftRank = left.category == DeviceCategory.router
        ? 0
        : left.sources.contains(DiscoverySource.localInterface)
        ? 1
        : 2;
    final rightRank = right.category == DeviceCategory.router
        ? 0
        : right.sources.contains(DiscoverySource.localInterface)
        ? 1
        : 2;
    if (leftRank != rightRank) return leftRank.compareTo(rightRank);
    final leftIp = _tryParseIpv4(left.ipAddresses.first) ?? 0;
    final rightIp = _tryParseIpv4(right.ipAddresses.first) ?? 0;
    return leftIp.compareTo(rightIp);
  }

  static void _throwIfCancelled(DiscoveryCancellationToken token) {
    if (token.isCancelled) throw const DiscoveryCancelledException();
  }
}

class WindowsNetworkContextCandidate {
  const WindowsNetworkContextCandidate({
    required this.interfaceName,
    required this.interfaceIndex,
    required this.ipv4Address,
    required this.prefixLength,
    required this.gateway,
    required this.isWireless,
  });

  factory WindowsNetworkContextCandidate.fromJson(Map<String, Object?> json) {
    return WindowsNetworkContextCandidate(
      interfaceName: json['interfaceName']?.toString() ?? '',
      interfaceIndex: int.tryParse(json['interfaceIndex'].toString()) ?? -1,
      ipv4Address: json['ipv4Address']?.toString() ?? '',
      prefixLength: int.tryParse(json['prefixLength'].toString()) ?? 24,
      gateway: json['gateway']?.toString() ?? '',
      isWireless: json['isWireless'] == true,
    );
  }

  final String interfaceName;
  final int interfaceIndex;
  final String ipv4Address;
  final int prefixLength;
  final String gateway;
  final bool isWireless;
}

class _ScanPlan {
  const _ScanPlan({
    required this.networkAddress,
    required this.prefixLength,
    required this.localAddress,
    required this.targets,
    required this.coverageLimited,
  });

  final int networkAddress;
  final int prefixLength;
  final int localAddress;
  final List<String> targets;
  final bool coverageLimited;
}

class _NeighborRecord {
  const _NeighborRecord({required this.ipAddress, required this.macAddress});

  final String ipAddress;
  final String? macAddress;
}
