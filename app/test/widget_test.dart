import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/app/wifi_scan_app.dart';

void main() {
  testWidgets('shows the independent project scaffold', (tester) async {
    await tester.pumpWidget(const WifiScanApp());

    expect(find.text('와이파이 스캔'), findsOneWidget);
    expect(find.text('새 프로젝트 준비 완료'), findsOneWidget);
    expect(find.text('WifiScan의 요구사항을 정한 뒤 첫 번째 기능을 추가합니다.'), findsOneWidget);
  });
}
