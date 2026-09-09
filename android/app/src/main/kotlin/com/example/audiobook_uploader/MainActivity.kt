package com.example.audiobook_uploader

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.audiobook_uploader/files"
    private val REQUEST_CODE_PICK_FILE = 1001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFile" -> {
                        pickAudioFile(result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickAudioFile(result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "audio/*"
            addCategory(Intent.CATEGORY_OPENABLE)
        }
        startActivityForResult(intent, REQUEST_CODE_PICK_FILE)

        // Store the result for onActivityResult
        filePickerResult = result
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == REQUEST_CODE_PICK_FILE && resultCode == Activity.RESULT_OK) {
            val uri = data?.data
            if (uri != null) {
                val filePath = getFilePathFromUri(uri)
                filePickerResult?.success(filePath)
            } else {
                filePickerResult?.error("ERROR", "No file selected", null)
            }
            filePickerResult = null
        } else {
            filePickerResult?.error("CANCELLED", "File picker cancelled", null)
            filePickerResult = null
        }
    }

    private fun getFilePathFromUri(uri: Uri): String {
        val cursor = contentResolver.query(uri, arrayOf(MediaStore.Audio.Media.DATA), null, null, null)
        cursor?.use {
            if (it.moveToFirst()) {
                val columnIndex = it.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                return it.getString(columnIndex)
            }
        }
        // Fallback: return the URI path
        return uri.path ?: ""
    }

    companion object {
        private var filePickerResult: MethodChannel.Result? = null
    }
}
