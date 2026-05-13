package com.gastrocore.gastrocore_pos

import android.content.Context
import android.util.Log
import com.mypos.slavesdk.POSHandler
import java.io.File
import java.lang.reflect.Modifier
import java.net.InetSocketAddress
import java.net.Socket
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object MyPosTcpConnectionCleaner {
    private const val TAG = "MyPosTcpCleaner"
    private const val PREFS_NAME = "mypos_config"
    private const val KEY_TERMINAL_IP = "terminal_ip"
    private const val KEY_TERMINAL_PORT = "terminal_port"
    private const val KEY_LAST_LOCAL_PORT = "terminal_last_local_port"
    private const val KEY_LAST_SOCKET_SAVED_AT = "terminal_last_socket_saved_at"
    @Volatile private var deviceShutdownInProgress = false
    @Volatile private var reconnectPausedUntilMs = 0L
    @Volatile private var reflectionCompatibilityLogged = false

    fun logReflectionCompatibility(reason: String) {
        if (reflectionCompatibilityLogged) return
        reflectionCompatibilityLogged = true

        try {
            val listenClass = Class.forName("com.mypos.slavesdk.ListenTCPIPConnection")
            val requiredFields = listOf(
                "mRunning",
                "mReconnecting",
                "mConnecting",
                "mSocket",
                "mThread",
                "mIPPSlaveCommunication",
            )
            val fields = requiredFields.associateWith { name ->
                try {
                    listenClass.getDeclaredField(name)
                    true
                } catch (_: NoSuchFieldException) {
                    false
                }
            }
            val getInstanceOk = try {
                getListenTcpInstance(listenClass)
                true
            } catch (_: Exception) {
                false
            }
            val resetDataOk = try {
                listenClass.getDeclaredMethod("resetData")
                true
            } catch (_: NoSuchMethodException) {
                false
            }
            Log.d(
                TAG,
                "SDK reflection compatibility ($reason): class=true, " +
                    "getInstance=$getInstanceOk, resetData=$resetDataOk, fields=$fields"
            )
        } catch (e: Exception) {
            Log.w(TAG, "SDK reflection compatibility failed ($reason): ${e.message}")
        }
    }

    fun beginDeviceShutdown(reason: String) {
        deviceShutdownInProgress = true
        reconnectPausedUntilMs = Long.MAX_VALUE
        Log.d(TAG, "Device shutdown mode ON: $reason")
    }

    fun pauseReconnect(reason: String, durationMs: Long) {
        val until = System.currentTimeMillis() + durationMs.coerceAtLeast(0L)
        reconnectPausedUntilMs = maxOf(reconnectPausedUntilMs, until)
        Log.d(TAG, "MyPOS reconnect paused for ${durationMs}ms: $reason")
    }

    fun isDeviceShutdownInProgress(): Boolean = deviceShutdownInProgress

    fun isReconnectBlocked(): Boolean {
        return deviceShutdownInProgress || System.currentTimeMillis() < reconnectPausedUntilMs
    }

    fun closeGracefullyForShutdown(
        reason: String,
        settleMs: Long = 2_500L,
        context: Context? = null,
    ) {
        Log.d(TAG, "MyPOS TCP graceful shutdown cleanup start: $reason")
        appendShutdownTrace(context, "START graceful cleanup: $reason")

        try {
            val listenClass = Class.forName("com.mypos.slavesdk.ListenTCPIPConnection")
            val instance = getListenTcpInstance(listenClass)
            appendShutdownTrace(context, "Reflection OK: ListenTCPIPConnection/getInstance")

            // Planned device shutdown/reboot must look like a normal client
            // disconnect to Sigma. A hard RST can be treated as a network drop
            // by POSLink, while FIN makes it return to Waiting for Connection.
            setBooleanField(listenClass, instance, "mRunning", false)
            setBooleanField(listenClass, instance, "mReconnecting", false)
            setBooleanField(listenClass, instance, "mConnecting", false)
            appendShutdownTrace(context, "SDK reconnect flags cleared")

            val socket = getField(listenClass, instance, "mSocket") as? Socket
            appendShutdownTrace(context, socketLabel(socket, "Socket before graceful close"))
            rememberSocketEndpoint(context, socket, "before graceful close: $reason")
            closeSocketGracefully(socket, context)
            setBooleanField(listenClass, instance, "mRunning", false)
            setBooleanField(listenClass, instance, "mReconnecting", false)
            setBooleanField(listenClass, instance, "mConnecting", false)
            appendShutdownTrace(context, "SDK reconnect flags re-cleared after socket close")

            val thread = getField(listenClass, instance, "mThread") as? Thread
            try {
                thread?.javaClass?.getDeclaredMethod("cancel")?.apply {
                    isAccessible = true
                    invoke(thread)
                }
                appendShutdownTrace(context, "SDK TCP thread cancel invoked")
            } catch (e: Exception) {
                Log.w(TAG, "Thread cancel failed: ${e.message}")
                appendShutdownTrace(context, "WARN thread cancel failed: ${e.message}")
            }
            try {
                thread?.interrupt()
                appendShutdownTrace(context, "SDK TCP thread interrupt invoked")
            } catch (_: Exception) {}

            setObjectField(listenClass, instance, "mSocket", null)
            setObjectField(listenClass, instance, "mThread", null)
            setObjectField(listenClass, instance, "mIPPSlaveCommunication", null)
            appendShutdownTrace(context, "SDK TCP fields nulled")
        } catch (e: Exception) {
            Log.w(TAG, "ListenTCPIP graceful cleanup failed: ${e.message}")
            appendShutdownTrace(context, "ERROR graceful cleanup failed: ${e.javaClass.simpleName}: ${e.message}")
            resetViaPublicSdk(context, "graceful fallback after reflection failure: $reason")
        }

        clearSdkBusyFlags()
        appendShutdownTrace(context, "SDK busy flags cleared")

        if (settleMs > 0) {
            try {
                Thread.sleep(settleMs)
            } catch (_: InterruptedException) {}
        }

        Log.d(TAG, "MyPOS TCP graceful shutdown cleanup done: $reason")
        appendShutdownTrace(context, "DONE graceful cleanup: $reason")
    }

    fun close(reason: String, settleMs: Long = 0L, context: Context? = null) {
        Log.d(TAG, "MyPOS TCP cleanup start: $reason")

        try {
            val listenClass = Class.forName("com.mypos.slavesdk.ListenTCPIPConnection")
            val instance = getListenTcpInstance(listenClass)

            // Stop SDK auto-reconnect before closing the socket. Otherwise the
            // SDK can reconnect during Android shutdown and Sigma remains busy.
            setBooleanField(listenClass, instance, "mRunning", false)
            setBooleanField(listenClass, instance, "mReconnecting", false)
            setBooleanField(listenClass, instance, "mConnecting", false)

            val thread = getField(listenClass, instance, "mThread") as? Thread
            try {
                thread?.javaClass?.getDeclaredMethod("cancel")?.apply {
                    isAccessible = true
                    invoke(thread)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Thread cancel failed: ${e.message}")
            }
            try {
                thread?.interrupt()
            } catch (_: Exception) {}

            val socket = getField(listenClass, instance, "mSocket") as? Socket
            rememberSocketEndpoint(context, socket, "before reset close: $reason")
            closeSocketWithReset(socket)

            setObjectField(listenClass, instance, "mSocket", null)
            setObjectField(listenClass, instance, "mThread", null)
            setObjectField(listenClass, instance, "mIPPSlaveCommunication", null)

            // resetData() is still useful for SDK internal cleanup, but only
            // after we already sent RST and stopped reconnect flags.
            try {
                listenClass.getDeclaredMethod("resetData").apply {
                    isAccessible = true
                    invoke(instance)
                }
            } catch (e: Exception) {
                Log.w(TAG, "resetData failed: ${e.message}")
            }
        } catch (e: Exception) {
            Log.w(TAG, "ListenTCPIP cleanup failed: ${e.message}")
            resetViaPublicSdk(context, "reset fallback after reflection failure: $reason")
        }

        clearSdkBusyFlags()

        if (settleMs > 0) {
            try {
                Thread.sleep(settleMs)
            } catch (_: InterruptedException) {}
        }

        Log.d(TAG, "MyPOS TCP cleanup done: $reason")
    }

    fun rememberActiveSocketEndpoint(context: Context?, reason: String) {
        if (context == null) return
        try {
            val listenClass = Class.forName("com.mypos.slavesdk.ListenTCPIPConnection")
            val instance = getListenTcpInstance(listenClass)
            val socket = getField(listenClass, instance, "mSocket") as? Socket
            rememberSocketEndpoint(context, socket, reason)
        } catch (e: Exception) {
            Log.w(TAG, "Remember active socket failed: ${e.message}")
        }
    }

    fun breakStaleSigmaSessionFromPrefs(
        context: Context,
        reason: String,
        attempts: Int = 6,
        initialDelayMs: Long = 3_000L,
        intervalMs: Long = 2_000L,
    ) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val ip = prefs.getString(KEY_TERMINAL_IP, null)
        val port = prefs.getInt(KEY_TERMINAL_PORT, 60180)
        val lastLocalPort = prefs.getInt(KEY_LAST_LOCAL_PORT, -1)
        breakStaleSigmaSessionAsync(
            ip,
            port,
            reason,
            attempts,
            initialDelayMs,
            intervalMs,
            preferredLocalPort = lastLocalPort.takeIf { it in 1024..65535 },
        )
    }

    fun breakStaleSigmaSessionAsync(
        ip: String?,
        port: Int,
        reason: String,
        attempts: Int = 3,
        initialDelayMs: Long = 0L,
        intervalMs: Long = 750L,
        preferredLocalPort: Int? = null,
    ) {
        if (ip.isNullOrBlank()) {
            Log.d(TAG, "Stale breaker skipped, terminal IP empty: $reason")
            return
        }

        Thread({
            if (initialDelayMs > 0) {
                try {
                    Thread.sleep(initialDelayMs)
                } catch (_: InterruptedException) {
                    return@Thread
                }
            }

            repeat(attempts.coerceAtLeast(1)) { index ->
                val ok = sendRawResetProbe(
                    ip,
                    port,
                    reason,
                    index + 1,
                    attempts,
                    preferredLocalPort,
                )
                if (!ok && preferredLocalPort != null) {
                    sendRawResetProbe(ip, port, "$reason fallback random-port", index + 1, attempts, null)
                }
                if (index < attempts - 1) {
                    try {
                        Thread.sleep(intervalMs)
                    } catch (_: InterruptedException) {
                        return@Thread
                    }
                }
            }
        }, "mypos-stale-session-breaker").start()
    }

    private fun sendRawResetProbe(
        ip: String,
        port: Int,
        reason: String,
        attempt: Int,
        attempts: Int,
        preferredLocalPort: Int? = null,
    ): Boolean {
        var socket: Socket? = null
        try {
            socket = Socket()
            socket.reuseAddress = true
            socket.tcpNoDelay = true
            socket.setSoLinger(true, 0)
            if (preferredLocalPort != null) {
                socket.bind(InetSocketAddress(preferredLocalPort))
            }
            socket.connect(InetSocketAddress(ip, port), 1_500)
            socket.close()
            Log.d(
                TAG,
                "Stale Sigma session breaker RST sent ($attempt/$attempts) " +
                    "${localPortLabel(preferredLocalPort)}$ip:$port reason=$reason"
            )
            return true
        } catch (e: Exception) {
            Log.w(
                TAG,
                "Stale Sigma session breaker failed ($attempt/$attempts) " +
                    "${localPortLabel(preferredLocalPort)}$ip:$port reason=$reason: ${e.message}"
            )
            try {
                socket?.close()
            } catch (_: Exception) {}
            return false
        }
    }

    private fun rememberSocketEndpoint(context: Context?, socket: Socket?, reason: String) {
        if (context == null || socket == null || socket.isClosed) return
        try {
            val localPort = socket.localPort
            val remoteIp = socket.inetAddress?.hostAddress
            val remotePort = socket.port
            if (localPort !in 1024..65535 || remoteIp.isNullOrBlank() || remotePort <= 0) return

            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_TERMINAL_IP, remoteIp)
                .putInt(KEY_TERMINAL_PORT, remotePort)
                .putInt(KEY_LAST_LOCAL_PORT, localPort)
                .putLong(KEY_LAST_SOCKET_SAVED_AT, System.currentTimeMillis())
                .apply()

            Log.d(
                TAG,
                "Remembered MyPOS TCP endpoint localPort=$localPort remote=$remoteIp:$remotePort reason=$reason"
            )
        } catch (e: Exception) {
            Log.w(TAG, "Remember socket endpoint failed: ${e.message}")
        }
    }

    private fun localPortLabel(port: Int?): String {
        return if (port != null) "localPort=$port -> " else ""
    }

    private fun getListenTcpInstance(listenClass: Class<*>): Any {
        val getInstance = try {
            listenClass.getDeclaredMethod("getInstance")
        } catch (_: NoSuchMethodException) {
            listenClass.declaredMethods.firstOrNull { method ->
                method.parameterTypes.isEmpty() &&
                    Modifier.isStatic(method.modifiers) &&
                    method.returnType == listenClass
            } ?: throw NoSuchMethodException("${listenClass.name}.getInstance or static singleton accessor")
        }
        getInstance.isAccessible = true
        return getInstance.invoke(null)
            ?: throw IllegalStateException("${listenClass.name}.getInstance returned null")
    }

    private fun resetViaPublicSdk(context: Context?, reason: String): Boolean {
        return try {
            POSHandler.getInstance().resetTcpConnection()
            Log.d(TAG, "Public SDK resetTcpConnection invoked: $reason")
            appendShutdownTrace(context, "Public SDK resetTcpConnection invoked: $reason")
            true
        } catch (e: Exception) {
            Log.w(TAG, "Public SDK resetTcpConnection failed: ${e.message}")
            appendShutdownTrace(
                context,
                "ERROR public SDK resetTcpConnection failed: ${e.javaClass.simpleName}: ${e.message}"
            )
            false
        }
    }

    private fun socketLabel(socket: Socket?, prefix: String): String {
        if (socket == null) return "$prefix: null"
        return try {
            "$prefix: local=${socket.localAddress?.hostAddress}:${socket.localPort} " +
                "remote=${socket.inetAddress?.hostAddress}:${socket.port} " +
                "connected=${socket.isConnected} closed=${socket.isClosed} " +
                "inputShutdown=${socket.isInputShutdown} outputShutdown=${socket.isOutputShutdown}"
        } catch (e: Exception) {
            "$prefix: inspect failed ${e.message}"
        }
    }

    private fun appendShutdownTrace(context: Context?, message: String) {
        if (context == null) return
        val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US).format(Date())
        val line = "$timestamp $message\n"

        val targets = listOfNotNull(
            File("/storage/emulated/0/log2tech/mypos_shutdown.log"),
            context.getExternalFilesDir(null)?.let { File(it, "log2tech/mypos_shutdown.log") },
            File(context.filesDir, "log2tech/mypos_shutdown.log"),
        )

        for (target in targets) {
            try {
                target.parentFile?.mkdirs()
                target.appendText(line)
                return
            } catch (_: Exception) {
                // Try the next location.
            }
        }
    }

    private fun closeSocketWithReset(socket: Socket?) {
        if (socket == null) {
            Log.d(TAG, "Socket null")
            return
        }

        if (socket.isClosed) {
            Log.d(TAG, "Socket already closed")
            return
        }

        try {
            socket.setSoLinger(true, 0)
        } catch (e: Exception) {
            Log.w(TAG, "setSoLinger failed: ${e.message}")
        }

        try {
            socket.close()
            Log.d(TAG, "TCP RST sent (SO_LINGER=0)")
        } catch (e: Exception) {
            Log.w(TAG, "Socket close failed: ${e.message}")
        }
    }

    private fun closeSocketGracefully(socket: Socket?, context: Context?) {
        if (socket == null) {
            Log.d(TAG, "Graceful socket null")
            appendShutdownTrace(context, "Graceful socket null")
            return
        }

        if (socket.isClosed) {
            Log.d(TAG, "Graceful socket already closed")
            appendShutdownTrace(context, "Graceful socket already closed")
            return
        }

        try {
            socket.setSoLinger(false, 0)
            appendShutdownTrace(context, "SO_LINGER disabled for FIN close")
        } catch (e: Exception) {
            Log.w(TAG, "disable SO_LINGER failed: ${e.message}")
            appendShutdownTrace(context, "WARN disable SO_LINGER failed: ${e.message}")
        }

        try {
            socket.shutdownOutput()
            Log.d(TAG, "TCP FIN sent (shutdownOutput)")
            appendShutdownTrace(context, "TCP FIN sent (shutdownOutput)")
            Thread.sleep(700L)
        } catch (e: Exception) {
            Log.w(TAG, "shutdownOutput failed: ${e.message}")
            appendShutdownTrace(context, "WARN shutdownOutput failed: ${e.javaClass.simpleName}: ${e.message}")
        }

        try {
            socket.close()
            Log.d(TAG, "TCP socket closed gracefully")
            appendShutdownTrace(context, "TCP socket closed gracefully")
        } catch (e: Exception) {
            Log.w(TAG, "Graceful socket close failed: ${e.message}")
            appendShutdownTrace(context, "WARN graceful socket close failed: ${e.javaClass.simpleName}: ${e.message}")
        }
    }

    private fun clearSdkBusyFlags() {
        try {
            val utilsClass = Class.forName("com.mypos.slavesdk.Utils")
            setStaticBooleanField(utilsClass, "mTransactionInProgress", false)
            setStaticBooleanField(utilsClass, "mTerminalReady", false)
        } catch (e: Exception) {
            Log.w(TAG, "SDK busy flag cleanup failed: ${e.message}")
        }
    }

    private fun getField(clazz: Class<*>, instance: Any, name: String): Any? {
        return clazz.getDeclaredField(name).apply { isAccessible = true }.get(instance)
    }

    private fun setObjectField(clazz: Class<*>, instance: Any, name: String, value: Any?) {
        try {
            clazz.getDeclaredField(name).apply { isAccessible = true }.set(instance, value)
        } catch (e: Exception) {
            Log.w(TAG, "Set $name failed: ${e.message}")
        }
    }

    private fun setBooleanField(clazz: Class<*>, instance: Any, name: String, value: Boolean) {
        try {
            clazz.getDeclaredField(name).apply { isAccessible = true }.setBoolean(instance, value)
        } catch (e: Exception) {
            Log.w(TAG, "Set $name failed: ${e.message}")
        }
    }

    private fun setStaticBooleanField(clazz: Class<*>, name: String, value: Boolean) {
        try {
            clazz.getDeclaredField(name).apply { isAccessible = true }.setBoolean(null, value)
        } catch (e: Exception) {
            Log.w(TAG, "Set static $name failed: ${e.message}")
        }
    }
}
