import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/network_profiles/domain/network_profile.dart';

NetworkProfile _profile(String ssid, {String? password}) =>
    NetworkProfile(id: ssid, ssid: ssid, displayName: ssid, password: password);

void main() {
  test('never replaces a password the user already has', () {
    final profiles = [_profile('madwind-5G', password: 'typed-by-user')];

    final merged = profilesWithMissingPasswordsFilled(profiles, {
      'madwind-5G': 'from-windows',
    });

    expect(merged.single.password, 'typed-by-user');
  });

  test('fills a blank password from what the OS has saved', () {
    final profiles = [_profile('madwind-L'), _profile('madwind-H')];

    final merged = profilesWithMissingPasswordsFilled(profiles, {
      'madwind-L': 'from-windows',
    });

    expect(merged.first.password, 'from-windows');
    // An SSID the OS knows nothing about is left alone.
    expect(merged.last.password, isNull);
  });

  test('ignores empty saved values and an empty map', () {
    final profiles = [_profile('madwind-L')];

    expect(
      profilesWithMissingPasswordsFilled(profiles, {'madwind-L': ''}).single
          .password,
      isNull,
    );
    expect(
      profilesWithMissingPasswordsFilled(profiles, const {}),
      same(profiles),
    );
  });
}
