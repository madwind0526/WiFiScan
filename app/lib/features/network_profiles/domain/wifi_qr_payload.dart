/// A Wi-Fi network read from a QR code.
class WifiQrPayload {
  const WifiQrPayload({
    required this.ssid,
    this.password,
    this.security,
    this.hidden = false,
  });

  final String ssid;
  final String? password;

  /// `WPA`, `WEP`, `SAE`, or `nopass` for an open network.
  final String? security;
  final bool hidden;

  bool get isOpen =>
      (password ?? '').isEmpty ||
      (security ?? '').toLowerCase() == 'nopass';
}

/// Parses the `WIFI:` QR format that Android's "share network" screen and most
/// routers print.
///
/// The payload looks like `WIFI:S:my ssid;T:WPA;P:secret;H:false;;`. Fields may
/// appear in any order, and `\`, `;`, `,`, `:` and `"` inside a value are
/// backslash-escaped, so an SSID or password containing a separator survives
/// the round trip. Returns null for anything that is not a Wi-Fi payload or
/// that carries no SSID.
WifiQrPayload? parseWifiQr(String raw) {
  final text = raw.trim();
  if (!RegExp(r'^WIFI:', caseSensitive: false).hasMatch(text)) return null;

  final fields = <String, String>{};
  final value = StringBuffer();
  String? key;
  var escaped = false;
  // Walk the body character by character: a split on ';' or ':' would break
  // values that legitimately contain an escaped one.
  for (final char in text.substring(5).split('')) {
    if (escaped) {
      value.write(char);
      escaped = false;
      continue;
    }
    switch (char) {
      case r'\':
        escaped = true;
      case ':':
        if (key == null) {
          key = value.toString().trim().toUpperCase();
          value.clear();
        } else {
          value.write(char);
        }
      case ';':
        if (key != null) {
          fields[key] = value.toString();
          key = null;
        }
        value.clear();
      default:
        value.write(char);
    }
  }

  final ssid = fields['S'] ?? '';
  if (ssid.isEmpty) return null;
  final password = fields['P'];
  return WifiQrPayload(
    ssid: ssid,
    password: (password == null || password.isEmpty) ? null : password,
    security: fields['T'],
    hidden: (fields['H'] ?? '').toLowerCase() == 'true',
  );
}
