import 'dart:io' if (dart.library.html) 'package:panditji_printing_app/web_io_stub.dart' show Platform;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

class DocumentScannerService {
  static const MethodChannel _channel = MethodChannel('photoeditor.cutout/document_processor');

  static final DocumentScannerService _instance = DocumentScannerService._internal();
  factory DocumentScannerService() => _instance;
  DocumentScannerService._internal();

  /// Launches the native Google Play Services Document Scanner on Android.
  /// Returns a list of local temporary file paths to the scanned page images, or null if cancelled.
  Future<List<String>?> startScan() async {
    if (!Platform.isAndroid) {
      return null;
    }
    try {
      final List<dynamic>? result = await _channel.invokeMethod('startScan');
      if (result == null) return null;
      return result.cast<String>();
    } on PlatformException catch (e) {
      debugPrint("Failed to run native document scanner: ${e.message}");
      return null;
    }
  }
}
