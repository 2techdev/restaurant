import 'package:equatable/equatable.dart';

class CustomerAddressEntity extends Equatable {
  final String id;
  final String customerId;
  final String label;
  final String street;
  final String city;
  final String postalCode;
  final String country;
  final bool isDefault;
  final DateTime createdAt;

  const CustomerAddressEntity({
    required this.id,
    required this.customerId,
    required this.label,
    required this.street,
    required this.city,
    required this.postalCode,
    this.country = 'CH',
    this.isDefault = false,
    required this.createdAt,
  });

  String get fullAddress => '$street, $postalCode $city, $country';

  CustomerAddressEntity copyWith({
    String? label,
    String? street,
    String? city,
    String? postalCode,
    String? country,
    bool? isDefault,
  }) {
    return CustomerAddressEntity(
      id: id,
      customerId: customerId,
      label: label ?? this.label,
      street: street ?? this.street,
      city: city ?? this.city,
      postalCode: postalCode ?? this.postalCode,
      country: country ?? this.country,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt,
    );
  }

  @override
  List<Object?> get props => [id, customerId, label, street, city,
      postalCode, country, isDefault, createdAt];
}
