package com.example.drive_shuffle_player

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.ComponentName
import android.content.Context
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.Rational
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.HttpDataSource
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import kotlin.math.roundToInt

class PlayerActivity : Activity() {
    private lateinit var playerView: PlayerView
    private lateinit var controls: FrameLayout
    private lateinit var topBar: LinearLayout
    private lateinit var bottomPanel: LinearLayout
    private lateinit var centerPlayButton: IconGlassButton
    private lateinit var lockButton: IconGlassButton
    private lateinit var unlockOverlay: FrameLayout
    private lateinit var titleText: TextView
    private lateinit var positionText: TextView
    private lateinit var durationText: TextView
    private lateinit var resizeButton: TextView
    private lateinit var speedButton: TextView
    private lateinit var quickRow: LinearLayout
    private lateinit var progressView: PlayerProgressView
    private lateinit var hintText: TextView
    private lateinit var overlay: LinearLayout
    private lateinit var overlayText: TextView
    private lateinit var panelScrim: FrameLayout
    private lateinit var gestureDetector: GestureDetector
    private lateinit var controllerFuture: ListenableFuture<MediaController>

    private val handler = Handler(Looper.getMainLooper())
    private var controller: MediaController? = null
    private var resizeModeIndex = 0
    private var playbackSpeed = 1.0f
    private var controlsVisible = true
    private var userSeeking = false
    private var playbackErrorMessage: String? = null
    private var locked = false
    private var inPip = false
    private var pendingUnlock = false
    private var controlsOnRight = true
    private var activityResumed = false
    private var progressUpdatesRunning = false

    private val resizeModes = intArrayOf(
        AspectRatioFrameLayout.RESIZE_MODE_FIT,
        AspectRatioFrameLayout.RESIZE_MODE_FILL,
        AspectRatioFrameLayout.RESIZE_MODE_ZOOM,
    )
    private val resizeModeLabels = arrayOf("\uB9DE\uCDA4", "\uCC44\uC6C0", "\uD655\uB300")

    private val hideHintRunnable = Runnable { hintText.visibility = View.GONE }
    private val hideControlsRunnable = Runnable { setControlsVisible(false) }
    private val hideUnlockOverlayRunnable = Runnable {
        if (locked && !pendingUnlock) {
            unlockOverlay.visibility = View.GONE
        }
    }
    private val unlockRunnable = Runnable {
        if (pendingUnlock) {
            locked = false
            pendingUnlock = false
            handler.removeCallbacks(hideUnlockOverlayRunnable)
            unlockOverlay.visibility = View.GONE
            setControlsVisible(true)
            showHint("잠금 해제")
        }
    }
    private val progressRunnable = object : Runnable {
        override fun run() {
            if (!progressUpdatesRunning) return
            updateControls()
            handler.postDelayed(this, progressUpdateDelayMs())
        }
    }

