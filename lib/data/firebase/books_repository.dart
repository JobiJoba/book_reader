import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../domain/book.dart';
import 'book_id.dart';
import 'cover_service.dart';

final _firestore = FirebaseFirestore.instance;
final _storage = FirebaseStorage.instance;

const _booksCollection = 'books';

/// Storage path for a book file: books/{bookId}/file.{ext}
/// Uses a safe segment to avoid backend errors from spaces/parentheses in filenames.
String storagePathForBook(String bookId, String fileName) {
  final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'bin';
  final safeExt = (ext == 'pdf' || ext == 'epub') ? ext : 'bin';
  return 'books/$bookId/file.$safeExt';
}

/// Stream of all books (with offline persistence).
/// Sorted by [Book.orderIndex] (nulls last), then by [Book.createdAt].
Stream<List<Book>> watchBooks() {
  return _firestore.collection(_booksCollection).snapshots().map((snap) {
    final list = snap.docs
        .map((doc) => Book.fromFirestore(doc.data(), doc.id))
        .toList();
    list.sort((a, b) {
      final aOrder = a.orderIndex;
      final bOrder = b.orderIndex;
      if (aOrder != null && bOrder != null) return aOrder.compareTo(bOrder);
      if (aOrder != null) return -1;
      if (bOrder != null) return 1;
      return a.createdAt.compareTo(b.createdAt);
    });
    return list;
  });
}

/// Add a book: upload file to Storage and create Firestore doc.
/// [fileBytes] and [fileName] from file picker; [title] can be derived from fileName.
Future<Book> addBook({
  required List<int> fileBytes,
  required String fileName,
  String? title,
}) async {
  final bookId = sanitizeDocId(computeBookId(fileBytes));
  final path = storagePathForBook(bookId, fileName);
  developer.log('addBook: uploading to Storage path=$path', name: 'BooksRepository');
  final ref = _storage.ref().child(path);
  try {
    await ref.putData(
      fileBytes is Uint8List
          ? fileBytes
          : Uint8List.fromList(fileBytes),
    );
  } catch (e, stackTrace) {
    if (e is FirebaseException) {
      developer.log(
        'addBook: Storage upload failed code=${e.code} message=${e.message}',
        name: 'BooksRepository',
        error: e,
        stackTrace: stackTrace,
      );
    } else {
      developer.log('addBook: Storage upload failed', name: 'BooksRepository', error: e, stackTrace: stackTrace);
    }
    rethrow;
  }
  final format = _formatFromFileName(fileName);
  String? coverPath;
  final coverResult = await generateCoverBytes(fileBytes, format);
  if (coverResult != null) {
    try {
      coverPath = 'books/$bookId/cover.${coverResult.ext}';
      final coverRef = _storage.ref().child(coverPath);
      await coverRef.putData(coverResult.bytes);
      developer.log('addBook: cover uploaded path=$coverPath', name: 'BooksRepository');
    } catch (e, stackTrace) {
      developer.log('addBook: cover upload failed', name: 'BooksRepository', error: e, stackTrace: stackTrace);
    }
  }

  developer.log('addBook: creating Firestore doc bookId=$bookId', name: 'BooksRepository');
  final book = Book(
    id: bookId,
    title: title ?? fileName,
    fileName: fileName,
    storagePath: path,
    format: format,
    createdAt: DateTime.now(),
    coverPath: coverPath,
  );
  try {
    await _firestore.collection(_booksCollection).doc(bookId).set(book.toFirestore());
  } catch (e, stackTrace) {
    developer.log('addBook: Firestore write failed', name: 'BooksRepository', error: e, stackTrace: stackTrace);
    rethrow;
  }
  developer.log('addBook: success bookId=$bookId', name: 'BooksRepository');
  return book;
}

String _formatFromFileName(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  if (ext == 'pdf') return 'pdf';
  if (ext == 'epub') return 'epub';
  return 'other';
}

/// Persist the current grid order. Updates [Book.orderIndex] in Firestore
/// for each book (only writes docs whose orderIndex changed).
Future<void> updateBooksOrder(List<Book> orderedBooks) async {
  final batch = _firestore.batch();
  for (var i = 0; i < orderedBooks.length; i++) {
    final book = orderedBooks[i];
    if (book.orderIndex != i) {
      batch.update(
        _firestore.collection(_booksCollection).doc(book.id),
        {'orderIndex': i},
      );
    }
  }
  await batch.commit();
}

/// Get a single book by id.
Future<Book?> getBook(String bookId) async {
  final doc = await _firestore.collection(_booksCollection).doc(bookId).get();
  if (!doc.exists || doc.data() == null) return null;
  return Book.fromFirestore(doc.data()!, doc.id);
}

/// Refresh covers for books that have none. Downloads each book from Storage,
/// generates cover (PDF first page / EPUB cover or first image), uploads to Storage,
/// and updates Firestore. Returns the number of covers created.
Future<int> refreshMissingCovers(List<Book> books) async {
  final toProcess = books
      .where((b) =>
          b.coverPath == null &&
          (b.format == 'pdf' || b.format == 'epub'))
      .toList();
  if (toProcess.isEmpty) return 0;
  int updated = 0;
  for (final book in toProcess) {
    try {
      final data = await _storage.ref().child(book.storagePath).getData();
      if (data == null || data.isEmpty) continue;
      final coverResult = await generateCoverBytes(data, book.format);
      if (coverResult == null) continue;
      final coverPath = 'books/${book.id}/cover.${coverResult.ext}';
      final coverRef = _storage.ref().child(coverPath);
      await coverRef.putData(coverResult.bytes);
      await _firestore
          .collection(_booksCollection)
          .doc(book.id)
          .update({'coverPath': coverPath});
      updated++;
      developer.log('refreshMissingCovers: updated bookId=${book.id}', name: 'BooksRepository');
    } catch (e, stackTrace) {
      developer.log(
        'refreshMissingCovers: failed for bookId=${book.id}',
        name: 'BooksRepository',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
  return updated;
}
