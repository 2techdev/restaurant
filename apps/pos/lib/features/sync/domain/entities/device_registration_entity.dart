/// Domain entity for device registration with the cloud.
library;

/// The type/role of the device in the restaurant.
enum DeviceType { pos, kds, kiosk, waiter }

/// A registered device in the cloud.
class DeviceRegistrationEntity {
  const DeviceRegistrationEntity({
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.businessId,
    required this.registeredAt,
    this.serverUrl,
  });

  final String deviceId;
  final String deviceName;
  final DeviceType deviceType;
  final String businessId;   // tenantId
  final DateTime registeredAt;
  final String? serverUrl;
}
