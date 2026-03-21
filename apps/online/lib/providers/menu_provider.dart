/// Menu data provider — fetches restaurant info, categories, and products
/// from the Go backend and caches them for the session.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gastrocore_online/core/api/api_client.dart';
import 'package:gastrocore_online/domain/models/menu_models.dart';

// ---------------------------------------------------------------------------
// API client provider (override baseUrl in main via ProviderScope overrides)
// ---------------------------------------------------------------------------

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(baseUrl: 'https://api.gastrocore.ch');
});

// ---------------------------------------------------------------------------
// Menu provider — AsyncNotifier keyed on restaurantId
// ---------------------------------------------------------------------------

final menuProvider = AsyncNotifierProviderFamily<MenuNotifier, OnlineMenu,
    String>(MenuNotifier.new);

class MenuNotifier extends FamilyAsyncNotifier<OnlineMenu, String> {
  @override
  Future<OnlineMenu> build(String restaurantId) async {
    return _fetch(restaurantId);
  }

  Future<OnlineMenu> _fetch(String restaurantId) async {
    final client = ref.read(apiClientProvider);
    final json = await client.fetchMenu(restaurantId);
    return OnlineMenu.fromJson(json);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(arg));
  }
}

// ---------------------------------------------------------------------------
// Demo/mock menu for development (when running without a backend)
// ---------------------------------------------------------------------------

