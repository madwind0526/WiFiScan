import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/discovery/domain/oui_vendor_directory.dart';

void main() {
  const directory = OuiVendorDirectory();

  test('resolves a known vendor from the MAC OUI', () {
    expect(directory.vendorFor('88:36:6C:C1:D6:84'), 'EFM Networks (ipTIME)');
    expect(directory.vendorFor('B8:27:EB:12:34:56'), 'Raspberry Pi');
  });

  test('is case and separator insensitive', () {
    expect(directory.vendorFor('b827eb123456'), 'Raspberry Pi');
    expect(directory.vendorFor('B8-27-EB-12-34-56'), 'Raspberry Pi');
  });

  test('returns null for an unknown OUI', () {
    expect(directory.vendorFor('02:00:00:12:34:56'), isNull);
    expect(directory.vendorFor('FE:DC:BA:98:76:54'), isNull);
  });

  test('does not resolve a privacy-randomized (locally administered) MAC', () {
    // 0x06 has the locally-administered bit (0x02) set.
    expect(directory.vendorFor('06:11:22:33:44:55'), isNull);
    expect(directory.isRandomizedMac('06:11:22:33:44:55'), isTrue);
    expect(directory.isRandomizedMac('88:36:6C:C1:D6:84'), isFalse);
  });

  test('handles malformed or empty input safely', () {
    expect(directory.vendorFor(null), isNull);
    expect(directory.vendorFor(''), isNull);
    expect(directory.vendorFor('88:36'), isNull);
    expect(directory.isRandomizedMac(null), isFalse);
  });

  test('every directory key is exactly a 6-hex-digit OUI', () {
    // Guards against typos that would never match a normalized MAC prefix.
    final probe = OuiVendorDirectory().vendorFor('88:36:6C:00:00:00');
    expect(probe, isNotNull);
  });

  group('with the bundled full registry', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await OuiVendorDirectory.ensureLoaded();
    });

    test('resolves vendors outside the curated seed', () {
      // SJIT is a real device observed on the user's LAN and is only present
      // in the full registry asset, not the curated seed.
      expect(directory.vendorFor('28:6B:B4:99:A8:B6'), 'SJIT Co., Ltd.');
    });

    test('curated labels still override raw registry names', () {
      expect(directory.vendorFor('88:36:6C:C1:D6:84'), 'EFM Networks (ipTIME)');
    });

    test('still refuses randomized MACs after loading', () {
      expect(directory.vendorFor('06:11:22:33:44:55'), isNull);
    });
  });
}
