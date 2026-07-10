import 'package:wifi_scan/features/discovery/domain/discovery_result.dart';

enum DiscoveryStage { preparing, probing, collecting, complete }

class DiscoveryProgress {
  const DiscoveryProgress({
    required this.stage,
    required this.completed,
    required this.total,
  });

  final DiscoveryStage stage;
  final int completed;
  final int total;

  double? get fraction => total == 0 ? null : completed / total;
}

class DiscoveryCancellationToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

class DiscoveryCancelledException implements Exception {
  const DiscoveryCancelledException();
}

class DiscoveryUnavailableException implements Exception {
  const DiscoveryUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class NetworkDiscoveryService {
  Future<DiscoveryResult> discover({
    required DiscoveryCancellationToken cancellationToken,
    required void Function(DiscoveryProgress progress) onProgress,
  });
}
