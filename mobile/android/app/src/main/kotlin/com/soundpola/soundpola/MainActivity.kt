package com.soundpola.soundpola

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var ringBridge: RingSoundBridge? = null
    private var visualMp4Bridge: VisualMp4Bridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        ringBridge = RingSoundBridge(this, messenger)
        visualMp4Bridge = VisualMp4Bridge(messenger)
    }

    override fun onDestroy() {
        ringBridge?.dispose()
        ringBridge = null
        visualMp4Bridge?.dispose()
        visualMp4Bridge = null
        super.onDestroy()
    }
}
