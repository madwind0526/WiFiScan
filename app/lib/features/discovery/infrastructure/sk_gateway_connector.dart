import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:wifi_scan/features/discovery/domain/router_dhcp_client.dart';

/// Read-only connector for a user-owned SK Broadband gateway (e.g. GW-ME6110).
///
/// The device uses a captcha the user must read, and hashes credentials with
/// SHA-256 client-side. This connector never solves the captcha itself — the
/// user types it — and only reads the connected-device list. It never changes
/// settings or sends data anywhere.
///
/// Login (`/goform/mcr_verifyLoginPasswd`), with `c = captcha.toLowerCase()`:
///   id         = sha256(userid)
///   passwd     = sha256(c + sha256(password) + c)
///   captchatext= sha256(c + c + c + c)
/// On success the server sets an `MCRSESSIONID` cookie; the device list lives
/// in `/asp/basic_ip_list.html` as a `szIPInfo` string of `ip,mac,name,port`
/// entries separated by `;`.
class SkGatewayConnector {
  SkGatewayConnector({
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 8),
  }) : _client = httpClient ?? (HttpClient()..connectionTimeout = timeout);

  final HttpClient _client;
  final Duration timeout;

  /// Fetches the current captcha image for the user to read.
  Future<Uint8List> fetchCaptcha(String host) async {
    try {
      final request = await _client
          .getUrl(Uri.parse('http://$host/captcha.png'))
          .timeout(timeout);
      request.headers.set(HttpHeaders.refererHeader, 'http://$host/start.asp');
      final response = await request.close().timeout(timeout);
      final builder = BytesBuilder();
      await for (final chunk in response) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (bytes.isEmpty) {
        throw const RouterQueryException('공유기 캡차 이미지를 불러오지 못했습니다.');
      }
      return bytes;
    } on RouterQueryException {
      rethrow;
    } on Exception catch (_) {
      throw const RouterQueryException('공유기에 연결하지 못했습니다. 주소를 확인하세요.');
    }
  }

  /// Logs in with the user-typed [captcha] and returns the `MCRSESSIONID`.
  Future<String> login({
    required String host,
    required String username,
    required String password,
    required String captcha,
  }) async {
    final c = captcha.trim().toLowerCase();
    final idHash = await _sha256Hex(username);
    final passHash = await _sha256Hex(password);
    final passwdHash = await _sha256Hex('$c$passHash$c');
    final captchaHash = await _sha256Hex('$c$c$c$c');
    final body =
        'id=${Uri.encodeQueryComponent(idHash)}'
        '&passwd=${Uri.encodeQueryComponent(passwdHash)}'
        '&captchatext=${Uri.encodeQueryComponent(captchaHash)}';
    final bodyBytes = utf8.encode(body);

    final HttpClientResponse response;
    final String responseBody;
    try {
      final request = await _client
          .postUrl(Uri.parse('http://$host/goform/mcr_verifyLoginPasswd'))
          .timeout(timeout);
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded',
      );
      request.headers.set(HttpHeaders.refererHeader, 'http://$host/start.asp');
      // HTTP/1.0 server rejects chunked bodies, so set an explicit length.
      request.contentLength = bodyBytes.length;
      request.add(bodyBytes);
      response = await request.close().timeout(timeout);
      responseBody = await response.transform(latin1.decoder).join();
    } on Exception catch (_) {
      throw const RouterQueryException('공유기에 연결하지 못했습니다.');
    }

    if (responseBody.contains('맞지 않습니다') ||
        responseBody.contains('start.asp')) {
      throw const RouterQueryException(
        '로그인에 실패했습니다. 아이디·비밀번호·캡차를 확인하세요. '
        '캡차는 화면 그대로 대소문자까지 정확히 입력하세요.',
      );
    }
    final session = _sessionFromHeaders(response);
    if (session == null || session.isEmpty) {
      throw const RouterQueryException(
        '로그인은 되었지만 세션 정보를 읽지 못했습니다. 다시 시도하세요.',
      );
    }
    return session;
  }

  /// Reads the connected-device list using an active [session] cookie.
  Future<List<RouterDhcpClient>> readDevices({
    required String host,
    required String session,
  }) async {
    try {
      final request = await _client
          .getUrl(Uri.parse('http://$host/asp/basic_ip_list.html'))
          .timeout(timeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.cookieHeader, 'MCRSESSIONID=$session');
      request.headers.set(
        HttpHeaders.refererHeader,
        'http://$host/asp/home.html',
      );
      final response = await request.close().timeout(timeout);
      final body = await response.transform(latin1.decoder).join();
      if (body.contains('start.asp') || body.contains('Access Error')) {
        throw const RouterQueryException('공유기 세션이 만료되었습니다. 다시 로그인하세요.');
      }
      return parseDeviceList(body);
    } on RouterQueryException {
      rethrow;
    } on Exception catch (_) {
      throw const RouterQueryException('공유기 접속 장비 목록을 읽지 못했습니다.');
    }
  }

  void close() => _client.close(force: true);

  /// Parses the `szIPInfo` device string: `ip,mac,name,port;` entries.
  static List<RouterDhcpClient> parseDeviceList(String body) {
    final match = RegExp(
      '''szIPInfo\\s*=\\s*(['"])(.*?)\\1''',
      dotAll: true,
    ).firstMatch(body);
    final raw = match?.group(2);
    if (raw == null || raw.isEmpty) return const [];

    final byIp = <String, RouterDhcpClient>{};
    for (final entry in raw.split(';')) {
      if (entry.trim().isEmpty) continue;
      final fields = entry.split(',');
      if (fields.length < 2) continue;
      final ip = fields[0].trim();
      final mac = fields[1].trim();
      if (!_isIpv4(ip) || !_looksLikeMac(mac)) continue;
      final name = fields.length > 2 ? fields[2].trim() : '';
      byIp[ip] = RouterDhcpClient(
        ipAddress: ip,
        macAddress: mac,
        hostname: name.isEmpty ? null : name,
      );
    }
    return byIp.values.toList(growable: false);
  }

  static String? _sessionFromHeaders(HttpClientResponse response) {
    for (final cookie in response.cookies) {
      if (cookie.name == 'MCRSESSIONID' && cookie.value.isNotEmpty) {
        return cookie.value;
      }
    }
    final raw = response.headers[HttpHeaders.setCookieHeader];
    if (raw == null) return null;
    final match = RegExp(
      r'MCRSESSIONID=([^;\s]+)',
    ).firstMatch(raw.join('; '));
    return match?.group(1);
  }

  static Future<String> _sha256Hex(String input) async {
    final hash = await Sha256().hash(utf8.encode(input));
    return hash.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static bool _isIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  static bool _looksLikeMac(String mac) {
    return RegExp(r'^(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$').hasMatch(mac);
  }
}
