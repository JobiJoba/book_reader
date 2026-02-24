import 'package:cloud_firestore/cloud_firestore.dart';

class ReadingProgress {
  const ReadingProgress({
    required this.bookId,
    required this.pageIndex,
    required this.updatedAt,
  });

  final String bookId;
  final int pageIndex;
  final DateTime updatedAt;

  factory ReadingProgress.fromFirestore(Map<String, dynamic> data, String bookId) {
    return ReadingProgress(
      bookId: bookId,
      pageIndex: data['pageIndex'] as int? ?? 0,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'pageIndex': pageIndex,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}
