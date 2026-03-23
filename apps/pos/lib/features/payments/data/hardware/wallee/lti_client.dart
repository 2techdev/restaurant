import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// TCP client for the Wallee Local Till Interface (LTI) protocol.
///
/// Protocol:
///   - Terminal acts as server; this client initiates a new TCP connection
///     for every transaction.
///   - Each message is framed: [4-byte big-endian length][UTF-8 XML body].
///   - During a transaction the terminal sends intermediate frames
///     (displayNotification, printerNotification) before the final
///     financialTrxResponse / errorNotification.
///
/// LTI spec reference: Wallee LTI 2.52
class LtiClient {
  LtiClient({
    required this.host,
    required this.port,
    this.transactionTimeoutSeconds = 180,
  });

  final String host;
  final int port;

  /// Maximum seconds to wait for a terminal response.
  /// Must be longer than the gateway timeout so the terminal always responds
  /// before this client gives up (allows for customer PIN entry, chip dip, etc.).
  final int transactionTimeoutSeconds;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Opens a TCP connection, sends [xml] and waits for the final response frame.
  ///
  /// Throws on connection failure or timeout — callers must not increment
  /// the trxSyncNumber when an exception is thrown.
  Future<String> sendLtiMessage(String xml) async {
    final xmlBytes = utf8.encode(xml);
    final header = ByteData(4)..setUint32(0, xmlBytes.length, Endian.big);

    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 10),
    );

    try {
      socket.add(header.buffer.asUint8List());
      socket.add(xmlBytes);
      await socket.flush();
      return await _readUntilFinalResponse(socket);
    } catch (e) {
      rethrow;
    } finally {
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  /// Verify the terminal is reachable (quick TCP handshake, no LTI exchange).
  Future<bool> testConnection() async {
    try {
      final s = await Socket.connect(host, port, timeout: const Duration(seconds: 10));
      await s.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Frame reading
  // ---------------------------------------------------------------------------

  Future<String> _readUntilFinalResponse(Socket socket) async {
    final completer = Completer<String>();
    final buffer = BytesBuilder();
    final receivedTypes = <String>[];
    final startTime = DateTime.now();
    int frameCount = 0;

    String elapsedLabel() {
      return '[${DateTime.now().difference(startTime).inSeconds}s]';
    }

    late StreamSubscription<List<int>> sub;

    final timeoutTimer = Timer(Duration(seconds: transactionTimeoutSeconds), () {
      if (!completer.isCompleted) {
        sub.cancel();
        completer.completeError(
          TimeoutException(
            'LTI timeout after $transactionTimeoutSeconds s '
            '(frames: ${receivedTypes.join(", ")})',
          ),
        );
      }
    });

    final warningTimer = Timer.periodic(const Duration(seconds: 30), (t) {
      if (completer.isCompleted) {
        t.cancel();
      } else {
        final elapsed = DateTime.now().difference(startTime).inSeconds;
        debugPrint('[LtiClient] ${elapsedLabel()} Still waiting ($elapsed/${transactionTimeoutSeconds}s) '
            '— frames: ${receivedTypes.join(", ")}');
      }
    });

    sub = socket.listen(
      (chunk) {
        buffer.add(chunk);
        _processBuffer(
          buffer,
          frameCount,
          receivedTypes,
          completer,
          sub,
          timeoutTimer,
          warningTimer,
          elapsedLabel,
          (count) => frameCount = count,
        );
      },
      onError: (Object error, StackTrace st) {
        timeoutTimer.cancel();
        warningTimer.cancel();
        if (!completer.isCompleted) completer.completeError(error, st);
      },
      onDone: () {
        _onSocketDone(
          buffer,
          frameCount,
          receivedTypes,
          completer,
          timeoutTimer,
          warningTimer,
          elapsedLabel,
        );
      },
      cancelOnError: true,
    );

    return completer.future;
  }

  void _processBuffer(
    BytesBuilder buffer,
    int frameCount,
    List<String> receivedTypes,
    Completer<String> completer,
    StreamSubscription<List<int>> sub,
    Timer timeoutTimer,
    Timer warningTimer,
    String Function() elapsed,
    void Function(int) updateCount,
  ) {
    while (true) {
      final bytes = buffer.toBytes();
      if (bytes.length < 4) break;

      final expectedLen =
          ByteData.sublistView(Uint8List.fromList(bytes), 0, 4).getUint32(0, Endian.big);
      final totalLen = 4 + expectedLen;
      if (bytes.length < totalLen) break;

      final body = utf8.decode(bytes.sublist(4, totalLen));
      frameCount++;
      updateCount(frameCount);

      final remaining = bytes.sublist(totalLen);
      buffer.clear();
      if (remaining.isNotEmpty) buffer.add(remaining);

      final msgType = _messageType(body);
      receivedTypes.add(msgType);
      debugPrint('[LtiClient] ${elapsed()} Frame $frameCount: $msgType (${body.length} chars)');

      if (_isFinal(body)) {
        timeoutTimer.cancel();
        warningTimer.cancel();
        sub.cancel();
        if (!completer.isCompleted) completer.complete(body);
        return;
      }
    }
  }

  void _onSocketDone(
    BytesBuilder buffer,
    int frameCount,
    List<String> receivedTypes,
    Completer<String> completer,
    Timer timeoutTimer,
    Timer warningTimer,
    String Function() elapsed,
  ) {
    debugPrint('[LtiClient] ${elapsed()} Socket closed (frames: ${receivedTypes.join(", ")})');

    // Try to parse any remaining bytes as a complete frame
    if (buffer.length > 0) {
      try {
        final bytes = buffer.toBytes();
        if (bytes.length >= 4) {
          final expectedLen =
              ByteData.sublistView(Uint8List.fromList(bytes), 0, 4).getUint32(0, Endian.big);
          if (bytes.length >= 4 + expectedLen) {
            final body = utf8.decode(bytes.sublist(4, 4 + expectedLen));
            timeoutTimer.cancel();
            warningTimer.cancel();
            if (!completer.isCompleted) {
              completer.complete(body);
              return;
            }
          }
        }
      } catch (_) {}
    }

    timeoutTimer.cancel();
    warningTimer.cancel();
    if (!completer.isCompleted) {
      completer.completeError(
        StateError(
          'Terminal closed connection before final response. '
          'Frames received: $frameCount (${receivedTypes.join(", ")}). '
          'Terminal may be busy or the transaction was cancelled.',
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Protocol helpers
  // ---------------------------------------------------------------------------

  bool _isFinal(String xml) {
    final lower = xml.toLowerCase();
    const finalTypes = [
      'financialtrxresponse',
      'reversalresponse',
      'endofdayresponse',
      'pinpadinformationresponse',
      'pingresponse',
      'abortresponse',
      'errornotification',
    ];
    for (final t in finalTypes) {
      if (lower.contains('<$t') || lower.contains(':$t>') || lower.contains('</$t>')) {
        return true;
      }
    }
    // Content-based fallback: has "response" + transaction data
    if (lower.contains('response') &&
        (lower.contains('trxresult') ||
            lower.contains('authcode') ||
            lower.contains('ep2authcode'))) {
      return true;
    }
    return false;
  }

  String _messageType(String xml) {
    const types = [
      'financialTrxResponse',
      'financialTrxRequest',
      'displayNotification',
      'printerNotification',
      'errorNotification',
      'reversalResponse',
      'endOfDayResponse',
      'pingResponse',
      'pinpadInformationResponse',
      'abortResponse',
    ];
    for (final t in types) {
      if (xml.contains(t)) return t;
    }
    return 'unknown';
  }

  // ---------------------------------------------------------------------------
  // XML builders
  // ---------------------------------------------------------------------------

  /// financialTrxRequest — purchase (type=0) or refund (type=2).
  String buildFinancialTrxRequestXml({
    required String posId,
    required int amountMinorUnits,
    required int currencyNumeric,
    required int trxSyncNumber,
    required String merchantReference,
    int transactionType = 0,
  }) {
    return '''<?xml version="1.0" encoding="UTF-8"?>
<vcs-pos:financialTrxRequest xmlns:vcs-pos="http://www.vibbek.com/pos">
  <posId>$posId</posId>
  <trxSyncNumber>$trxSyncNumber</trxSyncNumber>
  <trxData>
    <amount>$amountMinorUnits</amount>
    <currency>$currencyNumeric</currency>
    <transactionType>$transactionType</transactionType>
    <merchantReference>$merchantReference</merchantReference>
  </trxData>
  <generatePanToken>false</generatePanToken>
  <receiptFormat>1</receiptFormat>
  <showTrxResultScreens>true</showTrxResultScreens>
</vcs-pos:financialTrxRequest>
''';
  }

  /// reversalRequest — voids the last transaction (or a specific seq count).
  String buildReversalRequestXml({required String posId, int? origTrxSeqCnt}) {
    final seqTag = origTrxSeqCnt != null
        ? '<origTrxSeqCnt>$origTrxSeqCnt</origTrxSeqCnt>'
        : '';
    return '''<?xml version="1.0" encoding="UTF-8"?>
<vcs-pos:reversalRequest xmlns:vcs-pos="http://www.vibbek.com/pos">
  <posId>$posId</posId>
  $seqTag
  <receiptFormat>1</receiptFormat>
  <tillMode>VTIApp</tillMode>
</vcs-pos:reversalRequest>
''';
  }

  /// endOfDayRequest — triggers settlement.
  String buildEndOfDayRequestXml({required String posId}) {
    return '''<?xml version="1.0" encoding="UTF-8"?>
<vcs-pos:endOfDayRequest xmlns:vcs-pos="http://www.vibbek.com/pos">
  <posId>$posId</posId>
  <receiptFormat>1</receiptFormat>
  <tillMode>VTIApp</tillMode>
</vcs-pos:endOfDayRequest>
''';
  }

  /// abortRequest — cancels the currently active transaction on the terminal.
  String buildAbortRequestXml({required String posId}) {
    return '''<?xml version="1.0" encoding="UTF-8"?>
<vcs-pos:abortRequest xmlns:vcs-pos="http://www.vibbek.com/pos">
  <posId>$posId</posId>
  <tillMode>VTIApp</tillMode>
</vcs-pos:abortRequest>
''';
  }

  Future<String> sendReversal({required String posId, int? origTrxSeqCnt}) =>
      sendLtiMessage(buildReversalRequestXml(posId: posId, origTrxSeqCnt: origTrxSeqCnt));

  Future<String> sendEndOfDay({required String posId}) =>
      sendLtiMessage(buildEndOfDayRequestXml(posId: posId));

  Future<String> sendAbort({required String posId}) =>
      sendLtiMessage(buildAbortRequestXml(posId: posId));
}
