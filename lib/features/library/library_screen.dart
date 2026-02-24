import 'dart:developer' as developer;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/firebase/books_repository.dart';
import '../../data/firebase/progress_repository.dart';
import '../../data/firebase/storage_repository.dart';
import '../../domain/book.dart';
import '../../domain/reading_progress.dart';
import '../notes/all_notes_screen.dart';
import '../reader/reader_screen.dart';

final booksStreamProvider =
    StreamProvider.autoDispose<List<Book>>((ref) => watchBooks());

final progressForBookProvider =
    StreamProvider.autoDispose.family<ReadingProgress?, String>(
        (ref, bookId) => watchProgress(bookId));

/// Download URL for a cover stored at [path]. Returns null if path is empty or fetch fails.
final coverUrlProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, path) async {
  if (path.isEmpty) return null;
  try {
    return await FirebaseStorage.instance.ref(path).getDownloadURL();
  } catch (_) {
    return null;
  }
});

enum LibraryViewMode { list, grid }

final libraryViewModeProvider =
    StateProvider<LibraryViewMode>((ref) => LibraryViewMode.grid);

enum LibrarySortMode { lastOpen, sortOrder }

final librarySortModeProvider =
    StateProvider<LibrarySortMode>((ref) => LibrarySortMode.lastOpen);

final allProgressLastOpenProvider =
    StreamProvider.autoDispose<Map<String, DateTime>>(
        (ref) => watchAllProgressLastOpen());

List<Book> _sortBooksByLastOpen(
  List<Book> books,
  Map<String, DateTime> progressMap,
) {
  final sorted = List<Book>.from(books);
  sorted.sort((a, b) {
    final aAt = progressMap[a.id];
    final bAt = progressMap[b.id];
    if (aAt != null && bAt != null) return bAt.compareTo(aAt);
    if (aAt != null) return -1;
    if (bAt != null) return 1;
    return b.createdAt.compareTo(a.createdAt);
  });
  return sorted;
}

Future<void> openBook(BuildContext context, WidgetRef ref, Book book) async {
  try {
    final file = await downloadBookToCache(book.storagePath, book.fileName);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(book: book, localPath: file.path),
      ),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open book: $e')),
      );
    }
  }
}

Future<void> _refreshMissingCovers(
  BuildContext context,
  WidgetRef ref,
  List<Book> books,
) async {
  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 24),
          Text('Refreshing missing covers…'),
        ],
      ),
    ),
  );
  try {
    final updated = await refreshMissingCovers(books);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ref.invalidate(booksStreamProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          updated > 0
              ? '$updated cover${updated == 1 ? '' : 's'} updated'
              : 'No books needed a cover refresh',
        ),
      ),
    );
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Refresh failed: $e')),
      );
    }
  }
}

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(booksStreamProvider);
    final viewMode = ref.watch(libraryViewModeProvider);
    final sortMode = ref.watch(librarySortModeProvider);
    final progressMapAsync = ref.watch(allProgressLastOpenProvider);
    final books = booksAsync.valueOrNull;
    final hasBooks = books != null && books.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Book Reader'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.notes_outlined),
            tooltip: 'Notes',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AllNotesScreen(),
                ),
              );
            },
          ),
          if (hasBooks) ...[
            SegmentedButton<LibrarySortMode>(
              segments: const [
                ButtonSegment<LibrarySortMode>(
                  value: LibrarySortMode.lastOpen,
                  label: Text('Last open'),
                  icon: Icon(Icons.access_time),
                ),
                ButtonSegment<LibrarySortMode>(
                  value: LibrarySortMode.sortOrder,
                  label: Text('Sort order'),
                  icon: Icon(Icons.sort),
                ),
              ],
              selected: {sortMode},
              onSelectionChanged: (Set<LibrarySortMode> selected) {
                ref.read(librarySortModeProvider.notifier).state =
                    selected.first;
              },
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh missing covers',
              onPressed: () => _refreshMissingCovers(context, ref, books),
            ),
            IconButton(
              icon: Icon(
                viewMode == LibraryViewMode.list
                    ? Icons.grid_view
                    : Icons.view_list,
              ),
              onPressed: () {
                ref.read(libraryViewModeProvider.notifier).state =
                    viewMode == LibraryViewMode.list
                        ? LibraryViewMode.grid
                        : LibraryViewMode.list;
              },
            ),
          ],
        ],
      ),
      body: booksAsync.when(
        data: (books) {
          if (books.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No books yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to add a book from your device',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            );
          }
          final progressMap = progressMapAsync.valueOrNull ?? {};
          final sortedBooks = sortMode == LibrarySortMode.sortOrder
              ? books
              : _sortBooksByLastOpen(books, progressMap);
          if (viewMode == LibraryViewMode.grid) {
            return _ReorderableBookGrid(
              books: sortedBooks,
              ref: ref,
              sortMode: sortMode,
            );
          }
          return ListView.builder(
            itemCount: sortedBooks.length,
            itemBuilder: (context, index) {
              final book = sortedBooks[index];
              return _BookListTile(book: book);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error: $err', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(booksStreamProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _pickAndUploadBook(context, ref),
        tooltip: 'Add book',
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _pickAndUploadBook(BuildContext context, WidgetRef ref) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'epub'],
        withData: true,
      );
    } catch (e, stackTrace) {
      developer.log('File picker error', error: e, stackTrace: stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file picker: $e')),
        );
      }
      return;
    }

    if (result == null || result.files.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No file selected')),
        );
      }
      return;
    }

    final file = result.files.single;
    if (file.bytes == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not read file. On desktop, ensure the app has file access.',
            ),
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Uploading…'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await addBook(
        fileBytes: file.bytes!,
        fileName: file.name,
        title: file.name,
      );
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Book added')),
        );
      }
    } catch (e, stackTrace) {
      developer.log('Upload failed', error: e, stackTrace: stackTrace);
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }
  }
}

