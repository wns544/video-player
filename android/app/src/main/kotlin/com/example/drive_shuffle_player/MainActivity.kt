package com.example.drive_shuffle_player

import android.content.ComponentName
import android.content.Intent
import android.database.Cursor
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.util.Log
import java.io.ByteArrayOutputStream
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
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory("drive_shuffle_player/mini_player", MiniPlayerViewFactory(this))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickLocalVideos" -> pickLocalVideos(result)
                    "openPlayer" -> withController(result) { controller ->
                        openPlayer(controller, result)
                    }
                    "playQueue" -> withController(result) { controller ->
                        playQueue(call, controller, result)
                    }
                    "updateAccessToken" -> withController(result) { controller ->
                        updateAccessToken(call, controller, result)
                    }
                    "getPlaybackState" -> withController(result) { controller ->
                        result.success(playbackState(controller))
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
                        PlaybackAuth.authError = false
                        PlaybackAuth.lastHttpStatusCode = null
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
                "size" to sizeFor(uri),
                "duration" to durationFor(uri),
                "thumbnail" to thumbnailFor(uri),
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

    private fun openPlayer() {
        startActivity(Intent(this, PlayerActivity::class.java))
    }

    private fun openPlayer(controller: MediaController, result: MethodChannel.Result) {
        if (controller.mediaItemCount <= 0) {
            Log.d(TAG, "openPlayer blocked: empty queue")
            result.error("EMPTY_QUEUE", "No videos are queued.", null)
            return
        }
        Log.d(TAG, "openPlayer: mediaItemCount=${controller.mediaItemCount}")
        openPlayer()
        result.success(null)
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

    private fun sizeFor(uri: Uri): Long? {
        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(uri, null, null, null, null)
            val sizeIndex = cursor?.getColumnIndex(OpenableColumns.SIZE) ?: -1
            if (cursor != null && cursor.moveToFirst() && sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                cursor.getLong(sizeIndex)
            } else {
                null
            }
        } finally {
            cursor?.close()
        }
    }

    private fun durationFor(uri: Uri): Long? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(this, uri)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
        } catch (_: Throwable) {
            null
        } finally {
            retriever.release()
        }
    }

    private fun thumbnailFor(uri: Uri): ByteArray? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(this, uri)
            val bitmap = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: return null
            val scaled = Bitmap.createScaledBitmap(bitmap, 320, 180, true)
            ByteArrayOutputStream().use { output ->
                scaled.compress(Bitmap.CompressFormat.JPEG, 72, output)
                output.toByteArray()
            }
        } catch (_: Throwable) {
            null
        } finally {
            retriever.release()
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

    private fun playQueue(
        call: MethodCall,
        controller: MediaController,
        result: MethodChannel.Result,
    ) {
        val items = call.argument<List<Map<String, Any?>>>("items").orEmpty()
        if (items.isEmpty()) {
            Log.d(TAG, "playQueue blocked: empty input")
            result.error("EMPTY_QUEUE", "No videos were provided.", null)
            return
        }

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
        if (mediaItems.isEmpty()) {
            Log.d(TAG, "playQueue blocked: no valid media items")
            result.error("EMPTY_QUEUE", "No playable videos were provided.", null)
            return
        }

        PlaybackAuth.bearerToken = call.argument<String>("accessToken")
        PlaybackAuth.authError = false
        PlaybackAuth.lastHttpStatusCode = null
        val requestedStartIndex = call.argument<Int>("startIndex") ?: 0
        val startPositionMs = (call.argument<Number>("startPositionMs") ?: 0).toLong()
        val startIndex = requestedStartIndex.coerceIn(0, mediaItems.size - 1)
        controller.setMediaItems(mediaItems, startIndex, startPositionMs.coerceAtLeast(0L))
        controller.repeatMode = Player.REPEAT_MODE_ALL
        controller.prepare()
        controller.play()
        Log.d(TAG, "playQueue loaded: mediaItemCount=${mediaItems.size}, startIndex=$startIndex")
        result.success(mediaItems.size)
    }

    private fun updateAccessToken(
        call: MethodCall,
        controller: MediaController,
        result: MethodChannel.Result,
    ) {
        PlaybackAuth.bearerToken = call.argument<String>("accessToken")
        PlaybackAuth.authError = false
        PlaybackAuth.lastHttpStatusCode = null
        val retry = call.argument<Boolean>("retry") ?: false
        if (retry && controller.mediaItemCount > 0) {
            val position = controller.currentPosition.coerceAtLeast(0L)
            controller.seekTo(controller.currentMediaItemIndex, position)
            controller.prepare()
            controller.play()
        }
        result.success(null)
    }

    private fun playbackState(controller: MediaController): Map<String, Any?> {
        val duration = controller.duration.takeIf { it >= 0 } ?: 0L
        return mapOf(
            "mediaId" to controller.currentMediaItem?.mediaId,
            "currentIndex" to controller.currentMediaItemIndex,
            "positionMs" to controller.currentPosition.coerceAtLeast(0L),
            "durationMs" to duration,
            "isPlaying" to controller.isPlaying,
            "mediaItemCount" to controller.mediaItemCount,
            "playbackState" to controller.playbackState,
            "authError" to PlaybackAuth.authError,
            "httpStatusCode" to PlaybackAuth.lastHttpStatusCode,
            "playerErrorCode" to controller.playerError?.errorCodeName,
        )
    }

    companion object {
        private const val CHANNEL = "drive_shuffle_player/playback"
        private const val PICK_VIDEOS_REQUEST = 4210
        private const val TAG = "DriveShuffleMain"
    }
}