    private val playerListener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            Log.d(TAG, "state=$playbackState count=${controller?.mediaItemCount}")
            updateOverlay()
            updateControls()
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            updateControls()
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            Log.d(TAG, "mediaItem=${mediaItem?.mediaId} reason=$reason")
            playbackErrorMessage = null
            updateOverlay()
            updateControls()
        }

        override fun onPlayerError(error: PlaybackException) {
            val detail = error.cause?.message ?: error.message ?: error.errorCodeName
            Log.d(TAG, "error=${error.errorCodeName}: $detail", error)
            val httpStatus = httpStatusCodeFor(error)
            val authError = httpStatus == 401 || httpStatus == 403 ||
                error.errorCodeName.contains("IO_BAD_HTTP_STATUS")
            PlaybackAuth.authError = authError
            PlaybackAuth.lastHttpStatusCode = httpStatus
            playbackErrorMessage =
                if (authError) {
                    "Drive 인증을 갱신하는 중입니다..."
                } else {
                    "재생 오류\n${error.errorCodeName}"
                }
            showOverlay(playbackErrorMessage.orEmpty())
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        hideSystemBars()
        setContentView(buildContentView())
        showOverlay("플레이어 연결 중...")

        val sessionToken = SessionToken(this, ComponentName(this, PlaybackService::class.java))
        controllerFuture = MediaController.Builder(this, sessionToken).buildAsync()
        controllerFuture.addListener(
            {
                try {
                    val mediaController = controllerFuture.get()
                    runOnUiThread {
                        controller = mediaController
                        playerView.player = mediaController
                        mediaController.addListener(playerListener)
                        updateOverlay()
                        updateControls()
                        if (activityResumed) startProgressUpdates()
                    }
                } catch (error: Throwable) {
                    Log.d(TAG, "controller connection failed", error)
                    runOnUiThread {
                        showOverlay("플레이어를 열 수 없습니다.")
                    }
                }
            },
            MoreExecutors.directExecutor(),
        )
    }

    override fun onResume() {
        super.onResume()
        activityResumed = true
        if (controller != null) startProgressUpdates()
    }

    override fun onPause() {
        stopProgressUpdates()
        activityResumed = false
        super.onPause()
    }

    override fun onDestroy() {
        handler.removeCallbacks(hideHintRunnable)
        handler.removeCallbacks(hideControlsRunnable)
        handler.removeCallbacks(hideUnlockOverlayRunnable)
        handler.removeCallbacks(unlockRunnable)
        stopProgressUpdates()
        controller?.removeListener(playerListener)
        playerView.player = null
        MediaController.releaseFuture(controllerFuture)
        super.onDestroy()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (controller?.mediaItemCount ?: 0 > 0) {
            enterPipMode()
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        inPip = isInPictureInPictureMode
        if (inPip) {
            controls.visibility = View.GONE
            panelScrim.visibility = View.GONE
            hintText.visibility = View.GONE
            overlay.visibility = View.GONE
            unlockOverlay.visibility = View.GONE
        } else {
            setControlsVisible(false)
            updateOverlay()
        }
    }

    private fun buildContentView(): View {
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
        }
        gestureDetector = GestureDetector(this, PlayerGestureListener())

        playerView = PlayerView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
            useController = false
            resizeMode = resizeModes[resizeModeIndex]
            setShowBuffering(PlayerView.SHOW_BUFFERING_NEVER)
            keepScreenOn = true
            setOnTouchListener { _, event ->
                if (locked) {
                    if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                        showUnlockOverlayTemporarily()
                    }
                    return@setOnTouchListener true
                }
                if (inPip) return@setOnTouchListener true
                gestureDetector.onTouchEvent(event)
                true
            }
        }

        hintText = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 17f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(dp(22), dp(12), dp(22), dp(12))
            background = pillBackground(Color.argb(205, 26, 26, 28))
            visibility = View.GONE
        }

        overlayText = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 18f
            gravity = Gravity.CENTER
            setPadding(dp(32), dp(16), dp(32), dp(16))
            includeFontPadding = false
        }
        overlay = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.argb(118, 0, 0, 0))
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
            addView(overlayText)
        }

        controls = buildControls()
        panelScrim = buildPanelScrim()
        unlockOverlay = buildUnlockOverlay()

        root.addView(playerView)
        root.addView(controls)
        root.addView(
            hintText,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER,
            ),
        )
        root.addView(overlay)
        root.addView(panelScrim)
        root.addView(unlockOverlay)
        scheduleHideControls()
        return root
    }

    private fun buildControls(): FrameLayout {
        titleText = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            maxLines = 1
            setPadding(dp(10), 0, dp(10), 0)
            includeFontPadding = false
        }
        positionText = timeText("00:00")
        durationText = timeText("00:00")
        centerPlayButton = IconGlassButton(this, ICON_PLAY, strong = true).apply {
            setOnClickListener { safeAction { togglePlayPause() } }
        }
        lockButton = IconGlassButton(this, ICON_LOCK).apply {
            setOnClickListener { safeAction { lockPlayer() } }
        }
        progressView = PlayerProgressView(this).apply {
            onSeekStarted = {
                userSeeking = true
                setControlsVisible(true)
            }
            onSeekChanged = { fraction ->
                val mediaController = controller
                val duration = mediaController?.duration?.takeIf { it > 0 }
                if (mediaController != null && duration != null) {
                    mediaController.seekTo((duration * fraction).toLong().coerceIn(0L, duration))
                }
            }
            onSeekFinished = {
                userSeeking = false
                scheduleHideControls()
            }
        }

        topBar = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(18), dp(16), dp(18), dp(28))
            background = verticalGradient(Color.argb(196, 0, 0, 0), Color.TRANSPARENT)
            addView(IconGlassButton(this@PlayerActivity, ICON_BACK).apply {
                setOnClickListener { finish() }
            }, LinearLayout.LayoutParams(dp(52), dp(52)))
            addView(titleText, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            addView(lockButton, LinearLayout.LayoutParams(dp(52), dp(52)))
            addView(space(10))
            addView(IconGlassButton(this@PlayerActivity, ICON_MENU).apply {
                setOnClickListener { safeAction { showPlayerOptionsPanel() } }
            }, LinearLayout.LayoutParams(dp(52), dp(52)))
        }

        val centerLayer = FrameLayout(this).apply {
            addView(
                centerPlayButton,
                FrameLayout.LayoutParams(dp(82), dp(82), Gravity.CENTER),
            )
        }

        val timeRow = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(18), 0, dp(18), 0)
            addView(positionText, LinearLayout.LayoutParams(dp(70), LinearLayout.LayoutParams.WRAP_CONTENT))
            addView(progressView, LinearLayout.LayoutParams(0, dp(36), 1f))
            addView(durationText, LinearLayout.LayoutParams(dp(70), LinearLayout.LayoutParams.WRAP_CONTENT))
        }

        resizeButton = pillButton(resizeModeLabels[resizeModeIndex]) { cycleResizeMode() }
        speedButton = pillButton(formatSpeedLabel()) { showSpeedPanel() }

        quickRow = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL or Gravity.END
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(18), dp(8), dp(18), dp(18))
        }
        renderQuickRow()

        bottomPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(42), 0, 0)
            background = verticalGradient(Color.TRANSPARENT, Color.argb(224, 0, 0, 0))
            addView(timeRow)
            addView(quickRow)
        }

        return FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
            addView(
                topBar,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    Gravity.TOP,
                ),
            )
            addView(
                centerLayer,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
            addView(
                bottomPanel,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    Gravity.BOTTOM,
                ),
            )
        }
    }

    private fun renderQuickRow() {
        quickRow.removeAllViews()
        if (controlsOnRight) {
            addSwapButton()
            quickRow.addView(View(this), LinearLayout.LayoutParams(0, 1, 1f))
            addQuickActions()
        } else {
            addQuickActions()
            quickRow.addView(View(this), LinearLayout.LayoutParams(0, 1, 1f))
            addSwapButton()
        }
    }

    private fun addQuickActions() {
        quickRow.addView(IconGlassButton(this, ICON_PREVIOUS).apply {
            setOnClickListener { safeAction { controller?.seekToPreviousMediaItem() } }
        }, LinearLayout.LayoutParams(dp(48), dp(48)))
        quickRow.addView(space(8))
        quickRow.addView(IconGlassButton(this, ICON_NEXT).apply {
            setOnClickListener { safeAction { controller?.seekToNextMediaItem() } }
        }, LinearLayout.LayoutParams(dp(48), dp(48)))
        quickRow.addView(space(8))
        quickRow.addView(resizeButton)
        quickRow.addView(space(8))
        quickRow.addView(speedButton)
        quickRow.addView(space(8))
        quickRow.addView(IconGlassButton(this, ICON_PIP).apply {
            setOnClickListener { safeAction { enterPipMode() } }
        }, LinearLayout.LayoutParams(dp(52), dp(48)))
    }

    private fun addSwapButton() {
        quickRow.addView(IconGlassButton(this, ICON_SWAP_CONTROLS).apply {
            setOnClickListener {
                if (locked || inPip) return@setOnClickListener
                controlsOnRight = !controlsOnRight
                renderQuickRow()
                setControlsVisible(true)
                scheduleHideControls()
            }
        }, LinearLayout.LayoutParams(dp(52), dp(48)))
    }

    private fun buildUnlockOverlay(): FrameLayout {
        val hint = TextView(this).apply {
            text = "잠금 중 · 버튼을 길게 눌러 해제"
            setTextColor(Color.WHITE)
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            includeFontPadding = false
            setPadding(dp(14), 0, dp(14), 0)
            background = pillBackground(Color.argb(150, 26, 26, 28))
        }
        val unlockButton = IconGlassButton(this, ICON_UNLOCK, strong = true).apply {
            setOnTouchListener { _, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        pendingUnlock = true
                        handler.postDelayed(unlockRunnable, 1500)
                        true
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        if (pendingUnlock) {
                            pendingUnlock = false
                            handler.removeCallbacks(unlockRunnable)
                            showHint("길게 눌러 잠금 해제")
                            showUnlockOverlayTemporarily()
                        }
                        true
                    }
                    else -> true
                }
            }
        }
        return FrameLayout(this).apply {
            visibility = View.GONE
            isClickable = true
            setOnClickListener {
                if (locked) showUnlockOverlayTemporarily()
            }
            addView(
                hint,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    dp(38),
                    Gravity.TOP or Gravity.CENTER_HORIZONTAL,
                ).apply { topMargin = dp(20) },
            )
            addView(
                unlockButton,
                FrameLayout.LayoutParams(dp(56), dp(56), Gravity.TOP or Gravity.END)
                    .apply {
                        topMargin = dp(14)
                        rightMargin = dp(18)
                    },
            )
        }
    }

    private fun buildPanelScrim(): FrameLayout {
        return FrameLayout(this).apply {
            visibility = View.GONE
            setBackgroundColor(Color.argb(72, 0, 0, 0))
            setOnClickListener { hidePanel() }
        }
    }

    private fun timeText(textValue: String): TextView {
        return TextView(this).apply {
            text = textValue
            setTextColor(Color.WHITE)
            textSize = 13f
            gravity = Gravity.CENTER
            typeface = Typeface.MONOSPACE
            isSingleLine = true
            includeFontPadding = false
        }
    }

    private fun pillButton(label: String, action: () -> Unit): TextView {
        return TextView(this).apply {
            text = label
            setTextColor(Color.WHITE)
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            minWidth = dp(70)
            minHeight = dp(48)
            setPadding(dp(14), 0, dp(14), 0)
            includeFontPadding = false
            background = glassPillBackground()
            setOnClickListener { safeAction(action) }
        }
    }

    private fun safeAction(action: () -> Unit) {
        if (locked || inPip) return
        action()
        setControlsVisible(true)
        scheduleHideControls()
    }

    private fun space(widthDp: Int): View {
        return View(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(widthDp), 1)
        }
    }

    private fun pillBackground(color: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(999).toFloat()
            setColor(color)
        }
    }

    private fun glassPillBackground(): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(999).toFloat()
            setColor(Color.argb(118, 18, 18, 20))
            setStroke(dp(1), Color.argb(56, 255, 255, 255))
        }
    }

    private fun glassPanelBackground(): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(26).toFloat()
            setColor(Color.argb(232, 18, 18, 20))
            setStroke(dp(1), Color.argb(40, 255, 255, 255))
        }
    }

    private fun verticalGradient(top: Int, bottom: Int): GradientDrawable {
        return GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, intArrayOf(top, bottom))
    }

    private fun httpStatusCodeFor(error: Throwable?): Int? {
        var current = error
        while (current != null) {
            if (current is HttpDataSource.InvalidResponseCodeException) {
                return current.responseCode
            }
            current = current.cause
        }
        return null
    }

    private fun togglePlayPause() {
        val mediaController = controller ?: return
        if (mediaController.isPlaying) {
            mediaController.pause()
        } else {
            mediaController.play()
        }
        updateControls()
    }

    private fun lockPlayer() {
        locked = true
        pendingUnlock = false
        handler.removeCallbacks(unlockRunnable)
        hidePanel()
        controls.visibility = View.GONE
        showUnlockOverlayTemporarily()
        showHint("화면 잠금")
    }

    private fun showUnlockOverlayTemporarily() {
        if (!locked || inPip) return
        handler.removeCallbacks(hideUnlockOverlayRunnable)
        unlockOverlay.visibility = View.VISIBLE
        handler.postDelayed(hideUnlockOverlayRunnable, 1500)
    }

    private fun setControlsVisible(visible: Boolean) {
        if (locked || inPip) return
        controlsVisible = visible
        controls.animate().cancel()
        controls.visibility = View.VISIBLE
        controls.animate()
            .alpha(if (visible) 1f else 0f)
            .setDuration(if (visible) 120L else 220L)
            .withEndAction {
                controls.visibility = if (visible) View.VISIBLE else View.GONE
            }
            .start()
        if (visible) scheduleHideControls()
    }

    private fun scheduleHideControls() {
        handler.removeCallbacks(hideControlsRunnable)
        if (!locked && !inPip) {
            handler.postDelayed(hideControlsRunnable, 3600)
        }
    }

    private fun startProgressUpdates() {
        if (progressUpdatesRunning) return
        progressUpdatesRunning = true
        handler.removeCallbacks(progressRunnable)
        handler.post(progressRunnable)
    }

    private fun stopProgressUpdates() {
        progressUpdatesRunning = false
        handler.removeCallbacks(progressRunnable)
    }

    private fun progressUpdateDelayMs(): Long {
        return if (userSeeking || (controlsVisible && !locked && !inPip)) 500L else 1000L
    }

    private fun cycleResizeMode() {
        setResizeMode((resizeModeIndex + 1) % resizeModes.size)
    }

    private fun setResizeMode(index: Int) {
        resizeModeIndex = index.coerceIn(resizeModes.indices)
        playerView.resizeMode = resizeModes[resizeModeIndex]
        if (::resizeButton.isInitialized) resizeButton.text = resizeModeLabels[resizeModeIndex]
        showHint("화면 비율: ${resizeModeLabels[resizeModeIndex]}")
    }

    private fun setPlaybackSpeed(speed: Float) {
        val mediaController = controller ?: return
        playbackSpeed = ((speed.coerceIn(0.25f, 3.0f) * 20f).roundToInt() / 20f)
        mediaController.setPlaybackSpeed(playbackSpeed)
        if (::speedButton.isInitialized) speedButton.text = formatSpeedLabel()
        showHint("재생 속도: ${formatSpeedLabel()}")
    }

    private fun formatSpeedLabel(): String = "%.2fx".format(playbackSpeed)

    private fun showSpeedPanel() {
        val speedValue = TextView(this).apply {
            text = formatSpeedLabel()
            setTextColor(Color.WHITE)
            textSize = 30f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            includeFontPadding = false
        }
        val slider = SpeedSliderView(this).apply {
            speed = playbackSpeed
            onSpeedChanged = {
                playbackSpeed = it
                speedValue.text = formatSpeedLabel()
            }
            onSpeedCommitted = { setPlaybackSpeed(it) }
        }
        val row = LinearLayout(this).apply {
            gravity = Gravity.CENTER
            orientation = LinearLayout.HORIZONTAL
            addView(panelStepButton("-0.05") {
                setPlaybackSpeed(playbackSpeed - 0.05f)
                slider.speed = playbackSpeed
                slider.invalidate()
                speedValue.text = formatSpeedLabel()
            })
            addView(space(12))
            addView(panelStepButton("+0.05") {
                setPlaybackSpeed(playbackSpeed + 0.05f)
                slider.speed = playbackSpeed
                slider.invalidate()
                speedValue.text = formatSpeedLabel()
            })
        }
        val panel = panelContainer("재생 속도").apply {
            addView(speedValue, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(48)))
            addView(slider, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(56)))
            addView(row)
        }
        showPanel(panel)
    }

    private fun panelStepButton(label: String, action: () -> Unit): TextView {
        return TextView(this).apply {
            text = label
            setTextColor(Color.WHITE)
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            minWidth = dp(112)
            minHeight = dp(46)
            background = glassPillBackground()
            setOnClickListener { action() }
        }
    }

    private fun showPlayerOptionsPanel() {
        val mediaController = controller
        if (mediaController == null || mediaController.mediaItemCount <= 0) {
            showHint("재생 중인 영상이 없습니다")
            return
        }
        val panel = panelContainer("플레이어 설정").apply {
            addView(panelOption("자막", "다음 단계에서 지원 예정") {
                hidePanel()
                showHint("자막은 다음 단계에서 지원 예정")
            })
            addView(panelOption("오디오 트랙", "다음 단계에서 지원 예정") {
                hidePanel()
                showHint("오디오 트랙은 다음 단계에서 지원 예정")
            })
        }
        showPanel(panel)
    }

    private fun panelContainer(title: String): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(22), dp(18), dp(22), dp(20))
            background = glassPanelBackground()
            addView(TextView(this@PlayerActivity).apply {
                text = title
                setTextColor(Color.WHITE)
                textSize = 18f
                typeface = Typeface.DEFAULT_BOLD
                includeFontPadding = false
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(34)))
        }
    }

    private fun panelOption(title: String, subtitle: String, action: () -> Unit): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(2), dp(12), dp(2), dp(12))
            addView(TextView(this@PlayerActivity).apply {
                text = title
                setTextColor(Color.WHITE)
                textSize = 16f
                typeface = Typeface.DEFAULT_BOLD
                includeFontPadding = false
            })
            addView(TextView(this@PlayerActivity).apply {
                text = subtitle
                setTextColor(Color.argb(180, 255, 255, 255))
                textSize = 12f
                includeFontPadding = false
            })
            setOnClickListener { action() }
        }
    }

    private fun showPanel(panel: View) {
        panelScrim.removeAllViews()
        panelScrim.addView(
            panel,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM,
            ).apply {
                leftMargin = dp(18)
                rightMargin = dp(18)
                bottomMargin = dp(20)
            },
        )
        panelScrim.alpha = 0f
        panelScrim.visibility = View.VISIBLE
        panelScrim.animate().alpha(1f).setDuration(140L).start()
    }

    private fun hidePanel() {
        if (::panelScrim.isInitialized) {
            panelScrim.visibility = View.GONE
            panelScrim.removeAllViews()
        }
    }

    private fun seekRelative(deltaMs: Long) {
        val mediaController = controller ?: return
        if (mediaController.mediaItemCount <= 0) return
        val duration = mediaController.duration
        val target = (mediaController.currentPosition + deltaMs).coerceAtLeast(0L)
        mediaController.seekTo(if (duration > 0) target.coerceAtMost(duration) else target)
        showHint(if (deltaMs > 0) "+10초" else "-10초")
        updateControls()
    }

    private fun showHint(message: String) {
        if (inPip) return
        hintText.text = message
        hintText.visibility = View.VISIBLE
        handler.removeCallbacks(hideHintRunnable)
        handler.postDelayed(hideHintRunnable, 900)
    }

    private fun enterPipMode() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            showHint("PiP를 지원하지 않는 기기입니다")
            return
        }
        if (isInPictureInPictureMode) return
        val mediaController = controller
        if (mediaController == null || mediaController.mediaItemCount <= 0) {
            showHint("재생 중인 영상이 없습니다")
            return
        }
        controls.visibility = View.GONE
        panelScrim.visibility = View.GONE
        hintText.visibility = View.GONE
        overlay.visibility = View.GONE
        unlockOverlay.visibility = View.GONE
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
            .build()
        enterPictureInPictureMode(params)
    }

    private fun updateControls() {
        val mediaController = controller ?: return
        val current = mediaController.currentMediaItem
        titleText.text = current?.mediaMetadata?.title?.toString().orEmpty()
        centerPlayButton.icon = if (mediaController.isPlaying) ICON_PAUSE else ICON_PLAY
        centerPlayButton.invalidate()
        val duration = mediaController.duration.takeIf { it > 0 } ?: 0L
        val position = mediaController.currentPosition.coerceAtLeast(0L)
        positionText.text = formatTime(position)
        durationText.text = formatTime(duration)
        if (!userSeeking) {
            progressView.progress = if (duration > 0) (position.toFloat() / duration.toFloat()).coerceIn(0f, 1f) else 0f
            progressView.invalidate()
        }
    }

    private fun updateOverlay() {
        if (inPip) return
        playbackErrorMessage?.let {
            showOverlay(it)
            return
        }
        val mediaController = controller ?: run {
            showOverlay("플레이어 연결 중...")
            return
        }
        if (mediaController.mediaItemCount <= 0) {
            showOverlay("재생할 영상이 없습니다")
            return
        }
        when (mediaController.playbackState) {
            Player.STATE_IDLE -> showOverlay("영상 준비 중...")
            Player.STATE_BUFFERING -> showOverlay("영상 불러오는 중...")
            Player.STATE_READY -> hideOverlay()
            Player.STATE_ENDED -> showOverlay("재생이 끝났습니다")
            else -> showOverlay("영상 준비 중...")
        }
    }

    private fun showOverlay(message: String) {
        overlayText.text = message
        overlay.visibility = View.VISIBLE
    }

    private fun hideOverlay() {
        overlay.visibility = View.GONE
    }

    private fun formatTime(milliseconds: Long): String {
        val totalSeconds = (milliseconds / 1000L).coerceAtLeast(0L)
        val hours = totalSeconds / 3600L
        val minutes = (totalSeconds % 3600L) / 60L
        val seconds = totalSeconds % 60L
        return if (hours > 0) {
            "%d:%02d:%02d".format(hours, minutes, seconds)
        } else {
            "%02d:%02d".format(minutes, seconds)
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).roundToInt()

    private fun hideSystemBars() {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.let { controller ->
                controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        }
    }

    private inner class PlayerGestureListener : GestureDetector.SimpleOnGestureListener() {
        override fun onDown(e: MotionEvent): Boolean = true

        override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
            if (locked || inPip) return true
            setControlsVisible(!controlsVisible)
            return true
        }

        override fun onDoubleTap(e: MotionEvent): Boolean {
            if (locked || inPip) return true
            if (e.x < playerView.width / 2f) {
                seekRelative(-10_000L)
            } else {
                seekRelative(10_000L)
            }
            return true
        }
    }

    private inner class IconGlassButton(
        context: Context,
        var icon: Int,
        private val strong: Boolean = false,
    ) : View(context) {
        private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = dp(1).toFloat()
            color = Color.argb(60, 255, 255, 255)
        }
        private val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.FILL
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        private val rect = RectF()

        init {
            isClickable = true
            isFocusable = true
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val size = width.coerceAtMost(height).toFloat()
            rect.set((width - size) / 2f, (height - size) / 2f, (width + size) / 2f, (height + size) / 2f)
            fillPaint.color = if (strong) Color.argb(212, 18, 18, 20) else Color.argb(120, 18, 18, 20)
            canvas.drawOval(rect, fillPaint)
            canvas.drawOval(rect, strokePaint)
            drawIcon(canvas, rect)
        }

        private fun drawIcon(canvas: Canvas, area: RectF) {
            vectorDrawableRes(icon)?.let { resId ->
                val drawable = context.getDrawable(resId)?.mutate() ?: return
                drawable.setTint(Color.WHITE)
                val inset = (area.width() * 0.28f).roundToInt()
                drawable.setBounds(
                    area.left.roundToInt() + inset,
                    area.top.roundToInt() + inset,
                    area.right.roundToInt() - inset,
                    area.bottom.roundToInt() - inset,
                )
                drawable.draw(canvas)
                return
            }
            val cx = area.centerX()
            val cy = area.centerY()
            val s = area.width()
            iconPaint.color = Color.WHITE
            iconPaint.style = Paint.Style.FILL
            iconPaint.strokeWidth = (s * 0.07f).coerceAtLeast(3f)
            when (icon) {
                ICON_PLAY -> {
                    val p = Path()
                    p.moveTo(cx - s * 0.12f, cy - s * 0.18f)
                    p.lineTo(cx - s * 0.12f, cy + s * 0.18f)
                    p.lineTo(cx + s * 0.18f, cy)
                    p.close()
                    canvas.drawPath(p, iconPaint)
                }
                ICON_PAUSE -> {
                    val w = s * 0.075f
                    val h = s * 0.34f
                    val gap = s * 0.08f
                    canvas.drawRoundRect(RectF(cx - gap - w, cy - h / 2f, cx - gap, cy + h / 2f), w, w, iconPaint)
                    canvas.drawRoundRect(RectF(cx + gap, cy - h / 2f, cx + gap + w, cy + h / 2f), w, w, iconPaint)
                }
                ICON_BACK -> {
                    iconPaint.style = Paint.Style.STROKE
                    canvas.drawLine(cx + s * 0.12f, cy - s * 0.18f, cx - s * 0.10f, cy, iconPaint)
                    canvas.drawLine(cx - s * 0.10f, cy, cx + s * 0.12f, cy + s * 0.18f, iconPaint)
                }
                ICON_MENU -> {
                    canvas.drawCircle(cx, cy - s * 0.16f, s * 0.035f, iconPaint)
                    canvas.drawCircle(cx, cy, s * 0.035f, iconPaint)
                    canvas.drawCircle(cx, cy + s * 0.16f, s * 0.035f, iconPaint)
                }
                ICON_PREVIOUS, ICON_NEXT -> {
                    val dir = if (icon == ICON_NEXT) 1f else -1f
                    iconPaint.style = Paint.Style.STROKE
                    iconPaint.strokeWidth = s * 0.07f
                    canvas.drawLine(cx + dir * s * 0.20f, cy - s * 0.20f, cx + dir * s * 0.20f, cy + s * 0.20f, iconPaint)
                    iconPaint.style = Paint.Style.FILL
                    val p = Path()
                    p.moveTo(cx + dir * s * 0.13f, cy)
                    p.lineTo(cx - dir * s * 0.08f, cy - s * 0.17f)
                    p.lineTo(cx - dir * s * 0.08f, cy + s * 0.17f)
                    p.close()
                    canvas.drawPath(p, iconPaint)
                    val p2 = Path()
                    p2.moveTo(cx - dir * s * 0.08f, cy)
                    p2.lineTo(cx - dir * s * 0.27f, cy - s * 0.17f)
                    p2.lineTo(cx - dir * s * 0.27f, cy + s * 0.17f)
                    p2.close()
                    canvas.drawPath(p2, iconPaint)
                }
                ICON_PIP -> {
                    iconPaint.style = Paint.Style.STROKE
                    iconPaint.strokeWidth = s * 0.055f
                    val outer = RectF(cx - s * 0.24f, cy - s * 0.17f, cx + s * 0.24f, cy + s * 0.17f)
                    canvas.drawRoundRect(outer, s * 0.04f, s * 0.04f, iconPaint)
                    iconPaint.style = Paint.Style.FILL
                    canvas.drawRoundRect(RectF(cx + s * 0.02f, cy, cx + s * 0.19f, cy + s * 0.12f), s * 0.025f, s * 0.025f, iconPaint)
                }
                ICON_LOCK -> {
                    iconPaint.style = Paint.Style.STROKE
                    iconPaint.strokeWidth = s * 0.06f
                    canvas.drawArc(RectF(cx - s * 0.15f, cy - s * 0.24f, cx + s * 0.15f, cy + s * 0.10f), 200f, 140f, false, iconPaint)
                    iconPaint.style = Paint.Style.FILL
                    canvas.drawRoundRect(RectF(cx - s * 0.20f, cy - s * 0.02f, cx + s * 0.20f, cy + s * 0.24f), s * 0.045f, s * 0.045f, iconPaint)
                }
            }
        }

        private fun vectorDrawableRes(icon: Int): Int? {
            return when (icon) {
                ICON_LOCK -> R.drawable.ic_lock
                ICON_UNLOCK -> R.drawable.ic_unlock
                ICON_SWAP_CONTROLS -> R.drawable.ic_swap_horizontal
                ICON_PIP -> R.drawable.ic_picture_in_picture
                else -> null
            }
        }

    }

    private inner class PlayerProgressView(context: Context) : View(context) {
        var progress = 0f
        var onSeekStarted: (() -> Unit)? = null
        var onSeekChanged: ((Float) -> Unit)? = null
        var onSeekFinished: (() -> Unit)? = null
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val rect = RectF()

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val centerY = height / 2f
            val left = dp(2).toFloat()
            val right = width - dp(2).toFloat()
            val trackHeight = dp(7).toFloat()
            rect.set(left, centerY - trackHeight / 2f, right, centerY + trackHeight / 2f)
            paint.color = Color.argb(116, 255, 255, 255)
            canvas.drawRoundRect(rect, trackHeight, trackHeight, paint)
            rect.right = left + (right - left) * progress.coerceIn(0f, 1f)
            paint.color = ACCENT
            canvas.drawRoundRect(rect, trackHeight, trackHeight, paint)
            val thumbX = left + (right - left) * progress.coerceIn(0f, 1f)
            paint.color = Color.WHITE
            canvas.drawRoundRect(RectF(thumbX - dp(5), centerY - dp(16), thumbX + dp(5), centerY + dp(16)), dp(5).toFloat(), dp(5).toFloat(), paint)
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            if (locked || inPip) return true
            val fraction = (event.x / width.toFloat()).coerceIn(0f, 1f)
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    onSeekStarted?.invoke()
                    progress = fraction
                    invalidate()
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    progress = fraction
                    invalidate()
                    onSeekChanged?.invoke(fraction)
                    return true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    progress = fraction
                    invalidate()
                    onSeekChanged?.invoke(fraction)
                    onSeekFinished?.invoke()
                    return true
                }
            }
            return true
        }
    }

    private inner class SpeedSliderView(context: Context) : View(context) {
        var speed = 1.0f
        var onSpeedChanged: ((Float) -> Unit)? = null
        var onSpeedCommitted: ((Float) -> Unit)? = null
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val rect = RectF()

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val y = height / 2f
            val left = dp(6).toFloat()
            val right = width - dp(6).toFloat()
            val fraction = ((speed - 0.25f) / 2.75f).coerceIn(0f, 1f)
            rect.set(left, y - dp(4), right, y + dp(4))
            paint.color = Color.argb(78, 255, 255, 255)
            canvas.drawRoundRect(rect, dp(8).toFloat(), dp(8).toFloat(), paint)
            rect.right = left + (right - left) * fraction
            paint.color = ACCENT
            canvas.drawRoundRect(rect, dp(8).toFloat(), dp(8).toFloat(), paint)
            val x = left + (right - left) * fraction
            paint.color = Color.WHITE
            canvas.drawCircle(x, y, dp(11).toFloat(), paint)
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            val fraction = (event.x / width.toFloat()).coerceIn(0f, 1f)
            val ICON_NEXT = ((0.25f + 2.75f * fraction) * 20f).roundToInt() / 20f
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                    speed = ICON_NEXT.coerceIn(0.25f, 3.0f)
                    onSpeedChanged?.invoke(speed)
                    invalidate()
                    return true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    speed = ICON_NEXT.coerceIn(0.25f, 3.0f)
                    onSpeedCommitted?.invoke(speed)
                    invalidate()
                    return true
                }
            }
            return true
        }
    }

    companion object {
        private const val TAG = "DriveShufflePlayer"
        private const val ACCENT = 0xff32BF5E.toInt()
        private const val ICON_PLAY = 1
        private const val ICON_PAUSE = 2
        private const val ICON_BACK = 3
        private const val ICON_MENU = 4
        private const val ICON_PREVIOUS = 5
        private const val ICON_NEXT = 6
        private const val ICON_PIP = 7
        private const val ICON_LOCK = 8
        private const val ICON_UNLOCK = 9
        private const val ICON_SWAP_CONTROLS = 10
    }
}

