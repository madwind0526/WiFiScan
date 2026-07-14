import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/network_profiles/domain/network_profile.dart';
import 'package:wifi_scan/features/network_profiles/infrastructure/profile_backup_codec.dart';

void main() {
  final codec = ProfileBackupCodec.forTesting();
  const profiles = [
    NetworkProfile(
      id: 'LivingRoom-5G',
      ssid: 'LivingRoom-5G',
      displayName: '거실 공유기',
      password: 'wifi-secret-password',
    ),
  ];

  test('round-trips profiles without exposing plaintext', () async {
    final exported = await codec.exportProfiles(
      profiles,
      password: 'export-password',
    );

    expect(exported, isNot(contains('LivingRoom-5G')));
    expect(exported, isNot(contains('wifi-secret-password')));
    final envelope = jsonDecode(exported) as Map<String, dynamic>;
    expect(envelope['format'], 'wifiscan_profile_backup_encrypted');
    expect(envelope.keys, containsAll(['salt', 'nonce', 'cipherText', 'mac']));

    final restored = await codec.importProfiles(
      exported,
      password: 'export-password',
    );
    expect(restored.single.ssid, 'LivingRoom-5G');
    expect(restored.single.password, 'wifi-secret-password');
  });

  test('rejects a wrong password and uses randomized encryption', () async {
    final first = await codec.exportProfiles(
      profiles,
      password: 'export-password',
    );
    final second = await codec.exportProfiles(
      profiles,
      password: 'export-password',
    );

    expect(first, isNot(second));
    await expectLater(
      codec.importProfiles(first, password: 'wrong-password'),
      throwsA(isA<ProfileBackupException>()),
    );
  });
}
