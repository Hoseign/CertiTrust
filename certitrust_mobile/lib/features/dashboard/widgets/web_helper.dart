import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'universal_html/html.dart' as html;

Future<void> downloadFileWeb(Uint8List bytes, String fileName) async {
  if (kIsWeb) {
    final blob = html.createBlob(bytes, html.BlobPropertyBag(type: 'image/png'));
    final url = html.URL.createObjectURL(blob);
    final anchor = html.document.createElement('a') as html.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = fileName;
    html.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    html.URL.revokeObjectURL(url);
  } else {
    try {
      debugPrint('File download helper invoked on mobile/desktop.');
    } catch (e) {
      debugPrint('Error saving file: $e');
    }
  }
}