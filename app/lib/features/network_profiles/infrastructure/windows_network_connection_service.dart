import 'dart:io';

import 'package:wifi_scan/features/network_profiles/application/network_connection_service.dart';
import 'package:wifi_scan/features/network_profiles/domain/network_profile.dart';

class WindowsNetworkConnectionService implements NetworkConnectionService {
  const WindowsNetworkConnectionService({
    this.pollInterval = const Duration(seconds: 2),
  });

  final Duration pollInterval;

  @override
  Future<List<NetworkProfile>> discoverAvailableProfiles() async {
    final result = await Process.run('netsh', ['wlan', 'show', 'profiles']);
    if (result.exitCode != 0) {
      throw const NetworkConnectionException('Windows Wi-Fi 프로필을 읽지 못했습니다.');
    }
    final profiles = <NetworkProfile>[];
    final seen = <String>{};
    for (final line in result.stdout.toString().split(RegExp(r'\r?\n'))) {
      final match = RegExp(r':\s*(.+)$').firstMatch(line);
      final key = line.toLowerCase();
      if (match == null || !(key.contains('profile') || line.contains('프로필'))) {
        continue;
      }
      final ssid = match.group(1)!.trim();
      if (ssid.isEmpty || !seen.add(ssid)) continue;
      profiles.add(NetworkProfile(id: ssid, ssid: ssid, displayName: ssid));
    }
    return profiles;
  }

  @override
  Future<String?> currentSsid() async {
    final result = await Process.run('netsh', ['wlan', 'show', 'interfaces']);
    if (result.exitCode != 0) return null;
    for (final line in result.stdout.toString().split(RegExp(r'\r?\n'))) {
      final match = RegExp(
        r'^\s*SSID\s*:\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (match != null) return match.group(1)!.trim();
    }
    return null;
  }

  @override
  Future<void> connect(NetworkProfile profile) async {
    File? temporaryProfile;
    if (profile.password != null && profile.password!.isNotEmpty) {
      temporaryProfile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}wifiscan_${DateTime.now().microsecondsSinceEpoch}.xml',
      );
      await temporaryProfile.writeAsString(_profileXml(profile));
      final addResult = await Process.run('netsh', [
        'wlan',
        'add',
        'profile',
        'filename=${temporaryProfile.path}',
        'user=current',
      ]);
      if (addResult.exitCode != 0) {
        try {
          await temporaryProfile.delete();
        } catch (_) {
          // The temporary credential file is best-effort cleanup.
        }
        throw NetworkConnectionException(
          '${profile.ssid} Wi-Fi 프로필을 Windows에 등록하지 못했습니다.',
        );
      }
    }
    final result = await Process.run('netsh', [
      'wlan',
      'connect',
      'name=${profile.ssid}',
    ]);
    if (temporaryProfile != null && await temporaryProfile.exists()) {
      await temporaryProfile.delete();
    }
    if (result.exitCode != 0) {
      throw NetworkConnectionException(
        'Windows에 저장된 Wi-Fi 프로필로 ${profile.ssid}에 연결하지 못했습니다. '
        '먼저 Windows Wi-Fi 설정에서 한 번 연결해 주세요.',
      );
    }
    for (var attempt = 0; attempt < 15; attempt++) {
      await Future<void>.delayed(pollInterval);
      if (await currentSsid() == profile.ssid) return;
    }
    throw NetworkConnectionException('${profile.ssid} 연결이 시간 초과되었습니다.');
  }

  @override
  Future<void> restore(String? ssid) async {
    if (ssid == null || ssid.isEmpty) return;
    await connect(NetworkProfile(id: ssid, ssid: ssid, displayName: ssid));
  }

  String _profileXml(NetworkProfile profile) {
    final ssid = _xmlEscape(profile.ssid);
    final password = _xmlEscape(profile.password ?? '');
    return '''<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>$ssid</name>
  <SSIDConfig><SSID><name>$ssid</name></SSID></SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>manual</connectionMode>
  <MSM>
    <security>
      <authEncryption><authentication>WPA2PSK</authentication><encryption>AES</encryption><useOneX>false</useOneX></authEncryption>
      <sharedKey><keyType>passPhrase</keyType><protected>false</protected><keyMaterial>$password</keyMaterial></sharedKey>
    </security>
  </MSM>
</WLANProfile>''';
  }

  String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
