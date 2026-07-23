import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:wifi_scan/features/discovery/domain/router_connector.dart';
import 'package:wifi_scan/features/discovery/domain/router_dhcp_client.dart';

/// Read-only connector for a user-owned ipTIME router.
///
/// Logs in with credentials the user supplies (POST to `login_handler.cgi`),
/// keeps the returned session cookie, and fetches admin pages under
/// `timepro.cgi`. It never guesses passwords, never changes settings, and
/// never sends queried data anywhere. Dart's [HttpClient] tolerates the
/// router's HTTP/1.0 responses (verified against A6004NS-M).
class IptimeRouterConnector implements RouterConnector {
  IptimeRouterConnector({
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 8),
  }) : _client = httpClient ?? (HttpClient()..connectionTimeout = timeout);

  final HttpClient _client;
  final Duration timeout;

  @override
  String get id => 'iptime';

  @override
  String get displayName => 'ipTIME';

  /// LAN-side ipTIME admin login has no captcha by default, so saved
  /// credentials can log in without prompting the user.
  @override
  bool get requiresCaptcha => false;

  static const _loginPath = '/sess-bin/login_handler.cgi';
  static const _loginPagePath = '/sess-bin/login_session.cgi';

  /// Markers ipTIME firmwares serve on their root or login page.
  static const _fingerprints = [
    'sess-bin',
    'login_session',
    'iptime',
    'timepro',
    'efm_session',
  ];

  /// Pages probed for those markers. Newer firmware answers `/` with a bare
  /// meta-refresh to `/login/login.cgi` and only that page names `sess-bin`
  /// (verified against the live A6004NS-M); older ones expose the session CGI
  /// directly.
  static const _probePaths = ['/', '/login/login.cgi', _loginPagePath];

  /// Detection probes stay short so an unreachable host fails fast.
  static const _probeTimeout = Duration(seconds: 4);

  @override
  Future<bool> matches(String host) async {
    for (final path in _probePaths) {
      final text = await _probe(host, path);
      if (text == null) continue;
      if (_fingerprints.any(text.contains)) return true;
    }
    return false;
  }

  /// GETs [path] read-only, returning body plus redirect target in lower case,
  /// or null when the host does not answer.
  Future<String?> _probe(String host, String path) async {
    try {
      final request = await _client
          .getUrl(Uri.parse('http://$host$path'))
          .timeout(_probeTimeout);
      request.followRedirects = false;
      final response = await request.close().timeout(_probeTimeout);
      final body = await response.transform(latin1.decoder).join();
      final location = response.headers.value(HttpHeaders.locationHeader) ?? '';
      return '$body $location'.toLowerCase();
    } on Exception catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List> fetchCaptcha(String host) {
    throw UnsupportedError('ipTIME 로그인은 캡차를 사용하지 않습니다.');
  }

  /// Logs in and returns the `efm_session_id` session token.
  ///
  /// [captcha] is ignored: LAN-side ipTIME login runs with captcha off.
  /// Throws [RouterQueryException] on a wrong password or unreachable router.
  @override
  Future<String> login({
    required String host,
    required String username,
    required String password,
    String captcha = '',
  }) async {
    final uri = Uri.parse('http://$host$_loginPath');
    // Field names match ipTIME's login form; captcha is assumed off (the
    // default for LAN-side admin login).
    final form = {
      'init_status': '1',
      'captcha_on': '0',
      'username': username.isEmpty ? 'admin' : username,
      'passwd': password,
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
    final bodyBytes = utf8.encode(body);

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
        'http://$host$_loginPagePath',
      );
      // The router's HTTP/1.0 server rejects chunked bodies (400), so send a
      // fixed Content-Length instead of streaming.
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);
      response = await request.close().timeout(timeout);
      responseBody = await response.transform(latin1.decoder).join();
    } on Exception catch (_) {
      throw const RouterQueryException('공유기에 연결하지 못했습니다. 주소와 연결 상태를 확인하세요.');
    }

    // ipTIME delivers the session in the response BODY as a JavaScript
    // `setCookie('<id>')` call (the browser runs it to set efm_session_id),
    // not as a Set-Cookie header. On failure the body bounces back to the
    // login page instead.
    final session = _sessionFromBody(responseBody);
    if (session != null) return session;
    if (responseBody.contains('login_session') ||
        responseBody.contains('noauto')) {
      throw const RouterQueryException(
        '공유기 로그인에 실패했습니다. 관리자 아이디·비밀번호를 확인하세요. '
        '여러 번 실패하면 공유기가 캡차를 요구할 수 있습니다.',
      );
    }
    // Fall back to header/cookie parsing for other firmwares.
    final headerSession = _sessionFromHeaders(response) ?? _sessionCookie(response);
    if (headerSession != null && headerSession.isNotEmpty) return headerSession;
    throw const RouterQueryException(
      '로그인은 되었지만 세션 정보를 읽지 못했습니다. 잠시 후 다시 시도하세요.',
    );
  }

  /// Extracts the session id from ipTIME's `setCookie('<id>')` script body.
  static String? _sessionFromBody(String body) {
    final match = RegExp(r"setCookie\('([^']+)'\)").firstMatch(body);
    final id = match?.group(1);
    return (id != null && id.isNotEmpty) ? id : null;
  }

  /// Extracts `efm_session_id` directly from the raw Set-Cookie header (for
  /// firmwares that use a header instead of the script body).
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
  /// a parser to consume; used both by [readDevices] and by endpoint
  /// discovery against a live device.
  Future<String> fetchAdminPage({
    required String host,
    required String session,
    required String tmenu,
    required String smenu,
    Map<String, String> extra = const {},
    String? referer,
  }) async {
    final query = {'tmenu': tmenu, 'smenu': smenu, ...extra};
    final uri = Uri.parse(
      'http://$host/sess-bin/timepro.cgi',
    ).replace(queryParameters: query);
    try {
      final request = await _client.getUrl(uri).timeout(timeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.cookieHeader, 'efm_session_id=$session');
      request.headers.set(
        HttpHeaders.refererHeader,
        referer ?? 'http://$host/',
      );
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

  /// Pages that hold the DHCP / connected-device list, most-specific first.
  /// A6004NS-M serves it from the `lan_pcinfo_status` iframe; the rest are
  /// fallbacks for other firmwares.
  static const List<(String, String)> dhcpPageCandidates = [
    ('iframe', 'lan_pcinfo_status'),
    ('netconf', 'lansetup'),
    ('netconf', 'dhcpserverset'),
  ];

  /// Reads the router's DHCP client list with an active [session].
  ///
  /// Returns an empty list if the router exposes none of the known pages; the
  /// caller treats that as "no data" rather than an error.
  @override
  Future<List<RouterDhcpClient>> readDevices({
    required String host,
    required String session,
  }) async {
    // The status iframe expects the pc-info page as its referer.
    final referer =
        'http://$host/sess-bin/timepro.cgi?tmenu=iframe&smenu=lan_pcinfo';
    for (final (tmenu, smenu) in dhcpPageCandidates) {
      try {
        final body = await fetchAdminPage(
          host: host,
          session: session,
          tmenu: tmenu,
          smenu: smenu,
          referer: referer,
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

  // A6004NS-M stores each lease as hidden inputs `m<N>`/`i<N>`/`h<N>`
  // (MAC/IP/hostname), e.g. `<input type=hidden name=m0 value="AA:...">`.
  static final _leaseField = RegExp(
    r'name=["' "'" r']?([mih])(\d+)["' "'" r']?\s+value="([^"]*)"',
    caseSensitive: false,
  );

  /// Extracts DHCP client rows from an ipTIME admin page.
  ///
  /// Prefers the A6004NS-M hidden-input triplet format; otherwise falls back
  /// to a format-agnostic scan that keeps any record carrying both an IPv4 and
  /// a MAC (HTML tables, JS arrays, delimited strings).
  static List<RouterDhcpClient> parseDhcpClients(String body) {
    final triplets = _parseLeaseFields(body);
    if (triplets.isNotEmpty) return triplets;

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

  static List<RouterDhcpClient> _parseLeaseFields(String body) {
    final macByIdx = <String, String>{};
    final ipByIdx = <String, String>{};
    final hostByIdx = <String, String>{};
    for (final match in _leaseField.allMatches(body)) {
      final field = match.group(1)!.toLowerCase();
      final index = match.group(2)!;
      final value = match.group(3)!.trim();
      if (value.isEmpty) continue;
      switch (field) {
        case 'm':
          macByIdx[index] = value;
        case 'i':
          ipByIdx[index] = value;
        case 'h':
          hostByIdx[index] = value;
      }
    }
    final byIp = <String, RouterDhcpClient>{};
    for (final index in macByIdx.keys) {
      final mac = macByIdx[index];
      final ip = ipByIdx[index];
      if (mac == null || ip == null || !_isUsableIpv4(ip)) continue;
      final host = hostByIdx[index];
      byIp[ip] = RouterDhcpClient(
        ipAddress: ip,
        macAddress: mac,
        hostname: (host == null || host.isEmpty) ? null : host,
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

  @override
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
