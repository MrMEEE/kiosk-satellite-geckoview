package com.kiosksatellite.geckoview

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import org.mozilla.geckoview.GeckoRuntime
import org.mozilla.geckoview.GeckoRuntimeSettings
import org.mozilla.geckoview.GeckoResult
import org.mozilla.geckoview.GeckoSession
import org.mozilla.geckoview.GeckoSessionSettings
import org.mozilla.geckoview.GeckoView
import org.mozilla.geckoview.WebRequestError
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream

class KioskGeckoPlatformView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    initialUrl: String?,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val bridgePrefix = "__KS_BRIDGE__"
    private val consolePrefix = "__KS_CONSOLE__"
    private val channel = MethodChannel(messenger, "kiosk_satellite/geckoview_$viewId")
    private val geckoView = GeckoView(context)
    private val runtime = runtime(context)
    private val session = GeckoSession(sessionSettings())
    private val jsHandlers = HashSet<String>()
    private var currentUrl: String? = initialUrl
    private var canNavigateBack: Boolean = false
    private var syntheticJsPageStopsPending: Int = 0

    init {
        channel.setMethodCallHandler(this)
        session.navigationDelegate = object : GeckoSession.NavigationDelegate {
            override fun onLocationChange(
                session: GeckoSession,
                url: String?,
                perms: MutableList<GeckoSession.PermissionDelegate.ContentPermission>,
                hasUserGesture: Boolean,
            ) {
                if (url.isNullOrEmpty()) return
                if (isSyntheticJavascriptUrl(url)) return
                currentUrl = url
                emitEvent(
                    "locationChanged",
                    mapOf("url" to url, "hasUserGesture" to hasUserGesture),
                )
            }

            override fun onLoadError(
                session: GeckoSession,
                uri: String?,
                error: WebRequestError,
            ): GeckoResult<String>? {
                emitEvent(
                    "loadError",
                    mapOf(
                        "url" to uri,
                        "code" to error.code,
                        "category" to error.category,
                    ),
                )
                return null
            }
        }
        session.progressDelegate = object : GeckoSession.ProgressDelegate {
            override fun onPageStart(session: GeckoSession, url: String) {
                if (isSyntheticJavascriptUrl(url)) return
                // Any real navigation invalidates stale synthetic suppression.
                syntheticJsPageStopsPending = 0
                currentUrl = url
            }

            override fun onPageStop(session: GeckoSession, success: Boolean) {
                if (syntheticJsPageStopsPending > 0) {
                    syntheticJsPageStopsPending--
                    return
                }
                if (isSyntheticJavascriptUrl(currentUrl)) return
                emitEvent(
                    "pageLoaded",
                    mapOf("url" to currentUrl, "success" to success),
                )
            }
        }
        session.historyDelegate = object : GeckoSession.HistoryDelegate {
            override fun onVisited(
                session: GeckoSession,
                url: String,
                lastVisitedURL: String?,
                flags: Int,
            ): GeckoResult<Boolean> {
                return GeckoResult.fromValue(false)
            }

            override fun getVisited(
                session: GeckoSession,
                urls: Array<out String>,
            ): GeckoResult<BooleanArray> {
                return GeckoResult.fromValue(BooleanArray(urls.size))
            }

            override fun onHistoryStateChange(
                session: GeckoSession,
                historyList: GeckoSession.HistoryDelegate.HistoryList,
            ) {
                canNavigateBack = historyList.getCurrentIndex() > 0
            }
        }
        session.promptDelegate = object : GeckoSession.PromptDelegate {
            override fun onTextPrompt(
                session: GeckoSession,
                prompt: GeckoSession.PromptDelegate.TextPrompt,
            ): GeckoResult<GeckoSession.PromptDelegate.PromptResponse>? {
                val message = prompt.message ?: return null
                if (message.startsWith(consolePrefix)) {
                    val payloadText = message.removePrefix(consolePrefix)
                    val payload = runCatching { JSONObject(payloadText) }.getOrNull()
                    if (payload != null) {
                        emitEvent(
                            "console",
                            mapOf(
                                "level" to payload.optString("level", "log"),
                                "message" to payload.optString("message", ""),
                                "source" to payload.optString("source", ""),
                                "line" to payload.optInt("line", 0),
                                "column" to payload.optInt("column", 0),
                            ),
                        )
                    }
                    return GeckoResult.fromValue(prompt.confirm(""))
                }
                if (!message.startsWith(bridgePrefix)) return null
                val payloadText = message.removePrefix(bridgePrefix)
                val payload = runCatching { JSONObject(payloadText) }.getOrNull()
                    ?: return GeckoResult.fromValue(prompt.confirm("null"))

                val name = payload.optString("name", "")
                if (name.isEmpty() || !jsHandlers.contains(name)) {
                    return GeckoResult.fromValue(prompt.confirm("null"))
                }

                val args = payload.optJSONArray("args") ?: JSONArray()
                val resultFuture = GeckoResult<GeckoSession.PromptDelegate.PromptResponse>()
                channel.invokeMethod(
                    "jsHandler",
                    mapOf(
                        "handlerName" to name,
                        "args" to jsonArrayToList(args),
                    ),
                    object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            resultFuture.complete(prompt.confirm(encodeJsonValue(result)))
                        }

                        override fun error(
                            errorCode: String,
                            errorMessage: String?,
                            errorDetails: Any?,
                        ) {
                            resultFuture.complete(prompt.confirm("null"))
                        }

                        override fun notImplemented() {
                            resultFuture.complete(prompt.confirm("null"))
                        }
                    },
                )
                return resultFuture
            }
        }
        session.open(runtime)
        geckoView.setSession(session)
        // Explicitly bind text input to this view; some API 27 devices do
        // not deliver committed text reliably without an explicit link.
        session.textInput.setView(geckoView)
        geckoView.isFocusable = true
        geckoView.isFocusableInTouchMode = true
        geckoView.setOnTouchListener { _, _ ->
            session.setActive(true)
            session.setFocused(true)
            false
        }
        geckoView.requestFocus()
        session.setActive(true)
        session.setFocused(true)
        if (!initialUrl.isNullOrBlank()) {
            session.loadUri(initialUrl)
        }
    }

    override fun getView(): View = geckoView

    override fun dispose() {
        channel.setMethodCallHandler(null)
        runCatching { session.close() }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadUrl" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrBlank()) {
                    result.error("invalid_url", "url is required", null)
                } else {
                    syntheticJsPageStopsPending = 0
                    session.loadUri(url)
                    result.success(null)
                }
            }

            "reload" -> {
                syntheticJsPageStopsPending = 0
                session.reload()
                result.success(null)
            }

            "goBack" -> {
                syntheticJsPageStopsPending = 0
                session.goBack()
                result.success(null)
            }

            "canGoBack" -> {
                result.success(canNavigateBack)
            }

            "evaluateJavascript" -> {
                val source = call.argument<String>("source")
                if (source == null) {
                    result.error("invalid_source", "source is required", null)
                } else {
                    runJavascript(source)
                    result.success(null)
                }
            }

            "pause" -> {
                geckoView.visibility = View.INVISIBLE
                session.setFocused(false)
                session.setActive(false)
                result.success(null)
            }

            "resume" -> {
                geckoView.visibility = View.VISIBLE
                geckoView.requestFocus()
                session.textInput.setView(geckoView)
                session.setActive(true)
                session.setFocused(true)
                result.success(null)
            }

            "takeScreenshot" -> {
                val quality = (call.argument<Number>("quality")?.toInt() ?: 80)
                    .coerceIn(1, 100)
                val requestedWidth = call.argument<Number>("width")?.toDouble()
                captureScreenshot(quality, requestedWidth, result)
            }

            "registerJsHandler" -> {
                val handlerName = call.argument<String>("handlerName")
                if (handlerName.isNullOrBlank()) {
                    result.error("invalid_handler", "handlerName is required", null)
                } else {
                    jsHandlers.add(handlerName)
                    injectBridge(handlerName)
                    result.success(null)
                }
            }

            "unregisterJsHandler" -> {
                val handlerName = call.argument<String>("handlerName")
                if (!handlerName.isNullOrBlank()) {
                    jsHandlers.remove(handlerName)
                }
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun injectBridge(handlerName: String) {
        val escaped = handlerName
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
        val script = """
            (function () {
              window.kiosk_geckoview = window.kiosk_geckoview || {};
              window.kiosk_geckoview.callHandler = function(name) {
                var args = Array.prototype.slice.call(arguments, 1);
                if (name !== \"$escaped\") {
                  return Promise.resolve(null);
                }
                return new Promise(function(resolve) {
                  try {
                    var payload = JSON.stringify({ name: name, args: args });
                    var response = prompt('$bridgePrefix' + payload, '');
                    resolve(response ? JSON.parse(response) : null);
                  } catch (e) {
                    resolve(null);
                  }
                });
              };
            })();
        """.trimIndent()
        runJavascript(script)
    }

    private fun runJavascript(source: String) {
        // javascript: navigations replace the current document when the
        // evaluated script returns a string. Many probes return strings
        // (for example "other"), so force an undefined result to keep the
        // current page intact.
        val wrapped = "(function(){\n$source\n})();void(0);"
        syntheticJsPageStopsPending++
        session.loadUri("javascript:" + Uri.encode(wrapped))
    }

    private fun captureScreenshot(
        quality: Int,
        requestedWidth: Double?,
        result: MethodChannel.Result,
    ) {
        geckoView.capturePixels().accept(
            { bitmap: Bitmap? ->
                if (bitmap == null) {
                    result.success(null)
                    return@accept
                }
                val scaled = maybeScaleBitmap(bitmap, requestedWidth)
                val out = ByteArrayOutputStream()
                val ok = scaled.compress(Bitmap.CompressFormat.JPEG, quality, out)
                if (scaled !== bitmap) scaled.recycle()
                if (!ok) {
                    result.success(null)
                } else {
                    result.success(out.toByteArray())
                }
            },
            {
                result.success(null)
            },
        )
    }

    private fun maybeScaleBitmap(bitmap: Bitmap, requestedWidth: Double?): Bitmap {
        val targetWidth = requestedWidth?.toInt() ?: return bitmap
        if (targetWidth <= 0 || targetWidth >= bitmap.width || bitmap.width <= 0 || bitmap.height <= 0) {
            return bitmap
        }
        val targetHeight = (bitmap.height.toFloat() * targetWidth.toFloat() / bitmap.width.toFloat())
            .toInt()
            .coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true)
    }

    private fun isSyntheticJavascriptUrl(url: String?): Boolean {
        if (url == null) return false
        return url.startsWith("javascript:", ignoreCase = true)
    }

    private fun emitEvent(name: String, payload: Map<String, Any?>) {
        channel.invokeMethod(
            "event",
            mapOf("name" to name, "payload" to payload),
        )
    }

    private fun jsonArrayToList(array: JSONArray): List<Any?> {
        val out = ArrayList<Any?>(array.length())
        for (index in 0 until array.length()) {
            out.add(jsonToAny(array.opt(index)))
        }
        return out
    }

    private fun jsonObjectToMap(obj: JSONObject): Map<String, Any?> {
        val out = LinkedHashMap<String, Any?>()
        val keys = obj.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            out[key] = jsonToAny(obj.opt(key))
        }
        return out
    }

    private fun jsonToAny(value: Any?): Any? {
        return when (value) {
            null, JSONObject.NULL -> null
            is JSONArray -> jsonArrayToList(value)
            is JSONObject -> jsonObjectToMap(value)
            else -> value
        }
    }

    private fun encodeJsonValue(value: Any?): String {
        return when (value) {
            null -> "null"
            is String -> JSONObject.quote(value)
            is Number, is Boolean -> value.toString()
            is Map<*, *> -> {
                val obj = JSONObject()
                value.forEach { (k, v) ->
                    if (k != null) obj.put(k.toString(), anyToJson(v))
                }
                obj.toString()
            }
            is List<*> -> {
                val arr = JSONArray()
                value.forEach { arr.put(anyToJson(it)) }
                arr.toString()
            }
            else -> JSONObject.quote(value.toString())
        }
    }

    private fun anyToJson(value: Any?): Any? {
        return when (value) {
            null -> JSONObject.NULL
            is Map<*, *> -> {
                val obj = JSONObject()
                value.forEach { (k, v) ->
                    if (k != null) obj.put(k.toString(), anyToJson(v))
                }
                obj
            }
            is List<*> -> {
                val arr = JSONArray()
                value.forEach { arr.put(anyToJson(it)) }
                arr
            }
            else -> value
        }
    }

    companion object {
        @Volatile
        private var sharedRuntime: GeckoRuntime? = null

        private fun runtimeSettings(): GeckoRuntimeSettings {
            val builder = GeckoRuntimeSettings.Builder()
                .javaScriptEnabled(true)
                .webFontsEnabled(true)
                .lowMemoryDetection(true)

            if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.O_MR1) {
                // API 27 devices are resource constrained; keep Gecko in the
                // app process to avoid extra child-process churn.
                builder
                    .fissionEnabled(false)
                    .isolatedProcessEnabled(false)
                    .appZygoteProcessEnabled(false)
            }
            return builder.build()
        }

        private fun sessionSettings(): GeckoSessionSettings {
            return GeckoSessionSettings.Builder()
                .allowJavascript(true)
                .useTrackingProtection(false)
                .suspendMediaWhenInactive(false)
                .build()
        }

        private fun runtime(context: Context): GeckoRuntime {
            val cached = sharedRuntime
            if (cached != null) return cached
            return synchronized(this) {
                val existing = sharedRuntime
                if (existing != null) {
                    existing
                } else {
                    GeckoRuntime.create(context.applicationContext, runtimeSettings()).also {
                        sharedRuntime = it
                    }
                }
            }
        }
    }
}
