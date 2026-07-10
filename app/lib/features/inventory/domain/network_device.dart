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
  mdns,
  ssdp,
  manual,
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
}
