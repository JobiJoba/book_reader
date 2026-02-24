import 'package:flutter/material.dart';

import 'features/library/library_screen.dart';

class BookReaderApp extends StatelessWidget {
  const BookReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Book Reader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const LibraryScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
