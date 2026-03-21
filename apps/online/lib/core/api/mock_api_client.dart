/// MockApiClient — returns embedded demo data without any HTTP requests.
/// Used when deployed outside a known GastroCore backend domain.
library;

import 'dart:async';
import 'package:gastrocore_online/core/api/api_client.dart';

class MockApiClient extends ApiClient {
  MockApiClient() : super(baseUrl: '');

  static const _restaurant = {
    'id': 'demo',
    'name': 'Restaurant GastroCore',
    'description': 'Frische Schweizer Küche · Cuisine suisse fraîche',
    'logo_url': null,
    'cover_image_url': null,
    'is_open': true,
    'closed_message': null,
    'estimated_wait_minutes': 20,
  };

  static const _categories = [
    {'id': 'cat-1', 'name': 'Vorspeisen', 'display_order': 1, 'color': '#FF9800', 'icon': ''},
    {'id': 'cat-2', 'name': 'Hauptgerichte', 'display_order': 2, 'color': '#E53935', 'icon': ''},
    {'id': 'cat-3', 'name': 'Pizza & Pasta', 'display_order': 3, 'color': '#7B1FA2', 'icon': ''},
    {'id': 'cat-4', 'name': 'Desserts', 'display_order': 4, 'color': '#00897B', 'icon': ''},
    {'id': 'cat-5', 'name': 'Getränke', 'display_order': 5, 'color': '#1976D2', 'icon': ''},
  ];

  static final _sizeGroup = {
    'id': 'mg-size',
    'name': 'Grösse',
    'selection_type': 'single',
    'min_selections': 1,
    'max_selections': 1,
    'is_required': true,
    'display_order': 1,
    'modifiers': [
      {'id': 'mod-s', 'group_id': 'mg-size', 'name': 'Klein', 'price_delta': -200, 'is_default': false, 'display_order': 1},
      {'id': 'mod-m', 'group_id': 'mg-size', 'name': 'Mittel', 'price_delta': 0, 'is_default': true, 'display_order': 2},
      {'id': 'mod-l', 'group_id': 'mg-size', 'name': 'Gross', 'price_delta': 300, 'is_default': false, 'display_order': 3},
    ],
  };

