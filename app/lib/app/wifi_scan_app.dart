import 'package:flutter/material.dart';
import 'package:wifi_scan/features/home/presentation/project_home_page.dart';

class WifiScanApp extends StatelessWidget {
  const WifiScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '와이파이 스캔',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const ProjectHomePage(),
    );
  }
}
