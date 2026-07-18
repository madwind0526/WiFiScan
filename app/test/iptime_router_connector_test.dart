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

  group('IptimeRouterConnector.parseDhcpClients', () {
    test('parses an HTML table of leases', () {
      const body = '''
        <table>
        <tr><td>192.168.0.10</td><td>88:36:6C:C1:D6:84</td><td>living-room-tv</td></tr>
        <tr><td>192.168.0.11</td><td>28-6B-B4-99-A8-B6</td><td>settop</td></tr>
        </table>
      ''';
      final clients = IptimeRouterConnector.parseDhcpClients(body);
      expect(clients.length, 2);
      final tv = clients.firstWhere((c) => c.ipAddress == '192.168.0.10');
      expect(tv.normalizedMac, '88:36:6C:C1:D6:84');
      expect(tv.hostname, 'living-room-tv');
    });

    test('parses delimited JavaScript-style records', () {
      const body =
          'dhcp[0]="192.168.0.20|A0:0B:BA:11:22:33|my-phone|3600";\n'
          'dhcp[1]="192.168.0.21|5C:CF:7F:44:55:66|esp-plug|7200";';
      final clients = IptimeRouterConnector.parseDhcpClients(body);
      expect(clients.length, 2);
      expect(
        clients.firstWhere((c) => c.ipAddress == '192.168.0.21').hostname,
        'esp-plug',
      );
    });

    test('ignores records without both an IP and a MAC', () {
      const body = '<tr><td>192.168.0.30</td><td>no-mac-here</td></tr>';
      expect(IptimeRouterConnector.parseDhcpClients(body), isEmpty);
    });
  });
}
