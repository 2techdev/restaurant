/// EcoCash V4.2 kiosk service — request/response models.
///
/// The kiosk is an HTTP/JSON service on TCP port 8080. Every body except
/// `/api/token` carries `"token": "..."`. Money is always int in minor
/// units (rappen for CHF). date_time is `"yyyy-MM-dd HH:mm:ss"` local.
library;

class ApiEnvelope<T> {
  final String code;
  final String? message;
  final T? data;

  const ApiEnvelope({required this.code, this.message, this.data});

  bool get isOk => code == '0000';

  factory ApiEnvelope.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>)? dataMapper,
  ) {
    final raw = json['data'];
    return ApiEnvelope<T>(
      code: (json['code'] ?? '').toString(),
      message: json['message'] as String?,
      data: (raw is Map<String, dynamic> && dataMapper != null)
          ? dataMapper(raw)
          : null,
    );
  }
}

class TokenData {
  final String token;
  TokenData(this.token);
  factory TokenData.fromJson(Map<String, dynamic> j) =>
      TokenData((j['token'] ?? '').toString());
}

class StatusData {
  final String deviceId, softwareVer, hardwareVar, workType, errorCode, message;
  final int status;
  const StatusData({
    required this.deviceId,
    required this.softwareVer,
    required this.hardwareVar,
    required this.status,
    required this.workType,
    required this.errorCode,
    required this.message,
  });
  factory StatusData.fromJson(Map<String, dynamic> j) => StatusData(
        deviceId: (j['device_id'] ?? '').toString(),
        softwareVer: (j['software_ver'] ?? '').toString(),
        hardwareVar: (j['hardware_var'] ?? '').toString(),
        status: (j['status'] as num?)?.toInt() ?? 0,
        workType: (j['work_type'] ?? '').toString(),
        errorCode: (j['error_code'] ?? '').toString(),
        message: (j['message'] ?? '').toString(),
      );
}

class SaleStartedData {
  final String? orderId;
  final String? transId;
  final int? amount;
  const SaleStartedData({this.orderId, this.transId, this.amount});
  factory SaleStartedData.fromJson(Map<String, dynamic> j) => SaleStartedData(
        orderId: j['order_id'] as String?,
        transId: j['trans_id'] as String?,
        amount: (j['amount'] as num?)?.toInt(),
      );
}

class CashDetail {
  final int value;
  final int type; // 1 = banknote, 2 = coin
  final int number;
  final int? inOut; // 0 = requested, 1 = deposited, 2 = paid out
  const CashDetail({
    required this.value,
    required this.type,
    required this.number,
    this.inOut,
  });
  factory CashDetail.fromJson(Map<String, dynamic> j) => CashDetail(
        value: (j['value'] as num).toInt(),
        type: (j['type'] as num).toInt(),
        number: (j['number'] as num?)?.toInt() ?? 0,
        inOut: (j['in_out'] as num?)?.toInt(),
      );
}

class TransactionData {
  final String deviceId, clientId, orderId, transType, transId, payType, userName;
  final int amount, result, refund, collectedAmount, dispensedAmount;
  final List<CashDetail> cashDetail;
  const TransactionData({
    required this.deviceId,
    required this.clientId,
    required this.orderId,
    required this.transType,
    required this.transId,
    required this.payType,
    required this.userName,
    required this.amount,
    required this.result,
    required this.refund,
    required this.collectedAmount,
    required this.dispensedAmount,
    required this.cashDetail,
  });
  factory TransactionData.fromJson(Map<String, dynamic> j) => TransactionData(
        deviceId: (j['device_id'] ?? '').toString(),
        clientId: (j['client_id'] ?? '').toString(),
        orderId: (j['order_id'] ?? '').toString(),
        transType: (j['trans_type'] ?? '').toString(),
        transId: (j['trans_id'] ?? '').toString(),
        payType: (j['pay_type'] ?? '').toString(),
        userName: (j['user_name'] ?? '').toString(),
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        result: (j['result'] as num?)?.toInt() ?? 0,
        refund: (j['refund'] as num?)?.toInt() ?? 0,
        collectedAmount: (j['collected_amount'] as num?)?.toInt() ?? 0,
        dispensedAmount: (j['dispensed_amount'] as num?)?.toInt() ?? 0,
        cashDetail: (j['cash_detail'] as List? ?? [])
            .map((e) => CashDetail.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Sale state machine — see SALE_FLOW.md.
enum CashCollectorState {
  idle,
  starting,
  awaitingCash,
  partial,
  paidEnough,
  dispensingChange,
  completed,
  cancelled,
  failed,
}

class CashCollectorTransaction {
  final String orderId;
  final String? transId;
  final int saleAmount;
  final String currency;
  final int collected;
  final int dispensed;
  final int refund;
  final CashCollectorState state;
  final String? errorMessage;
  const CashCollectorTransaction({
    required this.orderId,
    this.transId,
    required this.saleAmount,
    required this.currency,
    this.collected = 0,
    this.dispensed = 0,
    this.refund = 0,
    this.state = CashCollectorState.idle,
    this.errorMessage,
  });

  int get remaining =>
      saleAmount - collected < 0 ? 0 : saleAmount - collected;
  int get overpaid =>
      collected - saleAmount < 0 ? 0 : collected - saleAmount;
  bool get isTerminal =>
      state == CashCollectorState.completed ||
      state == CashCollectorState.cancelled ||
      state == CashCollectorState.failed;

  CashCollectorTransaction copyWith({
    String? transId,
    int? collected,
    int? dispensed,
    int? refund,
    CashCollectorState? state,
    String? errorMessage,
  }) =>
      CashCollectorTransaction(
        orderId: orderId,
        transId: transId ?? this.transId,
        saleAmount: saleAmount,
        currency: currency,
        collected: collected ?? this.collected,
        dispensed: dispensed ?? this.dispensed,
        refund: refund ?? this.refund,
        state: state ?? this.state,
        errorMessage: errorMessage,
      );
}
