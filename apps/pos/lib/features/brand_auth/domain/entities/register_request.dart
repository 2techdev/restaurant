/// Request payload for new brand registration.
library;

class RegisterRequest {
  const RegisterRequest({
    required this.restaurantName,
    required this.ownerName,
    required this.email,
    required this.password,
    this.address,
    this.phone,
  });

  final String restaurantName;
  final String ownerName;
  final String email;
  final String password;
  final String? address;
  final String? phone;

  Map<String, dynamic> toJson() => {
        'restaurant_name': restaurantName,
        'owner_name': ownerName,
        'email': email,
        'password': password,
        if (address != null) 'address': address,
        if (phone != null) 'phone': phone,
      };
}
