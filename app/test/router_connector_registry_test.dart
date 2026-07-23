import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/discovery/domain/router_connector.dart';
import 'package:wifi_scan/features/discovery/domain/router_dhcp_client.dart';
import 'package:wifi_scan/features/discovery/infrastructure/iptime_router_connector.dart';
import 'package:wifi_scan/features/discovery/infrastructure/router_connector_registry.dart';
import 'package:wifi_scan/features/discovery/infrastructure/sk_gateway_connector.dart';

/// Stands in for a router family so detection can be tested without a network.
class _FakeConnector implements RouterConnector {
  _FakeConnector({
    required this.id,
    required this.matchesHost,
    this.throwsOnMatch = false,
  });

  @override
  final String id;

  final bool matchesHost;
  final bool throwsOnMatch;

  @override
  bool get requiresCaptcha => false;

  bool closed = false;

  @override
  String get displayName => id;

  @override
  Future<bool> matches(String host) async {
    if (throwsOnMatch) throw StateError('probe failed');
    return matchesHost;
  }

  @override
  Future<Uint8List> fetchCaptcha(String host) async => Uint8List(0);

  @override
  Future<String> login({
    required String host,
    required String username,
    required String password,
    String captcha = '',
  }) async => 'session';

  @override
  Future<List<RouterDhcpClient>> readDevices({
    required String host,
    required String session,
  }) async => const [];

  @override
  void close() => closed = true;
}

void main() {
  test('returns the first connector that recognizes the host', () async {
    final miss = _FakeConnector(id: 'miss', matchesHost: false);
    final hit = _FakeConnector(id: 'hit', matchesHost: true);
    final later = _FakeConnector(id: 'later', matchesHost: true);
    final registry = RouterConnectorRegistry(
      factories: [() => miss, () => hit, () => later],
    );

    final detected = await registry.detect('192.168.0.1');

    expect(detected, same(hit));
    // Probes that did not match are closed; the one handed back is not, since
    // the caller now owns it.
    expect(miss.closed, isTrue);
    expect(hit.closed, isFalse);
    // Detection stops at the first match, so later families are never probed.
    expect(later.closed, isFalse);
  });

  test('returns null when no family matches', () async {
    final registry = RouterConnectorRegistry(
      factories: [() => _FakeConnector(id: 'a', matchesHost: false)],
    );

    expect(await registry.detect('192.168.0.1'), isNull);
  });

  test('a probe that throws is treated as no match, not a crash', () async {
    final broken = _FakeConnector(
      id: 'broken',
      matchesHost: true,
      throwsOnMatch: true,
    );
    final hit = _FakeConnector(id: 'hit', matchesHost: true);
    final registry = RouterConnectorRegistry(
      factories: [() => broken, () => hit],
    );

    expect(await registry.detect('192.168.0.1'), same(hit));
    expect(broken.closed, isTrue);
  });

  test('real connectors expose the captcha routing the UI branches on', () {
    final iptime = IptimeRouterConnector();
    final sk = SkGatewayConnector();
    addTearDown(iptime.close);
    addTearDown(sk.close);

    expect(iptime.requiresCaptcha, isFalse);
    expect(sk.requiresCaptcha, isTrue);
    expect(iptime.id, 'iptime');
    expect(sk.id, 'sk-broadband');
    // ipTIME has no captcha to fetch, so asking for one is a programming error.
    expect(() => iptime.fetchCaptcha('192.168.0.1'), throwsUnsupportedError);
  });

  test('default registry probes the captcha gateway before ipTIME', () {
    expect(RouterConnectorRegistry.defaultFactories.length, 2);
    final first = RouterConnectorRegistry.defaultFactories.first();
    final second = RouterConnectorRegistry.defaultFactories.last();
    addTearDown(first.close);
    addTearDown(second.close);

    expect(first.id, 'sk-broadband');
    expect(second.id, 'iptime');
  });
}
