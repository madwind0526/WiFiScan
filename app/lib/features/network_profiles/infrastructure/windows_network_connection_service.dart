import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';
import 'package:wifi_scan/features/network_profiles/application/network_connection_service.dart';
import 'package:wifi_scan/features/network_profiles/domain/network_profile.dart';

class WindowsNetworkConnectionService implements NetworkConnectionService {
  const WindowsNetworkConnectionService({
    this.pollInterval = const Duration(seconds: 2),
  });

  final Duration pollInterval;

  @override
  Future<List<NetworkProfile>> discoverAvailableProfiles() async {
    final result = await _runNetshQuery('wlan show profiles');
    if (result.exitCode != 0) {
      throw const NetworkConnectionException('Windows Wi-Fi 프로필을 읽지 못했습니다.');
    }
    final names = _parseProfileNames(result.stdout.toString());
    return [
      for (final ssid in names)
        NetworkProfile(id: ssid, ssid: ssid, displayName: ssid),
    ];
  }

  /// Reads the passphrases Windows already has saved, keyed by SSID.
  ///
  /// Uses `netsh wlan export profile key=clear`, which writes one XML per
  /// saved profile into a folder we own. That form takes no SSID argument, so
  /// nothing user-controlled is ever interpolated into a command, and unlike
  /// `show profile ... key=clear` its output is not localized. The exported
  /// files hold plaintext passphrases, so they are read once and the folder is
  /// deleted immediately afterwards — nothing is left on disk and nothing
  /// leaves the machine.
  static const _exportFolderPrefix = 'wifiscan_wlan';

  @override
  Future<Map<String, String>> savedPasswords() async {
    // A run killed before its cleanup would leave plaintext behind, so clear
    // any folder an earlier run failed to remove before adding another.
    await _sweepStaleExports();
    final Directory folder;
    try {
      folder = await Directory.systemTemp.createTemp(_exportFolderPrefix);
    } on IOException {
      return const {};
    }
    try {
      final result = await Process.run('netsh', [
        'wlan',
        'export',
        'profile',
        'key=clear',
        'folder=${folder.path}',
      ]);
      if (result.exitCode != 0) return const {};
      final passwords = <String, String>{};
      await for (final entity in folder.list()) {
        if (entity is! File || !entity.path.toLowerCase().endsWith('.xml')) {
          continue;
        }
        final parsed = parseExportedProfile(await entity.readAsString());
        if (parsed != null) passwords[parsed.$1] = parsed.$2;
      }
      return passwords;
    } catch (_) {
      return const {};
    } finally {
      try {
        await folder.delete(recursive: true);
      } catch (_) {
        // A leftover temp folder must not break profile loading; the next run
        // sweeps it.
      }
    }
  }

