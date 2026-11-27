package com.prady.installm

import android.app.role.RoleManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import java.io.File
import com.prady.installm.assistant.AssistSession
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

    // The launch intent stays attached to the activity for its whole life, and
    // it still carries the selection or share that started it. Reading it must
    // therefore happen once: a second read would stage the same text again.
    private var launchContentRead = false

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

    // Request code for the system's assistant-role prompt (API 29+).
    private val ASSISTANT_ROLE_REQUEST = 4703

    // Chat export (Road Map 5 Phase 5.0): a saved file has to be openable by
    // another program, and on Android the app's own folder is not. An export
    // therefore goes into the public Downloads collection through MediaStore
    // (no storage permission on API 29+), and this channel hands the file to
    // the app the user picks to view it.
    private val exportsChannelName = "installm/exports"

    // Ask with InstaLLM (Road Map 5 Phase 5.2): a PROCESS_TEXT launch may hand
    // the answer back to the app the text was selected in, but only when that
    // selection is editable. Null until a PROCESS_TEXT intent is read.
    private var processTextReadOnly: Boolean? = null

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
                    // the next time the app is opened from the launcher, and a
                    // selection cannot be staged twice (the launch intent keeps
                    // its extras for as long as the activity lives).
                    val content =
                        pendingSharedContent ?: if (launchContentRead) {
                            null
                        } else {
                            sharedContentFrom(intent)
                        }
                    pendingSharedContent = null
                    launchContentRead = true
                    result.success(if (isAllowed(content)) content else null)
                }

                "setShareTargetEnabled" -> {
                    val enabled = call.arguments as? Boolean ?: false
                    try {
                        result.success(setShareTargetEnabled(enabled))
                    } catch (e: Exception) {
                        result.error("share_target_error", e.message, null)
                    }
                }

                "returnProcessedText" -> {
                    val text = call.arguments as? String
                    result.success(returnProcessedText(text))
                }

                "isAssistantRoleHeld" -> result.success(isAssistantRoleHeld())

                "requestAssistantRole" -> {
                    try {
                        result.success(requestAssistantRole())
                    } catch (e: Exception) {
                        result.error("assistant_role_error", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, exportsChannelName)
            .setMethodCallHandler { call, result ->
                val args = call.arguments as? Map<*, *>
                when (call.method) {
                    "saveToDownloads" -> {
                        val name = args?.get("name") as? String
                        val mimeType = args?.get("mimeType") as? String
                        val bytes = args?.get("bytes") as? ByteArray
                        if (name == null || mimeType == null || bytes == null) {
                            result.error(
                                "export_error",
                                "An export needs a name, a type and its bytes.",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(saveExportToDownloads(name, mimeType, bytes))
                        } catch (e: Exception) {
                            result.error("export_error", e.message, null)
                        }
                    }

                    "openFile" -> {
                        val uri = args?.get("uri") as? String
                        val mimeType = args?.get("mimeType") as? String ?: "*/*"
                        if (uri == null) {
                            result.error("open_error", "A file URI is required.", null)
                            return@setMethodCallHandler
                        }
                        result.success(openExportedFile(uri, mimeType))
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Copies an export into the public Downloads collection and reports where
     * it landed.
     *
     * MediaStore is used instead of a file path because another program has to
     * be able to open what was saved: on API 29+ the insert is the app's own
     * write, so no storage permission is asked for. Null on older releases and
     * on any failure, which leaves the caller with its own exports folder.
     */
    private fun saveExportToDownloads(
        name: String,
        mimeType: String,
        bytes: ByteArray,
    ): Map<String, String>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val resolver = contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: return null
        try {
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("Downloads did not open for writing.")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            return null
        }

        // MediaStore renames a duplicate, so the name is read back rather than
        // assumed: the notice has to say where the file really is.
        var savedName = name
        resolver.query(
            uri,
            arrayOf(MediaStore.Downloads.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) savedName = cursor.getString(0) ?: name
        }
        return mapOf(
            "uri" to uri.toString(),
            "displayPath" to "Downloads/$savedName",
        )
    }

    /** Hands an exported file to another app to view, or reports that none could. */
    private fun openExportedFile(uri: String, mimeType: String): Boolean {
        val view = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(Uri.parse(uri), mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            startActivity(Intent.createChooser(view, null))
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Whether this payload may reach the composer.
     *
     * A share or a selection is gated by the Sharing switch, so an explicit
     * intent aimed straight at the activity cannot bypass it. An assistant
     * launch is not: it comes from the assistant slot the user granted in
     * system settings, which is its own decision and carries no content.
     */
    private fun isAllowed(content: Map<String, Any?>?): Boolean {
        if (content == null) return false
        if (content["assist"] == true) return true
        return isShareTargetEnabled()
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

    override fun onResume() {
        super.onResume()
        // The assistant's floating panel stays up until the chat it opened is
        // actually on screen, so dismissing it can never take the launch with
        // it.
        AssistSession.hideActive()
    }

    override fun onNewIntent(intent: Intent) {
        // Flutter hands a VIEW intent's data URI to the router as an in-app
        // route, and the app has no http(s) routes: a link that arrived while
        // the app was open landed on the not-found page instead of the
        // composer. The URI belongs to the share payload below, so the engine
        // gets a copy without it.
        val forward = Intent(intent).setData(null)
        super.onNewIntent(forward)
        setIntent(forward)
        val content = sharedContentFrom(intent)
        if (!isAllowed(content)) return
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
        processTextReadOnly = null
        if (intent == null) return null

        // An assistant launch carries what the floating composer collected: the
        // question, the screen's text, and a picture of it when the device
        // offered one. Every part is optional — an empty send still opens the
        // chat, which is what the summon alone asks for.
        if (intent.action == Intent.ACTION_ASSIST) {
            val attachments = mutableListOf<Map<String, String>>()
            assistScreenshotFrom(intent)?.let { attachments.add(it) }
            return mapOf(
                "text" to intent.getStringExtra(EXTRA_ASSIST_QUERY)?.trim()?.ifEmpty { null },
                "attachments" to attachments,
                "screenText" to intent.getStringExtra(EXTRA_ASSIST_SCREEN_TEXT)?.trim()
                    ?.ifEmpty { null },
                "unreadable" to 0,
                "assist" to true,
            )
        }

        if (intent.action == Intent.ACTION_PROCESS_TEXT) {
            val selection = processTextFrom(intent)
            if (selection == null) return null
            val readOnly = intent.getBooleanExtra(
                Intent.EXTRA_PROCESS_TEXT_READONLY,
                true,
            )
            processTextReadOnly = readOnly
            return mapOf(
                "text" to selection,
                "attachments" to emptyList<Map<String, String>>(),
                "unreadable" to 0,
                "processTextReadOnly" to readOnly,
            )
        }

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
     * The picture of the screen the session saved, described for the composer,
     * or null when there is none.
     *
     * Only a file the app itself wrote is accepted: the path arrives in an
     * intent, so it is checked for being a real, non-empty file in our own
     * storage rather than trusted to name anything.
     */
    private fun assistScreenshotFrom(intent: Intent): Map<String, String>? {
        val path = intent.getStringExtra(EXTRA_ASSIST_SCREENSHOT) ?: return null
        val staged = File(path)
        val owned = File(filesDir, stagedShareDirectoryName).absolutePath
        if (staged.parentFile?.absolutePath != owned) return null
        if (!staged.isFile || staged.length() <= 0L) return null
        return mapOf(
            "path" to staged.absolutePath,
            "mimeType" to "image/png",
            "name" to "screen.png",
        )
    }

    /**
     * The text the user selected in another app, or null.
     *
     * The platform sends one CharSequence; an app that sends several chunks
     * gets them joined with newlines rather than losing all but the first, and
     * an entry that is neither shape is skipped instead of crashing the launch.
     */
    @Suppress("DEPRECATION")
    private fun processTextFrom(intent: Intent): String? {
        val raw = try {
            intent.extras?.get(Intent.EXTRA_PROCESS_TEXT)
        } catch (e: Exception) {
            null
        }
        val chunks = when (raw) {
            null -> emptyList()
            is CharSequence -> listOf(raw.toString())
            is Array<*> -> raw.mapNotNull { (it as? CharSequence)?.toString() }
            is Iterable<*> -> raw.mapNotNull { (it as? CharSequence)?.toString() }
            else -> emptyList()
        }.map { it.trim() }.filter { it.isNotEmpty() }
        return if (chunks.isEmpty()) null else chunks.joinToString("\n")
    }

    /**
     * Hands [text] back to the app the selection came from.
     *
     * A read-only selection has no edit to make, so nothing is ever returned
     * for one: the request is refused here rather than trusted to the UI. Only
     * an editable request gets a result, and only once the app is finished.
     */
    /**
     * The app the device sends its assistant button and gesture to.
     *
     * This is the `voice_interaction_service` secure setting, which names the
     * chosen app's VoiceInteractionService. Holding `ROLE_ASSISTANT` is not the
     * same thing: the role only makes an app a candidate for the system prompt,
     * which is why summoning the assistant still showed a chooser after the
     * role was granted here.
     */
    private fun chosenAssistant(): ComponentName? {
        val value = try {
            Settings.Secure.getString(contentResolver, "voice_interaction_service")
        } catch (e: Exception) {
            null
        }
        if (value.isNullOrBlank()) return null
        return ComponentName.unflattenFromString(value)
    }

    /**
     * Whether InstaLLM is the device's assistant.
     *
     * The setting is what the assistant button follows, so it decides. Only
     * when no assistant app is recorded at all does the generic role count;
     * below Android 10 there is no role and the answer is false, which the
     * settings row explains.
     */
    private fun isAssistantRoleHeld(): Boolean {
        val chosen = chosenAssistant()
        if (chosen != null) return chosen.packageName == packageName
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        return try {
            getSystemService(RoleManager::class.java)
                ?.isRoleHeld(RoleManager.ROLE_ASSISTANT) ?: false
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Opens the system screen where the assistant app is chosen.
     *
     * Android has no per-app "become the assistant" dialog for a
     * VoiceInteractionService, so the user picks InstaLLM in the platform's own
     * Assist & voice input screen. The role prompt is kept as a fallback for a
     * device that does not offer that screen.
     */
    private fun requestAssistantRole(): Boolean {
        if (isAssistantRoleHeld()) return true
        val chooseAssistant = Intent(Settings.ACTION_VOICE_INPUT_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (packageManager.resolveActivity(chooseAssistant, 0) != null) {
            startActivityForResult(chooseAssistant, ASSISTANT_ROLE_REQUEST)
            return true
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val manager = getSystemService(RoleManager::class.java) ?: return false
        if (!manager.isRoleAvailable(RoleManager.ROLE_ASSISTANT)) return false
        startActivityForResult(
            manager.createRequestRoleIntent(RoleManager.ROLE_ASSISTANT),
            ASSISTANT_ROLE_REQUEST,
        )
        return true
    }

    private fun returnProcessedText(text: String?): Boolean {
        val readOnly = processTextReadOnly ?: return false
        if (readOnly) return false
        val processed = text?.trim()
        if (processed.isNullOrEmpty()) return false
        processTextReadOnly = null
        setResult(
            RESULT_OK,
            Intent().putExtra(Intent.EXTRA_PROCESS_TEXT, processed),
        )
        finish()
        return true
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

    companion object {
        // What the assistant's floating composer collected, handed to this
        // activity in the intent that opens it.
        const val EXTRA_ASSIST_QUERY = "com.prady.installm.extra.ASSIST_QUERY"
        const val EXTRA_ASSIST_SCREEN_TEXT = "com.prady.installm.extra.ASSIST_SCREEN_TEXT"
        const val EXTRA_ASSIST_SCREENSHOT = "com.prady.installm.extra.ASSIST_SCREENSHOT"
    }
}
