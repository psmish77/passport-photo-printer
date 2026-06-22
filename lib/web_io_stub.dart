import 'dart:typed_data';

/// Web stub for dart:io's File class.
/// On web, File paths don't exist — all image data is passed as bytes directly.
/// These methods return empty/no-op results and are never actually called
/// because all code paths using File are guarded by `if (!kIsWeb)`.
class File {
  final String path;
  const File(this.path);

  Future<Uint8List> readAsBytes() async => Uint8List(0);

  Future<bool> exists() async => false;
}

/// Web stub for dart:io's Platform class.
class Platform {
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isWindows => false;
  static bool get isMacOS => false;
  static bool get isLinux => false;
}
