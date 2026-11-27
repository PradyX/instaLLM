package com.prady.installm.assistant

import android.os.Bundle
import android.service.voice.VoiceInteractionSession
import android.service.voice.VoiceInteractionSessionService

/**
 * Creates one assistant session per summon (Road Map 5 Phase 5.3).
 *
 * The session exists only long enough to bring the chat to the front; no
 * microphone is opened and no voice-interaction loop runs.
 */
class AssistSessionService : VoiceInteractionSessionService() {
    override fun onNewSession(args: Bundle?): VoiceInteractionSession =
        AssistSession(this)
}
