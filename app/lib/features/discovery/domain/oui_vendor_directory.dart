import 'package:flutter/services.dart' show rootBundle;

/// Offline OUI (MAC prefix) to vendor lookup.
///
/// The first three octets of a globally-administered MAC address are an IEEE
/// OUI assigned to a manufacturer. Resolving them locally lets the app name a
/// vendor for devices that never answer any active probe (mDNS/SSDP/NetBIOS),
/// with no network calls at scan time — matching the app's local-first
/// principle.
///
/// The full registry (IEEE data via the Wireshark `manuf` file, ~39k entries)
/// ships as the bundled asset `assets/oui/oui_manuf.tsv` and is loaded once
/// via [ensureLoaded]. The small curated map below acts as a seed: it keeps
/// lookups working when the asset cannot be loaded (e.g. plain unit tests
/// without a Flutter binding) and its labels override the registry where a
/// friendlier local name is preferred (e.g. ipTIME, LG전자).
class OuiVendorDirectory {
  const OuiVendorDirectory();

  static const String _assetPath = 'assets/oui/oui_manuf.tsv';

  /// Registry loaded from [_assetPath]; null until [ensureLoaded] succeeds.
  static Map<String, String>? _registry;
  static Future<void>? _loading;

  /// Loads the bundled full OUI registry once. Safe to call repeatedly and
  /// from concurrent scans; failures fall back to the curated seed silently.
  static Future<void> ensureLoaded() {
    if (_registry != null) return Future.value();
    return _loading ??= _loadRegistry();
  }

  static Future<void> _loadRegistry() async {
    try {
      final text = await rootBundle.loadString(_assetPath);
      final entries = <String, String>{};
      for (final line in text.split('\n')) {
        final separator = line.indexOf('\t');
        if (separator != 6) continue;
        final oui = line.substring(0, 6).toUpperCase();
        final name = line.substring(separator + 1).trim();
        if (name.isEmpty) continue;
        entries[oui] = name;
      }
      if (entries.isNotEmpty) {
        // Curated labels win over raw registry names.
        entries.addAll(_vendors);
        _registry = entries;
      }
    } catch (_) {
      // Asset unavailable (no Flutter binding, stripped bundle): keep the
      // curated seed as the lookup source.
    } finally {
      _loading = null;
    }
  }

