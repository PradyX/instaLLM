package com.prady.installm

import android.content.Intent
import android.os.StatFs
import com.prady.installm.tools.ToolExecutor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val storageChannel = "installm/storage_info"
    private val runtimePathsChannel = "installm/runtime_paths"
    private val toolExecutorChannel = "installm/tool_executor"
    private val toolExecutor = ToolExecutor()

    // Text another app sent through the Android share sheet (Road Map 5 Phase
    // 5.1). Nothing is uploaded and nothing is sent to a model: the text waits
    // here until Dart stages it in the composer, and is cleared once read.
    private val shareChannelName = "installm/share"
    private var shareChannel: MethodChannel? = null
    private var pendingSharedText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, storageChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStorageInfo" -> {
                        try {
                            val stat = StatFs(filesDir.absolutePath)
                            val freeBytes = stat.availableBytes
                            val totalBytes = stat.totalBytes
                            result.success(
                                mapOf(
                                    "freeBytes" to freeBytes,
                                    "totalBytes" to totalBytes,
                                ),
                            )
                        } catch (e: Exception) {
                            result.error("storage_error", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, runtimePathsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAndroidNativeLibraryDir" -> {
                        try {
                            result.success(applicationInfo.nativeLibraryDir)
                        } catch (e: Exception) {
                            result.error("runtime_paths_error", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, toolExecutorChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "execute_tool" -> {
                        val payload = call.arguments as? String
                        if (payload.isNullOrBlank()) {
                            result.error(
                                "tool_executor_error",
                                "Tool payload is required.",
                                null,
                            )
                            return@setMethodCallHandler
                        }

                        try {
                            result.success(toolExecutor.execute(this, payload))
                        } catch (e: Exception) {
                            result.error("tool_executor_error", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        val share = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName)
        shareChannel = share
        share.setMethodCallHandler { call, result ->
            when (call.method) {
                "getSharedText" -> {
                    // Handed over at most once, so a stale share cannot reappear
                    // the next time the app is opened from the launcher.
                    val text = pendingSharedText ?: sharedTextFrom(intent)
                    pendingSharedText = null
                    result.success(text)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = sharedTextFrom(intent) ?: return
        val channel = shareChannel
        if (channel == null) {
            pendingSharedText = text
            return
        }
        channel.invokeMethod("sharedText", text)
    }

    /** The text of an ACTION_SEND intent, or null when this launch is not one. */
    private fun sharedTextFrom(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_SEND) return null
        if (!intent.type.orEmpty().startsWith("text/")) return null
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.trim()
        return if (text.isNullOrEmpty()) null else text
    }
}