OnlineMenu buildDemoMenu(String restaurantId) {
  final restaurant = OnlineRestaurant(
    id: restaurantId,
    name: 'Restaurant GastroCore',
    description: 'Frische Schweizer Küche · Cuisine suisse fraîche',
    isOpen: true,
    estimatedWaitMinutes: 20,
  );

  const categories = [
    OnlineCategory(
        id: 'cat-1', name: 'Vorspeisen', displayOrder: 1, color: '#FF9800'),
    OnlineCategory(
        id: 'cat-2',
        name: 'Hauptgerichte',
        displayOrder: 2,
        color: '#E53935'),
    OnlineCategory(
        id: 'cat-3', name: 'Pizza & Pasta', displayOrder: 3, color: '#7B1FA2'),
    OnlineCategory(
        id: 'cat-4', name: 'Desserts', displayOrder: 4, color: '#00897B'),
    OnlineCategory(
        id: 'cat-5', name: 'Getränke', displayOrder: 5, color: '#1976D2'),
  ];

  final sizeGroup = OnlineModifierGroup(
    id: 'mg-size',
    name: 'Grösse',
    selectionType: 'single',
    minSelections: 1,
    maxSelections: 1,
    isRequired: true,
    displayOrder: 1,
    modifiers: const [
      OnlineModifier(
          id: 'mod-s',
          groupId: 'mg-size',
          name: 'Klein',
          priceDelta: -200,
          isDefault: false,
          displayOrder: 1),
      OnlineModifier(
          id: 'mod-m',
          groupId: 'mg-size',
          name: 'Mittel',
          priceDelta: 0,
          isDefault: true,
          displayOrder: 2),
      OnlineModifier(
          id: 'mod-l',
          groupId: 'mg-size',
          name: 'Gross',
          priceDelta: 300,
          isDefault: false,
          displayOrder: 3),
    ],
  );

  final products = [
    // Vorspeisen
    OnlineProduct(
        id: 'p-1',
        categoryId: 'cat-1',
        name: 'Gemischter Salat',
        description: 'Frischer Salat mit Saison-Gemüse und Vinaigrette',
        price: 1450,
        taxGroup: 'standard',
        isAvailable: true,
        displayOrder: 1),
    OnlineProduct(
        id: 'p-2',
        categoryId: 'cat-1',
        name: 'Suppe des Tages',
        description: 'Täglich frisch zubereitet, mit Brot',
        price: 990,
        taxGroup: 'standard',
        isAvailable: true,
        displayOrder: 2),
    OnlineProduct(
        id: 'p-3',
        categoryId: 'cat-1',
        name: 'Bruschetta',
        description: 'Röstbrot mit Tomaten, Basilikum und Knoblauch',
        price: 1190,
        taxGroup: 'standard',
        isAvailable: true,
        displayOrder: 3),

    // Hauptgerichte
    OnlineProduct(
        id: 'p-4',
        categoryId: 'cat-2',
        name: 'Zürcher Geschnetzeltes',
        description:
            'Kalbfleisch in Rahmsauce mit Rösti, klassisch zubereitet',
        price: 3490,
        taxGroup: 'standard',
        isAvailable: true,
        displayOrder: 1),
    OnlineProduct(
        id: 'p-5',
        categoryId: 'cat-2',
        name: 'Poulet Cordon Bleu',
        description: 'Gefüllt mit Schinken und Käse, mit Pommes und Salat',
        price: 2990,
        taxGroup: 'standard',
        isAvailable: true,
        displayOrder: 2),
    OnlineProduct(
        id: 'p-6',
        categoryId: 'cat-2',
        name: 'Veganes Gemüsecurry',
        description: 'Saisonales Gemüse in Kokosmilch, mit Basmati-Reis',
        price: 2290,
        taxGroup: 'standard',
        isAvailable: true,
        displayOrder: 3),

    // Pizza & Pasta
    OnlineProduct(
        id: 'p-7',
        categoryId: 'cat-3',
        name: 'Pizza Margherita',
        description: 'Tomatensauce, Mozzarella, Basilikum',
        price: 1890,
        taxGroup: 'standard',
        isAvailable: true,
        displayOrder: 1,
        modifierGroups: [sizeGroup]),
    OnlineProduct(
        id: 'p-8',
        categoryId: 'cat-3',
        name: 'Spaghetti Carbonara',
        description: 'Pancetta, Ei, Parmesan, Pfeffer — kein Rahm',
        price: 2190,
        taxGroup: 'standard',
        isAvailable: true,
        displayOrder: 2),
    OnlineProduct(
        id: 'p-9',
        categoryId: 'cat-3',
        name: 'Penne al Arrabiata',
        description: 'Tomatensauce mit Chili und Knoblauch, vegan',
        price: 1890,
        taxGroup: 'standard',
        isAvailable: true,
        displayOrder: 3),

    // Desserts
    OnlineProduct(
        id: 'p-10',
        categoryId: 'cat-4',
        name: 'Crème Brûlée',
        description: 'Klassische Vanillecreme mit Karamellkruste',
        price: 950,
        taxGroup: 'standard',
        isAvailable: true,
        displayOrder: 1),
    OnlineProduct(
        id: 'p-11',
        categoryId: 'cat-4',
        name: 'Schokoladenfondue',
        description: 'Dunkle Schweizer Schokolade mit Früchten (für 2)',
        price: 1890,
        taxGroup: 'standard',
        isAvailable: true,
        displayOrder: 2),

    // Getränke
    OnlineProduct(
        id: 'p-12',
        categoryId: 'cat-5',
        name: 'Mineralwasser',
        description: 'Still oder prickelnd, 0.5 l',
        price: 490,
        taxGroup: 'standard',
        isAvailable: true,
        displayOrder: 1),
    OnlineProduct(
        id: 'p-13',
        categoryId: 'cat-5',
        name: 'Hausgemachte Limonade',
        description: 'Zitrone, Minze und Zucker, 0.4 l',
        price: 690,
        taxGroup: 'standard',
        isAvailable: true,
        displayOrder: 2),
    OnlineProduct(
        id: 'p-14',
        categoryId: 'cat-5',
        name: 'Kaffee',
        description: 'Espresso, Cappuccino oder Filterkaffee',
        price: 490,
        taxGroup: 'standard',
        isAvailable: true,
        displayOrder: 3),
  ];

  return OnlineMenu(
    restaurant: restaurant,
    categories: categories,
    products: products,
  );
}
