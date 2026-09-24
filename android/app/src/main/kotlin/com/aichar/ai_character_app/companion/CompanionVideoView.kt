package com.aichar.ai_character_app.companion

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.widget.FrameLayout
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import com.aichar.ai_character_app.R
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

/**
 * 与 preview.html 相同：双 ExoPlayer + 双 TextureView 叠层。
 * 切换只改 visibility（不用 GONE、不重绑 playerView.player），
 * 片尾预载下一条 → play → 再显隐，避免单播放器 loop/换条目时的黑帧。
 */
class CompanionVideoView(
    context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
) : PlatformView, MethodChannel.MethodCallHandler {

    private val appContext = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())
    private val frame = FrameLayout(context)
    private val playerViewA: PlayerView = inflatePlayerView(context)
    private val playerViewB: PlayerView = inflatePlayerView(context)
    private val dataSourceFactory = DefaultDataSource.Factory(appContext)
    private val playerA: ExoPlayer = buildPlayer(appContext)
    private val playerB: ExoPlayer = buildPlayer(appContext)
    private val channel =
        MethodChannel(messenger, "com.aichar.ai_character_app/companion_video_$viewId")
    private val flutterLoader = FlutterInjector.instance().flutterLoader()

    private var clips: List<String> = emptyList()
    private var singleLoop = true
    private var actions: Map<String, String> = emptyMap()
    private var clipIndex = 0
    private var activeIsB = false
    private var standbyAsset: String? = null
    private var pendingActionId: String? = null
    private var pendingInsertAsset: String? = null
    private var playingInsert = false
    private var resumeMainAsset: String? = null
    private var swapLock = false
    private var disposed = false
    private var lastEmittedActiveIsB = false
    private var lastEmittedPendingActionId: String? = null

    private val progressTick = object : Runnable {
        override fun run() {
            if (disposed) return
            val active = activePlayer
            if (!swapLock && active.isPlaying && active.duration > 0 &&
                active.currentPosition >= active.duration - NEAR_END_MS
            ) {
                onNearEnd()
            }
            handler.postDelayed(this, 32)
        }
    }

    init {
        channel.setMethodCallHandler(this)
        hideShutter(playerViewA)
        hideShutter(playerViewB)
        frame.addView(
            playerViewA,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        frame.addView(
            playerViewB,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        playerViewA.player = playerA
        playerViewB.player = playerB
        updateVisibility()

        val errorListener = object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                Log.e(TAG, "Player error: ${error.message}", error)
                channel.invokeMethod(
                    "error",
                    mapOf("message" to (error.message ?: "playback error")),
                )
            }
        }
        playerA.addListener(errorListener)
        playerB.addListener(errorListener)
        fun playbackListener(who: ExoPlayer) = object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_READY &&
                    who === activePlayer &&
                    !playingInsert
                ) {
                    channel.invokeMethod("ready", null)
                }
                if (playbackState == Player.STATE_ENDED &&
                    playingInsert &&
                    who === activePlayer
                ) {
                    finishInsert()
                }
            }
        }
        playerA.addListener(playbackListener(playerA))
        playerB.addListener(playbackListener(playerB))
        handler.post(progressTick)
    }

    private fun inflatePlayerView(context: Context): PlayerView {
        return LayoutInflater.from(context)
            .inflate(R.layout.companion_player_view, frame, false) as PlayerView
    }

    private fun hideShutter(view: PlayerView) {
        view.post {
            view.findViewById<View>(androidx.media3.ui.R.id.exo_shutter)?.visibility = View.GONE
        }
    }

    private fun buildPlayer(context: Context): ExoPlayer {
        return ExoPlayer.Builder(context)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dataSourceFactory))
            .build()
    }

    private val activePlayer: ExoPlayer
        get() = if (activeIsB) playerB else playerA

    private val standbyPlayer: ExoPlayer
        get() = if (activeIsB) playerA else playerB

    private fun isActivePlayer(player: ExoPlayer): Boolean = player === activePlayer

    private fun updateVisibility() {
        if (activeIsB) {
            playerViewA.visibility = View.INVISIBLE
            playerViewB.visibility = View.VISIBLE
        } else {
            playerViewA.visibility = View.VISIBLE
            playerViewB.visibility = View.INVISIBLE
        }
    }

    private fun assetMediaItem(flutterAsset: String): MediaItem {
        val key = flutterLoader.getLookupKeyForAsset(flutterAsset)
        return MediaItem.fromUri("asset:///$key")
    }

    private fun emitState(force: Boolean = false) {
        val pending = pendingActionId
        if (!force &&
            activeIsB == lastEmittedActiveIsB &&
            pending == lastEmittedPendingActionId
        ) {
            return
        }
        lastEmittedActiveIsB = activeIsB
        lastEmittedPendingActionId = pending
        channel.invokeMethod(
            "state",
            mapOf(
                "activeIsB" to activeIsB,
                "pendingActionId" to pending,
            ),
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                clips = call.argument<List<String>>("clips") ?: emptyList()
                singleLoop = call.argument<Boolean>("singleLoop") ?: true
                actions = call.argument<Map<String, String>>("actions") ?: emptyMap()
                Log.d(TAG, "start clips=$clips singleLoop=$singleLoop")
                startPlayback(result)
            }
            "queueAction" -> {
                queueAction(call.argument<String>("actionId").orEmpty())
                result.success(null)
            }
            "dispose" -> {
                disposeInternal()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startPlayback(result: MethodChannel.Result) {
        if (clips.isEmpty()) {
            result.error("start_failed", "clips empty", null)
            return
        }
        try {
            swapLock = false
            clipIndex = 0
            activeIsB = false
            playingInsert = false
            pendingActionId = null
            pendingInsertAsset = null
            resumeMainAsset = null
            standbyAsset = null

            playerA.stop()
            playerA.clearMediaItems()
            playerB.stop()
            playerB.clearMediaItems()

            val first = clips.first()
            playerA.setMediaItem(assetMediaItem(first))
            playerA.repeatMode = Player.REPEAT_MODE_OFF
            playerA.prepare()
            playerA.playWhenReady = true
            playerA.play()
            updateVisibility()

            if (!singleLoop && clips.size > 1) {
                preloadStandby(clips[1], warm = true)
            }

            lastEmittedActiveIsB = true
            emitState(force = true)
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "startPlayback failed", e)
            result.error("start_failed", e.message, null)
        }
    }

    private fun nextClipIndex(): Int = (clipIndex + 1) % clips.size

    /** 与 HTML preload 一致：加载 → 短暂 play → pause 在首帧，解码器就绪。 */
    private fun preloadStandby(asset: String, warm: Boolean = true) {
        if (standbyAsset == asset &&
            standbyPlayer.playbackState == Player.STATE_READY &&
            standbyPlayer.mediaItemCount > 0
        ) {
            return
        }
        standbyAsset = asset
        val target = standbyPlayer
        target.stop()
        target.clearMediaItems()
        target.repeatMode = Player.REPEAT_MODE_OFF
        target.setMediaItem(assetMediaItem(asset))
        target.prepare()
        target.playWhenReady = false

        val onReady = Runnable {
            if (disposed) return@Runnable
            target.seekTo(0)
            if (!warm) return@Runnable
            target.playWhenReady = true
            target.play()
            handler.postDelayed({
                if (disposed) return@postDelayed
                target.pause()
                target.seekTo(0)
                target.playWhenReady = false
            }, PRELOAD_WARM_MS)
        }
        if (target.playbackState == Player.STATE_READY) {
            onReady.run()
        } else {
            val listener = object : Player.Listener {
                override fun onPlaybackStateChanged(playbackState: Int) {
                    if (playbackState == Player.STATE_READY) {
                        target.removeListener(this)
                        onReady.run()
                    }
                }
            }
            target.addListener(listener)
        }
    }

    private fun queueAction(actionId: String) {
        val url = actions[actionId] ?: return
        if (pendingInsertAsset != null || playingInsert) return
        pendingActionId = actionId
        pendingInsertAsset = url
        preloadStandby(url, warm = true)
        emitState()
    }

    private fun onNearEnd() {
        if (swapLock || playingInsert) return

        if (singleLoop || clips.size <= 1) {
            if (pendingInsertAsset != null) {
                trySwapToInsert()
            } else {
                swapLock = true
                activePlayer.seekTo(0)
                activePlayer.playWhenReady = true
                activePlayer.play()
                handler.postDelayed({ swapLock = false }, 200)
            }
            return
        }

        swapLock = true
        if (pendingInsertAsset != null) {
            trySwapToInsert()
            return
        }

        val nextIdx = nextClipIndex()
        val nextAsset = clips[nextIdx]
        if (standbyAsset != nextAsset) {
            preloadStandby(nextAsset, warm = true)
            handler.postDelayed({
                swapLock = false
                onNearEnd()
            }, 120)
            return
        }
        clipIndex = nextIdx
        swapPlayers()
        preloadStandby(clips[nextClipIndex()], warm = true)
        handler.postDelayed({ swapLock = false }, 120)
    }

    private fun trySwapToInsert() {
        val insert = pendingInsertAsset ?: return
        if (standbyAsset != insert) {
            preloadStandby(insert, warm = true)
            handler.postDelayed({
                swapLock = false
                onNearEnd()
            }, 120)
            return
        }
        resumeMainAsset = clips[clipIndex]
        pendingInsertAsset = null
        pendingActionId = null
        playingInsert = true
        swapPlayers()
        emitState()
        handler.postDelayed({ swapLock = false }, 120)
    }

    /** HTML swap：standby 先 play，再改显隐，再 pause 旧路。 */
    private fun swapPlayers() {
        val next = standbyPlayer
        val prev = activePlayer
        if (next.duration > 0 && next.currentPosition >= next.duration - 100) {
            next.seekTo(0)
        }
        next.playWhenReady = true
        next.play()
        activeIsB = !activeIsB
        updateVisibility()
        prev.playWhenReady = false
        prev.pause()
        Log.d(TAG, "swap visible=${if (activeIsB) "B" else "A"} asset=$standbyAsset")
    }

    private fun finishInsert() {
        if (!playingInsert) return
        playingInsert = false
        val resume = resumeMainAsset ?: clips[clipIndex]
        resumeMainAsset = null
        standbyAsset = resume
        preloadStandby(resume, warm = true)
        handler.postDelayed({
            swapPlayers()
            if (!singleLoop && clips.size > 1) {
                preloadStandby(clips[nextClipIndex()], warm = true)
            }
            emitState()
        }, 80)
    }

    override fun getView(): View = frame

    override fun dispose() = disposeInternal()

    private fun disposeInternal() {
        if (disposed) return
        disposed = true
        handler.removeCallbacksAndMessages(null)
        playerViewA.player = null
        playerViewB.player = null
        playerA.release()
        playerB.release()
        channel.setMethodCallHandler(null)
    }

    companion object {
        private const val TAG = "CompanionVideoView"
        private const val NEAR_END_MS = 100L
        private const val PRELOAD_WARM_MS = 60L
    }
}