  static const Map<String, String> _vendors = {
    // EFM Networks (ipTIME) — confirmed by the local router BSSID.
    '88366C': 'EFM Networks (ipTIME)',
    '002666': 'EFM Networks (ipTIME)',
    '909F33': 'EFM Networks (ipTIME)',
    'DC9FDB': 'EFM Networks (ipTIME)',
    '64E599': 'EFM Networks (ipTIME)',
    // Samsung Electronics.
    '001247': 'Samsung',
    '001599': 'Samsung',
    '001A8A': 'Samsung',
    '002119': 'Samsung',
    '002637': 'Samsung',
    '08373D': 'Samsung',
    '0C1420': 'Samsung',
    '183A2D': 'Samsung',
    '1C62B8': 'Samsung',
    '342387': 'Samsung',
    '38AA3C': 'Samsung',
    '5C0A5B': 'Samsung',
    '781FDB': 'Samsung',
    '8C71F8': 'Samsung',
    '94350A': 'Samsung',
    'A00BBA': 'Samsung',
    'AC5F3E': 'Samsung',
    'B85E7B': 'Samsung',
    'C819F7': 'Samsung',
    'D059E4': 'Samsung',
    'E8508B': 'Samsung',
    'EC1F72': 'Samsung',
    'F008F1': 'Samsung',
    'FCA13E': 'Samsung',
    // LG Electronics.
    '001C62': 'LG전자',
    '001E75': 'LG전자',
    '001F6B': 'LG전자',
    '0022A9': 'LG전자',
    '0034DA': 'LG전자',
    '10683F': 'LG전자',
    '2C54CF': 'LG전자',
    '3CBDD8': 'LG전자',
    '58A2B5': 'LG전자',
    '64995D': 'LG전자',
    'A816B2': 'LG전자',
    'C4366C': 'LG전자',
    'CCFA00': 'LG전자',
    // Apple.
    '001B63': 'Apple',
    '001EC2': 'Apple',
    '002312': 'Apple',
    '002500': 'Apple',
    '0026BB': 'Apple',
    '3C0754': 'Apple',
    '40D32D': 'Apple',
    '60334B': 'Apple',
    '68967B': 'Apple',
    '7073CB': 'Apple',
    '78CA39': 'Apple',
    '7CD1C3': 'Apple',
    '8C5877': 'Apple',
    '90B0ED': 'Apple',
    'A4B197': 'Apple',
    'A8667F': 'Apple',
    'ACBC32': 'Apple',
    'B853AC': 'Apple',
    'BC926B': 'Apple',
    'D0817A': 'Apple',
    'DC2B2A': 'Apple',
    'F0DBF8': 'Apple',
    'F40F24': 'Apple',
    // Google / Nest.
    '3C5AB4': 'Google',
    '54604E': 'Google',
    'A47733': 'Google',
    'DACE9B': 'Google Nest',
    'F4F5D8': 'Google',
    'F4F5E8': 'Google Nest',
    // Amazon (Echo / Fire / Kindle).
    '0C47C9': 'Amazon',
    '34D270': 'Amazon',
    '44650D': 'Amazon',
    '68370E': 'Amazon',
    '747548': 'Amazon',
    'AC63BE': 'Amazon',
    'F0272D': 'Amazon',
    'FC65DE': 'Amazon',
    // Xiaomi.
    '286C07': 'Xiaomi',
    '3480B3': 'Xiaomi',
    '640980': 'Xiaomi',
    '7451BA': 'Xiaomi',
    '8CBEBE': 'Xiaomi',
    'A063F1': 'Xiaomi',
    'F8A45F': 'Xiaomi',
    // Huawei.
    '00E0FC': 'Huawei',
    '182C91': 'Huawei',
    '283CE4': 'Huawei',
    '48DB50': 'Huawei',
    '5CB395': 'Huawei',
    '844765': 'Huawei',
    'B41513': 'Huawei',
    // Intel (Wi-Fi/NIC in PCs & laptops).
    '001B21': 'Intel',
    '00A0C9': 'Intel',
    '3C9757': 'Intel',
    '54E1AD': 'Intel',
    '7CB27D': 'Intel',
    '94659C': 'Intel',
    '9C6B00': 'Intel',
    'A0A8CD': 'Intel',
    'B0227A': 'Intel',
    'E4A471': 'Intel',
    // Espressif (ESP32/ESP8266 — DIY & IoT).
    '240AC4': 'Espressif (IoT)',
    '30AEA4': 'Espressif (IoT)',
    '3C6105': 'Espressif (IoT)',
    '3C71BF': 'Espressif (IoT)',
    '4C11AE': 'Espressif (IoT)',
    '5CCF7F': 'Espressif (IoT)',
    '807D3A': 'Espressif (IoT)',
    '84F3EB': 'Espressif (IoT)',
    '8CAAB5': 'Espressif (IoT)',
    'A020A6': 'Espressif (IoT)',
    'AC0BFB': 'Espressif (IoT)',
    'B4E62D': 'Espressif (IoT)',
    'C44F33': 'Espressif (IoT)',
    'CC50E3': 'Espressif (IoT)',
    'DC4F22': 'Espressif (IoT)',
    'ECFABC': 'Espressif (IoT)',
    // Raspberry Pi.
    'B827EB': 'Raspberry Pi',
    'DCA632': 'Raspberry Pi',
    'E45F01': 'Raspberry Pi',
    '2CCF67': 'Raspberry Pi',
    'D83ADD': 'Raspberry Pi',
    // TP-Link.
    '003192': 'TP-Link',
    '1C61B4': 'TP-Link',
    '5091E3': 'TP-Link',
    '54AF97': 'TP-Link',
    '647002': 'TP-Link',
    'A42BB0': 'TP-Link',
    'C006C3': 'TP-Link',
    'EC086B': 'TP-Link',
    // ASUSTek.
    '00E018': 'ASUS',
    '107B44': 'ASUS',
    '2C56DC': 'ASUS',
    '385521': 'ASUS',
    '50465D': 'ASUS',
    'AC220B': 'ASUS',
    'D850E6': 'ASUS',
    // Netgear.
    '00146C': 'Netgear',
    '20E52A': 'Netgear',
    '3894ED': 'Netgear',
    '9CD36D': 'Netgear',
    'A040A0': 'Netgear',
    'C03F0E': 'Netgear',
    // Sony.
    '001A80': 'Sony',
    '104FA8': 'Sony',
    '3C0771': 'Sony',
    'D8D43C': 'Sony',
    'FC0FE6': 'Sony',
    // Microsoft (Surface / Xbox).
    '000D3A': 'Microsoft',
    '281878': 'Microsoft',
    '7C1E52': 'Microsoft',
    'C83F26': 'Microsoft',
    // Realtek (generic NIC/Wi-Fi in many devices).
    '00E04C': 'Realtek',
  };

  /// Resolves a manufacturer for [macAddress], or null when unknown or the
  /// address is locally administered (randomized/virtual).
  String? vendorFor(String? macAddress) {
    final oui = _normalizedOui(macAddress);
    if (oui == null) return null;
    if (_isLocallyAdministered(oui)) return null;
    return (_registry ?? _vendors)[oui];
  }

  /// Whether [macAddress] is locally administered — i.e. a privacy-randomized
  /// or virtual address whose OUI does not identify a real manufacturer.
  bool isRandomizedMac(String? macAddress) {
    final oui = _normalizedOui(macAddress);
    return oui != null && _isLocallyAdministered(oui);
  }

  static String? _normalizedOui(String? macAddress) {
    if (macAddress == null) return null;
    final compact = macAddress
        .replaceAll(RegExp('[^0-9A-Fa-f]'), '')
        .toUpperCase();
    if (compact.length < 6) return null;
    return compact.substring(0, 6);
  }

  static bool _isLocallyAdministered(String oui) {
    final firstOctet = int.tryParse(oui.substring(0, 2), radix: 16);
    if (firstOctet == null) return false;
    return firstOctet & 0x02 != 0;
  }
}
