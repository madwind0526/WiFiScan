import 'dart:typed_data';

import 'package:wifi_scan/features/discovery/domain/router_dhcp_client.dart';

/// A read-only management connector for one router family.
///
/// Every connector logs in with credentials the user supplied, reads the
/// connected-device list, and does nothing else: no setting changes, no
/// password guessing, no queried data leaving the machine.
///
/// Supporting a new router means implementing this interface and registering
/// it — the UI routes on [requiresCaptcha] alone, so it needs no per-brand
/// branches.
abstract interface class RouterConnector {
  /// Stable identifier used in messages and tests (e.g. `iptime`).
  String get id;

  /// Router family name shown to the user (e.g. `ipTIME`).
  String get displayName;

  /// Whether [login] needs a captcha the user reads from [fetchCaptcha].
  ///
  /// Connectors that return false ignore the `captcha` argument, which lets
  /// the caller log in silently from saved credentials.
  bool get requiresCaptcha;

  /// Whether [host] looks like this router family. Probes read-only and
  /// returns false rather than throwing when the host is unreachable.
  Future<bool> matches(String host);

  /// Fetches the current captcha image for the user to read.
  ///
  /// Only meaningful when [requiresCaptcha]; other connectors throw
  /// [UnsupportedError].
  Future<Uint8List> fetchCaptcha(String host);

  /// Logs in and returns an opaque session token for [readDevices].
  ///
  /// Throws [RouterQueryException] with a user-facing message when the
  /// credentials are rejected or the router is unreachable.
  Future<String> login({
    required String host,
    required String username,
    required String password,
    String captcha,
  });

  /// Reads the router's connected-device (DHCP) list.
  ///
  /// Returns an empty list when the router exposes no known page; the caller
  /// treats that as "no data" rather than an error.
  Future<List<RouterDhcpClient>> readDevices({
    required String host,
    required String session,
  });

  /// Releases the underlying HTTP client. The owner of the connector calls
  /// this once the flow is done.
  void close();
}
