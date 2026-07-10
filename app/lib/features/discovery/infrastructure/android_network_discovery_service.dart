import 'dart:io';

import 'package:flutter/services.dart';
import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/domain/discovery_result.dart';
import 'package:wifi_scan/features/discovery/domain/network_context.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';

class AndroidNetworkPermissionService {
  const AndroidNetworkPermissionService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.wifiscan/network');

  final MethodChannel _channel;

  Future<AndroidPermissionStatus> requestPermission() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'requestPermission',
    );
    return AndroidPermissionStatus.fromMap(result);
  }
}

class AndroidPermissionStatus {
  const AndroidPermissionStatus({required this.granted, required this.name});

  factory AndroidPermissionStatus.fromMap(Map<String, Object?>? map) {
    return AndroidPermissionStatus(
      granted: map?['granted'] == true,
      name: map?['permission']?.toString() ?? 'unknown',
    );
  }

  final bool granted;
  final String name;
}

class AndroidNetworkDiscoveryService implements NetworkDiscoveryService {
  const AndroidNetworkDiscoveryService({
    MethodChannel? channel,
    AndroidNetworkPermissionService? permissionService,
  }) : _channel = channel ?? const MethodChannel('com.wifiscan/network'),
       _permissionService =
           permissionService ?? const AndroidNetworkPermissionService();

  final MethodChannel _channel;
  final AndroidNetworkPermissionService _permissionService;

  @override
  Future<DiscoveryResult> discover({
    required DiscoveryCancellationToken cancellationToken,
    required void Function(DiscoveryProgress progress) onProgress,
  }) async {
    if (!Platform.isAndroid) {
      throw const DiscoveryUnavailableException(
        'Android 네트워크 탐색은 Android에서만 사용할 수 있습니다.',
      );
    }

    final stopwatch = Stopwatch()..start();
    onProgress(
      const DiscoveryProgress(
        stage: DiscoveryStage.preparing,
        completed: 0,
        total: 0,
      ),
    );
    final permission = await _permissionService.requestPermission();
    if (!permission.granted) {
      throw const DiscoveryUnavailableException(
        '로컬 네트워크 권한이 필요합니다. 권한을 허용한 뒤 다시 시도하세요.',
      );
    }
    _throwIfCancelled(cancellationToken);

    final rawContext = await _channel.invokeMapMethod<String, Object?>(
      'networkContext',
    );
    if (rawContext == null) {
      throw const DiscoveryUnavailableException(
        '현재 연결된 사설 Wi-Fi 네트워크를 찾지 못했습니다.',
      );
    }
    final context = _contextFrom(rawContext);
    final targetCount = context.scannedPrefixLength >= 31 ? 1 : 254;
    onProgress(
      DiscoveryProgress(
        stage: DiscoveryStage.probing,
        completed: 0,
        total: targetCount,
      ),
    );

    final rawHosts = await _channel
        .invokeMethod<List<Object?>>('discoverHosts', {
          'network': context.scannedNetwork,
          'prefixLength': context.scannedPrefixLength,
          'timeoutMilliseconds': 250,
        });
    _throwIfCancelled(cancellationToken);
    final hosts = rawHosts?.whereType<String>().toSet() ?? <String>{};
    onProgress(
      DiscoveryProgress(
        stage: DiscoveryStage.collecting,
        completed: targetCount,
        total: targetCount,
      ),
    );

    final now = DateTime.now();
    final devices = <NetworkDevice>[
      NetworkDevice(
        id: 'local:${context.ipv4Address}',
        displayName: '이 Android 휴대폰',
        category: DeviceCategory.phone,
        ownershipStatus: OwnershipStatus.confirmed,
        ipAddresses: [context.ipv4Address],
        sources: const [DiscoverySource.localInterface],
        firstSeenAt: now,
        lastSeenAt: now,
        identityConfidence: 1,
      ),
      if (context.gateway.isNotEmpty)
        NetworkDevice(
          id: 'ip:${context.gateway}',
          displayName: '기본 게이트웨이',
          category: DeviceCategory.router,
          ownershipStatus: OwnershipStatus.unconfirmed,
          ipAddresses: [context.gateway],
          sources: const [DiscoverySource.router, DiscoverySource.subnet],
          firstSeenAt: now,
          lastSeenAt: now,
          identityConfidence: 0.7,
        ),
      ...hosts
          .where(
            (host) => host != context.ipv4Address && host != context.gateway,
          )
          .map(
            (host) => NetworkDevice(
              id: 'ip:$host',
              displayName: '확인되지 않은 장비',
              category: DeviceCategory.unknown,
              ownershipStatus: OwnershipStatus.unconfirmed,
              ipAddresses: [host],
              sources: const [DiscoverySource.subnet],
              firstSeenAt: now,
              lastSeenAt: now,
              identityConfidence: 0.55,
            ),
          ),
    ];
    stopwatch.stop();
    onProgress(
      DiscoveryProgress(
        stage: DiscoveryStage.complete,
        completed: targetCount,
        total: targetCount,
      ),
    );

    return DiscoveryResult(
      context: context,
      devices: devices,
      limitations: [
        'Android 탐색은 응답 가능한 호스트만 확인하며 MAC 주소를 제공하지 않을 수 있습니다.',
        '절전, 방화벽, AP 격리 또는 다른 VLAN의 장비는 탐지되지 않을 수 있습니다.',
        if (context.coverageLimited) '현재 주소가 속한 최대 /24 범위로 검색을 제한했습니다.',
      ],
      duration: stopwatch.elapsed,
    );
  }

  static NetworkContext _contextFrom(Map<String, Object?> raw) {
    final ipv4 = raw['ipv4Address']?.toString() ?? '';
    final prefix = (raw['prefixLength'] as num?)?.toInt() ?? 24;
    final scannedPrefix = (raw['scannedPrefixLength'] as num?)?.toInt() ?? 24;
    return NetworkContext(
      interfaceName: raw['interfaceName']?.toString() ?? 'Wi-Fi',
      interfaceIndex: -1,
      ipv4Address: ipv4,
      prefixLength: prefix,
      gateway: raw['gateway']?.toString() ?? '',
      scannedNetwork: raw['scannedNetwork']?.toString() ?? ipv4,
      scannedPrefixLength: scannedPrefix,
      coverageLimited: prefix < scannedPrefix,
    );
  }

  static void _throwIfCancelled(DiscoveryCancellationToken token) {
    if (token.isCancelled) throw const DiscoveryCancelledException();
  }
}
