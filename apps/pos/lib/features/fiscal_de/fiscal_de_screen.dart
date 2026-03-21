/// German fiscal compliance settings screen.
///
/// Displays:
///   • TSE status (state, serial number, signature counter)
///   • Fiskaly API configuration (API key, secret, environment)
///   • Self-test trigger button
///   • DSFinV-K export trigger with date range picker
///
/// Only shown when country = DE is configured. In CH mode this screen
/// is not reachable via the settings navigation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fiskaly_models.dart';
import 'fiskaly_provider.dart';
import 'tse_lifecycle_service.dart';

class FiscalDeScreen extends ConsumerStatefulWidget {
  const FiscalDeScreen({super.key});

  @override
  ConsumerState<FiscalDeScreen> createState() => _FiscalDeScreenState();
}

class _FiscalDeScreenState extends ConsumerState<FiscalDeScreen> {
  final _apiKeyCtrl = TextEditingController();
  final _apiSecretCtrl = TextEditingController();
  final _adminPinCtrl = TextEditingController();
  final _clientIdCtrl = TextEditingController();
  var _env = 'test';
  bool _secretObscured = true;

  DateTime? _exportStart;
  DateTime? _exportEnd;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadConfig());
  }

  void _loadConfig() {
    final configAsync = ref.read(fiskalyConfigProvider);
    configAsync.whenData((config) {
      _apiKeyCtrl.text = config.apiKey;
      _apiSecretCtrl.text = config.apiSecret;
      _adminPinCtrl.text = config.adminPin;
      _clientIdCtrl.text = config.clientId ?? '';
      setState(() => _env = config.environment);
    });
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _apiSecretCtrl.dispose();
    _adminPinCtrl.dispose();
    _clientIdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tseAsync = ref.watch(tseStateProvider);
    final configAsync = ref.watch(fiskalyConfigProvider);
    final exportJob = ref.watch(exportJobProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Germany — Fiscal Compliance (KassenSichV)'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ----------------------------------------------------------------
            // TSE Status card
            // ----------------------------------------------------------------
            _SectionHeader(title: 'TSE Status', icon: Icons.security),
            const SizedBox(height: 8),
            tseAsync.when(
              data: (state) => _TseStatusCard(state: state),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  _ErrorCard(message: e.toString()),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: configAsync.hasValue
                      ? () => ref
                          .read(tseStateProvider.notifier)
                          .initialize()
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Initialize TSE'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: tseAsync.hasValue
                      ? () => ref
                          .read(tseStateProvider.notifier)
                          .runSelfTest()
                      : null,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Run Self-Test'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: tseAsync.hasValue
                      ? () => ref
                          .read(tseStateProvider.notifier)
                          .refresh()
                      : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // ----------------------------------------------------------------
            // Fiskaly API configuration
            // ----------------------------------------------------------------
            _SectionHeader(
                title: 'Fiskaly API Configuration',
                icon: Icons.api),
            const SizedBox(height: 8),
            _buildConfigForm(),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _saveConfig(),
              child: const Text('Save Configuration'),
            ),

            const SizedBox(height: 32),

            // ----------------------------------------------------------------
            // DSFinV-K export
            // ----------------------------------------------------------------
            _SectionHeader(
                title: 'DSFinV-K Export',
                icon: Icons.download_rounded),
            const SizedBox(height: 8),
            const Text(
              'Generate a DSFinV-K export for tax auditors. '
              'Leave dates empty to export all data.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickExportDate(isStart: true),
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_exportStart != null
                        ? _fmtDate(_exportStart!)
                        : 'Start Date (optional)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickExportDate(isStart: false),
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_exportEnd != null
                        ? _fmtDate(_exportEnd!)
                        : 'End Date (optional)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (exportJob != null) _ExportJobCard(state: exportJob),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => _triggerExport(),
              icon: const Icon(Icons.cloud_download),
              label: const Text('Trigger DSFinV-K Export'),
            ),

            const SizedBox(height: 32),

            // ----------------------------------------------------------------
            // Information
            // ----------------------------------------------------------------
            _SectionHeader(
                title: 'Legal Information', icon: Icons.info_outline),
            const SizedBox(height: 8),
            const _InfoCard(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Config form
  // ---------------------------------------------------------------------------

  Widget _buildConfigForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _apiKeyCtrl,
          decoration: const InputDecoration(
            labelText: 'API Key',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _apiSecretCtrl,
          obscureText: _secretObscured,
          decoration: InputDecoration(
            labelText: 'API Secret',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_secretObscured
                  ? Icons.visibility_off
                  : Icons.visibility),
              onPressed: () =>
                  setState(() => _secretObscured = !_secretObscured),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _adminPinCtrl,
          decoration: const InputDecoration(
            labelText: 'Admin PIN (TSE)',
            border: OutlineInputBorder(),
            hintText: 'e.g. 12345',
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _clientIdCtrl,
          decoration: const InputDecoration(
            labelText: 'Client ID (leave empty to auto-generate)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _env,
          decoration: const InputDecoration(
            labelText: 'Environment',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'test', child: Text('Test')),
            DropdownMenuItem(
                value: 'production', child: Text('Production')),
          ],
          onChanged: (v) => setState(() => _env = v ?? 'test'),
        ),
      ],
    );
  }

  Future<void> _saveConfig() async {
    final existing =
        ref.read(fiskalyConfigProvider).valueOrNull ??
            FiskalyConfig.empty();
    final updated = existing.copyWith(
      apiKey: _apiKeyCtrl.text.trim(),
      apiSecret: _apiSecretCtrl.text.trim(),
      adminPin: _adminPinCtrl.text.trim(),
      clientId: _clientIdCtrl.text.trim().isEmpty
          ? null
          : _clientIdCtrl.text.trim(),
      environment: _env,
    );
    await ref
        .read(fiskalyConfigProvider.notifier)
        .save(updated);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuration saved')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  Future<void> _pickExportDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _exportStart = picked;
      } else {
        _exportEnd = picked;
      }
    });
  }

  Future<void> _triggerExport() async {
    await ref.read(triggerExportProvider(DateRange(
      start: _exportStart,
      end: _exportEnd,
    )).future);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Export triggered — check status above')),
      );
    }
  }

  String _fmtDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}

