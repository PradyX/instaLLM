package com.prady.installm

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.StatFs
import android.provider.OpenableColumns
import java.io.File
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
    private var pendingSharedContent: Map<String, Any?>? = null

    // A shared file arrives as a content:// URI that another app may revoke at
    // any moment, so it is copied into the app's own storage before it is
    // handed to Dart. Only the kinds the composer can show and send are taken:
    // images and PDFs, at most a handful, each bounded in size.
    private val stagedShareDirectoryName = "shared"
    private val acceptedShareTypes = listOf("image/", "application/pdf")
    private val maxSharedAttachments = 4
    private val maxSharedAttachmentBytes = 32L * 1024 * 1024
    private val stagedShareLifetimeMillis = 24L * 60 * 60 * 1000

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
                "getSharedContent" -> {
                    // Handed over at most once, so a stale share cannot reappear
                    // the next time the app is opened from the launcher.
                    val content = pendingSharedContent ?: sharedContentFrom(intent)
                    pendingSharedContent = null
                    result.success(if (isShareTargetEnabled()) content else null)
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
        val content = sharedContentFrom(intent) ?: return
        val channel = shareChannel
        if (channel == null) {
            pendingSharedContent = content
            return
        }
        channel.invokeMethod("sharedContent", content)
    }

    /**
     * What another app handed over: text or a link, and any images or PDFs
     * already copied into the app's storage. Null when this launch carried
     * nothing InstaLLM can show.
     */
    private fun sharedContentFrom(intent: Intent?): Map<String, Any?>? {
        if (intent == null) return null
        val text = sharedTextFrom(intent)
        val attachments = mutableListOf<Map<String, String>>()
        val unreadable = sharedAttachmentsFrom(intent, attachments)
        if (text == null && attachments.isEmpty()) return null
        return mapOf(
            "text" to text,
            "attachments" to attachments,
            "unreadable" to unreadable,
        )
    }

    /**
     * The text of a share or the http(s) link of an ACTION_VIEW, or null. A
     * media share's caption is not treated as text: the file is the message.
     */
    private fun sharedTextFrom(intent: Intent): String? {
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

    /**
     * Copies the images and PDFs of a share into the app's own storage and
     * describes them for Dart. Anything else, anything too large and anything
     * unreadable is skipped instead of being offered and then failing.
     */
    @Suppress("DEPRECATION")
    private fun sharedAttachmentsFrom(
        intent: Intent,
        shared: MutableList<Map<String, String>>,
    ): Int {
        val uris = mutableListOf<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND ->
                (intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri)?.let {
                    uris.add(it)
                }
            Intent.ACTION_SEND_MULTIPLE ->
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let {
                    uris.addAll(it)
                }
            else -> return 0
        }
        if (uris.isEmpty()) {
            val clip = intent.clipData
            if (clip != null) {
                for (index in 0 until clip.itemCount) {
                    clip.getItemAt(index).uri?.let { uris.add(it) }
                }
            }
        }

        var unreadable = 0
        for (uri in uris) {
            if (shared.size >= maxSharedAttachments) break
            val mimeType = (contentResolver.getType(uri) ?: intent.type.orEmpty()).lowercase()
            if (acceptedShareTypes.none { mimeType.startsWith(it) }) continue
            val staged = stageSharedFile(uri, mimeType)
            if (staged == null) {
                unreadable++
                continue
            }
            shared.add(staged)
        }
        return unreadable
    }

    /** Copies one shared URI into the staged-share folder, or null. */
    private fun stageSharedFile(uri: Uri, mimeType: String): Map<String, String>? {
        return try {
            val name = sharedFileDisplayName(uri) ?: defaultSharedFileName(mimeType)
            val directory = File(filesDir, stagedShareDirectoryName)
            if (!directory.exists() && !directory.mkdirs()) return null
            pruneStagedShares(directory)

            val target = File(
                directory,
                "${System.currentTimeMillis()}-${name.replace(Regex("[^A-Za-z0-9._-]"), "_")}",
            )
            var copied = 0L
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (copied <= maxSharedAttachmentBytes) {
                        val read = input.read(buffer)
                        if (read <= 0) break
                        copied += read
                        output.write(buffer, 0, read)
                    }
                }
            } ?: return null

            if (copied <= 0L || copied > maxSharedAttachmentBytes) {
                target.delete()
                return null
            }
            mapOf(
                "path" to target.absolutePath,
                "mimeType" to mimeType,
                "name" to name,
            )
        } catch (e: Exception) {
            // Only the failure kind: the file's name and contents never go to
            // the log, and a silent no-op would leave the user guessing.
            android.util.Log.w(
                "InstaLLM",
                "Shared file could not be copied: ${e.javaClass.simpleName}",
            )
            null
        }
    }

    /** The provider's own name for the file, when it offers one. */
    private fun sharedFileDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (!cursor.moveToFirst()) return null
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index < 0) return null
                    val name = cursor.getString(index)?.trim()
                    if (name.isNullOrEmpty()) null else name
                }
        } catch (e: Exception) {
            null
        }
    }

    /** A readable name when the sharing app offers none, extension included. */
    private fun defaultSharedFileName(mimeType: String): String {
        if (!mimeType.startsWith("image/")) return "shared-document.pdf"
        val subtype = mimeType.substringAfter('/', "").trim()
        val simple = subtype.isNotEmpty() && subtype.all { it.isLetterOrDigit() }
        return if (simple) "shared-image.$subtype" else "shared-image.png"
    }

    /**
     * Removes copies an earlier share left behind. They are only ever needed
     * until the message that carries them is sent, and the chat keeps its own
     * copy from then on.
     */
    private fun pruneStagedShares(directory: File) {
        val cutoff = System.currentTimeMillis() - stagedShareLifetimeMillis
        directory.listFiles()?.forEach { file ->
            if (file.isFile && file.lastModified() < cutoff) file.delete()
        }
    }
}
