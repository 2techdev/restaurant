/// DSFinV-K (Digitale Schnittstelle der Finanzverwaltung für Kassensysteme)
/// compliant export service.
///
/// Generates CSV files per the German DSFinV-K 2.3 standard. These files
/// must be provided to tax auditors on request (GoBD §§ 147 AO).
///
/// The export consists of four CSV datasets:
///   • Stammdaten (Z_KASSE_ID, Z_ERSTELLUNG, etc.) — master data
///   • Kassendaten (Z_GV_TYP, Z_KASSE_SERIENNR, etc.) — register data
///   • Einzelaufzeichnung (Z_GV_TYP per line) — individual transaction records
///   • TSE-Daten (TSE_ID, TSE_SIG, TSE_ZEIT, etc.) — TSE signatures
///
/// All monetary amounts in EUR with 5 decimal places (DSFinV-K §4.2).
library;

import 'package:intl/intl.dart';

// ---------------------------------------------------------------------------
// Input models
// ---------------------------------------------------------------------------

/// A single receipt record for DSFinV-K export.
class DsfinvkReceiptRecord {
  const DsfinvkReceiptRecord({
    required this.receiptId,
    required this.receiptNumber,
    required this.receiptDatetime,
    required this.kasseSerialNumber,
    required this.netAmountStandard,
    required this.vatAmountStandard,
    required this.netAmountReduced,
    required this.vatAmountReduced,
    required this.paymentType,
    required this.totalAmount,
    this.transactionNumber,
    this.signatureValue,
    this.signatureCounter,
    this.tseSerialNumber,
    this.signatureAlgorithm,
    this.signatureStartTime,
    this.signatureEndTime,
  });

  final String receiptId;
  final String receiptNumber;
  final DateTime receiptDatetime;
  final String kasseSerialNumber;

  /// Net (ex-VAT) amount at 19% rate in EUR.
  final double netAmountStandard;

  /// VAT amount at 19% in EUR.
  final double vatAmountStandard;

  /// Net (ex-VAT) amount at 7% rate in EUR.
  final double netAmountReduced;

  /// VAT amount at 7% in EUR.
  final double vatAmountReduced;

  /// DSFinV-K payment type code (e.g. 'Bar', 'Unbar').
  final String paymentType;

  /// Total gross amount in EUR.
  final double totalAmount;

  // TSE fields (optional — may be null if TSE not active)
  final int? transactionNumber;
  final String? signatureValue;
  final int? signatureCounter;
  final String? tseSerialNumber;
  final String? signatureAlgorithm;
  final DateTime? signatureStartTime;
  final DateTime? signatureEndTime;
}

/// Master data for the POS system (Stammdaten).
class DsfinvkStammdaten {
  const DsfinvkStammdaten({
    required this.kasseId,
    required this.kasseSerialNumber,
    required this.kasseFirmwareVersion,
    required this.taxIdNumber,
    required this.companyName,
    required this.companyStreet,
    required this.companyZip,
    required this.companyCity,
    required this.companyCountry,
  });

  final String kasseId;
  final String kasseSerialNumber;
  final String kasseFirmwareVersion;
  final String taxIdNumber;
  final String companyName;
  final String companyStreet;
  final String companyZip;
  final String companyCity;
  final String companyCountry;
}

// ---------------------------------------------------------------------------
// DSFinV-K Export Service
// ---------------------------------------------------------------------------

/// Generates DSFinV-K compliant CSV export data.
///
/// Returns a [DsfinvkExportResult] with the four CSV datasets as strings.
/// The caller is responsible for writing them to files or a ZIP archive.
class DsfinvkExportService {
  static final _dtFmt =
      DateFormat("yyyy-MM-dd'T'HH:mm:ss");
  static final _amtFmt = NumberFormat('0.00000', 'de_DE');

  /// Generates the complete DSFinV-K export.
  DsfinvkExportResult generateExport({
    required DsfinvkStammdaten stammdaten,
    required List<DsfinvkReceiptRecord> records,
    required DateTime exportStart,
    required DateTime exportEnd,
  }) {
    return DsfinvkExportResult(
      stammdatenCsv: _buildStammdaten(stammdaten, exportStart, exportEnd),
      kassendatenCsv: _buildKassendaten(records),
      einzelaufzeichnungCsv: _buildEinzelaufzeichnung(records),
      tseDatenCsv: _buildTseDaten(records),
      exportedAt: DateTime.now(),
      recordCount: records.length,
    );
  }

