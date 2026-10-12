import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/config.dart';

/// On-device OCR + image compression (target < 100 KB).
class ReceiptPipeline {
  static final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  static Future<String> ocr(String imagePath) async {
    final result = await _recognizer.processImage(InputImage.fromFilePath(imagePath));
    return result.text;
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
