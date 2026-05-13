/**
 * MyPOS Sigma Terminal Plugin — GastroCore POS
 *
 * WiFi (TCP/IP) connectivity only. USB and Bluetooth are not used.
 *
 * Features:
 *  - TCP/IP WiFi connection via MyPOS SlaveSDK
 *  - Periodic heartbeat PING (60 s) to detect connection loss
 *  - 15 s ICMP watchdog thread for network-level monitoring
 *  - Automatic reconnect with linear back-off (max 10 attempts)
 *  - Pre-payment connection verification via real PING
 *  - Card purchase, TWINT purchase, refund, cancel, batch clear
 */
package com.gastrocore.gastrocore_pos

import android.app.Activity
import android.bluetooth.BluetoothDevice
import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.mypos.slavesdk.*
import java.util.UUID
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

private const val TAG = "MyPosPlugin"
private const val RECONNECT_DELAY_MS = 3000L
private const val MAX_RECONNECT_ATTEMPTS = 10
private const val HEARTBEAT_INTERVAL_MS = 60000L  // TCP/IP only

class MyPosPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var logChannel: EventChannel
    private var logSink: EventChannel.EventSink? = null
    private var activity: Activity? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var posHandler: POSHandler? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pingResult: MethodChannel.Result? = null
    private var tcpIp: String = "192.168.1.131"
    private var tcpPort: Int = 60180

    // Connection state
    private var connectionState: ConnectionState = ConnectionState.DISCONNECTED
    private var isConfigured: Boolean = false
    private var reconnectAttempts: Int = 0
    private var isReconnecting: Boolean = false
    private var lastSuccessfulPingTime: Long = 0
    private var heartbeatRunnable: Runnable? = null
    private var isPaymentInProgress: Boolean = false

    // Watchdog (ICMP ping in background thread)
    @Volatile private var watchdogActive = false
    private var watchdogThread: Thread? = null

    enum class ConnectionState { DISCONNECTED, CONNECTING, CONNECTED, RECONNECTING }

    // =========================================================================
    // Plugin lifecycle
    // =========================================================================

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "mypos_payment")
        channel.setMethodCallHandler(this)

        logChannel = EventChannel(binding.binaryMessenger, "mypos_logs")
        logChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { logSink = events }
            override fun onCancel(arguments: Any?) { logSink = null }
        })

        POSHandler.setApplicationContext(binding.applicationContext)
        sendLog("✅ MyPOS plugin attached (TCP/IP mode)")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopHeartbeat()
        stopWatchdog()
        channel.setMethodCallHandler(null)
    }

    private var activityBinding: ActivityPluginBinding? = null

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        // Required for TWINT: the SDK's `openPaymentActivity` returns via
        // onActivityResult, which Flutter only forwards if the plugin is
        // registered as an ActivityResultListener.
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivity() {
        stopHeartbeat()
        stopWatchdog()
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    // =========================================================================
    // Method channel dispatch
    // =========================================================================

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configure"          -> handleConfigure(call, result)
            "disconnect"         -> handleDisconnect(result)
            "isConnected"        -> result.success(mapOf("connected" to (connectionState == ConnectionState.CONNECTED)))
            "checkRealConnection"-> handleCheckRealConnection(result)
            "pingTerminal"       -> handlePingTerminal(result)
            "testConnection"     -> result.success(mapOf("success" to (connectionState == ConnectionState.CONNECTED)))
            "processPayment"     -> handlePayment(call, result)
            "twintPurchase"      -> handleTwint(call, result)
            "refund"             -> handleRefund(call, result)
            "cancelPayment"      -> handleCancel(result)
            "clearBatch"         -> handleClearBatch(result)
            "isTerminalBusy"     -> result.success(mapOf("busy" to (posHandler?.isTerminalBusy() ?: false)))
            else                 -> result.notImplemented()
        }
    }

    // =========================================================================
    // Configure (TCP/IP)
    // =========================================================================

    private fun handleConfigure(call: MethodCall, result: MethodChannel.Result) {
        val type = call.argument<String>("type") ?: "tcp"
        if (type != "tcp") {
            sendLog("❌ Only TCP/IP is supported in GastroCore POS")
            result.success(mapOf("success" to false, "error" to "Only TCP/IP supported"))
            return
        }

        tcpIp = call.argument<String>("ip") ?: tcpIp
        tcpPort = call.argument<Int>("port") ?: tcpPort

        sendLog("⚙️ Configuring TCP/IP: $tcpIp:$tcpPort")
        updateConnectionState(ConnectionState.CONNECTING, "configure called")

        try {
            if (posHandler == null) {
                posHandler = POSHandler.getInstance()
                setupListeners()
            }

            // SDK 2.1.8: setConnectionType and setTcpIpConnectivity are static
            POSHandler.setConnectionType(ConnectionType.TCP_IP)
            POSHandler.setTcpIpConnectivity(tcpIp, tcpPort)

            activity?.let { ctx ->
                posHandler?.connectDevice(ctx)
                isConfigured = true
                sendLog("📡 TCP connect initiated to $tcpIp:$tcpPort")
                // Report success optimistically; real state comes via listener
                result.success(mapOf("success" to true))
                startWatchdog()
                startHeartbeat()
            } ?: run {
                sendLog("❌ Activity not available")
                result.success(mapOf("success" to false, "error" to "Activity not available"))
            }
        } catch (e: Exception) {
            sendLog("❌ Configure error: ${e.message}")
            updateConnectionState(ConnectionState.DISCONNECTED, "configure exception")
            result.success(mapOf("success" to false, "error" to e.message))
        }
    }

    private fun handleDisconnect(result: MethodChannel.Result) {
        stopHeartbeat()
        stopWatchdog()
        try {
            posHandler?.resetTcpConnection()
        } catch (_: Exception) {}
        isConfigured = false
        reconnectAttempts = 0
        updateConnectionState(ConnectionState.DISCONNECTED, "explicit disconnect")
        result.success(mapOf("success" to true))
    }

    private fun handleCheckRealConnection(result: MethodChannel.Result) {
        // Kit Troubleshooting §7: SDK 2.1.8's `isConnected()` is NOT a pure
        // state check — it sends an OOB byte over the socket; if the byte
        // fails to deliver, the SDK fires `onDisconnected` immediately.
        // Calling it on every payment was actively destroying the very
        // connection it was trying to verify. Trust our own state machine
        // (driven by the ConnectionListener) instead — it tracks the
        // SDK's view without the side effect.
        val connected = connectionState == ConnectionState.CONNECTED && isPosReady
        sendLog("🔍 checkRealConnection: state=$connectionState ready=$isPosReady → $connected")
        result.success(mapOf("connected" to connected))
    }

    private fun handlePingTerminal(result: MethodChannel.Result) {
        if (pingResult != null) {
            result.success(mapOf("success" to false, "connected" to false, "error" to "Ping already in progress"))
            return
        }
        pingResult = result
        try {
            posHandler?.checkConnection()
            // Response handled in POSInfoListener
            mainHandler.postDelayed({
                if (pingResult != null) {
                    sendLog("⏰ Ping timeout")
                    pingResult?.success(mapOf("success" to false, "connected" to false))
                    pingResult = null
                    if (connectionState == ConnectionState.CONNECTED) {
                        updateConnectionState(ConnectionState.DISCONNECTED, "ping timeout")
                    }
                }
            }, 5000)
        } catch (e: Exception) {
            pingResult = null
            result.success(mapOf("success" to false, "connected" to false))
        }
    }

    // =========================================================================
    // Payment operations
    // =========================================================================

    private fun handlePayment(call: MethodCall, result: MethodChannel.Result) {
        val amount = call.argument<Double>("amount") ?: run {
            result.success(mapOf("success" to false, "error" to "Missing amount"))
            return
        }
        val currency = call.argument<String>("currency") ?: "CHF"

        // 🚨 CRITICAL — operator reported "first payment auto-approves
        // without card tap, second works". Symptom of a queued/stale
        // `onTransactionComplete` event from a previous session firing
        // *after* we set pendingResult on the new payment. Hard-reset
        // any lingering session state here so the only outcome that can
        // close this ticket is a fresh SDK callback we triggered
        // ourselves.
        resetPaymentSessionState("handlePayment entry")

        ensureConnectionBeforePayment(
            onReady = {
                pendingResult = result
                pendingOp = "purchase"
                isPaymentInProgress = true
                // Stamp the start time *immediately before* we tell the SDK
                // to begin — used by onTransactionComplete to filter out
                // any stale event with an older transactionDateLocal.
                cardStartedAt = System.currentTimeMillis()
                try {
                    // Bundle alignment (2026-05-13):
                    //  1) Pin the SDK's currency only when it differs from
                    //     the last call. Pre-cache patch the SDK call fired
                    //     on every payment and operators saw a perceptible
                    //     "refresh" — pure SDK overhead with no benefit.
                    val wantCurrency = getCurrencyEnum(currency)
                    if (lastSetCurrency != wantCurrency) {
                        POSHandler.setCurrency(wantCurrency)
                        lastSetCurrency = wantCurrency
                        sendLog("purchase: setCurrency($wantCurrency)")
                    }
                    //  2) Clear a stuck busy flag from a previous timeout/
                    //     cancel — already conditional on isTerminalBusy.
                    if (posHandler?.isTerminalBusy() == true) {
                        sendLog("purchase: busy flag set — force clearing")
                        forceCleanSdkState()
                    }
                    sendLog("purchase(${String.format("%.2f", amount)}, $currency, DO_NOT_PRINT)")
                    // SDK 2.1.8 legacy signature: purchase(amount, currency, receiptConfig).
                    // RECEIPT_DO_NOT_PRINT: POS prints its own receipt; don't
                    // make the operator deal with a duplicate from the terminal.
                    posHandler?.purchase(
                        String.format("%.2f", amount),
                        currency,
                        POSHandler.RECEIPT_DO_NOT_PRINT
                    )
                    //  3) 75 s safety net so the POS dialog doesn't hang if
                    //     the SDK never calls onTransactionComplete.
                    schedulePaymentTimeout(result, "purchase")
                } catch (e: Exception) {
                    isPaymentInProgress = false
                    pendingResult = null
                    pendingOp = ""
                    result.success(mapOf("success" to false, "error" to e.message))
                }
            },
            onError = { err ->
                result.success(mapOf("success" to false, "error" to err))
            }
        )
    }

    /// TWINT flow per official MyPOS SDK doc (MYPOS_SDK_STANDALONE.md §5):
    /// completely separate from card purchase. SDK's `openPaymentActivity`
    /// launches its own Activity (terminal shows the QR), customer scans
    /// with the TWINT app, and the result returns via `onActivityResult`
    /// in the host Activity (forwarded here via ActivityResultListener).
    ///
    /// Pre-fix this method called `posHandler.twintPurchase(amount, currency)`
    /// — that's the WRONG SDK entry point for TWINT; the doc explicitly
    /// says PaymentParams isn't used for TWINT and the only correct path
    /// is openPaymentActivity. That's why no QR ever appeared on the
    /// terminal — the legacy call was a silent no-op.
    private fun handleTwint(call: MethodCall, result: MethodChannel.Result) {
        val amount = call.argument<Double>("amount") ?: run {
            result.success(mapOf("success" to false, "error" to "Missing amount"))
            return
        }
        if (amount <= 0) {
            result.success(mapOf("success" to false, "error" to "Amount must be > 0"))
            return
        }
        val act = activity
        if (act == null) {
            // TWINT *requires* an Activity context (doc §6). We can't
            // launch openPaymentActivity from a Service or detached engine.
            result.success(mapOf(
                "success"   to false,
                "errorCode" to "NO_ACTIVITY",
                "error"     to "TWINT için Activity context şart — uygulama foreground'da değil"
            ))
            return
        }

        // Same hard-reset as handlePayment: clear any queued stale event
        // before we set pendingResult so the first SDK callback we get
        // is the one for *this* transaction.
        resetPaymentSessionState("handleTwint entry")

        ensureConnectionBeforePayment(
            onReady = {
                pendingResult = result
                pendingOp = "twint"
                isPaymentInProgress = true
                lastTwintTransRef = UUID.randomUUID().toString()
                twintStartedAt = System.currentTimeMillis()
                val amountStr = String.format(java.util.Locale.US, "%.2f", amount)
                try {
                    // TWINT is CHF-only at the SDK level.
                    if (lastSetCurrency != Currency.CHF) {
                        POSHandler.setCurrency(Currency.CHF)
                        lastSetCurrency = Currency.CHF
                        sendLog("twint: setCurrency(CHF)")
                    }
                    if (posHandler?.isTerminalBusy() == true) {
                        sendLog("twint: busy flag set — force clearing")
                        forceCleanSdkState()
                    }
                    Log.i(TAG, "openPaymentActivity ENTRY amount=$amountStr transRef=$lastTwintTransRef act=${act.javaClass.simpleName}")
                    sendLog("➡️ openPaymentActivity($amountStr, CHF, transRef=$lastTwintTransRef)")
                    // ActivityNotFoundException is the specific symptom the
                    // operator hit after the doc-spec rewrite: SDK fires an
                    // Intent for `com.mypos.slavesdk.OperationActivity` which
                    // must be declared in *our* AndroidManifest (the AAR's
                    // own declaration uses a non-AppCompat theme that gets
                    // stripped by the merger). We catch it explicitly so the
                    // operator sees a clean error instead of an app crash.
                    posHandler?.openPaymentActivity(
                        act,
                        REQ_CODE_TWINT,
                        amountStr,
                        lastTwintTransRef
                    )
                    sendLog("twint: launched via openPaymentActivity — waiting for onActivityResult")
                    // 180 s safety net — TWINT can legitimately take ~90 s
                    // (doc §6); double that gives slow customers room. If
                    // onActivityResult fires earlier the timer is cancelled.
                    schedulePaymentTimeout(result, "twintActivity")
                } catch (e: ActivityNotFoundException) {
                    Log.e(TAG, "TWINT: OperationActivity not found", e)
                    sendLog("❌ TWINT: OperationActivity not declared in manifest (or theme mismatch)")
                    isPaymentInProgress = false
                    pendingResult = null
                    pendingOp = ""
                    cancelPaymentTimeout()
                    result.success(mapOf(
                        "success"   to false,
                        "errorCode" to "MANIFEST_MISSING",
                        "error"     to "MyPOS OperationActivity manifest'te eksik / tema uyumsuz — APK build sorunu"
                    ))
                } catch (e: Throwable) {
                    Log.e(TAG, "openPaymentActivity EXCEPTION", e)
                    sendLog("❌ openPaymentActivity failed: ${e.javaClass.simpleName}: ${e.message}")
                    isPaymentInProgress = false
                    pendingResult = null
                    pendingOp = ""
                    cancelPaymentTimeout()
                    result.success(mapOf(
                        "success"   to false,
                        "errorCode" to "TWINT_EXCEPTION",
                        "error"     to "${e.javaClass.simpleName}: ${e.message ?: "unknown"}"
                    ))
                }
            },
            onError = { err ->
                result.success(mapOf("success" to false, "error" to err))
            }
        )
    }

    /// SDK delivers the TWINT result here via ActivityResultListener.
    /// Result Intent extras (per doc §5):
    ///   - "pos_status": Int (POSHandler.POS_STATUS_*)
    ///   - "transaction_data": Parcelable TransactionData
    /// resultCode is RESULT_CANCELED on user cancel.
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ): Boolean {
        if (requestCode != REQ_CODE_TWINT) return false
        Log.i(TAG, "TWINT onActivityResult resultCode=$resultCode hasData=${data != null}")
        sendLog("✉️ TWINT onActivityResult: resultCode=$resultCode")
        cancelPaymentTimeout()
        val result = pendingResult
        pendingResult = null
        val wasTwint = pendingOp == "twint"
        pendingOp = ""
        isPaymentInProgress = false
        if (result == null || !wasTwint) {
            sendLog("TWINT result arrived but pendingResult is stale — dropping")
            return true
        }

        val txData: TransactionData? = try {
            @Suppress("DEPRECATION")
            data?.getParcelableExtra("transaction_data")
        } catch (e: Throwable) {
            sendLog("TWINT result: parcelable read failed: ${e.message}")
            null
        }
        val posStatus = data?.getIntExtra("pos_status", -1) ?: -1

        // Kit Troubleshooting §5: occasionally the SDK hands back the
        // PREVIOUS transaction's data when a second TWINT starts quickly.
        // If the txn timestamp predates our `twintStartedAt - 60s` window
        // it can't be ours; refuse it so the POS doesn't accidentally
        // mark a completely different sale as paid.
        if (txData != null) {
            val txTime = try { txData.transactionDateLocal?.time ?: 0L }
                catch (_: Throwable) { 0L }
            if (txTime > 0 && txTime < twintStartedAt - 60_000) {
                sendLog("⚠️ TWINT stale data (txTime=$txTime started=$twintStartedAt) — rejecting")
                result.success(mapOf(
                    "success"   to false,
                    "errorCode" to "STALE_DATA",
                    "error"     to "TWINT eski işlem verisi döndü (SDK bug) — manuel kontrol"
                ))
                return true
            }
        }

        when {
            txData != null && !txData.rrn.isNullOrEmpty() -> {
                val declined = txData.declinedReason1?.takeIf { it.isNotEmpty() }
                    ?: txData.declineReason2?.takeIf { it.isNotEmpty() }
                if (declined != null) {
                    sendLog("❌ TWINT declined: $declined")
                    result.success(mapOf(
                        "success"   to false,
                        "errorCode" to "DECLINED",
                        "error"     to "TWINT reddedildi: $declined"
                    ))
                } else {
                    sendLog("✅ TWINT approved rrn=${txData.rrn}")
                    result.success(mapOf(
                        "success"       to true,
                        "transactionId" to (txData.rrn ?: ""),
                        "authCode"      to (txData.authCode ?: ""),
                        "amount"        to (txData.amount ?: "0.00"),
                        "maskedPan"     to (txData.panMasked ?: ""),
                        "cardType"      to "TWINT",
                        "transRef"      to lastTwintTransRef
                    ))
                }
            }
            resultCode == Activity.RESULT_CANCELED -> {
                sendLog("TWINT cancelled by user (RESULT_CANCELED)")
                result.success(mapOf(
                    "success"   to false,
                    "errorCode" to "CANCELLED",
                    "error"     to "Kullanıcı iptal etti"
                ))
            }
            posStatus != -1 && posStatus != POSHandler.POS_STATUS_SUCCESS -> {
                sendLog("TWINT failed: pos_status=$posStatus")
                result.success(mapOf(
                    "success"   to false,
                    "errorCode" to "STATUS_$posStatus",
                    "error"     to "TWINT başarısız: status=$posStatus"
                ))
            }
            else -> {
                sendLog("TWINT result: no data and no status — treating as failed")
                result.success(mapOf(
                    "success"   to false,
                    "errorCode" to "NO_DATA",
                    "error"     to "TWINT sonucu alınamadı (no transaction_data, status=-1)"
                ))
            }
        }
        return true
    }

    private fun handleRefund(call: MethodCall, result: MethodChannel.Result) {
        val amount = call.argument<Double>("amount") ?: 0.0
        val currency = call.argument<String>("currency") ?: "CHF"

        ensureConnectionBeforePayment(
            onReady = {
                pendingResult = result
                isPaymentInProgress = true
                try {
                    // SDK 2.1.8: refund(String amount, String currency, int receiptConfig)
                    posHandler?.refund(
                        String.format("%.2f", amount),
                        currency,
                        POSHandler.RECEIPT_PRINT_AUTOMATICALLY
                    )
                } catch (e: Exception) {
                    isPaymentInProgress = false
                    pendingResult = null
                    result.success(mapOf("success" to false, "error" to e.message))
                }
            },
            onError = { err ->
                result.success(mapOf("success" to false, "error" to err))
            }
        )
    }

    private fun handleCancel(result: MethodChannel.Result) {
        // Cashier-initiated cancel: kill the in-flight timer + poller too,
        // otherwise they'd fire 75 s / 6 s later and try to push a second
        // result through a now-null pendingResult.
        cancelPaymentTimeout()
        stopTwintBusyPoller()
        try {
            // SDK 2.1.8: cancel() → cancelTransaction()
            posHandler?.cancelTransaction()
            result.success(mapOf("success" to true))
        } catch (e: Exception) {
            result.success(mapOf("success" to false, "error" to e.message))
        }
    }

    private fun handleClearBatch(result: MethodChannel.Result) {
        ensureConnectionBeforePayment(
            onReady = {
                pendingResult = result
                try {
                    posHandler?.clearBatch()
                } catch (e: Exception) {
                    pendingResult = null
                    result.success(mapOf("success" to false, "error" to e.message))
                }
            },
            onError = { err ->
                result.success(mapOf("success" to false, "error" to err))
            }
        )
    }

    // =========================================================================
    // Pre-payment connection verification
    // =========================================================================

    private fun ensureConnectionBeforePayment(
        onReady: () -> Unit,
        onError: (String) -> Unit,
    ) {
        // Pre-v3 (2026-05-12 fix): the dialog could race the SDK — a fresh
        // configure() leaves state=CONNECTING for ~1-3 s before onConnected
        // fires, and the payment request that came in right after was
        // hard-rejected here with "Terminal not connected (state: CONNECTING)".
        // Now we tolerate a brief CONNECTING window: poll up to 3 s at 200 ms
        // intervals, only fail if the state hasn't settled by then.
        if (connectionState != ConnectionState.CONNECTED) {
            sendLog("⏳ Pre-payment: state=$connectionState, waiting up to 3 s for handshake")
            val startWait = System.currentTimeMillis()
            val deadlineMs = 3000L
            val pollMs = 200L
            val poller = object : Runnable {
                override fun run() {
                    if (connectionState == ConnectionState.CONNECTED) {
                        val waited = System.currentTimeMillis() - startWait
                        sendLog("✅ Pre-payment: settled after ${waited}ms — proceeding")
                        proceedWithPaymentChecks(onReady, onError)
                        return
                    }
                    if (System.currentTimeMillis() - startWait >= deadlineMs) {
                        onError("Terminal not connected (state: $connectionState) — handshake timed out")
                        return
                    }
                    mainHandler.postDelayed(this, pollMs)
                }
            }
            mainHandler.post(poller)
            return
        }

        proceedWithPaymentChecks(onReady, onError)
    }

    /// Skip the pre-payment PING round-trip when the heartbeat has confirmed
    /// the terminal recently. Pre-fix this method (then `runPingThenPayment`)
    /// always pinged + waited 2 s per payment, which the operator perceived
    /// as a "refresh" every single ÖDE. The 60 s heartbeat already runs and
    /// updates `lastSuccessfulPingTime`, so within 30 s of a heartbeat we
    /// have strong evidence the terminal is up — no need to pay another 2 s.
    ///
    /// Per the official doc (§3 + §10) there's a *second* gate: command-
    /// layer readiness (`isPosReady`, fired by setPOSReadyListener). Without
    /// it `purchase()` / `openPaymentActivity()` can silently no-op even on
    /// a connected socket. We wait up to 2 s for that signal — long enough
    /// for the post-connect handshake, short enough that a wedged terminal
    /// still surfaces a clean error.
    private fun proceedWithPaymentChecks(
        onReady: () -> Unit,
        onError: (String) -> Unit,
    ) {
        if (!isPosReady) {
            sendLog("⏳ Pre-payment: waiting for POSReady (handshake in progress)")
            val startWait = System.currentTimeMillis()
            val deadlineMs = 2000L
            val pollMs = 100L
            val poller = object : Runnable {
                override fun run() {
                    if (isPosReady) {
                        val waited = System.currentTimeMillis() - startWait
                        sendLog("✅ Pre-payment: POSReady arrived after ${waited}ms")
                        proceedWithPaymentChecksReady(onReady, onError)
                        return
                    }
                    if (System.currentTimeMillis() - startWait >= deadlineMs) {
                        onError("Terminal POSReady not signalled within ${deadlineMs}ms")
                        return
                    }
                    mainHandler.postDelayed(this, pollMs)
                }
            }
            mainHandler.post(poller)
            return
        }
        proceedWithPaymentChecksReady(onReady, onError)
    }

    private fun proceedWithPaymentChecksReady(
        onReady: () -> Unit,
        onError: (String) -> Unit,
    ) {
        val sinceLastPing = System.currentTimeMillis() - lastSuccessfulPingTime
        if (sinceLastPing in 0..30_000) {
            sendLog("✅ Pre-payment: heartbeat fresh (${sinceLastPing}ms ago) — skipping ping")
            onReady()
            return
        }
        runPingThenPayment(onReady, onError)
    }

    private fun runPingThenPayment(
        onReady: () -> Unit,
        onError: (String) -> Unit,
    ) {
        // Send real PING and wait for response before proceeding
        sendLog("🔍 Pre-payment PING verification...")
        val startTime = System.currentTimeMillis()

        try {
            posHandler?.checkConnection()
        } catch (e: Exception) {
            onError("Pre-payment ping failed: ${e.message}")
            return
        }

        // Wait up to 2 s for ping response
        mainHandler.postDelayed({
            val elapsed = System.currentTimeMillis() - startTime
            if (connectionState == ConnectionState.CONNECTED) {
                sendLog("✅ Pre-payment PING OK (${elapsed}ms)")
                onReady()
            } else {
                onError("Terminal disconnected during pre-payment check")
            }
        }, 2000)
    }

    // =========================================================================
    // Payment safety helpers — ported from MyPOS-only bundle (2026-05-13)
    // =========================================================================

    /// Last UUID we minted for a TWINT request. SDK 2.1.8 doesn't accept
    /// a transRef on `twintPurchase(String, String)`, so this is a
    /// client-side correlation token surfaced in the response payload so
    /// the POS receipt + audit log can reference *something* unique even
    /// when the terminal RRN is missing.
    private var lastTwintTransRef: String = ""

    /// Wall-clock at which the current TWINT was launched. Kit
    /// Troubleshooting §5: `getLastTransactionData()` (and even the SDK's
    /// own onActivityResult) can occasionally return the **previous**
    /// transaction's data, e.g. when the operator quickly fires a second
    /// TWINT before SDK state has fully reset. We compare the result's
    /// transaction date against this — anything older than 60 s before
    /// launch is treated as stale.
    private var twintStartedAt: Long = 0L

    /// Same guard, extended to CARD payments. RotaKit's troubleshooting
    /// only documents §5 for TWINT, but operators reported a "first
    /// payment auto-approves without touching the card, second works" —
    /// classic stale `onTransactionComplete` from a previous app run or
    /// reconnect cycle still queued in `mainHandler`. We capture the
    /// wall-clock the moment `purchase()` is called and reject any
    /// onTransactionComplete with a `transactionDateLocal` predating
    /// that minus a 5 s margin.
    private var cardStartedAt: Long = 0L

    /// Cache the last SDK-level currency / receipt-config we set so we
    /// don't re-issue identical calls on every payment. Pre-fix the
    /// operator saw a perceptible "refresh" before every ÖDE; that was
    /// `setCurrency` + (TWINT) `setDefaultReceiptConfig` firing each time.
    private var lastSetCurrency: Currency? = null
    private var lastReceiptConfig: Int = -1

    /// SDK command-layer readiness — `setPOSReadyListener` fires this true
    /// after the terminal completes its post-connect handshake. The plugin
    /// already treated `connectionState=CONNECTED` as "go" but the official
    /// doc (§3 + §10) says command-layer ready is a separate gate. Without
    /// it `purchase()` and `openPaymentActivity()` can be silently no-op'd
    /// by the SDK if it isn't yet ready.
    private var isPosReady: Boolean = false

    /// One-time guard for `setupListeners()`. Kit Troubleshooting §1: SDK's
    /// `setConnectionListener` *appends* (doesn't replace) — re-calling
    /// would accumulate listeners and re-handshake the terminal into the
    /// "You are all set" loop. Defensively double-check even though our
    /// posHandler-null gate already prevents this in the common path.
    private var listenersAttached: Boolean = false

    /// Request code for TWINT's openPaymentActivity flow. SDK returns the
    /// result via onActivityResult with this code.
    private val REQ_CODE_TWINT = 9001

    /// Kit Troubleshooting §3: SDK fires the failure status (USER_CANCEL,
    /// COM_ERROR, TERMINAL_BUSY...) via `onPOSInfoReceived` first, then
    /// follows up with `onTransactionComplete(null)`. If we hand back a
    /// generic "no transaction data" error on the second callback the POS
    /// layer reports a failed sale even though the operator just hit
    /// cancel. We stash the most-recent financial-command failure status
    /// here so onTransactionComplete can map it back to the right errorCode.
    private var lastFinancialFailureStatus: Int = -1

    /// Failure status codes worth surfacing as semantic errors (rather
    /// than the generic NO_DATA). Copied from the kit's MyPosManager.
    private fun terminalFailureStatuses(): Set<Int> = setOf(
        POSHandler.POS_STATUS_USER_CANCEL,
        POSHandler.POS_STATUS_INTERNAL_ERROR,
        POSHandler.POS_STATUS_TERMINAL_BUSY,
        POSHandler.POS_STATUS_WRONG_AMOUNT,
        POSHandler.POS_STATUS_COM_ERROR,
        POSHandler.POS_STATUS_NO_CARD_FOUND,
        POSHandler.POS_STATUS_NOT_SUPPORTED_CARD,
        POSHandler.POS_STATUS_CARD_CHIP_ERROR,
        POSHandler.POS_STATUS_INVALID_PIN,
        POSHandler.POS_STATUS_MAX_PIN_COUNT_EXCEEDED,
        POSHandler.POS_STATUS_TRANSACTION_NOT_FOUND,
    )

    /// Map a POSHandler status int to a stable string error code surfaced
    /// to Dart. CANCELLED is the cleanest signal for the cash-software side
    /// (Cash Collector / payment_screen) so it knows to leave the ticket
    /// open rather than mark a refund.
    private fun statusToErrorCode(status: Int): String = when (status) {
        POSHandler.POS_STATUS_USER_CANCEL          -> "CANCELLED"
        POSHandler.POS_STATUS_TERMINAL_BUSY        -> "TERMINAL_BUSY"
        POSHandler.POS_STATUS_WRONG_AMOUNT         -> "WRONG_AMOUNT"
        POSHandler.POS_STATUS_COM_ERROR            -> "COM_ERROR"
        POSHandler.POS_STATUS_NO_CARD_FOUND        -> "NO_CARD"
        POSHandler.POS_STATUS_NOT_SUPPORTED_CARD   -> "CARD_NOT_SUPPORTED"
        POSHandler.POS_STATUS_CARD_CHIP_ERROR      -> "CARD_CHIP_ERROR"
        POSHandler.POS_STATUS_INVALID_PIN          -> "INVALID_PIN"
        POSHandler.POS_STATUS_MAX_PIN_COUNT_EXCEEDED -> "PIN_LOCKED"
        POSHandler.POS_STATUS_TRANSACTION_NOT_FOUND -> "TX_NOT_FOUND"
        else                                        -> "STATUS_$status"
    }

    /// Currently in-flight operation, used by timeout / poller paths to
    /// know whether the pendingResult they hold is still theirs.
    private var pendingOp: String = ""

    /// Wipe every piece of "current transaction" state before starting a
    /// new payment. Without this the operator's first payment can be
    /// auto-approved by a stale `onTransactionComplete` event left over
    /// from the previous app launch / reconnect — the very symptom
    /// reported on 2026-05-13 ("ilk ödemede otomatik onaylıyor, kart hiç
    /// yaklaştırmadan adisyon ödendi"). Called at the top of every
    /// handlePayment / handleTwint entry.
    private fun resetPaymentSessionState(reason: String) {
        if (pendingResult != null || isPaymentInProgress) {
            sendLog("🧹 resetPaymentSessionState ($reason): clearing stale pending state " +
                "[pendingOp=$pendingOp, isPaymentInProgress=$isPaymentInProgress]")
        }
        cancelPaymentTimeout()
        stopTwintBusyPoller()
        pendingResult = null
        pendingOp = ""
        isPaymentInProgress = false
        lastFinancialFailureStatus = -1
        cardStartedAt = 0L
        twintStartedAt = 0L
        lastTwintTransRef = ""
    }

    /// Reflection-based unstick for the SDK's `mTransactionInProgress`
    /// flag. The SDK occasionally leaves it true after a cancel/timeout,
    /// which then makes the next purchase silently fail with TERMINAL_BUSY.
    /// Copied from MyPOS-only bundle's `forceCleanSdkState`.
    private fun forceCleanSdkState() {
        try {
            val utilsClass = Class.forName("com.mypos.slavesdk.Utils")
            val field = utilsClass.getDeclaredField("mTransactionInProgress")
            field.isAccessible = true
            val wasBusy = field.getBoolean(null)
            if (wasBusy) {
                field.setBoolean(null, false)
                sendLog("SDK busy flag cleared (was stuck)")
            }
        } catch (e: Exception) {
            sendLog("forceCleanSdkState: ${e.message}")
        }
    }

    /// Map an ISO 4217 alpha code to the SDK's Currency enum. Used for
    /// `POSHandler.setCurrency(...)` ahead of every purchase so a previous
    /// transaction's currency doesn't leak in.
    private fun getCurrencyEnum(code: String): Currency = when (code.uppercase()) {
        "EUR" -> Currency.EUR
        "USD" -> Currency.USD
        "GBP" -> Currency.GBP
        else  -> Currency.CHF
    }

    // ---------- Payment timeout (75 s) ----------

    private var paymentTimeoutRunnable: Runnable? = null

    /// Posts a 75 s safety net: if the SDK never fires
    /// `onTransactionComplete` we cancel the pending payment with a TIMEOUT
    /// error so the POS dialog doesn't hang forever. Called right after
    /// firing `purchase()` / `twintPurchase()`; cancelled on
    /// `onTransactionComplete`, `handleCancel`, and on each subsequent
    /// payment start.
    private fun schedulePaymentTimeout(result: MethodChannel.Result, op: String) {
        cancelPaymentTimeout()
        val timeoutMs = 75_000L
        paymentTimeoutRunnable = Runnable {
            if (pendingResult != result) return@Runnable
            sendLog("⏱ $op timeout after ${timeoutMs / 1000}s — no SDK callback, cancelling")
            try { posHandler?.cancelTransaction() } catch (_: Exception) {}
            forceCleanSdkState()
            isPaymentInProgress = false
            val r = pendingResult
            pendingResult = null
            pendingOp = ""
            stopTwintBusyPoller()
            r?.success(mapOf(
                "success"   to false,
                "errorCode" to "TIMEOUT",
                "error"     to "$op timeout — no response from terminal"
            ))
        }
        mainHandler.postDelayed(paymentTimeoutRunnable!!, timeoutMs)
    }

    private fun cancelPaymentTimeout() {
        paymentTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        paymentTimeoutRunnable = null
    }

    // ---------- TWINT busy poller ----------
    //
    // The SDK is unreliable about firing `onTransactionComplete` for TWINT
    // when the customer dismisses the QR screen or the terminal times out
    // internally — it just goes idle. We poll `isTerminalBusy` and, after
    // 3 consecutive idle ticks past a 3 s grace window, declare the
    // transaction CANCELLED so the dialog can close instead of hanging.
    // Simpler than the bundle's variant (no `queryLastTransaction`
    // dependency) — adequate for our use.

    private var twintBusyPollRunnable: Runnable? = null
    private var twintNotBusyStreak: Int = 0
    private var twintPollStartedAt: Long = 0L

    private fun startTwintBusyPoller(result: MethodChannel.Result) {
        stopTwintBusyPoller()
        twintNotBusyStreak = 0
        twintPollStartedAt = System.currentTimeMillis()
        twintBusyPollRunnable = object : Runnable {
            override fun run() {
                if (pendingResult != result || pendingOp != "twint") {
                    sendLog("TWINT poller: pendingResult changed, stopping")
                    return
                }
                val elapsed = System.currentTimeMillis() - twintPollStartedAt
                // Grace window: SDK takes ~1-2 s to set busy=true.
                if (elapsed < 3000) {
                    mainHandler.postDelayed(this, 1500)
                    return
                }
                val busy = try {
                    posHandler?.isTerminalBusy() ?: false
                } catch (_: Exception) { false }
                if (busy) {
                    twintNotBusyStreak = 0
                } else {
                    twintNotBusyStreak++
                    sendLog("TWINT poller: idle (streak=$twintNotBusyStreak)")
                    // 3 idle checks × 2 s = 6 s without callback → treat as cancel.
                    if (twintNotBusyStreak >= 3) {
                        sendLog("TWINT poller: 6 s idle without callback — declaring CANCELLED")
                        cancelPaymentTimeout()
                        isPaymentInProgress = false
                        val r = pendingResult
                        pendingResult = null
                        pendingOp = ""
                        r?.success(mapOf(
                            "success"   to false,
                            "errorCode" to "CANCELLED",
                            "error"     to "TWINT cancelled (terminal idle without callback)"
                        ))
                        return
                    }
                }
                mainHandler.postDelayed(this, 2000)
            }
        }
        mainHandler.postDelayed(twintBusyPollRunnable!!, 1500)
    }

    private fun stopTwintBusyPoller() {
        twintBusyPollRunnable?.let { mainHandler.removeCallbacks(it) }
        twintBusyPollRunnable = null
    }

    // =========================================================================
    // SDK listeners
    // =========================================================================

    private fun setupListeners() {
        if (listenersAttached) {
            // Kit §1 — accidentally calling setConnectionListener twice
            // accumulates callbacks; the terminal then enters its "You
            // are all set" loop and refuses commands. Guard belt-and-
            // suspenders even though handleConfigure's posHandler-null
            // gate already prevents re-entry on the happy path.
            sendLog("setupListeners: already attached — skipping (kit §1 guard)")
            return
        }
        listenersAttached = true
        // SDK 2.1.8: ConnectionListener callbacks take BluetoothDevice param (ignored for TCP)
        posHandler?.setConnectionListener(object : ConnectionListener {
            override fun onConnected(device: BluetoothDevice?) {
                mainHandler.post {
                    sendLog("🔗 SDK onConnected (waiting for POSReady)")
                    reconnectAttempts = 0
                    isReconnecting = false
                    isPosReady = false  // command-layer waits for POSReadyListener
                    lastSuccessfulPingTime = System.currentTimeMillis()
                    updateConnectionState(ConnectionState.CONNECTED, "SDK connected callback")
                    startHeartbeat()
                }
            }

            override fun onDisconnected(device: BluetoothDevice?) {
                mainHandler.post {
                    sendLog("🔌 SDK onDisconnected")
                    isPosReady = false
                    updateConnectionState(ConnectionState.DISCONNECTED, "SDK disconnected callback")
                }
            }
        })

        posHandler?.setPOSReadyListener(object : POSReadyListener {
            override fun onPOSReady() {
                mainHandler.post {
                    sendLog("✅ Terminal POS ready — can dispatch commands")
                    isPosReady = true
                    if (connectionState != ConnectionState.CONNECTED) {
                        updateConnectionState(ConnectionState.CONNECTED, "POS ready")
                    }
                }
            }
        })

        // SDK 2.1.8: POSInfoListener.onPOSInfoReceived(command, status, message, bundle)
        posHandler?.setPOSInfoListener(object : POSInfoListener {
            override fun onPOSInfoReceived(command: Int, status: Int, message: String?, bundle: Bundle?) {
                mainHandler.post {
                    sendLog("ℹ️ POSInfo cmd=$command status=$status: $message")

                    // Kit Troubleshooting §3: stash the financial-command
                    // failure status here so onTransactionComplete(null) —
                    // which fires *after* this for cancel/decline — can
                    // surface the right errorCode instead of NO_DATA.
                    if ((command == POSHandler.COMMAND_PURCHASE ||
                            command == POSHandler.COMMAND_REFUND) &&
                        status in terminalFailureStatuses()) {
                        lastFinancialFailureStatus = status
                    }

                    when (status) {
                        POSHandler.POS_STATUS_SUCCESS_PING -> {
                            lastSuccessfulPingTime = System.currentTimeMillis()
                            sendLog("🏓 PING success")
                            pingResult?.let {
                                it.success(mapOf("success" to true, "connected" to true))
                                pingResult = null
                            }
                        }
                        POSHandler.POS_STATUS_PING_FAILED -> {
                            sendLog("❌ PING failed")
                            pingResult?.let {
                                it.success(mapOf("success" to false, "connected" to false))
                                pingResult = null
                            }
                            if (connectionState == ConnectionState.CONNECTED) {
                                updateConnectionState(ConnectionState.DISCONNECTED, "PING failed")
                            }
                        }
                        POSHandler.POS_STATUS_COM_ERROR -> {
                            sendLog("❌ Communication error")
                            if (connectionState == ConnectionState.CONNECTED) {
                                updateConnectionState(ConnectionState.DISCONNECTED, "COM error")
                            }
                        }
                        else -> {}
                    }
                }
            }

            override fun onTransactionComplete(transactionData: TransactionData?) {
                mainHandler.post {
                    val result = pendingResult ?: run {
                        sendLog("⚠️ Orphan onTransactionComplete (no pendingResult) — ignoring")
                        return@post
                    }
                    val wasTwint = pendingOp == "twint"

                    // 🚨 CRITICAL stale-event filter (extended kit §5 to
                    // card path). If the SDK hands us transaction data
                    // whose `transactionDateLocal` predates the moment
                    // we kicked off the request, it can't be ours —
                    // it's a leftover event from before the user even
                    // tapped ÖDE. Treating it as success was the
                    // "first payment auto-approves" symptom reported
                    // 2026-05-13.
                    val sessionStartedAt = if (wasTwint) twintStartedAt else cardStartedAt
                    if (sessionStartedAt > 0 && transactionData != null) {
                        val txTime = try {
                            transactionData.transactionDateLocal?.time ?: 0L
                        } catch (_: Throwable) { 0L }
                        if (txTime > 0 && txTime < sessionStartedAt - 5_000) {
                            sendLog("⚠️ Stale onTransactionComplete (txTime=$txTime " +
                                "< startedAt=$sessionStartedAt) — rejecting, NOT closing ticket")
                            // Leave pendingResult intact — the real
                            // callback for *this* transaction should
                            // still arrive (or the timeout will fire).
                            return@post
                        }
                    }

                    cancelPaymentTimeout()
                    stopTwintBusyPoller()
                    isPaymentInProgress = false
                    pendingResult = null
                    pendingOp = ""
                    cardStartedAt = 0L
                    twintStartedAt = 0L
                    // Snapshot the failure status before resetting it so
                    // the post-data path below can map it. Pre-fix this
                    // wasn't tracked and a cancelled card always came back
                    // as NO_DATA → POS layer marked it as failed.
                    val failureStatus = lastFinancialFailureStatus
                    lastFinancialFailureStatus = -1

                    if (transactionData != null) {
                        // SDK 2.1.8: success if authCode is non-empty and no declined reason
                        val authCode = transactionData.getAuthCode() ?: ""
                        val declinedReason = transactionData.getDeclinedReason1() ?: ""
                        val isSuccess = authCode.isNotEmpty() && declinedReason.isEmpty()

                        if (isSuccess) {
                            val rrn = transactionData.getRRN() ?: ""
                            sendLog("✅ Transaction complete: RRN=$rrn (twint=$wasTwint)")
                            val payload = mutableMapOf<String, Any?>(
                                "success"       to true,
                                "transactionId" to rrn,
                                "authCode"      to authCode,
                                "cardType"      to (transactionData.getAIDName() ?: ""),
                                "maskedPan"     to (transactionData.getPANMasked() ?: ""),
                                "amount"        to (transactionData.getAmount() ?: "0.00"),
                            )
                            // Surface the client-side correlation token to the
                            // POS so the receipt + audit log have a stable ref
                            // even when the terminal RRN comes back empty for
                            // TWINT (SDK 2.1.8 occasionally does).
                            if (wasTwint && lastTwintTransRef.isNotEmpty()) {
                                payload["transRef"] = lastTwintTransRef
                            }
                            result.success(payload)
                        } else {
                            // Kit §3 honour: prefer the financial status
                            // we already captured (USER_CANCEL etc) over
                            // the generic declinedReason text — operator
                            // wants a "iptal edildi" pop, not "DECLINED".
                            val errCode = when {
                                failureStatus in terminalFailureStatuses() ->
                                    statusToErrorCode(failureStatus)
                                declinedReason.isNotEmpty() -> declinedReason
                                else -> "DECLINED"
                            }
                            sendLog("❌ Transaction failed: $errCode (failureStatus=$failureStatus)")
                            result.success(mapOf(
                                "success"   to false,
                                "errorCode" to errCode,
                                "error"     to (if (errCode == "CANCELLED") "Kullanıcı iptal etti"
                                                else "Transaction declined or failed: $errCode"),
                            ))
                        }
                    } else {
                        sendLog("❌ Transaction failed: null data")
                        // null data + captured failure status = the cancel /
                        // decline path operator hit on the terminal. Surface
                        // the specific code rather than a generic UNKNOWN so
                        // the POS dialog can render "Kullanıcı iptal etti"
                        // instead of "no data received".
                        val errCode = if (failureStatus in terminalFailureStatuses()) {
                            statusToErrorCode(failureStatus)
                        } else "UNKNOWN"
                        sendLog("❌ Transaction failed: null data, failureStatus=$failureStatus → $errCode")
                        result.success(mapOf(
                            "success"   to false,
                            "errorCode" to errCode,
                            "error"     to (if (errCode == "CANCELLED") "Kullanıcı iptal etti"
                                            else "Transaction failed: no data received"),
                        ))
                    }
                }
            }
        })

        // SDK 2.1.8: PosTransactionClearedListener.onComplete(status)
        posHandler?.setTransactionClearedListener(object : PosTransactionClearedListener {
            override fun onComplete(status: Int) {
                mainHandler.post {
                    sendLog("✅ Batch cleared (end of day), status=$status")
                    val result = pendingResult ?: return@post
                    pendingResult = null
                    result.success(mapOf("success" to true, "status" to "batch_cleared"))
                }
            }
        })
    }

    // =========================================================================
    // Connection state manager
    // =========================================================================

    private fun updateConnectionState(newState: ConnectionState, reason: String = "") {
        val old = connectionState
        connectionState = newState
        sendLog("🔄 State: $old → $newState${if (reason.isNotEmpty()) " ($reason)" else ""}")

        channel.invokeMethod("onConnectionChanged", mapOf(
            "connected" to (newState == ConnectionState.CONNECTED),
            "state"     to newState.name,
            "reason"    to reason
        ))

        // Kit Troubleshooting §2: on TCP/IP we must NOT manually trigger
        // reconnect — the slave SDK runs its own 2.5 s sleep + retry loop
        // and our scheduleReconnect raced it, producing the ~1 s connect/
        // disconnect flap (you'd see "SDK CONNECTED → SDK DISCONNECTED →
        // SDK CONNECTED" cycling in logs). Operator-visible symptom: the
        // dialog hung in "BAĞLANIYOR" forever.
        //
        // We only set the TCP/IP connection type today, so simply
        // surrender here. The heartbeat code below still pings every 60 s
        // and will surface a real outage; the user can always hit
        // "BAĞLANTIYI TEST ET" from Settings to force a reconfigure if
        // the SDK gets wedged.
    }

    // =========================================================================
    // Heartbeat (TCP/IP only)
    // =========================================================================

    private fun startHeartbeat() {
        stopHeartbeat()
        sendLog("💓 Heartbeat started (${HEARTBEAT_INTERVAL_MS / 1000}s)")
        heartbeatRunnable = object : Runnable {
            override fun run() {
                if (connectionState == ConnectionState.CONNECTED) {
                    sendHeartbeatPing()
                }
                mainHandler.postDelayed(this, HEARTBEAT_INTERVAL_MS)
            }
        }
        mainHandler.postDelayed(heartbeatRunnable!!, HEARTBEAT_INTERVAL_MS)
    }

    private fun stopHeartbeat() {
        heartbeatRunnable?.let { mainHandler.removeCallbacks(it) }
        heartbeatRunnable = null
    }

    private fun sendHeartbeatPing() {
        if (isPaymentInProgress) {
            lastSuccessfulPingTime = System.currentTimeMillis()
            return
        }
        if (posHandler?.isTerminalBusy() == true) {
            lastSuccessfulPingTime = System.currentTimeMillis()
            return
        }
        try {
            posHandler?.checkConnection()
            mainHandler.postDelayed({
                val timeSinceLastPing = System.currentTimeMillis() - lastSuccessfulPingTime
                if (timeSinceLastPing > HEARTBEAT_INTERVAL_MS && connectionState == ConnectionState.CONNECTED) {
                    sendLog("💔 Heartbeat: no PING response — connection lost")
                    updateConnectionState(ConnectionState.DISCONNECTED, "heartbeat timeout")
                }
            }, 5000)
        } catch (e: Exception) {
            sendLog("💔 Heartbeat error: ${e.message}")
            if (connectionState == ConnectionState.CONNECTED) {
                updateConnectionState(ConnectionState.DISCONNECTED, "heartbeat exception")
            }
        }
    }

    // =========================================================================
    // Watchdog (ICMP ping background thread)
    // =========================================================================

    private fun startWatchdog() {
        stopWatchdog()
        watchdogActive = true
        watchdogThread = Thread {
            var lastReachable = false
            while (watchdogActive) {
                try { Thread.sleep(15000) } catch (_: InterruptedException) { break }
                if (!watchdogActive) break

                val reachable = icmpPing(tcpIp, 3000)

                if (reachable != lastReachable) {
                    mainHandler.post {
                        if (reachable) {
                            sendLog("📡 Watchdog: terminal reachable")
                            if (connectionState != ConnectionState.CONNECTED && !isReconnecting) {
                                try {
                                    posHandler?.resetTcpConnection()
                                    activity?.let { posHandler?.connectDevice(it) }
                                } catch (_: Exception) {}
                            }
                        } else {
                            sendLog("📡 Watchdog: terminal unreachable")
                            if (connectionState == ConnectionState.CONNECTED) {
                                updateConnectionState(ConnectionState.DISCONNECTED, "watchdog ICMP unreachable")
                            }
                        }
                    }
                }
                lastReachable = reachable
            }
        }.also {
            it.isDaemon = true
            it.name = "mypos-watchdog"
            it.start()
        }
        sendLog("📡 Watchdog started (15 s ICMP)")
    }

    private fun stopWatchdog() {
        watchdogActive = false
        watchdogThread?.interrupt()
        watchdogThread = null
    }

    private fun icmpPing(ip: String, timeoutMs: Int): Boolean =
        try { java.net.InetAddress.getByName(ip).isReachable(timeoutMs) } catch (_: Exception) { false }

    // =========================================================================
    // Auto-reconnect
    // =========================================================================

    private fun scheduleReconnect() {
        if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
            sendLog("❌ Max reconnect attempts ($MAX_RECONNECT_ATTEMPTS) reached")
            isReconnecting = false
            reconnectAttempts = 0
            return
        }
        isReconnecting = true
        updateConnectionState(ConnectionState.RECONNECTING, "attempt ${reconnectAttempts + 1}")
        val delay = RECONNECT_DELAY_MS * (reconnectAttempts + 1)
        mainHandler.postDelayed({ attemptReconnect() }, delay)
    }

    private fun attemptReconnect() {
        if (!isConfigured) { isReconnecting = false; return }

        if (posHandler?.isConnected() == true) {
            reconnectAttempts = 0
            isReconnecting = false
            lastSuccessfulPingTime = System.currentTimeMillis()
            updateConnectionState(ConnectionState.CONNECTED, "SDK already connected")
            startHeartbeat()
            return
        }

        reconnectAttempts++
        sendLog("🔄 Reconnect attempt $reconnectAttempts/$MAX_RECONNECT_ATTEMPTS")

        try {
            activity?.let { ctx ->
                try { posHandler?.resetTcpConnection() } catch (_: Exception) {}
                Thread.sleep(300)
                posHandler?.connectDevice(ctx)
                isReconnecting = false
            } ?: run {
                sendLog("⚠️ No activity for reconnect")
                isReconnecting = false
            }
        } catch (e: Exception) {
            sendLog("❌ Reconnect error: ${e.message}")
            isReconnecting = false
            scheduleReconnect()
        }
    }

    // =========================================================================
    // Logging
    // =========================================================================

    private fun sendLog(message: String) {
        Log.d(TAG, message)
        mainHandler.post { logSink?.success(message) }
    }
}
