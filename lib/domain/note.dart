import 'package:cloud_firestore/cloud_firestore.dart';

class Note {
  const Note({
    required this.id,
    required this.text,
    required this.position,
    required this.createdAt,
  });

  final String id;
  final String text;
  final String position; // page index or CFI for epub
  final DateTime createdAt;

  factory Note.fromFirestore(Map<String, dynamic> data, String id) {
    return Note(
      id: id,
      text: data['text'] as String? ?? '',
      position: data['position'] as String? ?? '0',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'text': text,
      'position': position,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
