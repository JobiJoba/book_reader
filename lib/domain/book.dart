import 'package:cloud_firestore/cloud_firestore.dart';

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.fileName,
    required this.storagePath,
    required this.format,
    required this.createdAt,
    this.coverPath,
    this.orderIndex,
  });

  final String id;
  final String title;
  final String fileName;
  final String storagePath;
  final String format; // 'pdf', 'epub', 'other'
  final DateTime createdAt;
  final String? coverPath;
  final int? orderIndex;

  factory Book.fromFirestore(Map<String, dynamic> data, String id) {
    return Book(
      id: id,
      title: data['title'] as String? ?? '',
      fileName: data['fileName'] as String? ?? '',
      storagePath: data['storagePath'] as String? ?? '',
      format: data['format'] as String? ?? 'other',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      coverPath: data['coverPath'] as String?,
      orderIndex: data['orderIndex'] as int?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'fileName': fileName,
      'storagePath': storagePath,
      'format': format,
      'createdAt': Timestamp.fromDate(createdAt),
      if (coverPath != null) 'coverPath': coverPath,
      if (orderIndex != null) 'orderIndex': orderIndex,
    };
  }
}

