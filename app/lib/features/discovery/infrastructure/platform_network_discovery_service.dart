import 'dart:io';

import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/application/network_information_enricher.dart';
import 'package:wifi_scan/features/discovery/infrastructure/android_network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/domain/discovery_result.dart';
import 'package:wifi_scan/features/discovery/infrastructure/enriched_network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/infrastructure/mdns_enrichment_provider.dart';
import 'package:wifi_scan/features/discovery/infrastructure/reverse_dns_enrichment_provider.dart';
import 'package:wifi_scan/features/discovery/infrastructure/ssdp_enrichment_provider.dart';
import 'package:wifi_scan/features/discovery/infrastructure/tcp_service_probe_provider.dart';
import 'package:wifi_scan/features/discovery/infrastructure/windows_netbios_enrichment_provider.dart';
import 'package:wifi_scan/features/discovery/infrastructure/windows_network_discovery_service.dart';

NetworkDiscoveryService createNetworkDiscoveryService() {
  NetworkDiscoveryService? delegate;
  if (Platform.isWindows) {
    delegate = const WindowsNetworkDiscoveryService();
  }
  if (Platform.isAndroid) {
    delegate = const AndroidNetworkDiscoveryService();
  }
  if (delegate == null) return const _UnsupportedNetworkDiscoveryService();
  return EnrichedNetworkDiscoveryService(
    delegate: delegate,
    enrichmentLease: Platform.isAndroid
        ? const AndroidMulticastEnrichmentLease()
        : const NetworkEnrichmentLease(),
    enricher: NetworkInformationEnricher(
      providers: [
        const ReverseDnsEnrichmentProvider(),
        const MdnsEnrichmentProvider(),
        const SsdpEnrichmentProvider(),
        const TcpServiceProbeProvider(),
        if (Platform.isWindows) const WindowsNetbiosEnrichmentProvider(),
      ],
    ),
  );
}

class _UnsupportedNetworkDiscoveryService implements NetworkDiscoveryService {
  const _UnsupportedNetworkDiscoveryService();

  @override
  Future<DiscoveryResult> discover({
    required DiscoveryCancellationToken cancellationToken,
    required void Function(DiscoveryProgress progress) onProgress,
  }) {
    throw const DiscoveryUnavailableException(
      '이 플랫폼의 네트워크 탐색 기능은 아직 준비되지 않았습니다.',
    );
  }
}
