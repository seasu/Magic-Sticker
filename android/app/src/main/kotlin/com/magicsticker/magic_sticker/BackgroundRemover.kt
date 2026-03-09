package com.magicsticker.magic_sticker

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import com.google.firebase.crashlytics.FirebaseCrashlytics
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import java.io.ByteArrayOutputStream

object BackgroundRemover {

    fun remove(
        context: Context,
        imageBytes: ByteArray,
        onSuccess: (ByteArray) -> Unit,
        onError: (Exception) -> Unit,
    ) {
        FirebaseCrashlytics.getInstance().log("BackgroundRemover.remove: start")

        val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
            ?: run {
                onError(IllegalArgumentException("Failed to decode bitmap"))
                return
            }

        val options = SubjectSegmenterOptions.Builder()
            .enableForegroundConfidenceMask()
            .build()

        val segmenter = SubjectSegmentation.getClient(options)
        val inputImage = InputImage.fromBitmap(bitmap, 0)

        segmenter.process(inputImage)
            .addOnSuccessListener { result ->
                try {
                    FirebaseCrashlytics.getInstance()
                        .log("BackgroundRemover.remove: segmentation done")

                    val mask = result.foregroundConfidenceMask
                        ?: throw IllegalStateException("Confidence mask is null")
                    val maskArray = FloatArray(mask.remaining()).also { mask.get(it) }

                    val output = Bitmap.createBitmap(
                        bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888,
                    )
                    val canvas = Canvas(output)
                    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
                    canvas.drawBitmap(bitmap, 0f, 0f, paint)

                    // Alpha masking：信心度 < 0.5 的像素設為透明
                    paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
                    val maskBitmap = confidenceMaskToBitmap(
                        maskArray, bitmap.width, bitmap.height,
                    )
                    canvas.drawBitmap(maskBitmap, 0f, 0f, paint)
                    maskBitmap.recycle()

                    val stream = ByteArrayOutputStream()
                    output.compress(Bitmap.CompressFormat.PNG, 100, stream)
                    output.recycle()
                    bitmap.recycle()

                    FirebaseCrashlytics.getInstance()
                        .log("BackgroundRemover.remove: done")
                    onSuccess(stream.toByteArray())
                } catch (e: Exception) {
                    FirebaseCrashlytics.getInstance().recordException(e)
                    onError(e)
                }
            }
            .addOnFailureListener { e ->
                FirebaseCrashlytics.getInstance().recordException(e)
                onError(e)
            }
    }

    private fun confidenceMaskToBitmap(
        mask: FloatArray,
        width: Int,
        height: Int,
    ): Bitmap {
        val pixels = IntArray(width * height) { i ->
            val confidence = mask[i]
            val alpha = (confidence * 255).toInt().coerceIn(0, 255)
            alpha shl 24 // ARGB — 只設定 alpha，RGB 由 DST_IN 保留原圖
        }
        return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
    }
}
