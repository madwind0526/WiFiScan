import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/network_profiles/application/network_connection_service.dart';
import 'package:wifi_scan/features/network_profiles/infrastructure/windows_network_connection_service.dart';

void main() {
  test('reads an explicit English band field', () {
    const output = '''
    Name                   : Wi-Fi
    SSID                   : madwind-H
    Band                   : 5 GHz
    Channel                : 149
''';
    expect(WindowsNetworkConnectionService.parseBand(output), WifiBand.ghz5);
  });

  test('reads an explicit Korean band field', () {
    const output = '''
    이름                   : Wi-Fi
    SSID                   : madwind-L
    대역                   : 2.4 GHz
    채널                   : 6
''';
    expect(WindowsNetworkConnectionService.parseBand(output), WifiBand.ghz24);
  });

  test('falls back to a 5 GHz channel number when band is absent', () {
    const output = '''
    SSID                   : madwind-H
    Channel                : 149
''';
    expect(WindowsNetworkConnectionService.parseBand(output), WifiBand.ghz5);
  });

  test('falls back to a 2.4 GHz channel number when band is absent', () {
    const output = '''
    SSID                   : madwind-L
    Channel                : 6
''';
    expect(WindowsNetworkConnectionService.parseBand(output), WifiBand.ghz24);
  });

  test('returns unknown when neither band nor channel is present', () {
    const output = '''
    SSID                   : madwind-H
    State                  : connected
''';
    expect(WindowsNetworkConnectionService.parseBand(output), WifiBand.unknown);
  });
}
