import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'document_content.dart';

/// An image larger than this is scaled down before it goes to Claude.
///
/// Claude Desktop refuses a tool result larger than 1 MB, and MCP sends an
/// image base64-encoded (4 characters for every 3 bytes): 700 KB becomes
/// about 930 KB.
const maxImageBytes = 700 * 1024;

/// The longest side of a scaled-down image: what Claude's vision works at
/// without scaling it down again.
const _maxSide = 1568;

/// [bytes], an image of [mimeType] (PNG, JPEG, GIF or WebP), as it can go
/// to Claude: unchanged when it is at most [maxBytes], otherwise decoded,
/// turned upright, scaled down (longest side at most 1568 pixels, then 1024)
/// and saved as JPEG.
DocumentContent imageContent(
  Uint8List bytes,
  String mimeType, {
  int maxBytes = maxImageBytes,
}) {
  if (bytes.length <= maxBytes) {
    return DocumentImage(bytes: bytes, mimeType: mimeType);
  }
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes, frame: 0);
  } catch (_) {
    throw const UnreadableDocumentException(
      'It could not be read as an image: the file seems damaged.',
    );
  }
  if (decoded == null) {
    throw const UnreadableDocumentException(
      'It could not be read as an image: the file seems damaged.',
    );
  }
  final upright = img.bakeOrientation(decoded);
  for (final (side, quality) in const [(_maxSide, 80), (1024, 70)]) {
    final fitted = _fit(upright, side);
    final jpeg = img.encodeJpg(_flatten(fitted), quality: quality);
    if (jpeg.length <= maxBytes) {
      return DocumentImage(
        bytes: jpeg,
        mimeType: 'image/jpeg',
        notes: [
          'The image (${upright.width}×${upright.height} pixels) was scaled '
              'down to ${fitted.width}×${fitted.height} pixels to fit.',
        ],
      );
    }
  }
  throw const UnreadableDocumentException(
    'The image is too large to show, even scaled down.',
  );
}

/// [image] scaled down so that its longest side is at most [side] pixels.
img.Image _fit(img.Image image, int side) {
  if (image.width <= side && image.height <= side) return image;
  return image.width >= image.height
      ? img.copyResize(
          image,
          width: side,
          interpolation: img.Interpolation.average,
        )
      : img.copyResize(
          image,
          height: side,
          interpolation: img.Interpolation.average,
        );
}

/// [image] on a white background when it has transparency: JPEG has none.
img.Image _flatten(img.Image image) {
  if (!image.hasAlpha) return image;
  final background = img.Image(width: image.width, height: image.height)
    ..clear(img.ColorRgb8(255, 255, 255));
  return img.compositeImage(background, image);
}
