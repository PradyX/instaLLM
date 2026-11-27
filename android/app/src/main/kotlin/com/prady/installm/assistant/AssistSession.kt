package com.prady.installm.assistant

import android.app.assist.AssistContent
import android.app.assist.AssistStructure
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.service.voice.VoiceInteractionSession
import com.prady.installm.MainActivity

/**
 * What a summoned assistant does: opens InstaLLM in its composer, carrying the
 * screen the user summoned it from.
 *
 * That is the whole point of the assistant slot here — the user swipes up from
 * the bottom edge, the chat opens, and they ask about what they were looking
 * at. The platform hands a session the screen's view text (`AssistStructure`)
 * right after it is shown, which is what the activity reads and stages in the
 * composer.
 *
 * The platform normally shows a session's own panel above the screen, which is
 * where a voice UI would live; InstaLLM has no voice panel to show, so the
 * session starts the activity and hides at once, leaving only the app.
 */
class AssistSession(context: Context) : VoiceInteractionSession(context) {
    private val handler = Handler(Looper.getMainLooper())
    private var opened = false

    override fun onShow(args: Bundle?, showFlags: Int) {
        super.onShow(args, showFlags)
        // The screen arrives moments later through onHandleAssist. If it never
        // does — an app that blocks assist, an OEM that sends nothing — the
        // composer still opens, rather than the gesture doing nothing at all.
        handler.postDelayed({ open(null) }, ASSIST_TIMEOUT_MS)
    }

    /** Android 13 and later hand the screen over in an [AssistState]. */
    override fun onHandleAssist(state: AssistState) {
        super.onHandleAssist(state)
        open(state.assistStructure)
    }

    /** Android 12 and earlier use the older shape of the same call. */
    @Deprecated("Superseded by onHandleAssist(AssistState) on Android 13")
    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onHandleAssist(
        assistBundle: Bundle?,
        structure: AssistStructure?,
        content: AssistContent?,
    ) {
        super.onHandleAssist(assistBundle, structure, content)
        open(structure)
    }

    /** Opens the chat once, with [structure] when the screen could be read. */
    private fun open(structure: AssistStructure?) {
        if (opened) return
        opened = true
        handler.removeCallbacksAndMessages(null)
        val intent =
            Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_ASSIST
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                if (structure != null) {
                    putExtra(MainActivity.EXTRA_ASSIST_STRUCTURE, structure)
                }
            }
        // A session is not a foreground app, so a plain start would be refused
        // as a background activity launch and the chat would never appear.
        // startAssistantActivity is the platform's own door for this: it is
        // allowed from the assistant and lands above the current app.
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startAssistantActivity(intent)
            } else {
                context.startActivity(intent)
            }
        } catch (e: Exception) {
            try {
                context.startActivity(intent)
            } catch (ignored: Exception) {
                // Nothing left to try: the session hides and the next summon
                // starts over.
            }
        } finally {
            // Dismissing the session in the same breath as the launch cancels
            // the transition: the chat's task was created but never became
            // visible, and the empty session window stayed on top. Given a
            // moment, the activity takes the screen first.
            handler.postDelayed({ hide() }, HIDE_DELAY_MS)
        }
    }

    private companion object {
        const val ASSIST_TIMEOUT_MS = 1200L
        const val HIDE_DELAY_MS = 600L
    }
}
