import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:epub_plus/epub_plus.dart';
import 'package:pdfx/pdfx.dart';

/// Result of cover generation: image bytes and file extension (e.g. "jpg", "png").
class CoverResult {
  const CoverResult({required this.bytes, required this.ext});

  final Uint8List bytes;
  final String ext;
}

/// Generates cover image bytes from the first page (PDF) or cover/first image (EPUB).
/// Returns null if format is unsupported or generation fails.
Future<CoverResult?> generateCoverBytes(
  List<int> fileBytes,
  String format,
) async {
  if (format == 'pdf') {
    return _generatePdfCover(fileBytes);
  }
  if (format == 'epub') {
    return _generateEpubCover(fileBytes);
  }
  return null;
}

Future<CoverResult?> _generatePdfCover(List<int> fileBytes) async {
  PdfDocument? document;
  try {
    final bytes = fileBytes is Uint8List ? fileBytes : Uint8List.fromList(fileBytes);
    document = await PdfDocument.openData(bytes);
    if (document.pagesCount < 1) return null;
    final page = await document.getPage(1);
    try {
      final image = await page.render(
        width: 400,
        height: 600,
        format: PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
      );
      if (image == null || image.bytes.isEmpty) return null;
      return CoverResult(bytes: image.bytes, ext: 'jpg');
    } finally {
      await page.close();
    }
  } catch (e, stackTrace) {
    developer.log('PDF cover generation failed', name: 'CoverService', error: e, stackTrace: stackTrace);
    return null;
  } finally {
    await document?.close();
  }
}

Future<CoverResult?> _generateEpubCover(List<int> fileBytes) async {
  try {
    final epubBook = await EpubReader.readBook(fileBytes);
    Uint8List? imageBytes;
    String ext = 'jpg';

    final images = epubBook.content?.images;
    if (images != null && images.isNotEmpty) {
      for (final file in images.values) {
        if (file.content != null && file.content!.isNotEmpty) {
          imageBytes = Uint8List.fromList(file.content!);
          final mime = file.contentMimeType?.toLowerCase() ?? '';
          ext = mime.contains('png')
              ? 'png'
              : (mime.contains('jpeg') || mime.contains('jpg')
                  ? 'jpg'
                  : _imageExtensionFromBytes(imageBytes));
          break;
        }
      }
    }

    if (imageBytes == null || imageBytes.isEmpty) return null;
    return CoverResult(bytes: imageBytes, ext: ext);
  } catch (e, stackTrace) {
    developer.log('EPUB cover generation failed', name: 'CoverService', error: e, stackTrace: stackTrace);
    return null;
  }
}

String _imageExtensionFromBytes(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) return 'jpg';
  if (bytes.length >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return 'png';
  return 'jpg';
}
