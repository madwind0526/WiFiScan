import 'dart:convert';
import 'dart:io';

import 'package:wifi_scan/features/discovery/domain/router_dhcp_client.dart';

/// Read-only connector for a user-owned ipTIME router.
///
/// Logs in with credentials the user supplies (POST to `login_handler.cgi`),
/// keeps the returned session cookie, and fetches admin pages under
/// `timepro.cgi`. It never guesses passwords, never changes settings, and
/// never sends queried data anywhere. Dart's [HttpClient] tolerates the
/// router's HTTP/1.0 responses (verified against A6004NS-M).
class IptimeRouterConnector {
  IptimeRouterConnector({
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 8),
  }) : _client = httpClient ?? (HttpClient()..connectionTimeout = timeout);

  final HttpClient _client;
  final Duration timeout;

  static const _loginPath = '/sess-bin/login_handler.cgi';

  /// Logs in and returns the `efm_session_id` session token.
  ///
  /// Throws [RouterQueryException] on a wrong password or unreachable router.
  Future<String> login(RouterCredentials credentials) async {
    final uri = Uri.parse('http://${credentials.host}$_loginPath');
    // Field names match ipTIME's login form; captcha is assumed off (the
    // default for LAN-side admin login).
    final form = {
      'init_status': '1',
      'captcha_on': '0',
      'username': credentials.username.isEmpty ? 'admin' : credentials.username,
      'passwd': credentials.password,
      'default_passwd': '',
      'captcha_file': '',
      'captcha_code': '',
    };
    final body = form.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');

    final HttpClientResponse response;
    final String responseBody;
    try {
      final request = await _client.postUrl(uri).timeout(timeout);
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded',
      );
      // Match the browser's Referer (the login form page) — ipTIME checks it.
      request.headers.set(
        HttpHeaders.refererHeader,
        'http://${credentials.host}/sess-bin/login_session.cgi',
      );
      request.write(body);
      response = await request.close().timeout(timeout);
      responseBody = await response.transform(latin1.decoder).join();
    } on Exception catch (_) {
      throw const RouterQueryException('공유기에 연결하지 못했습니다. 주소와 연결 상태를 확인하세요.');
    }

    // On failure ipTIME bounces back to the login page (no session set);
    // success redirects elsewhere and sets an efm_session_id cookie.
    if (responseBody.contains('login_session') ||
        responseBody.contains('noauto')) {
      throw const RouterQueryException(
        '공유기 로그인에 실패했습니다. 관리자 아이디·비밀번호를 확인하세요. '
        '여러 번 실패하면 공유기가 캡차를 요구할 수 있습니다.',
      );
    }
    final session = _sessionFromHeaders(response) ?? _sessionCookie(response);
    if (session == null || session.isEmpty) {
      throw const RouterQueryException(
        '로그인은 되었지만 세션 정보를 읽지 못했습니다. 잠시 후 다시 시도하세요.',
      );
    }
    return session;
  }

  /// Extracts `efm_session_id` directly from the raw Set-Cookie header, which
  /// is more tolerant of the router's non-standard HTTP than [
  /// HttpClientResponse.cookies].
  static String? _sessionFromHeaders(HttpClientResponse response) {
    final raw = response.headers[HttpHeaders.setCookieHeader];
    if (raw == null) return null;
    final match = RegExp(
      r'efm_session_id=([^;\s]+)',
    ).firstMatch(raw.join('; '));
    return match?.group(1);
  }

  /// Fetches an admin page under `timepro.cgi` with an active [session].
  ///
  /// [tmenu]/[smenu] select the admin page. Returns the raw response body for
  /// a parser to consume; used both by [readDhcpClients] and by endpoint
  /// discovery against a live device.
  Future<String> fetchAdminPage({
    required String host,
    required String session,
    required String tmenu,
    required String smenu,
    Map<String, String> extra = const {},
  }) async {
    final query = {'tmenu': tmenu, 'smenu': smenu, ...extra};
    final uri = Uri.parse(
      'http://$host/sess-bin/timepro.cgi',
    ).replace(queryParameters: query);
    try {
      final request = await _client.getUrl(uri).timeout(timeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.cookieHeader, 'efm_session_id=$session');
      request.headers.set(HttpHeaders.refererHeader, 'http://$host/');
      final response = await request.close().timeout(timeout);
      final text = await response.transform(latin1.decoder).join();
      if (text.contains('login_session') || text.contains('session_timeout')) {
        throw const RouterQueryException('공유기 세션이 만료되었습니다. 다시 시도하세요.');
      }
      return text;
    } on RouterQueryException {
      rethrow;
    } on Exception catch (_) {
      throw const RouterQueryException('공유기 관리 정보를 읽지 못했습니다.');
    }
  }

  /// Endpoints under `timepro.cgi` that ipTIME firmwares expose the DHCP /
  /// connected-device list on. Tried in order until one yields entries, since
  /// the exact page varies by firmware.
  static const List<(String, String)> dhcpPageCandidates = [
    ('netconf', 'lansetup'),
    ('netconf', 'dhcpserverset'),
    ('netconf', 'dhcpsummary'),
    ('iframe', 'internetstatus'),
  ];

  /// Reads the router's DHCP client list with an active [session].
  ///
  /// Returns an empty list if the router exposes none of the known pages; the
  /// caller treats that as "no data" rather than an error.
  Future<List<RouterDhcpClient>> readDhcpClients({
    required String host,
    required String session,
  }) async {
    for (final (tmenu, smenu) in dhcpPageCandidates) {
      try {
        final body = await fetchAdminPage(
          host: host,
          session: session,
          tmenu: tmenu,
          smenu: smenu,
        );
        final clients = parseDhcpClients(body);
        if (clients.isNotEmpty) return clients;
      } on RouterQueryException {
        rethrow;
      } catch (_) {
        // Try the next candidate page.
      }
    }
    return const [];
  }

  static final _ipv4 = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');
  static final _mac = RegExp(
    r'\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b',
  );

  /// Extracts DHCP client rows from an ipTIME admin page.
  ///
  /// Firmware differs (HTML tables vs JavaScript arrays vs delimited strings),
  /// so this splits the body into records and keeps any record carrying both
  /// an IPv4 and a MAC, treating the leftover text as the hostname. This is
  /// format-agnostic within ipTIME's page shapes.
  static List<RouterDhcpClient> parseDhcpClients(String body) {
    final records = body.split(RegExp(r'</tr>|;|\n', caseSensitive: false));
    final byIp = <String, RouterDhcpClient>{};
    for (final record in records) {
      final mac = _mac.firstMatch(record)?.group(0);
      if (mac == null) continue;
      final ip = _ipv4
          .allMatches(record)
          .map((m) => m.group(0)!)
          .where(_isUsableIpv4)
          .cast<String?>()
          .firstWhere((_) => true, orElse: () => null);
      if (ip == null) continue;
      final hostname = _extractHostname(record, ip: ip, mac: mac);
      byIp[ip] = RouterDhcpClient(
        ipAddress: ip,
        macAddress: mac,
        hostname: hostname,
      );
    }
    return byIp.values.toList(growable: false);
  }

  static bool _isUsableIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255) return false;
    }
    return ip != '0.0.0.0' && ip != '255.255.255.255';
  }

  static String? _extractHostname(
    String record, {
    required String ip,
    required String mac,
  }) {
    var text = record
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(ip, ' ')
        .replaceAll(mac, ' ');
    // Drop other addresses (subnet mask, lease-time numbers) and quotes.
    text = text.replaceAll(_ipv4, ' ').replaceAll(RegExp(r'["\x27,|]'), ' ');
    final tokens = text
        .split(RegExp(r'\s+'))
        .map((t) => t.trim())
        .where(_looksLikeHostname)
        .toList();
    if (tokens.isEmpty) return null;
    // The longest hostname-shaped token is the most likely device name.
    tokens.sort((a, b) => b.length.compareTo(a.length));
    return tokens.first;
  }

  static final _hostnameToken = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{1,}$');
  static final _hasLetter = RegExp('[A-Za-z]');

  static bool _looksLikeHostname(String token) {
    return _hostnameToken.hasMatch(token) && _hasLetter.hasMatch(token);
  }

  void close() => _client.close(force: true);

  static String? _sessionCookie(HttpClientResponse response) {
    for (final cookie in response.cookies) {
      if (cookie.name == 'efm_session_id' && cookie.value.isNotEmpty) {
        return cookie.value;
      }
    }
    return null;
  }
}

/// Supplies router credentials from local environment variables, so the admin
/// password is never hardcoded or committed.
///
/// - `WIFISCAN_ROUTER_PW`   (required) admin password
/// - `WIFISCAN_ROUTER_USER` (optional) admin id, defaults to `admin`
/// - `WIFISCAN_ROUTER_HOST` (optional) router address, defaults to [gateway]
class EnvRouterCredentialsSource {
  const EnvRouterCredentialsSource({Map<String, String>? environment})
    : _env = environment;

  final Map<String, String>? _env;

  RouterCredentials? credentials({String? gateway}) {
    final env = _env ?? Platform.environment;
    final password = env['WIFISCAN_ROUTER_PW'] ?? '';
    if (password.isEmpty) return null;
    final host = (env['WIFISCAN_ROUTER_HOST'] ?? gateway ?? '').trim();
    if (host.isEmpty) return null;
    return RouterCredentials(
      host: host,
      username: (env['WIFISCAN_ROUTER_USER'] ?? 'admin').trim(),
      password: password,
    );
  }
}
