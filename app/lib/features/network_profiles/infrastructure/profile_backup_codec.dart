import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:wifi_scan/features/network_profiles/domain/network_profile.dart';

class ProfileBackupException implements Exception {
  const ProfileBackupException();
}

class ProfileBackupCodec {
  ProfileBackupCodec() : _iterations = _kdfIterations;

  ProfileBackupCodec.forTesting({int iterations = 1000})
    : assert(iterations > 0),
      _iterations = iterations;

  static const minimumPasswordLength = 8;
  static const _format = 'wifiscan_profile_backup_encrypted';
  static const _version = 1;
  static const _payloadFormat = 'wifiscan_profile_payload';
  static const _payloadVersion = 1;
  static const _kdf = 'pbkdf2_hmac_sha256';
  static const _kdfIterations = 600000;
  static const _saltLength = 16;
  static const _nonceLength = 12;
  static const _macLength = 16;

  final AesGcm _aesGcm = AesGcm.with256bits();
  final int _iterations;

  Future<String> exportProfiles(
    List<NetworkProfile> profiles, {
    required String password,
  }) async {
    _validatePassword(password);
    final payload = jsonEncode({
      'format': _payloadFormat,
      'version': _payloadVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'profiles': [
        for (final profile in profiles)
          {
            ...profile.toJson(),
            if (profile.password case final value? when value.isNotEmpty)
              'password': value,
          },
      ],
    });
    final salt = _randomBytes(_saltLength);
    final nonce = _randomBytes(_nonceLength);
    final key = await _deriveKey(password, salt, _iterations);
    final box = await _aesGcm.encrypt(
      utf8.encode(payload),
      secretKey: key,
      nonce: nonce,
    );
    return const JsonEncoder.withIndent('  ').convert({
      'format': _format,
      'version': _version,
      'kdf': _kdf,
      'iterations': _iterations,
      'salt': _bytesToHex(salt),
      'nonce': _bytesToHex(Uint8List.fromList(box.nonce)),
      'cipherText': _bytesToHex(Uint8List.fromList(box.cipherText)),
      'mac': _bytesToHex(Uint8List.fromList(box.mac.bytes)),
    });
  }

  Future<List<NetworkProfile>> importProfiles(
    String content, {
    required String password,
  }) async {
    _validatePassword(password);
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic> ||
          decoded['format'] != _format ||
          decoded['version'] != _version ||
          decoded['kdf'] != _kdf ||
          decoded['iterations'] != _iterations) {
        throw const ProfileBackupException();
      }
      final salt = _requireHex(decoded['salt'], _saltLength);
      final nonce = _requireHex(decoded['nonce'], _nonceLength);
      final cipherText = _requireHex(decoded['cipherText']);
      final mac = _requireHex(decoded['mac'], _macLength);
      if (cipherText.isEmpty) throw const ProfileBackupException();
      final key = await _deriveKey(password, salt, _iterations);
      final clear = await _aesGcm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
      final payload = jsonDecode(utf8.decode(clear));
      if (payload is! Map<String, dynamic> ||
          payload['format'] != _payloadFormat ||
          payload['version'] != _payloadVersion ||
          payload['profiles'] is! List) {
        throw const ProfileBackupException();
      }
      final profiles = <NetworkProfile>[];
      for (final item in payload['profiles'] as List) {
        if (item is! Map) throw const ProfileBackupException();
        final map = item.cast<String, Object?>();
        var profile = NetworkProfile.fromJson(map);
        final profilePassword = map['password'];
        if (profilePassword is String && profilePassword.isNotEmpty) {
          profile = profile.copyWith(password: profilePassword);
        }
        if (profile.id.isEmpty || profile.ssid.isEmpty) {
          throw const ProfileBackupException();
        }
        profiles.add(profile);
      }
      if (profiles.isEmpty) throw const ProfileBackupException();
      return List.unmodifiable(profiles);
    } on ProfileBackupException {
      rethrow;
    } catch (_) {
      throw const ProfileBackupException();
    }
  }

  Future<SecretKey> _deriveKey(
    String password,
    Uint8List salt,
    int iterations,
  ) {
    return Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  }

  void _validatePassword(String password) {
    if (password.length < minimumPasswordLength) {
      throw const ProfileBackupException();
    }
  }

  Uint8List _requireHex(Object? value, [int? expectedLength]) {
    if (value is! String || value.length.isOdd) {
      throw const ProfileBackupException();
    }
    try {
      final bytes = Uint8List.fromList([
        for (var index = 0; index < value.length; index += 2)
          int.parse(value.substring(index, index + 2), radix: 16),
      ]);
      if (expectedLength != null && bytes.length != expectedLength) {
        throw const ProfileBackupException();
      }
      return bytes;
    } catch (_) {
      throw const ProfileBackupException();
    }
  }

  String _bytesToHex(Uint8List bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList([
      for (var index = 0; index < length; index++) random.nextInt(256),
    ]);
  }
}
