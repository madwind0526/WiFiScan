import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wifi_scan/features/discovery/domain/router_dhcp_client.dart';

/// Per-router admin credentials, keyed by the router's admin host (its gateway
/// IP). The user owns multiple routers on different subnets, so each is stored
/// and logged into independently.
///
/// The password lives in the OS secure store (never in plain files or git);
/// the username lives alongside it. Passwords are only ever supplied by the
/// user — never guessed.
abstract interface class RouterCredentialStore {
  Future<RouterCredentials?> read(String host);

  Future<void> write(RouterCredentials credentials);

  Future<void> delete(String host);
}

class SecureRouterCredentialStore implements RouterCredentialStore {
  SecureRouterCredentialStore({FlutterSecureStorage? storage})
    : _storage =
          storage ?? const FlutterSecureStorage(aOptions: AndroidOptions());

  static const _prefix = 'wifiscan.router.cred.v1.';

  final FlutterSecureStorage _storage;

  @override
  Future<RouterCredentials?> read(String host) async {
    final raw = await _storage.read(key: await _key(host));
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final password = json['password']?.toString() ?? '';
      if (password.isEmpty) return null;
      return RouterCredentials(
        host: host,
        username: json['username']?.toString() ?? 'admin',
        password: password,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(RouterCredentials credentials) async {
    await _storage.write(
      key: await _key(credentials.host),
      value: jsonEncode({
        'username': credentials.username,
        'password': credentials.password,
      }),
    );
  }

  @override
  Future<void> delete(String host) async {
    await _storage.delete(key: await _key(host));
  }

  Future<String> _key(String host) async {
    final digest = await Sha256().hash(utf8.encode(host));
    return '$_prefix${base64UrlEncode(digest.bytes).replaceAll('=', '')}';
  }
}