  /// Deletes export folders a previous run left behind.
  Future<void> _sweepStaleExports() async {
    try {
      await for (final entity in Directory.systemTemp.list()) {
        if (entity is! Directory) continue;
        final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (!name.startsWith(_exportFolderPrefix)) continue;
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          // Another instance may hold it open; leave it for next time.
        }
      }
    } catch (_) {
      // An unreadable temp directory must not block the import.
    }
  }

  /// Extracts `(ssid, passphrase)` from an exported WLAN profile.
  ///
  /// Parsed as XML rather than scraped with a regex, because Windows escapes
  /// the payload: a passphrase of `p&w` is written `p&amp;w`, and reading the
  /// raw text would store a passphrase that silently fails to connect.
  ///
  /// Returns null when there is nothing usable to import: open networks carry
  /// no key, and without elevation Windows may leave the key DPAPI-protected,
  /// in which case `keyMaterial` is an encrypted blob rather than the
  /// passphrase.
  static (String, String)? parseExportedProfile(String xml) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(xml);
    } on XmlException {
      return null;
    }
    final names = document.findAllElements('name');
    if (names.isEmpty) return null;
    final ssid = names.first.innerText.trim();
    if (ssid.isEmpty) return null;

    final keys = document.findAllElements('sharedKey');
    if (keys.isEmpty) return null;
    final sharedKey = keys.first;
    final isProtected =
        sharedKey.getElement('protected')?.innerText.trim().toLowerCase() ==
        'true';
    if (isProtected) return null;
    final keyType = sharedKey.getElement('keyType')?.innerText.trim();
    if (keyType != null && keyType.toLowerCase() != 'passphrase') return null;
    // Not trimmed: a passphrase may legitimately start or end with a space.
    final key = sharedKey.getElement('keyMaterial')?.innerText;
    if (key == null || key.isEmpty) return null;
    return (ssid, key);
  }

  /// Runs a read-only, argument-free `netsh` query with a forced UTF-8
  /// console codepage.
  ///
  /// `netsh`'s output text and byte encoding both follow the console
  /// codepage of the calling process. When Dart spawns it directly (no
  /// attached console), that codepage can default to the OS locale's DBCS
  /// codepage (e.g. CP949 on Korean Windows), which Dart's default decoding
  /// does not reliably reverse — garbling every localized label. Routing
  /// through `cmd /c chcp 65001` forces a UTF-8 codepage, which also makes
  /// `netsh` fall back to English resource strings, giving consistent,
  /// correctly-decoded output. Only ever call this with a fixed, literal
  /// [subcommand] — never interpolate an SSID or other untrusted value into
  /// it, since it is executed through a shell.
  Future<ProcessResult> _runNetshQuery(String subcommand) {
    return Process.run('cmd', [
      '/c',
      'chcp 65001 >NUL && netsh $subcommand',
    ], stdoutEncoding: utf8);
  }

  /// Extracts profile names from `netsh wlan show profiles` output.
  ///
  /// Matches structurally (an indented `label : name` line) instead of the
  /// localized label text, as a second layer of defense on top of
  /// [_runNetshQuery]'s codepage forcing.
  static Set<String> _parseProfileNames(String output) {
    final names = <String>{};
    for (final line in output.split(RegExp(r'\r?\n'))) {
      final match = RegExp(r'^\s+\S.*:\s*(.+)$').firstMatch(line);
      if (match == null) continue;
      final ssid = match.group(1)!.trim();
      if (ssid.isEmpty || ssid == '<None>') continue;
      names.add(ssid);
    }
    return names;
  }

  /// Whether Windows already has a saved WLAN profile for [ssid].
  ///
  /// A profile that already exists may be scoped to "all users" with its own
  /// security settings (e.g. WPA3), which [connect] must not try to overwrite
  /// via a hardcoded WPA2PSK XML profile — Windows rejects cross-scope
  /// overwrites, so re-registering a known profile only breaks the connection.
  Future<bool> _profileExists(String ssid) async {
    try {
      final result = await _runNetshQuery('wlan show profiles');
      if (result.exitCode != 0) return false;
      return _parseProfileNames(result.stdout.toString()).contains(ssid);
    } catch (_) {
      return false;
    }
  }

  /// SSIDs currently visible in Windows' Wi-Fi scan cache.
  Future<Set<String>> _visibleSsids() async {
    try {
      final result = await _runNetshQuery('wlan show networks');
      if (result.exitCode != 0) return const {};
      final names = <String>{};
      for (final match in RegExp(
        r'^SSID\s+\d+\s*:\s*(.+)$',
        multiLine: true,
      ).allMatches(result.stdout.toString())) {
        final name = match.group(1)!.trim();
        if (name.isNotEmpty) names.add(name);
      }
      return names;
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<String?> currentSsid() async {
    final result = await _runNetshQuery('wlan show interfaces');
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
  Future<WifiBand> currentBand() async {
    try {
      final result = await _runNetshQuery('wlan show interfaces');
      if (result.exitCode != 0) return WifiBand.unknown;
      return parseBand(result.stdout.toString());
    } catch (_) {
      return WifiBand.unknown;
    }
  }

  /// Extracts the radio band from `netsh wlan show interfaces` output.
  ///
  /// Prefers an explicit localized band field, then falls back to the channel
  /// number.
  static WifiBand parseBand(String output) {
    for (final line in output.split(RegExp(r'\r?\n'))) {
      final bandMatch = RegExp(
        r'^\s*(?:band|대역)\s*:\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (bandMatch != null) {
        final value = bandMatch.group(1)!;
        if (value.contains('6')) return WifiBand.ghz6;
        if (value.contains('5')) return WifiBand.ghz5;
        if (value.contains('2.4') || value.contains('2,4')) {
          return WifiBand.ghz24;
        }
      }
    }
    for (final line in output.split(RegExp(r'\r?\n'))) {
      final channelMatch = RegExp(
        r'^\s*(?:channel|채널)\s*:\s*(\d+)',
        caseSensitive: false,
      ).firstMatch(line);
      if (channelMatch != null) {
        final channel = int.parse(channelMatch.group(1)!);
        if (channel >= 1 && channel <= 14) return WifiBand.ghz24;
        if (channel >= 32 && channel <= 177) return WifiBand.ghz5;
      }
    }
    return WifiBand.unknown;
  }

  @override
  Future<void> connect(NetworkProfile profile) async {
    File? temporaryProfile;
    final hasPassword =
        profile.password != null && profile.password!.isNotEmpty;
    final knownToWindows = hasPassword && await _profileExists(profile.ssid);
    if (hasPassword && !knownToWindows) {
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
    final result = await _connectWithScanRetry(profile.ssid);
    if (temporaryProfile != null && await temporaryProfile.exists()) {
      await temporaryProfile.delete();
    }
    if (result.exitCode != 0) {
      final visible = (await _visibleSsids()).contains(profile.ssid);
      throw NetworkConnectionException(
        visible
            ? 'Windows에 저장된 Wi-Fi 프로필로 ${profile.ssid}에 연결하지 못했습니다. '
                  '먼저 Windows Wi-Fi 설정에서 한 번 연결해 주세요.'
            : '${profile.ssid} 신호가 현재 위치에서 잡히지 않습니다. 공유기와 더 가까운 곳에서 다시 시도하세요.',
      );
    }
    for (var attempt = 0; attempt < 15; attempt++) {
      await Future<void>.delayed(pollInterval);
      if (await currentSsid() == profile.ssid) return;
    }
    throw NetworkConnectionException('${profile.ssid} 연결이 시간 초과되었습니다.');
  }

  /// Connects to [ssid], refreshing Windows' Wi-Fi scan cache between
  /// attempts.
  ///
  /// `netsh wlan connect` only succeeds if the SSID is already in the
  /// driver's cached scan list; it does not scan on demand. A weak-signal or
  /// distant AP (e.g. a second router elsewhere in the house) can be briefly
  /// absent from that cache and needs a few scan cycles to reappear.
  Future<ProcessResult> _connectWithScanRetry(String ssid) async {
    ProcessResult result = await Process.run('netsh', [
      'wlan',
      'connect',
      'name=$ssid',
    ]);
    for (var attempt = 0; result.exitCode != 0 && attempt < 4; attempt++) {
      await Process.run('netsh', ['wlan', 'show', 'networks']);
      await Future<void>.delayed(const Duration(seconds: 2));
      result = await Process.run('netsh', ['wlan', 'connect', 'name=$ssid']);
    }
    return result;
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
