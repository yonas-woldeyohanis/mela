import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/config.dart';

/// Combined result of OCR text extraction and QR code / barcode scanning.
class ScanExtractionResult {
  const ScanExtractionResult({
    required this.text,
    this.qrUrl,
    this.qrRawData,
  });

  final String text;
  final String? qrUrl;
  final String? qrRawData;
}

/// On-device OCR + QR code scanning + image compression (target < 100 KB).
class ReceiptPipeline {
  static final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  static final _barcodeScanner = BarcodeScanner(formats: [
    BarcodeFormat.qrCode,
    BarcodeFormat.aztec,
    BarcodeFormat.dataMatrix,
    BarcodeFormat.pdf417,
    BarcodeFormat.code128,
  ]);

  /// Scans an image simultaneously for OCR text and embedded QR / Barcode data.
  static Future<ScanExtractionResult> scanImage(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);

    // Run Text OCR and QR Barcode detection in parallel for speed
    final results = await Future.wait([
      _recognizer.processImage(inputImage),
      _barcodeScanner.processImage(inputImage),
    ]);

    final textResult = results[0] as RecognizedText;
    final barcodes = results[1] as List<Barcode>;

    String? qrUrl;
    String? qrRawData;

    for (final b in barcodes) {
      final val = (b.displayValue ?? b.rawValue)?.trim();
      if (val != null && val.isNotEmpty) {
        if (val.startsWith('http://') || val.startsWith('https://')) {
          qrUrl = val;
          break;
        } else {
          qrRawData ??= val;
        }
      }
    }

    // Fallback: check if an official bank receipt verification URL is printed in the text
    qrUrl ??= RegExp(r'https?://[^\s/$.?#].[^\s]*', caseSensitive: false).firstMatch(textResult.text)?.group(0)?.trim();

    return ScanExtractionResult(
      text: textResult.text,
      qrUrl: qrUrl,
      qrRawData: qrRawData,
    );
  }

  /// Legacy helper for OCR-only callers
  static Future<String> ocr(String imagePath) async {
    final res = await scanImage(imagePath);
    return res.text;
  }

  static Future<String> compress(String srcPath, String id) async {
    final dir = await getApplicationDocumentsDirectory();
    final out = Directory(p.join(dir.path, 'receipts'));
    await out.create(recursive: true);
    final target = p.join(out.path, '$id.jpg');

    for (final q in const [70, 55, 42, 30]) {
      try {
        final x = await FlutterImageCompress.compressAndGetFile(
          srcPath, target,
          quality: q, minWidth: 900, minHeight: 900, format: CompressFormat.jpeg,
        );
        if (x == null) break;
        if (await File(x.path).length() <= AppConfig.maxImageBytes) break;
      } catch (_) {
        break;
      }
    }
    if (!await File(target).exists()) await File(srcPath).copy(target);
    try {
      await File(srcPath).delete();
    } catch (_) {}
    return target;
  }

  static Future<void> discard(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }
}
