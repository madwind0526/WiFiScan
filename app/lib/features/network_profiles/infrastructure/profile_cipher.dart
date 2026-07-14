import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Decrypts passwords written by the legacy local profile format.
///
/// New passwords are stored by ProfileCredentialStore. This cipher remains
/// only so existing passwordEnc values can be migrated without data loss.
class ProfileCipher {
  const ProfileCipher();

  static const String _keySeed = 'wifiscan.profile.storage.v1';

  Future<SecretKey> _secretKey() async {
    final hash = await Sha256().hash(utf8.encode(_keySeed));
    return SecretKey(hash.bytes);
  }

  Future<String> encrypt(String plainText) async {
    final algorithm = AesGcm.with256bits();
    final box = await algorithm.encrypt(
      utf8.encode(plainText),
      secretKey: await _secretKey(),
    );
    return base64Encode(box.concatenation());
  }

  Future<String?> decrypt(String encoded) async {
    try {
      final algorithm = AesGcm.with256bits();
      final box = SecretBox.fromConcatenation(
        base64Decode(encoded),
        nonceLength: AesGcm.defaultNonceLength,
        macLength: 16,
      );
      final clear = await algorithm.decrypt(box, secretKey: await _secretKey());
      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }
}
