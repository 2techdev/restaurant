import 'package:flutter_test/flutter_test.dart';

import 'package:gastrocore_pos/features/menu/domain/entities/modifier_entity.dart';

ModifierGroupEntity _group({
  int min = 0,
  int max = 1,
  int cols = 1,
  String prefix = '',
  bool isRequired = false,
}) {
  return ModifierGroupEntity(
    id: 'g',
    tenantId: 't',
    name: 'Group',
    selectionType: ModifierSelectionType.multiple,
    minSelections: min,
    maxSelections: max,
    isRequired: isRequired,
    displayOrder: 0,
    columnCount: cols,
    prefix: prefix,
  );
}

void main() {
  group('ModifierGroupEntity.hasUpperBound', () {
    test('is true when maxSelections > 0', () {
      expect(_group(max: 3).hasUpperBound, isTrue);
      expect(_group(max: 1).hasUpperBound, isTrue);
    });

    test('is false when maxSelections == 0 (unlimited / SambaPOS convention)',
        () {
      expect(_group(max: 0).hasUpperBound, isFalse);
    });
  });

  group('ModifierGroupEntity.isSelectionValid', () {
    test('rejects counts below min', () {
      final g = _group(min: 2, max: 5);
      expect(g.isSelectionValid(0), isFalse);
      expect(g.isSelectionValid(1), isFalse);
      expect(g.isSelectionValid(2), isTrue);
    });

    test('rejects counts above max when bounded', () {
      final g = _group(min: 0, max: 2);
      expect(g.isSelectionValid(2), isTrue);
      expect(g.isSelectionValid(3), isFalse);
    });

    test('accepts any count >= min when unbounded (max == 0)', () {
      final g = _group(min: 1, max: 0);
      expect(g.isSelectionValid(1), isTrue);
      expect(g.isSelectionValid(99), isTrue);
    });
  });

  group('ModifierGroupEntity.effectiveColumnCount', () {
    test('returns configured value when in range', () {
      expect(_group(cols: 3).effectiveColumnCount, 3);
    });

    test('clamps zero / negative to 1', () {
      expect(_group(cols: 0).effectiveColumnCount, 1);
      expect(_group(cols: -4).effectiveColumnCount, 1);
    });

    test('clamps values above upper bound', () {
      expect(_group(cols: kModifierColumnUpperBound + 1).effectiveColumnCount,
          kModifierColumnUpperBound);
      expect(_group(cols: 9999).effectiveColumnCount,
          kModifierColumnUpperBound);
    });
  });

  group('ModifierGroupEntity.displayName', () {
    test('returns bare name when prefix is empty', () {
      final g = _group(prefix: '');
      expect(g.displayName('Extra Cheese'), 'Extra Cheese');
    });

    test('concatenates prefix + name verbatim', () {
      // Prefix includes its own trailing space on purpose — receipts
      // want "+ Extra Cheese", not "+Extra Cheese".
      final g = _group(prefix: '+ ');
      expect(g.displayName('Extra Cheese'), '+ Extra Cheese');
    });

    test('handles negative-style prefixes', () {
      final g = _group(prefix: '- ');
      expect(g.displayName('Onions'), '- Onions');
    });
  });

  group('ModifierGroupEntity equality', () {
    test('equal when all richness fields match', () {
      final a = _group(min: 1, max: 3, cols: 2, prefix: '+ ');
      final b = _group(min: 1, max: 3, cols: 2, prefix: '+ ');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('unequal when prefix differs', () {
      final a = _group(prefix: '+ ');
      final b = _group(prefix: '- ');
      expect(a == b, isFalse);
    });

    test('unequal when columnCount differs', () {
      final a = _group(cols: 1);
      final b = _group(cols: 3);
      expect(a == b, isFalse);
    });
  });
}
