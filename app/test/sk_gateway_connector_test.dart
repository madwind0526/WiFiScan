import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/discovery/infrastructure/sk_gateway_connector.dart';

void main() {
  group('SkGatewayConnector.parseDeviceList', () {
    test('parses szIPInfo ip,mac,name,port entries', () {
      const body = '''
        <script>
        var szIPInfo = '192.168.45.10,88:36:6C:C1:D6:84,BID-AT200/IPTV/STB,1;'
          + '192.168.45.11,A0:0B:BA:11:22:33,Samsung-Refrigerator,8;'
          + '192.168.45.12,5C:CF:7F:44:55:66,,8';
        </script>
      ''';
      // The connector reads the server-rendered single string; emulate it.
      const rendered =
          "var szIPInfo = '192.168.45.10,88:36:6C:C1:D6:84,BID-AT200/IPTV/STB,1;192.168.45.11,A0:0B:BA:11:22:33,Samsung-Refrigerator,8;192.168.45.12,5C:CF:7F:44:55:66,,8';";
      expect(body, contains('szIPInfo'));
      final clients = SkGatewayConnector.parseDeviceList(rendered);
      expect(clients.length, 3);
      final tv = clients.firstWhere((c) => c.ipAddress == '192.168.45.10');
      expect(tv.normalizedMac, '88:36:6C:C1:D6:84');
      expect(tv.hostname, 'BID-AT200/IPTV/STB');
      final noName = clients.firstWhere((c) => c.ipAddress == '192.168.45.12');
      expect(noName.hostname, isNull);
    });

    test('handles a double-quoted szIPInfo', () {
      const body =
          'var szIPInfo = "192.168.45.20,04:B9:E3:00:11:22,Samsung-Washer,8";';
      final clients = SkGatewayConnector.parseDeviceList(body);
      expect(clients.single.hostname, 'Samsung-Washer');
    });

    test('returns empty when szIPInfo is absent or malformed', () {
      expect(SkGatewayConnector.parseDeviceList('<html></html>'), isEmpty);
      expect(
        SkGatewayConnector.parseDeviceList("var szIPInfo = 'notmac,alsonot';"),
        isEmpty,
      );
    });
  });
}
