// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

web.Window get window => web.window;
web.Document get document => web.document;

// Re-export native web types using external extension types or standard types
typedef Blob = web.Blob;
typedef BlobPropertyBag = web.BlobPropertyBag;
typedef HTMLAnchorElement = web.HTMLAnchorElement;

/// Helper function to create a native web Blob from byte data
web.Blob createBlob(Uint8List data, [web.BlobPropertyBag? options]) {
  // Convert Uint8List to JSArray<JSArrayBuffer> or JSUint8Array as required by web 1.1.x
  final jsArray = [data.toJS].toJS;
  return options != null 
      ? web.Blob(jsArray, options) 
      : web.Blob(jsArray);
}

class URL {
  static String createObjectURL(web.Blob blob) => web.URL.createObjectURL(blob);
  static void revokeObjectURL(String url) => web.URL.revokeObjectURL(url);
}