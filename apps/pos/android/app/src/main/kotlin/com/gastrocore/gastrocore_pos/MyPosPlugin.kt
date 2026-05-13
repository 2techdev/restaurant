/**
 * MyPOS Sigma Flutter plugin — TOTAL REWRITE 2026-05-13
 *
 * This file is a thin Flutter MethodChannel shim over a singleton
 * `MyPosManager` whose code is the kit's production-tested
 * `MyPosManager.kt` (RotaMyPosKit, 2026-05-13). All TWINT/card bug-
 * fixes (cancel-stuck, false-approval, listener accumulation, stale
 * data, busy poller fallback, 90 s safety timeout) live there, not
 * here. The plugin's only job is to translate MethodChannel calls to
 * Manager calls and pipe back results.
 *
 * Previous incarnations of this file accumulated ~1300 lines of
 * heuristics across many rounds of patches — most of those were
 * working around bugs that the kit had already solved in its
 * Manager. Wiping the slate clean and adopting the kit's pattern is
 * less risky than incremental patching at this point.
 *
 * MethodChannel: 'mypos_payment'
 *   configure(ip, port)             → { success: Boolean }
 *   isConnected                     → { connected: Boolean }
 *   checkRealConnection             → { connected: Boolean }
 *   testConnection                  → { success: Boolean }
 *   pingTerminal                    → { success: Boolean, connected: Boolean }
 *   isTerminalBusy                  → { busy: Boolean }
 *   processPayment(amount, currency)→ approval / failure map
 *   twintPurchase(amount)           → approval / failure map
 *   refund(amount, currency)        → approval / failure map
 *   cancelPayment                   → { success: Boolean }
 *   clearBatch                      → batch outcome
 *   disconnect                      → { success: Boolean }
 *
 * Dart→Flutter callback (channel.invokeMethod):
 *   onConnectionChanged({connected, state, reason})
 *
 * EventChannel: 'mypos_logs' — broadcast SDK + plugin log lines.
 */
package com.gastrocore.gastrocore_pos

import android.app.Activity
import android.bluetooth.BluetoothDevice
import android.content.ActivityNotFoundException
import android.content.Context
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

// =========================================================================
// MyPosManager — kit's production-tested singleton (RotaMyPosKit 2026-05-13)
// =========================================================================

/**
 * MyPos SDK Manager — singleton wrapper. Production-tested in 2tech
 * Service App; behaviour is unchanged from the kit's reference
 * `MyPosManager.kt`. The plugin below talks ONLY to this object.
 */
internal object MyPosManager {

    private const val MTAG = "MyPosManager"
    const val REQ_CODE_TWINT = 9001

    private val mainHandler = Handler(Looper.getMainLooper())
    private var posHandler: POSHandler? = null
    private var initialized = false

    @Volatile var isPosReady = false
        private set
    @Volatile var isPaymentInProgress = false
        private set

    private var cardCallback: ((PaymentResult) -> Unit)? = null
    private var twintCallback: ((PaymentResult) -> Unit)? = null
    private var twintStartedAt: Long = 0L
    private var cardStartedAt: Long = 0L
    private var lastTwintTransRef: String = ""
    private var connectionListener: ((Boolean) -> Unit)? = null
    private var logSink: ((String) -> Unit)? = null

    private var lastFinancialFailureStatus: Int = -1

    // ---- Public init / config ----

    fun init(context: Context, tcpIp: String, tcpPort: Int) {
        if (initialized) {
            sendLog("MyPosManager: already initialized — skipping re-init (kit §1 listener-accumulation guard)")
            return
        }
        initialized = true

        // 1) SDK config (Application-equivalent setup).
        POSHandler.setApplicationContext(context.applicationContext)
        POSHandler.setSafetyClearingTimeout(30_000)
        POSHandler.setConnectionType(ConnectionType.TCP_IP)
        POSHandler.setTcpIpConnectivity(tcpIp, tcpPort)
        POSHandler.setCurrency(Currency.CHF)
        POSHandler.setLanguage(Language.GERMAN)

        posHandler = POSHandler.getInstance()

        // 2) Listeners — ONE TIME ONLY. Kit Troubleshooting §1: calling
        // setConnectionListener twice accumulates callbacks and pushes
        // the terminal into the "You are all set" loop.
        setupListeners()

        sendLog("MyPosManager initialized: $tcpIp:$tcpPort")
    }

