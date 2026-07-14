import 'dart:io';

import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/application/network_information_enricher.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';

typedef ReverseDnsLookup = Future<String?> Function(String address);

class ReverseDnsEnrichmentProvider implements NetworkEnrichmentProvider {
  const ReverseDnsEnrichmentProvider({
    this.lookup,
    this.timeout = const Duration(milliseconds: 600),
    this.maxTargets = 64,
    this.maxConcurrentLookups = 16,
  });

  final ReverseDnsLookup? lookup;
  final Duration timeout;
  final int maxTargets;
  final int maxConcurrentLookups;

  @override
  Future<List<DeviceEnrichment>> collect({
    required Set<String> targetAddresses,
    required DiscoveryCancellationToken cancellationToken,
  }) async {
    final targets = targetAddresses.take(maxTargets).toList();
    final results = <DeviceEnrichment>[];
    var nextIndex = 0;

    Future<void> worker() async {
      while (!cancellationToken.isCancelled) {
        final index = nextIndex++;
        if (index >= targets.length) return;
        final address = targets[index];
        try {
          final hostname = await (lookup ?? _lookup)(address).timeout(timeout);
          final cleaned = _cleanHostname(hostname);
          if (cleaned != null && cleaned != address) {
            results.add(
              DeviceEnrichment(
                ipAddress: address,
                displayName: cleaned,
                hostnames: [cleaned],
                sources: const [DiscoverySource.reverseDns],
              ),
            );
          }
        } catch (_) {
          continue;
        }
      }
    }

    final workerCount = targets.length < maxConcurrentLookups
        ? targets.length
        : maxConcurrentLookups;
    await Future.wait([
      for (var index = 0; index < workerCount; index++) worker(),
    ]);
    return results;
  }

  Future<String?> _lookup(String address) async {
    final resolved = await InternetAddress(address).reverse();
    return resolved.host;
  }

  String? _cleanHostname(String? value) {
    final trimmed = value?.trim().replaceFirst(RegExp(r'\.$'), '');
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
