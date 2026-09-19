import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasReturned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _returnResult(String value) {
    if (_hasReturned || value.trim().isEmpty) return;
    _hasReturned = true;
    _controller.stop();
    Navigator.of(context).pop(value.trim());
  }

  Future<void> _scanFromGallery() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    final capture = await _controller.analyzeImage(path);
    final value = capture != null && capture.barcodes.isNotEmpty
      ? capture.barcodes.first.rawValue
      : null;
    if (value != null) _returnResult(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Certificate QR'),
        actions: [
          IconButton(
            tooltip: 'Use gallery image',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: _scanFromGallery,
          ),
          IconButton(
            tooltip: 'Switch camera',
            icon: const Icon(Icons.flip_camera_android),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
                final value = capture.barcodes.isNotEmpty
                  ? capture.barcodes.first.rawValue
                  : null;
              if (value != null) _returnResult(value);
            },
          ),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: SafeArea(
              child: Card(
                color: Colors.black87,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'Point the camera at a CertiTrust QR code, or choose an image from your gallery.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withAlpha(230)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
