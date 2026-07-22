import 'package:wifi_scan/features/inventory/domain/network_device.dart';

/// Infers a [DeviceCategory] from a device's textual evidence (name, vendor,
/// model, hostnames, advertised services). Returns null when nothing matches.
///
/// Shared so both scan-time enrichment and router-provided devices (which
/// never pass through the enricher) classify names like "Samsung-Refrigerator"
/// or "BID-AT200/IPTV/STB" consistently.
DeviceCategory? inferDeviceCategory(NetworkDevice device) {
  final evidence = [
    device.displayName,
    device.vendor ?? '',
    device.modelName ?? '',
    device.description ?? '',
    ...device.hostnames,
    ...device.services.map((service) => service.protocol),
    ...device.services.map((service) => service.product ?? ''),
  ].join(' ').toLowerCase().replaceAll('_', '-');

  bool containsAny(List<String> values) => values.any(evidence.contains);

  if (containsAny(const ['router', 'gateway', 'iptime', 'a6004ns'])) {
    return DeviceCategory.router;
  }
  if (containsAny(const [
    'bid-at',
    'iptv',
    'stb',
    'smart tv',
    'smarttv',
    'androidtv',
    'googlecast',
    'chromecast',
    'webos',
    'bravia',
    'tizen',
    'roku',
    'apple tv',
    'appletv',
    'set-top',
    'settop',
    'mediarenderer',
  ])) {
    return DeviceCategory.television;
  }
  if (containsAny(const ['printer', ' ipp ', 'airprint'])) {
    return DeviceCategory.printer;
  }
  if (containsAny(const ['camera', 'webcam', ' rtsp'])) {
    return DeviceCategory.camera;
  }
  if (containsAny(const ['speaker', 'sonos', ' raop', 'spotify-connect'])) {
    return DeviceCategory.speaker;
  }
  if (containsAny(const [
    'homekit',
    'matter',
    'miio',
    'ewelink',
    'smartthings',
    'home assistant',
    'tuya',
    'vacuum',
    'stickvacuum',
    'jet-bot',
    'jetbot',
    'robot',
    'air purifier',
    'airpurifier',
    'purifier',
    'washer',
    'dryer',
    'refrigerator',
    'kimchi',
    'dishwasher',
    'aircon',
    'air-con',
    'thermostat',
    'bulb',
    'plug',
    'sensor',
  ])) {
    return DeviceCategory.iot;
  }
  if (containsAny(const [
    'iphone',
    'ipad',
    'galaxy',
    'pixel',
    ' phone',
    'phone',
    'mobile',
    'mobdev',
    'z-flip',
    'zflip',
    'z-fold',
    'sm-',
  ])) {
    return DeviceCategory.phone;
  }
  if (containsAny(const [
    'windows',
    'desktop-',
    'laptop',
    'macbook',
    'imac',
    'workstation',
    ' smb',
    ' rdp',
    'netbios-ns',
  ])) {
    return DeviceCategory.computer;
  }
  return null;
}
