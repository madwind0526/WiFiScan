import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/infrastructure/windows_network_discovery_service.dart';

void main() {
  test('selects Wi-Fi instead of an active Ethernet gateway', () {
    final selected =
        WindowsNetworkDiscoveryService.selectWirelessNetworkContext([
          const WindowsNetworkContextCandidate(
            interfaceName: 'Ethernet',
            interfaceIndex: 17,
            ipv4Address: '192.168.0.30',
            prefixLength: 24,
            gateway: '192.168.0.1',
            isWireless: false,
          ),
          const WindowsNetworkContextCandidate(
            interfaceName: 'Wi-Fi',
            interfaceIndex: 21,
            ipv4Address: '192.168.45.20',
            prefixLength: 24,
            gateway: '192.168.45.1',
            isWireless: true,
          ),
        ]);

    expect(selected.interfaceIndex, 21);
    expect(selected.gateway, '192.168.45.1');
  });

  test('never falls back to Ethernet when Wi-Fi is unavailable', () {
    expect(
      () => WindowsNetworkDiscoveryService.selectWirelessNetworkContext([
        const WindowsNetworkContextCandidate(
          interfaceName: 'Ethernet',
          interfaceIndex: 17,
          ipv4Address: '192.168.0.30',
          prefixLength: 24,
          gateway: '192.168.0.1',
          isWireless: false,
        ),
      ]),
      throwsA(isA<DiscoveryUnavailableException>()),
    );
  });

  test('keeps Wi-Fi selected while its gateway is settling', () {
    final selected =
        WindowsNetworkDiscoveryService.selectWirelessNetworkContext([
          const WindowsNetworkContextCandidate(
            interfaceName: 'Ethernet',
            interfaceIndex: 17,
            ipv4Address: '192.168.0.30',
            prefixLength: 24,
            gateway: '192.168.0.1',
            isWireless: false,
          ),
          const WindowsNetworkContextCandidate(
            interfaceName: 'Wi-Fi',
            interfaceIndex: 21,
            ipv4Address: '192.168.45.20',
            prefixLength: 24,
            gateway: '',
            isWireless: true,
          ),
        ]);

    expect(selected.interfaceIndex, 21);
    expect(selected.gateway, isEmpty);
  });

  test('binds ping probes to the selected Wi-Fi IPv4 address', () {
    final arguments = WindowsNetworkDiscoveryService.buildPingArguments(
      sourceAddress: '192.168.0.29',
      targetAddress: '192.168.0.50',
      timeoutMilliseconds: 250,
    );

    expect(arguments, [
      '-4',
      '-n',
      '1',
      '-w',
      '250',
      '-S',
      '192.168.0.29',
      '192.168.0.50',
    ]);
  });
}
