import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/network_profiles/infrastructure/windows_network_connection_service.dart';

String _profileXml({
  required String name,
  String? keyType,
  String? keyMaterial,
  bool protected = false,
}) {
  return '''
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>$name</name>
  <SSIDConfig><SSID><name>$name</name></SSID></SSIDConfig>
  <MSM><security>
    ${keyType == null ? '' : '''<sharedKey>
      <keyType>$keyType</keyType>
      <protected>$protected</protected>
      <keyMaterial>${keyMaterial ?? ''}</keyMaterial>
    </sharedKey>'''}
  </security></MSM>
</WLANProfile>
''';
}

void main() {
  group('WindowsNetworkConnectionService.parseExportedProfile', () {
    test('reads the SSID and passphrase from an exported profile', () {
      final parsed = WindowsNetworkConnectionService.parseExportedProfile(
        _profileXml(
          name: 'madwind-5G',
          keyType: 'passPhrase',
          keyMaterial: 'correct horse battery',
        ),
      );

      expect(parsed?.$1, 'madwind-5G');
      expect(parsed?.$2, 'correct horse battery');
    });

    test('skips a key that Windows left encrypted', () {
      // Without elevation the key stays DPAPI-protected, so keyMaterial is a
      // blob rather than the passphrase — importing it would store garbage.
      final parsed = WindowsNetworkConnectionService.parseExportedProfile(
        _profileXml(
          name: 'madwind-L',
          keyType: 'passPhrase',
          keyMaterial: '01000000D08C9DDF0115D1118C7A00C04FC297EB',
          protected: true,
        ),
      );

      expect(parsed, isNull);
    });

    test('skips open networks and profiles without a key', () {
      expect(
        WindowsNetworkConnectionService.parseExportedProfile(
          _profileXml(name: 'cafe-guest'),
        ),
        isNull,
      );
      expect(
        WindowsNetworkConnectionService.parseExportedProfile(
          _profileXml(name: 'empty', keyType: 'passPhrase', keyMaterial: ''),
        ),
        isNull,
      );
    });

    test('skips non-passphrase key types', () {
      expect(
        WindowsNetworkConnectionService.parseExportedProfile(
          _profileXml(
            name: 'wep-net',
            keyType: 'networkKey',
            keyMaterial: 'ABCDEF0123',
          ),
        ),
        isNull,
      );
    });

    test('returns null for output that is not a profile', () {
      expect(
        WindowsNetworkConnectionService.parseExportedProfile('<html></html>'),
        isNull,
      );
    });
  });
}
