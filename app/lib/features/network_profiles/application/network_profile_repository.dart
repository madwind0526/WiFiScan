import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:wifi_scan/features/network_profiles/domain/network_profile.dart';
import 'package:wifi_scan/features/network_profiles/infrastructure/profile_cipher.dart';
import 'package:wifi_scan/features/network_profiles/infrastructure/profile_credential_store.dart';

class NetworkProfileRepository {
  NetworkProfileRepository({
    ProfileCredentialStore? credentialStore,
    ProfileCipher? legacyCipher,
    this.fileProvider,
  }) : _credentialStore = credentialStore ?? SecureProfileCredentialStore(),
       _legacyCipher = legacyCipher ?? const ProfileCipher();

  final ProfileCredentialStore _credentialStore;
  final ProfileCipher _legacyCipher;
  final Future<File> Function()? fileProvider;

  Future<List<NetworkProfile>> load() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      final profiles = <NetworkProfile>[];
      var hasLegacyPassword = false;
      var failedLegacyMigration = false;
      for (final item in decoded.whereType<Map>()) {
        final map = item.cast<String, Object?>();
        var profile = NetworkProfile.fromJson(map);
        if (profile.ssid.isEmpty) continue;
        var password = await _credentialStore.read(profile.id);
        final legacyPassword = map['passwordEnc']?.toString();
        if (legacyPassword != null && legacyPassword.isNotEmpty) {
          hasLegacyPassword = true;
          if (password == null) {
            password = await _legacyCipher.decrypt(legacyPassword);
            if (password == null) {
              failedLegacyMigration = true;
            } else {
              await _credentialStore.write(profile.id, password);
            }
          }
        }
        if (password != null && password.isNotEmpty) {
          profile = profile.copyWith(password: password);
        }
        profiles.add(profile);
      }
      if (hasLegacyPassword && !failedLegacyMigration) {
        await _writeMetadata(file, profiles);
      }
      return List.unmodifiable(profiles);
    } on FormatException {
      return const [];
    } on FileSystemException {
      return const [];
    }
  }

  Future<void> save(List<NetworkProfile> profiles) async {
    final file = await _file();
    final previousIds = await _storedProfileIds(file);
    for (final profile in profiles) {
      final password = profile.password;
      if (password != null && password.isNotEmpty) {
        await _credentialStore.write(profile.id, password);
      }
    }
    await _writeMetadata(file, profiles);
    final currentIds = profiles.map((profile) => profile.id).toSet();
    for (final removedId in previousIds.difference(currentIds)) {
      await _credentialStore.delete(removedId);
    }
  }

  Future<File> _file() async {
    if (fileProvider != null) return fileProvider!();
    final directory = await getApplicationSupportDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}network_profiles.json',
    );
  }

  Future<Set<String>> _storedProfileIds(File file) async {
    if (!await file.exists()) return const {};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const {};
      return {
        for (final item in decoded.whereType<Map>())
          if (item['id']?.toString() case final id? when id.isNotEmpty) id,
      };
    } catch (_) {
      return const {};
    }
  }

  Future<void> _writeMetadata(File file, List<NetworkProfile> profiles) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode([for (final profile in profiles) profile.toJson()]),
      flush: true,
    );
  }
}
