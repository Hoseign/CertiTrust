import 'package:flutter/material.dart';
import 'diploma_download.dart';

void showDiplomaPreview(
  BuildContext context,
  String imageUrl, {
  String fileName = 'Diploma.jpg',
}) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: SizedBox(
        width: MediaQuery.sizeOf(context).width * 0.85,
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: 20),
                    child: Text('Digital Diploma Copy'),
                  ),
                ),
                IconButton(
                  tooltip: 'Download diploma',
                  onPressed: () async {
                    try {
                      await downloadDiplomaImage(imageUrl, fileName: fileName);
                    } catch (error) {
                      if (!dialogContext.mounted) return;
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                            content: Text('Could not download diploma: $error')),
                      );
                    }
                  },
                  icon: const Icon(Icons.download),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Expanded(
              child: InteractiveViewer(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const Center(child: Text('Could not load diploma image.')),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}