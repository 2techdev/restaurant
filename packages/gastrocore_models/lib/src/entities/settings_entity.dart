/// Tenant / store settings bag.
///
/// Settings are intentionally unstructured (key / typed-value pairs) so
/// backoffice can add new keys without a schema migration. Consumers cast
/// via typed accessors and fall back to a default when a key is missing.
library;

/// Supported primitive value types. Kept small on purpose — complex
/// settings should use `json` with a known sub-schema.
enum SettingType { string, int, double, bool, json }

class SettingValue {
  final SettingType type;

  /// Raw JSON-compatible representation (String / int / double / bool / Map /
  /// List). Apps should use the typed accessors below.
  final Object? raw;

  const SettingValue({required this.type, required this.raw});

  String? asString() => raw is String ? raw as String : raw?.toString();

  int? asInt() {
    if (raw is int) return raw as int;
    if (raw is num) return (raw as num).toInt();
    if (raw is String) return int.tryParse(raw as String);
    return null;
  }

  double? asDouble() {
    if (raw is num) return (raw as num).toDouble();
    if (raw is String) return double.tryParse(raw as String);
    return null;
  }

  bool? asBool() {
    if (raw is bool) return raw as bool;
    if (raw is String) {
      final v = (raw as String).toLowerCase();
      if (v == 'true' || v == '1' || v == 'yes') return true;
      if (v == 'false' || v == '0' || v == 'no') return false;
    }
    return null;
  }

  Map<String, dynamic>? asMap() =>
      raw is Map ? Map<String, dynamic>.from(raw as Map) : null;

  factory SettingValue.fromJson(Map<String, dynamic> json) => SettingValue(
        type: SettingType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => SettingType.string,
        ),
        raw: json['value'],
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'value': raw,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingValue &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          raw == other.raw;

  @override
  int get hashCode => Object.hash(type, raw);

  @override
  String toString() => 'SettingValue(${type.name}=$raw)';
}

class SettingsEntity {
  final String id;
  final String tenantId;

  /// Optional — null means tenant-wide, non-null narrows to one store.
  final String? storeId;

  final Map<String, SettingValue> values;

  final DateTime updatedAt;

  const SettingsEntity({
    required this.id,
    required this.tenantId,
    this.storeId,
    required this.values,
    required this.updatedAt,
  });

  /// Read a setting, returning [fallback] if missing.
  T read<T>(String key, T fallback) {
    final v = values[key];
    if (v == null) return fallback;
    final out = switch (T) {
      const (String) => v.asString(),
      const (int) => v.asInt(),
      const (double) => v.asDouble(),
      const (bool) => v.asBool(),
      _ => v.raw,
    };
    return (out is T) ? out : fallback;
  }

  SettingsEntity set(String key, SettingValue value, {DateTime? now}) {
    final next = Map<String, SettingValue>.from(values)..[key] = value;
    return copyWith(values: next, updatedAt: now ?? DateTime.now());
  }

  factory SettingsEntity.fromJson(Map<String, dynamic> json) => SettingsEntity(
        id: json['id'] as String,
        tenantId: json['tenant_id'] as String,
        storeId: json['store_id'] as String?,
        values: ((json['values'] as Map<String, dynamic>?) ?? const {}).map(
          (k, v) => MapEntry(
            k,
            SettingValue.fromJson(v as Map<String, dynamic>),
          ),
        ),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tenant_id': tenantId,
        if (storeId != null) 'store_id': storeId,
        'values': values.map((k, v) => MapEntry(k, v.toJson())),
        'updated_at': updatedAt.toIso8601String(),
      };

  SettingsEntity copyWith({
    String? id,
    String? tenantId,
    String? Function()? storeId,
    Map<String, SettingValue>? values,
    DateTime? updatedAt,
  }) {
    return SettingsEntity(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      storeId: storeId != null ? storeId() : this.storeId,
      values: values ?? this.values,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SettingsEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          tenantId == other.tenantId &&
          storeId == other.storeId;

  @override
  int get hashCode => Object.hash(id, tenantId, storeId);

  @override
  String toString() =>
      'SettingsEntity(id: $id, tenant: $tenantId, store: $storeId, keys: ${values.length})';
}
