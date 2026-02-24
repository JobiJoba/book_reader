import 'dart:convert';
import 'dart:io';

import 'package:epub_plus/epub_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../data/firebase/progress_repository.dart';
import '../../domain/book.dart';

/// Builds the epub_plus-based EPUB viewer when dart:io is available (macOS, etc.).
Widget buildEpubPlusViewer({
  required String localPath,
  required Book book,
}) {
  return _EpubPlusReaderScope(localPath: localPath, book: book);
}

class _EpubPlusReaderScope extends StatefulWidget {
  const _EpubPlusReaderScope({required this.localPath, required this.book});

  final String localPath;
  final Book book;

  @override
  State<_EpubPlusReaderScope> createState() => _EpubPlusReaderScopeState();
}

class _EpubPlusReaderScopeState extends State<_EpubPlusReaderScope> {
  EpubBook? _epubBook;
  List<EpubChapter> _flatChapters = [];
  int _currentChapterIndex = 0;
  bool _loading = true;
  String? _error;
  InAppWebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    _loadBook();
  }

  @override
  void dispose() {
    _saveChapterProgress();
    super.dispose();
  }

  void _saveChapterProgress() {
    if (_flatChapters.isEmpty) return;
    saveProgress(widget.book.id, _currentChapterIndex.clamp(0, _flatChapters.length - 1));
  }

  Future<void> _loadBook() async {
    try {
      final file = File(widget.localPath);
      if (!await file.exists()) {
        setState(() {
          _loading = false;
          _error = 'File not found.';
        });
        return;
      }
      final bytes = await file.readAsBytes();
      final book = await EpubReader.readBook(bytes);
      final flatChapters = _flattenChapters(book.chapters);
      int savedChapterIndex = 0;
      if (flatChapters.isNotEmpty) {
        final progress = await getProgress(widget.book.id);
        final raw = progress?.pageIndex ?? 0;
        savedChapterIndex = raw.clamp(0, flatChapters.length - 1);
      }
      if (!mounted) return;
      setState(() {
        _epubBook = book;
        _flatChapters = flatChapters;
        _currentChapterIndex = savedChapterIndex;
        _loading = false;
        _error = null;
      });
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('EpubPlusReader load error: $e\n$stackTrace');
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  static List<EpubChapter> _flattenChapters(List<EpubChapter> chapters) {
    final result = <EpubChapter>[];
    for (final c in chapters) {
      result.add(c);
      if (c.subChapters.isNotEmpty) {
        result.addAll(_flattenChapters(c.subChapters));
      }
    }
    return result;
  }

  String _buildChapterHtml(EpubChapter chapter) {
    final book = _epubBook!;
    final content = book.content;
    final basePath = _chapterBasePath(chapter);
    final cssBlock = _buildCssBlock(content);
    String bodyHtml = chapter.htmlContent ?? '';
    bodyHtml = _resolveUrlsInHtml(bodyHtml, basePath, content);
    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
$cssBlock
</head>
<body>
$bodyHtml
</body>
</html>''';
  }

  String _chapterBasePath(EpubChapter chapter) {
    final name = chapter.contentFileName ?? '';
    if (name.isEmpty) return '';
    final lastSlash = name.lastIndexOf('/');
    if (lastSlash < 0) return '';
    return name.substring(0, lastSlash + 1);
  }

  String _buildCssBlock(EpubContent? content) {
    final css = content?.css;
    if (css == null || css.isEmpty) return '';
    final buffer = StringBuffer('<style>');
    for (final file in css.values) {
      if (file.content != null && file.content!.isNotEmpty) {
        buffer.write(file.content);
      }
    }
    buffer.write('</style>');
    return buffer.toString();
  }

  /// Resolve relative URLs in HTML to data URIs using content.images and content.css.
  String _resolveUrlsInHtml(String html, String basePath, EpubContent? content) {
    if (content == null) return html;
    final images = content.images;
    if (images.isEmpty) return html;

    // Replace img src="..." or src='...'.
    final imgPattern = RegExp('<img([^>]*)\\ssrc=(["\'])([^"\']+)\\2([^>]*)>', caseSensitive: false);
    html = html.replaceAllMapped(imgPattern, (match) {
      final before = match.group(1) ?? '';
      final url = match.group(3) ?? '';
      final after = match.group(4) ?? '';
      final dataUri = _resolveToDataUri(url, basePath, content);
      if (dataUri != null) {
        return '<img$before src="$dataUri"$after>';
      }
      return match.group(0) ?? '';
    });
    return html;
  }

  String? _resolveToDataUri(String relativeUrl, String basePath, EpubContent content) {
    final resolved = _resolvePath(basePath, relativeUrl);
    if (resolved.isEmpty) return null;

    // Try exact key, then try with/without leading slash, then filename only.
    final candidates = [
      resolved,
      resolved.replaceFirst(RegExp(r'^/'), ''),
      resolved.startsWith('/') ? resolved.substring(1) : '/$resolved',
      resolved.contains('/') ? resolved.substring(resolved.lastIndexOf('/') + 1) : resolved,
    ];
    final images = content.images;
    for (final key in candidates) {
      final file = images[key];
      if (file != null && file.content != null && file.content!.isNotEmpty) {
        final mime = file.contentMimeType ?? 'image/png';
        final b64 = base64Encode(file.content!);
        return 'data:$mime;base64,$b64';
      }
    }
    return null;
  }

  static String _resolvePath(String basePath, String relativeRef) {
    if (relativeRef.isEmpty) return '';
    relativeRef = relativeRef.split('?').first.split('#').first;
    final baseSegments = basePath.replaceFirst(RegExp(r'/$'), '').split('/').where((s) => s.isNotEmpty).toList();
    final parts = relativeRef.split('/');
    for (final p in parts) {
      if (p == '.' || p.isEmpty) continue;
      if (p == '..') {
        if (baseSegments.isNotEmpty) baseSegments.removeLast();
      } else {
        baseSegments.add(p);
      }
    }
    return baseSegments.join('/');
  }

  void _loadCurrentChapterInWebView() {
    if (_epubBook == null || _flatChapters.isEmpty || _currentChapterIndex >= _flatChapters.length) return;
    final chapter = _flatChapters[_currentChapterIndex];
    // If this is a subtitle with anchor but no content, use the chapter that has the same file and has htmlContent (so the anchor exists in the doc).
    final chapterToLoad = _chapterWithContentFor(chapter);
    final html = _buildChapterHtml(chapterToLoad);
    _webViewController?.loadData(
      data: html,
      baseUrl: WebUri('about:blank'),
      mimeType: 'text/html',
      encoding: 'utf-8',
    );
  }

  /// For a subchapter with anchor but empty htmlContent, returns the chapter that contains the full HTML (same contentFileName).
  EpubChapter _chapterWithContentFor(EpubChapter chapter) {
    if ((chapter.htmlContent != null && chapter.htmlContent!.trim().isNotEmpty)) {
      return chapter;
    }
    final fileName = chapter.contentFileName ?? '';
    if (fileName.isEmpty) return chapter;
    for (final c in _flatChapters) {
      if (c.contentFileName == fileName &&
          c.htmlContent != null &&
          c.htmlContent!.trim().isNotEmpty) {
        return c;
      }
    }
    return chapter;
  }

  void _scrollWebViewToTop() {
    final chapter = _currentChapterIndex < _flatChapters.length
        ? _flatChapters[_currentChapterIndex]
        : null;
    final rawAnchor = chapter?.anchor?.trim();
    final anchor = rawAnchor != null && rawAnchor.isNotEmpty
        ? (rawAnchor.startsWith('#') ? rawAnchor.substring(1) : rawAnchor)
        : null;
    if (anchor != null && anchor.isNotEmpty) {
      // Scroll to the subtitle/section element (escape for JS string).
      final escaped = anchor
          .replaceAll(r'\', r'\\')
          .replaceAll("'", r"\'");
      _webViewController?.evaluateJavascript(
        source: '''
          (function() {
            var el = document.getElementById('$escaped');
            if (el) { el.scrollIntoView({behavior: 'instant', block: 'start'}); }
            else {
              var heading = document.querySelector('h1, h2, h3, [id]');
              if (heading) { heading.scrollIntoView({behavior: 'instant', block: 'start'}); }
              else { window.scrollTo(0, 0); }
            }
          })();
        ''',
      );
    } else {
      _webViewController?.evaluateJavascript(
        source: 'window.scrollTo(0, 0);',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.book.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.book.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final hasChapters = _flatChapters.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Row(
        children: [
          if (hasChapters)
            SizedBox(
              width: 220,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _flatChapters.length,
                itemBuilder: (context, index) {
                  final ch = _flatChapters[index];
                  final title = ch.title?.isNotEmpty == true ? ch.title! : 'Chapter ${index + 1}';
                  final selected = index == _currentChapterIndex;
                  return ListTile(
                    title: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    selected: selected,
                    onTap: () {
                      setState(() {
                        _currentChapterIndex = index;
                        _loadCurrentChapterInWebView();
                        _saveChapterProgress();
                      });
                    },
                  );
                },
              ),
            ),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: InAppWebView(
                    initialSettings: InAppWebViewSettings(
                      transparentBackground: false,
                      // Disable so loadData() is not intercepted; otherwise chapter changes show a blank page on macOS.
                      useShouldOverrideUrlLoading: false,
                    ),
                    onWebViewCreated: (controller) {
                      _webViewController = controller;
                      _loadCurrentChapterInWebView();
                    },
                    onLoadStop: (controller, url) {
                      _scrollWebViewToTop();
                    },
                    initialData: InAppWebViewInitialData(
                      data: hasChapters
                          ? _buildChapterHtml(_flatChapters[_currentChapterIndex])
                          : _wrapWithHtml('<p>No chapters.</p>'),
                      baseUrl: WebUri('about:blank'),
                      mimeType: 'text/html',
                      encoding: 'utf-8',
                    ),
                  ),
                ),
                if (hasChapters)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        FilledButton.icon(
                          onPressed: _currentChapterIndex > 0
                              ? () {
                                  setState(() {
                                    _currentChapterIndex--;
                                    _loadCurrentChapterInWebView();
                                    _saveChapterProgress();
                                  });
                                }
                              : null,
                          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                          label: const Text('Previous'),
                        ),
                        FilledButton.icon(
                          onPressed: _currentChapterIndex < _flatChapters.length - 1
                              ? () {
                                  setState(() {
                                    _currentChapterIndex++;
                                    _loadCurrentChapterInWebView();
                                    _saveChapterProgress();
                                  });
                                }
                              : null,
                          icon: const Icon(Icons.arrow_forward_ios, size: 18),
                          label: const Text('Next'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _wrapWithHtml(String body) {
    final book = _epubBook;
    final css = book != null ? _buildCssBlock(book.content) : '';
    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
$css
</head>
<body>
$body
</body>
</html>''';
  }
}
