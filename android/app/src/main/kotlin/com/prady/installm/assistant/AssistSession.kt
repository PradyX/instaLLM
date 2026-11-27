package com.prady.installm.assistant

import android.app.assist.AssistContent
import android.app.assist.AssistStructure
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.service.voice.VoiceInteractionSession
import android.text.InputType
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.prady.installm.MainActivity
import java.io.File

/**
 * The floating composer a summon shows (Road Map 5 Phase 5.3).
 *
 * Swiping up from the bottom corner used to open InstaLLM and leave the app the
 * user was in, which is the wrong shape for "ask about this": the question is
 * about what is already on screen, so the question is asked there. The session
 * therefore draws its own small card over the current app — a field, the screen
 * it is about, and a send — and only a sent question moves to the chat, where a
 * reply can be read.
 *
 * The screen arrives as the text the platform captured for the assistant, and,
 * when the device offers one, as a picture. The picture is what a vision model
 * gets; the text is the fallback for every other model.
 */
class AssistSession(context: Context) : VoiceInteractionSession(context) {
    private lateinit var input: EditText
    private lateinit var contextLine: TextView
    private lateinit var preview: ImageView

    private var screenText: String? = null
    private var screenshot: Bitmap? = null
    private var sending = false

    override fun onCreate() {
        super.onCreate()
        active = this
        setContentView(buildPanel())
    }

    override fun onDestroy() {
        if (active === this) active = null
        super.onDestroy()
    }

    override fun onShow(args: Bundle?, showFlags: Int) {
        super.onShow(args, showFlags)
        // The session's own surface is not a normal window: without this the
        // field takes the first tap only to focus, and no keyboard ever opens.
        getWindow()?.window?.setSoftInputMode(
            WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or
                WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE,
        )
        input.post {
            input.requestFocus()
            val keyboard =
                context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            keyboard?.showSoftInput(input, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    /** The picture of the screen, when the device offers one. */
    override fun onHandleScreenshot(screenshot: Bitmap?) {
        super.onHandleScreenshot(screenshot)
        val picture = screenshot ?: return
        this.screenshot = picture
        preview.setImageBitmap(picture)
        preview.visibility = View.VISIBLE
        showContext("Screenshot")
    }

    /** Android 13 and later hand the screen's text over in an [AssistState]. */
    override fun onHandleAssist(state: AssistState) {
        super.onHandleAssist(state)
        readScreen(state.assistStructure)
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
        readScreen(structure)
    }

    private fun readScreen(structure: AssistStructure?) {
        if (screenText != null || structure == null) return
        screenText = screenTextFrom(structure)
        if (screenshot == null && !screenText.isNullOrBlank()) showContext("Screen text")
    }

    private fun showContext(label: String) {
        contextLine.text = label
        contextLine.visibility = View.VISIBLE
    }

    /** Opens the chat with what was typed, and whatever the screen gave us. */
    private fun send() {
        if (sending) return
        sending = true
        val intent =
            Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_ASSIST
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra(MainActivity.EXTRA_ASSIST_QUERY, input.text?.toString()?.trim().orEmpty())
                screenText?.let { putExtra(MainActivity.EXTRA_ASSIST_SCREEN_TEXT, it) }
                screenshot?.let { picture ->
                    saveScreenshot(picture)?.let {
                        putExtra(MainActivity.EXTRA_ASSIST_SCREENSHOT, it)
                    }
                }
            }
        // A session is not a foreground app, so a plain start would be refused
        // as a background activity launch and the chat would never appear.
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
                // Nothing left to try: the panel closes and the next summon
                // starts over.
            }
        }
        // The panel is not dismissed here. Hiding the session while the chat is
        // still starting takes the app's process with it — the activity and
        // this session share one — and the launch is lost. The chat dismisses
        // the panel itself once it is on screen, through hideActive().
    }

    /**
     * Writes the screen into the app's own storage and reports its path.
     *
     * The composer needs a file it owns: the platform's bitmap is gone as soon
     * as this session ends. It lands in the same folder as shared files, which
     * the activity prunes once a day.
     */
    private fun saveScreenshot(picture: Bitmap): String? {
        return try {
            val directory = File(context.filesDir, SHARED_DIRECTORY)
            if (!directory.exists() && !directory.mkdirs()) {
                null
            } else {
                val file = File(directory, "screen-${System.currentTimeMillis()}.png")
                file.outputStream().use { output ->
                    picture.compress(Bitmap.CompressFormat.PNG, 100, output)
                }
                file.absolutePath
            }
        } catch (e: Exception) {
            null
        }
    }

    /**
     * The text on the screen, bounded and de-duplicated: a screen holds far
     * more text than a prompt should carry.
     */
    private fun screenTextFrom(structure: AssistStructure): String? {
        val lines = mutableListOf<String>()
        var budget = MAX_SCREEN_TEXT_CHARS
        fun visit(node: AssistStructure.ViewNode?) {
            if (node == null || budget <= 0) return
            for (candidate in listOf(node.text, node.contentDescription)) {
                val text = candidate?.toString()?.trim().orEmpty()
                if (text.isEmpty() || lines.lastOrNull() == text) continue
                val clipped = if (text.length > budget) text.take(budget) else text
                lines.add(clipped)
                budget -= clipped.length
                if (budget <= 0) return
            }
            for (index in 0 until node.childCount) visit(node.getChildAt(index))
        }
        for (index in 0 until structure.windowNodeCount) {
            visit(structure.getWindowNodeAt(index).rootViewNode)
        }
        return lines.joinToString("\n").trim().ifEmpty { null }
    }

