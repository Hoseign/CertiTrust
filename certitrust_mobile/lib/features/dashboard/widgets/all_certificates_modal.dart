import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'qr_code_dialog.dart';
import 'universal_html/html.dart' as html;

class AllCertificatesModal extends StatelessWidget {
  final Future<List<Map<String, dynamic>>> Function() fetchCertificates;

  const AllCertificatesModal({super.key, required this.fetchCertificates});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'All Issued Credentials',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: fetchCertificates(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }
                    final certs = snapshot.data ?? [];
                    if (certs.isEmpty) {
                      return const Center(child: Text('No records found.'));
                    }
                    return ListView.separated(
                      controller: scrollController,
                      itemCount: certs.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final cert = certs[index];
                        final imageUrl = cert['cert_image_url'];
                        return ListTile(
                          leading: const Icon(Icons.school, color: Colors.blue),
                          title: Text(cert['student_name'] ?? 'Unknown'),
                          subtitle: Text('${cert['degree']} • ID: ${cert['student_id']}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (imageUrl != null && imageUrl.toString().isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.download, color: Colors.blue),
                                  tooltip: 'Download Diploma',
                                  onPressed: () async {
                                    if (kIsWeb) {
                                      final anchor = html.HTMLAnchorElement()
                                        ..href = imageUrl
                                        ..download = 'Diploma_${cert['student_name']?.replaceAll(' ', '_')}.jpg'
                                        ..target = '_blank';
                                      html.document.body?.appendChild(anchor);
                                      anchor.click();
                                      anchor.remove();
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Opening diploma image link...')),
                                      );
                                    }
                                  },
                                ),
                              IconButton(
                                icon: const Icon(Icons.qr_code, color: Colors.teal),
                                tooltip: 'Get QR Code',
                                onPressed: () => showQRCodeDialog(context, cert),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}