import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../capped_download.dart';

/// Downloads the Intradesk file [fileId] (checked with `isIntradeskId`),
/// stopping with a [FileTooLargeError] once it is clear the file is larger
/// than [maxBytes].
///
/// The request `IntradeskService.downloadFile` sends, which cannot be
/// limited (yvanvds/dartschool#41, #22).
Future<DownloadedFile> downloadIntradeskFile(
  SmartschoolClient client,
  String fileId, {
  required int maxBytes,
}) async {
  final platformId = await client.platformId;
  return downloadCapped(
    client,
    '/intradesk/api/v1/$platformId/files/$fileId/download',
    maxBytes: maxBytes,
  );
}
