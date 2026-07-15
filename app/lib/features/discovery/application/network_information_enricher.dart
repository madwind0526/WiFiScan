import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/domain/discovery_result.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';

abstract interface class NetworkEnrichmentProvider {
  Future<List<DeviceEnrichment>> collect({
    required Set<String> targetAddresses,
    required DiscoveryCancellationToken cancellationToken,
  });
}

class DeviceEnrichment {
  const DeviceEnrichment({
    required this.ipAddress,
    this.displayName,
    this.vendor,
    this.modelName,
    this.description,
    this.category,
    this.hostnames = const [],
    this.services = const [],
    this.sources = const [],
  });

  final String ipAddress;
  final String? displayName;
  final String? vendor;
  final String? modelName;
  final String? description;
  final DeviceCategory? category;
  final List<String> hostnames;
  final List<NetworkServiceObservation> services;
  final List<DiscoverySource> sources;
}

class NetworkInformationEnricher {
  const NetworkInformationEnricher({required this.providers});

  final List<NetworkEnrichmentProvider> providers;

  Future<DiscoveryResult> enrich(
    DiscoveryResult result, {
    required DiscoveryCancellationToken cancellationToken,
  }) async {
    final targetAddresses = {
      for (final device in result.devices)
        for (final address in device.ipAddresses)
          if (address.isNotEmpty) address,
    };
    if (targetAddresses.isEmpty || providers.isEmpty) return result;

    final batches = await Future.wait([
      for (final provider in providers)
        _safeCollect(
          provider,
          targetAddresses: targetAddresses,
          cancellationToken: cancellationToken,
        ),
    ]);
    if (cancellationToken.isCancelled) {
      throw const DiscoveryCancelledException();
    }

    final builders = <String, _DeviceEnrichmentBuilder>{};
    for (final enrichment in batches.expand((batch) => batch)) {
      builders
          .putIfAbsent(
            enrichment.ipAddress,
            () => _DeviceEnrichmentBuilder(enrichment.ipAddress),
          )
          .add(enrichment);
    }

    final devices = [
      for (final device in result.devices)
        _classifyDevice(_mergeDevice(device, builders)),
    ];
    return DiscoveryResult(
      context: result.context,
      devices: devices,
      limitations: [
        ...result.limitations,
        '장비 이름과 서비스 정보는 장비가 공개적으로 응답한 범위만 표시합니다.',
      ],
      duration: result.duration,
    );
  }

  Future<List<DeviceEnrichment>> _safeCollect(
    NetworkEnrichmentProvider provider, {
    required Set<String> targetAddresses,
    required DiscoveryCancellationToken cancellationToken,
  }) async {
    try {
      return await provider.collect(
        targetAddresses: targetAddresses,
        cancellationToken: cancellationToken,
      );
    } catch (_) {
      return const [];
    }
  }

  NetworkDevice _mergeDevice(
    NetworkDevice device,
    Map<String, _DeviceEnrichmentBuilder> builders,
  ) {
    _DeviceEnrichmentBuilder? builder;
    for (final address in device.ipAddresses) {
      final candidate = builders[address];
      if (candidate != null) {
        builder ??= _DeviceEnrichmentBuilder(address);
        builder.add(candidate.build());
      }
    }
    if (builder == null) return device;
    final enrichment = builder.build();
    final canReplaceName = device.displayName == '확인되지 않은 장비';
    final sources = {...device.sources, ...enrichment.sources}.toList();
    final services = <String, NetworkServiceObservation>{
      for (final service in device.services) service.identityKey: service,
      for (final service in enrichment.services) service.identityKey: service,
    }.values.toList()..sort((left, right) => left.port.compareTo(right.port));
    return device.copyWith(
      displayName: canReplaceName ? enrichment.displayName : device.displayName,
      vendor: enrichment.vendor,
      modelName: enrichment.modelName,
      description: enrichment.description,
      category: device.category == DeviceCategory.unknown
          ? enrichment.category
          : device.category,
      hostnames: {...device.hostnames, ...enrichment.hostnames}.toList(),
      services: services,
      sources: sources,
      identityConfidence: enrichment.sources.isEmpty
          ? device.identityConfidence
          : (device.identityConfidence + 0.1).clamp(0.0, 0.95),
    );
  }

