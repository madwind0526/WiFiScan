/// Fills in passphrases from [saved] for profiles that carry none yet.
///
/// A password the user already set is never replaced — only blanks are filled.
/// That keeps importing what the OS has stored from ever clobbering something
/// typed by hand, so an import can be re-run safely.
List<NetworkProfile> profilesWithMissingPasswordsFilled(
  List<NetworkProfile> profiles,
  Map<String, String> saved,
) {
  if (saved.isEmpty) return profiles;
  return [
    for (final profile in profiles)
      if ((profile.password ?? '').isEmpty &&
          (saved[profile.ssid] ?? '').isNotEmpty)
        profile.copyWith(password: saved[profile.ssid])
      else
        profile,
  ];
}

class NetworkProfile {
  const NetworkProfile({
    required this.id,
    required this.ssid,
    required this.displayName,
    this.password,
    this.lastScannedAt,
  });

  final String id;
  final String ssid;
  final String displayName;
  final String? password;
  final DateTime? lastScannedAt;

  NetworkProfile copyWith({
    String? id,
    String? ssid,
    String? displayName,
    String? password,
    DateTime? lastScannedAt,
  }) {
    return NetworkProfile(
      id: id ?? this.id,
      ssid: ssid ?? this.ssid,
      displayName: displayName ?? this.displayName,
      password: password ?? this.password,
      lastScannedAt: lastScannedAt ?? this.lastScannedAt,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'ssid': ssid,
    'displayName': displayName,
    if (lastScannedAt != null)
      'lastScannedAt': lastScannedAt!.toIso8601String(),
  };

  factory NetworkProfile.fromJson(Map<String, Object?> json) {
    return NetworkProfile(
      id: json['id']?.toString() ?? json['ssid']?.toString() ?? 'network',
      ssid: json['ssid']?.toString() ?? '',
      displayName:
          json['displayName']?.toString() ?? json['ssid']?.toString() ?? '',
      lastScannedAt: DateTime.tryParse(json['lastScannedAt']?.toString() ?? ''),
    );
  }
}
