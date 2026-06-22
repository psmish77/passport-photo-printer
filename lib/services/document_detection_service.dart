import 'dart:math';

class DocumentDetectionService {
  static final DocumentDetectionService _instance = DocumentDetectionService._internal();
  factory DocumentDetectionService() => _instance;
  DocumentDetectionService._internal();

  /// Helper to calculate default quadrilateral boundaries if manual correction is triggered.
  List<Point<int>> getInitialQuad(int width, int height) {
    return [
      Point<int>((width * 0.1).toInt(), (height * 0.1).toInt()),
      Point<int>((width * 0.9).toInt(), (height * 0.1).toInt()),
      Point<int>((width * 0.9).toInt(), (height * 0.9).toInt()),
      Point<int>((width * 0.1).toInt(), (height * 0.9).toInt()),
    ];
  }
}
