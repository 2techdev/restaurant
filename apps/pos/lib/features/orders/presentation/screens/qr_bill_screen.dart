/// Swiss QR-Bill screen.
///
/// Displays a payment slip in the standard Swiss QR-Bill layout:
///   - Left section: payment information (IBAN, amount, creditor, reference)
///   - Right section: QR code + amount in the "receipt" strip
///
/// The screen can pre-fill creditor info from restaurant settings and
/// debtor info from customer data. The QR data is fetched from the server
/// or generated locally using the Swiss QR-Bill spec.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

import 'package:gastrocore_pos/core/theme/app_colors.dart';
import 'package:gastrocore_pos/features/settings/domain/entities/restaurant_settings.dart';
import 'package:gastrocore_pos/features/settings/presentation/providers/settings_provider.dart';

// ---------------------------------------------------------------------------
// Provider — QR-Bill generation state
// ---------------------------------------------------------------------------

class _QRBillState {
  final bool isLoading;
  final String? error;
  final _QRBillData? data;

  const _QRBillState({this.isLoading = false, this.error, this.data});
}

class _QRBillData {
  final String qrData;
  final String iban;
  final String amountFormatted;
  final String creditorName;
  final String creditorAddress;
  final String? debtorName;
  final String? debtorAddress;
  final String referenceType;
  final String? reference;
  final String? message;

  const _QRBillData({
    required this.qrData,
    required this.iban,
    required this.amountFormatted,
    required this.creditorName,
    required this.creditorAddress,
    this.debtorName,
    this.debtorAddress,
    required this.referenceType,
    this.reference,
    this.message,
  });

