import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/network_profiles/application/network_profile_repository.dart';
import 'package:wifi_scan/features/network_profiles/domain/network_profile.dart';
import 'package:wifi_scan/features/network_profiles/infrastructure/profile_cipher.dart';
import 'package:wifi_scan/features/network_profiles/infrastructure/profile_credential_store.dart';

void main() {
  late Directory temporaryDirectory;
  late File profileFile;
  late _MemoryCredentialStore credentialStore;
  late NetworkProfileRepository repository;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'wifiscan-profile-test-',
    );
    profileFile = File('${temporaryDirectory.path}/network_profiles.json');
    credentialStore = _MemoryCredentialStore();
    repository = NetworkProfileRepository(
      credentialStore: credentialStore,
      fileProvider: () async => profileFile,
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('stores passwords outside the profile metadata file', () async {
    const profile = NetworkProfile(
      id: 'LivingRoom-5G',
      ssid: 'LivingRoom-5G',
      displayName: '거실 공유기',
      password: 'local-secret-password',
    );

    await repository.save(const [profile]);

    final raw = await profileFile.readAsString();
    final decoded = (jsonDecode(raw) as List).single as Map<String, dynamic>;
    expect(decoded, isNot(contains('password')));
    expect(decoded, isNot(contains('passwordEnc')));
    expect(raw, isNot(contains('local-secret-password')));
    expect(credentialStore.values['LivingRoom-5G'], 'local-secret-password');

    final loaded = await repository.load();
    expect(loaded.single.password, 'local-secret-password');
  });

  test('deletes a secure credential when its profile is removed', () async {
    const profile = NetworkProfile(
      id: 'Office-WiFi',
      ssid: 'Office-WiFi',
      displayName: '사무실',
      password: 'office-secret',
    );
    await repository.save(const [profile]);

    await repository.save(const []);

    expect(credentialStore.values, isEmpty);
    expect(credentialStore.deletedIds, contains('Office-WiFi'));
  });

  test('migrates legacy passwordEnc values to secure storage', () async {
    final encrypted = await const ProfileCipher().encrypt('legacy-secret');
    await profileFile.writeAsString(
      jsonEncode([
        {
          'id': 'Legacy-WiFi',
          'ssid': 'Legacy-WiFi',
          'displayName': '기존 프로필',
          'passwordEnc': encrypted,
        },
      ]),
    );

    final loaded = await repository.load();

    expect(loaded.single.password, 'legacy-secret');
    expect(credentialStore.values['Legacy-WiFi'], 'legacy-secret');
    final migrated = await profileFile.readAsString();
    expect(migrated, isNot(contains('passwordEnc')));
    expect(migrated, isNot(contains('legacy-secret')));
  });
}

class _MemoryCredentialStore implements ProfileCredentialStore {
  final Map<String, String> values = {};
  final List<String> deletedIds = [];

  @override
  Future<String?> read(String profileId) async => values[profileId];

  @override
  Future<void> write(String profileId, String password) async {
    values[profileId] = password;
  }

  @override
  Future<void> delete(String profileId) async {
    values.remove(profileId);
    deletedIds.add(profileId);
  }
}
