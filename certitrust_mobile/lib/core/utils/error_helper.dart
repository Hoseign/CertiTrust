import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void showErrorDialog(BuildContext context, String title, String errorDetails) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: const TextStyle(color: Colors.red)),
      content: SingleChildScrollView(
        child: Text(errorDetails),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: errorDetails));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error copied to clipboard!')),
            );
          },
          child: const Text('Copy Logs'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}