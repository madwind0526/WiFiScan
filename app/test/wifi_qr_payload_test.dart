import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/network_profiles/domain/wifi_qr_payload.dart';

void main() {
  test('reads the SSID, passphrase and security type', () {
    final payload = parseWifiQr('WIFI:S:madwind-5G;T:WPA;P:secret123;H:false;;');

    expect(payload?.ssid, 'madwind-5G');
    expect(payload?.password, 'secret123');
    expect(payload?.security, 'WPA');
    expect(payload?.hidden, isFalse);
    expect(payload?.isOpen, isFalse);
  });

  test('accepts fields in any order and marks hidden networks', () {
    final payload = parseWifiQr('WIFI:T:SAE;H:true;P:pw;S:hidden-net;;');

    expect(payload?.ssid, 'hidden-net');
    expect(payload?.password, 'pw');
    expect(payload?.hidden, isTrue);
  });

  test('keeps escaped separators inside a value', () {
    // An SSID or password may legitimately contain ; : , \ or ".
    final payload = parseWifiQr(r'WIFI:S:my\;net;T:WPA;P:a\:b\\c\;d;;');

    expect(payload?.ssid, 'my;net');
    expect(payload?.password, r'a:b\c;d');
  });

  test('treats a keyless payload as an open network', () {
    final payload = parseWifiQr('WIFI:S:cafe;T:nopass;;');

    expect(payload?.ssid, 'cafe');
    expect(payload?.password, isNull);
    expect(payload?.isOpen, isTrue);
  });

  test('rejects codes that are not Wi-Fi payloads', () {
    expect(parseWifiQr('https://example.com'), isNull);
    expect(parseWifiQr('WIFI:T:WPA;P:secret;;'), isNull);
    expect(parseWifiQr(''), isNull);
  });
}
