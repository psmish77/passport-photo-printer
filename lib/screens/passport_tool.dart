import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'dart:io' if (dart.library.html) 'package:panditji_printing_app/web_io_stub.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

class _PersonData {
  final String id;
  String? originalPath;
  Uint8List? rawBytes;          // Original cropped & resized photo bytes
  Uint8List? bgRemovedBytes;    // Cutout portrait with transparent background
  Uint8List? filteredBytes;     // Cutout portrait with quick filter applied
  double brightness = 1.0;
  double contrast = 1.0;
  double saturation = 1.0;
  double threshold = 0.12;      // Background removal sensitivity threshold
  String filter = 'original';   // Quick filter preset: 'original', 'magic', 'binarized'
  int quantity;
  bool isProcessing = false;
  Color bgColor = const Color.fromRGBO(77, 180, 213, 1.0);

  _PersonData({required this.id, required this.quantity});
}

class PassportToolScreen extends StatefulWidget {
  const PassportToolScreen({super.key});

  @override
  State<PassportToolScreen> createState() => _PassportToolScreenState();
}

class _PassportToolScreenState extends State<PassportToolScreen> {
  String _presetMode = 'custom';
  final TextEditingController _countCtrl = TextEditingController(text: '1');
  final List<_PersonData> _persons = [];
  bool _isRendering = false;
  final ImagePicker _picker = ImagePicker();

  void _applyPreset() {
    final count = int.tryParse(_countCtrl.text) ?? 1;
    final safe = count < 1 ? 1 : count;
    final newPersons = List.generate(safe, (i) {
      bool isLast = i == safe - 1;
      bool isOdd = safe % 2 != 0;
      int qty = (_presetMode == '2-person' && isLast && isOdd) ? 6 : (_presetMode == '2-person' ? 3 : 6);
      return _PersonData(id: '${DateTime.now().millisecondsSinceEpoch}$i', quantity: qty);
    });
    setState(() {
      _persons.clear();
      _persons.addAll(newPersons);
    });
  }

  void _addPerson() {
    setState(() {
      _persons.add(_PersonData(id: '${DateTime.now().millisecondsSinceEpoch}', quantity: 6));
    });
  }

  void _removePerson(String id) {
    setState(() => _persons.removeWhere((p) => p.id == id));
  }

  static Uint8List _resizeImage(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    if (decoded.width <= 450) return bytes;
    final resized = img.copyResize(decoded, width: 450);
    return Uint8List.fromList(img.encodePng(resized)); // PNG preserves transparency
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

  static Uint8List _removeBackgroundLocal(Map<String, dynamic> args) {
    final bytes = args['bytes'] as Uint8List;
    final double thresholdFactor = args['threshold'] as double? ?? 0.12;

    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    // Convert image to RGBA format (4 channels) to enable transparency
    final rgbaImage = decoded.convert(format: img.Format.uint8, numChannels: 4);

    // Sample background color from the four corners of the image
    final corners = [
      rgbaImage.getPixel(0, 0),
      rgbaImage.getPixel(rgbaImage.width - 1, 0),
      rgbaImage.getPixel(0, rgbaImage.height - 1),
      rgbaImage.getPixel(rgbaImage.width - 1, rgbaImage.height - 1),
    ];

    double bgR = 0;
    double bgG = 0;
    double bgB = 0;
    for (final pixel in corners) {
      bgR += pixel.r;
      bgG += pixel.g;
      bgB += pixel.b;
    }
    bgR /= corners.length;
    bgG /= corners.length;
    bgB /= corners.length;

    // Maximum distance in RGB space is sqrt(255^2 * 3) = ~441.67
    final double maxDist = 441.67;
    final double threshold = thresholdFactor * maxDist;
    final double feather = 0.05 * maxDist; // Smooth feathering region (5% window)

    for (final pixel in rgbaImage) {
      final double r = pixel.r.toDouble();
      final double g = pixel.g.toDouble();
      final double b = pixel.b.toDouble();

      final double dist = math.sqrt((r - bgR) * (r - bgR) + (g - bgG) * (g - bgG) + (b - bgB) * (b - bgB));

      if (dist < threshold) {
        pixel.a = 0; // Cut out background (fully transparent)
      } else if (dist < threshold + feather) {
        final double ratio = (dist - threshold) / feather;
        pixel.a = (ratio * 255).clamp(0, 255).toInt(); // Smooth edge blending
      }
    }

    return Uint8List.fromList(img.encodePng(rgbaImage));
  }

  static Uint8List _filterWork(Map<String, dynamic> args) {
    final bytes = args['bytes'] as Uint8List;
    final String filter = args['filter'] as String? ?? 'original';
    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;

    // Apply quick filters locally preserving alpha transparency
    if (filter == 'magic') {
      decoded = img.adjustColor(
        decoded,
        contrast: 1.25,
        brightness: 1.05,
      );
    } else if (filter == 'binarized') {
      decoded = img.grayscale(decoded);
      for (final pixel in decoded) {
        final luminance = pixel.r.toInt();
        final newValue = luminance > 128 ? 255 : 0;
        pixel.r = newValue;
        pixel.g = newValue;
        pixel.b = newValue;
      }
    } else if (filter == 'remini') {
      // 8-neighbor sharpening kernel – matches DocumentEnhancementService
      final sharpenKernel = [
        -0.5, -1.0, -0.5,
        -1.0,  7.0, -1.0,
        -0.5, -1.0, -0.5
      ];
      decoded = img.convolution(
        decoded,
        filter: sharpenKernel,
        div: 1.0,
      );
      decoded = img.adjustColor(
        decoded,
        contrast: 1.20,
        brightness: 1.05,
        saturation: 1.15,
      );
    }

    // Apply slider adjustments if necessary
    final double b = args['b'] as double? ?? 1.0;
    final double c = args['c'] as double? ?? 1.0;
    final double s = args['s'] as double? ?? 1.0;

    if (b != 1.0 || c != 1.0 || s != 1.0) {
      decoded = img.adjustColor(
        decoded,
        brightness: b - 1.0,
        contrast: c - 1.0,
        saturation: s - 1.0,
      );
    }

    return Uint8List.fromList(img.encodePng(decoded)); // PNG format preserves transparent channels
  }

  /// Returns the stored remove.bg API key from SharedPreferences.
  Future<String> _getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('REMOVE_BG_API_KEY') ?? '';
  }