    fun setConnectionListener(listener: ((Boolean) -> Unit)?) {
        connectionListener = listener
    }

    fun setLogSink(sink: ((String) -> Unit)?) {
        logSink = sink
    }

    fun isConnected(): Boolean = try {
        posHandler?.isConnected ?: false
    } catch (_: Exception) {
        false
    }

    fun isTerminalBusy(): Boolean = try {
        posHandler?.isTerminalBusy == true
    } catch (_: Exception) {
        false
    }

    // ---- Card payment ----

    fun processCardPayment(amountInCHF: Double, callback: (PaymentResult) -> Unit) {
        if (!initialized) {
            callback(PaymentResult.Failed("MyPosManager.init() çağrılmadı"))
            return
        }
        if (!isPosReady) {
            callback(PaymentResult.Failed("Terminal hazır değil (POSReady bekleniyor)"))
            return
        }
        if (isPaymentInProgress) {
            callback(PaymentResult.Failed("Önceki ödeme devam ediyor"))
            return
        }

        cardCallback = callback
        isPaymentInProgress = true
        cardStartedAt = System.currentTimeMillis()
        lastFinancialFailureStatus = -1

        forceCleanSdkState()

        val amountStr = String.format(java.util.Locale.US, "%.2f", amountInCHF)
        // SDK signature for .currency() is String (per javap inspection
        // of slavesdk-release.aar). Use the ISO 4217 numeric code "756".
        val params = PaymentParams.builder()
            .productAmount(amountStr)
            .currency("756")
            .fixedPinpad(true)
            .receiptConfiguration(POSHandler.RECEIPT_DO_NOT_PRINT)
            .build()

        POSHandler.setCurrency(Currency.CHF)
        sendLog("➡️ purchase($amountStr CHF)")
        try {
            posHandler?.purchase(params)
        } catch (e: Throwable) {
            Log.e(MTAG, "purchase() exception", e)
            sendLog("❌ purchase() exception: ${e.javaClass.simpleName}: ${e.message}")
            isPaymentInProgress = false
            cardCallback = null
            callback(PaymentResult.Failed("purchase() exception: ${e.message}"))
        }
    }

    // ---- TWINT payment ----

    fun processTwintPayment(activity: Activity, amountInCHF: Double, callback: (PaymentResult) -> Unit) {
        if (!initialized) {
            callback(PaymentResult.Failed("MyPosManager.init() çağrılmadı"))
            return
        }
        if (!isPosReady) {
            callback(PaymentResult.Failed("Terminal hazır değil (POSReady bekleniyor)"))
            return
        }
        if (isPaymentInProgress) {
            callback(PaymentResult.Failed("Önceki ödeme devam ediyor"))
            return
        }

        twintCallback = callback
        isPaymentInProgress = true
        twintStartedAt = System.currentTimeMillis()
        lastTwintTransRef = UUID.randomUUID().toString()
        lastFinancialFailureStatus = -1

        forceCleanSdkState()
        POSHandler.setCurrency(Currency.CHF) // TWINT only CHF

        val amountStr = String.format(java.util.Locale.US, "%.2f", amountInCHF)
        sendLog("➡️ openPaymentActivity(TWINT, $amountStr CHF, ref=$lastTwintTransRef)")

        try {
            posHandler?.openPaymentActivity(activity, REQ_CODE_TWINT, amountStr, lastTwintTransRef)
            scheduleTwintSafetyTimeout()
            scheduleTwintBusyPoller()
        } catch (e: ActivityNotFoundException) {
            Log.e(MTAG, "OperationActivity not declared", e)
            sendLog("❌ TWINT crash: OperationActivity not in manifest")
            isPaymentInProgress = false
            cancelTwintSafetyNets()
            twintCallback = null
            callback(PaymentResult.Failed("MyPOS OperationActivity manifest'te eksik"))
        } catch (e: Throwable) {
            Log.e(MTAG, "openPaymentActivity() exception", e)
            sendLog("❌ openPaymentActivity exception: ${e.javaClass.simpleName}: ${e.message}")
            isPaymentInProgress = false
            cancelTwintSafetyNets()
            twintCallback = null
            callback(PaymentResult.Failed("openPaymentActivity exception: ${e.message}"))
        }
    }

