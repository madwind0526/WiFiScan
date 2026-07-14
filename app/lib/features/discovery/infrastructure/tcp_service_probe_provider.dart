import 'dart:io';

import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/application/network_information_enricher.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';

typedef TcpPortConnector =
    Future<bool> Function(String address, int port, Duration timeout);

class TcpServiceProbeProvider implements NetworkEnrichmentProvider {
  const TcpServiceProbeProvider({
    this.connector,
    this.timeout = const Duration(milliseconds: 220),
    this.maxTargets = 64,
    this.maxConcurrentProbes = 32,
    this.ports = const {
      21: 'ftp',
      22: 'ssh',
      23: 'telnet',
      53: 'dns',
      80: 'http',
      443: 'https',
      445: 'smb',
      554: 'rtsp',
      631: 'ipp',
      1883: 'mqtt',
      8008: 'http-alt',
      8009: 'cast',
      8080: 'http-alt',
      8443: 'https-alt',
      9100: 'printer',
    },
  });

  final TcpPortConnector? connector;
  final Duration timeout;
  final int maxTargets;
  final int maxConcurrentProbes;
  final Map<int, String> ports;

  @override
  Future<List<DeviceEnrichment>> collect({
    required Set<String> targetAddresses,
    required DiscoveryCancellationToken cancellationToken,
  }) async {
    final targets = targetAddresses.take(maxTargets).toList();
    final tasks = <(String, int)>[
      for (final address in targets)
        for (final port in ports.keys) (address, port),
    ];
    final openByAddress = <String, List<NetworkServiceObservation>>{};
    var nextIndex = 0;

    Future<void> worker() async {
      while (!cancellationToken.isCancelled) {
        final index = nextIndex++;
        if (index >= tasks.length) return;
        final task = tasks[index];
        try {
          final open = await (connector ?? _connect)(task.$1, task.$2, timeout);
          if (!open) continue;
          openByAddress
              .putIfAbsent(task.$1, () => [])
              .add(
                NetworkServiceObservation(
                  protocol: ports[task.$2]!,
                  port: task.$2,
                  transport: NetworkTransport.tcp,
                  source: DiscoverySource.serviceProbe,
                ),
              );
        } catch (_) {
          continue;
        }
      }
    }

    final workerCount = tasks.length < maxConcurrentProbes
        ? tasks.length
        : maxConcurrentProbes;
    await Future.wait([
      for (var index = 0; index < workerCount; index++) worker(),
    ]);
    return [
      for (final entry in openByAddress.entries)
        DeviceEnrichment(
          ipAddress: entry.key,
          category: _categoryFrom(entry.value),
          services: entry.value,
          sources: const [DiscoverySource.serviceProbe],
        ),
    ];
  }

  Future<bool> _connect(String address, int port, Duration timeout) async {
    final socket = await Socket.connect(address, port, timeout: timeout);
    socket.destroy();
    return true;
  }

  DeviceCategory? _categoryFrom(List<NetworkServiceObservation> services) {
    final ports = services.map((service) => service.port).toSet();
    if (ports.contains(631) || ports.contains(9100)) {
      return DeviceCategory.printer;
    }
    if (ports.contains(554)) return DeviceCategory.camera;
    return null;
  }
}
