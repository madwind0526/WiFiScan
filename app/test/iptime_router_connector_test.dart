import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/discovery/domain/router_dhcp_client.dart';
import 'package:wifi_scan/features/discovery/infrastructure/iptime_router_connector.dart';

void main() {
  group('RouterDhcpClient.normalizedMac', () {
    test('normalizes dashed and lowercase MACs', () {
      const client = RouterDhcpClient(
        ipAddress: '192.168.0.40',
        macAddress: '88-36-6c-c1-d6-84',
      );
      expect(client.normalizedMac, '88:36:6C:C1:D6:84');
    });

    test('returns null for missing or malformed MACs', () {
      expect(
        const RouterDhcpClient(ipAddress: '192.168.0.40').normalizedMac,
        isNull,
      );
      expect(
        const RouterDhcpClient(
          ipAddress: '192.168.0.40',
          macAddress: '88:36:6C',
        ).normalizedMac,
        isNull,
      );
    });
  });

  group('EnvRouterCredentialsSource', () {
    test('builds credentials from env, defaulting user and host', () {
      const source = EnvRouterCredentialsSource(
        environment: {'WIFISCAN_ROUTER_PW': 'secret'},
      );
      final creds = source.credentials(gateway: '192.168.0.1');
      expect(creds, isNotNull);
      expect(creds!.host, '192.168.0.1');
      expect(creds.username, 'admin');
      expect(creds.password, 'secret');
      expect(creds.isComplete, isTrue);
    });

    test('honors explicit host and user overrides', () {
      const source = EnvRouterCredentialsSource(
        environment: {
          'WIFISCAN_ROUTER_PW': 'secret',
          'WIFISCAN_ROUTER_USER': 'root',
          'WIFISCAN_ROUTER_HOST': '10.0.0.1',
        },
      );
      final creds = source.credentials(gateway: '192.168.0.1');
      expect(creds!.host, '10.0.0.1');
      expect(creds.username, 'root');
    });

    test('returns null without a password or a resolvable host', () {
      const noPw = EnvRouterCredentialsSource(environment: {});
      expect(noPw.credentials(gateway: '192.168.0.1'), isNull);

      const noHost = EnvRouterCredentialsSource(
        environment: {'WIFISCAN_ROUTER_PW': 'secret'},
      );
      expect(noHost.credentials(), isNull);
    });
  });
}
