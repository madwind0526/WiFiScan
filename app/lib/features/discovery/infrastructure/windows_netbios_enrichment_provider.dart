import 'dart:async';
import 'dart:io';

import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/application/network_information_enricher.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';

typedef NetbiosCommandRunner =
    Future<ProcessResult> Function(String address, Duration timeout);

class WindowsNetbiosEnrichmentProvider implements NetworkEnrichmentProvider {
  const WindowsNetbiosEnrichmentProvider({
    this.runner,
    this.timeout = const Duration(milliseconds: 850),
    this.maxTargets = 40,
    this.maxConcurrentQueries = 8,
  });

  final NetbiosCommandRunner? runner;
  final Duration timeout;
  final int maxTargets;
  final int maxConcurrentQueries;

  @override
  Future<List<DeviceEnrichment>> collect({
    required Set<String> targetAddresses,
    required DiscoveryCancellationToken cancellationToken,
  }) async {
    final targets = targetAddresses
        .where(_isPrivateIpv4)
        .take(maxTargets)
        .toList(growable: false);
    final results = <DeviceEnrichment>[];
    var nextIndex = 0;

    Future<void> worker() async {
      while (!cancellationToken.isCancelled) {
        final index = nextIndex++;
        if (index >= targets.length) return;
        final address = targets[index];
        try {
          final process = await (runner ?? _runNbtstat)(address, timeout);
          if (process.exitCode != 0) continue;
          final identity = parseNetbiosNameTable(process.stdout.toString());
          if (identity == null) continue;
          results.add(
            DeviceEnrichment(
              ipAddress: address,
              displayName: identity.name,
              category: identity.hasServerService
                  ? DeviceCategory.computer
                  : null,
              hostnames: [identity.name],
              services: const [
                NetworkServiceObservation(
                  protocol: 'netbios-ns',
                  port: 137,
                  transport: NetworkTransport.udp,
                  source: DiscoverySource.netbios,
                ),
              ],
              sources: const [DiscoverySource.netbios],
            ),
          );
        } catch (_) {
          continue;
        }
      }
    }

    final workerCount = targets.length < maxConcurrentQueries
        ? targets.length
        : maxConcurrentQueries;
    await Future.wait([
      for (var index = 0; index < workerCount; index++) worker(),
    ]);
    return results;
  }

  Future<ProcessResult> _runNbtstat(String address, Duration timeout) async {
    final process = await Process.start('nbtstat', ['/A', address]);
    final stdoutFuture = process.stdout
        .transform(systemEncoding.decoder)
        .join();
    final stderrFuture = process.stderr
        .transform(systemEncoding.decoder)
        .join();
    var timedOut = false;
    final exitCode = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        timedOut = true;
        process.kill();
        return -1;
      },
    );
    final output = await stdoutFuture;
    final error = await stderrFuture;
    return ProcessResult(process.pid, timedOut ? -1 : exitCode, output, error);
  }

  static NetbiosIdentity? parseNetbiosNameTable(String output) {
    final entries = <(String, String)>[];
    final pattern = RegExp(
      r'^\s*([^\r\n<]{1,15}?)\s+<([0-9A-Fa-f]{2})>',
      multiLine: true,
    );
    for (final match in pattern.allMatches(output)) {
      final name = match.group(1)?.trim();
      final suffix = match.group(2)?.toUpperCase();
      if (name == null || name.isEmpty || suffix == null) continue;
      if (name == '__MSBROWSE__' || name == '*') continue;
      entries.add((name, suffix));
    }
    if (entries.isEmpty) return null;

    final server = entries.where((entry) => entry.$2 == '20').firstOrNull;
    final workstation = entries.where((entry) => entry.$2 == '00').firstOrNull;
    final selected = server ?? workstation;
    if (selected == null) return null;
    return NetbiosIdentity(name: selected.$1, hasServerService: server != null);
  }

  static bool _isPrivateIpv4(String address) {
    final parts = address.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    return parts[0] == 10 ||
        (parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31) ||
        (parts[0] == 192 && parts[1] == 168);
  }
}

class NetbiosIdentity {
  const NetbiosIdentity({required this.name, required this.hasServerService});

  final String name;
  final bool hasServerService;
}
