import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';

import 'universal_html/html.dart' as html;

Future<void> downloadDiplomaImage(
  String imageUrl, {
  required String fileName,
}) async {
  final response = await http.get(Uri.parse(imageUrl));
  if (response.statusCode != 200) {
    throw Exception('Diploma download failed [${response.statusCode}].');
  }

  final contentType = response.headers['content-type']?.split(';').first ??
      'application/octet-stream';
  final extension = switch (contentType) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    _ => null,
  };
  final outputName = extension == null
      ? fileName
      : '${fileName.replaceFirst(RegExp(r'\.[^.]+$'), '')}.$extension';
  if (kIsWeb) {
    final blob = html.createBlob(
      response.bodyBytes,
      html.BlobPropertyBag(type: contentType),
    );
    final url = html.URL.createObjectURL(blob);
    final anchor = html.document.createElement('a') as html.HTMLAnchorElement
      ..href = url
      ..download = outputName;
    html.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    html.URL.revokeObjectURL(url);
    return;
  }

  final result = await ImageGallerySaverPlus.saveImage(
    response.bodyBytes,
    quality: 100,
    name: outputName,
  );
  if (result == null ||
      (result['isSuccess'] != true && result['filePath'] == null)) {
    throw Exception('Could not save the diploma image to your gallery.');
  }
}
