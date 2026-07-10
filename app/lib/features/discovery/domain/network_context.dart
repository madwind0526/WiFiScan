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
}
