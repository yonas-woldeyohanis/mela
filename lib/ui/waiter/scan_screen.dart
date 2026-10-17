import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/friendly_error.dart';
import '../../services/ocr_parser.dart';
import '../../services/receipt_pipeline.dart';
import '../../state/providers.dart';
import 'review_sheet.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});
  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> with WidgetsBindingObserver {
  CameraController? _cam;
  final ImagePicker _picker = ImagePicker();
  bool _busy = false, _torch = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cam?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _cam;
    if (state == AppLifecycleState.inactive && c != null) {
      c.dispose();
      setState(() => _cam = null);
    } else if (state == AppLifecycleState.resumed && _cam == null) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final c = CameraController(back, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await c.initialize();
      await c.setFlashMode(FlashMode.off);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _cam = c;
        _error = null;
        _torch = false;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Camera unavailable. Allow camera access in Settings.\n$e');
    }
  }

  Future<void> _toggleTorch() async {
    final c = _cam;
    if (c == null) return;
    _torch = !_torch;
    await c.setFlashMode(_torch ? FlashMode.torch : FlashMode.off);
    setState(() {});
  }

  Future<void> _capture() async {
    final c = _cam;
    if (c == null || _busy || c.value.isTakingPicture) return;
    final haptics = ref.read(settingsProvider).haptics;
    setState(() => _busy = true);
    if (haptics) HapticFeedback.mediumImpact();
    String? path;
    try {
      final shot = await c.takePicture();
      path = shot.path;
      final scanResult = await ReceiptPipeline.scanImage(path);
      final parsed = OcrParser.parse(scanResult.text, qrUrl: scanResult.qrUrl);
      if (!mounted) return;
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => ReviewSheet(imagePath: path!, parsed: parsed),
      );
      if (saved != true) await ReceiptPipeline.discard(path);
    } catch (e) {
      if (path != null) await ReceiptPipeline.discard(path);
      if (mounted) {
        FriendlyError.show(context, e, title: 'Capture Issue');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickImageFromGallery() async {
    if (_busy) return;
    final haptics = ref.read(settingsProvider).haptics;
    if (haptics) HapticFeedback.selectionClick();

    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );
      if (file == null || !mounted) return;

      setState(() => _busy = true);
      final scanResult = await ReceiptPipeline.scanImage(file.path);
      final parsed = OcrParser.parse(scanResult.text, qrUrl: scanResult.qrUrl);
      if (!mounted) return;

      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => ReviewSheet(imagePath: file.path, parsed: parsed),
      );
      if (saved != true) await ReceiptPipeline.discard(file.path);
    } catch (e) {
      if (mounted) {
        FriendlyError.show(context, e, title: 'Upload Issue');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _cam;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        if (c != null && c.value.isInitialized)
          ClipRect(
            child: OverflowBox(
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: c.value.previewSize!.height,
                  height: c.value.previewSize!.width,
                  child: CameraPreview(c),
                ),
              ),
            ),
          )
        else
          Center(
            child: _error != null
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                  )
                : const CircularProgressIndicator(),
          ),
        CustomPaint(painter: _FramePainter()),
        // Bottom controls
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(99)),
                  child: Text(_busy ? 'Reading receipt…' : 'Fit the transfer confirmation inside the frame',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  IconButton.filledTonal(
                    iconSize: 28,
                    onPressed: _toggleTorch,
                    icon: Icon(_torch ? Icons.flash_on_rounded : Icons.flash_off_rounded),
                    tooltip: 'Flashlight',
                  ),
                  GestureDetector(
                    onTap: _capture,
                    child: AnimatedScale(
                      scale: _busy ? 0.88 : 1,
                      duration: const Duration(milliseconds: 150),
                      child: Container(
                        width: 82,
                        height: 82,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                        child: Container(
                          decoration: BoxDecoration(shape: BoxShape.circle, color: _busy ? Colors.white54 : Colors.white),
                          child: _busy ? const Padding(padding: EdgeInsets.all(22), child: CircularProgressIndicator(strokeWidth: 3)) : null,
                        ),
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    iconSize: 28,
                    onPressed: _pickImageFromGallery,
                    icon: const Icon(Icons.photo_library_rounded),
                    tooltip: 'Upload from files or gallery',
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.45), width: size.width * 0.86, height: size.height * 0.5);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(26));
    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rr)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.5));

    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    const l = 32.0;
    const rad = 26.0;
    final r = rect;

    // Draw clean smooth rounded corners
    final path = Path()
      // Top Left
      ..moveTo(r.left, r.top + l)
      ..lineTo(r.left, r.top + rad)
      ..arcToPoint(Offset(r.left + rad, r.top), radius: const Radius.circular(rad))
      ..lineTo(r.left + l, r.top)
      // Top Right
      ..moveTo(r.right - l, r.top)
      ..lineTo(r.right - rad, r.top)
      ..arcToPoint(Offset(r.right, r.top + rad), radius: const Radius.circular(rad))
      ..lineTo(r.right, r.top + l)
      // Bottom Left
      ..moveTo(r.left, r.bottom - l)
      ..lineTo(r.left, r.bottom - rad)
      ..arcToPoint(Offset(r.left + rad, r.bottom), radius: const Radius.circular(rad))
      ..lineTo(r.left + l, r.bottom)
      // Bottom Right
      ..moveTo(r.right - l, r.bottom)
      ..lineTo(r.right - rad, r.bottom)
      ..arcToPoint(Offset(r.right, r.bottom - rad), radius: const Radius.circular(rad))
      ..lineTo(r.right, r.bottom - l);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
