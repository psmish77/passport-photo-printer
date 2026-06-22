import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class QRCodeService {
  static final QRCodeService _instance = QRCodeService._internal();
  factory QRCodeService() => _instance;
  QRCodeService._internal();

  final BarcodeScanner _scanner = BarcodeScanner();

  /// Processes the image at the given file path and returns detected barcode/QR data.
  Future<List<Barcode>?> scanBarcodes(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      return await _scanner.processImage(inputImage);
    } catch (e) {
      debugPrint("Barcode scanning failed: $e");
      return null;
    }
  }

  /// Closes the barcode scanner client.
  void dispose() {
    _scanner.close();
  }
}
