# gastrocore_ui

Shared Flutter widget library for all GastroCore apps.

## Contents

- **`GastrocoreTheme`** — Material 3 dark theme with the Midnight Navy design system
- **`AppColors`** — Design-system color palette constants
- **`StatusBadge`** — Colored status chip for ticket/table/order status
- **`EmptyState`** — Empty list placeholder with icon, title, and optional action
- **`SkeletonLoader`** — Shimmer loading placeholder for lists and grids
- **`GastrocoreErrorWidget`** — Error display with retry button

## Usage

```dart
import 'package:gastrocore_ui/gastrocore_ui.dart';

// Apply theme
MaterialApp(
  theme: GastrocoreTheme.dark(),
  ...
)

// Status badge
StatusBadge(label: 'In Progress', color: AppColors.orange)

// Empty state
EmptyState(
  icon: Icons.receipt_long_outlined,
  title: 'No orders yet',
  subtitle: 'New orders will appear here',
)

// Skeleton loader
SkeletonLoader(width: double.infinity, height: 60)

// Error widget
GastrocoreErrorWidget(
  message: 'Failed to load menu',
  onRetry: () => ref.refresh(menuProvider),
)
```
