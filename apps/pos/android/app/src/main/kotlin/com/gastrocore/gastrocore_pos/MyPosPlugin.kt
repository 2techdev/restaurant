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
                isPaymentInProgress = true
                try {
                    // SDK 2.1.8: purchase(String amount, String currency, int receiptConfig)
                    posHandler?.purchase(
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

    private fun handleTwint(call: MethodCall, result: MethodChannel.Result) {
        val amount = call.argument<Double>("amount") ?: run {
            result.success(mapOf("success" to false, "error" to "Missing amount"))
            return
        }
        val currency = call.argument<String>("currency") ?: "CHF"

        ensureConnectionBeforePayment(
            onReady = {
                pendingResult = result
                isPaymentInProgress = true
                try {
                    // SDK 2.1.8: twintPurchase(String amount, String currency)
                    posHandler?.twintPurchase(String.format("%.2f", amount), currency)
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
        if (connectionState != ConnectionState.CONNECTED) {
            onError("Terminal not connected (state: $connectionState)")
            return
        }

        // Send real PING and wait for response before proceeding
        sendLog("🔍 Pre-payment PING verification...")
        val startTime = System.currentTimeMillis()

        try {
            posHandler?.checkConnection()
        } catch (e: Exception) {
            onError("Pre-payment ping failed: ${e.message}")
            return
        }

        // Wait up to 3 s for ping response
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
                    isPaymentInProgress = false
                    val result = pendingResult ?: return@post
                    pendingResult = null

                    if (transactionData != null) {
                        // SDK 2.1.8: success if authCode is non-empty and no declined reason
                        val authCode = transactionData.getAuthCode() ?: ""
                        val declinedReason = transactionData.getDeclinedReason1() ?: ""
                        val isSuccess = authCode.isNotEmpty() && declinedReason.isEmpty()

                        if (isSuccess) {
                            sendLog("✅ Transaction complete: RRN=${transactionData.getRRN()}")
                            result.success(mapOf(
                                "success"       to true,
                                "transactionId" to (transactionData.getRRN() ?: ""),
                                "authCode"      to authCode,
                                "cardType"      to (transactionData.getAIDName() ?: ""),
                                "maskedPan"     to (transactionData.getPANMasked() ?: ""),
                                "amount"        to (transactionData.getAmount() ?: "0.00"),
                            ))
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
