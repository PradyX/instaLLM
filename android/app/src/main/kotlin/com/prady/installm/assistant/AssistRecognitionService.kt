package com.prady.installm.assistant

import android.content.Intent
import android.speech.RecognitionService
import android.speech.SpeechRecognizer

/**
 * A recogniser that never listens (Road Map 5 Phase 5.3).
 *
 * `voice_interaction_service.xml` names this service because the platform
 * expects an assistant to describe how it takes speech, and a device's assistant
 * picker is strict about a service whose metadata leaves it out. Nothing here
 * records anything: every request is refused at once, and dictation continues
 * to go through the chat's own microphone, which the user starts themselves.
 */
class AssistRecognitionService : RecognitionService() {
    override fun onStartListening(recognizerIntent: Intent, listener: Callback) {
        listener.error(SpeechRecognizer.ERROR_CLIENT)
    }

    override fun onStopListening(listener: Callback) = Unit

    override fun onCancel(listener: Callback) = Unit
}
