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
    try {
      final request = await _client.postUrl(uri).timeout(timeout);
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded',
      );
      request.headers.set(HttpHeaders.refererHeader, 'http://${credentials.host}/');
      request.write(body);
      response = await request.close().timeout(timeout);
    } on Exception catch (_) {
      throw const RouterQueryException('공유기에 연결하지 못했습니다. 주소와 연결 상태를 확인하세요.');
    }

    final session = _sessionCookie(response);
    await response.drain<void>();
    if (session == null || session.isEmpty) {
      throw const RouterQueryException(
        '공유기 로그인에 실패했습니다. 관리자 아이디와 비밀번호를 확인하세요.',
      );
    }
    return session;
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
