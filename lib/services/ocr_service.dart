import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OCRService {
  static final OCRService _instance = OCRService._internal();
  factory OCRService() => _instance;
  OCRService._internal();

  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Performs OCR on an image file path and returns the recognized text blocks, lines, and elements.
  Future<RecognizedText?> performOCR(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      return await _recognizer.processImage(inputImage);
    } catch (e) {
      debugPrint("OCR processing failed: $e");
      return null;
    }
  }

  /// Closes the underlying ML Kit resources.
  void dispose() {
    _recognizer.close();
  }
}
