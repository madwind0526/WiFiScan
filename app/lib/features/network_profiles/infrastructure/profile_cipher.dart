import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Encrypts profile passwords at rest with AES-GCM.
///
/// The key is derived from an application-level seed so exported profile
/// files stay readable on another device running WifiScan. This protects
/// against casual inspection of the JSON file, not against an attacker
/// who can run code on the device.
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
      final clear = await algorithm.decrypt(
        box,
        secretKey: await _secretKey(),
      );
      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }
}
