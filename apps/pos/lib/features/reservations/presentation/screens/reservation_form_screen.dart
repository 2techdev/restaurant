/// ReservationFormScreen: create or edit a reservation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:gastrocore_pos/features/reservations/domain/entities/reservation_entity.dart';
import 'package:gastrocore_pos/features/reservations/presentation/providers/reservation_provider.dart';
import 'package:gastrocore_pos/features/tables/presentation/providers/table_provider.dart';
import 'package:gastrocore_pos/l10n/app_localizations.dart';

class ReservationFormScreen extends ConsumerStatefulWidget {
  /// Null = create mode; non-null = edit mode.
  final String? reservationId;

  const ReservationFormScreen({super.key, this.reservationId});

  @override
  ConsumerState<ReservationFormScreen> createState() =>
      _ReservationFormScreenState();
}

class _ReservationFormScreenState
    extends ConsumerState<ReservationFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  DateTime _date = DateTime.now();
  TimeOfDay _timeStart = const TimeOfDay(hour: 19, minute: 0);
  TimeOfDay _timeEnd = const TimeOfDay(hour: 21, minute: 0);
  int _partySize = 2;
  String? _selectedTableId;
  ReservationChannel _channel = ReservationChannel.phone;
  ReservationStatus _status = ReservationStatus.confirmed;

  bool _isEdit = false;
  bool _initialized = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _initFromEntity(ReservationEntity r) {
    _nameCtrl.text = r.customerName;
    _phoneCtrl.text = r.customerPhone ?? '';
    _emailCtrl.text = r.customerEmail ?? '';
    _notesCtrl.text = r.notes ?? '';
    _date = r.date;
    _timeStart = TimeOfDay.fromDateTime(r.timeStart);
    _timeEnd = TimeOfDay.fromDateTime(r.timeEnd);
    _partySize = r.partySize;
    _selectedTableId = r.tableId;
    _channel = r.channel;
    _status = r.status;
  }

  DateTime _toDateTime(DateTime date, TimeOfDay time) => DateTime(
        date.year, date.month, date.day, time.hour, time.minute);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _timeStart : _timeEnd,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _timeStart = picked;
          // Auto-set end +2h
          _timeEnd = TimeOfDay(
            hour: (picked.hour + 2) % 24,
            minute: picked.minute,
          );
        } else {
          _timeEnd = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(reservationManagementProvider.notifier);
    final timeStart = _toDateTime(_date, _timeStart);
    final timeEnd = _toDateTime(_date, _timeEnd);

    if (!timeEnd.isAfter(timeStart)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time')),
      );
      return;
    }

    bool success;
    if (_isEdit) {
      success = await notifier.updateReservation(
        id: widget.reservationId!,
        customerName: _nameCtrl.text.trim(),
        customerPhone: _phoneCtrl.text.trim().isEmpty
            ? null
            : _phoneCtrl.text.trim(),
        customerEmail: _emailCtrl.text.trim().isEmpty
            ? null
            : _emailCtrl.text.trim(),
        tableId: _selectedTableId,
        date: _date,
        timeStart: timeStart,
        timeEnd: timeEnd,
        partySize: _partySize,
        status: _status,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        channel: _channel,
      );
    } else {
      final entity = await notifier.createReservation(
        customerName: _nameCtrl.text.trim(),
        customerPhone: _phoneCtrl.text.trim().isEmpty
            ? null
            : _phoneCtrl.text.trim(),
        customerEmail: _emailCtrl.text.trim().isEmpty
            ? null
            : _emailCtrl.text.trim(),
        tableId: _selectedTableId,
        date: _date,
        timeStart: timeStart,
        timeEnd: timeEnd,
        partySize: _partySize,
        status: _status,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        channel: _channel,
      );
      success = entity != null;
    }

    if (!mounted) return;

    final state = ref.read(reservationManagementProvider);
    if (state.conflictTableId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Table already reserved at that time'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    if (success) {
      context.pop();
    } else if (state.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.error!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    _isEdit = widget.reservationId != null;

    // For edit mode: load existing reservation once
    if (_isEdit && !_initialized) {
      final existing =
          ref.watch(reservationByIdProvider(widget.reservationId!));
      existing.whenData((r) {
        if (r != null && !_initialized) {
          _initialized = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() => _initFromEntity(r));
          });
        }
      });
    } else {
      _initialized = true;
    }

    final allTables = ref.watch(allTablesProvider);
    final isLoading =
        ref.watch(reservationManagementProvider).isLoading;

    final dateFmt = DateFormat('EEE, d MMM yyyy');
    final timeFmt = DateFormat('HH:mm');
    final startDt = _toDateTime(_date, _timeStart);
    final endDt = _toDateTime(_date, _timeEnd);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Reservation' : 'New Reservation'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---- Customer ----
            Text('Guest Information',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Guest Name',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(
                labelText: 'Phone',
                prefixIcon: Icon(Icons.phone),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 20),

            // ---- Date & Time ----
            Text('Date & Time',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text(dateFmt.format(_date)),
                    onPressed: _pickDate,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule),
                    label: Text(
                      '${timeFmt.format(startDt)} – ${timeFmt.format(endDt)}',
                    ),
                    onPressed: () => _pickTime(true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _pickTime(false),
                  child: const Text('Change End Time'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ---- Party size ----
            Row(
              children: [
                Expanded(
                  child: Text('Party Size',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _partySize > 1
                      ? () => setState(() => _partySize--)
                      : null,
                ),
                Text('$_partySize',
                    style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setState(() => _partySize++),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ---- Table ----
            Text('Table',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            allTables.when(
              loading: () =>
                  const LinearProgressIndicator(),
              error: (e, _) => Text(e.toString()),
              data: (tables) {
                // Filter tables by capacity >= partySize
                final eligible = tables
                    .where((t) => t.capacity >= _partySize)
                    .toList();
                return DropdownButtonFormField<String?>(
                  initialValue: _selectedTableId,
                  decoration: const InputDecoration(
                    labelText: 'Table (optional)',
                    prefixIcon: Icon(Icons.table_restaurant),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('No table assigned'),
                    ),
                    ...eligible.map(
                      (t) => DropdownMenuItem(
                        value: t.id,
                        child: Text('${t.name} (cap: ${t.capacity})'),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _selectedTableId = v),
                );
              },
            ),
            const SizedBox(height: 20),

            // ---- Channel & Status ----
            Text('Booking Info',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<ReservationChannel>(
              initialValue: _channel,
              decoration: const InputDecoration(
                labelText: 'Source',
                prefixIcon: Icon(Icons.record_voice_over),
                border: OutlineInputBorder(),
              ),
              items: ReservationChannel.values
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(_channelLabel(c)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _channel = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ReservationStatus>(
              initialValue: _status,
              decoration: const InputDecoration(
                labelText: 'Status',
                prefixIcon: Icon(Icons.flag),
                border: OutlineInputBorder(),
              ),
              items: [
                ReservationStatus.pending,
                ReservationStatus.confirmed,
              ]
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(_statusLabel(s)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _status = v!),
            ),
            const SizedBox(height: 20),

            // ---- Notes ----
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes',
                prefixIcon: Icon(Icons.notes),
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: isLoading ? null : _submit,
              icon: isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(l10n.actionSave),
            ),
          ],
        ),
      ),
    );
  }

  String _channelLabel(ReservationChannel c) =>
      switch (c) {
        ReservationChannel.walkIn => 'Walk-In',
        ReservationChannel.online => 'Online',
        ReservationChannel.phone => 'Phone',
      };

  String _statusLabel(ReservationStatus s) =>
      switch (s) {
        ReservationStatus.pending => 'Pending',
        ReservationStatus.confirmed => 'Confirmed',
        _ => 'Pending',
      };
}
