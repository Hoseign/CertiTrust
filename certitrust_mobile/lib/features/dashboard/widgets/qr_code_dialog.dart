import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';

// Use the cross-platform conditional web helper instead of importing web packages directly
import 'web_helper.dart';

void showQRCodeDialog(BuildContext context, Map<String, dynamic> cert) {
  final hash = cert['cert_hash'] ?? cert['ipfs_hash'] ?? cert['hash'] ?? '';
  final studentName = cert['student_name'] ?? 'Certificate';

  if (hash.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Error: Certificate hash is missing, cannot generate QR code.')),
    );
    return;
  }

  final GlobalKey qrKey = GlobalKey();

  showDialog(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text('QR Code: $studentName'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Scan this QR code to access credential verification.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: RepaintBoundary(
                  key: qrKey,
                  child: SizedBox(
                    width: 180,
                    height: 180,
                    child: QrImageView(
                      data: hash,
                      version: QrVersions.auto,
                      size: 180.0,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Hash: ${hash.length > 20 ? '${hash.substring(0, 20)}...' : hash}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              try {
                RenderRepaintBoundary? boundary = qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
                if (boundary == null) {
                  throw Exception('QR layout not ready');
                }

                ui.Image image = await boundary.toImage(pixelRatio: 3.0);
                ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
                Uint8List pngBytes = byteData!.buffer.asUint8List();
                final fileName = 'QR_${studentName.replaceAll(' ', '_')}.png';

                if (kIsWeb) {
                  // Safely delegates to the conditional web helper
                  downloadFileWeb(pngBytes, fileName);
                } else {
                  await ImageGallerySaverPlus.saveImage(
                    pngBytes,
                    quality: 100,
                    name: "QR_${studentName.replaceAll(' ', '_')}",
                  );

                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('QR Code saved to your phone Gallery!')),
                    );
                  }
                }

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              } catch (e) {
                debugPrint('Error processing QR code: $e');
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('Failed to process QR code: $e')),
                  );
                }
              }
            },
            icon: const Icon(Icons.download),
            label: Text(kIsWeb ? 'Download QR' : 'Save to Gallery'),
          ),
        ],
      );
    },
  );
}