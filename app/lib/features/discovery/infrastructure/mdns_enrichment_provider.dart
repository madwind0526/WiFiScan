import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';
import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/application/network_information_enricher.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';

class MdnsEnrichmentProvider implements NetworkEnrichmentProvider {
  const MdnsEnrichmentProvider({
    this.queryTimeout = const Duration(milliseconds: 700),
    this.maxInstances = 32,
    this.maxServiceTypes = 40,
    this.maxConcurrentResolutions = 8,
  });

  static const _serviceTypes = {
    '_workstation._tcp.local',
    '_device-info._tcp.local',
    '_http._tcp.local',
    '_https._tcp.local',
    '_ssh._tcp.local',
    '_smb._tcp.local',
    '_ipp._tcp.local',
    '_printer._tcp.local',
    '_googlecast._tcp.local',
    '_airplay._tcp.local',
    '_raop._tcp.local',
    '_hap._tcp.local',
    '_homekit._tcp.local',
  };

  final Duration queryTimeout;
  final int maxInstances;
  final int maxServiceTypes;
  final int maxConcurrentResolutions;

  @override
  Future<List<DeviceEnrichment>> collect({
    required Set<String> targetAddresses,
    required DiscoveryCancellationToken cancellationToken,
  }) async {
    final client = MDnsClient(rawDatagramSocketFactory: _bindDatagramSocket);
    try {
      await client.start(
        interfacesFactory: _privateIpv4Interfaces,
        onError: (_) {},
      );
      final advertisedTypes = await client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer('_services._dns-sd._udp.local'),
            timeout: queryTimeout,
          )
          .map((record) => _normalizeServiceType(record.domainName))
          .where((value) => value != null)
          .map((value) => value!)
          .toList();
      final serviceTypes = {
        ..._serviceTypes,
        ...advertisedTypes,
      }.take(maxServiceTypes).toList(growable: false);
      final pointerBatches = await Future.wait([
        for (final serviceType in serviceTypes)
          client
              .lookup<PtrResourceRecord>(
                ResourceRecordQuery.serverPointer(serviceType),
                timeout: queryTimeout,
              )
              .toList(),
      ]);
      final pointers = <String, (PtrResourceRecord, String)>{};
      var serviceIndex = 0;
      for (final batch in pointerBatches) {
        final serviceType = serviceTypes[serviceIndex++];
        for (final pointer in batch) {
          pointers[pointer.domainName] = (pointer, serviceType);
        }
      }

      final results = <DeviceEnrichment>[];
      final instances = pointers.values.take(maxInstances).toList();
      var nextIndex = 0;
      Future<void> worker() async {
        while (!cancellationToken.isCancelled) {
          final index = nextIndex++;
          if (index >= instances.length) return;
          final entry = instances[index];
          results.addAll(
            await _resolveInstance(
              client,
              domainName: entry.$1.domainName,
              serviceType: entry.$2,
              targetAddresses: targetAddresses,
            ),
          );
        }
      }

      final workerCount = instances.length < maxConcurrentResolutions
          ? instances.length
          : maxConcurrentResolutions;
      await Future.wait([
        for (var index = 0; index < workerCount; index++) worker(),
      ]);
      return results;
    } finally {
      client.stop();
    }
  }

  Future<RawDatagramSocket> _bindDatagramSocket(
    dynamic host,
    int port, {
    bool reuseAddress = true,
    bool reusePort = false,
    int ttl = 1,
  }) {
    return RawDatagramSocket.bind(
      host,
      port,
      reuseAddress: reuseAddress,
      reusePort: Platform.isWindows ? false : reusePort,
      ttl: ttl,
    );
  }

  Future<List<DeviceEnrichment>> _resolveInstance(
    MDnsClient client, {
    required String domainName,
    required String serviceType,
    required Set<String> targetAddresses,
  }) async {
    final servicesFuture = client
        .lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(domainName),
          timeout: queryTimeout,
        )
        .toList();
    final textsFuture = client
        .lookup<TxtResourceRecord>(
          ResourceRecordQuery.text(domainName),
          timeout: queryTimeout,
        )
        .toList();
    final services = await servicesFuture;
    final texts = await textsFuture;
    final results = <DeviceEnrichment>[];
    for (final service in services) {
      final addresses = await client
          .lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(service.target),
            timeout: queryTimeout,
          )
          .map((record) => record.address.address)
          .where(targetAddresses.contains)
          .toList();
      final instanceName = domainName
          .replaceFirst(
            RegExp('[.]${RegExp.escape(serviceType)}[.]?${r'$'}'),
            '',
          )
          .replaceAll(r'\032', ' ');
      final txt = texts.map((record) => record.text).join(' ');
      for (final address in addresses) {
        results.add(
          DeviceEnrichment(
            ipAddress: address,
            displayName: instanceName,
            modelName: _txtValue(txt, const ['md', 'model', 'ty']),
            category: _categoryFor(serviceType),
            hostnames: [service.target.replaceFirst(RegExp(r'\.$'), '')],
            services: [
              NetworkServiceObservation(
                protocol: _protocolFor(serviceType),
                port: service.port,
                transport: serviceType.contains('._udp.')
                    ? NetworkTransport.udp
                    : NetworkTransport.tcp,
                source: DiscoverySource.mdns,
                product: _txtValue(txt, const ['product', 'fn']),
              ),
            ],
            sources: const [DiscoverySource.mdns],
          ),
        );
      }
    }
    return results;
  }

  Future<Iterable<NetworkInterface>> _privateIpv4Interfaces(
    InternetAddressType type,
  ) async {
    final interfaces = await NetworkInterface.list(
      includeLinkLocal: false,
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    return interfaces.where(
      (interface) =>
          interface.addresses.any((address) => _isPrivateIpv4(address.address)),
    );
  }

  bool _isPrivateIpv4(String address) {
    final parts = address.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    return parts[0] == 10 ||
        (parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31) ||
        (parts[0] == 192 && parts[1] == 168);
  }

  String _protocolFor(String serviceType) {
    return serviceType.split('._').first.replaceFirst('_', '');
  }

  DeviceCategory? _categoryFor(String serviceType) {
    final value = serviceType.toLowerCase();
    if (value.contains('ipp') || value.contains('printer')) {
      return DeviceCategory.printer;
    }
    if (value.contains('googlecast') ||
        value.contains('airplay') ||
        value.contains('androidtv') ||
        value.contains('roku') ||
        value.contains('dial')) {
      return DeviceCategory.television;
    }
    if (value.contains('raop') ||
        value.contains('sonos') ||
        value.contains('spotify')) {
      return DeviceCategory.speaker;
    }
    if (value.contains('hap') ||
        value.contains('homekit') ||
        value.contains('matter') ||
        value.contains('miio') ||
        value.contains('ewelink') ||
        value.contains('smartthings')) {
      return DeviceCategory.iot;
    }
    if (value.contains('workstation') ||
        value.contains('smb') ||
        value.contains('rdp')) {
      return DeviceCategory.computer;
    }
    if (value.contains('camera') || value.contains('rtsp')) {
      return DeviceCategory.camera;
    }
    if (value.contains('mobdev') || value.contains('iphone')) {
      return DeviceCategory.phone;
    }
    return null;
  }

  String? _normalizeServiceType(String value) {
    final normalized = value.replaceFirst(RegExp(r'\.$'), '').toLowerCase();
    final valid = RegExp(
      r'^_[a-z0-9-]+\._(?:tcp|udp)\.local$',
    ).hasMatch(normalized);
    return valid ? normalized : null;
  }

  String? _txtValue(String text, List<String> keys) {
    for (final key in keys) {
      final match = RegExp(
        '(?:^|[\\s,\\[])${RegExp.escape(key)}=([^,\\]\\s]+)',
        caseSensitive: false,
      ).firstMatch(text);
      final value = match?.group(1)?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}