    // ---- TWINT result (called from Activity.onActivityResult via plugin) ----

    fun handleTwintResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQ_CODE_TWINT) return
        if (twintCallback == null) {
            sendLog("TWINT result arrived but twintCallback null (already completed by safety net?)")
            return
        }
        cancelTwintSafetyNets()
        isPaymentInProgress = false

        val posStatus = data?.getIntExtra("pos_status", -1) ?: -1
        @Suppress("DEPRECATION")
        val txData: TransactionData? = try {
            data?.getParcelableExtra("transaction_data")
        } catch (_: Throwable) { null }

        sendLog("✉️ TWINT result: resultCode=$resultCode posStatus=$posStatus hasData=${txData != null}")

        // Stale data — kit §5: getLastTransactionData can return the
        // previous transaction. 60s window.
        if (txData != null) {
            val txTime = try { txData.transactionDateLocal?.time ?: 0L } catch (_: Throwable) { 0L }
            if (txTime > 0 && txTime < twintStartedAt - 60_000) {
                sendLog("⚠️ TWINT stale data (txTime=$txTime started=$twintStartedAt) — rejecting")
                val cb = twintCallback
                twintCallback = null
                cb?.invoke(PaymentResult.Failed("Stale TWINT data — eski işlem verisi"))
                return
            }
        }

        val result: PaymentResult = when {
            txData != null && !txData.rrn.isNullOrEmpty() -> {
                val declined = txData.declinedReason1?.takeIf { it.isNotEmpty() }
                    ?: txData.declineReason2?.takeIf { it.isNotEmpty() }
                if (declined != null) {
                    sendLog("❌ TWINT declined: $declined")
                    PaymentResult.Declined(declined)
                } else {
                    sendLog("✅ TWINT approved rrn=${txData.rrn}")
                    PaymentResult.Approved(
                        transactionId = txData.rrn ?: "",
                        authCode = txData.authCode ?: "",
                        amount = txData.amount ?: "",
                        maskedPan = txData.panMasked ?: "",
                        cardType = "TWINT",
                        terminalId = txData.terminalID ?: "",
                        merchantId = txData.merchantID ?: "",
                        stan = txData.stan ?: "",
                        transRef = lastTwintTransRef,
                    )
                }
            }
            resultCode == Activity.RESULT_CANCELED -> {
                sendLog("TWINT cancelled by user")
                PaymentResult.Cancelled
            }
            posStatus != -1 && posStatus != POSHandler.POS_STATUS_SUCCESS -> {
                sendLog("TWINT failed: pos_status=$posStatus")
                PaymentResult.Failed("status=$posStatus")
            }
            else -> {
                sendLog("TWINT no data, treating as failed")
                PaymentResult.Failed("No transaction data")
            }
        }

        val cb = twintCallback
        twintCallback = null
        cb?.invoke(result)
    }

    // ---- TWINT safety nets (kit production fallbacks) ----

    private var twintSafetyTimeout: Runnable? = null
    private var twintBusyPoller: Runnable? = null
    private var twintIdleCount: Int = 0

    /** 90 s timeout — terminal never responded. */
    private fun scheduleTwintSafetyTimeout() {
        cancelTwintSafetyTimeout()
        twintSafetyTimeout = Runnable {
            if (!isPaymentInProgress) return@Runnable
            sendLog("⏱ TWINT safety timeout (90s) — no response from terminal")
            try { posHandler?.cancelTransaction() } catch (_: Exception) {}
            isPaymentInProgress = false
            cancelTwintSafetyNets()
            val cb = twintCallback
            twintCallback = null
            cb?.invoke(PaymentResult.Failed("TWINT timeout (90s) — terminal cevap vermedi"))
        }
        mainHandler.postDelayed(twintSafetyTimeout!!, 90_000)
    }

    private fun cancelTwintSafetyTimeout() {
        twintSafetyTimeout?.let { mainHandler.removeCallbacks(it) }
        twintSafetyTimeout = null
    }

    /**
     * Busy poller — SDK 2.1.8/2.1.9 sometimes never fires
     * onActivityResult for TWINT. After 3 consecutive idle ticks
     * (~6 s) ask the SDK for the last transaction data and pretend
     * it's our onActivityResult.
     */
    private fun scheduleTwintBusyPoller() {
        cancelTwintBusyPoller()
        twintIdleCount = 0
        twintBusyPoller = object : Runnable {
            override fun run() {
                if (!isPaymentInProgress) return
                val busy = try { posHandler?.isTerminalBusy == true } catch (_: Exception) { true }
                if (!busy) {
                    twintIdleCount++
                    sendLog("TWINT poller: idle ($twintIdleCount/3)")
                    if (twintIdleCount >= 3) {
                        sendLog("TWINT poller: 3x idle — querying lastTransactionData (async)")
                        // SDK 2.1.9 signature: void getLastTransactionData() —
                        // it does NOT return the data, it triggers a fresh
                        // onTransactionComplete callback. Our listener will
                        // forward that to handleTwintResult via the
                        // twintCallback path below.
                        try {
                            posHandler?.getLastTransactionData()
                        } catch (e: Exception) {
                            sendLog("getLastTransactionData error: ${e.message}")
                            // If the SDK call itself fails, fall back to
                            // cancelling so the operator isn't stuck.
                            if (twintCallback != null) {
                                handleTwintResult(
                                    REQ_CODE_TWINT,
                                    Activity.RESULT_CANCELED,
                                    buildSyntheticIntentFromData(null),
                                )
                            }
                        }
                        return
                    }
                } else {
                    twintIdleCount = 0
                }
                mainHandler.postDelayed(this, 2000)
            }
        }
        mainHandler.postDelayed(twintBusyPoller!!, 2000)
    }

    private fun cancelTwintBusyPoller() {
        twintBusyPoller?.let { mainHandler.removeCallbacks(it) }
        twintBusyPoller = null
        twintIdleCount = 0
    }

    private fun cancelTwintSafetyNets() {
        cancelTwintSafetyTimeout()
        cancelTwintBusyPoller()
    }

    private fun buildSyntheticIntentFromData(data: TransactionData?): Intent {
        val intent = Intent()
        if (data != null) {
            intent.putExtra("transaction_data", data)
            intent.putExtra("pos_status", POSHandler.POS_STATUS_SUCCESS)
        } else {
            intent.putExtra("pos_status", -1)
        }
        return intent
    }

    // ---- Cancel / EOD ----

    fun cancelCurrentTransaction(): Boolean = try {
        cancelTwintSafetyNets()
        posHandler?.cancelTransaction()
        true
    } catch (e: Exception) {
        Log.e(MTAG, "cancelTransaction error: ${e.message}", e)
        false
    }

    fun clearBatch(callback: (success: Boolean, errorMsg: String?) -> Unit) {
        if (!initialized || posHandler == null) {
            callback(false, "not initialized")
            return
        }
        try {
            posHandler?.setTransactionClearedListener { status ->
                mainHandler.post {
                    callback(
                        status == POSHandler.POS_STATUS_SUCCESS,
                        if (status == 0) null else "status=$status"
                    )
                }
            }
            posHandler?.clearBatch()
        } catch (e: Exception) {
            callback(false, "exception: ${e.message}")
        }
    }

    // ---- Refund ----

    fun processRefund(amountInCHF: Double, currency: String, callback: (PaymentResult) -> Unit) {
        if (!initialized) {
            callback(PaymentResult.Failed("MyPosManager.init() çağrılmadı"))
            return
        }
        if (!isPosReady) {
            callback(PaymentResult.Failed("Terminal hazır değil"))
            return
        }
        if (isPaymentInProgress) {
            callback(PaymentResult.Failed("Önceki işlem devam ediyor"))
            return
        }
        cardCallback = callback // refund uses same complete callback
        isPaymentInProgress = true
        cardStartedAt = System.currentTimeMillis()
        lastFinancialFailureStatus = -1
        forceCleanSdkState()

        val amountStr = String.format(java.util.Locale.US, "%.2f", amountInCHF)
        // SDK has two refund signatures (per javap):
        //   void refund(RefundParams)
        //   void refund(String amount, String currency, int receipt)
        // The legacy 3-arg form is simpler and we don't need the
        // referenceNumber + referenceNumberType the builder API exposes
        // (POS-side cash software already tracks the original RRN).
        try {
            posHandler?.refund(amountStr, currency, POSHandler.RECEIPT_DO_NOT_PRINT)
            sendLog("➡️ refund($amountStr $currency)")
        } catch (e: Throwable) {
            isPaymentInProgress = false
            cardCallback = null
            callback(PaymentResult.Failed("refund() exception: ${e.message}"))
        }
    }

    // ---- Listener setup ----

    private fun setupListeners() {
        val ph = posHandler ?: return

        ph.setConnectionListener(object : ConnectionListener {
            override fun onConnected(device: BluetoothDevice?) {
                mainHandler.post {
                    sendLog("🔗 SDK CONNECTED (waiting for POSReady)")
                    isPosReady = false
                    connectionListener?.invoke(false) // not READY yet
                }
            }

            override fun onDisconnected(device: BluetoothDevice?) {
                mainHandler.post {
                    sendLog("🔌 SDK DISCONNECTED")
                    isPosReady = false
                    connectionListener?.invoke(false)
                    // Kit §2: don't manually reconnect on TCP/IP — SDK
                    // 2.1.9+ runs its own 2.5 s sleep+retry loop.
                }
            }
        })

        ph.setPOSReadyListener {
            mainHandler.post {
                sendLog("✅ POS READY — terminal command-layer ready")
                isPosReady = true
                connectionListener?.invoke(true)
            }
        }

        ph.setPOSInfoListener(object : POSInfoListener {
            override fun onPOSInfoReceived(command: Int, status: Int, description: String?, bundle: Bundle?) {
                mainHandler.post { handlePosInfo(command, status, description) }
            }

            override fun onTransactionComplete(data: TransactionData?) {
                mainHandler.post { handleTransactionComplete(data) }
            }
        })
    }

    private fun handlePosInfo(command: Int, status: Int, description: String?) {
        sendLog("ℹ️ PosInfo cmd=$command status=$status (${getStatusName(status)}) desc=${description ?: "-"}")

        // Stash financial-command failure status for handleTransactionComplete.
        if (command == POSHandler.COMMAND_PURCHASE ||
            command == POSHandler.COMMAND_REFUND ||
            command == POSHandler.COMMAND_TWINT_PURCHASE
        ) {
            if (status in terminalFailureStatuses()) {
                lastFinancialFailureStatus = status
            }
        }

        // Card direct-fire: definite terminal failure → callback NOW.
        // SDK does not always follow these with onTransactionComplete,
        // so waiting for it was the 2026-05-13 cancel-stuck bug.
        // (TWINT result path is onActivityResult; only fire here for
        // card/refund.)
        if (cardCallback != null && command != POSHandler.COMMAND_TWINT_PURCHASE) {
            when (status) {
                POSHandler.POS_STATUS_USER_CANCEL -> finishCard(PaymentResult.Cancelled)
                POSHandler.POS_STATUS_INTERNAL_ERROR -> finishCard(PaymentResult.Failed("Terminal internal error"))
                POSHandler.POS_STATUS_TERMINAL_BUSY -> finishCard(PaymentResult.Failed("Terminal busy"))
                POSHandler.POS_STATUS_WRONG_AMOUNT -> finishCard(PaymentResult.Failed("Wrong amount"))
                POSHandler.POS_STATUS_COM_ERROR -> finishCard(PaymentResult.Failed("Communication error"))
                POSHandler.POS_STATUS_NO_CARD_FOUND -> finishCard(PaymentResult.Failed("Card not found"))
                POSHandler.POS_STATUS_NOT_SUPPORTED_CARD -> finishCard(PaymentResult.Failed("Card not supported"))
                POSHandler.POS_STATUS_CARD_CHIP_ERROR -> finishCard(PaymentResult.Failed("Card chip read error"))
                POSHandler.POS_STATUS_INVALID_PIN -> finishCard(PaymentResult.Failed("Wrong PIN"))
                POSHandler.POS_STATUS_MAX_PIN_COUNT_EXCEEDED -> finishCard(PaymentResult.Failed("PIN locked"))
                POSHandler.POS_STATUS_TRANSACTION_NOT_FOUND -> finishCard(PaymentResult.Failed("Transaction not found"))
                else -> { /* progress — wait */ }
            }
        }
    }

    private fun handleTransactionComplete(data: TransactionData?) {
        sendLog("--- onTransactionComplete data=${data?.rrn ?: "null"} failureStatus=$lastFinancialFailureStatus")

        // TWINT bypass: if a TWINT callback is pending, this event is
        // almost certainly the SDK's response to a `getLastTransactionData()`
        // call from the busy poller (SDK 2.1.9 sometimes never fires
        // onActivityResult for TWINT). Forward to handleTwintResult as
        // if it had come through onActivityResult.
        if (twintCallback != null) {
            sendLog("onTransactionComplete forwarded to TWINT result handler")
            handleTwintResult(
                REQ_CODE_TWINT,
                if (data != null && !data.rrn.isNullOrEmpty()) Activity.RESULT_OK
                    else Activity.RESULT_CANCELED,
                buildSyntheticIntentFromData(data),
            )
            return
        }

        if (cardCallback == null) {
            // handlePosInfo already finished it (or it's an orphan).
            lastFinancialFailureStatus = -1
            return
        }

        // Stale data — 60s window (production aligned).
        if (data != null && cardStartedAt > 0) {
            val txTime = try { data.transactionDateLocal?.time ?: 0L } catch (_: Throwable) { 0L }
            if (txTime > 0 && txTime < cardStartedAt - 60_000) {
                sendLog("⚠️ Stale onTransactionComplete (card, txTime=$txTime started=$cardStartedAt) — rejecting")
                return
            }
        }

        val rrn = data?.rrn?.trim().orEmpty()
        val authCode = data?.authCode?.trim().orEmpty()
        val approval = try { data?.approval?.trim().orEmpty() } catch (_: Throwable) { "" }
        val declinedReason = data?.declinedReason1?.takeIf { it.isNotEmpty() }
            ?: data?.declineReason2?.takeIf { it.isNotEmpty() }
            ?: ""

        val hasCardData = rrn.isNotEmpty() || authCode.isNotEmpty()
        val hasApprovalCode = approval == "00" || approval == "0" ||
            approval.equals("approved", ignoreCase = true)
        val hasRealData = hasCardData || hasApprovalCode
        val failureOrDefinite = lastFinancialFailureStatus in terminalFailureStatuses()
        val hasExplicitDecline = declinedReason.isNotEmpty()

        val result: PaymentResult = when {
            failureOrDefinite -> when (lastFinancialFailureStatus) {
                POSHandler.POS_STATUS_USER_CANCEL -> PaymentResult.Cancelled
                else -> PaymentResult.Failed("status=${getStatusName(lastFinancialFailureStatus)}")
            }
            hasExplicitDecline -> PaymentResult.Declined(declinedReason)
            hasRealData -> PaymentResult.Approved(
                transactionId = if (rrn.isNotEmpty()) rrn else authCode,
                authCode = authCode,
                amount = data?.amount ?: "",
                maskedPan = data?.panMasked ?: "",
                cardType = data?.aidName ?: "",
                terminalId = data?.terminalID ?: "",
                merchantId = data?.merchantID ?: "",
                stan = data?.stan ?: "",
            )
            else -> PaymentResult.Failed("No approval proof (rrn/authCode/approval all empty)")
        }
        finishCard(result)
    }

    private fun finishCard(result: PaymentResult) {
        val cb = cardCallback
        cardCallback = null
        isPaymentInProgress = false
        cardStartedAt = 0L
        lastFinancialFailureStatus = -1
        cb?.invoke(result)
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

    private fun forceCleanSdkState() {
        try {
            val utilsClass = Class.forName("com.mypos.slavesdk.Utils")
            val field = utilsClass.getDeclaredField("mTransactionInProgress")
            field.isAccessible = true
            if (field.getBoolean(null)) {
                field.setBoolean(null, false)
                sendLog("SDK busy flag was stuck — cleared")
            }
        } catch (e: Exception) {
            // Non-fatal — only matters if the field was actually stuck.
        }
    }

    private fun getCurrencyIsoNumeric(code: String): Int = when (code.uppercase()) {
        "CHF" -> 756
        "EUR" -> 978
        "USD" -> 840
        "GBP" -> 826
        else -> 756
    }

    private fun getStatusName(status: Int): String = when (status) {
        0 -> "SUCCESS"
        1 -> "PENDING_USER_INTERACTION"
        2 -> "USER_CANCEL"
        3 -> "INTERNAL_ERROR"
        4 -> "TERMINAL_BUSY"
        11 -> "PROCESSING"
        23 -> "WRONG_AMOUNT"
        34 -> "SUCCESS_PURCHASE"
        35 -> "SUCCESS_REFUND"
        74 -> "PRESENT_CARD"
        76 -> "ENTER_PIN"
        79 -> "COM_ERROR"
        else -> "STATUS_$status"
    }

    private fun sendLog(msg: String) {
        Log.d(MTAG, msg)
        try { logSink?.invoke(msg) } catch (_: Throwable) {}
    }

    // ---- Result type (Flutter conversion happens in plugin) ----

    sealed class PaymentResult {
        object Cancelled : PaymentResult()
        data class Approved(
            val transactionId: String,
            val authCode: String,
            val amount: String,
            val maskedPan: String,
            val cardType: String,
            val terminalId: String,
            val merchantId: String,
            val stan: String,
            val transRef: String = "",
        ) : PaymentResult()
        data class Declined(val reason: String) : PaymentResult()
        data class Failed(val reason: String) : PaymentResult()
    }
}

