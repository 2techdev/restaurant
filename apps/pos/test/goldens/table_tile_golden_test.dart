/// Golden baseline: floor plan table tile.
///
/// Renders three table tiles (free / occupied / reserved) at 1920x1200 so
/// colour tokens, capacity badge and status chip regressions surface as a
/// pixel diff.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  testWidgets('golden :: table tile states', (tester) async {
    await pumpGolden(
      tester,
      child: const _TableTileMock(),
    );
    await matchScreenGolden(tester, 'table_tile');
  });
}

class _TableTileMock extends StatelessWidget {
  const _TableTileMock();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 900,
        child: Row(
          children: const [
            Expanded(
              child: _Tile(
                label: 'Masa 1',
                capacity: 4,
                statusLabel: 'Boş',
                statusColor: Color(0xFF10B981),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: _Tile(
                label: 'Masa 2',
                capacity: 2,
                statusLabel: 'Dolu',
                statusColor: Color(0xFFF59E0B),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: _Tile(
                label: 'Masa 3',
                capacity: 6,
                statusLabel: 'Rezerve',
                statusColor: Color(0xFFEF4444),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.capacity,
    required this.statusLabel,
    required this.statusColor,
  });

  final String label;
  final int capacity;
  final String statusLabel;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF282C35), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(38),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              const Icon(
                Icons.people_outline,
                size: 16,
                color: Color(0xFF94A3B8),
              ),
              const SizedBox(width: 6),
              Text(
                '$capacity kişilik',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
