import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_scan/app/wifi_scan_app.dart';
import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/domain/discovery_result.dart';
import 'package:wifi_scan/features/discovery/domain/network_context.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';
import 'package:wifi_scan/features/inventory/application/inventory_repository.dart';
import 'package:wifi_scan/features/inventory/domain/inventory_snapshot.dart';
import 'package:wifi_scan/features/network_profiles/application/network_connection_service.dart';
import 'package:wifi_scan/features/network_profiles/application/network_profile_repository.dart';
import 'package:wifi_scan/features/network_profiles/domain/network_profile.dart';
import 'package:wifi_scan/features/network_profiles/infrastructure/profile_backup_codec.dart';
import 'package:wifi_scan/features/network_profiles/infrastructure/profile_transfer_file_service.dart';
import 'dart:typed_data';

import 'package:wifi_scan/features/discovery/domain/router_connector.dart';
import 'package:wifi_scan/features/discovery/domain/router_dhcp_client.dart';
import 'package:wifi_scan/features/discovery/infrastructure/router_connector_registry.dart';
import 'package:wifi_scan/features/discovery/infrastructure/router_credential_store.dart';

void main() {
  testWidgets('shows the network security dashboard', (tester) async {
    await tester.pumpWidget(const WifiScanApp());

    expect(find.text('WifiScan'), findsOneWidget);
    expect(find.text('v1.3.0+9'), findsOneWidget);
    expect(find.byTooltip('설정'), findsOneWidget);
    expect(find.byTooltip('전체 네트워크 스캔'), findsOneWidget);
    expect(find.byTooltip('현재 네트워크 검색 시작'), findsOneWidget);
    expect(find.byTooltip('네트워크'), findsWidgets);
    expect(find.byTooltip('경고'), findsOneWidget);
  });

  testWidgets('shows discovered devices after a completed scan', (
    tester,
  ) async {
    await tester.pumpWidget(
      WifiScanApp(
        discoveryService: const _FakeDiscoveryService(),
        inventoryRepository: InventoryRepository(store: _MemorySnapshotStore()),
        connectionService: const _FakeConnectionService(),
        routerCredentialStore: _FakeRouterCredentialStore(),
        routerConnectors: RouterConnectorRegistry(
          factories: [_FakeRouterConnector.new],
        ),
      ),
    );

    await tester.tap(find.byTooltip('현재 네트워크 검색 시작').first);
    await tester.pumpAndSettle();

    final completedMessage = find.textContaining('검색 완료');
    expect(completedMessage, findsOneWidget);
    expect(find.byTooltip('메시지 닫기'), findsOneWidget);
    final completedCard = tester.widget<Card>(
      find.ancestor(of: completedMessage, matching: find.byType(Card)).first,
    );
    expect(completedCard.color!.a, lessThan(1));
    expect(tester.widget<Text>(completedMessage).style?.color, Colors.white);
    expect(tester.widget<Text>(completedMessage).textAlign, TextAlign.center);
    await tester.tap(find.byKey(const ValueKey('message-panel-close')));
    await tester.pump();
    expect(completedMessage, findsNothing);
    await tester.tap(find.byTooltip('장비'));
    await tester.pumpAndSettle();
    expect(find.text('Mesh'), findsOneWidget);
    expect(find.text('장비 검색'), findsOneWidget);
    await tester.tap(find.byTooltip('목록'));
    await tester.pumpAndSettle();
    expect(find.text('내 PC'), findsOneWidget);
    expect(find.text('GW'), findsOneWidget);
    await tester.tap(find.text('내 PC'));
    await tester.pumpAndSettle();
    expect(find.text('식별 신뢰도'), findsOneWidget);
    expect(find.text('MAC 주소'), findsOneWidget);
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    // Tapping a gateway node opens the read-only router login popup.
    await tester.tap(find.text('GW'));
    await tester.pumpAndSettle();
    expect(find.text('공유기 관리자 로그인'), findsOneWidget);
    expect(find.widgetWithText(TextField, '관리자 비밀번호'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    final searchField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText == '장비 검색',
    );
    await tester.enterText(searchField, '내 PC');
    await tester.pumpAndSettle();
    expect(find.text('장비 1개'), findsOneWidget);
    await tester.tap(find.byTooltip('홈'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('visible-device-count')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('visible-warning-count')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('uses a concise banner for one newly discovered device', (
    tester,
  ) async {
    final previousDevice = NetworkDevice(
      id: 'local:192.168.0.30',
      displayName: '내 PC',
      category: DeviceCategory.computer,
      ownershipStatus: OwnershipStatus.confirmed,
      ipAddresses: const ['192.168.0.30'],
      sources: const [DiscoverySource.localInterface],
      firstSeenAt: DateTime(2026, 7, 10),
      lastSeenAt: DateTime(2026, 7, 10),
      identityConfidence: 1,
    );
    final store = _MemorySnapshotStore([
      InventorySnapshot(
        scannedAt: DateTime(2026, 7, 10),
        networkKey: '192.168.0.0/24',
        context: _testNetworkContext,
        devices: [previousDevice],
        limitations: const [],
      ),
    ]);
    await tester.pumpWidget(
      WifiScanApp(
        discoveryService: const _FakeDiscoveryService(),
        inventoryRepository: InventoryRepository(store: store),
        connectionService: const _FakeConnectionService(),
      ),
    );

    await tester.tap(find.byTooltip('현재 네트워크 검색 시작').first);
    await tester.pumpAndSettle();

    expect(find.text('검색 완료 · 신규 장비 1개 발견'), findsOneWidget);
    expect(find.byTooltip('메시지 닫기'), findsOneWidget);
  });

  testWidgets('allows the user to stop an active scan', (tester) async {
    await tester.pumpWidget(
      const WifiScanApp(
        discoveryService: _SlowDiscoveryService(),
        connectionService: _FakeConnectionService(),
      ),
    );

    await tester.tap(find.byTooltip('현재 네트워크 검색 시작').first);
    await tester.pump();
    expect(find.byTooltip('검색 중지 요청'), findsOneWidget);

    await tester.tap(find.byTooltip('검색 중지 요청').first);
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('검색 중지'), findsOneWidget);
    expect(find.byTooltip('현재 네트워크 검색 시작'), findsOneWidget);
  });

  testWidgets('allows the user to dismiss a translucent error message', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      const WifiScanApp(
        discoveryService: _FailingDiscoveryService(),
        connectionService: _FakeConnectionService(),
      ),
    );

    await tester.tap(find.byTooltip('현재 네트워크 검색 시작').first);
    await tester.pumpAndSettle();

    const errorMessage = '네트워크 검색 불가';
    final messageFinder = find.text(errorMessage);
    expect(messageFinder, findsOneWidget);
    expect(find.byTooltip('메시지 닫기'), findsOneWidget);
    final card = tester.widget<Card>(
      find.ancestor(of: messageFinder, matching: find.byType(Card)).first,
    );
    expect(card.color!.a, lessThan(1));
    expect(tester.widget<Text>(messageFinder).textAlign, TextAlign.center);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('message-panel-close')));
    await tester.pump();
    expect(messageFinder, findsNothing);
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

    await tester.pumpWidget(
      WifiScanApp(
        discoveryService: const _FakeDiscoveryService(),
        inventoryRepository: InventoryRepository(store: _MemorySnapshotStore()),
        connectionService: const _FakeConnectionService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('현재 네트워크 검색 시작'), findsOneWidget);
    await tester.tap(find.byTooltip('현재 네트워크 검색 시작'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('장비'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone-width home screen keeps its blocks from overlapping', (
    tester,
  ) async {
    // A common phone viewport: the width where the title, the network chip and
    // the action icons used to be drawn on top of each other.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    // Android's gesture bar overlays the app; the nav row must stay above it.
    const gestureBar = FakeViewPadding(bottom: 66);
    tester.view.padding = gestureBar;
    tester.view.viewPadding = gestureBar;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(
      WifiScanApp(
        discoveryService: const _FakeDiscoveryService(),
        inventoryRepository: InventoryRepository(store: _MemorySnapshotStore()),
        connectionService: const _FakeConnectionService(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final title = tester.getRect(find.text('WifiScan'));
    final chip = tester.getRect(find.text('연결된 네트워크 없음'));
    final actions = tester.getRect(find.byTooltip('설정'));
    expect(title.right, lessThanOrEqualTo(chip.left));
    expect(chip.right, lessThanOrEqualTo(actions.left));

    // The counters sit above the footer note, never across it.
    final counters = tester.getRect(
      find.byKey(const ValueKey('visible-device-count')),
    );
    final footer = tester.getRect(
      find.text('스캔 후 인터페이스, 게이트웨이, 검색 범위가 표시됩니다.'),
    );
    expect(counters.bottom, lessThanOrEqualTo(footer.top));

    // Every bottom-bar icon clears the system gesture bar.
    final safeBottom =
        tester.view.physicalSize.height / tester.view.devicePixelRatio -
        gestureBar.bottom / tester.view.devicePixelRatio;
    // '네트워크' is skipped: the summary row uses that tooltip too, and these
    // items all share the one padded bottom bar anyway.
    for (final tooltip in ['홈', '장비', '경고']) {
      final item = tester.getRect(find.byTooltip(tooltip));
      expect(item.bottom, lessThanOrEqualTo(safeBottom), reason: tooltip);
      expect(item.height, greaterThan(0), reason: tooltip);
    }
  });

  testWidgets(
    'profile editor supports keyboard, large text, save, and cancel',
    (tester) async {
      final profileRepository = _MemoryProfileRepository();
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        WifiScanApp(
          discoveryService: const _FakeDiscoveryService(),
          inventoryRepository: InventoryRepository(
            store: _MemorySnapshotStore(),
          ),
          connectionService: const _FakeConnectionService(),
          profileRepository: profileRepository,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('네트워크 프로필'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('추가'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(3));

      tester.view.viewInsets = FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '취소할 프로필');
      await tester.enterText(find.byType(TextField).at(1), 'Cancel-WiFi');
      await tester.enterText(find.byType(TextField).at(2), 'cancel-password');
      await tester.ensureVisible(find.text('취소'));
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(profileRepository.profiles, isEmpty);
      expect(tester.takeException(), isNull);

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.tap(find.text('추가'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '거실 공유기');
      await tester.enterText(find.byType(TextField).at(1), 'LivingRoom-5G');
      await tester.enterText(find.byType(TextField).at(2), 'saved-password');
      await tester.ensureVisible(find.text('저장'));
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      expect(profileRepository.profiles, hasLength(1));
      expect(profileRepository.profiles.single.ssid, 'LivingRoom-5G');
      expect(profileRepository.profiles.single.password, 'saved-password');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('deleted Windows profiles stay suppressed after app reload', (
    tester,
  ) async {
    final repository = _MemoryProfileRepository();
    const discoveredProfile = NetworkProfile(
      id: 'Auto-WiFi',
      ssid: 'Auto-WiFi',
      displayName: 'Auto-WiFi',
    );
    const connectionService = _FakeConnectionService(
      availableProfiles: [discoveredProfile],
    );

    await tester.pumpWidget(
      WifiScanApp(
        connectionService: connectionService,
        profileRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.profiles, hasLength(1));

    await tester.tap(find.byTooltip('네트워크 프로필'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('삭제'));
    await tester.pumpAndSettle();
    expect(repository.profiles, isEmpty);
    expect(repository.suppressedSsids, contains('Auto-WiFi'));
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      WifiScanApp(
        connectionService: connectionService,
        profileRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.profiles, isEmpty);

    await tester.tap(find.byTooltip('네트워크 프로필'));
    await tester.pumpAndSettle();
    expect(find.text('Auto-WiFi'), findsNothing);
  });

  testWidgets(
    'encrypted profile export and import support keyboard and large text',
    (tester) async {
      final repository = _MemoryProfileRepository(const [
        NetworkProfile(
          id: 'LivingRoom-5G',
          ssid: 'LivingRoom-5G',
          displayName: '거실 공유기',
          password: 'wifi-local-secret',
        ),
      ]);
      final codec = ProfileBackupCodec.forTesting();
      final transferService = _MemoryProfileTransferFileService();
      transferService.contentToPick = await codec.exportProfiles(const [
        NetworkProfile(
          id: 'Office-WiFi',
          ssid: 'Office-WiFi',
          displayName: '사무실',
          password: 'office-secret',
        ),
      ], password: 'import-password');
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        WifiScanApp(
          discoveryService: const _FakeDiscoveryService(),
          inventoryRepository: InventoryRepository(
            store: _MemorySnapshotStore(),
          ),
          connectionService: const _FakeConnectionService(),
          profileRepository: repository,
          profileBackupCodec: codec,
          profileTransferFileService: transferService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('설정'));
      await tester.pumpAndSettle();
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      await tester.ensureVisible(find.text('내보내기'));
      await tester.tap(find.text('내보내기'));
      await tester.pumpAndSettle();
      expect(find.text('내보내기 암호 설정'), findsOneWidget);
      await tester.ensureVisible(find.text('취소'));
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(transferService.savedContent, isNull);

      await tester.tap(find.byTooltip('설정'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('내보내기'));
      await tester.tap(find.text('내보내기'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('profile-backup-password')),
        'export-password',
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile-backup-password-confirmation')),
        'different-password',
      );
      await tester.ensureVisible(find.text('내보내기'));
      await tester.tap(find.text('내보내기'));
      await tester.pumpAndSettle();
      expect(find.text('입력한 암호가 서로 다릅니다.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('profile-backup-password-confirmation')),
        'export-password',
      );
      await tester.ensureVisible(find.text('내보내기'));
      await tester.tap(find.text('내보내기'));
      await tester.pumpAndSettle();
      expect(transferService.savedContent, isNotNull);
      expect(
        transferService.savedContent,
        isNot(contains('wifi-local-secret')),
      );
      expect(tester.takeException(), isNull);

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('설정'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('가져오기'));
      await tester.tap(find.text('가져오기'));
      await tester.pumpAndSettle();
      expect(find.text('내보내기 암호 입력'), findsOneWidget);
      tester.view.viewInsets = FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('profile-backup-password')),
        'import-password',
      );
      await tester.ensureVisible(find.text('불러오기'));
      await tester.tap(find.text('불러오기'));
      await tester.pumpAndSettle();

      expect(
        repository.profiles.map((profile) => profile.ssid),
        containsAll(['LivingRoom-5G', 'Office-WiFi']),
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _FakeDiscoveryService implements NetworkDiscoveryService {
  const _FakeDiscoveryService();

  @override
  Future<DiscoveryResult> discover({
    required DiscoveryCancellationToken cancellationToken,
    required void Function(DiscoveryProgress progress) onProgress,
  }) async {
    onProgress(
      const DiscoveryProgress(
        stage: DiscoveryStage.probing,
        completed: 1,
        total: 1,
      ),
    );
    return DiscoveryResult(
      context: _testNetworkContext,
      devices: [
        NetworkDevice(
          id: 'local:192.168.0.30',
          displayName: '내 PC',
          category: DeviceCategory.computer,
          ownershipStatus: OwnershipStatus.confirmed,
          ipAddresses: const ['192.168.0.30'],
          sources: const [DiscoverySource.localInterface],
          firstSeenAt: DateTime(2026, 7, 11),
          lastSeenAt: DateTime(2026, 7, 11),
          identityConfidence: 1,
        ),
        NetworkDevice(
          id: 'router:192.168.0.1',
          displayName: 'GW',
          category: DeviceCategory.router,
          ownershipStatus: OwnershipStatus.unconfirmed,
          ipAddresses: const ['192.168.0.1'],
          sources: const [DiscoverySource.router, DiscoverySource.neighbor],
          firstSeenAt: DateTime(2026, 7, 11),
          lastSeenAt: DateTime(2026, 7, 11),
          identityConfidence: 0.85,
          vendor: 'EFM Networks',
          modelName: 'A6004NS-M',
          hostnames: const ['router.local'],
          services: const [
            NetworkServiceObservation(
              protocol: 'http',
              port: 80,
              transport: NetworkTransport.tcp,
              source: DiscoverySource.serviceProbe,
            ),
          ],
        ),
      ],
      limitations: const ['테스트 검색 결과입니다.'],
      duration: Duration.zero,
    );
  }
}

class _SlowDiscoveryService implements NetworkDiscoveryService {
  const _SlowDiscoveryService();

  @override
  Future<DiscoveryResult> discover({
    required DiscoveryCancellationToken cancellationToken,
    required void Function(DiscoveryProgress progress) onProgress,
  }) async {
    onProgress(
      const DiscoveryProgress(
        stage: DiscoveryStage.probing,
        completed: 0,
        total: 1,
      ),
    );
    while (!cancellationToken.isCancelled) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw const DiscoveryCancelledException();
  }
}

class _FailingDiscoveryService implements NetworkDiscoveryService {
  const _FailingDiscoveryService();

  @override
  Future<DiscoveryResult> discover({
    required DiscoveryCancellationToken cancellationToken,
    required void Function(DiscoveryProgress progress) onProgress,
  }) async {
    throw const DiscoveryUnavailableException(
      '3개 네트워크를 확인했습니다. 1개 네트워크는 연결하지 못했습니다.',
    );
  }
}

class _FakeConnectionService implements NetworkConnectionService {
  const _FakeConnectionService({this.availableProfiles = const []});

  final List<NetworkProfile> availableProfiles;

  @override
  Future<List<NetworkProfile>> discoverAvailableProfiles() async =>
      availableProfiles;

  @override
  Future<String?> currentSsid() async => null;

  @override
  Future<WifiBand> currentBand() async => WifiBand.unknown;

  @override
  Future<void> connect(NetworkProfile profile) async {}

  @override
  Future<void> restore(String? ssid) async {}
}

/// Recognizes any host without touching the network, so the gateway tap opens
/// the login popup deterministically in tests.
class _FakeRouterConnector implements RouterConnector {
  @override
  String get id => 'fake';

  @override
  String get displayName => '테스트 공유기';

  @override
  bool get requiresCaptcha => false;

  @override
  Future<bool> matches(String host) async => true;

  @override
  Future<Uint8List> fetchCaptcha(String host) async =>
      throw UnsupportedError('no captcha');

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
  void close() {}
}

class _FakeRouterCredentialStore implements RouterCredentialStore {
  @override
  Future<RouterCredentials?> read(String host) async => null;

  @override
  Future<void> write(RouterCredentials credentials) async {}

  @override
  Future<void> delete(String host) async {}
}

class _MemorySnapshotStore implements InventorySnapshotStore {
  _MemorySnapshotStore([Iterable<InventorySnapshot> initial = const []]) {
    snapshots.addAll(initial);
  }

  final List<InventorySnapshot> snapshots = [];

  @override
  Future<List<InventorySnapshot>> load() async => [...snapshots];

  @override
  Future<void> save(List<InventorySnapshot> value) async {
    snapshots
      ..clear()
      ..addAll(value);
  }
}

const _testNetworkContext = NetworkContext(
  interfaceName: 'Wi-Fi',
  interfaceIndex: 1,
  ipv4Address: '192.168.0.30',
  prefixLength: 24,
  gateway: '192.168.0.1',
  scannedNetwork: '192.168.0.0',
  scannedPrefixLength: 24,
  coverageLimited: false,
);

class _MemoryProfileRepository extends NetworkProfileRepository {
  _MemoryProfileRepository([Iterable<NetworkProfile> initial = const []]) {
    profiles.addAll(initial);
  }

  final List<NetworkProfile> profiles = [];
  final Set<String> suppressedSsids = {};

  @override
  Future<List<NetworkProfile>> load() async => List.unmodifiable(profiles);

  @override
  Future<void> save(List<NetworkProfile> value) async {
    profiles
      ..clear()
      ..addAll(value);
  }

  @override
  Future<Set<String>> loadSuppressedSsids() async => {...suppressedSsids};

  @override
  Future<void> suppressAutoDiscovery(String ssid) async {
    suppressedSsids.add(ssid);
  }

  @override
  Future<void> allowAutoDiscovery(String ssid) async {
    suppressedSsids.remove(ssid);
  }
}

class _MemoryProfileTransferFileService implements ProfileTransferFileService {
  String? contentToPick;
  String? savedContent;

  @override
  Future<String?> pick() async => contentToPick;

  @override
  Future<bool> save(String content) async {
    savedContent = content;
    return true;
  }
}