    /** The card: a field, what the screen gave us, and a send. */
    private fun buildPanel(): View {
        val display = context.resources.displayMetrics
        val density = display.density
        fun dp(value: Int) = (value * density).toInt()

        val dark =
            context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
                Configuration.UI_MODE_NIGHT_YES
        val cardColor = if (dark) Color.parseColor("#1C1C1E") else Color.WHITE
        val fieldColor = if (dark) Color.parseColor("#2A2A2E") else Color.parseColor("#F1F1EF")
        val textColor = if (dark) Color.parseColor("#F5F5F7") else Color.parseColor("#111113")
        val mutedColor = if (dark) Color.parseColor("#9A9AA0") else Color.parseColor("#6B6B72")
        val sendColor = if (dark) Color.parseColor("#F5F5F7") else Color.parseColor("#111113")
        val sendGlyph = if (dark) Color.parseColor("#111113") else Color.WHITE

        fun rounded(color: Int, radiusDp: Int): GradientDrawable =
            GradientDrawable().apply {
                setColor(color)
                cornerRadius = dp(radiusDp).toFloat()
            }

        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            background = rounded(cardColor, 24)
            setPadding(dp(18), dp(14), dp(18), dp(14))
        }

        val header = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val title = TextView(context).apply {
            text = "Ask InstaLLM"
            setTextColor(mutedColor)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            isAllCaps = true
            letterSpacing = 0.08f
        }
        header.addView(
            title,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
        )
        contextLine = TextView(context).apply {
            text = "Screen"
            setTextColor(mutedColor)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            visibility = View.INVISIBLE
        }
        header.addView(contextLine)
        val close = TextView(context).apply {
            text = "✕"
            setTextColor(mutedColor)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            gravity = Gravity.CENTER
            contentDescription = "Close"
            setPadding(dp(10), 0, dp(2), 0)
            setOnClickListener { hide() }
        }
        header.addView(close)
        card.addView(header)

        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.BOTTOM
        }

        preview = ImageView(context).apply {
            visibility = View.GONE
            scaleType = ImageView.ScaleType.CENTER_CROP
            background = rounded(fieldColor, 10)
            clipToOutline = true
        }
        row.addView(
            preview,
            LinearLayout.LayoutParams(dp(44), dp(44)).apply { rightMargin = dp(10) },
        )

        input = EditText(context).apply {
            hint = "Ask about this screen…"
            setHintTextColor(mutedColor)
            setTextColor(textColor)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            maxLines = 3
            background = rounded(fieldColor, 16)
            setPadding(dp(14), dp(12), dp(14), dp(12))
            imeOptions = android.view.inputmethod.EditorInfo.IME_ACTION_SEND
            setOnEditorActionListener { _, _, _ ->
                send()
                true
            }
        }
        row.addView(input, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

        val sendButton = TextView(context).apply {
            text = "↑"
            gravity = Gravity.CENTER
            setTextColor(sendGlyph)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(sendColor)
            }
            contentDescription = "Send"
            setOnClickListener { send() }
        }
        row.addView(
            sendButton,
            LinearLayout.LayoutParams(dp(44), dp(44)).apply { leftMargin = dp(10) },
        )
        card.addView(
            row,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(10) },
        )

        val root = FrameLayout(context).apply {
            // A tap that lands outside the card dismisses the panel. It cannot
            // be a plain click listener on this view: the first touch of a
            // freshly shown session is spent giving it focus, and a click
            // would close the panel the user was reaching for.
            setBackgroundColor(Color.parseColor("#26000000"))
        }
        root.setOnTouchListener { view, event ->
            if (event.action == MotionEvent.ACTION_UP) {
                val insideX = event.x >= card.left && event.x <= card.right
                val insideY = event.y >= card.top && event.y <= card.bottom
                if (!(insideX && insideY)) hide()
            }
            false
        }
        val cardParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM,
        ).apply {
            leftMargin = dp(12)
            rightMargin = dp(12)
            bottomMargin = dp(28)
        }
        root.addView(card, cardParams)
        // A tap on the card is not a tap outside it.
        card.isClickable = true
        return root
    }

    companion object {
        const val MAX_SCREEN_TEXT_CHARS = 1500
        const val SHARED_DIRECTORY = "shared"

        /** The panel that is up, if any, so the chat can dismiss it. */
        private var active: AssistSession? = null

        /**
         * Dismisses the open panel, called by the chat once it has resumed.
         *
         * Both live in the app's process, so this is a hand-off inside one
         * process rather than a second launch: the panel is only closed once
         * what it opened is actually visible, which is what keeps the launch
         * alive.
         */
        fun hideActive() {
            active?.hide()
        }
    }
}
