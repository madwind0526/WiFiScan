import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/features/discovery/infrastructure/dotenv.dart';

void main() {
  group('DotEnv.parse', () {
    test('reads keys, ignoring comments and blanks', () {
      final env = DotEnv.parse('''
# comment
WIFISCAN_ROUTER_PW=secret

WIFISCAN_ROUTER_USER = root
''');
      expect(env['WIFISCAN_ROUTER_PW'], 'secret');
      expect(env['WIFISCAN_ROUTER_USER'], 'root');
      expect(env.containsKey('# comment'), isFalse);
    });

    test('strips quotes and honors an export prefix', () {
      final env = DotEnv.parse('export WIFISCAN_ROUTER_PW="p@ss word"');
      expect(env['WIFISCAN_ROUTER_PW'], 'p@ss word');
    });

    test('keeps = characters inside the value', () {
      final env = DotEnv.parse('WIFISCAN_ROUTER_PW=a=b=c');
      expect(env['WIFISCAN_ROUTER_PW'], 'a=b=c');
    });
  });

  group('DotEnv.merged', () {
    test('fills missing keys from .env but lets real env win', () async {
      final dir = await Directory.systemTemp.createTemp('wifiscan_env');
      addTearDown(() => dir.delete(recursive: true));
      File('${dir.path}${Platform.pathSeparator}.env').writeAsStringSync(
        'WIFISCAN_ROUTER_PW=from_file\nWIFISCAN_ROUTER_HOST=192.168.0.1\n',
      );

      final merged = DotEnv.merged(
        start: dir,
        environment: const {'WIFISCAN_ROUTER_PW': 'from_env'},
      );

      expect(merged['WIFISCAN_ROUTER_PW'], 'from_env'); // real env wins
      expect(merged['WIFISCAN_ROUTER_HOST'], '192.168.0.1'); // filled from file
    });

    test('returns the base environment when no .env exists', () {
      final merged = DotEnv.merged(
        start: Directory.systemTemp,
        environment: const {'A': '1', 'WIFISCAN_ENV_FILE': ''},
      );
      expect(merged['A'], '1');
    });
  });
}