  factory _QRBillData.fromJson(Map<String, dynamic> json) => _QRBillData(
        qrData: json['qr_data'] as String,
        iban: json['iban'] as String,
        amountFormatted: json['amount_formatted'] as String,
        creditorName: json['creditor_name'] as String,
        creditorAddress: json['creditor_address'] as String? ?? '',
        debtorName: json['debtor_name'] as String?,
        debtorAddress: json['debtor_address'] as String?,
        referenceType: json['reference_type'] as String? ?? 'NON',
        reference: json['reference'] as String?,
        message: json['message'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class QRBillScreen extends ConsumerStatefulWidget {
  const QRBillScreen({
    super.key,
    this.ticketId,
    this.amountCents,
    this.customerName,
    this.invoiceId,
  });

  final String? ticketId;
  final int? amountCents; // cents
  final String? customerName;
  final String? invoiceId;

  @override
  ConsumerState<QRBillScreen> createState() => _QRBillScreenState();
}

class _QRBillScreenState extends ConsumerState<QRBillScreen> {
  final _ibanCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  _QRBillState _state = const _QRBillState();

  @override
  void initState() {
    super.initState();
    if (widget.invoiceId != null) {
      _messageCtrl.text = 'Invoice ${widget.invoiceId}';
    }
    // Pre-fill IBAN from restaurant settings when ready
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefill());
  }

  void _prefill() {
    final settings = ref.read(restaurantSettingsProvider).valueOrNull;
    if (settings != null && settings.vatNumber.isNotEmpty) {
      // Use VAT number area as placeholder until IBAN configured
    }
  }

  @override
  void dispose() {
    _ibanCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final settings = ref.read(restaurantSettingsProvider).valueOrNull ??
        const RestaurantSettings();

    if (_ibanCtrl.text.trim().isEmpty) {
      setState(() => _state = const _QRBillState(error: 'Please enter IBAN'));
      return;
    }

    setState(() => _state = const _QRBillState(isLoading: true));

    final amountFr = widget.amountCents != null
        ? widget.amountCents! / 100.0
        : 0.0;

    try {
      // Build request body — mirrors QRBillRequest on the server
      final body = {
        'iban': _ibanCtrl.text.trim(),
        'creditor_name': settings.name.isNotEmpty ? settings.name : 'Restaurant',
        'creditor_street': settings.address,
        'creditor_zip': '',
        'creditor_city': '',
        'creditor_country': 'CH',
        'amount': amountFr,
        'currency': 'CHF',
        'reference_type': 'NON',
        'message': _messageCtrl.text.trim(),
        if (widget.invoiceId != null) 'invoice_id': widget.invoiceId,
        if (widget.customerName != null) 'debtor_name': widget.customerName,
      };

      final response = await http
          .post(
            Uri.parse('http://localhost:8080/api/invoices/qrbill'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = _QRBillData.fromJson(json);
        setState(() => _state = _QRBillState(data: data));
      } else {
        // Fallback: generate QR data locally without server round-trip
        final qrData = _buildLocalQRData(
          iban: _ibanCtrl.text.trim(),
          creditorName: settings.name.isNotEmpty ? settings.name : 'Restaurant',
          creditorStreet: settings.address,
          amount: amountFr,
          message: _messageCtrl.text.trim(),
        );
        setState(() => _state = _QRBillState(
              data: _QRBillData(
                qrData: qrData,
                iban: _ibanCtrl.text.trim(),
                amountFormatted: amountFr > 0
                    ? 'CHF ${amountFr.toStringAsFixed(2)}'
                    : 'CHF –.–',
                creditorName:
                    settings.name.isNotEmpty ? settings.name : 'Restaurant',
                creditorAddress: settings.address,
                referenceType: 'NON',
                message: _messageCtrl.text.trim().isNotEmpty
                    ? _messageCtrl.text.trim()
                    : null,
              ),
            ));
      }
    } catch (_) {
      // Offline: generate locally
      final amFr = widget.amountCents != null ? widget.amountCents! / 100.0 : 0.0;
      final settings2 = ref.read(restaurantSettingsProvider).valueOrNull ??
          const RestaurantSettings();
      final qrData = _buildLocalQRData(
        iban: _ibanCtrl.text.trim(),
        creditorName: settings2.name.isNotEmpty ? settings2.name : 'Restaurant',
        creditorStreet: settings2.address,
        amount: amFr,
        message: _messageCtrl.text.trim(),
      );
      setState(() => _state = _QRBillState(
            data: _QRBillData(
              qrData: qrData,
              iban: _ibanCtrl.text.trim(),
              amountFormatted: amFr > 0
                  ? 'CHF ${amFr.toStringAsFixed(2)}'
                  : 'CHF –.–',
              creditorName:
                  settings2.name.isNotEmpty ? settings2.name : 'Restaurant',
              creditorAddress: settings2.address,
              referenceType: 'NON',
              message: _messageCtrl.text.trim().isNotEmpty
                  ? _messageCtrl.text.trim()
                  : null,
            ),
          ));
    }
  }

  /// Builds Swiss QR-Bill data string locally (Swiss Payment Standards 2.0).
  String _buildLocalQRData({
    required String iban,
    required String creditorName,
    required String creditorStreet,
    required double amount,
    required String message,
  }) {
    final sb = StringBuffer();
    void w(String s) => sb.write('$s\r\n');

    w('SPC');
    w('0200');
    w('1');
    w(iban.replaceAll(' ', ''));
    w('S');
    w(creditorName);
    w(creditorStreet);
    w(''); // building no
    w(''); // zip
    w(''); // city
    w('CH');
    for (var i = 0; i < 7; i++) w(''); // ultimate creditor (reserved)
    w(amount > 0 ? amount.toStringAsFixed(2) : '');
    w('CHF');
    for (var i = 0; i < 7; i++) w(''); // debtor
    w('NON'); // reference type
    w(''); // reference
    w(message); // additional info
    w('EPD');
    w('');
    w('');

    return sb.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: _state.data != null
                ? _buildSlip(_state.data!)
                : _buildForm(),
          ),
        ],
      ),
    );
  }

  // ---- Top bar ----

  Widget _buildTopBar() {
    return Container(
      height: 56,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (_state.data != null) {
                setState(() => _state = const _QRBillState());
              } else {
                Navigator.of(context).maybePop();
              }
            },
            child: const Icon(Icons.arrow_back_rounded,
                color: AppColors.textSecondary),
          ),
          const SizedBox(width: 16),
          const Text(
            'Swiss QR-Bill',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.accentDim,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'ISO 20022',
              style: TextStyle(
                  fontSize: 10,
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const Spacer(),
          if (_state.data != null)
            GestureDetector(
              onTap: () =>
                  setState(() => _state = const _QRBillState()),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('New Bill',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary)),
              ),
            ),
        ],
      ),
    );
  }

  // ---- Form ----

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('PAYMENT DETAILS'),
          const SizedBox(height: 12),
          _card(children: [
            _field(
              label: 'IBAN (Creditor)',
              controller: _ibanCtrl,
              hint: 'CH56 0483 5012 3456 7800 9',
              formatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(r'[A-Za-z0-9 ]')),
                _IBANFormatter(),
              ],
            ),
            if (widget.amountCents != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _readonlyField(
                  label: 'Amount',
                  value:
                      'CHF ${(widget.amountCents! / 100).toStringAsFixed(2)}',
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _field(
                label: 'Message / Invoice Reference',
                controller: _messageCtrl,
                hint: 'Invoice #2024-001',
              ),
            ),
          ]),
          const SizedBox(height: 24),
          if (_state.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _state.error!,
                style:
                    const TextStyle(color: AppColors.red, fontSize: 13),
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _state.isLoading ? null : _generate,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: _state.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text(
                      'Generate QR-Bill',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- QR-Bill Slip ----

  Widget _buildSlip(_QRBillData data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Slip container — white background like actual paper
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.4)),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x18000000),
                    blurRadius: 16,
                    offset: Offset(0, 4))
              ],
            ),
            child: Column(
              children: [
                // Separator line (scissors)
                _ScissorDivider(),
                // Slip body
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left — receipt section
                      SizedBox(
                        width: 220,
                        child: _buildReceiptSection(data),
                      ),
                      // Vertical separator
                      Container(
                        width: 1,
                        height: 200,
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        color: Colors.black26,
                      ),
                      // Right — payment section
                      Expanded(child: _buildPaymentSection(data)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Copy IBAN button
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SlipAction(
                icon: Icons.copy_rounded,
                label: 'Copy IBAN',
                onTap: () {
                  Clipboard.setData(ClipboardData(
                      text: data.iban.replaceAll(' ', '')));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('IBAN copied'),
                        duration: Duration(seconds: 1)),
                  );
                },
              ),
              const SizedBox(width: 12),
              _SlipAction(
                icon: Icons.print_rounded,
                label: 'Print',
                onTap: () => _printSlip(data),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptSection(_QRBillData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'EMPFANGSSCHEIN',
          style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: Colors.black,
              letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),
        _slipLabel('Konto / Zahlbar an'),
        _slipValue(data.iban),
        _slipValue(data.creditorName),
        if (data.creditorAddress.isNotEmpty) _slipValue(data.creditorAddress),
        const SizedBox(height: 8),
        if (data.referenceType != 'NON' && data.reference != null) ...[
          _slipLabel('Referenz'),
          _slipValue(data.reference!),
          const SizedBox(height: 8),
        ],
        if (data.debtorName != null) ...[
          _slipLabel('Zahlbar durch'),
          _slipValue(data.debtorName!),
          if (data.debtorAddress != null) _slipValue(data.debtorAddress!),
          const SizedBox(height: 8),
        ],
        _slipLabel('Währung'),
        _slipValue('CHF'),
        const SizedBox(height: 4),
        _slipLabel('Betrag'),
        _slipValue(data.amountFormatted),
        const SizedBox(height: 16),
        // Signature box
        Container(
          height: 32,
          width: 80,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black38),
            borderRadius: BorderRadius.circular(2),
          ),
          child: const Center(
            child: Text('Datum / Unterschrift',
                style: TextStyle(fontSize: 6, color: Colors.black38),
                textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentSection(_QRBillData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ZAHLTEIL',
          style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: Colors.black,
              letterSpacing: 0.5),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // QR code
            QrImageView(
              data: data.qrData,
              version: QrVersions.auto,
              size: 140,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
              backgroundColor: Colors.white,
            ),
            const SizedBox(width: 16),
            // Amount column
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _slipLabel('Währung'),
                _slipValue('CHF'),
                const SizedBox(height: 8),
                _slipLabel('Betrag'),
                _slipValue(data.amountFormatted),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        _slipLabel('Konto / Zahlbar an'),
        _slipValue(data.iban),
        _slipValue(data.creditorName),
        if (data.creditorAddress.isNotEmpty) _slipValue(data.creditorAddress),
        if (data.referenceType != 'NON' && data.reference != null) ...[
          const SizedBox(height: 8),
          _slipLabel('Referenz'),
          _slipValue(data.reference!),
        ],
        if (data.message != null && data.message!.isNotEmpty) ...[
          const SizedBox(height: 8),
          _slipLabel('Zusätzliche Informationen'),
          _slipValue(data.message!),
        ],
        if (data.debtorName != null) ...[
          const SizedBox(height: 8),
          _slipLabel('Zahlbar durch'),
          _slipValue(data.debtorName!),
          if (data.debtorAddress != null) _slipValue(data.debtorAddress!),
        ] else ...[
          const SizedBox(height: 8),
          _slipLabel('Zahlbar durch (Name/Adresse/PLZ/Ort)'),
          Container(
            height: 52,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black12),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _printSlip(_QRBillData _) async {
    // TODO: integrate with PrinterService to send slip to printer
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Printing not yet connected to printer service')),
    );
  }

  // ---- Helpers ----

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textDim,
                letterSpacing: 1.2)),
      );

  Widget _card({required List<Widget> children}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.4)),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDim)),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: formatters,
            style: const TextStyle(
                fontSize: 14, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                  fontSize: 13, color: AppColors.textDim),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              filled: true,
              fillColor: AppColors.surfaceContainerLow,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: AppColors.border.withValues(alpha: 0.4))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: AppColors.border.withValues(alpha: 0.4))),
            ),
          ),
        ],
      );

  Widget _readonlyField({required String label, required String value}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDim)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.border.withValues(alpha: 0.3)),
            ),
            child: Text(value,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ),
        ],
      );

  Widget _slipLabel(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 7,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
            letterSpacing: 0.2),
      );

  Widget _slipValue(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w500, color: Colors.black),
      );
}

// ---------------------------------------------------------------------------
// Scissor divider
// ---------------------------------------------------------------------------

class _ScissorDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const Icon(Icons.content_cut_rounded,
              size: 14, color: Colors.black38),
          Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: const Divider(
                  color: Colors.black26, height: 1, thickness: 1),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slip action button
// ---------------------------------------------------------------------------

class _SlipAction extends StatelessWidget {
  const _SlipAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// IBAN formatter
// ---------------------------------------------------------------------------

class _IBANFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text.replaceAll(' ', '').toUpperCase();
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length && i < 26; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(raw[i]);
    }
    final text = buffer.toString();
    return newValue.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
