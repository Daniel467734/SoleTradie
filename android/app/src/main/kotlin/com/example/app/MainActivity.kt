package com.example.app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import java.io.File
import java.io.FileWriter
import java.io.PrintWriter

class MainActivity : FlutterActivity() {

  companion object {
    private val defaultUEH = Thread.getDefaultUncaughtExceptionHandler()
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
      logNativeCrash(throwable)
      defaultUEH?.uncaughtException(thread, throwable)
    }
  }

  private fun logNativeCrash(throwable: Throwable) {
    try {
      val logFile = File(filesDir, "native_crash.log")
      FileWriter(logFile, true).use { writer ->
        writer.append("=== ${System.currentTimeMillis()} ===\n")
        throwable.printStackTrace(PrintWriter(writer))
        writer.append("\n")
      }
    } catch (e: Exception) {
      e.printStackTrace()
    }
  }
}