  NetworkDevice _classifyDevice(NetworkDevice device) {
    if (device.category != DeviceCategory.unknown) return device;
    final category = _inferCategory(device);
    return category == null ? device : device.copyWith(category: category);
  }

  DeviceCategory? _inferCategory(NetworkDevice device) {
    final evidence = [
      device.displayName,
      device.vendor ?? '',
      device.modelName ?? '',
      device.description ?? '',
      ...device.hostnames,
      ...device.services.map((service) => service.protocol),
      ...device.services.map((service) => service.product ?? ''),
    ].join(' ').toLowerCase().replaceAll('_', '-');

    bool containsAny(List<String> values) {
      return values.any(evidence.contains);
    }

    if (containsAny(const ['router', 'gateway', 'iptime', 'a6004ns'])) {
      return DeviceCategory.router;
    }
    if (containsAny(const [
      'bid-at',
      'smart tv',
      'smarttv',
      'androidtv',
      'googlecast',
      'chromecast',
      'webos',
      'bravia',
      'tizen',
      'roku',
      'apple tv',
      'appletv',
      'set-top',
      'settop',
      'mediarenderer',
    ])) {
      return DeviceCategory.television;
    }
    if (containsAny(const ['printer', ' ipp ', 'airprint'])) {
      return DeviceCategory.printer;
    }
    if (containsAny(const ['camera', 'webcam', ' rtsp'])) {
      return DeviceCategory.camera;
    }
    if (containsAny(const ['speaker', 'sonos', ' raop', 'spotify-connect'])) {
      return DeviceCategory.speaker;
    }
    if (containsAny(const [
      'homekit',
      'matter',
      'miio',
      'ewelink',
      'smartthings',
      'home assistant',
      'vacuum',
      'air purifier',
      'airpurifier',
      'washer',
      'dryer',
      'refrigerator',
    ])) {
      return DeviceCategory.iot;
    }
    if (containsAny(const [
      'iphone',
      'ipad',
      'galaxy',
      'pixel',
      ' phone',
      'mobile',
      'mobdev',
    ])) {
      return DeviceCategory.phone;
    }
    if (containsAny(const [
      'windows',
      'desktop-',
      'laptop',
      'macbook',
      'imac',
      'workstation',
      ' smb',
      ' rdp',
      'netbios-ns',
    ])) {
      return DeviceCategory.computer;
    }
    return null;
  }
}

class _DeviceEnrichmentBuilder {
  _DeviceEnrichmentBuilder(this.ipAddress);

  final String ipAddress;
  String? displayName;
  String? vendor;
  String? modelName;
  String? description;
  DeviceCategory? category;
  final Set<String> hostnames = {};
  final Map<String, NetworkServiceObservation> services = {};
  final Set<DiscoverySource> sources = {};

  void add(DeviceEnrichment value) {
    displayName ??= _clean(value.displayName);
    vendor ??= _clean(value.vendor);
    modelName ??= _clean(value.modelName);
    description ??= _clean(value.description);
    category ??= value.category;
    hostnames.addAll(value.hostnames.map(_clean).whereType<String>());
    for (final service in value.services) {
      services[service.identityKey] = service;
    }
    sources.addAll(value.sources);
  }

  DeviceEnrichment build() {
    final fallbackName = hostnames.isEmpty
        ? modelName
        : hostnames.first.replaceFirst(RegExp(r'\.local\.?$'), '');
    return DeviceEnrichment(
      ipAddress: ipAddress,
      displayName: displayName ?? fallbackName,
      vendor: vendor,
      modelName: modelName,
      description: description,
      category: category,
      hostnames: hostnames.toList(),
      services: services.values.toList(),
      sources: sources.toList(),
    );
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
