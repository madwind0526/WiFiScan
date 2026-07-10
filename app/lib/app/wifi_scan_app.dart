import 'package:flutter/material.dart';
import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/dashboard/presentation/security_dashboard_page.dart';
import 'package:wifi_scan/features/inventory/application/inventory_repository.dart';

class WifiScanApp extends StatelessWidget {
  const WifiScanApp({
    super.key,
    this.discoveryService,
    this.inventoryRepository,
  });

  final NetworkDiscoveryService? discoveryService;
  final InventoryRepository? inventoryRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '와이파이 스캔',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: SecurityDashboardPage(
        discoveryService: discoveryService,
        inventoryRepository: inventoryRepository,
      ),
    );
  }
}
