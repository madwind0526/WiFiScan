import 'package:flutter/services.dart';
import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/application/network_information_enricher.dart';
import 'package:wifi_scan/features/discovery/domain/discovery_result.dart';

class EnrichedNetworkDiscoveryService implements NetworkDiscoveryService {
  const EnrichedNetworkDiscoveryService({
    required this.delegate,
    required this.enricher,
    this.enrichmentLease = const NetworkEnrichmentLease(),
  });

  final NetworkDiscoveryService delegate;
  final NetworkInformationEnricher enricher;
  final NetworkEnrichmentLease enrichmentLease;

  @override
  Future<DiscoveryResult> discover({
    required DiscoveryCancellationToken cancellationToken,
    required void Function(DiscoveryProgress progress) onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();
    final result = await delegate.discover(
      cancellationToken: cancellationToken,
      onProgress: (progress) {
        if (progress.stage != DiscoveryStage.complete) onProgress(progress);
      },
    );
    onProgress(
      const DiscoveryProgress(
        stage: DiscoveryStage.collecting,
        completed: 0,
        total: 0,
      ),
    );
    await enrichmentLease.acquire();
    late final DiscoveryResult enriched;
    try {
      enriched = await enricher.enrich(
        result,
        cancellationToken: cancellationToken,
      );
    } finally {
      await enrichmentLease.release();
    }
    onProgress(
      const DiscoveryProgress(
        stage: DiscoveryStage.complete,
        completed: 0,
        total: 0,
      ),
    );
    stopwatch.stop();
    return DiscoveryResult(
      context: enriched.context,
      devices: enriched.devices,
      limitations: enriched.limitations,
      duration: stopwatch.elapsed,
    );
  }
}

class NetworkEnrichmentLease {
  const NetworkEnrichmentLease();

  Future<void> acquire() async {}

  Future<void> release() async {}
}

class AndroidMulticastEnrichmentLease extends NetworkEnrichmentLease {
  const AndroidMulticastEnrichmentLease({
    this.channel = const MethodChannel('com.wifiscan/network'),
  });

  final MethodChannel channel;

  @override
  Future<void> acquire() async {
    try {
      await channel.invokeMethod<bool>('acquireMulticastLock');
    } catch (_) {
      // Enrichment can continue without an optional multicast lock.
    }
  }

  @override
  Future<void> release() async {
    try {
      await channel.invokeMethod<bool>('releaseMulticastLock');
    } catch (_) {
      // Cleanup is best effort.
    }
  }
}
