import 'package:wifi_scan/features/discovery/domain/router_connector.dart';
import 'package:wifi_scan/features/discovery/infrastructure/iptime_router_connector.dart';
import 'package:wifi_scan/features/discovery/infrastructure/sk_gateway_connector.dart';

/// Builds a fresh connector to probe a host with.
typedef RouterConnectorFactory = RouterConnector Function();

/// Picks the connector that recognizes a given router.
///
/// Supporting a new router family means adding its factory to
/// [defaultFactories]; nothing else in the app branches on brand.
class RouterConnectorRegistry {
  const RouterConnectorRegistry({List<RouterConnectorFactory>? factories})
    : _factories = factories ?? defaultFactories;

  /// Probe order: families with the most distinctive markers come first.
  static const List<RouterConnectorFactory> defaultFactories = [
    SkGatewayConnector.new,
    IptimeRouterConnector.new,
  ];

  final List<RouterConnectorFactory> _factories;

  /// Returns a connector that recognizes [host], or null when no registered
  /// family matches — the caller then falls back to manual labelling.
  ///
  /// The caller owns the returned connector and must close it; connectors that
  /// do not match are closed here.
  Future<RouterConnector?> detect(String host) async {
    for (final factory in _factories) {
      final connector = factory();
      var matched = false;
      try {
        matched = await connector.matches(host);
      } catch (_) {
        // An unreachable or unexpected host is simply not a match.
        matched = false;
      }
      if (matched) return connector;
      connector.close();
    }
    return null;
  }
}
