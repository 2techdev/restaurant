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

private const val TAG = "MyPosPlugin"
private const val RECONNECT_DELAY_MS = 3000L
private const val MAX_RECONNECT_ATTEMPTS = 10
private const val HEARTBEAT_INTERVAL_MS = 60000L  // TCP/IP only

class MyPosPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

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

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() {
        stopHeartbeat()
        stopWatchdog()
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
        val sdkConnected = posHandler?.isConnected() ?: false
        val stateConnected = connectionState == ConnectionState.CONNECTED
        val connected = sdkConnected && stateConnected
        sendLog("🔍 checkRealConnection: sdk=$sdkConnected, state=$connectionState → $connected")
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

        ensureConnectionBeforePayment(
            onReady = {
                pendingResult = result
                pendingOp = "purchase"
                isPaymentInProgress = true
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

    private fun handleTwint(call: MethodCall, result: MethodChannel.Result) {
        val amount = call.argument<Double>("amount") ?: run {
            result.success(mapOf("success" to false, "error" to "Missing amount"))
            return
        }
        if (amount <= 0) {
            result.success(mapOf("success" to false, "error" to "Amount must be > 0"))
            return
        }

        ensureConnectionBeforePayment(
            onReady = {
                pendingResult = result
                pendingOp = "twint"
                isPaymentInProgress = true
                lastTwintTransRef = UUID.randomUUID().toString()
                val amountStr = String.format("%.2f", amount)
                try {
                    // TWINT is CHF-only at the SDK level — pin once.
                    if (lastSetCurrency != Currency.CHF) {
                        POSHandler.setCurrency(Currency.CHF)
                        lastSetCurrency = Currency.CHF
                        sendLog("twint: setCurrency(CHF)")
                    }
                    if (posHandler?.isTerminalBusy() == true) {
                        sendLog("twint: busy flag set — force clearing")
                        forceCleanSdkState()
                    }
                    if (lastReceiptConfig != POSHandler.RECEIPT_DO_NOT_PRINT) {
                        POSHandler.setDefaultReceiptConfig(POSHandler.RECEIPT_DO_NOT_PRINT)
                        lastReceiptConfig = POSHandler.RECEIPT_DO_NOT_PRINT
                        sendLog("twint: setDefaultReceiptConfig(DO_NOT_PRINT)")
                    }
                    Log.i(TAG, "twintPurchase ENTRY amount=$amountStr transRef=$lastTwintTransRef")
                    sendLog("➡️ twintPurchase($amountStr, CHF, transRef=$lastTwintTransRef)")
                    // Try the newer QRPaymentParams builder API first — it's
                    // what the May-2026 MyPOS bundle uses and our slavesdk-
                    // 2.1.8.aar may also expose it (the wildcard import pulls
                    // it in if present). If the class is missing at runtime
                    // we catch NoClassDefFoundError and fall back to the
                    // legacy (String, String) signature.
                    val launched = tryTwintViaBuilder(amountStr, lastTwintTransRef)
                    if (!launched) {
                        sendLog("twint: builder API unavailable — falling back to legacy signature")
                        posHandler?.twintPurchase(amountStr, "CHF")
                    }
                    Log.i(TAG, "twintPurchase RETURNED (waiting for onTransactionComplete)")
                    schedulePaymentTimeout(result, "twintPurchase")
                    startTwintBusyPoller(result)
                } catch (e: Throwable) {
                    Log.e(TAG, "twintPurchase EXCEPTION", e)
                    sendLog("❌ twintPurchase failed: ${e.javaClass.simpleName}: ${e.message}")
                    isPaymentInProgress = false
                    pendingResult = null
                    pendingOp = ""
                    cancelPaymentTimeout()
                    stopTwintBusyPoller()
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

    /// Try the newer `twintPurchase(QRPaymentParams)` builder API. Returns
    /// true on success, false if the class isn't available at runtime (in
    /// which case the caller falls back to the legacy 2-arg signature).
    /// Reflection-based so the file still compiles on older AARs that
    /// don't ship `QRPaymentParams`.
    private fun tryTwintViaBuilder(amountStr: String, transRef: String): Boolean {
        return try {
            val cls = Class.forName("com.mypos.slavesdk.QRPaymentParams")
            val builderMethod = cls.getMethod("builder")
            val builder = builderMethod.invoke(null)
            val builderCls = builder.javaClass
            builderCls.getMethod("productAmount", String::class.java)
                .invoke(builder, amountStr)
            builderCls.getMethod("currency", String::class.java)
                .invoke(builder, "756") // ISO 4217 numeric for CHF
            builderCls.getMethod("transRef", String::class.java)
                .invoke(builder, transRef)
            val params = builderCls.getMethod("build").invoke(builder)
            val twintMethod = POSHandler::class.java.getMethod(
                "twintPurchase",
                cls
            )
            twintMethod.invoke(posHandler, params)
            sendLog("twint: launched via QRPaymentParams.builder()")
            true
        } catch (e: ClassNotFoundException) {
            false
        } catch (e: NoSuchMethodException) {
            false
        } catch (e: Throwable) {
            // Builder exists but something else broke — log and let caller
            // fall through to legacy.
            Log.w(TAG, "twint builder path failed: ${e.javaClass.simpleName}: ${e.message}")
            sendLog("twint: builder path threw ${e.javaClass.simpleName} — falling back")
            false
        }
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
    private fun proceedWithPaymentChecks(
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

    /// Cache the last SDK-level currency / receipt-config we set so we
    /// don't re-issue identical calls on every payment. Pre-fix the
    /// operator saw a perceptible "refresh" before every ÖDE; that was
    /// `setCurrency` + (TWINT) `setDefaultReceiptConfig` firing each time.
    private var lastSetCurrency: Currency? = null
    private var lastReceiptConfig: Int = -1

    /// Currently in-flight operation, used by timeout / poller paths to
    /// know whether the pendingResult they hold is still theirs.
    private var pendingOp: String = ""

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
        // SDK 2.1.8: ConnectionListener callbacks take BluetoothDevice param (ignored for TCP)
        posHandler?.setConnectionListener(object : ConnectionListener {
            override fun onConnected(device: BluetoothDevice?) {
                mainHandler.post {
                    sendLog("🔗 SDK onConnected")
                    reconnectAttempts = 0
                    isReconnecting = false
                    lastSuccessfulPingTime = System.currentTimeMillis()
                    updateConnectionState(ConnectionState.CONNECTED, "SDK connected callback")
                    startHeartbeat()
                }
            }

            override fun onDisconnected(device: BluetoothDevice?) {
                mainHandler.post {
                    sendLog("🔌 SDK onDisconnected")
                    updateConnectionState(ConnectionState.DISCONNECTED, "SDK disconnected callback")
                }
            }
        })

        posHandler?.setPOSReadyListener(object : POSReadyListener {
            override fun onPOSReady() {
                mainHandler.post {
                    sendLog("✅ Terminal POS ready")
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
                    cancelPaymentTimeout()
                    stopTwintBusyPoller()
                    isPaymentInProgress = false
                    val result = pendingResult ?: return@post
                    val wasTwint = pendingOp == "twint"
                    pendingResult = null
                    pendingOp = ""

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
                            val errCode = declinedReason.ifEmpty { "DECLINED" }
                            sendLog("❌ Transaction failed: $errCode")
                            result.success(mapOf(
                                "success"   to false,
                                "errorCode" to errCode,
                                "error"     to "Transaction declined or failed: $errCode",
                            ))
                        }
                    } else {
                        sendLog("❌ Transaction failed: null data")
                        result.success(mapOf(
                            "success"   to false,
                            "errorCode" to "UNKNOWN",
                            "error"     to "Transaction failed: no data received",
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

        if (newState == ConnectionState.DISCONNECTED && isConfigured && !isReconnecting) {
            scheduleReconnect()
        }
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
