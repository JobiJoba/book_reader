import 'package:crypto/crypto.dart';

/// Returns a content-based ID (SHA-256 hex) for the given file bytes.
String computeBookId(List<int> bytes) {
  final digest = sha256.convert(bytes);
  return digest.toString();
}

/// Sanitize Firestore document ID: replace invalid chars with underscore.
String sanitizeDocId(String id) {
  return id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
}