  // ---------------------------------------------------------------------------
  // Stammdaten (Z_KASSE_ID, master data)
  // ---------------------------------------------------------------------------

  String _buildStammdaten(
    DsfinvkStammdaten d,
    DateTime exportStart,
    DateTime exportEnd,
  ) {
    final sb = StringBuffer();
    // Header
    sb.writeln(
        'Z_KASSE_ID;Z_ERSTELLUNG;Z_NR;KASSE_SERIENNR;KASSE_SW_VERSION;'
        'TAXONOMIE_VERSION;STEUERNUMMER;NAME_DES_KASSENVERANTWORTLICHEN;'
        'STRASSE;PLZ;ORT;LAND');
    // One row per terminal
    sb.writeln(
      '${_csv(d.kasseId)};'
      '${_csv(_dtFmt.format(exportStart.toUtc()))};'
      '1;'
      '${_csv(d.kasseSerialNumber)};'
      '${_csv(d.kasseFirmwareVersion)};'
      '2.3;'
      '${_csv(d.taxIdNumber)};'
      '${_csv(d.companyName)};'
      '${_csv(d.companyStreet)};'
      '${_csv(d.companyZip)};'
      '${_csv(d.companyCity)};'
      '${_csv(d.companyCountry)}',
    );
    return sb.toString();
  }

  // ---------------------------------------------------------------------------
  // Kassendaten (register / Z-report level data)
  // ---------------------------------------------------------------------------

  String _buildKassendaten(List<DsfinvkReceiptRecord> records) {
    final sb = StringBuffer();
    sb.writeln(
        'Z_KASSE_ID;Z_ERSTELLUNG;Z_NR;Z_GV_TYP;Z_GV_NAME;'
        'Z_GV_BETRAG_BRUTTO;Z_GV_BETRAG_NETTO;Z_GV_STEUER;Z_GV_STEUERART');

    var zNr = 1;
    for (final r in records) {
      final brutto19 = r.netAmountStandard + r.vatAmountStandard;
      final brutto7 = r.netAmountReduced + r.vatAmountReduced;

      if (brutto19 != 0) {
        sb.writeln(
          '${_csv(r.kasseSerialNumber)};'
          '${_csv(_dtFmt.format(r.receiptDatetime.toUtc()))};'
          '$zNr;'
          'Umsatz;'
          'Umsatz 19%;'
          '${_amt(brutto19)};'
          '${_amt(r.netAmountStandard)};'
          '${_amt(r.vatAmountStandard)};'
          '1', // 1 = 19%
        );
      }
      if (brutto7 != 0) {
        sb.writeln(
          '${_csv(r.kasseSerialNumber)};'
          '${_csv(_dtFmt.format(r.receiptDatetime.toUtc()))};'
          '$zNr;'
          'Umsatz;'
          'Umsatz 7%;'
          '${_amt(brutto7)};'
          '${_amt(r.netAmountReduced)};'
          '${_amt(r.vatAmountReduced)};'
          '2', // 2 = 7%
        );
      }
      zNr++;
    }
    return sb.toString();
  }

  // ---------------------------------------------------------------------------
  // Einzelaufzeichnung (individual transaction records)
  // ---------------------------------------------------------------------------

