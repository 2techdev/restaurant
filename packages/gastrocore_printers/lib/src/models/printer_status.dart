/// Runtime health of a single printer.
library;

import 'printer_target.dart';

enum PrinterHealth {
  online,
  offline,
  error;

  String get wire {
    switch (this) {
      case PrinterHealth.online:
        return 'online';
      case PrinterHealth.offline:
        return 'offline';
      case PrinterHealth.error:
        return 'error';
    }
  }
}

class PrinterStatus {
  final String configId;
  final PrinterTarget target;
  final PrinterHealth health;
  final String? errorMessage;
  final DateTime? lastSeenAt;

  const PrinterStatus({
    required this.configId,
    required this.target,
    required this.health,
    this.errorMessage,
    this.lastSeenAt,
  });

  bool get isOnline => health == PrinterHealth.online;

  Map<String, dynamic> toJson() => {
        'config_id': configId,
        'target': target.wire,
        'health': health.wire,
        if (errorMessage != null) 'error_message': errorMessage,
        if (lastSeenAt != null) 'last_seen_at': lastSeenAt!.toIso8601String(),
      };

  @override
  String toString() =>
      'PrinterStatus($configId $target ${health.wire}${errorMessage != null ? ' — $errorMessage' : ''})';
}
