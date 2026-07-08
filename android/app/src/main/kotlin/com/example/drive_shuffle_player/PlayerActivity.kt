package com.example.drive_shuffle_player

import android.app.Activity
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.Icon
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
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
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
    private lateinit var shuffleButton: IconGlassButton
    private lateinit var unlockOverlay: FrameLayout
    private lateinit var titleText: TextView
    private lateinit var positionText: TextView
    private lateinit var durationText: TextView
    private lateinit var resizeButton: IconGlassButton
    private lateinit var speedButton: TextView
    private lateinit var repeatButton: IconGlassButton
    private lateinit var quickRow: LinearLayout
    private lateinit var progressView: PlayerProgressView
    private lateinit var hintText: TextView
    private lateinit var overlay: LinearLayout
    private lateinit var overlayText: TextView
    private lateinit var overlaySpinner: ProgressBar
    private lateinit var overlayProgress: ProgressBar
    private lateinit var overlayAction: Button
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
    private var enteringPip = false
    private var pendingUnlock = false
    private var controlsOnRight = true
    private var activityResumed = false
    private var progressUpdatesRunning = false
    private var shuffleQueueActive = false
    private var pendingSeekDirection = 0
    private var pendingSeekSteps = 0
    private var horizontalSeekDragging = false
    private var horizontalSeekAllowed = false
    private var horizontalSeekStartX = 0f
    private var horizontalSeekAccumulatedMs = 0L
    private var queueBeforeShuffle: List<MediaItem>? = null

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
            updateOverlay()
            handler.postDelayed(this, progressUpdateDelayMs())
        }
    }
    private val enterPipRunnable = Runnable {
        if (!enteringPip || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return@Runnable
        if (isFinishing || isDestroyed || isInPictureInPictureMode) return@Runnable
        hideChromeForPip()
        updatePipParamsIfPossible()
        enterPictureInPictureMode(buildPipParams())
    }
    private val commitAccumulatedSeekRunnable = Runnable {
        commitAccumulatedSeek()
    }

    private val playerListener = object : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            Log.d(TAG, "state=$playbackState count=${controller?.mediaItemCount}")
            updateOverlay()
            updateControls()
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            updateControls()
            updatePipParamsIfPossible()
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            Log.d(TAG, "mediaItem=${mediaItem?.mediaId} reason=$reason")
            playbackErrorMessage = null
            updateOverlay()
            updateControls()
            updatePipParamsIfPossible()
        }

        override fun onPlayerError(error: PlaybackException) {
            val detail = error.cause?.message ?: error.message ?: error.errorCodeName
            Log.d(TAG, "error=${error.errorCodeName}: $detail", error)
            val httpStatus = httpStatusCodeFor(error)
            val authError = httpStatus == 401 || httpStatus == 403
            PlaybackAuth.authError = authError
            PlaybackAuth.lastHttpStatusCode = httpStatus
            playbackErrorMessage =
                if (authError) {
                    "Drive 인증이 필요합니다"
                } else {
                    "재생 오류\n${error.errorCodeName}"
                }
            showOverlay(
                playbackErrorMessage.orEmpty(),
                showProgress = authError,
                determinateProgress = null,
                showReconnectAction = authError,
            )
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (handlePipActionIntent(intent)) return
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
                        updatePipParamsIfPossible()
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
        enteringPip = false
        if (controller != null) startProgressUpdates()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handlePipActionIntent(intent)
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
        handler.removeCallbacks(enterPipRunnable)
        handler.removeCallbacks(commitAccumulatedSeekRunnable)
        stopProgressUpdates()
        controller?.removeListener(playerListener)
        if (::playerView.isInitialized) {
            playerView.player = null
        }
        if (::controllerFuture.isInitialized) {
            MediaController.releaseFuture(controllerFuture)
        }
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
            hideChromeForPip()
        } else {
            enteringPip = false
            setControlsVisible(false)
            updateOverlay()
            updatePipParamsIfPossible()
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
                if (
                    horizontalSeekDragging &&
                    (event.actionMasked == MotionEvent.ACTION_UP ||
                        event.actionMasked == MotionEvent.ACTION_CANCEL)
                ) {
                    finishHorizontalSeekDrag()
                }
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
        overlaySpinner = ProgressBar(this).apply {
            isIndeterminate = true
        }
        overlayProgress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
            progress = 0
            isIndeterminate = true
            progressDrawable?.setTint(ACCENT)
        }
        overlayAction = Button(this).apply {
            text = "Drive 다시 연결"
            visibility = View.GONE
            setOnClickListener {
                showOverlay("Drive 재인증 화면을 여는 중...", showProgress = true)
                startActivity(Intent(this@PlayerActivity, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                })
            }
        }
        overlay = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.argb(118, 0, 0, 0))
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
            setPadding(dp(28), dp(28), dp(28), dp(28))
            addView(overlaySpinner, LinearLayout.LayoutParams(dp(52), dp(52)))
            addView(overlayText)
            addView(overlayProgress, LinearLayout.LayoutParams(dp(260), dp(8)).apply {
                topMargin = dp(4)
            })
            addView(overlayAction, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(44)).apply {
                topMargin = dp(18)
            })
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
                Gravity.TOP or Gravity.CENTER_HORIZONTAL,
            ).apply { topMargin = dp(88) },
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
            addView(IconGlassButton(this@PlayerActivity, ICON_QUEUE).apply {
                setOnClickListener { safeAction { showQueuePanel() } }
            }, LinearLayout.LayoutParams(dp(52), dp(52)))
            addView(space(10))
            addView(lockButton, LinearLayout.LayoutParams(dp(52), dp(52)))
            addView(space(10))
            addView(IconGlassButton(this@PlayerActivity, ICON_MENU).apply {
                setOnClickListener { safeAction { showPlayerOptionsPanel() } }
            }, LinearLayout.LayoutParams(dp(52), dp(52)))
        }

        val centerLayer = LinearLayout(this).apply {
            gravity = Gravity.CENTER
            orientation = LinearLayout.HORIZONTAL
            addView(IconGlassButton(this@PlayerActivity, ICON_PREVIOUS).apply {
                setOnClickListener { safeAction { controller?.seekToPreviousMediaItem() } }
            }, LinearLayout.LayoutParams(dp(56), dp(56)))
            addView(space(42))
            addView(centerPlayButton, LinearLayout.LayoutParams(dp(82), dp(82)))
            addView(space(42))
            addView(IconGlassButton(this@PlayerActivity, ICON_NEXT).apply {
                setOnClickListener { safeAction { controller?.seekToNextMediaItem() } }
            }, LinearLayout.LayoutParams(dp(56), dp(56)))
        }

        val timeRow = LinearLayout(this).apply {
            gravity = Gravity.CENTER_VERTICAL
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(18), 0, dp(18), 0)
            addView(positionText, LinearLayout.LayoutParams(dp(70), LinearLayout.LayoutParams.WRAP_CONTENT))
            addView(space(10))
            addView(progressView, LinearLayout.LayoutParams(0, dp(44), 1f))
            addView(space(10))
            addView(durationText, LinearLayout.LayoutParams(dp(70), LinearLayout.LayoutParams.WRAP_CONTENT))
        }

        resizeButton = IconGlassButton(this, ICON_RESIZE).apply {
            setOnClickListener { safeAction { cycleResizeMode() } }
        }
        speedButton = pillButton(formatSpeedLabel()) { showSpeedPanel() }.apply {
            setOnLongClickListener {
                setPlaybackSpeed(1.0f)
                true
            }
        }
        repeatButton = IconGlassButton(this, ICON_REPEAT).apply {
            setOnClickListener { safeAction { toggleRepeatMode() } }
        }

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
        quickRow.addView(space(8))
        quickRow.addView(resizeButton, LinearLayout.LayoutParams(dp(48), dp(48)))
    }

    private fun addQuickActions() {
        shuffleButton = IconGlassButton(this, ICON_SHUFFLE).apply {
            setOnClickListener { safeAction { toggleShuffleMode() } }
        }
        quickRow.addView(shuffleButton, LinearLayout.LayoutParams(dp(48), dp(48)))
        quickRow.addView(space(8))
        quickRow.addView(speedButton)
        quickRow.addView(space(8))
        quickRow.addView(IconGlassButton(this, ICON_PIP).apply {
            setOnTouchListener { _, event ->
                if (locked || inPip) return@setOnTouchListener true
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        enteringPip = true
                        hideChromeForPip()
                        updatePipParamsIfPossible()
                        true
                    }
                    MotionEvent.ACTION_UP -> {
                        enterPipMode()
                        true
                    }
                    MotionEvent.ACTION_CANCEL -> {
                        enteringPip = false
                        true
                    }
                    else -> true
                }
            }
        }, LinearLayout.LayoutParams(dp(52), dp(48)))
        quickRow.addView(space(8))
        quickRow.addView(repeatButton, LinearLayout.LayoutParams(dp(48), dp(48)))
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
                if (!locked) return@setOnClickListener
                if (visibility == View.VISIBLE) {
                    hideUnlockOverlayNow()
                } else {
                    showUnlockOverlayTemporarily()
                }
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
            setBackgroundColor(Color.argb(24, 0, 0, 0))
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
        if (!enteringPip && !isInPictureInPictureMode) {
            setControlsVisible(true)
            scheduleHideControls()
        }
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

    private fun toggleShuffleMode() {
        val mediaController = controller ?: return
        if (mediaController.mediaItemCount <= 1) {
            shuffleQueueActive = false
            queueBeforeShuffle = null
            mediaController.shuffleModeEnabled = false
            updateControls()
            showHint("셔플할 다음 영상이 없습니다")
            return
        }
        if (shuffleQueueActive) {
            restoreQueueBeforeShuffle(mediaController)
            shuffleQueueActive = false
            queueBeforeShuffle = null
            showHint("셔플 꺼짐 · 큐 순서 복원")
        } else {
            queueBeforeShuffle = collectQueue(mediaController)
            shuffleQueue(mediaController)
            shuffleQueueActive = true
            showHint("셔플 켜짐 · 큐를 섞었습니다")
        }
        mediaController.shuffleModeEnabled = false
        updateControls()
    }

    private fun collectQueue(mediaController: MediaController): List<MediaItem> {
        return List(mediaController.mediaItemCount) { index ->
            mediaController.getMediaItemAt(index)
        }
    }

    private fun shuffleQueue(mediaController: MediaController) {
        val currentIndex = mediaController.currentMediaItemIndex.coerceAtLeast(0)
        val current = mediaController.currentMediaItem ?: mediaController.getMediaItemAt(currentIndex)
        val rest = collectQueue(mediaController).filterIndexed { index, _ -> index != currentIndex }.toMutableList()
        rest.shuffle()
        replaceQueueKeepingCurrent(mediaController, listOf(current) + rest, 0)
    }

    private fun restoreQueueBeforeShuffle(mediaController: MediaController) {
        val originalQueue = queueBeforeShuffle ?: return
        val currentId = mediaController.currentMediaItem?.mediaId
        val restoredIndex = originalQueue.indexOfFirst { it.mediaId == currentId }.takeIf { it >= 0 }
            ?: mediaController.currentMediaItemIndex.coerceIn(0, originalQueue.lastIndex)
        replaceQueueKeepingCurrent(mediaController, originalQueue, restoredIndex)
    }

    private fun replaceQueueKeepingCurrent(
        mediaController: MediaController,
        queue: List<MediaItem>,
        currentIndex: Int,
    ) {
        val position = mediaController.currentPosition.coerceAtLeast(0L)
        val wasPlaying = mediaController.isPlaying
        mediaController.setMediaItems(queue, currentIndex, position)
        mediaController.prepare()
        if (wasPlaying) {
            mediaController.play()
        }
    }

    private fun toggleRepeatMode() {
        val mediaController = controller ?: return
        mediaController.repeatMode = when (mediaController.repeatMode) {
            Player.REPEAT_MODE_OFF -> Player.REPEAT_MODE_ALL
            Player.REPEAT_MODE_ALL -> Player.REPEAT_MODE_ONE
            else -> Player.REPEAT_MODE_OFF
        }
        updateControls()
        showHint("반복: ${repeatModeLabel(mediaController.repeatMode)}")
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

    private fun hideUnlockOverlayNow() {
        pendingUnlock = false
        handler.removeCallbacks(unlockRunnable)
        handler.removeCallbacks(hideUnlockOverlayRunnable)
        handler.removeCallbacks(hideHintRunnable)
        unlockOverlay.visibility = View.GONE
        hintText.visibility = View.GONE
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
        if (::resizeButton.isInitialized) resizeButton.invalidate()
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
            textSize = 24f
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
        val sliderRow = LinearLayout(this).apply {
            gravity = Gravity.CENTER
            orientation = LinearLayout.HORIZONTAL
            addView(panelStepButton("-", compact = true) {
                setPlaybackSpeed(playbackSpeed - 0.05f)
                slider.speed = playbackSpeed
                slider.invalidate()
                speedValue.text = formatSpeedLabel()
            })
            addView(space(10))
            addView(slider, LinearLayout.LayoutParams(0, dp(48), 1f))
            addView(space(10))
            addView(panelStepButton("+", compact = true) {
                setPlaybackSpeed(playbackSpeed + 0.05f)
                slider.speed = playbackSpeed
                slider.invalidate()
                speedValue.text = formatSpeedLabel()
            })
        }
        val resetRow = LinearLayout(this).apply {
            gravity = Gravity.CENTER
            orientation = LinearLayout.HORIZONTAL
            addView(TextView(this@PlayerActivity).apply {
                text = "↻ 1.00x"
                setTextColor(Color.WHITE)
                textSize = 14f
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                setPadding(dp(10), dp(6), dp(10), dp(6))
                setOnClickListener {
                    setPlaybackSpeed(1.0f)
                    slider.speed = playbackSpeed
                    slider.invalidate()
                    speedValue.text = formatSpeedLabel()
                }
            })
        }
        val panel = panelContainer("재생 속도", compact = true).apply {
            addView(speedValue, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(40)))
            addView(sliderRow, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(48)))
            addView(resetRow, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(36)))
        }
        showPanel(panel, widthDp = 320, gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL, bottomMarginDp = 124)
    }

    private fun panelStepButton(label: String, compact: Boolean = false, action: () -> Unit): TextView {
        return TextView(this).apply {
            text = label
            setTextColor(Color.WHITE)
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            minWidth = dp(if (compact) 44 else 92)
            minHeight = dp(40)
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
        val panel = panelContainer("플레이어 설정", compact = true).apply {
            addView(panelOption(
                "현재 큐",
                if (shuffleQueueActive) {
                    "${mediaController.mediaItemCount}개 · 섞인 순서"
                } else {
                    "${mediaController.mediaItemCount}개 영상"
                },
            ) {
                showQueuePanel()
            })
            addView(panelOption("반복 모드", repeatModeLabel(mediaController.repeatMode)) {
                toggleRepeatMode()
            })
            addView(panelOption("재생 정지", "현재 큐를 비우고 플레이어를 닫습니다") {
                stopPlaybackAndClose()
            })
            addView(panelOption("자막", "다음 단계에서 지원 예정") {
                hidePanel()
                showHint("자막은 다음 단계에서 지원 예정")
            })
            addView(panelOption("오디오 트랙", "다음 단계에서 지원 예정") {
                hidePanel()
                showHint("오디오 트랙은 다음 단계에서 지원 예정")
            })
        }
        showPanel(panel, widthDp = 260, gravity = Gravity.TOP or Gravity.RIGHT, topMarginDp = 84, rightMarginDp = 18)
    }

    private fun showQueuePanel() {
        val mediaController = controller
        if (mediaController == null || mediaController.mediaItemCount <= 0) {
            showHint("현재 큐가 없습니다")
            return
        }
        hidePanel()
        val list = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        for (index in 0 until mediaController.mediaItemCount) {
            val item = mediaController.getMediaItemAt(index)
            val title = item.mediaMetadata.title?.toString().takeUnless { it.isNullOrBlank() }
                ?: item.mediaId
            val isCurrent = index == mediaController.currentMediaItemIndex
            list.addView(panelOption(
                if (isCurrent) "▶ ${index + 1}. $title" else "${index + 1}. $title",
                if (isCurrent) "현재 재생 중" else "탭해서 이동",
            ) {
                mediaController.seekToDefaultPosition(index)
                mediaController.play()
                hidePanel()
            })
        }
        val scroll = ScrollView(this).apply {
            addView(list)
        }
        val title = if (shuffleQueueActive) {
            "현재 큐 · ${mediaController.mediaItemCount}개 · 셔플"
        } else {
            "현재 큐 · ${mediaController.mediaItemCount}개"
        }
        val panel = panelContainer(title, compact = true).apply {
            if (shuffleQueueActive) {
                addView(panelNote("셔플 켜짐: 현재 영상은 유지하고 다음 큐를 섞었습니다."))
            }
            addView(scroll, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(280),
            ))
        }
        showPanel(panel, widthDp = 360, gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL, bottomMarginDp = 96)
    }

    private fun stopPlaybackAndClose() {
        val mediaController = controller ?: return
        hidePanel()
        mediaController.stop()
        mediaController.clearMediaItems()
        finish()
    }

    private fun panelContainer(title: String, compact: Boolean = false): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(14), dp(18), dp(16))
            background = glassPanelBackground()
            addView(TextView(this@PlayerActivity).apply {
                text = title
                setTextColor(Color.WHITE)
                textSize = if (compact) 15f else 18f
                typeface = Typeface.DEFAULT_BOLD
                includeFontPadding = false
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(if (compact) 28 else 34)))
        }
    }

    private fun panelNote(message: String): View {
        return TextView(this).apply {
            text = message
            setTextColor(Color.argb(190, 255, 255, 255))
            textSize = 12f
            includeFontPadding = false
            setPadding(dp(2), dp(2), dp(2), dp(10))
        }
    }

    private fun panelOption(title: String, subtitle: String, action: () -> Unit): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(2), dp(9), dp(2), dp(9))
            addView(TextView(this@PlayerActivity).apply {
                text = title
                setTextColor(Color.WHITE)
                textSize = 14f
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

    private fun showPanel(
        panel: View,
        widthDp: Int,
        gravity: Int,
        topMarginDp: Int = 0,
        rightMarginDp: Int = 0,
        bottomMarginDp: Int = 20,
    ) {
        panelScrim.removeAllViews()
        panelScrim.addView(
            panel,
            FrameLayout.LayoutParams(
                dp(widthDp),
                FrameLayout.LayoutParams.WRAP_CONTENT,
                gravity,
            ).apply {
                topMargin = dp(topMarginDp)
                rightMargin = dp(rightMarginDp)
                bottomMargin = dp(bottomMarginDp)
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
        val seconds = kotlin.math.abs(deltaMs / 1000L)
        showHint(if (deltaMs > 0) "+${seconds}초" else "-${seconds}초")
        updateControls()
    }

    private fun queueAccumulatedSeek(direction: Int) {
        if (pendingSeekDirection != 0 && pendingSeekDirection != direction) {
            commitAccumulatedSeek()
        }
        pendingSeekDirection = direction
        pendingSeekSteps += 1
        handler.removeCallbacks(commitAccumulatedSeekRunnable)
        handler.postDelayed(commitAccumulatedSeekRunnable, ACCUMULATED_SEEK_DELAY_MS)
        val seconds = pendingSeekSteps * 10
        showHint(if (direction > 0) "+${seconds}초" else "-${seconds}초")
    }

    private fun commitAccumulatedSeek() {
        if (pendingSeekDirection == 0 || pendingSeekSteps <= 0) return
        val deltaMs = pendingSeekDirection * pendingSeekSteps * 10_000L
        pendingSeekDirection = 0
        pendingSeekSteps = 0
        seekRelative(deltaMs)
    }

    private fun finishHorizontalSeekDrag() {
        if (!horizontalSeekDragging) return
        if (horizontalSeekAccumulatedMs != 0L) {
            seekRelative(horizontalSeekAccumulatedMs)
        }
        horizontalSeekDragging = false
        horizontalSeekAccumulatedMs = 0L
        scheduleHideControls()
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
        enteringPip = true
        hideChromeForPip()
        updatePipParamsIfPossible()
        handler.removeCallbacks(enterPipRunnable)
        playerView.post {
            hideChromeForPip()
            playerView.invalidate()
            window.decorView.invalidate()
            handler.postDelayed(enterPipRunnable, PIP_ENTER_DELAY_MS)
        }
    }

    private fun buildPipParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                builder.setAutoEnterEnabled(false)
            }
            builder.setActions(
                listOf(
                    pipRemoteAction(
                        ACTION_AUDIO_ONLY,
                        R.drawable.ic_headphones,
                        "오디오 전용",
                        "화면을 닫고 소리만 재생",
                        AUDIO_ONLY_REQUEST_CODE,
                    ),
                    pipRemoteAction(
                        ACTION_PIP_PLAY_PAUSE,
                        if (controller?.isPlaying == true) R.drawable.ic_pause else R.drawable.ic_play,
                        if (controller?.isPlaying == true) "일시정지" else "재생",
                        "재생 또는 일시정지",
                        PIP_PLAY_PAUSE_REQUEST_CODE,
                    ),
                    pipRemoteAction(
                        ACTION_PIP_NEXT,
                        R.drawable.ic_skip_next,
                        "다음",
                        "다음 영상",
                        PIP_NEXT_REQUEST_CODE,
                    ),
                ),
            )
        }
        return builder.build()
    }

    private fun pipRemoteAction(
        action: String,
        iconRes: Int,
        title: String,
        description: String,
        requestCode: Int,
    ): RemoteAction {
        val intent = Intent(this, PlayerActivity::class.java).apply {
            this.action = action
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return RemoteAction(
            Icon.createWithResource(this, iconRes),
            title,
            description,
            pendingIntent,
        )
    }

    private fun handlePipActionIntent(intent: Intent?): Boolean {
        return when (intent?.action) {
            ACTION_AUDIO_ONLY -> {
                enteringPip = false
                hideChromeForPipIfReady()
                finish()
                true
            }
            ACTION_PIP_PREVIOUS -> {
                controller?.seekToPreviousMediaItem()
                updateControlsIfReady()
                true
            }
            ACTION_PIP_PLAY_PAUSE -> {
                controller?.let { mediaController ->
                    if (mediaController.isPlaying) {
                        mediaController.pause()
                    } else {
                        mediaController.play()
                    }
                }
                updateControlsIfReady()
                true
            }
            ACTION_PIP_NEXT -> {
                controller?.seekToNextMediaItem()
                updateControlsIfReady()
                true
            }
            else -> false
        }
    }

    private fun updatePipParamsIfPossible() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !isFinishing && !isDestroyed) {
            setPictureInPictureParams(buildPipParams())
        }
    }

    private fun updateControlsIfReady() {
        if (::titleText.isInitialized && ::centerPlayButton.isInitialized) {
            updateControls()
        }
    }

    private fun hideChromeForPipIfReady() {
        if (::controls.isInitialized) {
            hideChromeForPip()
        }
    }

    private fun hideChromeForPip() {
        handler.removeCallbacks(hideHintRunnable)
        handler.removeCallbacks(hideControlsRunnable)
        handler.removeCallbacks(hideUnlockOverlayRunnable)
        controlsVisible = false
        controls.animate().cancel()
        controls.alpha = 0f
        controls.visibility = View.GONE
        panelScrim.visibility = View.GONE
        panelScrim.removeAllViews()
        hintText.visibility = View.GONE
        overlay.visibility = View.GONE
        unlockOverlay.visibility = View.GONE
        playerView.invalidate()
        window.decorView.invalidate()
    }

    private fun updateControls() {
        val mediaController = controller ?: return
        val current = mediaController.currentMediaItem
        titleText.text = current?.mediaMetadata?.title?.toString().orEmpty()
        centerPlayButton.icon = if (mediaController.isPlaying) ICON_PAUSE else ICON_PLAY
        centerPlayButton.invalidate()
        if (::shuffleButton.isInitialized) {
            shuffleButton.active = shuffleQueueActive
            shuffleButton.invalidate()
        }
        if (::repeatButton.isInitialized) {
            repeatButton.icon = when (mediaController.repeatMode) {
                Player.REPEAT_MODE_ONE -> ICON_REPEAT_ONE
                else -> ICON_REPEAT
            }
            repeatButton.active = mediaController.repeatMode != Player.REPEAT_MODE_OFF
            repeatButton.invalidate()
        }
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
        if (inPip || enteringPip) return
        playbackErrorMessage?.let {
            val authError = PlaybackAuth.authError
            showOverlay(
                it,
                showProgress = authError,
                determinateProgress = null,
                showReconnectAction = authError,
            )
            return
        }
        val mediaController = controller ?: run {
            showOverlay("플레이어 연결 중...", showProgress = true)
            return
        }
        if (mediaController.mediaItemCount <= 0) {
            showOverlay("재생할 영상이 없습니다", showProgress = false)
            return
        }
        when (mediaController.playbackState) {
            Player.STATE_IDLE -> showOverlay("영상 준비 중...", showProgress = true)
            Player.STATE_BUFFERING -> showOverlay(
                "영상 불러오는 중...",
                showProgress = true,
                determinateProgress = mediaController.bufferedPercentage.takeIf { it in 1..99 },
            )
            Player.STATE_READY -> hideOverlay()
            Player.STATE_ENDED -> showOverlay("재생이 끝났습니다", showProgress = false)
            else -> showOverlay("영상 준비 중...", showProgress = true)
        }
    }

    private fun showOverlay(
        message: String,
        showProgress: Boolean = true,
        determinateProgress: Int? = null,
        showReconnectAction: Boolean = false,
    ) {
        if (inPip || enteringPip) return
        overlayText.text = message
        overlaySpinner.visibility = if (showProgress) View.VISIBLE else View.GONE
        overlayProgress.visibility = if (showProgress) View.VISIBLE else View.GONE
        overlayProgress.isIndeterminate = determinateProgress == null
        if (determinateProgress != null) {
            overlayProgress.progress = determinateProgress.coerceIn(0, 100)
        }
        overlayAction.visibility = if (showReconnectAction) View.VISIBLE else View.GONE
        if (showProgress || showReconnectAction) {
            handler.removeCallbacks(hideControlsRunnable)
            setControlsVisible(false)
        }
        overlay.visibility = View.VISIBLE
    }

    private fun repeatModeLabel(mode: Int): String {
        return when (mode) {
            Player.REPEAT_MODE_OFF -> "꺼짐"
            Player.REPEAT_MODE_ONE -> "한 영상 반복"
            Player.REPEAT_MODE_ALL -> "전체 반복"
            else -> "꺼짐"
        }
    }

    private fun repeatModeShortLabel(mode: Int): String {
        return when (mode) {
            Player.REPEAT_MODE_ONE -> "1"
            Player.REPEAT_MODE_ALL -> "전체"
            else -> "끔"
        }
    }

    private fun hideOverlay() {
        overlay.visibility = View.GONE
        overlayAction.visibility = View.GONE
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
        override fun onDown(e: MotionEvent): Boolean {
            horizontalSeekDragging = false
            horizontalSeekAllowed = isHorizontalSeekArea(e.x)
            horizontalSeekStartX = e.x
            horizontalSeekAccumulatedMs = 0L
            return true
        }

        override fun onScroll(
            e1: MotionEvent?,
            e2: MotionEvent,
            distanceX: Float,
            distanceY: Float,
        ): Boolean {
            if (locked || inPip) return true
            if (!horizontalSeekAllowed) return true
            val start = e1 ?: return true
            val dx = e2.x - start.x
            val dy = e2.y - start.y
            if (!horizontalSeekDragging) {
                if (kotlin.math.abs(dx) < dp(24) || kotlin.math.abs(dx) < kotlin.math.abs(dy) * 1.35f) {
                    return true
                }
                horizontalSeekDragging = true
                horizontalSeekStartX = start.x
                setControlsVisible(true)
            }
            val nextMs = ((e2.x - horizontalSeekStartX) / dp(7).toFloat()).roundToInt() * 1000L
            if (nextMs != horizontalSeekAccumulatedMs) {
                horizontalSeekAccumulatedMs = nextMs
                val seconds = kotlin.math.abs(horizontalSeekAccumulatedMs / 1000L)
                showHint(
                    when {
                        horizontalSeekAccumulatedMs > 0 -> "+${seconds}초"
                        horizontalSeekAccumulatedMs < 0 -> "-${seconds}초"
                        else -> "0초"
                    },
                )
            }
            return true
        }

        override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
            if (locked || inPip || horizontalSeekDragging) return true
            setControlsVisible(!controlsVisible)
            return true
        }

        override fun onDoubleTap(e: MotionEvent): Boolean {
            if (locked || inPip) return true
            if (e.x < playerView.width / 2f) {
                queueAccumulatedSeek(-1)
            } else {
                queueAccumulatedSeek(1)
            }
            return true
        }

        override fun onSingleTapUp(e: MotionEvent): Boolean {
            if (horizontalSeekDragging) {
                finishHorizontalSeekDrag()
                return true
            }
            return super.onSingleTapUp(e)
        }
    }

    private fun isHorizontalSeekArea(x: Float): Boolean {
        val width = playerView.width.takeIf { it > 0 } ?: return false
        val edgeWidth = width / 6f
        return x >= edgeWidth && x <= width - edgeWidth
    }

    private inner class IconGlassButton(
        context: Context,
        var icon: Int,
        private val strong: Boolean = false,
    ) : View(context) {
        var active: Boolean = false
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
            val strokeInset = strokePaint.strokeWidth / 2f + 1f
            rect.set(
                (width - size) / 2f + strokeInset,
                (height - size) / 2f + strokeInset,
                (width + size) / 2f - strokeInset,
                (height + size) / 2f - strokeInset,
            )
            fillPaint.color = when {
                active -> Color.argb(224, 50, 191, 94)
                strong -> Color.argb(212, 18, 18, 20)
                else -> Color.argb(120, 18, 18, 20)
            }
            canvas.drawOval(rect, fillPaint)
            canvas.drawOval(rect, strokePaint)
            drawIcon(canvas, rect)
        }

        private fun drawIcon(canvas: Canvas, area: RectF) {
            vectorDrawableRes(icon)?.let { resId ->
                val drawable = context.getDrawable(resId)?.mutate() ?: return
                drawable.setTint(Color.WHITE)
                val insetRatio = if (icon == ICON_RESIZE) 0.26f else 0.28f
                val inset = (area.width() * insetRatio).roundToInt()
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
                ICON_SHUFFLE -> {
                    iconPaint.style = Paint.Style.STROKE
                    iconPaint.strokeWidth = s * 0.055f
                    iconPaint.strokeCap = Paint.Cap.ROUND
                    val leftX = cx - s * 0.28f
                    val rightX = cx + s * 0.28f
                    val topY = cy - s * 0.15f
                    val bottomY = cy + s * 0.15f
                    canvas.drawLine(leftX, topY, cx - s * 0.06f, topY, iconPaint)
                    canvas.drawLine(cx - s * 0.06f, topY, cx + s * 0.08f, bottomY, iconPaint)
                    canvas.drawLine(cx + s * 0.08f, bottomY, rightX, bottomY, iconPaint)
                    canvas.drawLine(leftX, bottomY, cx - s * 0.06f, bottomY, iconPaint)
                    canvas.drawLine(cx - s * 0.06f, bottomY, cx + s * 0.08f, topY, iconPaint)
                    canvas.drawLine(cx + s * 0.08f, topY, rightX, topY, iconPaint)
                    drawArrowHead(canvas, rightX, topY, s)
                    drawArrowHead(canvas, rightX, bottomY, s)
                }
            }
        }

        private fun drawArrowHead(canvas: Canvas, x: Float, y: Float, size: Float) {
            val arrow = Path()
            arrow.moveTo(x, y)
            arrow.lineTo(x - size * 0.10f, y - size * 0.08f)
            arrow.moveTo(x, y)
            arrow.lineTo(x - size * 0.10f, y + size * 0.08f)
            canvas.drawPath(arrow, iconPaint)
        }

        private fun vectorDrawableRes(icon: Int): Int? {
            return when (icon) {
                ICON_LOCK -> R.drawable.ic_lock
                ICON_UNLOCK -> R.drawable.ic_unlock
                ICON_SWAP_CONTROLS -> R.drawable.ic_swap_horizontal
                ICON_PIP -> R.drawable.ic_picture_in_picture
                ICON_SHUFFLE -> R.drawable.ic_shuffle
                ICON_QUEUE -> R.drawable.ic_queue
                ICON_REPEAT -> R.drawable.ic_repeat
                ICON_REPEAT_ONE -> R.drawable.ic_repeat_one
                ICON_RESIZE -> R.drawable.ic_resize_mode
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

        init {
            isClickable = true
            isFocusable = true
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val centerY = height / 2f
            val thumbRadius = dp(9).toFloat()
            val left = thumbRadius + dp(2).toFloat()
            val right = width - thumbRadius - dp(2).toFloat()
            val trackHeight = dp(7).toFloat()
            rect.set(left, centerY - trackHeight / 2f, right, centerY + trackHeight / 2f)
            paint.color = Color.argb(116, 255, 255, 255)
            canvas.drawRoundRect(rect, trackHeight, trackHeight, paint)
            rect.right = left + (right - left) * progress.coerceIn(0f, 1f)
            paint.color = ACCENT
            canvas.drawRoundRect(rect, trackHeight, trackHeight, paint)
            val thumbX = left + (right - left) * progress.coerceIn(0f, 1f)
            paint.color = Color.WHITE
            canvas.drawCircle(thumbX, centerY, thumbRadius, paint)
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            if (locked || inPip) return true
            parent?.requestDisallowInterceptTouchEvent(true)
            val fraction = seekFractionFor(event.x)
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    onSeekStarted?.invoke()
                    applySeekFraction(fraction)
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    applySeekFraction(fraction)
                    return true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    applySeekFraction(fraction)
                    onSeekFinished?.invoke()
                    return true
                }
            }
            return true
        }

        private fun seekFractionFor(x: Float): Float {
            val thumbRadius = dp(9).toFloat()
            val left = thumbRadius + dp(2).toFloat()
            val right = width - thumbRadius - dp(2).toFloat()
            val usableWidth = (right - left).coerceAtLeast(1f)
            return ((x - left) / usableWidth).coerceIn(0f, 1f)
        }

        private fun applySeekFraction(fraction: Float) {
            progress = fraction
            invalidate()
            onSeekChanged?.invoke(fraction)
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
        private const val ICON_SHUFFLE = 11
        private const val ICON_QUEUE = 12
        private const val ICON_REPEAT = 13
        private const val ICON_RESIZE = 14
        private const val ICON_REPEAT_ONE = 15
        private const val ACTION_AUDIO_ONLY = "com.example.drive_shuffle_player.action.AUDIO_ONLY"
        private const val ACTION_PIP_PREVIOUS = "com.example.drive_shuffle_player.action.PIP_PREVIOUS"
        private const val ACTION_PIP_PLAY_PAUSE = "com.example.drive_shuffle_player.action.PIP_PLAY_PAUSE"
        private const val ACTION_PIP_NEXT = "com.example.drive_shuffle_player.action.PIP_NEXT"
        private const val AUDIO_ONLY_REQUEST_CODE = 4102
        private const val PIP_PREVIOUS_REQUEST_CODE = 4103
        private const val PIP_PLAY_PAUSE_REQUEST_CODE = 4104
        private const val PIP_NEXT_REQUEST_CODE = 4105
        private const val PIP_ENTER_DELAY_MS = 180L
        private const val ACCUMULATED_SEEK_DELAY_MS = 350L
    }
}

