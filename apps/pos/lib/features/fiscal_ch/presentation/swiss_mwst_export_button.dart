/// Reports Center action that exports the current report window as a
/// Swiss-fiscal-compliant CSV + JSON pair and hands them to the OS share
/// sheet.
///
/// The service itself ([SwissMwstExportService]) is pure. This widget
/// handles the side-effect loop: pull tenant meta from the auth/tenant
/// providers, write the two files into the temp directory, and invoke
/// `share_plus`. Kept thin so the logic it delegates to is trivially
/// unit-testable.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:gastrocore_pos/features/auth/presentation/providers/auth_provider.dart';
import 'package:gastrocore_pos/features/fiscal_ch/domain/swiss_mwst_export.dart';
import 'package:gastrocore_pos/features/reports/domain/entities/report_entities.dart';

class SwissMwstExportButton extends ConsumerStatefulWidget {
  const SwissMwstExportButton({
    super.key,
    required this.snapshot,
    this.label = 'MWST CSV + JSON',
  });

  final ReportSnapshot snapshot;
  final String label;

  @override
  ConsumerState<SwissMwstExportButton> createState() =>
      _SwissMwstExportButtonState();
}

class _SwissMwstExportButtonState extends ConsumerState<SwissMwstExportButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final isEmpty = widget.snapshot.ticketCount == 0;
    return OutlinedButton.icon(
      onPressed: _busy || isEmpty ? null : _handle,
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.file_download_outlined),
      label: Text(widget.label),
    );
  }

  Future<void> _handle() async {
    setState(() => _busy = true);
    try {
      final user = ref.read(currentUserProvider);
      final tenantId = user?.tenantId ?? 'unknown-tenant';
      final meta = SwissFiscalMeta(
        tenantId: tenantId,
        restaurantName:
            (user?.name.isNotEmpty ?? false) ? 'GastroCore' : 'GastroCore',
        // MWST number is configured per-tenant elsewhere. Stored as an
        // empty string today; the CSV renders it as "—" so the file is
        // still importable while the settings screen is built out.
        mwstNumber: '',
      );
      final result = const SwissMwstExportService()
          .export(snapshot: widget.snapshot, meta: meta);

      final dir = await getTemporaryDirectory();
      final csvPath = p.join(dir.path, '${result.filenameBase}.csv');
      final jsonPath = p.join(dir.path, '${result.filenameBase}.json');
      await File(csvPath).writeAsString(result.csv, flush: true);
      await File(jsonPath).writeAsString(result.json, flush: true);

      await Share.shareXFiles(
        [
          XFile(csvPath, mimeType: 'text/csv'),
          XFile(jsonPath, mimeType: 'application/json'),
        ],
        subject: 'MWST-Auswertung',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('MWST export başarısız: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
