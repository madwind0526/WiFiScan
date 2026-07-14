import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class ProfileCredentialStore {
  Future<String?> read(String profileId);

  Future<void> write(String profileId, String password);

  Future<void> delete(String profileId);
}

class SecureProfileCredentialStore implements ProfileCredentialStore {
  SecureProfileCredentialStore({FlutterSecureStorage? storage})
    : _storage =
          storage ?? const FlutterSecureStorage(aOptions: AndroidOptions());

  static const _keyPrefix = 'wifiscan.profile.password.v1.';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String profileId) async {
    return _storage.read(key: await _storageKey(profileId));
  }

  @override
  Future<void> write(String profileId, String password) async {
    await _storage.write(key: await _storageKey(profileId), value: password);
  }

  @override
  Future<void> delete(String profileId) async {
    await _storage.delete(key: await _storageKey(profileId));
  }

  Future<String> _storageKey(String profileId) async {
    final digest = await Sha256().hash(utf8.encode(profileId));
    return '$_keyPrefix${base64UrlEncode(digest.bytes).replaceAll('=', '')}';
  }
}
