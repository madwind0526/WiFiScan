import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/app/wifi_scan_app.dart';

void main() {
  testWidgets('shows the network security dashboard', (tester) async {
    await tester.pumpWidget(const WifiScanApp());

    expect(find.text('와이파이 보안 점검'), findsOneWidget);
    expect(find.text('확인된 장비'), findsOneWidget);
    expect(find.text('미확인 장비'), findsOneWidget);
    expect(find.text('현재 네트워크 검색 시작'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('보안 경고'), 300);
    expect(find.text('보안 경고'), findsOneWidget);
  });

  testWidgets('explains that discovery is not connected yet', (tester) async {
    await tester.pumpWidget(const WifiScanApp());

    await tester.tap(find.text('현재 네트워크 검색 시작'));
    await tester.pump();

    expect(find.text('네트워크 탐색 기능은 다음 단계에서 연결됩니다.'), findsOneWidget);
  });

  testWidgets('supports a small screen without layout exceptions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(const WifiScanApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(find.text('현재 네트워크 검색 시작'), 200);
    expect(find.text('현재 네트워크 검색 시작'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
