import 'package:flutter/material.dart';
import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/dashboard/presentation/security_dashboard_page.dart';
import 'package:wifi_scan/features/inventory/application/inventory_repository.dart';
import 'package:wifi_scan/features/network_profiles/application/network_connection_service.dart';

class WifiScanApp extends StatefulWidget {
  const WifiScanApp({
    super.key,
    this.discoveryService,
    this.inventoryRepository,
    this.connectionService,
  });

  final NetworkDiscoveryService? discoveryService;
  final InventoryRepository? inventoryRepository;
  final NetworkConnectionService? connectionService;

  @override
  State<WifiScanApp> createState() => _WifiScanAppState();
}

class _WifiScanAppState extends State<WifiScanApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '와이파이 스캔',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: const Color(0xFF8A7CFF),
              brightness: Brightness.dark,
            ).copyWith(
              surface: const Color(0xFF11121A),
              surfaceContainerLow: const Color(0xFF14151F),
              surfaceContainerHighest: const Color(0xFF1C1D2A),
              outlineVariant: const Color(0xFF262838),
            ),
        scaffoldBackgroundColor: const Color(0xFF0A0B10),
        cardTheme: const CardThemeData(
          color: Color(0xFF14151F),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            side: BorderSide(color: Color(0xFF232432)),
          ),
        ),
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      home: SecurityDashboardPage(
        discoveryService: widget.discoveryService,
        inventoryRepository: widget.inventoryRepository,
        connectionService: widget.connectionService,
        onThemeModeChanged: (mode) => setState(() => _themeMode = mode),
      ),
    );
  }
}