  Future<Uint8List> _removeBackgroundML(String imagePath, Uint8List imageBytes, double threshold) async {
    // Try remove.bg API first (works on both web and Android)
    final apiKey = await _getApiKey();
    if (apiKey.isNotEmpty) {
      try {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('https://api.remove.bg/v1.0/removebg'),
        );
        request.headers['X-Api-Key'] = apiKey;
        request.fields['size'] = 'auto';
        request.files.add(http.MultipartFile.fromBytes(
          'image_file',
          imageBytes,
          filename: 'photo.jpg',
        ));
        final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
        if (streamedResponse.statusCode == 200) {
          final responseBytes = await streamedResponse.stream.toBytes();
          debugPrint('remove.bg API success: ${responseBytes.length} bytes');
          return responseBytes;
        } else {
          final body = await streamedResponse.stream.bytesToString();
          debugPrint('remove.bg API error ${streamedResponse.statusCode}: $body');
        }
      } catch (e) {
        debugPrint('remove.bg API call failed: $e');
      }
    }

    // Fallback: fast local Dart chroma-key isolate
    debugPrint('Falling back to local chroma-key bg removal');
    if (!kIsWeb) {
      // On Android also try native ML Kit segmentation before chroma-key
      try {
        const platform = MethodChannel('photoeditor.cutout/document_processor');
        final String? resultPath = await platform.invokeMethod('removeBackground', {
          'path': imagePath,
        });
        if (resultPath != null) {
          return await File(resultPath).readAsBytes();
        }
      } catch (e) {
        debugPrint('Android native bg removal failed: $e');
      }
    }
    return compute(_removeBackgroundLocal, {
      'bytes': imageBytes,
      'threshold': threshold,
    });
  }

  Future<void> _pickAndProcess(_PersonData person) async {
    final xfile = await _picker.pickImage(source: ImageSource.gallery);
    if (!mounted) return;
    if (xfile == null) return;

    final cropped = await ImageCropper().cropImage(
      sourcePath: xfile.path,
      aspectRatio: const CropAspectRatio(ratioX: 3.5, ratioY: 4.5),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Passport Photo',
          toolbarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
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
    if (cropped == null) return;

    setState(() {
      person.isProcessing = true;
      person.originalPath = cropped.path;
    });

    try {
      final rawBytes = await cropped.readAsBytes();
      final resizedBytes = await compute(_resizeImage, rawBytes);

      // Perform fast local background removal using Dart chroma-key isolate
      final removed = await _removeBackgroundML(cropped.path, resizedBytes, person.threshold);

      // Apply quick filter preset to the cutout
      final filtered = await compute(_filterWork, {
        'bytes': removed,
        'filter': person.filter,
        'b': 1.0,
        'c': 1.0,
        's': 1.0,
      });

      setState(() {
        person.rawBytes = resizedBytes;
        person.bgRemovedBytes = removed;
        person.filteredBytes = filtered;
        person.isProcessing = false;
      });
    } catch (e) {
      debugPrint("Error processing background removal: $e");
      setState(() {
        person.isProcessing = false;
      });
    }
  }

  Future<void> _updateFilter(_PersonData person, String filterValue) async {
    setState(() {
      person.filter = filterValue;
      person.isProcessing = true;
    });

    if (person.bgRemovedBytes != null) {
      final filtered = await compute(_filterWork, {
        'bytes': person.bgRemovedBytes!,
        'filter': filterValue,
        'b': 1.0,
        'c': 1.0,
        's': 1.0,
      });
      setState(() {
        person.filteredBytes = filtered;
        person.isProcessing = false;
      });
    } else {
      setState(() {
        person.isProcessing = false;
      });
    }
  }

  Future<void> _updateThreshold(_PersonData person, double val) async {
    setState(() {
      person.threshold = val;
      person.isProcessing = true;
    });

    if (person.rawBytes != null) {
      try {
        final removed = await compute(_removeBackgroundLocal, {
          'bytes': person.rawBytes!,
          'threshold': val,
          'feather': 0.05,
        });
        final filtered = await compute(_filterWork, {
          'bytes': removed,
          'filter': person.filter,
          'b': 1.0,
          'c': 1.0,
          's': 1.0,
        });
        setState(() {
          person.bgRemovedBytes = removed;
          person.filteredBytes = filtered;
          person.isProcessing = false;
        });
      } catch (_) {
        setState(() {
          person.isProcessing = false;
        });
      }
    } else {
      setState(() {
        person.isProcessing = false;
      });
    }
  }

  List<List<T>> _chunkList<T>(List<T> list, int chunkSize) {
    final List<List<T>> chunks = [];
    for (var i = 0; i < list.length; i += chunkSize) {
      chunks.add(list.sublist(i, i + chunkSize > list.length ? list.length : i + chunkSize));
    }
    return chunks;
  }

  Future<void> _generateSheet() async {
    setState(() => _isRendering = true);
    final pdf = pw.Document();
    final List<pw.Widget> cells = [];

    // Exact dimensions to fit 48 photos (6 cols x 8 rows) on A4 with thin spaces
    const double cellW = 32.88;
    const double cellH = 35.00;

    for (final person in _persons) {
      if (person.bgRemovedBytes == null) continue;

      final processed = await compute(_filterWork, {
        'bytes': person.bgRemovedBytes!,
        'filter': person.filter,
        'b': person.brightness,
        'c': person.contrast,
        's': person.saturation,
      });

      final pdfImg = pw.MemoryImage(processed);
      for (int i = 0; i < person.quantity; i++) {
        cells.add(pw.Container(
          width: cellW * PdfPageFormat.mm,
          height: cellH * PdfPageFormat.mm,
          color: PdfColors.black,
          padding: const pw.EdgeInsets.all(0.16 * PdfPageFormat.mm),
          child: pw.Container(
            color: PdfColor.fromInt(person.bgColor.toARGB32()),
            child: pw.Image(pdfImg, fit: pw.BoxFit.fill),
          ),
        ));
      }
    }

    final cellChunks = _chunkList(cells, 6); // Rows of 6 columns
    final pageChunks = _chunkList(cellChunks, 8); // Pages of 8 rows (48 photos)

    for (final pageRows in pageChunks) {
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 5.0 * PdfPageFormat.mm, vertical: 6.3 * PdfPageFormat.mm),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: pageRows.map((rowCells) {
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 0.55 * PdfPageFormat.mm),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.start,
                children: [
                  for (int j = 0; j < rowCells.length; j++) ...[
                    rowCells[j],
                    if (j < rowCells.length - 1)
                      pw.SizedBox(width: 0.55 * PdfPageFormat.mm),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ));
    }

    setState(() => _isRendering = false);
    await Printing.layoutPdf(
      onLayout: (fmt) async => pdf.save(),
      name: 'passport_sheet.pdf',
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
                'Choose a quick enhancement filter to optimize the print quality of the generated sheet:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              _buildEnhancerOption(
                title: 'Original',
                desc: 'Keep original processed photo colors.',
                icon: LucideIcons.image,
                onTap: () async {
                  setState(() => _isRendering = true);
                  Navigator.pop(context);
                  for (final p in _persons) {
                    await _updateFilter(p, 'original');
                  }
                  onProceed();
                },
              ),
              const SizedBox(height: 8),
              _buildEnhancerOption(
                title: 'Magic Color',
                desc: 'Stretches contrast and boosts brightness for a premium, clean print.',
                icon: LucideIcons.wand_sparkles,
                onTap: () async {
                  setState(() => _isRendering = true);
                  Navigator.pop(context);
                  for (final p in _persons) {
                    await _updateFilter(p, 'magic');
                  }
                  onProceed();
                },
              ),
              const SizedBox(height: 8),
              _buildEnhancerOption(
                title: 'Remini HD',
                desc: 'AI details-boosting sharpening filter for super-clear, high-definition faces.',
                icon: LucideIcons.sparkles,
                onTap: () async {
                  setState(() => _isRendering = true);
                  Navigator.pop(context);
                  for (final p in _persons) {
                    await _updateFilter(p, 'remini');
                  }
                  onProceed();
                },
              ),
              const SizedBox(height: 8),
              _buildEnhancerOption(
                title: 'B&W Document',
                desc: 'Crisp grayscale/monochrome conversion for office paper copies.',
                icon: LucideIcons.binary,
                onTap: () async {
                  setState(() => _isRendering = true);
                  Navigator.pop(context);
                  for (final p in _persons) {
                    await _updateFilter(p, 'binarized');
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

  int get _totalPhotos => _persons.fold(0, (s, p) => s + p.quantity);
  bool get _rowReady => _totalPhotos > 0 && _totalPhotos % 6 == 0;
  bool get _allUploaded => _persons.isNotEmpty && _persons.every((p) => p.bgRemovedBytes != null);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),

          // ── Setup Card ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.withAlpha(50)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Printing Mode Setup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _presetMode,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  filled: true,
                  fillColor: Theme.of(context).scaffoldBackgroundColor,
                ),
                items: const [
                  DropdownMenuItem(value: 'custom', child: Text('Custom (Manual Allocation)')),
                  DropdownMenuItem(value: '1-person', child: Text('1 Person Mode — 6 photos each')),
                  DropdownMenuItem(value: '2-person', child: Text('Dual Partition — 3 photos each')),
                ],
                onChanged: (v) => setState(() { _presetMode = v!; if (v == 'custom') _persons.clear(); }),
              ),
              if (_presetMode != 'custom') ...[
                const SizedBox(height: 12),
                Row(children: [
                  const Text('No. of Persons:', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 70,
                    child: TextField(
                      controller: _countCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _applyPreset,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.onSurface,
                      foregroundColor: cs.surface,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Apply'),
                  ),
                ]),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Icon(
                  _rowReady ? LucideIcons.circle_check : LucideIcons.info,
                  size: 16,
                  color: _rowReady ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(
                  '$_totalPhotos photos${_rowReady ? ' — Perfect layout ✓' : ' — need ${6 - (_totalPhotos % 6)} more for full row'}',
                  style: TextStyle(
                    color: _rowReady ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.w500, fontSize: 13,
                  ),
                ),
              ]),
            ]),
          ),

          const SizedBox(height: 20),

          // ── Empty State ─────────────────────────────────────────
          if (_persons.isEmpty)
            GestureDetector(
              onTap: _presetMode == 'custom' ? _addPerson : null,
              child: Container(
                padding: const EdgeInsets.all(48),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.withAlpha(76), style: BorderStyle.solid),
                ),
                child: Column(children: [
                  Icon(LucideIcons.image, size: 48, color: cs.onSurface.withAlpha(100)),
                  const SizedBox(height: 16),
                  Text(
                    _presetMode == 'custom' ? 'Tap to add a person' : 'Set count above and tap Apply',
                    style: TextStyle(color: cs.onSurface.withAlpha(150), fontWeight: FontWeight.w500),
                  ),
                ]),
              ),
            ),

          // ── Person Cards ────────────────────────────────────────
          for (int i = 0; i < _persons.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.withAlpha(50)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Person ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Row(children: [
                      if (_presetMode == 'custom') ...[
                        IconButton(icon: const Icon(LucideIcons.circle_minus, size: 22), onPressed: () => setState(() { if (_persons[i].quantity > 1) _persons[i].quantity--; })),
                        Text('${_persons[i].quantity}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        IconButton(icon: const Icon(LucideIcons.circle_plus, size: 22), onPressed: () => setState(() => _persons[i].quantity++)),
                      ],
                      IconButton(
                        icon: const Icon(LucideIcons.trash_2, color: Colors.red, size: 22),
                        onPressed: () => _removePerson(_persons[i].id),
                      ),
                    ]),
                  ],
                ),
                const SizedBox(height: 12),
                if (_persons[i].isProcessing)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 8),
                      Text('Removing background…', style: TextStyle(color: Colors.grey)),
                    ]),
                  ))
                else if (_persons[i].bgRemovedBytes != null)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 90,
                        height: 116,
                        color: _persons[i].bgColor,
                        child: ColorFiltered(
                          colorFilter: ColorFilter.matrix(_createColorMatrix(
                            _persons[i].brightness,
                            _persons[i].contrast,
                            _persons[i].saturation,
                          )),
                          child: Image.memory(_persons[i].filteredBytes!, fit: BoxFit.cover),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Quick filter chips
                        Row(
                          children: [
                            const Text('Filter: ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 4),
                            _buildFilterChip(_persons[i], 'original', 'Orig'),
                            const SizedBox(width: 4),
                            _buildFilterChip(_persons[i], 'magic', 'Magic'),
                            const SizedBox(width: 4),
                            _buildFilterChip(_persons[i], 'remini', 'Remini'),
                            const SizedBox(width: 4),
                            _buildFilterChip(_persons[i], 'binarized', 'B&W'),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _buildSlider('Bright', _persons[i].brightness, (v) => setState(() => _persons[i].brightness = v)),
                        _buildSlider('Contr', _persons[i].contrast, (v) => setState(() => _persons[i].contrast = v)),
                        _buildSlider('Satur', _persons[i].saturation, (v) => setState(() => _persons[i].saturation = v)),
                        _buildSlider('Cutout', _persons[i].threshold, (v) => _updateThreshold(_persons[i], v), min: 0.02, max: 0.40),
                        const SizedBox(height: 4),
                        _buildColorSelector(_persons[i]),
                      ],
                    )),
                  ])
                else
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: () => _pickAndProcess(_persons[i]),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.onSurface,
                        foregroundColor: cs.surface,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      ),
                      icon: const Icon(LucideIcons.camera),
                      label: const Text('Upload Portrait'),
                    ),
                  ),
              ]),
            ),

          // ── Action Buttons ──────────────────────────────────────
          Row(children: [
            if (_presetMode == 'custom') ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addPerson,
                  icon: const Icon(LucideIcons.plus),
                  label: const Text('Add Person'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: (_rowReady && _allUploaded && !_isRendering) ? () => _showPdfEnhancerDialog(_generateSheet) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.withAlpha(76),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: _isRendering
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(LucideIcons.printer),
                label: Text(_isRendering ? 'Rendering...' : 'Print Sheet'),
              ),
            ),
          ]),

          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildFilterChip(_PersonData person, String filterValue, String label) {
    final isSelected = person.filter == filterValue;
    return GestureDetector(
      onTap: () => _updateFilter(person, filterValue),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.withAlpha(40),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: isSelected ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildSlider(String label, double val, ValueChanged<double> onChanged, {double min = 0.0, double max = 2.0}) {
    return Row(children: [
      SizedBox(width: 42, child: Text(label, style: const TextStyle(fontSize: 11))),
      Expanded(child: Slider(value: val, min: min, max: max, onChanged: onChanged)),
    ]);
  }

  Widget _buildColorSelector(_PersonData person) {
    final colors = [
      const Color.fromRGBO(77, 180, 213, 1.0), // Sky Blue (Default)
      Colors.white,
      const Color(0xFF3B5998), // Visa Blue
      const Color(0xFF0000FF), // Pure Blue
      const Color(0xFFFF0000), // Red
    ];

    return Row(
      children: [
        const Text('Bg Color: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(width: 4),
        ...colors.map((color) {
          final isSelected = person.bgColor == color;
          return GestureDetector(
            onTap: () => setState(() => person.bgColor = color),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.deepPurple : Colors.grey.shade400,
                  width: isSelected ? 2.0 : 1.0,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
