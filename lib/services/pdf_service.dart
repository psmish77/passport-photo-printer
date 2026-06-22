import 'dart:io' if (dart.library.html) 'package:panditji_printing_app/web_io_stub.dart';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfService {
  static final PdfService _instance = PdfService._internal();
  factory PdfService() => _instance;
  PdfService._internal();

  /// Compiles multiple local scanned image paths into a standard A4 PDF document bytes.
  Future<Uint8List> generatePdf(List<String> imagePaths) async {
    final pdf = pw.Document();

    for (final path in imagePaths) {
      final bytes = await File(path).readAsBytes();
      final pdfImg = pw.MemoryImage(bytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (context) {
            return pw.Center(
              child: pw.Image(pdfImg, fit: pw.BoxFit.contain),
            );
          },
        ),
      );
    }
    return pdf.save();
  }
}
