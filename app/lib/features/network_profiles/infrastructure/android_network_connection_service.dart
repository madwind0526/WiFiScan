import 'package:flutter/services.dart';
import 'package:wifi_scan/features/network_profiles/application/network_connection_service.dart';
import 'package:wifi_scan/features/network_profiles/domain/network_profile.dart';

class AndroidNetworkConnectionService implements NetworkConnectionService {
  const AndroidNetworkConnectionService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.wifiscan/network');

  final MethodChannel _channel;

  @override
  Future<List<NetworkProfile>> discoverAvailableProfiles() async => const [];

  @override
  Future<String?> currentSsid() async {
    return _channel.invokeMethod<String>('currentSsid');
  }

  @override
  Future<void> connect(NetworkProfile profile) async {
    final connected = await _channel.invokeMethod<bool>('connectNetwork', {
      'ssid': profile.ssid,
      'password': profile.password ?? '',
    });
    if (connected != true) {
      throw NetworkConnectionException('${profile.ssid} 연결을 승인하지 않았습니다.');
    }
  }

  @override
  Future<void> restore(String? ssid) async {
    await _channel.invokeMethod<void>('restoreNetwork');
  }
}
