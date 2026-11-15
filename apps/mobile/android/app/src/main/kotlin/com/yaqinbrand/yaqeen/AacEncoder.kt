package com.yaqinbrand.yaqeen

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * «تلاواتي»: encodes the take's PCM (16-bit little-endian, mono) to AAC-LC in an MPEG-4 audio
 * file — contracts `RECORDING_FORMAT` (mono, 16 kHz, 32 kbps). Called once at the end of a
 * recording (`core/platform/plugin_voice_recorder.dart`); runs on its own thread and answers on
 * the main thread. Only the platform's own encoder and muxer: nothing bundled, nothing uploaded.
 */
object AacEncoder {
    private const val MIME = MediaFormat.MIMETYPE_AUDIO_AAC
    private const val TIMEOUT_US = 10_000L

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "encodePcm16") {
            result.notImplemented()
            return
        }
        val pcm = call.argument<ByteArray>("pcm")
        val path = call.argument<String>("path")
        val rate = call.argument<Int>("sampleRate") ?: 16000
        val bitRate = call.argument<Int>("bitRate") ?: 32000
        if (pcm == null || path == null) {
            result.error("bad_args", "pcm and path are required", null)
            return
        }
        val main = Handler(Looper.getMainLooper())
        Thread {
            try {
                encode(pcm, path, rate, bitRate)
                main.post { result.success(null) }
            } catch (e: Exception) {
                File(path).delete()
                main.post { result.error("encode_failed", e.message, null) }
            }
        }.start()
    }

    private fun encode(pcm: ByteArray, path: String, rate: Int, bitRate: Int) {
        val format = MediaFormat.createAudioFormat(MIME, rate, 1).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16 * 1024)
        }
        val codec = MediaCodec.createEncoderByType(MIME)
        File(path).parentFile?.mkdirs()
        val muxer = MediaMuxer(path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var track = -1
        var muxing = false
        try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            val info = MediaCodec.BufferInfo()
            var offset = 0
            var inputDone = false
            var outputDone = false
            val bytesPerSecond = rate * 2L
            while (!outputDone) {
                if (!inputDone) {
                    val index = codec.dequeueInputBuffer(TIMEOUT_US)
                    if (index >= 0) {
                        val buffer: ByteBuffer = codec.getInputBuffer(index)!!
                        buffer.clear()
                        val n = minOf(buffer.remaining() and 1.inv(), pcm.size - offset)
                        val ptsUs = offset * 1_000_000L / bytesPerSecond
                        if (n <= 0) {
                            codec.queueInputBuffer(index, 0, 0, ptsUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            buffer.order(ByteOrder.LITTLE_ENDIAN)
                            buffer.put(pcm, offset, n)
                            codec.queueInputBuffer(index, 0, n, ptsUs, 0)
                            offset += n
                        }
                    }
                }
                when (val out = codec.dequeueOutputBuffer(info, TIMEOUT_US)) {
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        track = muxer.addTrack(codec.outputFormat)
                        muxer.start()
                        muxing = true
                    }
                    MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                    else -> if (out >= 0) {
                        val data = codec.getOutputBuffer(out)!!
                        // The codec config (AudioSpecificConfig) travels in the track format, not as a sample.
                        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                        if (info.size > 0 && muxing) {
                            data.position(info.offset)
                            data.limit(info.offset + info.size)
                            muxer.writeSampleData(track, data, info)
                        }
                        codec.releaseOutputBuffer(out, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                    }
                }
            }
        } finally {
            try {
                codec.stop()
            } catch (_: Exception) {
            }
            codec.release()
            try {
                if (muxing) muxer.stop()
            } catch (_: Exception) {
            }
            muxer.release()
        }
        if (!muxing) throw IllegalStateException("no audio track")
    }
}