class _ReorderableBookGrid extends ConsumerStatefulWidget {
  const _ReorderableBookGrid({
    required this.books,
    required this.ref,
    required this.sortMode,
  });

  final List<Book> books;
  final WidgetRef ref;
  final LibrarySortMode sortMode;

  @override
  ConsumerState<_ReorderableBookGrid> createState() =>
      _ReorderableBookGridState();
}

class _ReorderableBookGridState extends ConsumerState<_ReorderableBookGrid> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final books = widget.books;
    final children = List.generate(
      books.length,
      (index) {
        final book = books[index];
        return KeyedSubtree(
          key: ValueKey(book.id),
          child: _BookGridTile(book: book),
        );
      },
    );

    return ReorderableBuilder(
      scrollController: _scrollController,
      enableDraggable: widget.sortMode == LibrarySortMode.sortOrder,
      children: children,
      onReorder: (ReorderedListFunction reorderedListFunction) {
        final newOrderedBooks = reorderedListFunction(books) as List<Book>;
        updateBooksOrder(newOrderedBooks).catchError((e, st) {
          developer.log('updateBooksOrder failed', error: e, stackTrace: st);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not save order: $e')),
            );
            ref.invalidate(booksStreamProvider);
          }
        });
      },
      builder: (children) {
        return GridView(
          controller: _scrollController,
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2 / 3,
          ),
          children: children,
        );
      },
    );
  }
}

class _BookListTile extends ConsumerWidget {
  const _BookListTile({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressAsync = ref.watch(progressForBookProvider(book.id));
    final coverUrlAsync = book.coverPath != null
        ? ref.watch(coverUrlProvider(book.coverPath!))
        : const AsyncValue.data(null);

    return ListTile(
      leading: coverUrlAsync.when(
        data: (url) {
          if (url != null && url.isNotEmpty) {
            return CircleAvatar(
              child: ClipOval(
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  width: 40,
                  height: 40,
                  errorBuilder: (_, dynamic e, dynamic st) => Icon(
                    book.format == 'pdf' ? Icons.picture_as_pdf : Icons.book,
                  ),
                ),
              ),
            );
          }
          return CircleAvatar(
            child: Icon(book.format == 'pdf' ? Icons.picture_as_pdf : Icons.book),
          );
        },
        loading: () => CircleAvatar(
          child: Icon(book.format == 'pdf' ? Icons.picture_as_pdf : Icons.book),
        ),
        error: (dynamic e, dynamic st) => CircleAvatar(
          child: Icon(book.format == 'pdf' ? Icons.picture_as_pdf : Icons.book),
        ),
      ),
      title: Text(book.title),
      subtitle: progressAsync.whenOrNull(
        data: (p) => p != null
            ? Text('Page ${p.pageIndex + 1}')
            : null,
      ),
      onTap: () => openBook(context, ref, book),
    );
  }
}

class _BookGridTile extends ConsumerWidget {
  const _BookGridTile({required this.book});

  final Book book;

  Widget _coverPlaceholder(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primaryContainer,
            Theme.of(context).colorScheme.secondaryContainer,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          book.format == 'pdf' ? Icons.picture_as_pdf : Icons.menu_book,
          size: 64,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressAsync = ref.watch(progressForBookProvider(book.id));
    final coverUrlAsync = book.coverPath != null
        ? ref.watch(coverUrlProvider(book.coverPath!))
        : const AsyncValue.data(null);

    /// Portrait aspect ratio (2:3) so books look like books and image is never horizontal.
    const double coverAspectRatio = 2 / 3;

    Widget coverWidget = coverUrlAsync.when(
      data: (url) {
        if (url != null && url.isNotEmpty) {
          return CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, _) => _coverPlaceholder(context),
            errorWidget: (_, _, _) => _coverPlaceholder(context),
          );
        }
        return _coverPlaceholder(context);
      },
      loading: () => _coverPlaceholder(context),
      error: (dynamic e, dynamic st) => _coverPlaceholder(context),
    );

    final progress = progressAsync.valueOrNull;
    final hasProgress = progress != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openBook(context, ref, book),
        child: AspectRatio(
          aspectRatio: coverAspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              coverWidget,
              Positioned(
                bottom: 6,
                right: 6,
                child: hasProgress
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surface
                              .withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${progress.pageIndex + 1}',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'NEW',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
