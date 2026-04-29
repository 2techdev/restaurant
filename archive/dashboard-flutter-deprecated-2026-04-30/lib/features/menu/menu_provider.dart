import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/models.dart';
import '../../core/auth/auth_provider.dart';

final selectedCategoryIdProvider = StateProvider.autoDispose<String?>((ref) => null);

final categoriesProvider = FutureProvider.autoDispose<List<MenuCategory>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final cats = await client.getCategories();
  // Auto-select first category
  if (ref.read(selectedCategoryIdProvider) == null && cats.isNotEmpty) {
    Future.microtask(() {
      ref.read(selectedCategoryIdProvider.notifier).state = cats.first.id;
    });
  }
  return cats;
});

final productsProvider = FutureProvider.autoDispose<List<Product>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final categoryId = ref.watch(selectedCategoryIdProvider);
  return client.getProducts(categoryId: categoryId);
});
