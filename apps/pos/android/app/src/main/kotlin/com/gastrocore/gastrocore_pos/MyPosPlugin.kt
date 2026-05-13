/**
 * MyPOS Sigma Terminal Plugin â€” v3 (slavesdk-2.1.9b uyumlu)
 *
 * SDK davranisi (slavesdk-2.1.9b bytecode analizinden):
 *
 * 1. ListenTCPIPConnection singleton: connect() â†’ closeSocket â†’ yeni thread â†’ Socket(ip,port,5s timeout)
 *    - Basarili â†’ onConnected callback
 *    - IOException â†’ onDisconnected callback â†’ triggerReconnect() 3s sonra otomatik yeniden dene
 *    - mReconnecting flag ile ic ic reconnect'leri engelliyor
 *
 * 2. isConnected() ARTIK SAF STATE CHECK (2.1.9 degisikligi):
 *    return mSocket != null && mSocket.isConnected() && !mSocket.isClosed()
 *    sendUrgentData artik YOK â€” yan etkisiz, serbestce cagirilabilir.
 *    Not: OS-level socket state'ini gosterir; canli network detection icin heartbeat gerekir.
 *
 * 3. checkConnection() = CommandPing: mTransactionInProgress=true yapar. Heartbeat icin KULLANMA.
 *
 * 4. clearConnectionListeners() YENI (2.1.9): Listener listesini temizler.
 *    initPosHandler() tekrar cagirilirken duplicate callback'leri onler.
 *
 * 5. SDK OTOMATIK RECONNECT (2.1.9 YENI): onDisconnect sonrasi SDK kendi 3 saniyede bir
 *    yeniden baglanma denemesi yapar. Bizim reconnect logic'imiz BACKUP/FALLBACK rolundedir.
 *
 * 6. Connection state flag'i onDisconnect icinde SDK tarafindan reset ediliyor.
 *
 * 7. resetTcpConnection() = resetData(): socket kapatir, reconnect loop durur.
 *
 * Bizim strateji:
 * - ConnectionState enum ile state yonetimi
 * - Heartbeat = ICMP ping (SDK'ya dokunmaz)
 * - initPosHandler() once clearConnectionListeners() cagirir, sonra listener set eder
 * - SDK'nin kendi auto-reconnect'ine guven; ICMP ile destekle
 * - Odeme oncesi: connectionState kontrol, gerekirse reconnect bekle
 */
package com.gastrocore.gastrocore_pos

import android.app.Activity
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbManager
import android.os.Build
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
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

private const val TAG = "MyPosPlugin"
private const val RECONNECT_BASE_DELAY_MS = 3000L
private const val RECONNECT_MAX_DELAY_MS = 30000L
private const val WATCHDOG_INTERVAL_MS = 15000L  // 15s ICMP ping
private const val SOCKET_CHECK_INTERVAL = 4  // Her 4 watchdog cycle'da 1 socket check (60s)
private const val CONNECT_DEBOUNCE_MS = 80L
private const val PRE_PAYMENT_CONN_WAIT_TCP_MS = 220L
private const val PRE_PAYMENT_CONN_WAIT_USB_MS = 150L
private const val PRE_PAYMENT_CONNECTED_READY_MAX_MS = 45L
private const val PRE_PAYMENT_BUSY_MAX_WAIT_MS = 30L
private const val PRE_PAYMENT_BUSY_POLL_MS = 25L
private const val PRE_PAYMENT_CONN_WAIT_TCP_POLL_MS = 35L
private const val PRE_PAYMENT_CONN_WAIT_USB_POLL_MS = 50L
private const val WAIT_SDK_RECONNECT_POLL_MS = 35L
private const val WAIT_SDK_RECONNECT_MAX_MS = 240L
private const val RECONNECT_AND_PAY_MAX_MS = 500L
private const val RESET_AND_PAY_PRE_WAIT_MS = 120L
private const val RESET_AND_PAY_WAIT_MS = 650L
private const val RECONNECT_RETRY_STALE_MS = 300L
private const val HANDLE_RESET_RECONNECT_MS = 800L
private const val DISCONNECT_STATE_DEBOUNCE_MS = 2500L
private const val TCP_RECONNECT_GRACE_MS = 2800L
private const val TCP_TRANSIENT_DISCONNECT_WINDOW_MS = 6_000L
private const val TCP_TRANSIENT_DISCONNECT_MAX = 2

