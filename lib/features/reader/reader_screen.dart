import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';

import '../../data/firebase/notes_repository.dart';
import '../../data/firebase/progress_repository.dart';
import '../../domain/book.dart';
import '../../domain/note.dart';
import '../notes/book_notes_screen.dart';
import 'epub_plus_reader_stub.dart' if (dart.library.io) 'epub_plus_reader_io.dart' as epub_plus_reader;

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    super.key,
    required this.book,
    required this.localPath,
  });

  final Book book;
  final String localPath;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  PdfController? _controller;
  int _initialPage = 1;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    if (widget.book.format != 'pdf') {
      setState(() => _loading = false);
      return;
    }
    try {
      final progress = await getProgress(widget.book.id);
      final pageIndex = progress?.pageIndex ?? 0;
      _initialPage = pageIndex + 1; // pdfx is 1-based

      final document = await PdfDocument.openFile(widget.localPath);
      if (!mounted) return;
      _controller = PdfController(
        document: Future.value(document),
        initialPage: _initialPage,
      );
      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.book.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.book.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (widget.book.format == 'epub') {
      if (kIsWeb) {
        return Scaffold(
          appBar: AppBar(title: Text(widget.book.title)),
          body: const Center(
            child: Text(
              'EPUB is not supported on this platform. Open the file with an external app.',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      return epub_plus_reader.buildEpubPlusViewer(
        localPath: widget.localPath,
        book: widget.book,
      );
    }

    if (widget.book.format != 'pdf') {
      return Scaffold(
        appBar: AppBar(title: Text(widget.book.title)),
        body: const Center(
          child: Text(
            'Only PDF and EPUB are supported in this reader. For other formats, open the file with an external app.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final controller = _controller!;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.notes_outlined),
            tooltip: 'Notes',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BookNotesScreen(book: widget.book),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.note_add_outlined),
            tooltip: 'Add note',
            onPressed: () => _showAddNoteDialog(context, controller),
          ),
        ],
      ),
      body: PdfView(
        controller: controller,
        onPageChanged: (page) {
          saveProgress(widget.book.id, page - 1);
        },
        onDocumentError: (error) {
          setState(() => _error = error.toString());
        },
      ),
    );
  }

  Future<void> _showAddNoteDialog(BuildContext context, PdfController controller) async {
    final page = controller.page;
    final controllerText = TextEditingController();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final text = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add note'),
          content: TextField(
            controller: controllerText,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: 'Note text',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controllerText.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (text == null || text.isEmpty) return;
    final note = Note(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      position: page.toString(),
      createdAt: DateTime.now(),
    );
    await addNote(widget.book.id, note);
    messenger?.showSnackBar(
      const SnackBar(content: Text('Note saved')),
    );
  }

}
