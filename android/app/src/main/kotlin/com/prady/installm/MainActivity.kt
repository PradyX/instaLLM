package com.prady.installm

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
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

    // Text or a link another app sent to InstaLLM (Road Map 5 Phase 5.1).
    // Nothing is uploaded and nothing is sent to a model: the payload waits
    // here until Dart stages it in the composer, and is cleared once read.
    private val shareChannelName = "installm/share"
    private var shareChannel: MethodChannel? = null
    private var pendingSharedText: String? = null

    // The manifest alias that makes InstaLLM appear in other apps' share sheets
    // and in link handling. It ships disabled: the user turns it on in Settings
    // › Sharing, and until then this activity ignores anything shared.
    private val shareTargetComponent = "com.prady.installm.ShareTarget"

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
                    result.success(if (isShareTargetEnabled()) text else null)
                }

                "setShareTargetEnabled" -> {
                    val enabled = call.arguments as? Boolean ?: false
                    try {
                        result.success(setShareTargetEnabled(enabled))
                    } catch (e: Exception) {
                        result.error("share_target_error", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    /** True only once the user has switched sharing on. */
    private fun isShareTargetEnabled(): Boolean =
        packageManager.getComponentEnabledSetting(ComponentName(this, shareTargetComponent)) ==
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED

    /** Enables or disables the share alias and reports the state that took. */
    private fun setShareTargetEnabled(enabled: Boolean): Boolean {
        val state =
            if (enabled) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }
        packageManager.setComponentEnabledSetting(
            ComponentName(this, shareTargetComponent),
            state,
            PackageManager.DONT_KILL_APP,
        )
        return isShareTargetEnabled()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (!isShareTargetEnabled()) return
        val text = sharedTextFrom(intent) ?: return
        val channel = shareChannel
        if (channel == null) {
            pendingSharedText = text
            return
        }
        channel.invokeMethod("sharedText", text)
    }

    /**
     * What another app handed over: the text of an ACTION_SEND, or the http(s)
     * link of an ACTION_VIEW. Null when this launch carried neither.
     */
    private fun sharedTextFrom(intent: Intent?): String? {
        if (intent == null) return null

        if (intent.action == Intent.ACTION_VIEW) {
            val scheme = intent.data?.scheme?.lowercase()
            if (scheme != "http" && scheme != "https") return null
            val link = intent.dataString?.trim()
            return if (link.isNullOrEmpty()) null else link
        }

        if (intent.action != Intent.ACTION_SEND) return null
        if (!intent.type.orEmpty().startsWith("text/")) return null
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.trim()
        return if (text.isNullOrEmpty()) null else text
    }
}