class MyPosPlugin(private val ownsSocket: Boolean = false) : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

    private lateinit var channel: MethodChannel
    private lateinit var logChannel: EventChannel
    private var logSink: EventChannel.EventSink? = null
    private var activity: Activity? = null
    private var appContext: Context? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // SDK references
    private var posHandler: POSHandler? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pingResult: MethodChannel.Result? = null
    private val nativeDebugExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    // TCP/IP config
    private var tcpIp: String = "192.168.1.131"
    private var tcpPort: Int = 60180
    // USB kaldirildi â€” default TCP/IP (WiFi). USB fonksiyonlari asagida
    // Ã¶lÃ¼ kod olarak birakildi, Flutter tarafi artik Ã§agirmiyor.
    private var currentConnectionType: ConnectionType = ConnectionType.TCP_IP
    private var terminalLanguage: Language = Language.GERMAN

    // Connection state â€” TEK MERKEZ
    enum class ConnectionState { DISCONNECTED, CONNECTING, CONNECTED, RECONNECTING }

    private var connectionState: ConnectionState = ConnectionState.DISCONNECTED
    private var pendingConnectionState: ConnectionState? = null
    private var pendingConnectionStateReason: String = ""
    private var pendingConnectionStateRunnable: Runnable? = null
    private var isConfigured: Boolean = false
    private var listenersInitialized: Boolean = false  // initPosHandler() sadece 1 kere
    private var reconnectAttempts: Int = 0
    private var isReconnecting: Boolean = false
    private var autoReconnectEnabled: Boolean = false
    private var isPaymentInProgress: Boolean = false
    private var isManualDisconnectInProgress: Boolean = false
    private var lastConnectedStateAtMs: Long = 0L
    private var transientDisconnectWindowStartMs: Long = 0L
    private var transientDisconnectCount: Int = 0
    private var paymentStartedAtMs: Long = 0L
    /** Pending operasyonun tipi â€” callback'lerde yanlis pendingResult
     *  completion'ini onlemek icin. Ornek: TWINT icin set edildi, sonra
     *  SDK yanlislikla transactionClearedListener fire ederse ignore ederiz. */
    private var pendingOp: String = ""

    /** BUSY status geldiginde otomatik retry icin orijinal istegi sakla.
     *  Status TERMINAL_BUSY â†’ forceCleanSdkState + 500ms bekle + ayni operasyonu
     *  yeniden cagir. attempts >= MAX_BUSY_RETRY ise normal hata akisi. */
    private data class PendingRetry(
        val op: String,
        val amount: Double,
        val currency: String,
        val result: MethodChannel.Result,
        var attempts: Int = 0,
    )
    private var pendingRetry: PendingRetry? = null
    private val MAX_BUSY_RETRY = 1

    /** Son onemli POSInfo status'u â€” onTransactionComplete'te approval
     *  belirsiz oldugunda bu flag ile karar veriyoruz (ornek: USER_CANCEL
     *  gorulmusse onTransactionComplete geldigi an success dememeliyiz). */
    private var lastFinancialStatus: Int = -1
    private var lastFinancialFailureStatus: Int = -1
    private var twintApprovedBySuccessStatus: Boolean = false
    private var lastApprovedRrn: String = ""
    private var lastApprovedAuthCode: String = ""
    private var myPosUsbEnabled: Boolean = false

    // SDK 2.1.9: POSReady = CommandGetStatus response tamamlandi.
    // Terminal kullanima hazir. Bunu beklemeden purchase() gondermemeli.
    @Volatile private var isPosReady: Boolean = false

    // Watchdog â€” ICMP ping + periodic TCP socket check
    @Volatile private var watchdogActive = false
    private var watchdogThread: Thread? = null
    private var watchdogCycleCount: Int = 0

    /** ICMP ping consecutive failure counter â€” Wi-Fi packet loss yanlis
     *  "unreachable" tespitlerini onler. 2 ardisik fail olmadan
     *  DISCONNECTED yapilmaz (debounce). */
    private var icmpConsecutiveFailures: Int = 0
    private val ICMP_FAIL_THRESHOLD = 2

    /** Recovery mutex â€” birden fazla recovery flow ayni anda calismasin.
     *  attemptReconnect, waitForSdkReconnectThenPay, reconnectAndPay,
     *  resetAndReconnectForPayment hepsi bu flag'i kontrol eder. Aksi
     *  halde paralel forceCleanSdkState cagrilari SDK ic state'ini bozar. */
    @Volatile private var isRecoveryInProgress: Boolean = false

    // Shutdown/Reboot receiver (MyPOS team recommendation)
    private var shutdownReceiver: BroadcastReceiver? = null
    private val nativeLogLock = Any()
    private var nativeDebugDir: File? = null

    // ======================== FLUTTER PLUGIN LIFECYCLE ========================

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        loadLastApprovedTransaction()
        channel = MethodChannel(binding.binaryMessenger, "mypos_payment")
        channel.setMethodCallHandler(this)

        logChannel = EventChannel(binding.binaryMessenger, "mypos_logs")
        logChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { logSink = events }
            override fun onCancel(arguments: Any?) { logSink = null }
        })

        POSHandler.setApplicationContext(binding.applicationContext)
        POSHandler.setSafetyClearingTimeout(30000)
        sendLog("MyPOS SDK initialized (v2, safety timeout: 30s)")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        if (ownsSocket) {
            cleanupBeforeExit()
        } else {
            sendLog("Flutter UI engine detached; keeping MyPOS socket owned by service runtime")
        }
        if (!nativeDebugExecutor.isShutdown) {
            nativeDebugExecutor.shutdown()
        }
        channel.setMethodCallHandler(null)
        appContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        sendLog("Activity attached")
        registerShutdownReceiver()
        // OperationActivity dondukten sonra Flutter'a haber vermek icin
        // ActivityResultListener kaydet
        binding.addActivityResultListener { reqCode, resultCode, data ->
            handleOperationActivityResult(reqCode, resultCode, data)
        }
    }

    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener { reqCode, resultCode, data ->
            handleOperationActivityResult(reqCode, resultCode, data)
        }
    }

    override fun onDetachedFromActivity() {
        if (ownsSocket) {
            cleanupBeforeExit()
        } else {
            sendLog("Activity detached; keeping MyPOS socket owned by service runtime")
        }
        unregisterShutdownReceiver()
        activity = null
    }

    private val REQ_CODE_TWINT_VIA_ACTIVITY = 9001
    private val REQ_CODE_PURCHASE_VIA_ACTIVITY = 9002

    /**
     * MyPOS support'un onerdigi alternatif TWINT akisi:
     * Intent ile OperationActivity'i ac, sonuc onActivityResult'a gelir.
     * SDK'nin onPOSInfoReceived/onTransactionComplete callback'i atmama
     * bug'ini bypass etme amacli.
     */
    private fun handleOperationActivityResult(
        reqCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (reqCode != REQ_CODE_TWINT_VIA_ACTIVITY &&
            reqCode != REQ_CODE_PURCHASE_VIA_ACTIVITY) {
            return false
        }
        try {
            val posStatus = data?.getIntExtra("pos_status", -1) ?: -1
            // transaction_data Parcelable<TransactionData> olarak gelir
            val txData = if (data != null) {
                @Suppress("DEPRECATION")
                data.getParcelableExtra<TransactionData>("transaction_data")
            } else null

            cancelPaymentTimeout()
            isPaymentInProgress = false
            restorePosHandlerListenersAfterOperationActivity("activity result reqCode=$reqCode")

            if (pendingResult == null || pendingOp.isEmpty()) {
                sendLog("OperationActivityResult ignored: no pending result (late callback)")
                return true
            }

            if (!isFlutterActivityAlive()) {
                sendLog("OperationActivityResult dropped: Flutter activity is not alive")
                pendingResult = null; pendingOp = ""
                return true
            }

            if (txData != null && (txData.rrn?.isNotEmpty() == true ||
                    txData.authCode?.isNotEmpty() == true)) {
                // Approval kontrol
                val declinedReason = txData.declinedReason1?.takeIf { it.isNotEmpty() }
                    ?: txData.declineReason2?.takeIf { it.isNotEmpty() }
                if (declinedReason != null) {
                    completePendingError("DECLINED", declinedReason)
                } else {
                    completePendingSuccess(hashMapOf(
                        "success" to true,
                        "status" to "approved",
                        "amount" to (txData.amount ?: "0"),
                        "authCode" to (txData.authCode ?: ""),
                        "rrn" to (txData.rrn ?: ""),
                        "transactionId" to (txData.rrn ?: ""),
                        "maskedPan" to (txData.panMasked ?: ""),
                        "cardType" to (txData.aidName ?: ""),
                        "terminalId" to (txData.terminalID ?: ""),
                        "merchantId" to (txData.merchantID ?: ""),
                        "stan" to (txData.stan ?: "")
                    ))
                }
            } else if (posStatus != -1 && posStatus != POSHandler.POS_STATUS_SUCCESS) {
                completePendingError(
                    "DECLINED",
                    "Activity result status=${getStatusName(posStatus)} ($posStatus)",
                )
            } else if (resultCode == Activity.RESULT_CANCELED) {
                completePendingError("CANCELLED", "User cancelled (activity)")
            } else {
                completePendingError(
                    "NO_DATA",
                    "OperationActivity returned no transaction_data",
                )
            }
            pendingResult = null; pendingOp = ""
        } catch (e: Exception) {
            sendLog("OperationActivityResult error: ${e.message}")
            restorePosHandlerListenersAfterOperationActivity("activity result error")
            completePendingError("ACTIVITY_ERROR", e.message ?: "Activity result error")
            pendingResult = null; pendingOp = ""
        }
        return true
    }

    private fun isFlutterActivityAlive(): Boolean {
        val act = activity ?: return false
        if (act.isFinishing) return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.JELLY_BEAN_MR1 || !act.isDestroyed
    }

    private fun completePendingSuccess(payload: Any) {
        try {
            pendingResult?.success(payload)
        } catch (t: Throwable) {
            sendLog("pendingResult.success failed: ${t.javaClass.simpleName}: ${t.message}")
        }
    }

    private fun completePendingError(code: String, message: String) {
        try {
            pendingResult?.error(code, message, null)
        } catch (t: Throwable) {
            sendLog("pendingResult.error failed: ${t.javaClass.simpleName}: ${t.message}")
        }
    }

    private fun restorePosHandlerListenersAfterOperationActivity(reason: String) {
        try {
            sendLog("Restoring POSHandler listeners after OperationActivity ($reason)")
            initPosHandler()
        } catch (t: Throwable) {
            sendLog("Restore listeners after OperationActivity failed: ${t.javaClass.simpleName}: ${t.message}")
        }
    }

    private fun launchTwintViaActivity(amount: Double, result: MethodChannel.Result) {
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "Activity not attached", null)
            return
        }
        try {
            sendLog("â³ POSHandler.openPaymentActivity (TWINT) â€” amount=$amount activity=${act.javaClass.simpleName}")
            isPaymentInProgress = true
            paymentStartedAtMs = System.currentTimeMillis()
            lastFinancialStatus = -1
            lastFinancialFailureStatus = -1
            pendingOp = "twint"
            pendingResult = result

            try {
                POSHandler.setCurrency(Currency.CHF)
                sendLog("  setCurrency(CHF) OK")
            } catch (e: Throwable) {
                sendLog("  âš ï¸ setCurrency error: ${e.javaClass.simpleName}: ${e.message}")
            }

            val amountStr = String.format(java.util.Locale.US, "%.2f", amount)
            val tranRef = java.util.UUID.randomUUID().toString()

            // Yeni AAR'da SDK'nin kendi launcher'i â€” internal Intent + extras +
            // command=23 (TWINT_PURCHASE) ayarliyor. Manuel Intent yapmiyoruz.
            try {
                posHandler?.openPaymentActivity(
                    act,
                    REQ_CODE_TWINT_VIA_ACTIVITY,
                    amountStr,
                    tranRef,
                )
                sendLog("  âœ“ openPaymentActivity(reqCode=$REQ_CODE_TWINT_VIA_ACTIVITY, amount=$amountStr, tranRef=$tranRef) returned")
            } catch (e: Throwable) {
                sendLog("  âŒ openPaymentActivity error: ${e.javaClass.simpleName}: ${e.message}")
                e.printStackTrace()
                throw e
            }
            schedulePaymentTimeout(result, "twintPurchase")
        } catch (e: Throwable) {
            sendLog("launchTwintViaActivity FAILED: ${e.javaClass.simpleName}: ${e.message}")
            e.printStackTrace()
            isPaymentInProgress = false
            pendingResult = null; pendingOp = ""
            result.error("ACTIVITY_ERROR", "${e.javaClass.simpleName}: ${e.message}", null)
        }
    }

    /**
     * App kapanirken temiz cikis.
     */
    private fun cleanupBeforeExit() {
        if (!isConfigured) return
        autoReconnectEnabled = false
        sendLog("App closing â€” cleanup...")
        stopWatchdog()
        clearPendingConnectionState()
        cancelPendingReconnect()
        nativeDebugExecutor.shutdown()

        if (currentConnectionType == ConnectionType.TCP_IP) {
            try {
                MyPosTcpConnectionCleaner.close(
                    "MyPosPlugin cleanupBeforeExit",
                    settleMs = 250L,
                    context = currentContext(),
                )
                sendLog("TCP connection cleaned on exit")
            } catch (e: Exception) {
                sendLog("Cleanup error: ${e.message}")
            }
        }

        forceCleanSdkState()
    }

    /**
     * Shutdown/Reboot receiver â€” MyPOS team recommendation.
     * Cihaz kapanirken/restart olurken terminal'e disconnect gonderir.
     */
    private fun registerShutdownReceiver() {
        if (shutdownReceiver != null) return
        shutdownReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                sendLog("Device shutting down/rebooting â€” disconnecting terminal")
                cleanupBeforeExit()
            }
        }
        try {
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_SHUTDOWN)
                addAction(Intent.ACTION_REBOOT)
            }
            activity?.registerReceiver(shutdownReceiver, filter)
            sendLog("Shutdown receiver registered")
        } catch (e: Exception) {
            sendLog("Shutdown receiver error: ${e.message}")
        }
    }

    private fun unregisterShutdownReceiver() {
        shutdownReceiver?.let {
            try { activity?.unregisterReceiver(it) } catch (_: Exception) {}
        }
        shutdownReceiver = null
    }

    /**
     * TCP socket state check (SDK 2.1.9: pure state, no side effect).
     * isConnected() artik sadece mSocket.isConnected() && !mSocket.isClosed() kontrolu yapar.
     * OS-level state gosterir; stale connection'i her zaman tespit etmez.
     * Gercek network liveness icin ICMP ping veya heartbeat gerekir.
     */
    private fun verifyTcpSocketAlive(): Boolean {
        if (currentConnectionType != ConnectionType.TCP_IP) return true
        if (posHandler == null) return false
        return try {
            posHandler!!.isConnected
        } catch (e: Exception) {
            sendLog("Socket state check error: ${e.message}")
            false
        }
    }

    private fun waitForConnectionState(
        timeoutMs: Long,
        pollMs: Long,
        onReady: () -> Unit,
        onTimeout: () -> Unit,
        predicate: () -> Boolean,
    ) {
        if (predicate()) {
            onReady()
            return
        }

        val startTime = System.currentTimeMillis()
        var resolved = false

        fun finish(action: () -> Unit) {
            if (resolved) return
            resolved = true
            action()
        }

        lateinit var poller: Runnable
        poller = Runnable {
            if (MyPosTcpConnectionCleaner.isReconnectBlocked()) {
                finish(onTimeout)
                return@Runnable
            }

            if (predicate()) {
                finish(onReady)
                return@Runnable
            }

            if (System.currentTimeMillis() - startTime >= timeoutMs) {
                finish(onTimeout)
                return@Runnable
            }

            mainHandler.postDelayed(poller, pollMs)
        }

        mainHandler.postDelayed(poller, pollMs)
    }

    // ======================== STATE MANAGEMENT ========================

    /**
     * Connection state degistiginde tek merkezden guncelle.
     * Tum Flutter bildirimleri buradan gider.
     */
    private fun updateConnectionState(newState: ConnectionState, reason: String = "") {
        val oldState = connectionState
        if (oldState == newState) return  // Gereksiz guncelleme yapma

        // Gecici connect/reconnect cikmalarini kisa sure gecikmeyle bildir.
        // USB/TCP auto reconnect aktifken bu sayede UI tarafinda "waiting for connection"
        // fliklerinin kisa sureli gelip gitmesi azalir.
        if ((newState == ConnectionState.DISCONNECTED || newState == ConnectionState.RECONNECTING) &&
            shouldDebounceDisconnectTransition(reason) &&
            autoReconnectEnabled) {
            scheduleConnectionStateTransition(newState, reason)
            return
        }

        commitConnectionState(newState, reason)
    }

    private fun shouldDebounceDisconnectTransition(reason: String): Boolean {
        if (MyPosTcpConnectionCleaner.isReconnectBlocked()) return false
        if (reason.contains("Manual disconnect", ignoreCase = true)) return false
        if (reason.contains("shutdown", ignoreCase = true)) return false
        if (reason.contains("while shutdown", ignoreCase = true)) return false
        if (shouldUseTcpReconnectState()) return true
        return true
    }

    private fun shouldUseTcpReconnectState(): Boolean {
        if (isManualDisconnectInProgress) return false
        if (!autoReconnectEnabled) return false
        if (currentConnectionType != ConnectionType.TCP_IP) return false
        if (MyPosTcpConnectionCleaner.isReconnectBlocked()) return false
        return true
    }

    private fun shouldSuppressTcpTransientDisconnect(): Boolean {
        if (!shouldUseTcpReconnectState()) return false
        if (transientDisconnectWindowStartMs == 0L ||
            System.currentTimeMillis() - transientDisconnectWindowStartMs > TCP_TRANSIENT_DISCONNECT_WINDOW_MS
        ) {
            transientDisconnectWindowStartMs = System.currentTimeMillis()
            transientDisconnectCount = 0
        }

        return if (System.currentTimeMillis() - lastConnectedStateAtMs < TCP_RECONNECT_GRACE_MS) {
            transientDisconnectCount++
            true
        } else {
            transientDisconnectCount++
            transientDisconnectCount <= TCP_TRANSIENT_DISCONNECT_MAX
        }
    }

    private fun resetTransientDisconnectWindow() {
        transientDisconnectWindowStartMs = 0L
        transientDisconnectCount = 0
    }

    private fun scheduleConnectionStateTransition(
        newState: ConnectionState,
        reason: String,
    ) {
        if ((newState == ConnectionState.DISCONNECTED || newState == ConnectionState.RECONNECTING) &&
            shouldSuppressTcpTransientDisconnect()
        ) {
            sendLog("Transient TCP disconnect suppressed ($reason, count=$transientDisconnectCount)")
            return
        }

        if (pendingConnectionState == newState && pendingConnectionStateReason == reason) {
            return
        }

        clearPendingConnectionState()

        val oldState = connectionState
        val runnable = Runnable {
            pendingConnectionState = null
            pendingConnectionStateReason = ""
            if (connectionState == newState) {
                return@Runnable
            }
            sendLog(
                "State transition delayed: $oldState -> $newState ("
                    + "debounced ${DISCONNECT_STATE_DEBOUNCE_MS}ms, reason=$reason)",
            )
            commitConnectionState(newState, reason)
        }

        pendingConnectionState = newState
        pendingConnectionStateReason = reason
        pendingConnectionStateRunnable = runnable
        sendLog("State transition queued: $oldState -> $newState ($reason)")
        mainHandler.postDelayed(runnable, DISCONNECT_STATE_DEBOUNCE_MS)
    }

    private fun clearPendingConnectionState() {
        pendingConnectionStateRunnable?.let { mainHandler.removeCallbacks(it) }
        pendingConnectionStateRunnable = null
        pendingConnectionState = null
        pendingConnectionStateReason = ""
    }

    private fun commitConnectionState(newState: ConnectionState, reason: String = "") {
        clearPendingConnectionState()

        val oldState = connectionState
        if (oldState == newState) return

        connectionState = newState
        when (newState) {
            ConnectionState.CONNECTED -> {
                lastConnectedStateAtMs = System.currentTimeMillis()
                resetTransientDisconnectWindow()
            }
            ConnectionState.DISCONNECTED -> {
                if (oldState == ConnectionState.CONNECTED) {
                    transientDisconnectWindowStartMs = System.currentTimeMillis()
                }
            }
            else -> {}
        }

        sendLog("State: $oldState -> $newState ${if (reason.isNotEmpty()) "($reason)" else ""}")

        // Flutter'a bildir
        try {
            channel.invokeMethod("onConnectionChanged", mapOf(
                "connected" to (newState == ConnectionState.CONNECTED),
                "state" to newState.name,
                "reason" to reason
            ))
        } catch (e: Exception) {
            Log.w(TAG, "Flutter notify error: ${e.message}")
        }
    }

    private fun sdkSocketAlive(): Boolean {
        return try {
            val handler = posHandler ?: POSHandler.getInstance().also { posHandler = it }
            handler.isConnected
        } catch (_: Exception) {
            false
        }
    }

    private fun syncConnectionStateFromSdk(reason: String): Boolean {
        val sdkAlive = sdkSocketAlive()
        if (sdkAlive && connectionState != ConnectionState.CONNECTED) {
            reconnectAttempts = 0
            isReconnecting = false
            updateConnectionState(ConnectionState.CONNECTED, reason)
        } else if (!sdkAlive && connectionState == ConnectionState.CONNECTED) {
            if (shouldUseTcpReconnectState()) {
                updateConnectionState(ConnectionState.RECONNECTING, "$reason - TCP reconnecting")
            } else {
                updateConnectionState(ConnectionState.DISCONNECTED, "$reason - SDK socket closed")
            }
        }
        return sdkAlive
    }

    // ======================== WATCHDOG (ICMP PING) ========================
    // SDK'nin checkConnection()'i mTransactionInProgress set ediyor.
    // Biz ICMP ping kullaniyoruz â€” SDK'ya dokunmaz, terminal ekranini bozmaz.

    private fun startWatchdog() {
        if (currentConnectionType != ConnectionType.TCP_IP) {
            sendLog("Watchdog: Not TCP/IP, skipping")
            return
        }
        stopWatchdog()
        watchdogActive = true

        watchdogCycleCount = 0
        watchdogThread = Thread {
            sendLog("Watchdog started (${WATCHDOG_INTERVAL_MS/1000}s ICMP, socket check every ${SOCKET_CHECK_INTERVAL * WATCHDOG_INTERVAL_MS / 1000}s)")
            while (watchdogActive) {
                try { Thread.sleep(WATCHDOG_INTERVAL_MS) } catch (e: InterruptedException) { break }
                if (!watchdogActive) break
                // Odeme sirasinda watchdog'u atla â€” AMA 90s+ surdukse "hung"
                // demektir, fiziksel kopma ihtimali var: kontrol et.
                if (isPaymentInProgress) {
                    val stuckMs = System.currentTimeMillis() - paymentStartedAtMs
                    if (stuckMs < 90_000L) continue
                    sendLog("Watchdog: payment stuck for ${stuckMs/1000}s â€” checking connection anyway")
                }

                // CRITICAL fix: recovery flow varken watchdog'u atla. Aksi
                // halde aktif reconnect'i bozar (SDK auto-reconnect ile yarisma).
                if (isRecoveryInProgress) {
                    sendLog("Watchdog: recovery in progress â€” skipping cycle")
                    continue
                }

                watchdogCycleCount++
                val reachable = icmpPing(tcpIp, 3000)
                // SDK 2.1.9: isConnected() pure state check, yan etkisiz
                val socketAlive = try { posHandler?.isConnected == true } catch (_: Exception) { false }

                mainHandler.post {
                    if (!watchdogActive) return@post
                    if (isRecoveryInProgress) return@post

                    // ICMP debounce: bir hata yetmiyor (Wi-Fi packet loss yanlis
                    // disconnect tetikliyordu). 2 ardisik fail olunca DISCONNECTED.
                    if (!reachable) {
                        icmpConsecutiveFailures++
                    } else {
                        icmpConsecutiveFailures = 0
                    }
                    val icmpDeadConfirmed = icmpConsecutiveFailures >= ICMP_FAIL_THRESHOLD

                    // State CONNECTED iken socket olu -> SDK reconnect devrede olmali;
                    // state guncelle, SDK'ya zaman tani (socket geri donerse onConnected fires)
                    if (connectionState == ConnectionState.CONNECTED && !socketAlive) {
                        sendLog("Watchdog: Socket state=false while CONNECTED â€” marking DISCONNECTED, waiting for SDK reconnect")
                        if (shouldUseTcpReconnectState()) {
                            updateConnectionState(ConnectionState.RECONNECTING, "Watchdog: TCP reconnecting")
                        } else {
                            updateConnectionState(ConnectionState.DISCONNECTED, "Watchdog: socket not alive")
                        }
                    }

                    // Socket canli ama state yanlis -> state'i duzelt (SDK auto-reconnect basarili olmus)
                    if (socketAlive && connectionState != ConnectionState.CONNECTED) {
                        sendLog("Watchdog: Socket alive but state != CONNECTED â€” syncing to CONNECTED")
                        reconnectAttempts = 0
                        isReconnecting = false
                        cancelPendingReconnect()
                        updateConnectionState(ConnectionState.CONNECTED, "Watchdog: socket recovered")
                    }

                    // Terminal erisilemez (DEBOUNCED) + state CONNECTED -> DISCONNECTED
                    if (icmpDeadConfirmed && connectionState == ConnectionState.CONNECTED) {
                        sendLog("Watchdog: Terminal unreachable via ICMP ($icmpConsecutiveFailures consecutive fails)")
                        if (shouldUseTcpReconnectState()) {
                            updateConnectionState(ConnectionState.RECONNECTING, "Watchdog: TCP reconnecting")
                        } else {
                            updateConnectionState(ConnectionState.DISCONNECTED, "Watchdog: ICMP unreachable (debounced)")
                        }
                    }

                    // Uzun suredir disconnect + network var + SDK reconnect basarisiz -> fallback
                    // Her SOCKET_CHECK_INTERVAL cycle'da (~1dk) bir kez fallback dene
                    val shouldFallback = connectionState != ConnectionState.CONNECTED
                            && reachable
                            && !socketAlive
                            && !isReconnecting
                            && !isRecoveryInProgress
                            && (watchdogCycleCount % SOCKET_CHECK_INTERVAL == 0)
                    if (shouldFallback) {
                        sendLog("Watchdog: Network OK but SDK still disconnected after ~1min â€” fallback reconnect")
                        scheduleReconnect()
                    }
                }
            }
            Log.d(TAG, "Watchdog stopped")
        }.apply {
            isDaemon = true
            name = "mypos-watchdog"
            start()
        }
    }

    private fun stopWatchdog() {
        watchdogActive = false
        val t = watchdogThread
        watchdogThread = null
        if (t != null && t.isAlive) {
            t.interrupt()
            try {
                // Join max 500ms â€” Thread.sleep(WATCHDOG_INTERVAL_MS) icindeyse
                // interrupt InterruptedException firlatip break edecek, dolayisi
                // ile thread cikis hemen olur. join() ile zombie thread kalmasin
                // ve eski posHandler/mainHandler reference'lari serbest birakilsin.
                t.join(500)
                if (t.isAlive) {
                    Log.w(TAG, "Watchdog thread did not exit within 500ms â€” leaving it to die naturally")
                }
            } catch (e: InterruptedException) {
                // Caller thread interrupt edildi, propagate
                Thread.currentThread().interrupt()
            }
        }
    }

    private fun icmpPing(ip: String, timeoutMs: Int): Boolean {
        return try {
            java.net.InetAddress.getByName(ip).isReachable(timeoutMs)
        } catch (e: Exception) { false }
    }

    // ======================== RECONNECT (FALLBACK) ========================
    // SDK 2.1.9 TCP icin kendi 3s reconnect loop'una sahip.
    // Bu logic USB/Bluetooth icin ve SDK reconnect'inin yetmedigi kosellerde fallback.
    //
    // Kurallari:
    // 1. Asla vazgecme â€” suresiz reconnect
    // 2. Backoff: 3s, 6s, 9s... max 30s
    // 3. Odeme sirasinda reconnect deneme

    private var reconnectRunnable: Runnable? = null

    private fun scheduleReconnect() {
        if (!autoReconnectEnabled) {
            sendLog("Reconnect skipped: auto reconnect disabled")
            isReconnecting = false
            return
        }
        if (isReconnecting) return
        if (isPaymentInProgress) return
        if (MyPosTcpConnectionCleaner.isReconnectBlocked()) {
            sendLog("Reconnect skipped: device shutdown/reconnect pause active")
            isReconnecting = false
            return
        }

        isReconnecting = true
        val delay = minOf(RECONNECT_BASE_DELAY_MS * (reconnectAttempts + 1), RECONNECT_MAX_DELAY_MS)

        sendLog("Reconnect #${reconnectAttempts + 1} scheduled in ${delay}ms")
        updateConnectionState(ConnectionState.RECONNECTING, "Scheduling reconnect")

        reconnectRunnable = Runnable { attemptReconnect() }
        mainHandler.postDelayed(reconnectRunnable!!, delay)
    }

    private fun cancelPendingReconnect() {
        reconnectRunnable?.let { mainHandler.removeCallbacks(it) }
        reconnectRunnable = null
        isReconnecting = false
    }

    private fun currentContext(): Context? = activity ?: appContext

    private fun attemptReconnect() {
        if (MyPosTcpConnectionCleaner.isReconnectBlocked()) {
            sendLog("Reconnect attempt skipped: device shutdown/reconnect pause active")
            isReconnecting = false
            isRecoveryInProgress = false
            return
        }

        if (!isConfigured) {
            sendLog("Not configured, cannot reconnect")
            isReconnecting = false
            isRecoveryInProgress = false
            return
        }

        // CRITICAL fix: baska recovery flow varsa skip et â€” paralel reconnect
        // SDK ic state'ini bozar.
        if (isRecoveryInProgress) {
            sendLog("Recovery already in progress â€” attemptReconnect skipping")
            isReconnecting = false
            return
        }
        isRecoveryInProgress = true

        reconnectAttempts++
        sendLog("Reconnect attempt $reconnectAttempts...")

        val ctx = currentContext()
        if (ctx == null) {
            sendLog("Context null, will retry")
            isReconnecting = false
            isRecoveryInProgress = false
            mainHandler.postDelayed({ scheduleReconnect() }, 5000)
            return
        }

        // TCP'de "Connection refused" buyuk olasilikla terminal'de half-open
        // socket var demek. MainActivity.closeMyPosTcpSocket() reflection ile mSocket'i
        // direkt kapatir; resetData()'dan daha agresif. 300ms ver ki Sigma
        // "Waiting for Connection"a gecsin, sonra yeni baglanti ac.
        if (currentConnectionType == ConnectionType.TCP_IP) {
            try {
                MyPosTcpConnectionCleaner.close(
                    "pre-reconnect cleanup",
                    context = ctx,
                )
                sendLog("Pre-reconnect cleanup: old TCP socket closed")
            } catch (e: Exception) {
                sendLog("Pre-reconnect cleanup error: ${e.message}")
            }
            mainHandler.postDelayed({ doConnectAttempt(ctx) }, RECONNECT_RETRY_STALE_MS)
        } else {
            doConnectAttempt(ctx)
        }

        // 10 saniye sonra kontrol et â€” onConnected gelmis mi?
        mainHandler.postDelayed({
            isRecoveryInProgress = false  // mutex serbest
            if (MyPosTcpConnectionCleaner.isReconnectBlocked()) {
                sendLog("Reconnect timeout check skipped: device shutdown/reconnect pause active")
                isReconnecting = false
                return@postDelayed
            }
            if (connectionState != ConnectionState.CONNECTED) {
                sendLog("Reconnect timeout â€” still not connected")
                isReconnecting = false
                scheduleReconnect()  // Tekrar dene, asla vazgecme
            }
        }, 10000)
    }

    /// Reconnect'in actual connectDevice cagrisini yapar; cleanup gecikmesi
    /// sonrasi cagrilmak uzere ayri tutuldu.
    private fun doConnectAttempt(ctx: Context) {
        if (MyPosTcpConnectionCleaner.isReconnectBlocked()) {
            sendLog("Connect attempt skipped: device shutdown/reconnect pause active")
            isReconnecting = false
            return
        }
        try {
            if (currentConnectionType == ConnectionType.TCP_IP) {
                connectTcpWithStaleBreaker(ctx, "scheduled reconnect")
            } else if (currentConnectionType == ConnectionType.USB) {
                posHandler?.connectDevice(ctx, true)
                sendLog("USB reconnect request sent")
            }
        } catch (e: Exception) {
            sendLog("Reconnect error: ${e.message}")
        }
    }

    // ======================== POS HANDLER SETUP ========================
    // SDK 2.1.9: clearConnectionListeners() ile guvenli re-init mumkun.

    private fun initPosHandler() {
        if (posHandler == null) {
            sendLog("posHandler is null!")
            return
        }

        if (listenersInitialized) {
            // Yapilandirma degisikligi (ornegin USB -> TCP) durumunda eski listener'lari temizle
            sendLog("Re-initializing listeners â€” clearing old ones first")
            try {
                posHandler?.clearConnectionListeners()
            } catch (e: Exception) {
                sendLog("clearConnectionListeners error: ${e.message}")
            }
            listenersInitialized = false
        }

        sendLog("Setting up POSHandler listeners...")

        // 1. Connection Listener
        posHandler?.setConnectionListener(object : ConnectionListener {
            override fun onConnected(device: BluetoothDevice?) {
                mainHandler.post {
                    if (MyPosTcpConnectionCleaner.isReconnectBlocked()) {
                        sendLog("SDK CONNECTED during shutdown/reconnect pause â€” closing immediately")
                        try {
                            MyPosTcpConnectionCleaner.closeGracefullyForShutdown(
                                "late SDK onConnected while reconnect blocked",
                                settleMs = 0L,
                                context = currentContext(),
                            )
                        } catch (e: Exception) {
                            sendLog("Late shutdown close error: ${e.message}")
                        }
                        updateConnectionState(ConnectionState.DISCONNECTED, "Late connect closed during shutdown")
                        return@post
                    }
                    sendLog("SDK CONNECTED: ${device?.name ?: "TCP/IP Terminal"}")
                    reconnectAttempts = 0
                    isReconnecting = false
                    isPosReady = false  // GetStatus cevabi henuz gelmedi
                    cancelPendingReconnect()
                    updateConnectionState(ConnectionState.CONNECTED, "SDK onConnected")

                    // TCP/IP icin socket keepalive ayarla
                    if (currentConnectionType == ConnectionType.TCP_IP) {
                        enableSocketKeepalive()
                        startWatchdog()
                    }
                }
            }

            override fun onDisconnected(device: BluetoothDevice?) {
                mainHandler.post {
                    sendLog("SDK DISCONNECTED: ${device?.name ?: "Terminal"}")
                    isPosReady = false
                    if (MyPosTcpConnectionCleaner.isReconnectBlocked()) {
                        cancelPendingReconnect()
                        stopWatchdog()
                        updateConnectionState(ConnectionState.DISCONNECTED, "SDK onDisconnected during shutdown")
                        sendLog("Reconnect blocked after disconnect â€” no reconnect will be scheduled")
                        return@post
                    }

                    if (connectionState == ConnectionState.CONNECTED || connectionState == ConnectionState.CONNECTING) {
                        if (shouldUseTcpReconnectState()) {
                            updateConnectionState(ConnectionState.RECONNECTING, "SDK onDisconnected (TCP auto reconnect)")
                        } else {
                            updateConnectionState(ConnectionState.DISCONNECTED, "SDK onDisconnected")
                        }
                    }

                    // SDK 2.1.9: TCP icin SDK kendisi 2.5s sleep + retry loop'u kosar.
                    // Bizim reconnect'imiz resetTcpConnection() cagirir ve mRunning=false yapar,
                    // bu da SDK'nin reconnect'ini OLDURUR. Yarismamak icin TCP'de bekliyoruz.
                    // USB/Bluetooth'ta SDK otomatik reconnect YAPMIYOR, fallback gerekli.
                    if (isConfigured &&
                        !isPaymentInProgress &&
                        currentConnectionType != ConnectionType.TCP_IP &&
                        !MyPosTcpConnectionCleaner.isReconnectBlocked()) {
                        scheduleReconnect()
                    }
                }
            }
        })

        // 2. POS Ready Listener â€” CommandGetStatus tamamlandi, terminal hazir
        posHandler?.setPOSReadyListener {
            mainHandler.post {
                isPosReady = true
                sendLog("POS READY â€” terminal GetStatus cevaplandi, artik komut gonderilebilir")
            }
        }

        // 3. POS Info Listener â€” tum islem sonuclari
        posHandler?.setPOSInfoListener(object : POSInfoListener {
            override fun onPOSInfoReceived(command: Int, status: Int, description: String?, bundle: Bundle?) {
                mainHandler.post {
                    handlePosInfo(command, status, description, bundle)
                }
            }

            override fun onTransactionComplete(data: TransactionData?) {
                mainHandler.post {
                    handleTransactionComplete(data)
                }
            }
        })

        // 4. Transaction Cleared Listener â€” SADECE clearBatch/endOfDay icin
        // pendingResult'i complete eder. TWINT/purchase/refund operasyonu
        // pending iken bu callback fire olursa (SDK bug), ignore edilir.
        posHandler?.setTransactionClearedListener { status ->
            mainHandler.post {
                sendLog("Batch cleared â€” Status: $status (pendingOp=$pendingOp)")
                if (pendingOp == "clearBatch" || pendingOp == "endOfDay") {
                    pendingResult?.success(hashMapOf("success" to true, "status" to status))
                    pendingResult = null; pendingOp = ""
                    pendingOp = ""
                } else if (pendingResult != null) {
                    sendLog("âš ï¸ Batch cleared callback fired but pendingOp=$pendingOp â€” NOT completing pendingResult (likely SDK stray callback)")
                }
            }
        }

        listenersInitialized = true
        sendLog("All listeners ready (one-time init complete)")
    }

    /**
     * POSInfo callback handler
     */
    private fun handlePosInfo(command: Int, status: Int, description: String?, bundle: Bundle?) {
        sendLog("--- POSInfo: cmd=${getCommandName(command)} status=${getStatusName(status)} desc=${description ?: "-"}")

        // Finansal komut status'unu kaydet â€” onTransactionComplete'te karar
        // verirken kullanilir. USER_CANCEL gormussek complete success sayilmaz.
        val isApprovedTwintFollowup = pendingOp == "twint" && twintApprovedBySuccessStatus
        if (command == POSHandler.COMMAND_PURCHASE ||
            command == POSHandler.COMMAND_REFUND ||
            command == POSHandler.COMMAND_TWINT_PURCHASE) {
            lastFinancialStatus = status
            if (status in terminalFailureStatuses() && !isApprovedTwintFollowup) {
                lastFinancialFailureStatus = status
            }
        }

        // Kesin hata statuslari â€” timeout iptal
        val errorStatuses = terminalFailureStatuses()
        if (status in errorStatuses) {
            if (isApprovedTwintFollowup) {
                sendLog("TWINT failure status ignored after approved status: ${getStatusName(status)} (${getCommandName(command)})")
                return
            }
            cancelPaymentTimeout()
        }

        if (status == POSHandler.POS_STATUS_SUCCESS && pendingOp == "twint") {
            val hasTwintAmount = bundleValue(bundle, "b_amount", "amount", "productAmount") != null
            if (command == POSHandler.COMMAND_TWINT_PURCHASE || hasTwintAmount) {
                if (markTwintSuccessStatusIfCurrent(command, bundle)) {
                    return
                }
            }
        }

        val financialCommands = setOf(
            POSHandler.COMMAND_PURCHASE,
            POSHandler.COMMAND_REFUND,
            POSHandler.COMMAND_TWINT_PURCHASE
        )
        val isFinancial = command in financialCommands

        // TWINT-ozel early termination (WHITELIST approach):
        // SADECE BILINEN definitive hata statuslari TWINT'i sonlandirir.
        // Bilinmeyen/negatif/progress status'larda bekle â€” SDK bazen status=-1
        // gibi "command sent" sinyali gonderiyor, onu iptal sanmayalim.
        if (command == POSHandler.COMMAND_TWINT_PURCHASE && pendingResult != null) {
            val twintTerminalErrorStatuses = setOf(
                POSHandler.POS_STATUS_USER_CANCEL,    // 2
                POSHandler.POS_STATUS_INTERNAL_ERROR, // 3
                POSHandler.POS_STATUS_TERMINAL_BUSY,  // 4
                POSHandler.POS_STATUS_WRONG_AMOUNT,   // 23
                POSHandler.POS_STATUS_COM_ERROR,      // 79
            )
            if (status in twintTerminalErrorStatuses) {
                // BUSY ise once auto-retry dene; kullaniciya hata gostermeden
                // 500ms sonra ayni TWINT istegini yeniden kuyrukla.
                if (status == POSHandler.POS_STATUS_TERMINAL_BUSY && maybeAutoRetryBusy()) {
                    return
                }
                // RAW SDK info: status code + name + description (SDK'dan gelen)
                val statusName = getStatusName(status)
                val rawMsg = description?.takeIf { it.isNotEmpty() }
                val rawCombined =
                    "TWINT terminated [SDK status=$status ($statusName)]" +
                        (if (rawMsg != null) " desc=\"$rawMsg\"" else "")
                sendLog("ðŸ›‘ $rawCombined")
                cancelPaymentTimeout()
                isPaymentInProgress = false
                twintApprovedBySuccessStatus = false
                pendingResult?.error(
                    "TWINT_$statusName",
                    rawCombined,
                    mapOf(
                        "status" to status,
                        "statusName" to statusName,
                        "description" to (rawMsg ?: ""),
                        "command" to command,
                    ),
                )
                pendingResult = null; pendingOp = ""
                pendingRetry = null
                return
            }
        }

        when (status) {
            POSHandler.POS_STATUS_SUCCESS -> {
                // KRITIK: POS_STATUS_SUCCESS (status=0) genel "ack" statusudur.
                // Finansal komutlar icin NIHAI basari DEGIL â€” onTransactionComplete bekleniyor.
                // Status=34 (POS_STATUS_SUCCESS_PURCHASE) veya onTransactionComplete fire etmeli.
                sendLog("POS_STATUS_SUCCESS (generic ack) â€” cmd=${getCommandName(command)}")
                if (pendingResult != null && !isFinancial && command != POSHandler.COMMAND_PING) {
                    if (pendingOp == "twint") {
                        sendLog("POS_STATUS_SUCCESS generic ack during TWINT â€” waiting for transaction data/fallback")
                        return
                    }
                    isPaymentInProgress = false
                    pendingResult?.success(hashMapOf(
                        "success" to true,
                        "amount" to (bundle?.getString("amount") ?: "0"),
                        "authCode" to (bundle?.getString("authCode") ?: ""),
                        "rrn" to (bundle?.getString("rrn") ?: ""),
                        "transactionId" to (bundle?.getString("rrn") ?: "")
                    ))
                    pendingResult = null; pendingOp = ""
                }
            }

            POSHandler.POS_STATUS_SUCCESS_PURCHASE,
            POSHandler.POS_STATUS_SUCCESS_REFUND -> {
                // GerÃ§ek finansal basari â€” terminal kart isledi, onaylandi.
                // onTransactionComplete yakinda full data ile gelmeli; simdilik sadece log.
                sendLog("FINANCIAL SUCCESS: ${getStatusName(status)} â€” waiting for onTransactionComplete")
            }

            POSHandler.POS_STATUS_PROCESSING -> {
                sendLog("PROCESSING...")
                // PING processing = baglanti canli
                if (command == POSHandler.COMMAND_PING) {
                    sendLog("PING processing â€” connection alive")
                    if (connectionState != ConnectionState.CONNECTED) {
                        reconnectAttempts = 0
                        isReconnecting = false
                        cancelPendingReconnect()
                        updateConnectionState(ConnectionState.CONNECTED, "PING processing")
                    }
                    pingResult?.success(mapOf("connected" to true, "pingSuccess" to true))
                    pingResult = null
                }
            }

            POSHandler.POS_STATUS_SUCCESS_PING -> {
                sendLog("PING SUCCESS â€” terminal alive")
                if (connectionState != ConnectionState.CONNECTED) {
                    reconnectAttempts = 0
                    isReconnecting = false
                    cancelPendingReconnect()
                    updateConnectionState(ConnectionState.CONNECTED, "PING success")
                }
                pingResult?.success(mapOf("connected" to true, "pingSuccess" to true))
                pingResult = null
            }

            POSHandler.POS_STATUS_PING_FAILED -> {
                sendLog("PING FAILED")
                pingResult?.success(mapOf("connected" to false, "pingSuccess" to false, "reason" to "Ping failed"))
                pingResult = null
            }

            POSHandler.POS_STATUS_PENDING_USER_INTERACTION -> {
                sendLog("Waiting for user interaction (card/QR)...")
            }

            POSHandler.POS_STATUS_USER_CANCEL -> {
                sendLog("User cancelled")
                isPaymentInProgress = false
                pendingResult?.error("CANCELLED", "User cancelled", null)
                pendingResult = null; pendingOp = ""
            }

            POSHandler.POS_STATUS_INTERNAL_ERROR -> {
                sendLog("INTERNAL ERROR")
                isPaymentInProgress = false
                pendingResult?.error("INTERNAL_ERROR", description ?: "Internal error", null)
                pendingResult = null; pendingOp = ""
            }

            POSHandler.POS_STATUS_TERMINAL_BUSY -> {
                if (maybeAutoRetryBusy()) {
                    // Retry zamanlandi, hata gostermeden cik
                    return
                }
                sendLog("TERMINAL BUSY â€” clearing SDK flag (retry exhausted or none)")
                forceCleanSdkState()
                isPaymentInProgress = false
                pendingResult?.error("BUSY", "Terminal busy, please retry in a few seconds", null)
                pendingResult = null; pendingOp = ""
                pendingRetry = null
            }

            POSHandler.POS_STATUS_WRONG_AMOUNT -> {
                val rawDesc = description?.takeIf { it.isNotEmpty() }
                val msg = "WRONG_AMOUNT [SDK status=23] " +
                    (rawDesc?.let { "desc=\"$it\"" } ?: "(no SDK description, amount rejected by terminal â€” check min/max)")
                sendLog("âš ï¸ $msg")
                isPaymentInProgress = false
                pendingResult?.error(
                    "WRONG_AMOUNT",
                    msg,
                    mapOf(
                        "status" to status,
                        "statusName" to "WRONG_AMOUNT",
                        "description" to (rawDesc ?: ""),
                        "command" to command,
                    ),
                )
                pendingResult = null; pendingOp = ""
            }

            POSHandler.POS_STATUS_COM_ERROR -> {
                // SDK bug: TWINT iptal/timeout durumunda da COM_ERROR firlatir.
                // Hemen "baglanti koptu" deme; socket hala acik olabilir.
                // Transaction'i iptal say, baglanti kaybi karari icin onDisconnected
                // callback'i bekle (SDK socket'i gercekten kapatirsa o fire olur).
                sendLog("COM_ERROR received â€” treating as transaction failure (TWINT cancel / timeout), NOT connection loss")
                isPaymentInProgress = false

                val rawDesc = description?.takeIf { it.isNotEmpty() }
                val cmdName = getCommandName(command)
                val errMsg =
                    "COM_ERROR [SDK status=$status (COM_ERROR)] cmd=$cmdName" +
                        (rawDesc?.let { " desc=\"$it\"" } ?: "")
                pendingResult?.error(
                    "PAYMENT_FAILED",
                    errMsg,
                    mapOf(
                        "status" to status,
                        "statusName" to "COM_ERROR",
                        "description" to (rawDesc ?: ""),
                        "command" to command,
                        "commandName" to cmdName,
                    ),
                )
                pendingResult = null; pendingOp = ""

                // Ping icin de bilgi ver ama "disconnected" demiyoruz;
                // gercek durum onDisconnected callback'inden gelecek.
                pingResult?.success(mapOf("connected" to true, "pingSuccess" to false, "reason" to "COM_ERROR on transaction"))
                pingResult = null
            }

            // ===== Diger kart hatalari â€” hepsi transaction-ending =====
            POSHandler.POS_STATUS_NO_CARD_FOUND -> {
                sendLog("No card found")
                isPaymentInProgress = false
                pendingResult?.error("NO_CARD", "Kart bulunamadi", null)
                pendingResult = null; pendingOp = ""
            }
            POSHandler.POS_STATUS_NOT_SUPPORTED_CARD -> {
                sendLog("Card not supported")
                isPaymentInProgress = false
                pendingResult?.error("CARD_NOT_SUPPORTED", "Kart desteklenmiyor", null)
                pendingResult = null; pendingOp = ""
            }
            POSHandler.POS_STATUS_CARD_CHIP_ERROR -> {
                sendLog("Card chip error")
                isPaymentInProgress = false
                pendingResult?.error("CARD_CHIP_ERROR", "Kart chip hatasi", null)
                pendingResult = null; pendingOp = ""
            }
            POSHandler.POS_STATUS_INVALID_PIN -> {
                sendLog("Invalid PIN")
                isPaymentInProgress = false
                pendingResult?.error("INVALID_PIN", "Yanlis PIN", null)
                pendingResult = null; pendingOp = ""
            }
            POSHandler.POS_STATUS_MAX_PIN_COUNT_EXCEEDED -> {
                sendLog("Max PIN attempts")
                isPaymentInProgress = false
                pendingResult?.error("PIN_LOCKED", "PIN deneme hakkini asti", null)
                pendingResult = null; pendingOp = ""
            }
            POSHandler.POS_STATUS_TRANSACTION_NOT_FOUND -> {
                sendLog("Transaction not found")
                isPaymentInProgress = false
                pendingResult?.error("TX_NOT_FOUND", "Islem bulunamadi", null)
                pendingResult = null; pendingOp = ""
            }

            else -> {
                // Bilinmeyen status â€” transaction'i fail ETME, cunku bir
                // sonraki SDK callback'inde definitive sonuc gelebilir.
                // Status'larin cogu "progress/screen" anlaminda (74=PRESENT_CARD,
                // 75=SELECT_DCC, 76=ENTER_PIN, 78=PASSWORD_REQUIRED vs).
                // Sadece logla; timeout zaten safety-net olarak calisir.
                val progressStatuses = setOf(
                    POSHandler.POS_STATUS_PENDING_USER_INTERACTION, // 1
                    POSHandler.POS_STATUS_PROCESSING,               // 11
                    74, // POS_STATUS_PRESENT_CARD_SCREEN
                    75, // POS_STATUS_SELECT_DCC_SCREEN
                    76, // POS_STATUS_ENTER_PIN_SCREEN
                    77, // POS_STATUS_DCC_BEEN_SELECTED
                    78, // POS_STATUS_PASSWORD_REQUIRED
                    29, // POS_STATUS_PIN_CHECK_ONLINE
                    52, // POS_STATUS_GIFTCARD_ACTIVATING
                    53, // POS_STATUS_GIFTCARD_DEACTIVATING
                    54, // POS_STATUS_GIFTCARD_BALANCE_CHECK
                    60, // POS_STATUS_REVERSING_TRANSACTION
                    48, // POS_STATUS_PREAUTH_COMPLETING
                    49, // POS_STATUS_PREAUTH_CANCELING
                    38, // POS_STATUS_DOWNLOADING_CERTIFICATES_IN_PROGRESS
                )
                if (status in progressStatuses) {
                    sendLog("Progress status ${getStatusName(status)} ($status) â€” keep waiting")
                } else {
                    // Gercekten bilinmeyen: log ama pendingResult'i bozma.
                    // Timeout safety-net (90s TWINT / 180s card) islem askida
                    // kalmayi onleyecek. Burada fail edersek PRESENT_CARD gibi
                    // progress status'larini yanlislikla oldururuz.
                    sendLog("â„¹ï¸ Unmapped status $status (${getStatusName(status)}) for ${getCommandName(command)} â€” keeping transaction alive; timeout will catch if no further progress")
                }
            }
        }
    }

    /**
     * Transaction Complete handler â€” odeme basarili
     */
    /**
     * TransactionData'nin TUM alanlarini dump et â€” SDK'nin gercekte ne
     * gonderdigini gorebilelim (iptal/success/decline durumlarini netlestirir).
     */
    private fun dumpTransactionData(d: TransactionData?): String {
        if (d == null) return "data=null"
        return buildString {
            append("TransactionData{")
            append("amount='${d.amount}', ")
            append("currency='${d.currencyIsoCode}', ")
            append("rrn='${d.rrn}', ")
            append("authCode='${d.authCode}', ")
            append("approval='${d.approval}', ")
            append("declinedReason1='${d.declinedReason1}', ")
            append("declineReason2='${d.declineReason2}', ")
            append("stan='${d.stan}', ")
            append("aid='${d.aid}', ")
            append("aidName='${d.aidName}', ")
            append("panMasked='${d.panMasked}', ")
            append("embossName='${d.embossName}', ")
            append("terminalID='${d.terminalID}', ")
            append("merchantID='${d.merchantID}', ")
            append("merchantName='${d.merchantName}', ")
            append("cvm='${d.cvm}', ")
            append("cardEntryMode='${d.cardEntryMode}', ")
            append("tipAmount='${d.tipAmount}', ")
            append("operatorCode='${d.operatorCode}', ")
            append("referenceNumber='${d.referenceNumber}', ")
            append("referenceNumberType=${d.referenceNumberType}, ")
            append("tranRef='${d.tranRef}', ")
            append("isDccUsed=${d.isDccUsed}, ")
            append("expireDate='${d.expireDate}', ")
            append("signatureRequired=${d.isSignatureRequired}, ")
            append("txDate=${d.transactionDateLocal}")
            append("}")
        }
    }

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

    private fun loadLastApprovedTransaction() {
        val prefs = appContext?.getSharedPreferences("mypos_state", Context.MODE_PRIVATE) ?: return
        lastApprovedRrn = prefs.getString("lastApprovedRrn", "") ?: ""
        lastApprovedAuthCode = prefs.getString("lastApprovedAuthCode", "") ?: ""
    }

    private fun rememberApprovedTransaction(data: TransactionData) {
        lastApprovedRrn = data.rrn?.trim() ?: ""
        lastApprovedAuthCode = data.authCode?.trim() ?: ""
        appContext
            ?.getSharedPreferences("mypos_state", Context.MODE_PRIVATE)
            ?.edit()
            ?.putString("lastApprovedRrn", lastApprovedRrn)
            ?.putString("lastApprovedAuthCode", lastApprovedAuthCode)
            ?.apply()
    }

    private fun parseTransactionAmount(value: String?): Double? {
        val raw = value?.trim() ?: return null
        val match = Regex("-?\\d+([\\.,]\\d+)?").find(raw)?.value ?: return null
        return match.replace(',', '.').toDoubleOrNull()
    }

    private fun transactionAmountMatches(dataAmount: String?, expectedAmount: Double?): Boolean {
        val expected = expectedAmount ?: return false
        val actual = parseTransactionAmount(dataAmount) ?: return false
        return java.lang.Math.abs(actual - expected) <= 0.005 ||
            java.lang.Math.abs((actual / 100.0) - expected) <= 0.005
    }

    private fun bundleValue(bundle: Bundle?, vararg keys: String): String? {
        if (bundle == null) return null
        for (key in keys) {
            val value = try { bundle.get(key) } catch (_: Exception) { null }
            if (value != null) return value.toString()
        }
        return null
    }

    private fun markTwintSuccessStatusIfCurrent(command: Int, bundle: Bundle?): Boolean {
        if (pendingResult == null || pendingOp != "twint") {
            sendLog("TWINT SUCCESS status ignored: no active TWINT pending cmd=${getCommandName(command)}")
            return false
        }
        if (lastFinancialFailureStatus in terminalFailureStatuses()) {
            sendLog(
                "TWINT SUCCESS status ignored: failure status already seen " +
                    "${getStatusName(lastFinancialFailureStatus)} cmd=${getCommandName(command)}"
            )
            return false
        }

        val expectedAmount = pendingRetry
            ?.takeIf { it.op == "twint" && it.result == pendingResult }
            ?.amount
        val bundleAmount = bundleValue(bundle, "b_amount", "amount", "productAmount")
        if (!transactionAmountMatches(bundleAmount, expectedAmount)) {
            sendLog(
                "TWINT SUCCESS status ignored: amount mismatch " +
                    "cmd=${getCommandName(command)} bundle=$bundleAmount expected=$expectedAmount"
            )
            return false
        }

        val elapsedMs = System.currentTimeMillis() - paymentStartedAtMs
        twintApprovedBySuccessStatus = true
        sendLog(
            "TWINT SUCCESS status observed; waiting for transaction data " +
                "(cmd=${getCommandName(command)} amount=$bundleAmount expected=$expectedAmount elapsed=${elapsedMs}ms)"
        )
        return true
    }

    private fun isCurrentTwintTransactionData(
        data: TransactionData?,
        startedAtMs: Long,
        requireDate: Boolean,
        expectedAmount: Double?,
    ): Boolean {
        val rrn = data?.rrn?.trim() ?: ""
        val authCode = data?.authCode?.trim() ?: ""
        val hasApprovalProof = rrn.isNotEmpty() || authCode.isNotEmpty()
        val amountMatches = transactionAmountMatches(data?.amount, expectedAmount)
        val repeatsLastApproved = (rrn.isNotEmpty() && rrn == lastApprovedRrn) ||
            (rrn.isEmpty() && authCode.isNotEmpty() && authCode == lastApprovedAuthCode)

        if (requireDate && repeatsLastApproved) {
            sendLog("TWINT validation: last transaction data repeated rrn=$rrn - treating as stale")
            return false
        }

        val txDate = data?.transactionDateLocal
        if (txDate == null) {
            if (requireDate) {
                if (hasApprovalProof && amountMatches) {
                    sendLog("TWINT validation: transaction date missing but rrn/auth + amount match - accepting")
                    return true
                }
                sendLog("TWINT validation: transaction date missing after getLastTransactionData() - not trusting as approval")
                return false
            }
            return true
        }

        val minAcceptedMs = startedAtMs - 5000L
        if (txDate.time < minAcceptedMs) {
            if (requireDate && hasApprovalProof && amountMatches) {
                sendLog(
                    "TWINT validation: stale txDate=$txDate but rrn/auth + amount match " +
                        "and transaction is new - accepting"
                )
                return true
            }
            sendLog(
                "TWINT validation: stale transaction data txDate=$txDate " +
                    "startedAt=${java.util.Date(startedAtMs)} - treating as cancelled"
            )
            return false
        }
        return true
    }

    private fun handleTransactionComplete(data: TransactionData?) {
        val opAtCallback = pendingOp
        val wasTwintLastTxQuery = opAtCallback == "twint" && twintQueriedLastTx
        val startedAtMs = paymentStartedAtMs
        val expectedTwintAmount = pendingRetry
            ?.takeIf { it.op == "twint" && it.result == pendingResult }
            ?.amount
        sendLog("--- Transaction Complete! (lastFinancialStatus=$lastFinancialStatus failureStatus=$lastFinancialFailureStatus op=$opAtCallback queriedLastTx=$wasTwintLastTxQuery)")

        if (pendingResult == null || opAtCallback.isEmpty()) {
            sendLog("Transaction Complete ignored: no pending payment (late SDK callback)")
            return
        }

        cancelPaymentTimeout()
        isPaymentInProgress = false

        val terminalStatus = lastFinancialStatus
        val failureStatus = if (lastFinancialFailureStatus != -1) {
            lastFinancialFailureStatus
        } else {
            terminalStatus
        }
        val staleTwintResult = opAtCallback == "twint" &&
            !isCurrentTwintTransactionData(
                data = data,
                startedAtMs = startedAtMs,
                requireDate = wasTwintLastTxQuery,
                expectedAmount = expectedTwintAmount,
            )

        if (staleTwintResult) {
            val approval = data?.approval ?: ""
            val rawDesc = "TWINT stale data (SDK getLastTransactionData returned old transaction). " +
                "lastFinancialStatus=$terminalStatus (${getStatusName(terminalStatus)}), " +
                "lastFailureStatus=$failureStatus, " +
                "data.approval=\"$approval\"${if (data == null) "" else ", data.amount=\"${data.amount}\""}"
            sendLog("⚠️ TWINT rejected as stale: $rawDesc")
            pendingResult?.error(
                "TWINT_STALE_DATA",
                rawDesc,
                mapOf(
                    "lastFinancialStatus" to terminalStatus,
                    "lastFinancialStatusName" to getStatusName(terminalStatus),
                    "approval" to approval,
                    "amount" to (data?.amount ?: ""),
                    "rrn" to (data?.rrn ?: ""),
                    "authCode" to (data?.authCode ?: ""),
                ),
            )
            pendingResult = null; pendingOp = ""
            pendingRetry = null
            twintApprovedBySuccessStatus = false
            lastFinancialStatus = -1
            lastFinancialFailureStatus = -1
            return
        }

        val hasCardData = data != null && !(data.rrn.isNullOrEmpty() && data.authCode.isNullOrEmpty())
        val approval = data?.approval?.trim()
        val hasApprovalCode = approval != null && (
            approval == "00" ||
            approval == "0" ||
            approval.equals("approved", ignoreCase = true)
        )
        val declinedReason = data?.declinedReason1?.trim() ?: data?.declineReason2?.trim()
        val hasExplicitDeclineReason = !declinedReason.isNullOrEmpty()
        val twintSuccessHint = opAtCallback == "twint" && twintApprovedBySuccessStatus
        val hasRealData = hasCardData || hasApprovalCode || twintSuccessHint
        val failureOrDefinite = failureStatus in terminalFailureStatuses()

        if (failureOrDefinite && opAtCallback == "twint") {
            sendLog("⚠️ TWINT completion ignored: terminal failure state seen before completion")
            pendingResult?.error(
                "TWINT_FAILURE_STATE",
                "TWINT completion came while terminal failure state was active",
                mapOf(
                    "status" to failureStatus,
                    "statusName" to getStatusName(failureStatus),
                    "approval" to (approval ?: ""),
                    "declinedReason" to (declinedReason ?: ""),
                ),
            )
            pendingResult = null; pendingOp = ""
            pendingRetry = null
            twintApprovedBySuccessStatus = false
            lastFinancialStatus = -1
            lastFinancialFailureStatus = -1
            return
        }

        if (hasExplicitDeclineReason && opAtCallback == "twint") {
            sendLog("⚠️ TWINT completion contains decline reason: $declinedReason")
            pendingResult?.error(
                "TWINT_DECLINED",
                declinedReason ?: "Transaction declined",
                mapOf(
                    "status" to failureStatus,
                    "statusName" to getStatusName(failureStatus),
                    "approval" to (approval ?: ""),
                    "declinedReason" to (declinedReason ?: ""),
                    "amount" to (data?.amount ?: ""),
                    "rrn" to (data?.rrn ?: ""),
                    "authCode" to (data?.authCode ?: ""),
                ),
            )
            pendingResult = null; pendingOp = ""
            pendingRetry = null
            twintApprovedBySuccessStatus = false
            lastFinancialStatus = -1
            lastFinancialFailureStatus = -1
            return
        }

        if (hasRealData) {
            val resolvedAmount = data?.amount
                ?: expectedTwintAmount?.let { String.format(java.util.Locale.US, "%.2f", it) }
                ?: "0"
            sendLog("  Amount: $resolvedAmount")
            sendLog("  AuthCode: ${data?.authCode ?: "(twint:none)"}")
            sendLog("  RRN: ${data?.rrn ?: "(twint:none)"}")
            sendLog("  PAN: ${data?.panMasked ?: "(twint:none)"}")
            sendLog("  Card: ${data?.aidName ?: "(twint)"}")
            data?.let { rememberApprovedTransaction(it) }

            val effectiveRrn = data?.rrn ?: ""
            val effectiveAuth = data?.authCode ?: ""
            val effectiveTxId = if (effectiveRrn.isNotEmpty()) effectiveRrn
                else if (effectiveAuth.isNotEmpty()) effectiveAuth
                else "twint-${System.currentTimeMillis()}"

            pendingResult?.success(hashMapOf(
                "success" to true,
                "status" to "approved",
                "amount" to resolvedAmount,
                "authCode" to effectiveAuth,
                "rrn" to effectiveRrn,
                "transactionId" to effectiveTxId,
                "maskedPan" to (data?.panMasked ?: ""),
                "cardType" to (data?.aidName ?: if (twintSuccessHint) "TWINT" else ""),
                "terminalId" to (data?.terminalID ?: ""),
                "merchantId" to (data?.merchantID ?: ""),
                "stan" to (data?.stan ?: ""),
                "twintApprovedBySuccessStatus" to twintSuccessHint,
            ))
        } else if (failureOrDefinite) {
            // KART iptal/hata: handlePosInfo USER_CANCEL veya benzer kesin
            // hata statusunu yakalamis (lastFinancialFailureStatus set), simdi
            // onTransactionComplete(null) ile geliyoruz. NO_DATA dondurursek
            // cash software "failed" sanir, "cancelled" goremez. Bu yuzden
            // failure status'una gore dogru error code'u dondurelim.
            val statusName = getStatusName(failureStatus)
            val errCode = when (failureStatus) {
                POSHandler.POS_STATUS_USER_CANCEL -> "CANCELLED"
                POSHandler.POS_STATUS_INTERNAL_ERROR -> "INTERNAL_ERROR"
                POSHandler.POS_STATUS_TERMINAL_BUSY -> "BUSY"
                POSHandler.POS_STATUS_WRONG_AMOUNT -> "WRONG_AMOUNT"
                POSHandler.POS_STATUS_COM_ERROR -> "PAYMENT_FAILED"
                POSHandler.POS_STATUS_NO_CARD_FOUND -> "NO_CARD"
                POSHandler.POS_STATUS_NOT_SUPPORTED_CARD -> "CARD_NOT_SUPPORTED"
                POSHandler.POS_STATUS_CARD_CHIP_ERROR -> "CARD_CHIP_ERROR"
                POSHandler.POS_STATUS_INVALID_PIN -> "INVALID_PIN"
                POSHandler.POS_STATUS_MAX_PIN_COUNT_EXCEEDED -> "PIN_LOCKED"
                POSHandler.POS_STATUS_TRANSACTION_NOT_FOUND -> "TX_NOT_FOUND"
                else -> "PAYMENT_FAILED"
            }
            val message = when (failureStatus) {
                POSHandler.POS_STATUS_USER_CANCEL -> "User cancelled"
                else -> "Transaction failed: $statusName"
            }
            sendLog(
                "Transaction Complete after failure status seen: " +
                    "$statusName -> returning errCode=$errCode",
            )
            pendingResult?.error(
                errCode,
                message,
                mapOf(
                    "status" to failureStatus,
                    "statusName" to statusName,
                    "lastFinancialStatus" to failureStatus,
                    "lastFailureStatus" to failureStatus,
                    "approval" to (approval ?: ""),
                ),
            )
        } else {
            sendLog("Transaction Complete with NO approval proof (rrn/authCode/approval empty and no TWINT success hint) â€” treating as NOT successful")
            pendingResult?.error(
                "NO_DATA",
                "Transaction complete but no approval data returned",
                mapOf(
                    "status" to terminalStatus,
                    "statusName" to getStatusName(terminalStatus),
                    "lastFinancialStatus" to failureStatus,
                    "lastFailureStatus" to failureStatus,
                    "approval" to (approval ?: ""),
                ),
            )
        }
        pendingResult = null; pendingOp = ""
        pendingRetry = null
        twintApprovedBySuccessStatus = false
        lastFinancialStatus = -1
        lastFinancialFailureStatus = -1
    }
    /**
     * TCP socket'e keepalive + linger ayarla.
     * Cihaz kapanirsa/crash olursa TCP stack RST gonderir.
     */
    private fun enableSocketKeepalive() {
        try {
            val listenClass = Class.forName("com.mypos.slavesdk.ListenTCPIPConnection")
            val getInstance = listenClass.getMethod("getInstance")
            val instance = getInstance.invoke(null)
            val socketField = listenClass.getDeclaredField("mSocket")
            socketField.isAccessible = true
            val socket = socketField.get(instance) as? java.net.Socket

            if (socket != null && socket.isConnected && !socket.isClosed) {
                socket.keepAlive = true
                MyPosTcpConnectionCleaner.rememberActiveSocketEndpoint(
                    currentContext(),
                    "onConnected socket keepalive",
                )
                // NOT: setSoLinger(true, 0) KALDIRILDI â€” close() sirasinda RST gonderiyordu,
                // bu da aktif command sirasinda terminal tarafini dusurebiliyordu.
                sendLog("Socket keepalive=ON")
            }
        } catch (e: Exception) {
            sendLog("enableSocketKeepalive: ${e.message}")
        }
    }

    /**
     * SDK internal busy flag temizle (reflection).
     * SDK bug: TCP/IP modunda timeout'ta mTransactionInProgress temizlenmiyor.
     */
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

    /**
     * NetworkListener kaydet â€” baglanti kurulduktan sonra.
     */
    private fun registerNetworkListener() {
        currentContext()?.let { ctx ->
            try {
                posHandler?.setNetworkListener(ctx, object : NetworkListener {
                    override fun onAvailable() {
                        mainHandler.post {
                            sendLog("Network AVAILABLE")
                            if (connectionState == ConnectionState.DISCONNECTED &&
                                isConfigured &&
                                autoReconnectEnabled &&
                                !MyPosTcpConnectionCleaner.isReconnectBlocked()) {
                                scheduleReconnect()
                            }
                        }
                    }
                    override fun onLost() {
                        mainHandler.post {
                            sendLog("Network LOST")
                            if (connectionState == ConnectionState.CONNECTED) {
                                if (shouldUseTcpReconnectState()) {
                                    updateConnectionState(ConnectionState.RECONNECTING, "Network lost")
                                } else {
                                    updateConnectionState(ConnectionState.DISCONNECTED, "Network lost")
                                }
                            }
                        }
                    }
                })
                sendLog("NetworkListener registered")
            } catch (e: Exception) {
                sendLog("NetworkListener error: ${e.message}")
            }
        }
    }

    // ======================== METHOD CHANNEL ROUTER ========================

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configure" -> handleConfigure(call, result)
            "connect" -> handleConnect(result)
            "testConnection" -> handleTestConnection(result)
            "processPayment" -> handlePayment(call, result)
            "twintPurchase" -> handleTwint(call, result)
            "twintPurchaseViaActivity" -> {
                val amt = call.argument<Double>("amount") ?: 0.0
                if (amt <= 0) {
                    result.error("INVALID_AMOUNT", "Amount must be > 0", null); return
                }
                ensureConnectionBeforePayment(
                    onReady = { launchTwintViaActivity(amt, result) },
                    onError = { result.error("NOT_CONNECTED", it, null) },
                )
            }
            "refund" -> handleRefund(call, result)
            "cancelPayment" -> handleCancel(result)
            "clearBatch" -> handleClearBatch(result)
            "isTerminalBusy" -> result.success(mapOf("busy" to (posHandler?.isTerminalBusy ?: false)))
            "isConnected" -> handleIsConnected(result)
            "disconnect" -> handleDisconnect(result)
            "checkRealConnection" -> handleCheckRealConnection(result)
            "pingTerminal" -> handlePingTerminal(result)
            "getConnectionState" -> handleGetConnectionState(result)
            "rebootTerminal" -> handleSimpleCommand(result) { posHandler?.rebootPOS() }
            "resetConnection" -> handleResetConnection(result)
            "sendTerminalLog" -> handleSimpleCommand(result) { posHandler?.sendLog() }
            "openTerminalSettings" -> handleSimpleCommand(result) { posHandler?.openSettings() }
            "reprintReceipt" -> handleSimpleCommand(result) { posHandler?.reprintReceipt() }
            "getLastTransaction" -> handleSimpleCommand(result) { posHandler?.getLastTransactionData() }
            "activateTerminal" -> handleSimpleCommand(result) { posHandler?.activate() }
            "deactivateTerminal" -> handleSimpleCommand(result) { posHandler?.deactivate() }
            "updateTerminal" -> handleSimpleCommand(result) { posHandler?.update() }
            "getTerminalInfo" -> handleGetTerminalInfo(result)
            "setMyPosUsbEnabled" -> {
                myPosUsbEnabled = call.argument<Boolean>("enabled") ?: false
                sendLog("MyPOS USB enabled: $myPosUsbEnabled")
                result.success(mapOf("success" to true))
            }
            "getUsbDevices" -> {
                if (myPosUsbEnabled) handleGetUsbDevices(result)
                else result.success(mapOf("success" to true, "devices" to emptyList<Map<String, Any>>()))
            }
            "requestUsbPermission" -> result.success(mapOf("success" to true, "skipped" to true))
            "hasUsbPermission" -> result.success(mapOf("hasPermission" to true))
            else -> result.notImplemented()
        }
    }

    // ======================== CONFIGURE ========================

    private fun handleConfigure(call: MethodCall, result: MethodChannel.Result) {
        val type = call.argument<String>("type") ?: "tcp"
        val newIp = call.argument<String>("ip") ?: "192.168.1.131"
        val newPort = call.argument<Int>("port") ?: 60180
        val autoConnect = call.argument<Boolean>("autoConnect") ?: true
        val langCode = call.argument<String>("language")
        terminalLanguage = getLanguageFromCode(langCode)

        sendLog("Configure: type=$type, ip=$newIp, port=$newPort, lang=$langCode, autoConnect=$autoConnect")

        // SDK stale state temizle
        forceCleanSdkState()

        try {
            when (type.lowercase()) {
                "usb" -> configureUsb(call, result)
                "tcp", "tcpip" -> configureTcp(newIp, newPort, result, autoConnect)
                "bluetooth", "bt" -> configureBluetooth(result)
                else -> result.error("INVALID_TYPE", "Invalid type: $type", null)
            }
        } catch (e: Exception) {
            sendLog("Configure error: ${e.message}")
            isConfigured = false
            updateConnectionState(ConnectionState.DISCONNECTED, "Config error")
            result.error("CONFIG_ERROR", e.message, null)
        }
    }

    private fun configureUsb(call: MethodCall, result: MethodChannel.Result) {
        myPosUsbEnabled = true
        currentConnectionType = ConnectionType.USB
        stopWatchdog()  // USB'de watchdog gereksiz â€” fiziksel baglanti

        POSHandler.setConnectionType(ConnectionType.USB)
        POSHandler.setCurrency(Currency.CHF)
        POSHandler.setLanguage(terminalLanguage)
        posHandler = POSHandler.getInstance()
        initPosHandler()  // Sadece 1 kere calisir

        isConfigured = true
        reconnectAttempts = 0
        updateConnectionState(ConnectionState.CONNECTING, "USB configure")

        activity?.let { ctx ->
            // connectDevice(ctx, true) â†’ USB_DEVICE_ATTACHED/DETACHED receiver kaydeder
            // Kablo cikip takildiginda SDK otomatik reconnect yapar
            posHandler?.connectDevice(ctx, true)
            sendLog("USB connect request sent (with attach/detach listener)")
        }

        result.success(mapOf("success" to true, "type" to "usb"))
    }

    private fun configureTcp(
        newIp: String,
        newPort: Int,
        result: MethodChannel.Result,
        autoConnect: Boolean,
    ) {
        // IP degisiyorsa eski baglantiya temiz cikis
        if (isConfigured && currentConnectionType == ConnectionType.TCP_IP && tcpIp != newIp) {
            sendLog("IP changing: $tcpIp -> $newIp â€” closing old connection")
            stopWatchdog()
            cancelPendingReconnect()
            isPaymentInProgress = false
            pendingResult = null; pendingOp = ""
            try { posHandler?.resetTcpConnection() } catch (_: Exception) {}
        }

        // Zaten ayni IP/Port ile CONNECTED ise verify et
        if (isConfigured && currentConnectionType == ConnectionType.TCP_IP
            && tcpIp == newIp && tcpPort == newPort
            && connectionState == ConnectionState.CONNECTED && autoConnect) {
            sendLog("Already connected to $tcpIp:$tcpPort")
            result.success(mapOf("success" to true, "already_connected" to true))
            return
        }

        tcpIp = newIp
        tcpPort = newPort
        currentConnectionType = ConnectionType.TCP_IP

        // Eski TCP socket'i temizle
        try { posHandler?.resetTcpConnection() } catch (_: Exception) {}

        POSHandler.setConnectionType(ConnectionType.TCP_IP)
        POSHandler.setTcpIpConnectivity(tcpIp, tcpPort)
        POSHandler.setCurrency(Currency.CHF)
        POSHandler.setLanguage(terminalLanguage)
        posHandler = POSHandler.getInstance()
        initPosHandler()  // Sadece 1 kere calisir

        // IP'yi SharedPreferences'a kaydet
        try {
            (activity ?: appContext)?.getSharedPreferences("mypos_config", Context.MODE_PRIVATE)
                ?.edit()
                ?.putString("terminal_ip", tcpIp)
                ?.putInt("terminal_port", tcpPort)
                ?.apply()
        } catch (_: Exception) {}

        isConfigured = true
        reconnectAttempts = 0
        val shouldAutoConnect = autoConnect && !MyPosTcpConnectionCleaner.isReconnectBlocked()
        autoReconnectEnabled = shouldAutoConnect
        updateConnectionState(
            if (shouldAutoConnect) ConnectionState.CONNECTING else ConnectionState.DISCONNECTED,
            when {
                shouldAutoConnect -> "TCP configure"
                autoConnect -> "TCP configured; auto-connect blocked during shutdown"
                else -> "TCP configured on demand"
            },
        )

        if (shouldAutoConnect) {
            (activity ?: appContext)?.let { ctx ->
                connectTcpWithStaleBreaker(ctx, "configureTcp")
            }
        } else if (autoConnect) {
            sendLog("TCP auto-connect skipped: device shutdown/reconnect pause active")
        } else {
            sendLog("TCP configured without persistent connection -> $tcpIp:$tcpPort")
        }

        registerNetworkListener()
        result.success(mapOf("success" to true, "type" to "tcp", "autoConnect" to autoConnect))
    }

    private fun configureBluetooth(result: MethodChannel.Result) {
        currentConnectionType = ConnectionType.BLUETOOTH
        stopWatchdog()

        POSHandler.setConnectionType(ConnectionType.BLUETOOTH)
        POSHandler.setCurrency(Currency.CHF)
        POSHandler.setLanguage(terminalLanguage)
        posHandler = POSHandler.getInstance()
        initPosHandler()

        isConfigured = true
        reconnectAttempts = 0
        updateConnectionState(ConnectionState.CONNECTING, "BT configure")

        activity?.let { ctx ->
            posHandler?.connectDevice(ctx)
            sendLog("Bluetooth connect request sent")
        }

        result.success(mapOf("success" to true, "type" to "bluetooth"))
    }

    // ======================== CONNECTION HANDLERS ========================

    private fun handleConnect(result: MethodChannel.Result) {
        if (MyPosTcpConnectionCleaner.isReconnectBlocked()) {
            sendLog("handleConnect blocked: device shutdown/reconnect pause active")
            result.success(mapOf(
                "success" to false,
                "state" to connectionState.name,
                "reason" to "Device shutdown/reconnect pause active"
            ))
            return
        }
        if (posHandler == null) {
            result.error("NOT_CONFIGURED", "Call configure first", null)
            return
        }
        if (connectionState == ConnectionState.CONNECTED) {
            result.success(mapOf("success" to true, "state" to "CONNECTED"))
            return
        }

        // CRITICAL fix: Devam eden odeme varsa Connect butonu engellenir.
        // Aksi halde MainActivity.closeMyPosTcpSocket() aktif transaction
        // socket'ini keser, kart cekildi ama kayit yok riski olur.
        if (isPaymentInProgress) {
            sendLog("handleConnect: REJECTED â€” payment in progress (would abort transaction)")
            result.success(mapOf(
                "success" to false,
                "state" to connectionState.name,
                "reason" to "Payment in progress â€” wait for it to finish"
            ))
            return
        }

        currentContext()?.let { ctx ->
            updateConnectionState(ConnectionState.CONNECTING, "Manual connect")

            if (currentConnectionType == ConnectionType.TCP_IP) {
                connectTcpWithStaleBreaker(ctx, "manual connect")
            } else if (currentConnectionType == ConnectionType.USB) {
                posHandler?.connectDevice(ctx, true)
            } else {
                posHandler?.connectDevice(ctx)
            }
            sendLog("Connect request sent")

            // 15s timeout
            mainHandler.postDelayed({
                if (connectionState != ConnectionState.CONNECTED) {
                    result.success(mapOf("success" to false, "state" to connectionState.name, "reason" to "Timeout"))
                } else {
                    result.success(mapOf("success" to true, "state" to "CONNECTED"))
                }
            }, 15000)
        } ?: result.error("NO_CONTEXT", "Application context not available", null)
    }

    private fun connectTcpWithStaleBreaker(ctx: Context, reason: String) {
        if (MyPosTcpConnectionCleaner.isReconnectBlocked()) {
            sendLog("TCP connect blocked: device shutdown/reconnect pause active ($reason)")
            return
        }
        autoReconnectEnabled = true
        MyPosTcpConnectionCleaner.close("before MyPOS TCP connect: $reason", context = ctx)
        MyPosTcpConnectionCleaner.breakStaleSigmaSessionFromPrefs(
            ctx,
            reason = "before SDK connect: $reason",
            attempts = 2,
            initialDelayMs = 150L,
            intervalMs = 450L,
        )
        POSHandler.setTcpIpConnectivity(tcpIp, tcpPort)
        updateConnectionState(ConnectionState.CONNECTING, "TCP connect: $reason")
        mainHandler.postDelayed({
            if (MyPosTcpConnectionCleaner.isReconnectBlocked()) {
                sendLog("Delayed TCP connect cancelled: device shutdown/reconnect pause active ($reason)")
                updateConnectionState(ConnectionState.DISCONNECTED, "Delayed connect cancelled during shutdown")
                return@postDelayed
            }
            try {
                posHandler?.connectDevice(ctx)
                sendLog("TCP connect request sent -> $tcpIp:$tcpPort ($reason)")
            } catch (e: Exception) {
                sendLog("TCP connect error ($reason): ${e.message}")
            }
        }, CONNECT_DEBOUNCE_MS)
    }

    private fun handleTestConnection(result: MethodChannel.Result) {
        val sdkAlive = syncConnectionStateFromSdk("testConnection SDK sync")
        result.success(mapOf(
            "success" to sdkAlive,
            "connected" to sdkAlive,
            "state" to connectionState.name,
            "sdkSocketAlive" to sdkAlive
        ))
    }

    private fun handleIsConnected(result: MethodChannel.Result) {
        // SDK 2.1.9: isConnected() pure state check, serbestce cagirilabilir
        val sdkAlive = syncConnectionStateFromSdk("isConnected SDK sync")
        result.success(mapOf(
            "connected" to sdkAlive,
            "state" to connectionState.name,
            "sdkSocketAlive" to sdkAlive
        ))
    }

    private fun handleGetConnectionState(result: MethodChannel.Result) {
        val sdkAlive = syncConnectionStateFromSdk("getConnectionState SDK sync")
        result.success(mapOf(
            "state" to connectionState.name,
            "connected" to sdkAlive,
            "busy" to (posHandler?.isTerminalBusy ?: false),
            "sdkSocketAlive" to sdkAlive,
            "reconnectAttempts" to reconnectAttempts,
            "isReconnecting" to isReconnecting,
            "autoReconnectEnabled" to autoReconnectEnabled
        ))
    }

    private fun handleDisconnect(result: MethodChannel.Result) {
        sendLog("Disconnecting...")
        isManualDisconnectInProgress = true
        mainHandler.postDelayed({
            isManualDisconnectInProgress = false
        }, 6_000L)
        clearPendingConnectionState()
        resetTransientDisconnectWindow()

        // CRITICAL fix: Devam eden odeme varsa once iptal et, sonra disconnect.
        // Aksi halde transaction socket'i sessizce kesilir.
        if (isPaymentInProgress) {
            sendLog("handleDisconnect: payment in progress â€” cancelling transaction first")
            try {
                cancelPaymentTimeout()
                pendingResult?.error("DISCONNECTED", "Connection closed by user during payment", null)
                pendingResult = null
                pendingOp = ""
                pendingRetry = null
                isPaymentInProgress = false
                try { posHandler?.cancelTransaction() } catch (_: Exception) {}
            } catch (e: Exception) {
                sendLog("Cancel before disconnect error: ${e.message}")
            }
        }

        stopWatchdog()
        autoReconnectEnabled = false
        cancelPendingReconnect()

        try {
            if (currentConnectionType == ConnectionType.TCP_IP) {
                // resetData() + raw socket.close() â€” terminal "Waiting for
                // Connection"a duser, half-open socket kalmaz.
                MyPosTcpConnectionCleaner.close("manual disconnect", context = currentContext())
            }
        } catch (e: Exception) {
            sendLog("Disconnect cleanup error: ${e.message}")
        }

        updateConnectionState(ConnectionState.DISCONNECTED, "Manual disconnect")
        result.success(mapOf("success" to true))
    }

    private fun handleCheckRealConnection(result: MethodChannel.Result) {
        val sdkAlive = syncConnectionStateFromSdk("checkRealConnection SDK sync")
        if (sdkAlive) {
            result.success(mapOf("connected" to true, "sdkSocketAlive" to true))
            return
        }

        // Terminal busy ise baglanti var demektir
        if (posHandler?.isTerminalBusy == true) {
            result.success(mapOf("connected" to true, "busy" to true))
            return
        }

        // ICMP ping ile kontrol (SDK'ya dokunmaz)
        Thread {
            val reachable = icmpPing(tcpIp, 3000)
            mainHandler.post {
                if (reachable && connectionState == ConnectionState.CONNECTED) {
                    result.success(mapOf("connected" to true, "pingSuccess" to true))
                } else if (reachable) {
                    // Agda var ama SDK bagli degil â€” reconnect gerekebilir
                    result.success(mapOf("connected" to false, "reachable" to true, "reason" to "SDK not connected"))
                } else {
                    result.success(mapOf("connected" to false, "reachable" to false, "reason" to "ICMP unreachable"))
                }
            }
        }.start()
    }

    private fun handlePingTerminal(result: MethodChannel.Result) {
        if (posHandler == null) {
            posHandler = try { POSHandler.getInstance() } catch (_: Exception) { null }
        }
        if (posHandler == null) {
            result.success(mapOf("connected" to false, "reason" to "POSHandler unavailable"))
            return
        }
        if (posHandler?.isTerminalBusy == true) {
            val sdkAlive = syncConnectionStateFromSdk("pingTerminal busy SDK sync")
            result.success(mapOf("connected" to sdkAlive, "busy" to true))
            return
        }

        // SDK PING â€” dikkat: mTransactionInProgress set eder
        pingResult = result
        sendLog("Sending SDK PING...")
        posHandler?.checkConnection()

        mainHandler.postDelayed({
            if (pingResult != null) {
                sendLog("PING timeout")
                pingResult?.success(mapOf("connected" to false, "pingSuccess" to false, "reason" to "Timeout"))
                pingResult = null
            }
        }, 5000)
    }

    private fun handleResetConnection(result: MethodChannel.Result) {
        sendLog("Resetting connection...")
        cancelPendingReconnect()

        try {
            if (currentConnectionType == ConnectionType.TCP_IP) {
                posHandler?.resetTcpConnection()
                POSHandler.setTcpIpConnectivity(tcpIp, tcpPort)
            } else if (currentConnectionType == ConnectionType.BLUETOOTH) {
                posHandler?.resetBluetoothConnection()
            }
            // USB icin SDK reset gereksiz â€” fiziksel baglanti
        } catch (e: Exception) {
            sendLog("Reset error: ${e.message}")
        }

        // 2s sonra reconnect
        mainHandler.postDelayed({
            if (MyPosTcpConnectionCleaner.isReconnectBlocked()) {
                sendLog("Manual reset reconnect cancelled: device shutdown/reconnect pause active")
                updateConnectionState(ConnectionState.DISCONNECTED, "Manual reset reconnect cancelled during shutdown")
                return@postDelayed
            }
            currentContext()?.let { ctx ->
                if (currentConnectionType == ConnectionType.USB) {
                    posHandler?.connectDevice(ctx, true)
                } else if (currentConnectionType == ConnectionType.TCP_IP) {
                    connectTcpWithStaleBreaker(ctx, "manual reset")
                } else {
                    posHandler?.connectDevice(ctx)
                }
                sendLog("Reconnecting after reset...")
            }
        }, HANDLE_RESET_RECONNECT_MS)

        result.success(mapOf("success" to true))
    }

    // ======================== PAYMENT HANDLERS ========================

    /**
     * Odeme oncesi baglanti kontrolu.
     * SDK 2.1.9: isConnected() pure state check, serbestce kullanabiliriz.
     * State CONNECTED + socket alive ise direkt devam.
     * Socket olu ama state CONNECTED (timing issue) -> kisa sure bekle SDK reconnect yapabilir.
     */
    private fun ensureConnectionBeforePayment(
        onReady: () -> Unit,
        onError: (String) -> Unit,
    ) {
        sendLog("Pre-payment check: state=$connectionState, type=$currentConnectionType, inProgress=$isPaymentInProgress")
        if (MyPosTcpConnectionCleaner.isReconnectBlocked()) {
            onError("Device is shutting down; MyPOS reconnect is blocked")
            return
        }

        if (connectionState == ConnectionState.CONNECTING ||
            connectionState == ConnectionState.RECONNECTING
        ) {
            sendLog("Pre-payment: already connecting/reconnecting, waiting for connect result")
            val waitTime = if (currentConnectionType == ConnectionType.USB) {
                PRE_PAYMENT_CONN_WAIT_USB_MS
            } else {
                PRE_PAYMENT_CONN_WAIT_TCP_MS
            }
            val pollMs = if (currentConnectionType == ConnectionType.USB) {
                PRE_PAYMENT_CONN_WAIT_USB_POLL_MS
            } else {
                PRE_PAYMENT_CONN_WAIT_TCP_POLL_MS
            }
            waitForConnectionState(
                timeoutMs = waitTime,
                pollMs = pollMs,
                onReady = {
                    if (connectionState != ConnectionState.CONNECTED) {
                        onError(
                            if (currentConnectionType == ConnectionType.USB) {
                                "USB terminal not connected. Check: 1) Terminal powered on 2) USB cable connected 3) POSLink Manager running"
                            } else {
                                "Terminal not connected ($tcpIp:$tcpPort). Check POSLink Manager is running on terminal."
                            }
                        )
                        return@waitForConnectionState
                    }

                    if (currentConnectionType == ConnectionType.TCP_IP && !verifyTcpSocketAlive()) {
                        sendLog("Connected without live socket â€” waiting for SDK reconnect before payment")
                        waitForSdkReconnectThenPay(onReady, onError)
                        return@waitForConnectionState
                    }
                    sendLog("Existing connect attempt completed â€” proceeding with payment")
                    onReady()
                },
                onTimeout = {
                    onError(
                        if (currentConnectionType == ConnectionType.USB) {
                            "USB terminal not connected. Check: 1) Terminal powered on 2) USB cable connected 3) POSLink Manager running"
                        } else {
                            "Terminal not connected ($tcpIp:$tcpPort). Check POSLink Manager is running on terminal."
                        }
                    )
                },
                predicate = { connectionState == ConnectionState.CONNECTED }
            )
            return
        }

        // Stale isPaymentInProgress flag temizligi (bizim Kotlin tarafi)
        if (isPaymentInProgress && pendingResult == null) {
            sendLog("Stale isPaymentInProgress flag detected â€” resetting")
            isPaymentInProgress = false
        }

        // CONNECTED ise socket'i dogrula
        if (connectionState == ConnectionState.CONNECTED) {
            val busy = posHandler?.isTerminalBusy == true
            if (!busy && isPosReady) {
                sendLog("Pre-payment: connected and terminal ready, continuing immediately")
                onReady()
                return
            }
            if (currentConnectionType == ConnectionType.TCP_IP) {
                val socketAlive = verifyTcpSocketAlive()
                if (!socketAlive) {
                    sendLog("Pre-payment: Socket not alive, waiting for SDK auto-reconnect...")
                    waitForSdkReconnectThenPay(onReady, onError)
                    return
                }
            }

            // SDK 2.1.9 connect sonrasi CommandGetStatus gonderiyor â†’ mTransactionInProgress=true.
            // GetStatus response gelince dogal olarak temizleniyor.
            // En iyi duruma uygun olarak bekle; yine uzarsa kÄ±sa timeout ile devam et.
            waitForBusyFlagOrClear(onReady, timeoutMs = PRE_PAYMENT_CONNECTED_READY_MAX_MS)
            return
        }

        // CONNECTED degil â€” reconnect dene ve bekle
        sendLog("Not connected, attempting reconnect for payment...")

        val ctx = currentContext()
        if (ctx == null) {
            onError("Cannot connect â€” no application context")
            return
        }

        try {
            if (currentConnectionType == ConnectionType.TCP_IP) {
                connectTcpWithStaleBreaker(ctx, "pre-payment")
            } else if (currentConnectionType == ConnectionType.USB) {
                // USB: connectDevice(ctx, true) ile attach/detach receiver dahil
                posHandler?.connectDevice(ctx, true)
            } else {
                posHandler?.connectDevice(ctx)
            }
        } catch (e: Exception) {
            onError("Connection failed: ${e.message}")
            return
        }

        // Baglanti icin bekle â€” USB fiziksel, daha hizli; TCP network, daha yavas
        val waitTime = if (currentConnectionType == ConnectionType.USB) {
            PRE_PAYMENT_CONN_WAIT_USB_MS
        } else {
            PRE_PAYMENT_CONN_WAIT_TCP_MS
        }
        val pollMs = if (currentConnectionType == ConnectionType.USB) {
            PRE_PAYMENT_CONN_WAIT_USB_POLL_MS
        } else {
            PRE_PAYMENT_CONN_WAIT_TCP_POLL_MS
        }
        waitForConnectionState(
            timeoutMs = waitTime,
            pollMs = pollMs,
            onReady = {
                if (connectionState != ConnectionState.CONNECTED) {
                    onError(
                        if (currentConnectionType == ConnectionType.USB) {
                            "USB terminal not connected. Check: 1) Terminal powered on 2) USB cable connected 3) POSLink Manager running"
                        } else {
                            "Terminal not connected ($tcpIp:$tcpPort). Check POSLink Manager is running on terminal."
                        }
                    )
                    return@waitForConnectionState
                }

                if (currentConnectionType == ConnectionType.TCP_IP && !verifyTcpSocketAlive()) {
                    sendLog("Connected without live socket Ã¢â‚¬â€ waiting for SDK reconnect before payment")
                    waitForSdkReconnectThenPay(onReady, onError)
                    return@waitForConnectionState
                }
                sendLog("Reconnect successful Ã¢â‚¬â€ proceeding with payment")
                onReady()
            },
            onTimeout = {
                onError(
                    if (currentConnectionType == ConnectionType.USB) {
                        "USB terminal not connected. Check: 1) Terminal powered on 2) USB cable connected 3) POSLink Manager running"
                    } else {
                        "Terminal not connected ($tcpIp:$tcpPort). Check POSLink Manager is running on terminal."
                    }
                )
            },
            predicate = { connectionState == ConnectionState.CONNECTED }
        )
    }

    /**
     * SDK 2.1.9 davranisi:
     * - connectSocket sonrasi CommandGetStatus.sendCommand() cagriliyor (mTransactionInProgress=true)
     * - Terminal cevap verince CommandGetStatus.processResponse() fire oluyor
     * - processResponse basarili biterse: Utils.mTerminalReady=true + POSHandler.onPOSReady()
     * - Bu bizim setPOSReadyListener callback'imizi tetikler -> isPosReady=true
     *
     * ONEMLI: Eger POSReady gelmezse (terminal stuck/offline gibi), kisa timeout sonra
     * reflection ile mTransactionInProgress'i temizleyip devam ediyoruz (best effort).
     */
    private fun waitForBusyFlagOrClear(onReady: () -> Unit, timeoutMs: Long = PRE_PAYMENT_BUSY_MAX_WAIT_MS) {
        // POSReady ise terminal hazir demektir â€” direkt devam
        if (isPosReady && posHandler?.isTerminalBusy != true) {
            onReady()
            return
        }

        sendLog("Pre-payment: Waiting for POSReady (isPosReady=$isPosReady, busy=${posHandler?.isTerminalBusy})")
        val startTime = System.currentTimeMillis()
        var resolved = false

        lateinit var poller: Runnable
        poller = Runnable {
            if (resolved) return@Runnable
            val elapsed = System.currentTimeMillis() - startTime
            val ready = isPosReady
            val busy = posHandler?.isTerminalBusy == true

            if (ready && !busy) {
                sendLog("POSReady + !busy in ${elapsed}ms â€” proceed")
                resolved = true
                onReady()
            } else if (elapsed >= timeoutMs) {
                sendLog("POSReady timeout after ${timeoutMs}ms (ready=$ready, busy=$busy) â€” force clearing + best effort")
                resolved = true
                if (busy) forceCleanSdkState()
                onReady()
            } else {
                mainHandler.postDelayed(poller, PRE_PAYMENT_BUSY_POLL_MS)
            }
        }
        mainHandler.postDelayed(poller, PRE_PAYMENT_BUSY_POLL_MS)
    }

    /**
     * SDK 2.1.9: SDK zaten auto-reconnect yapiyor. Biz resetTcpConnection() cagirirsak
     * SDK'nin reconnect loop'unu oldurur (mRunning=false). Bu fonksiyon bunu yapmadan
     * SDK'ya zaman taniyor ve periyodik olarak isConnected() ile dogruluyor.
     *
     * Eger belli bir sure icinde SDK toparlanamazsa fallback reconnect devreye girer.
     */
    private fun waitForSdkReconnectThenPay(onReady: () -> Unit, onError: (String) -> Unit) {
        isPaymentInProgress = true; paymentStartedAtMs = System.currentTimeMillis(); lastFinancialStatus = -1; lastFinancialFailureStatus = -1  // Watchdog ve scheduleReconnect karismasin
        val startTime = System.currentTimeMillis()
        val maxWait = WAIT_SDK_RECONNECT_MAX_MS
        val pollInterval = WAIT_SDK_RECONNECT_POLL_MS

        lateinit var poller: Runnable
        poller = Runnable {
            val elapsed = System.currentTimeMillis() - startTime
            val socketAlive = try { posHandler?.isConnected == true } catch (_: Exception) { false }
            val stateOk = connectionState == ConnectionState.CONNECTED

            if (socketAlive && stateOk) {
                sendLog("waitForSdkReconnectThenPay: Socket recovered in ${elapsed}ms")
                onReady()
            } else if (socketAlive && !stateOk) {
                // Socket canli ama state geri alinmamis, state'i sync et
                reconnectAttempts = 0
                isReconnecting = false
                updateConnectionState(ConnectionState.CONNECTED, "Pre-payment socket check")
                onReady()
            } else if (elapsed >= maxWait) {
                sendLog("waitForSdkReconnectThenPay: Timeout after ${maxWait}ms â€” falling back to manual reconnect")
                reconnectAndPay(onReady, onError)
            } else {
                mainHandler.postDelayed(poller, pollInterval)
            }
        }
        mainHandler.postDelayed(poller, pollInterval)
    }

    /**
     * Fallback: SDK reconnect yetmedi, manuel reset + connect.
     * ONEMLI: resetTcpConnection() SDK'nin kendi reconnect loop'unu oldurur.
     * Bu fonksiyon sadece SDK kendisi toparlayamazsa cagrilmali.
     */
    private fun reconnectAndPay(onReady: () -> Unit, onError: (String) -> Unit) {
        val ctx = currentContext()
        if (ctx == null) { onError("No application context"); return }

        // CRITICAL fix: paralel recovery yarismasin
        if (isRecoveryInProgress) {
                sendLog("reconnectAndPay: recovery already in progress, queueing onReady wait")
            // Mevcut recovery bitince connection'i tekrar kontrol et
            mainHandler.postDelayed({
                if (connectionState == ConnectionState.CONNECTED) onReady()
                else onError("Recovery in progress, retry payment again")
            }, RECONNECT_AND_PAY_MAX_MS)
            return
        }
        isRecoveryInProgress = true

        // Diger reconnect'leri durdur â€” biz yonetiyoruz
        cancelPendingReconnect()
        isPaymentInProgress = true; paymentStartedAtMs = System.currentTimeMillis(); lastFinancialStatus = -1; lastFinancialFailureStatus = -1  // Watchdog ve scheduleReconnect karismasin

        forceCleanSdkState()
        try {
            connectTcpWithStaleBreaker(ctx, "payment recovery")
            sendLog("Reconnect for payment sent -> $tcpIp:$tcpPort")
        } catch (e: Exception) {
            isPaymentInProgress = false
            isRecoveryInProgress = false
            onError("Reconnect failed: ${e.message}")
            return
        }

        // 5 saniye bekle â€” onConnected gelmeli
        mainHandler.postDelayed({
            isRecoveryInProgress = false
            if (connectionState == ConnectionState.CONNECTED) {
                sendLog("Reconnect successful â€” proceeding with payment")
                // isPaymentInProgress zaten true, executePayment devam edecek
                onReady()
            } else {
                isPaymentInProgress = false
                onError("Terminal not connected after reconnect ($tcpIp:$tcpPort). Check POSLink Manager.")
            }
        }, RECONNECT_AND_PAY_MAX_MS)
    }

    /**
     * Terminal BUSY â€” SDK flag temizle + TCP reset + reconnect + odeme.
     * Senaryo: Eski stale baglanti terminal'de takilmis, BUSY veriyor.
     */
    private fun resetAndReconnectForPayment(onReady: () -> Unit, onError: (String) -> Unit) {
        val ctx = currentContext()
        if (ctx == null) { onError("No application context"); return }

        // CRITICAL fix: paralel recovery yarismasin
        if (isRecoveryInProgress) {
            sendLog("resetAndReconnectForPayment: recovery already in progress, queueing")
            mainHandler.postDelayed({
                if (connectionState == ConnectionState.CONNECTED) onReady()
                else onError("Recovery in progress, retry payment again")
            }, RESET_AND_PAY_WAIT_MS)
            return
        }
        isRecoveryInProgress = true

        // Diger reconnect'leri durdur
        cancelPendingReconnect()
        isPaymentInProgress = true; paymentStartedAtMs = System.currentTimeMillis(); lastFinancialStatus = -1; lastFinancialFailureStatus = -1

        sendLog("BUSY recovery: full TCP reset + reconnect...")
        forceCleanSdkState()
        try {
            MyPosTcpConnectionCleaner.close("busy recovery before reconnect", context = ctx)
        } catch (_: Exception) {}

        // 2 saniye sonra reconnect â€” terminal'in eski session'i temizlemesi icin
        mainHandler.postDelayed({
            try {
                connectTcpWithStaleBreaker(ctx, "busy recovery")
                sendLog("BUSY recovery: reconnect sent")
            } catch (e: Exception) {
                isPaymentInProgress = false
                isRecoveryInProgress = false
                onError("BUSY recovery failed: ${e.message}")
                return@postDelayed
            }

            // 5 saniye bekle
            mainHandler.postDelayed({
                forceCleanSdkState()  // Tekrar temizle
                isRecoveryInProgress = false
                if (connectionState == ConnectionState.CONNECTED) {
                    if (posHandler?.isTerminalBusy == true) {
                        isPaymentInProgress = false
                        onError("Terminal still busy after reset. Please restart POSLink Manager on terminal.")
                    } else {
                        sendLog("BUSY recovery successful â€” proceeding with payment")
                        onReady()
                    }
                } else {
                    isPaymentInProgress = false
                    onError("Terminal not connected after BUSY recovery. Check POSLink Manager.")
                }
            }, RESET_AND_PAY_WAIT_MS)
        }, RESET_AND_PAY_PRE_WAIT_MS)
    }

    /**
     * BUSY auto-retry: TERMINAL_BUSY status geldiginde 1 kez otomatik retry yap.
     *
     * Akis:
     * 1) BUSY status alindi
     * 2) pendingRetry kontrolu â€” varsa ve attempts < MAX_BUSY_RETRY:
     *    - forceCleanSdkState() ile SDK flag'i temizle
     *    - cancelPaymentTimeout() ile mevcut timeout'u iptal
     *    - 500ms bekle (terminal toparlansin)
     *    - Ayni operasyonu inner execute fonksiyonuyla tekrar cagir
     * 3) attempts >= MAX ise normal hata akisina dus
     *
     * Bu sayede gecici BUSY durumlarinda kullaniciya hata mesaji gitmez â€”
     * ikinci deneme genellikle basarili olur (SDK flag race + transient).
     */
    private fun maybeAutoRetryBusy(): Boolean {
        val retry = pendingRetry ?: return false
        if (retry.attempts >= MAX_BUSY_RETRY) return false
        if (pendingResult == null) {
            // pendingResult zaten temizlenmis â€” retry alakasiz, eski payment artigi
            pendingRetry = null
            return false
        }
        retry.attempts++
        sendLog("BUSY auto-retry ${retry.attempts}/$MAX_BUSY_RETRY scheduled in 500ms (op=${retry.op})")
        forceCleanSdkState()
        cancelPaymentTimeout()
        isPaymentInProgress = false
        // pendingResult/pendingOp temizlenmiyor â€” execute fonksiyonu yeniden set ediyor
        // ama pendingOp'u shu an temizleyelim ki ara callback'lerde yanlis match olmasin
        twintApprovedBySuccessStatus = false
        pendingOp = ""
        mainHandler.postDelayed({
            when (retry.op) {
                "purchase" -> executePayment(retry.amount, retry.currency, retry.result)
                "twint" -> executeTwintInner(retry.amount, retry.result)
                "refund" -> executeRefundInner(retry.amount, retry.currency, retry.result)
                else -> {
                    sendLog("Unknown retry op: ${retry.op}")
                    pendingRetry = null
                }
            }
        }, 500)
        return true
    }

    private fun handlePayment(call: MethodCall, result: MethodChannel.Result) {
        val amount = call.argument<Double>("amount") ?: 0.0
        val currency = call.argument<String>("currency") ?: "CHF"
        sendLog("Payment: $amount $currency")

        // BUSY otomatik retry icin orijinal istegi sakla
        pendingRetry = PendingRetry(op = "purchase", amount = amount, currency = currency, result = result)

        ensureConnectionBeforePayment(
            onReady = { executePayment(amount, currency, result) },
            onError = {
                pendingRetry = null
                result.error("NOT_CONNECTED", it, null)
            }
        )
    }

    private fun executePayment(amount: Double, currency: String, result: MethodChannel.Result) {
        try {
            isPaymentInProgress = true; paymentStartedAtMs = System.currentTimeMillis(); lastFinancialStatus = -1; lastFinancialFailureStatus = -1
            pendingOp = "purchase"
            pendingResult = result
            POSHandler.setCurrency(getCurrency(currency))
            val amountStr = String.format(java.util.Locale.US, "%.2f", amount)
            val currencyCode = getCurrencyNumericCode(currency)

            // Son safety temizleyici â€” SDK'nin isNewCommandPossible() check'i
            // mTransactionInProgress=true gorursa sessizce abort eder, TERMINAL_BUSY fire eder.
            // Bu guard o racyi kapatiyor.
            if (posHandler?.isTerminalBusy == true) {
                sendLog("executePayment: busy flag set before purchase â€” force clearing")
                forceCleanSdkState()
            }

            sendLog("purchase($amountStr, $currencyCode)")

            val params = PaymentParams.builder()
                .productAmount(amountStr)
                .currency(currencyCode)
                .fixedPinpad(true)
                .receiptConfiguration(POSHandler.RECEIPT_DO_NOT_PRINT)
                .build()
            posHandler?.purchase(params)
            schedulePaymentTimeout(result, "purchase")
        } catch (e: Exception) {
            sendLog("Payment error: ${e.message}")
            isPaymentInProgress = false
            pendingResult = null; pendingOp = ""
            result.error("PAYMENT_ERROR", e.message, null)
        }
    }

    /**
     * Safety net: SDK hic cevap dondurmezse timeout sonrasi hata firla.
     * TWINT icin kisa (90s), kart odeme icin uzun (180s). Cancel/success
     * cagri geldiginde cancelPaymentTimeout ile iptal edilir.
     *
     * Bu safety net olmadan: musteri TWINT QR'i taramazsa veya X'e basip SDK
     * hic callback atmazsa, POS ekrani sonsuza kadar "odeme bekleniyor" kalir.
     */
    private var paymentTimeoutRunnable: Runnable? = null
    private fun schedulePaymentTimeout(result: MethodChannel.Result, op: String) {
        cancelPaymentTimeout()
        // 75s timeout â€” eskiden 180s, kullanici 3 dk donmus gibi hissediyor.
        // Kart icin: kart tak/PIN gir/onay max 60-70s gerek; 75s yeterli.
        val timeoutMs = when (op) {
            "twintDirectActivityExact" -> 180_000L
            "twintPurchase" -> 75_000L
            else -> 75_000L
        }
        paymentTimeoutRunnable = Runnable {
            if (pendingResult == result) {
                isPaymentInProgress = false
                val isActivityExact = op == "twintDirectActivityExact"
                sendLog(
                    if (isActivityExact) {
                        "$op timeout after ${timeoutMs / 1000}s â€” OperationActivity did not return result"
                    } else {
                        "$op timeout after ${timeoutMs / 1000}s â€” no SDK callback received, cancelling transaction"
                    }
                )
                if (isActivityExact) {
                    sendLog(
                        "twintDirectActivityExact timeout means OperationActivity did not finish/result; " +
                            "not sending cancelTransaction so support can inspect terminal/activity state"
                    )
                } else {
                    // Terminali de aktif olarak iptal et (TWINT ekrani kapansin)
                    try {
                        posHandler?.cancelTransaction()
                    } catch (e: Exception) {
                        sendLog("cancelTransaction on timeout error: ${e.message}")
                    }
                }
                forceCleanSdkState()
                if (op.contains("Activity", ignoreCase = true) ||
                    pendingOp.contains("activity", ignoreCase = true)) {
                    restorePosHandlerListenersAfterOperationActivity("timeout op=$op")
                }
                val message = if (isActivityExact) {
                    "$op timeout â€” OperationActivity did not return onActivityResult"
                } else {
                    "$op timeout â€” no response from terminal"
                }
                pendingResult?.error("TIMEOUT", message, null)
                twintApprovedBySuccessStatus = false
                pendingResult = null; pendingOp = ""
            }
        }
        mainHandler.postDelayed(paymentTimeoutRunnable!!, timeoutMs)
    }

    private fun cancelPaymentTimeout() {
        paymentTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
        paymentTimeoutRunnable = null
        stopTwintBusyPoller()
    }

    // TWINT icin aktif polling â€” SDK TWINT sonunda callback atmiyor (ne iptal
    // ne basari). Biz isTerminalBusy'yi izleyip terminal idle olunca SDK'dan
    // getLastTransactionData() ile gercek sonucu soruyoruz.
    //
    // Akis:
    //   1) TWINT baslayinca poller 2s interval'le isTerminalBusy kontrol
    //   2) 3 kez arka arkaya busy=false â†’ transaction bitti
    //   3) getLastTransactionData() cagir â€” SDK asyncr onTransactionComplete
    //      fire edecek (bu defa gercek data ile)
    //   4) 5s icinde callback gelmezse cancel kabul et (fallback)
    //   5) Gelen data approval/declinedReason'a gore success/cancel karari
    private var twintBusyPollRunnable: Runnable? = null
    private var twintNotBusyStreak: Int = 0
    private var twintPollStartedAt: Long = 0L
    private var twintQueriedLastTx: Boolean = false
    private var twintQueryFallback: Runnable? = null

    private fun startTwintBusyPoller(result: MethodChannel.Result) {
        stopTwintBusyPoller()
        twintNotBusyStreak = 0
        twintQueriedLastTx = false
        twintPollStartedAt = System.currentTimeMillis()
        twintBusyPollRunnable = object : Runnable {
            override fun run() {
                if (pendingResult != result || pendingOp != "twint") {
                    sendLog("TWINT poller: pending changed, stopping")
                    return
                }
                val elapsed = System.currentTimeMillis() - twintPollStartedAt
                // Ilk 3s'de SDK'ya firsat ver (busy=true henuz set olmamis olabilir)
                if (elapsed < 3000) {
                    mainHandler.postDelayed(this, 2000)
                    return
                }
                val busy = try { posHandler?.isTerminalBusy == true } catch (_: Exception) { false }
                if (busy) {
                    twintNotBusyStreak = 0
                } else {
                    twintNotBusyStreak++
                    sendLog("TWINT poller: terminal not busy (streak=$twintNotBusyStreak)")
                    if (twintNotBusyStreak >= 3 && !twintQueriedLastTx) {
                        if (lastFinancialStatus == POSHandler.POS_STATUS_SUCCESS_PURCHASE ||
                            twintApprovedBySuccessStatus) {
                            sendLog("TWINT poller: success status seen but no transaction data yet")
                        }
                        twintQueriedLastTx = true
                        sendLog("ðŸ“ž TWINT poller: terminal idle ${twintNotBusyStreak * 2}s â€” querying getLastTransactionData()")
                        queryLastTransaction(result)
                        return  // Polling durur; onTransactionComplete cevabi bekle
                    }
                }
                mainHandler.postDelayed(this, 2000)
            }
        }
        mainHandler.postDelayed(twintBusyPollRunnable!!, 2000)
        sendLog("TWINT busy poller started (2s interval)")
    }

    /**
     * SDK'dan son islemin sonucunu sor. Bu asynchronous â€” SDK
     * onTransactionComplete (ya da onPOSInfoReceived) fire edecek.
     * handleTransactionComplete bu data'yi inceleyip success/decline
     * karari verir. 5s fallback: cevap gelmezse cancel say.
     */
    private fun queryLastTransaction(result: MethodChannel.Result) {
        try {
            // SDK internal busy flag'i temizle (yeni komut icin gerekli)
            forceCleanSdkState()
            posHandler?.getLastTransactionData()
        } catch (e: Exception) {
            sendLog("getLastTransactionData() error: ${e.message}")
        }

        // Fallback: 5s icinde onTransactionComplete fire etmezse cancel say
        twintQueryFallback = Runnable {
            if (pendingResult == result && pendingOp == "twint") {
                // RAW SDK state'i log + error data icine koy
                val lastStatus = lastFinancialStatus
                val lastStatusName = getStatusName(lastStatus)
                val isBusy = try { posHandler?.isTerminalBusy == true } catch (_: Exception) { false }
                val isConn = try { posHandler?.isConnected == true } catch (_: Exception) { false }
                val raw =
                    "getLastTransactionData() did NOT fire onTransactionComplete within 5s. " +
                        "lastFinancialStatus=$lastStatus ($lastStatusName), " +
                        "isTerminalBusy=$isBusy, isConnected=$isConn â€” assuming cancelled"
                sendLog("ðŸ›‘ $raw")
                cancelPaymentTimeout()
                isPaymentInProgress = false
                pendingResult?.error(
                    "TWINT_NO_RESPONSE",
                    raw,
                    mapOf(
                        "lastFinancialStatus" to lastStatus,
                        "lastFinancialStatusName" to lastStatusName,
                        "isTerminalBusy" to isBusy,
                        "isConnected" to isConn,
                    ),
                )
                twintApprovedBySuccessStatus = false
                pendingResult = null; pendingOp = ""
            }
        }
        mainHandler.postDelayed(twintQueryFallback!!, 5000)
    }

    private fun stopTwintBusyPoller() {
        twintBusyPollRunnable?.let { mainHandler.removeCallbacks(it) }
        twintBusyPollRunnable = null
        twintQueryFallback?.let { mainHandler.removeCallbacks(it) }
        twintQueryFallback = null
        twintNotBusyStreak = 0
        twintQueriedLastTx = false
    }

    private fun handleTwint(call: MethodCall, result: MethodChannel.Result) {
        val amount = call.argument<Double>("amount") ?: 0.0
        sendLog("TWINT: $amount CHF")

        if (amount <= 0) {
            result.error("INVALID_AMOUNT", "Amount must be > 0", null)
            return
        }

        // BUSY otomatik retry icin orijinal istegi sakla
        pendingRetry = PendingRetry(op = "twint", amount = amount, currency = "CHF", result = result)

        ensureConnectionBeforePayment(
            onReady = { executeTwintInner(amount, result) },
            onError = {
                pendingRetry = null
                result.error("NOT_CONNECTED", it, null)
            }
        )
    }

    private fun executeTwintInner(amount: Double, result: MethodChannel.Result) {
        try {
            isPaymentInProgress = true; paymentStartedAtMs = System.currentTimeMillis(); lastFinancialStatus = -1; lastFinancialFailureStatus = -1
            twintApprovedBySuccessStatus = false
            pendingOp = "twint"
            pendingResult = result
            POSHandler.setCurrency(Currency.CHF)
            val amountStr = String.format(java.util.Locale.US, "%.2f", amount)
            if (posHandler?.isTerminalBusy == true) {
                sendLog("TWINT: busy flag set before twintPurchase â€” force clearing")
                forceCleanSdkState()
            }
            POSHandler.setDefaultReceiptConfig(POSHandler.RECEIPT_DO_NOT_PRINT)
            val tranRef = java.util.UUID.randomUUID().toString()
            val params = QRPaymentParams.builder()
                .productAmount(amountStr)
                .currency("756")
                .transRef(tranRef)
                .build()
            sendLog("twintPurchase(QRPaymentParams amount=$amountStr currency=756 tranRef=$tranRef receipt=DO_NOT_PRINT)")
            posHandler?.twintPurchase(params)
            schedulePaymentTimeout(result, "twintPurchase")
            // SDK TWINT cancel callback atmayabiliyor â€” isTerminalBusy
            // polling ile iptal tespit et
            startTwintBusyPoller(result)
        } catch (e: Exception) {
            sendLog("TWINT error: ${e.message}")
            isPaymentInProgress = false
            twintApprovedBySuccessStatus = false
            pendingResult = null; pendingOp = ""
            pendingRetry = null
            result.error("TWINT_ERROR", e.message, null)
        }
    }

    private fun handleRefund(call: MethodCall, result: MethodChannel.Result) {
        val amount = call.argument<Double>("amount") ?: 0.0
        val currency = call.argument<String>("currency") ?: "CHF"
        sendLog("Refund: $amount $currency")

        // BUSY otomatik retry icin orijinal istegi sakla
        pendingRetry = PendingRetry(op = "refund", amount = amount, currency = currency, result = result)

        ensureConnectionBeforePayment(
            onReady = { executeRefundInner(amount, currency, result) },
            onError = {
                pendingRetry = null
                result.error("NOT_CONNECTED", it, null)
            }
        )
    }

    private fun executeRefundInner(amount: Double, currency: String, result: MethodChannel.Result) {
        try {
            isPaymentInProgress = true; paymentStartedAtMs = System.currentTimeMillis(); lastFinancialStatus = -1; lastFinancialFailureStatus = -1
            pendingOp = "refund"
            pendingResult = result
            POSHandler.setCurrency(getCurrency(currency))
            val amountStr = String.format(java.util.Locale.US, "%.2f", amount)
            val currencyCode = getCurrencyNumericCode(currency)
            if (posHandler?.isTerminalBusy == true) {
                sendLog("Refund: busy flag set before refund â€” force clearing")
                forceCleanSdkState()
            }
            sendLog("refund($amountStr, $currencyCode)")
            val params = RefundParams.builder()
                .refundAmount(amountStr)
                .currency(currencyCode)
                .fixedPinpad(true)
                .receiptConfiguration(POSHandler.RECEIPT_DO_NOT_PRINT)
                .build()
            posHandler?.refund(params)
            schedulePaymentTimeout(result, "refund")
        } catch (e: Exception) {
            sendLog("Refund error: ${e.message}")
            isPaymentInProgress = false
            pendingResult = null; pendingOp = ""
            pendingRetry = null
            result.error("REFUND_ERROR", e.message, null)
        }
    }

    private fun handleCancel(result: MethodChannel.Result) {
        sendLog("Cancelling transaction...")
        if (posHandler == null) {
            result.error("NOT_CONFIGURED", "Not configured", null)
            return
        }

        try {
            posHandler?.cancelTransaction()
            cancelPaymentTimeout()
            isPaymentInProgress = false
            pendingResult?.error("CANCELLED", "Transaction cancelled by user", null)
            pendingResult = null; pendingOp = ""
            result.success(mapOf("success" to true))
        } catch (e: Exception) {
            sendLog("Cancel error: ${e.message}")
            isPaymentInProgress = false
            result.error("CANCEL_ERROR", e.message, null)
        }
    }

    private fun handleClearBatch(result: MethodChannel.Result) {
        sendLog("End of day...")
        ensureConnectionBeforePayment(
            onReady = {
                try {
                    pendingOp = "clearBatch"
                    pendingResult = result
                    posHandler?.clearBatch()
                } catch (e: Exception) {
                    sendLog("EOD error: ${e.message}")
                    pendingResult = null; pendingOp = ""
                    result.error("BATCH_ERROR", e.message, null)
                }
            },
            onError = { result.error("NOT_CONNECTED", it, null) }
        )
    }

    // ======================== TERMINAL CONTROL ========================

    private fun handleSimpleCommand(result: MethodChannel.Result, command: () -> Unit) {
        try {
            command()
            result.success(mapOf("success" to true))
        } catch (e: Exception) {
            result.success(mapOf("success" to false, "error" to e.message))
        }
    }

    private fun handleGetTerminalInfo(result: MethodChannel.Result) {
        try {
            result.success(mapOf(
                "connected" to (connectionState == ConnectionState.CONNECTED),
                "busy" to (posHandler?.isTerminalBusy ?: false),
                "hasPrinter" to (posHandler?.hasPrinter() ?: false),
                "terminalId" to (POSHandler.getTerminalID() ?: ""),
                "connectionType" to currentConnectionType.name,
                "ip" to tcpIp,
                "port" to tcpPort,
                "state" to connectionState.name,
                "reconnectAttempts" to reconnectAttempts
            ))
        } catch (e: Exception) {
            result.success(mapOf("success" to false, "error" to e.message))
        }
    }

    // ======================== USB ========================

    private fun handleGetUsbDevices(result: MethodChannel.Result) {
        try {
            val usbManager = activity?.getSystemService(Context.USB_SERVICE) as? UsbManager
            if (usbManager == null) {
                result.success(mapOf("success" to false, "error" to "USB not available", "devices" to emptyList<Map<String, Any>>()))
                return
            }
            val devices = usbManager.deviceList.values.map { device ->
                mapOf(
                    "name" to device.deviceName,
                    "vendorId" to device.vendorId,
                    "productId" to device.productId,
                    "deviceId" to device.deviceId,
                    "deviceClass" to device.deviceClass,
                    "hasPermission" to usbManager.hasPermission(device)
                )
            }
            result.success(mapOf("success" to true, "devices" to devices))
        } catch (e: Exception) {
            result.success(mapOf("success" to false, "error" to e.message, "devices" to emptyList<Map<String, Any>>()))
        }
    }

    // ======================== HELPERS ========================

    private fun sendLog(message: String) {
        Log.d(TAG, message)
        writeNativeDebugLog(message)
        mainHandler.post { logSink?.success(message) }
    }

    private fun writeNativeDebugLog(message: String) {
        val context = appContext ?: activity?.applicationContext ?: return
        val today = SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).format(Date())
        val time = SimpleDateFormat("HH:mm:ss.SSS", java.util.Locale.US).format(Date())
        val line = "[$time] [D] [MyPosPluginNative] $message\n"

        nativeDebugExecutor.execute {
            try {
                synchronized(nativeLogLock) {
                    val dir = resolveNativeDebugDir(context) ?: return@execute
                    if (!dir.exists()) dir.mkdirs()
                    File(dir, "debug_$today.txt").appendText(line)
                }
            } catch (_: Throwable) {
                // Native file logging is best-effort; EventChannel/logcat still receive the line.
            }
        }
    }

    private fun resolveNativeDebugDir(context: Context): File? {
        nativeDebugDir?.let { cached ->
            if (cached.exists() || cached.mkdirs()) return cached
        }
        val candidates = listOfNotNull(
            File("/storage/emulated/0/log2tech/debug"),
            context.getExternalFilesDir(null)?.let { File(it, "log2tech/debug") },
            File(context.filesDir, "log2tech/debug"),
        )
        for (dir in candidates) {
            try {
                if (!dir.exists()) dir.mkdirs()
                val probe = File(dir, ".native_write_probe")
                probe.writeText("ok")
                probe.delete()
                nativeDebugDir = dir
                return dir
            } catch (_: Throwable) {
                // Try next writable location.
            }
        }
        return null
    }

    private fun getLanguageFromCode(code: String?): Language = when (code?.lowercase()) {
        "fr" -> Language.FRENCH; "en" -> Language.ENGLISH; "it" -> Language.ITALIAN
        else -> Language.GERMAN
    }

    private fun getCurrency(code: String): Currency = when (code.uppercase()) {
        "EUR" -> Currency.EUR; "USD" -> Currency.USD; "GBP" -> Currency.GBP
        else -> Currency.CHF
    }

    private fun getCurrencyNumericCode(code: String): String = when (code.uppercase()) {
        "CHF" -> "756"; "EUR" -> "978"; "USD" -> "840"; "GBP" -> "826"
        else -> "756"
    }

    private fun getCommandName(command: Int): String = when (command) {
        POSHandler.COMMAND_PURCHASE -> "PURCHASE"
        POSHandler.COMMAND_REFUND -> "REFUND"
        POSHandler.COMMAND_CLEAR_BATCH -> "CLEAR_BATCH"
        POSHandler.COMMAND_TWINT_PURCHASE -> "TWINT_PURCHASE"
        POSHandler.COMMAND_PING -> "PING"
        POSHandler.COMMAND_ACTIVATE -> "ACTIVATE"
        POSHandler.COMMAND_DEACTIVATE -> "DEACTIVATE"
        POSHandler.COMMAND_UPDATE -> "UPDATE"
        POSHandler.COMMAND_REPRINT_RECEIPT -> "REPRINT"
        POSHandler.COMMAND_SEND_LOG -> "SEND_LOG"
        POSHandler.COMMAND_OPEN_SETTINGS -> "OPEN_SETTINGS"
        else -> "CMD_$command"
    }

    private fun getStatusName(status: Int): String = when (status) {
        POSHandler.POS_STATUS_SUCCESS -> "SUCCESS"
        POSHandler.POS_STATUS_PROCESSING -> "PROCESSING"
        POSHandler.POS_STATUS_SUCCESS_PING -> "SUCCESS_PING"
        POSHandler.POS_STATUS_PING_FAILED -> "PING_FAILED"
        POSHandler.POS_STATUS_PENDING_USER_INTERACTION -> "PENDING_USER"
        POSHandler.POS_STATUS_USER_CANCEL -> "USER_CANCEL"
        POSHandler.POS_STATUS_INTERNAL_ERROR -> "INTERNAL_ERROR"
        POSHandler.POS_STATUS_TERMINAL_BUSY -> "TERMINAL_BUSY"
        POSHandler.POS_STATUS_WRONG_AMOUNT -> "WRONG_AMOUNT"
        POSHandler.POS_STATUS_COM_ERROR -> "COM_ERROR"
        POSHandler.POS_STATUS_SUCCESS_PURCHASE -> "SUCCESS_PURCHASE"
        POSHandler.POS_STATUS_SUCCESS_REFUND -> "SUCCESS_REFUND"
        else -> "STATUS_$status"
    }
}