  String _buildEinzelaufzeichnung(List<DsfinvkReceiptRecord> records) {
    final sb = StringBuffer();
    sb.writeln(
        'Z_KASSE_ID;BON_ID;BON_NR;BON_TYP;BON_NAME;'
        'DATUM;UHRZEIT;'
        'POS_ZEILE_ID;GV_TYP;GV_NAME;'
        'POS_BRUTTO;POS_NETTO;POS_UST;'
        'ZAHLART_TYP;ZAHLART_BETRAG');

    var posId = 1;
    for (final r in records) {
      final date = DateFormat('yyyy-MM-dd').format(r.receiptDatetime.toUtc());
      final time = DateFormat('HH:mm:ss').format(r.receiptDatetime.toUtc());

      final brutto19 = r.netAmountStandard + r.vatAmountStandard;
      if (brutto19 != 0) {
        sb.writeln(
          '${_csv(r.kasseSerialNumber)};'
          '${_csv(r.receiptId)};'
          '${_csv(r.receiptNumber)};'
          'Beleg;'
          'Kassenbeleg-V1;'
          '${_csv(date)};'
          '${_csv(time)};'
          '$posId;'
          'Umsatz;'
          'Umsatz 19%;'
          '${_amt(brutto19)};'
          '${_amt(r.netAmountStandard)};'
          '${_amt(r.vatAmountStandard)};'
          '${_csv(r.paymentType)};'
          '${_amt(r.totalAmount)}',
        );
        posId++;
      }

      final brutto7 = r.netAmountReduced + r.vatAmountReduced;
      if (brutto7 != 0) {
        sb.writeln(
          '${_csv(r.kasseSerialNumber)};'
          '${_csv(r.receiptId)};'
          '${_csv(r.receiptNumber)};'
          'Beleg;'
          'Kassenbeleg-V1;'
          '${_csv(date)};'
          '${_csv(time)};'
          '$posId;'
          'Umsatz;'
          'Umsatz 7%;'
          '${_amt(brutto7)};'
          '${_amt(r.netAmountReduced)};'
          '${_amt(r.vatAmountReduced)};'
          '${_csv(r.paymentType)};'
          '${_amt(r.totalAmount)}',
        );
        posId++;
      }
    }
    return sb.toString();
  }

  // ---------------------------------------------------------------------------
  // TSE-Daten (signature records)
  // ---------------------------------------------------------------------------

  String _buildTseDaten(List<DsfinvkReceiptRecord> records) {
    final sb = StringBuffer();
    sb.writeln(
        'Z_KASSE_ID;BON_ID;TSE_ID;TSE_TANR;TSE_SIGZ;'
        'TSE_SIG;TSE_SIG_ALGO;'
        'TSE_ZEIT_VON;TSE_ZEIT_BIS');

    for (final r in records) {
      if (r.tseSerialNumber == null) continue;
      sb.writeln(
        '${_csv(r.kasseSerialNumber)};'
        '${_csv(r.receiptId)};'
        '${_csv(r.tseSerialNumber!)};'
        '${r.transactionNumber ?? ""};'
        '${r.signatureCounter ?? ""};'
        '${_csv(r.signatureValue ?? "")};'
        '${_csv(r.signatureAlgorithm ?? "")};'
        '${r.signatureStartTime != null ? _csv(_dtFmt.format(r.signatureStartTime!.toUtc())) : ""};'
        '${r.signatureEndTime != null ? _csv(_dtFmt.format(r.signatureEndTime!.toUtc())) : ""}',
      );
    }
    return sb.toString();
  }

  // ---------------------------------------------------------------------------
  // Formatting helpers
  // ---------------------------------------------------------------------------

  /// Escapes and quotes a CSV field (semicolon-separated per DSFinV-K).
  String _csv(String value) {
    if (value.contains(';') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Formats a monetary amount to 5 decimal places (DSFinV-K §4.2).
  String _amt(double value) => _amtFmt.format(value);
}

// ---------------------------------------------------------------------------
// Result
// ---------------------------------------------------------------------------

/// The four DSFinV-K CSV datasets.
class DsfinvkExportResult {
  const DsfinvkExportResult({
    required this.stammdatenCsv,
    required this.kassendatenCsv,
    required this.einzelaufzeichnungCsv,
    required this.tseDatenCsv,
    required this.exportedAt,
    required this.recordCount,
  });

  /// Z_STAMM_KASSE (master data of the POS terminal).
  final String stammdatenCsv;

  /// Z_KASSE_ABSCHLUSS (register totals / Z-report level).
  final String kassendatenCsv;

  /// Z_TRANS (individual transaction records).
  final String einzelaufzeichnungCsv;

  /// Z_TSE (TSE signature data per transaction).
  final String tseDatenCsv;

  final DateTime exportedAt;
  final int recordCount;

  /// Map of filename → CSV content for easy ZIP packaging.
  Map<String, String> get files => {
        'Z_STAMM_KASSE.csv': stammdatenCsv,
        'Z_KASSE_ABSCHLUSS.csv': kassendatenCsv,
        'Z_TRANS.csv': einzelaufzeichnungCsv,
        'Z_TSE.csv': tseDatenCsv,
      };
}
