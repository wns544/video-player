package com.example.drive_shuffle_player

import android.content.ComponentName
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var controllerFuture: ListenableFuture<MediaController>
    private var pendingPickResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val sessionToken = SessionToken(this, ComponentName(this, PlaybackService::class.java))
        controllerFuture = MediaController.Builder(this, sessionToken).buildAsync()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickLocalVideos" -> pickLocalVideos(result)
                    "playQueue" -> withController(result) { controller ->
                        playQueue(call, controller)
                        result.success(null)
                    }
                    "playPause" -> withController(result) { controller ->
                        if (controller.isPlaying) controller.pause() else controller.play()
                        result.success(null)
                    }
                    "next" -> withController(result) { controller ->
                        controller.seekToNextMediaItem()
                        result.success(null)
                    }
                    "previous" -> withController(result) { controller ->
                        controller.seekToPreviousMediaItem()
                        result.success(null)
                    }
                    "stop" -> withController(result) { controller ->
                        controller.stop()
                        controller.clearMediaItems()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        MediaController.releaseFuture(controllerFuture)
        super.onDestroy()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_VIDEOS_REQUEST) return

        val result = pendingPickResult ?: return
        pendingPickResult = null

        if (resultCode != RESULT_OK || data == null) {
            result.success(emptyList<Map<String, String>>())
            return
        }

        val uris = mutableListOf<Uri>()
        data.clipData?.let { clipData ->
            for (index in 0 until clipData.itemCount) {
                uris.add(clipData.getItemAt(index).uri)
            }
        } ?: data.data?.let(uris::add)

        val videos = uris.map { uri ->
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
            mapOf(
                "uri" to uri.toString(),
                "name" to displayNameFor(uri),
            )
        }
        result.success(videos)
    }

    private fun pickLocalVideos(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("PICKER_BUSY", "A file picker is already open.", null)
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "video/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, PICK_VIDEOS_REQUEST)
    }

    private fun displayNameFor(uri: Uri): String {
        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(uri, null, null, null, null)
            val nameIndex = cursor?.getColumnIndex(OpenableColumns.DISPLAY_NAME) ?: -1
            if (cursor != null && cursor.moveToFirst() && nameIndex >= 0) {
                cursor.getString(nameIndex)
            } else {
                uri.lastPathSegment ?: "Local video"
            }
        } finally {
            cursor?.close()
        }
    }

    private fun withController(
        result: MethodChannel.Result,
        action: (MediaController) -> Unit,
    ) {
        controllerFuture.addListener(
            {
                try {
                    action(controllerFuture.get())
                } catch (error: Throwable) {
                    result.error("PLAYER_ERROR", error.message, null)
                }
            },
            MoreExecutors.directExecutor(),
        )
    }

    private fun playQueue(call: MethodCall, controller: MediaController) {
        PlaybackAuth.bearerToken = call.argument<String>("accessToken")
        val items = call.argument<List<Map<String, Any?>>>("items").orEmpty()
        val mediaItems = items.mapNotNull { item ->
            val uri = item["uri"] as? String ?: return@mapNotNull null
            val title = item["title"] as? String ?: "Untitled video"
            val id = item["id"] as? String ?: uri
            MediaItem.Builder()
                .setMediaId(id)
                .setUri(uri)
                .setMediaMetadata(MediaMetadata.Builder().setTitle(title).build())
                .build()
        }

        controller.setMediaItems(mediaItems)
        controller.repeatMode = Player.REPEAT_MODE_ALL
        controller.prepare()
        controller.play()
    }

    companion object {
        private const val CHANNEL = "drive_shuffle_player/playback"
        private const val PICK_VIDEOS_REQUEST = 4210
    }
}
