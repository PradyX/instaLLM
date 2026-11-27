package com.prady.installm.assistant

import android.service.voice.VoiceInteractionService

/**
 * The device's assistant entry point (Road Map 5 Phase 5.3).
 *
 * Android's assistant button and gesture are routed to the app chosen as the
 * device's *voice interaction service*, not to whichever app holds the generic
 * `ROLE_ASSISTANT` role: the role alone only makes an app a candidate for the
 * system prompt, so summoning the assistant kept showing the system chooser
 * instead of opening InstaLLM.
 *
 * Nothing is recorded here: no audio session is ever started, and the service
 * does nothing on its own. Its only job is to be listed under Settings ›
 * Default apps › Digital assistant app, where the user picks it, and to let the
 * session below open the chat composer.
 */
class AssistService : VoiceInteractionService()
