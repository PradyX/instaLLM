package com.prady.installm.assistant

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.service.voice.VoiceInteractionSession
import com.prady.installm.MainActivity

/**
 * What a summoned assistant does: opens InstaLLM in its composer.
 *
 * The platform normally shows a session's own panel above the screen, which is
 * where a voice UI would live. InstaLLM has no voice panel to show — the user
 * types or dictates in the chat itself — so the session starts the activity
 * with the assistant action and hides immediately, leaving only the app.
 */
class AssistSession(context: Context) : VoiceInteractionSession(context) {
    override fun onShow(args: Bundle?, showFlags: Int) {
        super.onShow(args, showFlags)
        val intent =
            Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_ASSIST
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
        try {
            context.startActivity(intent)
        } finally {
            hide()
        }
    }
}
