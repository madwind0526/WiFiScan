import 'package:wifi_scan/features/discovery/domain/network_context.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';

class DiscoveryResult {
  const DiscoveryResult({
    required this.context,
    required this.devices,
    required this.limitations,
    required this.duration,
  });

  final NetworkContext context;
  final List<NetworkDevice> devices;
  final List<String> limitations;
  final Duration duration;
}
