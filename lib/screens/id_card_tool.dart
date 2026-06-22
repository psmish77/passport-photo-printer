import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/document_scanner_service.dart';
import '../services/document_enhancement_service.dart';
import '../services/ocr_service.dart';
import '../services/qrcode_service.dart';

class IDCardData {
  String? originalPath;
  Uint8List? processedBytes;
  Uint8List? filteredBytes;
  double brightness = 1.0;
  double contrast = 1.0;
  double saturation = 1.0;
  double aspect = 1.58;
  String filter = 'original';

  // OCR & QR code data
  String? extractedText;
  String? qrCodeData;
  Map<String, String>? keyDetails;
  bool isOcrRunning = false;
}

class IdCardToolScreen extends StatefulWidget {
  const IdCardToolScreen({super.key});

  @override
  State<IdCardToolScreen> createState() => _IdCardToolScreenState();
}

class _IdCardToolScreenState extends State<IdCardToolScreen> {
  String _docType = '2-side-aadhar';
  final IDCardData _front = IDCardData();
  final IDCardData _back = IDCardData();
  final ImagePicker _picker = ImagePicker();
  bool _isProcessingPDF = false;

  static Uint8List _resizeIDImage(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    if (decoded.width <= 1000) return bytes;
    final resized = img.copyResize(decoded, width: 1000);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 95));
  }

  List<double> _createColorMatrix(double brightness, double contrast, double saturation) {
    final double b = brightness;
    final double c = contrast;
    final double s = saturation;
    final double t = 128.0 * (1.0 - c);

    const double lr = 0.2126;
    const double lg = 0.7152;
    const double lb = 0.0722;

    final double rR = lr * (1.0 - s) + s;
    final double rG = lg * (1.0 - s);
    final double rB = lb * (1.0 - s);

    final double gR = lr * (1.0 - s);
    final double gG = lg * (1.0 - s) + s;
    final double gB = lb * (1.0 - s);

    final double bR = lr * (1.0 - s);
    final double bG = lg * (1.0 - s);
    final double bB = lb * (1.0 - s) + s;

    return [
      c * rR * b, c * rG * b, c * rB * b, 0.0, t,
      c * gR * b, c * gG * b, c * gB * b, 0.0, t,
      c * bR * b, c * bG * b, c * bB * b, 0.0, t,
      0.0,        0.0,        0.0,        1.0, 0.0,
    ];
  }

  Future<void> _pickAndCrop(bool isFront) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (!mounted) return;
    if (image == null) return;

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: image.path,
      aspectRatio: _docType == '1-side-aadhar' ? null : const CropAspectRatio(ratioX: 85.6, ratioY: 54.0),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Document',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: Colors.deepPurple,
          lockAspectRatio: _docType != '1-side-aadhar',
        ),
        WebUiSettings(
          context: context,
          presentStyle: WebPresentStyle.dialog,
          size: const CropperSize(
            width: 450,
            height: 450,
          ),
        ),
      ],
    );

    if (croppedFile == null) return;

    final bytes = await croppedFile.readAsBytes();
    final resizedBytes = await compute(_resizeIDImage, bytes);
    final decoded = await compute(_decodeAspect, resizedBytes);

    final data = isFront ? _front : _back;
    setState(() {
      data.originalPath = croppedFile.path;
      data.processedBytes = resizedBytes;
      data.filteredBytes = resizedBytes;
      data.aspect = decoded;
      data.filter = 'original';
    });

    _runOCRAndBarcode(isFront);
  }

  Future<void> _scanDocument(bool isFront) async {
    final paths = await DocumentScannerService().startScan();
    if (paths == null || paths.isEmpty) return;

    final scannedPath = paths.first;
    final bytes = await File(scannedPath).readAsBytes();
    final resizedBytes = await compute(_resizeIDImage, bytes);
    final decodedAspect = await compute(_decodeAspect, resizedBytes);

    final data = isFront ? _front : _back;
    setState(() {
      data.originalPath = scannedPath;
      data.processedBytes = resizedBytes;
      data.filteredBytes = resizedBytes;
      data.aspect = decodedAspect;
      data.filter = 'original';
    });

    _runOCRAndBarcode(isFront);
  }

  Future<void> _runOCRAndBarcode(bool isFront) async {
    final data = isFront ? _front : _back;
    if (data.originalPath == null) return;

    setState(() {
      data.isOcrRunning = true;
      data.extractedText = null;
      data.qrCodeData = null;
      data.keyDetails = null;
    });

    try {
      final ocrResult = await OCRService().performOCR(data.originalPath!);
      String? text;
      Map<String, String> details = {};
      if (ocrResult != null) {
        text = ocrResult.text;
        
        final aadhaarRegex = RegExp(r'\b\d{4}\s\d{4}\s\d{4}\b|\b\d{12}\b');
        final aadhaarMatch = aadhaarRegex.firstMatch(text);
        if (aadhaarMatch != null) {
          details['Aadhaar No'] = aadhaarMatch.group(0)!;
        }

        final panRegex = RegExp(r'\b[A-Z]{5}[0-9]{4}[A-Z]\b');
        final panMatch = panRegex.firstMatch(text);
        if (panMatch != null) {
          details['PAN No'] = panMatch.group(0)!;
        }

        final dobRegex = RegExp(r'(?:DOB|Date of Birth|Birth|जन्मतिथि)[\s:]*([0-9/.-]+)', caseSensitive: false);
        final dobMatch = dobRegex.firstMatch(text);
        if (dobMatch != null && dobMatch.groupCount >= 1) {
          details['DOB'] = dobMatch.group(1)!;
        } else {
          final dateRegex = RegExp(r'\b\d{2}[/.-]\d{2}[/.-]\d{4}\b');
          final dateMatch = dateRegex.firstMatch(text);
          if (dateMatch != null) {
            details['Date'] = dateMatch.group(0)!;
          }
        }
      }

      final barcodes = await QRCodeService().scanBarcodes(data.originalPath!);
      String? qrData;
      if (barcodes != null && barcodes.isNotEmpty) {
        qrData = barcodes.first.rawValue;
        if (qrData != null) {
          if (qrData.startsWith('<?xml') || qrData.contains('PrintLetterBarcodeData')) {
            details['Aadhaar QR'] = 'Secure QR Data';
            final nameRegex = RegExp(r'name="([^"]+)"');
            final yobRegex = RegExp(r'yob="([^"]+)"');
            final genderRegex = RegExp(r'gender="([^"]+)"');
            final uidRegex = RegExp(r'uid="([^"]+)"');
            
            final nameMatch = nameRegex.firstMatch(qrData);
            final yobMatch = yobRegex.firstMatch(qrData);
            final genderMatch = genderRegex.firstMatch(qrData);
            final uidMatch = uidRegex.firstMatch(qrData);
            
            if (uidMatch != null) details['UID'] = uidMatch.group(1)!;
            if (nameMatch != null) details['Name'] = nameMatch.group(1)!;
            if (yobMatch != null) details['YOB'] = yobMatch.group(1)!;
            if (genderMatch != null) details['Gender'] = genderMatch.group(1)!;
          } else {
            details['QR/Barcode'] = qrData;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        data.extractedText = text;
        data.qrCodeData = qrData;
        data.keyDetails = details.isNotEmpty ? details : null;
        data.isOcrRunning = false;
      });
    } catch (e) {
      debugPrint("OCR/Barcode analysis failed: $e");
      if (!mounted) return;
      setState(() {
        data.isOcrRunning = false;
      });
    }
  }

  Future<void> _updateFilter(bool isFront, String filterName) async {
    final data = isFront ? _front : _back;
    if (data.processedBytes == null) return;

    setState(() {
      data.filter = filterName;
    });

    final enhanced = await DocumentEnhancementService().enhanceImageAsync(
      data.processedBytes!,
      filterName,
    );

    setState(() {
      data.filteredBytes = enhanced;
    });
  }

  void _showImageSourceSelector(bool isFront) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              const Text('Select Source', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(LucideIcons.camera),
                title: const Text('Scan Document (Camera)'),
                subtitle: const Text('Auto border detection and skew correction'),
                onTap: () {
                  Navigator.pop(context);
                  _scanDocument(isFront);
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.image),
                title: const Text('Upload Photo (Gallery)'),
                subtitle: const Text('Pick existing photo and crop manually'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndCrop(isFront);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  static double _decodeAspect(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return 1.58;
    return decoded.width / decoded.height;
  }

  Future<Uint8List> _applyFilters(Uint8List bytes, double b, double c, double s) async {
    if (b == 1.0 && c == 1.0 && s == 1.0) return bytes;
    return compute(_filterWork, {'bytes': bytes, 'b': b, 'c': c, 's': s});
  }

  static Uint8List _filterWork(Map<String, dynamic> args) {
    final bytes = args['bytes'] as Uint8List;
    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    decoded = img.adjustColor(
      decoded,
      brightness: (args['b'] as double) - 1.0,
      contrast: (args['c'] as double) - 1.0,
      saturation: (args['s'] as double) - 1.0,
    );
    return Uint8List.fromList(img.encodeJpg(decoded, quality: 100));
  }

  Future<void> _generatePDF() async {
    if (_front.originalPath == null) return;
    if (_docType == '2-side-aadhar' && _back.originalPath == null) return;

    setState(() => _isProcessingPDF = true);

    final frontBytes = await _applyFilters(
      _front.filteredBytes ?? _front.processedBytes!, _front.brightness, _front.contrast, _front.saturation,
    );
    final frontImage = pw.MemoryImage(frontBytes);

    pw.MemoryImage? backImage;
    if (_docType == '2-side-aadhar') {
      final backBytes = await _applyFilters(
        _back.filteredBytes ?? _back.processedBytes!, _back.brightness, _back.contrast, _back.saturation,
      );
      backImage = pw.MemoryImage(backBytes);
    }

    final pdf = pw.Document();

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (pw.Context ctx) {
        const double mm = PdfPageFormat.mm;
        const double a4w = 210.0;

        if (_docType == '1-side-aadhar') {
          // Long Aadhar — full width stretched to preserve aspect ratio
          const double printW = 180.0;
          final double printH = printW / _front.aspect;
          final double startX = (a4w - printW) / 2;
          return pw.Stack(children: [
            pw.Positioned(
              left: startX * mm,
              top: 40 * mm,
              child: pw.Image(frontImage, width: printW * mm, height: printH * mm, fit: pw.BoxFit.fill),
            ),
          ]);
        } else if (_docType == '2-side-aadhar') {
          const double cardW = 85.6;
          const double cardH = 54.0;
          final double startX = (a4w - cardW) / 2;
          return pw.Stack(children: [
            pw.Positioned(
              left: startX * mm,
              top: 30 * mm,
              child: pw.Image(frontImage, width: cardW * mm, height: cardH * mm, fit: pw.BoxFit.fill),
            ),
            pw.Positioned(
              left: startX * mm,
              top: (30 + cardH + 15) * mm,
              child: pw.Image(backImage!, width: cardW * mm, height: cardH * mm, fit: pw.BoxFit.fill),
            ),
          ]);
        } else {
          // Single PAN / DL
          const double cardW = 85.6;
          const double cardH = 54.0;
          final double startX = (a4w - cardW) / 2;
          return pw.Stack(children: [
            pw.Positioned(
              left: startX * mm,
              top: 40 * mm,
              child: pw.Image(frontImage, width: cardW * mm, height: cardH * mm, fit: pw.BoxFit.fill),
            ),
          ]);
        }
      },
    ));

    setState(() => _isProcessingPDF = false);

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: '$_docType-document.pdf',
    );
  }

  void _showPdfEnhancerDialog(VoidCallback onProceed) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(LucideIcons.sparkles, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text('PDF Enhancer'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose a quick enhancement filter to optimize the print quality of the generated ID Card PDF:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              _buildEnhancerOption(
                title: 'Original',
                desc: 'Keep original processed card colors.',
                icon: LucideIcons.file,
                onTap: () async {
                  setState(() => _isProcessingPDF = true);
                  Navigator.pop(context);
                  await _updateFilter(true, 'original');
                  if (_docType == '2-side-aadhar') {
                    await _updateFilter(false, 'original');
                  }
                  onProceed();
                },
              ),
              const SizedBox(height: 8),
              _buildEnhancerOption(
                title: 'Magic Color',
                desc: 'Stretches contrast and sharpens text for a premium, scan-clean print.',
                icon: LucideIcons.wand_sparkles,
                onTap: () async {
                  setState(() => _isProcessingPDF = true);
                  Navigator.pop(context);
                  await _updateFilter(true, 'magic');
                  if (_docType == '2-side-aadhar') {
                    await _updateFilter(false, 'magic');
                  }
                  onProceed();
                },
              ),
              const SizedBox(height: 8),
              _buildEnhancerOption(
                title: 'Remini HD',
                desc: 'AI details-boosting sharpening filter for super-clear, high-definition faces and text.',
                icon: LucideIcons.sparkles,
                onTap: () async {
                  setState(() => _isProcessingPDF = true);
                  Navigator.pop(context);
                  await _updateFilter(true, 'remini');
                  if (_docType == '2-side-aadhar') {
                    await _updateFilter(false, 'remini');
                  }
                  onProceed();
                },
              ),
              const SizedBox(height: 8),
              _buildEnhancerOption(
                title: 'B&W Document',
                desc: 'High contrast black and white conversion for photocopy printing.',
                icon: LucideIcons.binary,
                onTap: () async {
                  setState(() => _isProcessingPDF = true);
                  Navigator.pop(context);
                  await _updateFilter(true, 'binarized');
                  if (_docType == '2-side-aadhar') {
                    await _updateFilter(false, 'binarized');
                  }
                  onProceed();
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEnhancerOption({
    required String title,
    required String desc,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withAlpha(50)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.deepPurple, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevron_right, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  void _clearAll() {
    setState(() {
      _front.originalPath = null;
      _front.processedBytes = null;
      _front.filteredBytes = null;
      _front.filter = 'original';
      _front.extractedText = null;
      _front.qrCodeData = null;
      _front.keyDetails = null;
      _front.isOcrRunning = false;

      _back.originalPath = null;
      _back.processedBytes = null;
      _back.filteredBytes = null;
      _back.filter = 'original';
      _back.extractedText = null;
      _back.qrCodeData = null;
      _back.keyDetails = null;
      _back.isOcrRunning = false;
    });
  }

  Widget _buildUploader(String title, bool isFront) {
    final data = isFront ? _front : _back;
    final cs = Theme.of(context).colorScheme;

    if (data.originalPath != null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withAlpha(50)),
        ),
        child: Column(children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(LucideIcons.refresh_cw, size: 18),
                onPressed: () => _showImageSourceSelector(isFront),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColorFiltered(
              colorFilter: ColorFilter.matrix(_createColorMatrix(
                data.brightness,
                data.contrast,
                data.saturation,
              )),
              child: Image.memory(data.filteredBytes ?? data.processedBytes!, height: 180, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 12),
          
          // Scanner Filters selector row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Filter: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Original', style: TextStyle(fontSize: 11)),
                selected: data.filter == 'original',
                onSelected: (selected) => _updateFilter(isFront, 'original'),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('Magic Color', style: TextStyle(fontSize: 11)),
                selected: data.filter == 'magic',
                onSelected: (selected) => _updateFilter(isFront, 'magic'),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('Remini HD', style: TextStyle(fontSize: 11)),
                selected: data.filter == 'remini',
                onSelected: (selected) => _updateFilter(isFront, 'remini'),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: const Text('B&W Doc', style: TextStyle(fontSize: 11)),
                selected: data.filter == 'binarized',
                onSelected: (selected) => _updateFilter(isFront, 'binarized'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          _buildSlider('Brightness', data.brightness, (v) => setState(() => data.brightness = v)),
          _buildSlider('Contrast', data.contrast, (v) => setState(() => data.contrast = v)),
          _buildSlider('Saturation', data.saturation, (v) => setState(() => data.saturation = v)),
          if (data.isOcrRunning)
            Padding(
              padding: const EdgeInsets.only(top: 12.0, bottom: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepPurple),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Extracting ID text & QR details...',
                    style: TextStyle(fontSize: 12, color: cs.primary.withAlpha(150)),
                  ),
                ],
              ),
            ),
          if (data.keyDetails != null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: cs.surface.withAlpha(200) == Colors.white.withAlpha(200) ? Colors.grey.shade50 : Colors.grey.shade900,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.primary.withAlpha(25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.scan_text, size: 16, color: Colors.deepPurple),
                      const SizedBox(width: 6),
                      const Text(
                        'Extracted Card Details',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepPurple),
                      ),
                      const Spacer(),
                      if (data.keyDetails!.containsKey('Aadhaar No') || data.keyDetails!.containsKey('PAN No'))
                        InkWell(
                          onTap: () {
                            final idNum = data.keyDetails!['Aadhaar No'] ?? data.keyDetails!['PAN No']!;
                            Clipboard.setData(ClipboardData(text: idNum));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Copied ID Number: $idNum')),
                            );
                          },
                          child: Row(
                            children: [
                              const Icon(LucideIcons.copy, size: 12, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text('Copy ID', style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(150))),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 16),
                  ...data.keyDetails!.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 100,
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: cs.onSurface.withAlpha(180),
                              ),
                            ),
                          ),
                          Expanded(
                            child: SelectableText(
                              entry.value,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          if (data.extractedText != null && data.extractedText!.trim().isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: const Text('View Raw Extracted Text', style: TextStyle(fontSize: 12)),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.symmetric(vertical: 8),
                iconColor: cs.primary,
                collapsedIconColor: cs.onSurface.withAlpha(120),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      data.extractedText!,
                      style: TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(200)),
                    ),
                  ),
                ],
              ),
            ),
        ]),
      );
    }

    return GestureDetector(
      onTap: () => _showImageSourceSelector(isFront),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withAlpha(76), style: BorderStyle.solid),
        ),
        child: Column(children: [
          Icon(LucideIcons.camera, size: 36, color: cs.onSurface.withAlpha(100)),
          const SizedBox(height: 12),
          Text('Upload $title', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface.withAlpha(150))),
        ]),
      ),
    );
  }

  Widget _buildSlider(String label, double val, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 85, child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(
          child: Slider(
            value: val, min: 0.0, max: 2.0,
            activeColor: Theme.of(context).colorScheme.primary,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 42, child: Text('${(val * 100).toInt()}%', style: const TextStyle(fontSize: 12))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isReady = _docType == '2-side-aadhar'
        ? (_front.originalPath != null && _back.originalPath != null)
        : _front.originalPath != null;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),

          // Mode selector
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.withAlpha(50)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Document Mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _docType,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  filled: true,
                  fillColor: Theme.of(context).scaffoldBackgroundColor,
                ),
                items: const [
                  DropdownMenuItem(value: '2-side-aadhar', child: Text('2-Side Aadhar (Front + Back)')),
                  DropdownMenuItem(value: '1-side-aadhar', child: Text('1-Side Aadhar (Long Document)')),
                  DropdownMenuItem(value: 'single', child: Text('Single ID — PAN / DL')),
                ],
                onChanged: (v) => setState(() { _docType = v!; _clearAll(); }),
              ),
            ]),
          ),

          const SizedBox(height: 20),

          _buildUploader(_docType == '2-side-aadhar' ? 'Front Side' : 'Document', true),
          if (_docType == '2-side-aadhar') _buildUploader('Back Side', false),

          const SizedBox(height: 16),
          Row(children: [
            if (isReady) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _clearAll,
                  icon: const Icon(LucideIcons.trash_2),
                  label: const Text('Clear'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: isReady && !_isProcessingPDF ? () => _showPdfEnhancerDialog(_generatePDF) : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.withAlpha(76),
                ),
                icon: _isProcessingPDF
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(LucideIcons.file_text),
                label: Text(_isProcessingPDF ? 'Building HD PDF...' : 'Generate PDF'),
              ),
            ),
          ]),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}
