package com.gastrocore.gastrocore_pos

import android.app.PendingIntent
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.*
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.UUID

/**
 * GastroCore POS — Yazıcı eklentisi (USB + Bluetooth).
 *
 * Kayıtlı kanallar:
 *   MethodChannel  : com.gastrocore.gastrocore_pos/printer
 *   EventChannel   : com.gastrocore.gastrocore_pos/printer_usb_events
 *
 * Desteklenen USB vendor ID'ler: Epson, Star, Bixolon, Citizen,
 *   Xprinter, SNBC, POS-X, HPRT, Gainscha, Rongta, CH340, FTDI,
 *   Prolific, Silicon Labs vb.
 */
class PrinterPlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "GastroPrinterPlugin"
        private const val CHANNEL = "com.gastrocore.gastrocore_pos/printer"
        private const val USB_EVENT_CHANNEL = "com.gastrocore.gastrocore_pos/printer_usb_events"
        private const val ACTION_USB_PERMISSION =
            "com.gastrocore.gastrocore_pos.USB_PRINTER_PERMISSION"

        /** SPP UUID — tüm seri-port Bluetooth yazıcılar tarafından desteklenir */
        private val SPP_UUID: UUID =
            UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

        /**
         * Bilinen yazıcı vendor ID listesi.
         *
         * USB device class = 7 (Printer) olmasa bile bu vendor ID'e sahip
         * cihazlar yazıcı olarak kabul edilir.
         */
        val KNOWN_PRINTER_VENDORS = setOf(
            // Epson (TM-T88, TM-T20, TM-U220 ...)
            0x04B8,
            // Star Micronics (TSP, SP series)
            0x0519,
            // Bixolon (SRP series)
            0x154F,
            // Citizen (CT-S, CT-E series)
            0x2730, 0x0665,
            // Xprinter / XP-series
            0x0483, 0x0416, 0x1504,
            // SNBC / Sewoo LK series
            0x0FE6,
            // POS-X / Custom
            0x0DD4,
            // HPRT TP series
            0x0485,
            // Gainscha / Gprinter GP series
            0x28E9,
            // Generic POS
            0x0456, 0x0471, 0x0525,
            // USB-Serial çipleri (termal yazıcı içi)
            0x1A86, // CH340 / CH341
            0x0403, // FTDI FT232
            0x067B, // Prolific PL2303
            0x10C4, // Silicon Labs CP210x
        )
    }

    private var methodChannel: MethodChannel? = null
    private var usbEventChannel: EventChannel? = null
    private var usbEventSink: EventChannel.EventSink? = null
    private var usbManager: UsbManager? = null

    // USB bağlantı nesneleri
    private var usbDevice: UsbDevice? = null
    private var usbConnection: UsbDeviceConnection? = null
    private var usbInterface: UsbInterface? = null
    private var usbEndpoint: UsbEndpoint? = null

    // Bluetooth bağlantı nesneleri
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var bluetoothSocket: BluetoothSocket? = null
    private var bluetoothOutputStream: OutputStream? = null

    // -------------------------------------------------------------------------
    // USB BroadcastReceiver
    // -------------------------------------------------------------------------

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val device = getUsbDevice(intent)

            when (intent.action) {
                ACTION_USB_PERMISSION -> {
                    val granted =
                        intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    Log.d(TAG, "USB izni ${if (granted) "verildi" else "reddedildi"}: ${device?.deviceName}")
                }

                UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                    Log.d(TAG, "USB takıldı: ${device?.productName} VID=${device?.vendorId}")
                    if (device != null && isPrinterDevice(device)) {
                        notifyUsbEvent("USB_DEVICE_ATTACHED", device)
                    }
                }

                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    Log.d(TAG, "USB çıkarıldı: ${device?.productName} VID=${device?.vendorId}")
                    if (device != null) {
                        if (device.deviceId == usbDevice?.deviceId) {
                            disconnectUsb()
                            notifyUsbEvent("USB_DEVICE_DETACHED", device)
                        } else if (isPrinterDevice(device)) {
                            notifyUsbEvent("USB_DEVICE_DETACHED", device)
                        }
                    }
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun getUsbDevice(intent: Intent): UsbDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        }

    // -------------------------------------------------------------------------
    // Kayıt / Sil
    // -------------------------------------------------------------------------

    fun register(flutterEngine: FlutterEngine) {
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, CHANNEL
        ).also { it.setMethodCallHandler(this) }

        usbEventChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger, USB_EVENT_CHANNEL
        ).also {
            it.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    usbEventSink = sink
                    Log.d(TAG, "USB event stream başlatıldı")
                }
                override fun onCancel(args: Any?) {
                    usbEventSink = null
                }
            })
        }

        usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()

        val filter = IntentFilter().apply {
            addAction(ACTION_USB_PERMISSION)
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(usbReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(usbReceiver, filter)
        }

        Log.d(TAG, "PrinterPlugin kayıtlandı (USB + Bluetooth)")
    }

    fun unregister() {
        try { context.unregisterReceiver(usbReceiver) } catch (_: Exception) {}
        usbEventSink = null
        usbEventChannel?.setStreamHandler(null)
        disconnect()
        methodChannel?.setMethodCallHandler(null)
    }

    // -------------------------------------------------------------------------
    // MethodChannel handler
    // -------------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getUsbPrinters"         -> result.success(getUsbPrinters())
            "connectUsbPrinter"      -> {
                val deviceId = call.argument<Int>("deviceId") ?: 0
                result.success(connectUsbPrinter(deviceId))
            }
            "getBluetoothPrinters"   -> result.success(getBluetoothPrinters())
            "connectBluetoothPrinter" -> {
                val address = call.argument<String>("address") ?: ""
                result.success(connectBluetoothPrinter(address))
            }
            "printBytes"             -> {
                val data = call.argument<ByteArray>("data")
                if (data != null) result.success(printBytes(data))
                else result.error("INVALID_DATA", "data null", null)
            }
            "disconnectPrinter"      -> { disconnect(); result.success(true) }
            else                     -> result.notImplemented()
        }
    }

    // =========================================================================
    // USB
    // =========================================================================

    private fun isPrinterDevice(device: UsbDevice): Boolean =
        device.deviceClass == 7 ||
        (device.interfaceCount > 0 && device.getInterface(0).interfaceClass == 7) ||
        isKnownPrinterVendor(device.vendorId)

    private fun isKnownPrinterVendor(vendorId: Int): Boolean =
        vendorId in KNOWN_PRINTER_VENDORS

    private fun getUsbPrinters(): List<Map<String, Any?>> {
        val result = mutableListOf<Map<String, Any?>>()
        val deviceList = usbManager?.deviceList ?: return result

        for ((_, device) in deviceList) {
            if (isPrinterDevice(device)) {
                result.add(
                    mapOf(
                        "deviceId"  to device.deviceId,
                        "name"      to (device.productName ?: "USB Yazici"),
                        "vendorId"  to device.vendorId,
                        "productId" to device.productId,
                    )
                )
                Log.d(TAG, "USB yazıcı bulundu: ${device.productName} VID=0x${device.vendorId.toString(16)}")
            }
        }
        return result
    }

    private fun connectUsbPrinter(deviceId: Int): Boolean {
        val deviceList = usbManager?.deviceList ?: return false

        for ((_, device) in deviceList) {
            if (device.deviceId != deviceId) continue

            usbDevice = device

            if (usbManager?.hasPermission(device) != true) {
                val pi = PendingIntent.getBroadcast(
                    context, 0,
                    Intent(ACTION_USB_PERMISSION),
                    PendingIntent.FLAG_IMMUTABLE
                )
                usbManager?.requestPermission(device, pi)
                Log.d(TAG, "USB izni istendi...")
                return false
            }

            return openUsbConnection()
        }
        return false
    }

    private fun openUsbConnection(): Boolean {
        val device = usbDevice ?: return false
        try {
            for (i in 0 until device.interfaceCount) {
                val intf = device.getInterface(i)
                for (j in 0 until intf.endpointCount) {
                    val ep = intf.getEndpoint(j)
                    if (ep.direction == UsbConstants.USB_DIR_OUT) {
                        usbInterface = intf
                        usbEndpoint  = ep
                        break
                    }
                }
                if (usbEndpoint != null) break
            }

            if (usbEndpoint == null) {
                Log.e(TAG, "OUT endpoint bulunamadı")
                return false
            }

            usbConnection = usbManager?.openDevice(device) ?: run {
                Log.e(TAG, "USB bağlantısı açılamadı")
                return false
            }
            usbConnection?.claimInterface(usbInterface, true)
            Log.d(TAG, "USB yazıcı bağlantısı kuruldu: ${device.productName}")
            return true

        } catch (e: Exception) {
            Log.e(TAG, "USB bağlantı hatası: ${e.message}")
            return false
        }
    }

    private fun disconnectUsb() {
        try {
            usbConnection?.releaseInterface(usbInterface)
            usbConnection?.close()
        } catch (_: Exception) {}
        usbConnection = null
        usbInterface  = null
        usbEndpoint   = null
        usbDevice     = null
        Log.d(TAG, "USB yazıcı bağlantısı kesildi")
    }

    private fun notifyUsbEvent(action: String, device: UsbDevice) {
        val data = mapOf(
            "action"     to action,
            "vendorId"  to device.vendorId,
            "productId" to device.productId,
            "deviceId"  to device.deviceId,
            "deviceName" to (device.productName ?: "USB Device"),
        )
        Log.d(TAG, "USB event → Flutter: $action")
        usbEventSink?.success(data)
    }

    // =========================================================================
    // Bluetooth
    // =========================================================================

    private fun getBluetoothPrinters(): List<Map<String, Any?>> {
        val result = mutableListOf<Map<String, Any?>>()
        try {
            val paired = bluetoothAdapter?.bondedDevices ?: return result
            for (device in paired) {
                result.add(
                    mapOf(
                        "name"    to (device.name ?: "Bluetooth Yazici"),
                        "address" to device.address,
                    )
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Bluetooth tarama hatası: ${e.message}")
        }
        return result
    }

    private fun connectBluetoothPrinter(address: String): Boolean {
        return try {
            val device = bluetoothAdapter?.getRemoteDevice(address) ?: return false
            bluetoothSocket?.close()
            bluetoothSocket = device.createRfcommSocketToServiceRecord(SPP_UUID)
            bluetoothSocket?.connect()
            bluetoothOutputStream = bluetoothSocket?.outputStream
            Log.d(TAG, "Bluetooth yazıcı bağlantısı kuruldu: ${device.name}")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Bluetooth bağlantı hatası: ${e.message}")
            false
        }
    }

    // =========================================================================
    // Yazdırma
    // =========================================================================

    private fun printBytes(data: ByteArray): Boolean {
        return try {
            // USB — bulk transfer
            val conn = usbConnection
            val ep   = usbEndpoint
            if (conn != null && ep != null) {
                val written = conn.bulkTransfer(ep, data, data.size, 5_000)
                Log.d(TAG, "USB yazdırma: $written / ${data.size} byte")
                return written >= 0
            }

            // Bluetooth
            val btOut = bluetoothOutputStream
            if (btOut != null) {
                btOut.write(data)
                btOut.flush()
                Log.d(TAG, "Bluetooth yazdırma: ${data.size} byte")
                return true
            }

            Log.e(TAG, "Bağlı yazıcı yok")
            false
        } catch (e: Exception) {
            Log.e(TAG, "Yazdırma hatası: ${e.message}")
            false
        }
    }

    // =========================================================================
    // Genel bağlantı kesme
    // =========================================================================

    private fun disconnect() {
        disconnectUsb()
        try {
            bluetoothOutputStream?.close()
            bluetoothSocket?.close()
        } catch (_: Exception) {}
        bluetoothOutputStream = null
        bluetoothSocket       = null
        Log.d(TAG, "Tüm yazıcı bağlantıları kesildi")
    }
}
