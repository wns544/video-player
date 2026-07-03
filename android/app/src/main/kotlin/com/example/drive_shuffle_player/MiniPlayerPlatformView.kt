package com.example.drive_shuffle_player

import android.content.ComponentName
import android.content.Context
import android.view.View
import android.widget.FrameLayout
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import androidx.media3.ui.PlayerView
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class MiniPlayerViewFactory(private val context: Context) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return MiniPlayerPlatformView(this.context)
    }
}

private class MiniPlayerPlatformView(context: Context) : PlatformView {
    private val container = FrameLayout(context)
    private val playerView = PlayerView(context).apply {
        useController = false
        setShowBuffering(PlayerView.SHOW_BUFFERING_NEVER)
        layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        )
    }
    private val controllerFuture: ListenableFuture<MediaController>

    init {
        container.addView(playerView)
        val sessionToken = SessionToken(context, ComponentName(context, PlaybackService::class.java))
        controllerFuture = MediaController.Builder(context, sessionToken).buildAsync()
        controllerFuture.addListener(
            {
                playerView.post {
                    playerView.player = controllerFuture.get()
                }
            },
            MoreExecutors.directExecutor(),
        )
    }

    override fun getView(): View = container

    override fun dispose() {
        playerView.player = null
        MediaController.releaseFuture(controllerFuture)
    }
}
