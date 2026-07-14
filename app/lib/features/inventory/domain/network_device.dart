enum DeviceCategory {
  router,
  phone,
  computer,
  television,
  appliance,
  camera,
  speaker,
  printer,
  iot,
  unknown,
}

enum OwnershipStatus { confirmed, unconfirmed, blocked }

enum DiscoverySource {
  localInterface,
  router,
  neighbor,
  subnet,
  reverseDns,
  mdns,
  ssdp,
  serviceProbe,
  manual,
}

enum NetworkTransport { tcp, udp }

class NetworkServiceObservation {
  const NetworkServiceObservation({
    required this.protocol,
    required this.port,
    required this.transport,
    required this.source,
    this.product,
    this.version,
  });

  final String protocol;
  final int port;
  final NetworkTransport transport;
  final DiscoverySource source;
  final String? product;
  final String? version;

  String get identityKey => '${transport.name}:$port:$protocol';

  Map<String, Object?> toJson() => {
    'protocol': protocol,
    'port': port,
    'transport': transport.name,
    'source': source.name,
    if (product != null) 'product': product,
    if (version != null) 'version': version,
  };

  factory NetworkServiceObservation.fromJson(Map<String, Object?> json) {
    return NetworkServiceObservation(
      protocol: json['protocol']?.toString() ?? 'unknown',
      port: (json['port'] as num?)?.toInt() ?? 0,
      transport: _enumByName(
        NetworkTransport.values,
        json['transport']?.toString(),
        NetworkTransport.tcp,
      ),
      source: _enumByName(
        DiscoverySource.values,
        json['source']?.toString(),
        DiscoverySource.subnet,
      ),
      product: json['product']?.toString(),
      version: json['version']?.toString(),
    );
  }
}

class NetworkDevice {
  const NetworkDevice({
    required this.id,
    required this.displayName,
    required this.category,
    required this.ownershipStatus,
    required this.ipAddresses,
    required this.sources,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.identityConfidence,
    this.macAddress,
    this.vendor,
    this.modelName,
    this.description,
    this.hostnames = const [],
    this.services = const [],
  });

  final String id;
  final String displayName;
  final DeviceCategory category;
  final OwnershipStatus ownershipStatus;
  final List<String> ipAddresses;
  final List<DiscoverySource> sources;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final double identityConfidence;
  final String? macAddress;
  final String? vendor;
  final String? modelName;
  final String? description;
  final List<String> hostnames;
  final List<NetworkServiceObservation> services;

  NetworkDevice copyWith({
    String? id,
    String? displayName,
    DeviceCategory? category,
    OwnershipStatus? ownershipStatus,
    List<String>? ipAddresses,
    List<DiscoverySource>? sources,
    DateTime? firstSeenAt,
    DateTime? lastSeenAt,
    double? identityConfidence,
    String? macAddress,
    String? vendor,
    String? modelName,
    String? description,
    List<String>? hostnames,
    List<NetworkServiceObservation>? services,
  }) {
    return NetworkDevice(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      category: category ?? this.category,
      ownershipStatus: ownershipStatus ?? this.ownershipStatus,
      ipAddresses: ipAddresses ?? this.ipAddresses,
      sources: sources ?? this.sources,
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      identityConfidence: identityConfidence ?? this.identityConfidence,
      macAddress: macAddress ?? this.macAddress,
      vendor: vendor ?? this.vendor,
      modelName: modelName ?? this.modelName,
      description: description ?? this.description,
      hostnames: hostnames ?? this.hostnames,
      services: services ?? this.services,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'category': category.name,
      'ownershipStatus': ownershipStatus.name,
      'ipAddresses': ipAddresses,
      'sources': sources.map((source) => source.name).toList(),
      'firstSeenAt': firstSeenAt.toIso8601String(),
      'lastSeenAt': lastSeenAt.toIso8601String(),
      'identityConfidence': identityConfidence,
      if (macAddress != null) 'macAddress': macAddress,
      if (vendor != null) 'vendor': vendor,
      if (modelName != null) 'modelName': modelName,
      if (description != null) 'description': description,
      if (hostnames.isNotEmpty) 'hostnames': hostnames,
      if (services.isNotEmpty)
        'services': services.map((service) => service.toJson()).toList(),
    };
  }

  factory NetworkDevice.fromJson(Map<String, Object?> json) {
    return NetworkDevice(
      id: json['id']?.toString() ?? 'unknown',
      displayName: json['displayName']?.toString() ?? '확인되지 않은 장비',
      category: _enumByName(
        DeviceCategory.values,
        json['category']?.toString(),
        DeviceCategory.unknown,
      ),
      ownershipStatus: _enumByName(
        OwnershipStatus.values,
        json['ownershipStatus']?.toString(),
        OwnershipStatus.unconfirmed,
      ),
      ipAddresses: _stringList(json['ipAddresses']),
      sources: _enumList(json['sources']),
      firstSeenAt: _dateTime(json['firstSeenAt']),
      lastSeenAt: _dateTime(json['lastSeenAt']),
      identityConfidence: (json['identityConfidence'] as num?)?.toDouble() ?? 0,
      macAddress: json['macAddress']?.toString(),
      vendor: json['vendor']?.toString(),
      modelName: json['modelName']?.toString(),
      description: json['description']?.toString(),
      hostnames: _stringList(json['hostnames']),
      services: _serviceList(json['services']),
    );
  }
}

List<NetworkServiceObservation> _serviceList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(
        (item) =>
            NetworkServiceObservation.fromJson(item.cast<String, Object?>()),
      )
      .where((service) => service.port > 0)
      .toList(growable: false);
}

T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString()).toList(growable: false);
}

List<DiscoverySource> _enumList(Object? value) {
  if (value is! List) return const [];
  return value
      .map(
        (item) => _enumByName(
          DiscoverySource.values,
          item.toString(),
          DiscoverySource.manual,
        ),
      )
      .toList(growable: false);
}

DateTime _dateTime(Object? value) {
  return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
}
