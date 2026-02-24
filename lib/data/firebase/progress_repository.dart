import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/reading_progress.dart';

final _firestore = FirebaseFirestore.instance;
const _collection = 'progress';

Stream<ReadingProgress?> watchProgress(String bookId) {
  return _firestore
      .collection(_collection)
      .doc(bookId)
      .snapshots()
      .map((doc) {
        if (!doc.exists || doc.data() == null) return null;
        return ReadingProgress.fromFirestore(doc.data()!, doc.id);
      });
}

Future<void> saveProgress(String bookId, int pageIndex) {
  return _firestore.collection(_collection).doc(bookId).set({
    'pageIndex': pageIndex,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

Future<ReadingProgress?> getProgress(String bookId) async {
  final doc =
      await _firestore.collection(_collection).doc(bookId).get();
  if (!doc.exists || doc.data() == null) return null;
  return ReadingProgress.fromFirestore(doc.data()!, doc.id);
}

/// Stream of bookId -> last opened (updatedAt) for all progress docs.
/// Used to sort the library by "last open".
Stream<Map<String, DateTime>> watchAllProgressLastOpen() {
  return _firestore.collection(_collection).snapshots().map((snap) {
    final map = <String, DateTime>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final updated = data['updatedAt'];
      if (updated != null) {
        map[doc.id] = (updated as Timestamp).toDate();
      }
    }
    return map;
  });
}
