import 'dart:typed_data';

/// The kinds of files `readDocument` can read.
enum DocumentFormat {
  docx('Word document'),
  xlsx('Excel workbook'),
  pptx('PowerPoint presentation'),
  pdf('PDF'),
  text('text file'),
  html('web page'),
  image('image');

  const DocumentFormat(this.label);

  /// What tool output calls it.
  final String label;
}

/// What `readDocument` made of a file: its text, an image, or why it cannot
/// be read.
sealed class DocumentContent {
  const DocumentContent();
}

/// The text of a document, as plain text with light Markdown: `## Page 3`,
/// `## Sheet: Blad1` and `## Slide 2` lines between the parts, `#` lines for
/// headings, `- ` lines for list items, and table rows as one line with the
/// cells joined by ` | `.
final class DocumentText extends DocumentContent {
  const DocumentText({
    required this.format,
    required this.text,
    this.parts,
    this.truncated = false,
    this.fullLength,
    this.notes = const [],
  });

  final DocumentFormat format;

  /// The text, at most the character budget long; empty when the document
  /// has no text.
  final String text;

  /// What the document consists of, like `12 pages`, `3 sheets` or
  /// `20 slides`; null for formats without parts.
  final String? parts;

  /// Whether [text] stops at the character budget.
  final bool truncated;

  /// The length of the whole text when [truncated] and it is known; null
  /// when reading stopped at the budget, before the end.
  final int? fullLength;

  /// Sentences for the reader about what was left out, like pages that
  /// could not be read.
  final List<String> notes;
}

/// An image, small enough to hand to Claude as MCP image content.
final class DocumentImage extends DocumentContent {
  const DocumentImage({
    required this.bytes,
    required this.mimeType,
    this.notes = const [],
  });

  final Uint8List bytes;

  /// `image/png`, `image/jpeg`, `image/gif` or `image/webp`.
  final String mimeType;

  /// Sentences for the reader, like that the image was scaled down.
  final List<String> notes;
}

/// A file that cannot be read, with the [reason] for Claude: one or more
/// sentences, like `It is in the old Word format (.doc), which cannot be
/// read.`
final class UnreadableDocument extends DocumentContent {
  const UnreadableDocument(this.reason);

  final String reason;
}

/// Thrown by the format readers for a file they cannot read; `readDocument`
/// turns it into an [UnreadableDocument].
final class UnreadableDocumentException implements Exception {
  const UnreadableDocumentException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}