  List<Map<String, dynamic>> get _products => [
        // Vorspeisen
        {'id': 'p-1', 'category_id': 'cat-1', 'name': 'Gemischter Salat', 'description': 'Frischer Salat mit Saison-Gemüse und Vinaigrette', 'price': 1450, 'tax_group': 'standard', 'image_url': '', 'is_available': true, 'display_order': 1, 'modifier_groups': []},
        {'id': 'p-2', 'category_id': 'cat-1', 'name': 'Suppe des Tages', 'description': 'Täglich frisch zubereitet, mit Brot', 'price': 990, 'tax_group': 'standard', 'image_url': '', 'is_available': true, 'display_order': 2, 'modifier_groups': []},
        {'id': 'p-3', 'category_id': 'cat-1', 'name': 'Bruschetta', 'description': 'Röstbrot mit Tomaten, Basilikum und Knoblauch', 'price': 1190, 'tax_group': 'standard', 'image_url': '', 'is_available': true, 'display_order': 3, 'modifier_groups': []},
        // Hauptgerichte
        {'id': 'p-4', 'category_id': 'cat-2', 'name': 'Zürcher Geschnetzeltes', 'description': 'Kalbfleisch in Rahmsauce mit Rösti, klassisch zubereitet', 'price': 3490, 'tax_group': 'standard', 'image_url': '', 'is_available': true, 'display_order': 1, 'modifier_groups': []},
        {'id': 'p-5', 'category_id': 'cat-2', 'name': 'Poulet Cordon Bleu', 'description': 'Gefüllt mit Schinken und Käse, mit Pommes und Salat', 'price': 2990, 'tax_group': 'standard', 'image_url': '', 'is_available': true, 'display_order': 2, 'modifier_groups': []},
        {'id': 'p-6', 'category_id': 'cat-2', 'name': 'Veganes Gemüsecurry', 'description': 'Saisonales Gemüse in Kokosmilch, mit Basmati-Reis', 'price': 2290, 'tax_group': 'standard', 'image_url': '', 'is_available': true, 'display_order': 3, 'modifier_groups': []},
        // Pizza & Pasta
        {'id': 'p-7', 'category_id': 'cat-3', 'name': 'Pizza Margherita', 'description': 'Tomatensauce, Mozzarella, Basilikum', 'price': 1890, 'tax_group': 'standard', 'image_url': '', 'is_available': true, 'display_order': 1, 'modifier_groups': [_sizeGroup]},
        {'id': 'p-8', 'category_id': 'cat-3', 'name': 'Spaghetti Carbonara', 'description': 'Pancetta, Ei, Parmesan, Pfeffer — kein Rahm', 'price': 2190, 'tax_group': 'standard', 'image_url': '', 'is_available': true, 'display_order': 2, 'modifier_groups': []},
        {'id': 'p-9', 'category_id': 'cat-3', 'name': 'Penne al Arrabiata', 'description': 'Tomatensauce mit Chili und Knoblauch, vegan', 'price': 1890, 'tax_group': 'standard', 'image_url': '', 'is_available': true, 'display_order': 3, 'modifier_groups': []},
        // Desserts
        {'id': 'p-10', 'category_id': 'cat-4', 'name': 'Crème Brûlée', 'description': 'Klassische Vanillecreme mit Karamellkruste', 'price': 950, 'tax_group': 'standard', 'image_url': '', 'is_available': true, 'display_order': 1, 'modifier_groups': []},
        {'id': 'p-11', 'category_id': 'cat-4', 'name': 'Schokoladenfondue', 'description': 'Dunkle Schweizer Schokolade mit Früchten (für 2)', 'price': 1890, 'tax_group': 'standard', 'image_url': '', 'is_available': true, 'display_order': 2, 'modifier_groups': []},
        // Getränke
        {'id': 'p-12', 'category_id': 'cat-5', 'name': 'Mineralwasser', 'description': 'Still oder prickelnd, 0.5 l', 'price': 490, 'tax_group': 'standard', 'image_url': '', 'is_available': true, 'display_order': 1, 'modifier_groups': []},
        {'id': 'p-13', 'category_id': 'cat-5', 'name': 'Hausgemachte Limonade', 'description': 'Zitrone, Minze und Zucker, 0.4 l', 'price': 690, 'tax_group': 'standard', 'image_url': '', 'is_available': true, 'display_order': 2, 'modifier_groups': []},
        {'id': 'p-14', 'category_id': 'cat-5', 'name': 'Kaffee', 'description': 'Espresso, Cappuccino oder Filterkaffee', 'price': 490, 'tax_group': 'standard', 'image_url': '', 'is_available': true, 'display_order': 3, 'modifier_groups': []},
      ];

  @override
  Future<Map<String, dynamic>> fetchMenu(String restaurantId) async {
    await Future.delayed(const Duration(milliseconds: 250));
    return {
      'restaurant': Map<String, dynamic>.from(_restaurant)..['id'] = restaurantId,
      'categories': _categories,
      'products': _products,
    };
  }

  @override
  Future<Map<String, dynamic>> placeOrder(Map<String, dynamic> payload) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final ts = DateTime.now().millisecondsSinceEpoch;
    final id = 'demo-${ts.toString().substring(ts.toString().length - 6)}';
    return {
      'id': id,
      'order_number': 42,
      'status': 'received',
      'estimated_wait_minutes': 20,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  @override
  Future<Map<String, dynamic>> fetchOrderStatus(String orderId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return {
      'order_id': orderId,
      'order_number': 42,
      'status': 'received',
      'estimated_wait_minutes': 20,
    };
  }
}
