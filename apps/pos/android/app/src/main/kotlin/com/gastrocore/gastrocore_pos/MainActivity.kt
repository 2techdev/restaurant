package com.gastrocore.gastrocore_pos

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private lateinit var printerPlugin: PrinterPlugin

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        printerPlugin = PrinterPlugin(this)
        printerPlugin.register(flutterEngine)
        flutterEngine.plugins.add(MyPosPlugin())
    }

    override fun onDestroy() {
        printerPlugin.unregister()
        super.onDestroy()
    }
}