class _TseStatusCard extends StatelessWidget {
  const _TseStatusCard({required this.state});

  final TseLifecycleState state;

  @override
  Widget build(BuildContext context) {
    final info = state.tseInfo;
    final stateColor = switch (state.tseState) {
      TseState.active => Colors.green,
      TseState.initialized => Colors.orange,
      TseState.created => Colors.blue,
      TseState.disabled => Colors.red,
      TseState.unknown => Colors.grey,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: stateColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  state.tseState.name.toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: stateColor,
                  ),
                ),
                if (state.isReady) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.verified,
                      color: Colors.green, size: 16),
                  const Text(' Ready to sign',
                      style: TextStyle(color: Colors.green)),
                ],
              ],
            ),
            if (info != null) ...[
              const SizedBox(height: 12),
              _InfoRow(
                  label: 'Serial Number', value: info.serialNumber),
              _InfoRow(
                  label: 'Algorithm',
                  value: info.signatureAlgorithm),
              _InfoRow(
                  label: 'Signature Counter',
                  value: '${info.signatureCounter}'),
              _InfoRow(label: 'TSE ID', value: info.id),
            ] else ...[
              const SizedBox(height: 8),
              const Text('No TSE configured. Click Initialize TSE.',
                  style: TextStyle(color: Colors.grey)),
            ],
            if (state.lastSelfTestAt != null) ...[
              const SizedBox(height: 8),
              _InfoRow(
                label: 'Last Self-Test',
                value: state.lastSelfTestAt!.toLocal().toString(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text('$label:',
                style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(message,
            style: TextStyle(
                color:
                    Theme.of(context).colorScheme.onErrorContainer)),
      ),
    );
  }
}

class _ExportJobCard extends StatelessWidget {
  const _ExportJobCard({required this.state});

  final ExportState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state.state) {
      'COMPLETED' => Colors.green,
      'FAILED' => Colors.red,
      _ => Colors.orange,
    };

    return Card(
      child: ListTile(
        leading: Icon(
          state.isCompleted ? Icons.check_circle : Icons.hourglass_top,
          color: color,
        ),
        title: Text('Export ${state.state}'),
        subtitle: Text(state.href ?? state.error ?? state.id),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'German fiscal law (KassenSichV, §146a AO) requires:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
                '• A certified TSE (Technische Sicherheitseinrichtung) must be used'),
            Text('• Every receipt must carry the TSE signature data'),
            Text(
                '• DSFinV-K exports must be available for tax authorities'),
            Text(
                '• Self-tests must be performed periodically (BSI TR-03153)'),
            SizedBox(height: 8),
            Text(
              'Fiskaly provides a cloud-based TSE certified by the BSI.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
