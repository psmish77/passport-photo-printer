package com.example.panditji_printing_app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import com.google.mlkit.vision.segmentation.Segmentation
import com.google.mlkit.vision.segmentation.selfie.SelfieSegmenterOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "photoeditor.cutout/document_processor"
    private val REQUEST_CODE_SCAN = 1001
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "startScan") {
                if (pendingResult != null) {
                    result.error("ALREADY_SCANNING", "Another scan is already in progress", null)
                    return@setMethodCallHandler
                }
                pendingResult = result
                launchScanner()
            } else if (call.method == "removeBackground") {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("BAD_ARGS", "Missing path argument", null)
                    return@setMethodCallHandler
                }
                val file = File(path)
                if (!file.exists()) {
                    result.error("FILE_NOT_FOUND", "File does not exist", null)
                    return@setMethodCallHandler
                }
                
                try {
                    val bitmap = BitmapFactory.decodeFile(path)
                    val options = SelfieSegmenterOptions.Builder()
                        .setDetectorMode(SelfieSegmenterOptions.SINGLE_IMAGE_MODE)
                        .enableRawSizeMask()
                        .build()
                    val segmenter = Segmentation.getClient(options)
                    val inputImage = InputImage.fromBitmap(bitmap, 0)
                    
                    segmenter.process(inputImage)
                        .addOnSuccessListener { segmentationMask ->
                            val mask = segmentationMask.buffer
                            
                            val outBitmap = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
                            for (y in 0 until bitmap.height) {
                                for (x in 0 until bitmap.width) {
                                    val confidence = mask.float
                                    val color = bitmap.getPixel(x, y)
                                    if (confidence > 0.55f) {
                                        outBitmap.setPixel(x, y, color)
                                    } else {
                                        outBitmap.setPixel(x, y, Color.TRANSPARENT)
                                    }
                                }
                            }
                            
                            val tempFile = File.createTempFile("cutout_", ".png", cacheDir)
                            FileOutputStream(tempFile).use { out ->
                                outBitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                            }
                            result.success(tempFile.absolutePath)
                        }
                        .addOnFailureListener { e ->
                            result.error("SEGMENTATION_FAILED", e.message, null)
                        }
                } catch (e: Exception) {
                    result.error("PROCESSING_FAILED", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun launchScanner() {
        val options = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(true)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .build()

        val scanner = GmsDocumentScanning.getClient(options)
        scanner.getStartScanIntent(this)
            .addOnSuccessListener { intentSender ->
                try {
                    startIntentSenderForResult(intentSender, REQUEST_CODE_SCAN, null, 0, 0, 0)
                } catch (e: Exception) {
                    pendingResult?.error("SCAN_ERROR", "Failed to start intent sender: ${e.message}", null)
                    pendingResult = null
                }
            }
            .addOnFailureListener { e ->
                pendingResult?.error("SCAN_ERROR", "Failed to get scanner intent: ${e.message}", null)
                pendingResult = null
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_SCAN) {
            val result = GmsDocumentScanningResult.fromActivityResultIntent(data)
            if (resultCode == Activity.RESULT_OK && result != null) {
                val pages = result.pages
                val imagePaths = ArrayList<String>()
                if (pages != null) {
                    for (page in pages) {
                        val path = getFilePathFromContentUri(this, page.imageUri)
                        if (path != null) {
                            imagePaths.add(path)
                        }
                    }
                }
                pendingResult?.success(imagePaths)
            } else if (resultCode == Activity.RESULT_CANCELED) {
                pendingResult?.error("CANCELLED", "User cancelled scanning", null)
            } else {
                pendingResult?.error("SCAN_FAILED", "Document scanning failed", null)
            }
            pendingResult = null
        }
    }

    private fun getFilePathFromContentUri(context: Context, uri: Uri): String? {
        try {
            val inputStream = context.contentResolver.openInputStream(uri) ?: return null
            val tempFile = File.createTempFile("scanned_", ".jpg", context.cacheDir)
            tempFile.deleteOnExit()
            FileOutputStream(tempFile).use { outputStream ->
                inputStream.use { input ->
                    input.copyTo(outputStream)
                }
            }
            return tempFile.absolutePath
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }
}
