import 'package:flutter/material.dart';
import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/dashboard/presentation/security_dashboard_page.dart';
import 'package:wifi_scan/features/inventory/application/inventory_repository.dart';

class WifiScanApp extends StatefulWidget {
  const WifiScanApp({
    super.key,
    this.discoveryService,
    this.inventoryRepository,
  });

  final NetworkDiscoveryService? discoveryService;
  final InventoryRepository? inventoryRepository;

  @override
  State<WifiScanApp> createState() => _WifiScanAppState();
}

class _WifiScanAppState extends State<WifiScanApp> {
  ThemeMode _themeMode = ThemeMode.system;

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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8A7CFF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0D0E14),
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      home: SecurityDashboardPage(
        discoveryService: widget.discoveryService,
        inventoryRepository: widget.inventoryRepository,
        onThemeModeChanged: (mode) => setState(() => _themeMode = mode),
      ),
    );
  }
}