// =========================================================================
// MyPosPlugin — thin Flutter shim that delegates to MyPosManager.
// =========================================================================

class MyPosPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var logChannel: EventChannel
    private var logSink: EventChannel.EventSink? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var appContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "mypos_payment")
        channel.setMethodCallHandler(this)
        logChannel = EventChannel(binding.binaryMessenger, "mypos_logs")
        logChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { logSink = events }
            override fun onCancel(arguments: Any?) { logSink = null }
        })

        // Pipe MyPosManager logs to the Dart EventChannel + the connection
        // listener to the Flutter MethodChannel callback.
        MyPosManager.setLogSink { msg ->
            mainHandler.post { logSink?.success(msg) }
        }
        MyPosManager.setConnectionListener { ready ->
            mainHandler.post {
                channel.invokeMethod("onConnectionChanged", mapOf(
                    "connected" to ready,
                    "state" to if (ready) "READY" else "NOT_READY",
                    "reason" to "MyPosManager state change",
                ))
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        MyPosManager.setLogSink(null)
        MyPosManager.setConnectionListener(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
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
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != MyPosManager.REQ_CODE_TWINT) return false
        MyPosManager.handleTwintResult(requestCode, resultCode, data)
        return true
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "configure" -> handleConfigure(call, result)
            "disconnect" -> {
                // Manager doesn't expose explicit disconnect; treat as cancel-only.
                MyPosManager.cancelCurrentTransaction()
                result.success(mapOf("success" to true))
            }
            "isConnected" -> result.success(mapOf("connected" to MyPosManager.isConnected()))
            "checkRealConnection" -> result.success(mapOf("connected" to (MyPosManager.isConnected() && MyPosManager.isPosReady)))
            "testConnection" -> result.success(mapOf("success" to MyPosManager.isPosReady))
            "pingTerminal" -> {
                // Heartbeat-equivalent: trust state flag (kit §7).
                val ok = MyPosManager.isConnected() && MyPosManager.isPosReady
                result.success(mapOf("success" to ok, "connected" to ok))
            }
            "isTerminalBusy" -> result.success(mapOf("busy" to MyPosManager.isTerminalBusy()))
            "processPayment" -> handlePayment(call, result)
            "twintPurchase" -> handleTwint(call, result)
            "refund" -> handleRefund(call, result)
            "cancelPayment" -> result.success(mapOf("success" to MyPosManager.cancelCurrentTransaction()))
            "clearBatch" -> MyPosManager.clearBatch { success, err ->
                result.success(mapOf(
                    "success" to success,
                    "status" to (if (success) "batch_cleared" else "failed"),
                    "error" to (err ?: ""),
                ))
            }
            else -> result.notImplemented()
        }
    }

    private fun handleConfigure(call: MethodCall, result: MethodChannel.Result) {
        val ip = call.argument<String>("ip") ?: "192.168.1.131"
        val port = call.argument<Int>("port") ?: 60180
        try {
            val ctx = activity ?: appContext
                ?: return result.success(mapOf("success" to false, "error" to "No context available"))
            MyPosManager.init(ctx, ip, port)
            result.success(mapOf("success" to true))
        } catch (e: Throwable) {
            Log.e(TAG, "configure() failed", e)
            result.success(mapOf("success" to false, "error" to (e.message ?: "configure failed")))
        }
    }

    private fun handlePayment(call: MethodCall, result: MethodChannel.Result) {
        val amount = call.argument<Double>("amount")
            ?: return result.success(mapOf("success" to false, "error" to "Missing amount"))
        MyPosManager.processCardPayment(amount) { r -> result.success(toMap(r)) }
    }

    private fun handleTwint(call: MethodCall, result: MethodChannel.Result) {
        val amount = call.argument<Double>("amount")
            ?: return result.success(mapOf("success" to false, "error" to "Missing amount"))
        val act = activity
            ?: return result.success(mapOf(
                "success" to false,
                "errorCode" to "NO_ACTIVITY",
                "error" to "TWINT için Activity context şart — uygulama foreground'da değil"
            ))
        MyPosManager.processTwintPayment(act, amount) { r -> result.success(toMap(r)) }
    }

    private fun handleRefund(call: MethodCall, result: MethodChannel.Result) {
        val amount = call.argument<Double>("amount")
            ?: return result.success(mapOf("success" to false, "error" to "Missing amount"))
        val currency = call.argument<String>("currency") ?: "CHF"
        MyPosManager.processRefund(amount, currency) { r -> result.success(toMap(r)) }
    }

    /** Convert manager PaymentResult to the response shape Dart expects. */
    private fun toMap(r: MyPosManager.PaymentResult): Map<String, Any?> = when (r) {
        is MyPosManager.PaymentResult.Approved -> mapOf(
            "success" to true,
            "transactionId" to r.transactionId,
            "authCode" to r.authCode,
            "amount" to r.amount,
            "maskedPan" to r.maskedPan,
            "cardType" to r.cardType,
            "terminalId" to r.terminalId,
            "merchantId" to r.merchantId,
            "stan" to r.stan,
            "transRef" to r.transRef,
            "rrn" to r.transactionId,
        )
        is MyPosManager.PaymentResult.Declined -> mapOf(
            "success" to false,
            "errorCode" to "DECLINED",
            "error" to r.reason,
        )
        is MyPosManager.PaymentResult.Cancelled -> mapOf(
            "success" to false,
            "errorCode" to "CANCELLED",
            "error" to "Kullanıcı iptal etti",
        )
        is MyPosManager.PaymentResult.Failed -> mapOf(
            "success" to false,
            "errorCode" to "FAILED",
            "error" to r.reason,
        )
    }
}
