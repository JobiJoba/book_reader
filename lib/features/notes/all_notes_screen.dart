import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/firebase/books_repository.dart';
import '../../data/firebase/notes_repository.dart';
import '../../domain/book.dart';
import '../../domain/note.dart';
import 'book_notes_screen.dart';

final _allNotesGroupedProvider =
    StreamProvider.autoDispose<Map<String, List<Note>>>(
  (ref) => watchAllNotesGroupedByBook(),
);

final _booksStreamProvider =
    StreamProvider.autoDispose<List<Book>>((ref) => watchBooks());

class AllNotesScreen extends ConsumerStatefulWidget {
  const AllNotesScreen({super.key});

  @override
  ConsumerState<AllNotesScreen> createState() => _AllNotesScreenState();
}

class _AllNotesScreenState extends ConsumerState<AllNotesScreen> {
  String? _selectedBookId;

  static const double _tabletBreakpoint = 600;

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(_booksStreamProvider);
    final notesGroupedAsync = ref.watch(_allNotesGroupedProvider);
    final isWide = MediaQuery.sizeOf(context).width >= _tabletBreakpoint;

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Notes'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: notesGroupedAsync.when(
        data: (notesByBookId) {
          if (notesByBookId.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notes_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No notes yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add notes from the reader',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            );
          }

          return booksAsync.when(
            data: (allBooks) {
              final bookIdsWithNotes = notesByBookId.keys.toList();
              final booksWithNotes = allBooks
                  .where((b) => bookIdsWithNotes.contains(b.id))
                  .toList();
              // Keep selection valid
              if (_selectedBookId != null &&
                  !bookIdsWithNotes.contains(_selectedBookId)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _selectedBookId = null);
                });
              }
              if (booksWithNotes.isEmpty) {
                return const Center(child: Text('No notes'));
              }

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 280,
                      child: Material(
                        elevation: 0,
                        child: ListView.builder(
                          itemCount: booksWithNotes.length,
                          itemBuilder: (context, index) {
                            final book = booksWithNotes[index];
                            final count = notesByBookId[book.id]!.length;
                            final selected = _selectedBookId == book.id;
                            return ListTile(
                              title: Text(book.title),
                              subtitle: Text('$count note${count == 1 ? '' : 's'}'),
                              selected: selected,
                              onTap: () {
                                setState(() => _selectedBookId = book.id);
                              },
                            );
                          },
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _selectedBookId == null
                          ? Center(
                              child: Text(
                                'Select a book',
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: Theme.of(context).colorScheme.outline,
                                    ),
                              ),
                            )
                          : _NotesListPanel(
                              book: booksWithNotes.firstWhere(
                                (b) => b.id == _selectedBookId,
                              ),
                              notes: notesByBookId[_selectedBookId!]!,
                            ),
                    ),
                  ],
                );
              }

              // Narrow: list of books, tap pushes BookNotesScreen
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: booksWithNotes.length,
                itemBuilder: (context, index) {
                  final book = booksWithNotes[index];
                  final count = notesByBookId[book.id]!.length;
                  return ListTile(
                    title: Text(book.title),
                    subtitle: Text('$count note${count == 1 ? '' : 's'}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => BookNotesScreen(book: book),
                        ),
                      );
                    },
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Center(child: Text('Error: $e')),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _NotesListPanel extends StatelessWidget {
  const _NotesListPanel({required this.book, required this.notes});

  final Book book;
  final List<Note> notes;

  static String _pageLabel(Note note) {
    final pageIndex = int.tryParse(note.position);
    final pageNum = (pageIndex ?? 0) + 1;
    return 'Page $pageNum';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            book.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              final preview = note.text.length > 100
                  ? '${note.text.substring(0, 100)}…'
                  : note.text;
              final dateStr =
                  '${note.createdAt.year}-${note.createdAt.month.toString().padLeft(2, '0')}-${note.createdAt.day.toString().padLeft(2, '0')} '
                  '${note.createdAt.hour.toString().padLeft(2, '0')}:${note.createdAt.minute.toString().padLeft(2, '0')}';
              return ListTile(
                title: Text(preview),
                subtitle: Text(
                  '${_pageLabel(note)} · $dateStr',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outlined),
                  tooltip: 'Delete note',
                  onPressed: () =>
                      _NotesListPanel._confirmDeleteNote(context, book.id, note),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static Future<void> _confirmDeleteNote(
    BuildContext context,
    String bookId,
    Note note,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text(
          'This note will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await removeNote(bookId, note.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Note deleted')),
    );
  }
}
