import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class DocumentEnhancementService {
  static final DocumentEnhancementService _instance = DocumentEnhancementService._internal();
  factory DocumentEnhancementService() => _instance;
  DocumentEnhancementService._internal();

  /// Stretches contrast and boosts brightness to simulate the 'magic color' scanner filter.
  static Uint8List applyMagicColor(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    
    // Stretch contrast and boost brightness slightly
    final enhanced = img.adjustColor(
      decoded,
      contrast: 1.25,
      brightness: 1.05,
    );
    return Uint8List.fromList(img.encodeJpg(enhanced, quality: 95));
  }

  static Uint8List applyRemini(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    
    // 3x3 8-neighbor details-boosting sharpening kernel (sum = 1.0)
    final sharpenKernel = [
      -0.5, -1.0, -0.5,
      -1.0,  7.0, -1.0,
      -0.5, -1.0, -0.5
    ];
    final sharpened = img.convolution(
      decoded,
      filter: sharpenKernel,
      div: 1.0,
    );
    final enhanced = img.adjustColor(
      sharpened,
      contrast: 1.20,
      brightness: 1.05,
      saturation: 1.15,
    );
    if (decoded.hasAlpha) {
      return Uint8List.fromList(img.encodePng(enhanced));
    }
    return Uint8List.fromList(img.encodeJpg(enhanced, quality: 95));
  }

  static Uint8List applyBinarization(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    
    // Convert to grayscale and apply thresholding
    final gray = img.grayscale(decoded);
    for (final pixel in gray) {
      final luminance = pixel.r.toInt();
      final newValue = luminance > 128 ? 255 : 0;
      pixel.r = newValue;
      pixel.g = newValue;
      pixel.b = newValue;
    }
    return Uint8List.fromList(img.encodeJpg(gray, quality: 90));
  }

  /// Runs the selected enhancement filter asynchronously inside a background Isolate.
  Future<Uint8List> enhanceImageAsync(Uint8List bytes, String filter) async {
    if (filter == 'binarized') {
      return compute(applyBinarization, bytes);
    } else if (filter == 'magic') {
      return compute(applyMagicColor, bytes);
    } else if (filter == 'remini') {
      return compute(applyRemini, bytes);
    }
    return bytes;
  }
}
