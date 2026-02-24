import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

final _storage = FirebaseStorage.instance;

/// Download a book file from Storage to a local cache file.
/// Returns the local file path. Creates dir books_cache under app documents.
Future<File> downloadBookToCache(String storagePath, String fileName) async {
  final ref = _storage.ref().child(storagePath);
  final dir = await getApplicationDocumentsDirectory();
  final cacheDir = Directory(p.join(dir.path, 'books_cache'));
  if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
  final localPath = p.join(cacheDir.path, storagePath.replaceAll('/', '_'));
  final file = File(localPath);
  if (await file.exists()) return file;
  await ref.writeToFile(file);
  return file;
}