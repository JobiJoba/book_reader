import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/note.dart';

final _firestore = FirebaseFirestore.instance;
const _collection = 'notes';

Stream<List<Note>> watchNotes(String bookId) {
  return _firestore
      .collection(_collection)
      .doc(bookId)
      .collection('items')
      .snapshots()
      .map((snap) => snap.docs
          .map((doc) => Note.fromFirestore(doc.data(), doc.id))
          .toList());
}

Future<void> addNote(String bookId, Note note) {
  final col = _firestore
      .collection(_collection)
      .doc(bookId)
      .collection('items');
  return col.doc(note.id).set(note.toFirestore());
}

Future<void> removeNote(String bookId, String noteId) {
  return _firestore
      .collection(_collection)
      .doc(bookId)
      .collection('items')
      .doc(noteId)
      .delete();
}

/// Stream of all notes grouped by book ID. Uses collection group query on
/// [notes] collection's [items] subcollection. Combine with books list to show titles.
Stream<Map<String, List<Note>>> watchAllNotesGroupedByBook() {
  return _firestore
      .collectionGroup('items')
      .snapshots()
      .map((snap) {
        final map = <String, List<Note>>{};
        for (final doc in snap.docs) {
          // Path is notes/{bookId}/items/{noteId}
          final bookId = doc.reference.parent.parent?.id;
          if (bookId == null) continue;
          final note = Note.fromFirestore(doc.data(), doc.id);
          map.putIfAbsent(bookId, () => []).add(note);
        }
        // Sort notes by createdAt within each book
        for (final list in map.values) {
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        }
        return map;
      });
}
