import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:wifi_scan/features/network_profiles/domain/network_profile.dart';
import 'package:wifi_scan/features/network_profiles/infrastructure/profile_cipher.dart';

class NetworkProfileRepository {
  const NetworkProfileRepository({ProfileCipher? cipher})
    : _cipher = cipher ?? const ProfileCipher();

  final ProfileCipher _cipher;

  Future<List<NetworkProfile>> load() async {
    final file = await _file();
    if (!await file.exists()) return const [];
    try {
      return await decode(await file.readAsString());
    } on FormatException {
      return const [];
    } on FileSystemException {
      return const [];
    }
  }

  Future<void> save(List<NetworkProfile> profiles) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(await encode(profiles), flush: true);
  }

  /// Serializes profiles to JSON with AES-encrypted passwords.
  Future<String> encode(List<NetworkProfile> profiles) async {
    final items = <Map<String, Object?>>[];
    for (final profile in profiles) {
      final map = profile.toJson();
      final password = profile.password;
      if (password != null && password.isNotEmpty) {
        map['passwordEnc'] = await _cipher.encrypt(password);
      }
      items.add(map);
    }
    return jsonEncode(items);
  }

  /// Parses profile JSON produced by [encode], decrypting stored passwords.
  Future<List<NetworkProfile>> decode(String content) async {
    final decoded = jsonDecode(content);
    if (decoded is! List) return const [];
    final result = <NetworkProfile>[];
    for (final item in decoded.whereType<Map>()) {
      final map = item.cast<String, Object?>();
      var profile = NetworkProfile.fromJson(map);
      final encrypted = map['passwordEnc']?.toString();
      if (encrypted != null && encrypted.isNotEmpty) {
        final password = await _cipher.decrypt(encrypted);
        if (password != null) profile = profile.copyWith(password: password);
      }
      if (profile.ssid.isNotEmpty) result.add(profile);
    }
    return List.unmodifiable(result);
  }

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}network_profiles.json',
    );
  }
}
