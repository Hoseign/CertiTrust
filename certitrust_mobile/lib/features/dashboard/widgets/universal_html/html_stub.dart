// ignore_for_file: camel_case_types, non_constant_identifier_names
import 'dart:typed_data';

class Window {}

class ElementMock {
  void appendChild(Object child) {}
  void removeChild(Object child) {}
}

class Document {
  ElementMock? body = ElementMock();
  dynamic createElement(String tag) => HTMLAnchorElement();
}

final Window window = Window();
final Document document = Document();

class HTMLAnchorElement {
  String? href;
  String? download;
  String? target; // Added target field to fix all_certificates_modal.dart error
  
  HTMLAnchorElement({this.href, this.target});

  void click() {}

  void setAttribute(String name, String value) {
    if (name == 'download') {
      download = value;
    } else if (name == 'href') {
      href = value;
    } else if (name == 'target') {
      target = value;
    }
  }

  void remove() {}
}

class BlobPropertyBag {
  final String? type;
  BlobPropertyBag({this.type});
}

class Blob {
  final List<Object> data;
  final BlobPropertyBag? options;
  Blob(this.data, [this.options]);
}

Object createBlob(Uint8List data, [BlobPropertyBag? options]) {
  return Blob([data], options);
}

class URL {
  static String createObjectURL(Object blob) => '';
  static void revokeObjectURL(String url) {}
}