import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:wifi_scan/features/discovery/application/network_discovery_service.dart';
import 'package:wifi_scan/features/discovery/application/network_information_enricher.dart';
import 'package:wifi_scan/features/inventory/domain/network_device.dart';
import 'package:xml/xml.dart';

class SsdpEnrichmentProvider implements NetworkEnrichmentProvider {
  const SsdpEnrichmentProvider({
    this.discoveryWindow = const Duration(milliseconds: 1400),
    this.httpTimeout = const Duration(milliseconds: 900),
    this.maxDescriptions = 24,
    this.maxConcurrentDescriptions = 6,
  });

  final Duration discoveryWindow;
  final Duration httpTimeout;
  final int maxDescriptions;
  final int maxConcurrentDescriptions;

  @override
  Future<List<DeviceEnrichment>> collect({
    required Set<String> targetAddresses,
    required DiscoveryCancellationToken cancellationToken,
  }) async {
    final responses = await _discover(cancellationToken);
    final locations = <String, _SsdpResponse>{};
    for (final response in responses) {
      final location = response.headers['location'];
      final uri = location == null ? null : Uri.tryParse(location);
      if (uri == null ||
          uri.scheme != 'http' ||
          !targetAddresses.contains(uri.host)) {
        continue;
      }
      locations[location!] = response;
    }

    final results = <DeviceEnrichment>[];
    final descriptions = locations.entries.take(maxDescriptions).toList();
    var nextIndex = 0;
    Future<void> worker() async {
      while (!cancellationToken.isCancelled) {
        final index = nextIndex++;
        if (index >= descriptions.length) return;
        final entry = descriptions[index];
        final parsed = await _readDescription(entry.key, entry.value);
        if (parsed != null) results.add(parsed);
      }
    }

    final workerCount = descriptions.length < maxConcurrentDescriptions
        ? descriptions.length
        : maxConcurrentDescriptions;
    await Future.wait([
      for (var index = 0; index < workerCount; index++) worker(),
    ]);
    return results;
  }

  Future<List<_SsdpResponse>> _discover(
    DiscoveryCancellationToken cancellationToken,
  ) async {
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
      reuseAddress: true,
    );
    final responses = <String, _SsdpResponse>{};
    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read || cancellationToken.isCancelled) {
        return;
      }
      final datagram = socket.receive();
      if (datagram == null) return;
      final text = ascii.decode(datagram.data, allowInvalid: true);
      final parsed = _SsdpResponse.parse(text);
      if (parsed != null) {
        responses['${datagram.address.address}:${parsed.headers['location']}'] =
            parsed;
      }
    });
    const request =
        'M-SEARCH * HTTP/1.1\r\n'
        'HOST: 239.255.255.250:1900\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 1\r\n'
        'ST: ssdp:all\r\n\r\n';
    socket.send(
      ascii.encode(request),
      InternetAddress('239.255.255.250'),
      1900,
    );
    await Future<void>.delayed(discoveryWindow);
    await subscription.cancel();
    socket.close();
    return responses.values.toList();
  }

  Future<DeviceEnrichment?> _readDescription(
    String location,
    _SsdpResponse response,
  ) async {
    final client = HttpClient()..connectionTimeout = httpTimeout;
    try {
      final request = await client
          .getUrl(Uri.parse(location))
          .timeout(httpTimeout);
      request.followRedirects = false;
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/xml, text/xml',
      );
      final httpResponse = await request.close().timeout(httpTimeout);
      if (httpResponse.statusCode != HttpStatus.ok) return null;
      final bytes = await httpResponse
          .fold<List<int>>(<int>[], (buffer, chunk) {
            if (buffer.length + chunk.length > 262144) {
              throw const FormatException('UPnP description is too large.');
            }
            return buffer..addAll(chunk);
          })
          .timeout(httpTimeout);
      final document = XmlDocument.parse(
        utf8.decode(bytes, allowMalformed: true),
      );
      final uri = Uri.parse(location);
      final friendlyName = _elementText(document, 'friendlyName');
      final manufacturer = _elementText(document, 'manufacturer');
      final modelName = _elementText(document, 'modelName');
      final description = _elementText(document, 'modelDescription');
      final deviceType = _elementText(document, 'deviceType');
      return DeviceEnrichment(
        ipAddress: uri.host,
        displayName: friendlyName,
        vendor: manufacturer,
        modelName: modelName,
        description: description,
        category: _categoryFor(deviceType, modelName),
        services: [
          NetworkServiceObservation(
            protocol: 'upnp',
            port: uri.hasPort ? uri.port : 80,
            transport: NetworkTransport.tcp,
            source: DiscoverySource.ssdp,
            product: response.headers['server'],
          ),
        ],
        sources: const [DiscoverySource.ssdp],
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  String? _elementText(XmlDocument document, String name) {
    final values = document
        .findAllElements(name)
        .map((element) => element.innerText.trim())
        .where((value) => value.isNotEmpty);
    return values.isEmpty ? null : values.first;
  }

  DeviceCategory? _categoryFor(String? deviceType, String? modelName) {
    final text = '${deviceType ?? ''} ${modelName ?? ''}'.toLowerCase();
    if (text.contains('router') || text.contains('internetgateway')) {
      return DeviceCategory.router;
    }
    if (text.contains('printer')) return DeviceCategory.printer;
    if (text.contains('camera')) return DeviceCategory.camera;
    if (text.contains('television') || text.contains('mediarenderer')) {
      return DeviceCategory.television;
    }
    return null;
  }
}

class _SsdpResponse {
  const _SsdpResponse(this.headers);

  final Map<String, String> headers;

  static _SsdpResponse? parse(String text) {
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty ||
        !lines.first.toUpperCase().startsWith('HTTP/1.1 200')) {
      return null;
    }
    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      headers[line.substring(0, separator).trim().toLowerCase()] = line
          .substring(separator + 1)
          .trim();
    }
    return headers.containsKey('location') ? _SsdpResponse(headers) : null;
  }
}
