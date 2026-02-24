import 'package:flutter/material.dart';

import '../../domain/book.dart';

/// Stub for epub_plus-based reader when dart:io is not available (e.g. web).
Widget buildEpubPlusViewer({
  required String localPath,
  required Book book,
}) {
  return Scaffold(
    appBar: AppBar(title: Text(book.title)),
    body: const Center(
      child: Text(
        'EPUB is not supported on this platform.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}
