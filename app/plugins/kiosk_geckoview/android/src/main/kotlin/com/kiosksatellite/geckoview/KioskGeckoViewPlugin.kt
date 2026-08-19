package com.kiosksatellite.geckoview

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class KioskGeckoViewPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var globalChannel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        binding
            .platformViewRegistry
            .registerViewFactory("kiosk_satellite/geckoview", KioskGeckoViewFactory(binding.binaryMessenger))

        globalChannel = MethodChannel(binding.binaryMessenger, "kiosk_satellite/geckoview_global")
        globalChannel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        globalChannel?.setMethodCallHandler(null)
        globalChannel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "clearAllCache" -> {
                // GeckoView cache clearing hooks vary by runtime version.
                // Keep this non-failing during migration scaffolding.
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }
}
