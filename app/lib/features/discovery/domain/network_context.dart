class NetworkContext {
  const NetworkContext({
    required this.interfaceName,
    required this.interfaceIndex,
    required this.ipv4Address,
    required this.prefixLength,
    required this.gateway,
    required this.scannedNetwork,
    required this.scannedPrefixLength,
    required this.coverageLimited,
  });

  final String interfaceName;
  final int interfaceIndex;
  final String ipv4Address;
  final int prefixLength;
  final String gateway;
  final String scannedNetwork;
  final int scannedPrefixLength;
  final bool coverageLimited;

  String get scannedSubnet => '$scannedNetwork/$scannedPrefixLength';

  Map<String, Object?> toJson() {
    return {
      'interfaceName': interfaceName,
      'interfaceIndex': interfaceIndex,
      'ipv4Address': ipv4Address,
      'prefixLength': prefixLength,
      'gateway': gateway,
      'scannedNetwork': scannedNetwork,
      'scannedPrefixLength': scannedPrefixLength,
      'coverageLimited': coverageLimited,
    };
  }

  factory NetworkContext.fromJson(Map<String, Object?> json) {
    return NetworkContext(
      interfaceName: json['interfaceName']?.toString() ?? '알 수 없음',
      interfaceIndex: _intValue(json['interfaceIndex'], -1),
      ipv4Address: json['ipv4Address']?.toString() ?? '',
      prefixLength: _intValue(json['prefixLength'], 24),
      gateway: json['gateway']?.toString() ?? '',
      scannedNetwork: json['scannedNetwork']?.toString() ?? '',
      scannedPrefixLength: _intValue(json['scannedPrefixLength'], 24),
      coverageLimited: json['coverageLimited'] == true,
    );
  }
}

int _intValue(Object? value, int fallback) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}
