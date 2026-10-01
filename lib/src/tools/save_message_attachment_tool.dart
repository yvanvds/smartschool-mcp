import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../downloads/download_folder.dart';
import '../intradesk/intradesk_format.dart';
import '../log.dart';
import '../messages/message_box.dart';
import '../session.dart';
import 'arguments.dart';
import 'save_intradesk_file_tool.dart';
import 'saved_file_result.dart';
import 'server_tool.dart';

/// `save_message_attachment`: saves one attachment of a Smartschool message
/// into the download folder ([downloads]), so that Claude can open it with
/// its own file tools (in a Cowork project) or the teacher can.
///
/// The attachment is named by its number as `read_message` lists it (1 for
/// the first) or by its file name. Attachments larger than [maxBytes] are
/// not saved. Without a download folder ([downloads] null), every call says
/// how to set one.
ServerTool saveMessageAttachmentTool(
  SmartschoolSession session,
  DownloadFolder? downloads, {
  int maxBytes = maxSavedFileBytes,
}) => ServerTool(
  definition: Tool(
    name: 'save_message_attachment',
    title: 'Save a message attachment',
    description:
        'Saves one attachment of a Smartschool message into the download '
        'folder on this PC, and returns its full path, file name and size. '
        'Use it to open an attachment (a PDF, a scan, a Word or Excel file, '
        'an image, ...) or when the user wants the file itself. After '
        'saving, open the file from the returned path with your own file '
        'tools when you can (for example in a Cowork project whose folder '
        'holds the download folder); otherwise tell the user where the file '
        'is, so they can open it or drag it into the chat. Get the message '
        'id from list_messages or search_messages and pass the same box; '
        'read_message lists the attachments, numbered. Pass the attachment '
        'by that number (1 for the first) or by its file name. Attachments '
        'up to ${formatFileSize(maxBytes)} are saved. An existing file is '
        'never replaced: the new one gets " (2)", " (3)", ... in its name. '
        'Files saved here are deleted after '
        '${DownloadFolder.defaultRetention.inDays} days; other files in the '
        'folder are never touched. Saving does not mark the message as read '
        'and changes nothing in Smartschool.',
    inputSchema: Schema.object(
      properties: {
        'message_id': Schema.int(
          description: 'The id of the message, from list_messages.',
          minimum: 1,
        ),
        'attachment': Schema.combined(
          description:
              'Which attachment: its number as read_message lists it (1 for '
              'the first), or its file name.',
          anyOf: [Schema.int(minimum: 1), Schema.string(minLength: 1)],
        ),
        'box': MessageBox.schema(
          description:
              'The box list_messages showed the message in: inbox (default), '
              'sent or archive.',
        ),
      },
      required: ['message_id', 'attachment'],
    ),
    annotations: ToolAnnotations(
      title: 'Save a message attachment',
      // It writes a file on this PC; it never replaces one.
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: true,
    ),
  ),
  handler: (request) =>
      _save(session, downloads, maxBytes, request.arguments ?? const {}),
);

Future<CallToolResult> _save(
  SmartschoolSession session,
  DownloadFolder? downloads,
  int maxBytes,
  Map<String, Object?> arguments,
) async {
  final id = requiredIntArgument(arguments, 'message_id');
  final box = MessageBox.parse(arguments['box']);
  final which = _attachmentArgument(arguments);
  final folder = downloads ?? (throw noDownloadFolder());

  // As read_message: neither call changes the read state.
  final (message, attachments) = await withMessages(session, (messages) async {
    final message = await box.message(messages, id, allRecipients: false);
    if (message == null || message.attachment <= 0) {
      return (message, const <MessageAttachment>[]);
    }
    return (message, await messages.getAttachments(id, boxType: box.boxType));
  });
  if (message == null) {
    throw ToolError(
      'There is no message with id $id in the ${box.name} box. Take the id '
      'from list_messages and pass the box it was listed in.',
    );
  }
  if (attachments.isEmpty) {
    throw ToolError('Message $id (${box.label}) has no attachments.');
  }
  final (number, attachment) = _pick(attachments, which, id, box);
  final title =
      'attachment $number of message $id (${box.label}), '
      '"${attachment.name.trim()}"';

  final watch = Stopwatch()..start();
  final saved = await folder.save(
    (temporary) => session.run((client) async {
      try {
        // The library refuses a larger announced size before reading any of
        // the file, and otherwise stops the transfer once past the limit.
        final download = await attachment.downloadStream(
          client,
          maxBytes: maxBytes,
        );
        await writeDownload(download, temporary);
        final name = attachment.name.trim();
        return name.isEmpty ? download.fileName : name;
      } on SmartschoolDownloadError catch (error) {
        throw ToolError(
          'Smartschool could not download $title (status '
          '${error.statusCode}). Try again later; the teacher can download '
          'it in Smartschool.',
        );
      } on SmartschoolDownloadTooLargeError catch (error) {
        final size = tooLargeSize(error);
        throw ToolError(
          '${_capitalise(title)}'
          '${size == null ? '' : ' (${formatFileSize(size)})'} '
          '${tooLargeToSave(error)}',
        );
      }
    }),
    fallbackName: 'attachment-$id-$number',
  );
  log(
    'save_message_attachment: ${saved.size} bytes saved in '
    '${watch.elapsedMilliseconds} ms (${describeNameForLog(saved)})',
  );
  return savedFileResult(title, saved, folder);
}

/// The `attachment` argument: a number from 1, or a file name.
Object _attachmentArgument(Map<String, Object?> arguments) {
  final value = arguments['attachment'];
  if (value is String) {
    final name = value.trim();
    if (name.isEmpty) {
      throw const ToolError(
        'attachment is empty: pass its number as read_message lists it (1 '
        'for the first), or its file name.',
      );
    }
    return name;
  }
  return requiredIntArgument(arguments, 'attachment');
}

/// The attachment [which] names, with its number.
(int, MessageAttachment) _pick(
  List<MessageAttachment> attachments,
  Object which,
  int id,
  MessageBox box,
) {
  final numbered = attachments.indexed.map((e) => (e.$1 + 1, e.$2)).toList();
  String list([Iterable<(int, MessageAttachment)>? only]) => [
    for (final (number, attachment) in only ?? numbered)
      '$number. ${attachment.name.trim()}'
          '${attachment.size.trim().isEmpty ? '' : ' (${attachment.size.trim()})'}',
  ].join('\n');
  final count =
      '${attachments.length} attachment${attachments.length == 1 ? '' : 's'}';

  if (which is String) {
    for (final matches in [
      (String name) => name == which,
      (String name) => name.toLowerCase() == which.toLowerCase(),
    ]) {
      final found = [
        for (final entry in numbered)
          if (matches(entry.$2.name.trim())) entry,
      ];
      if (found.length == 1) return found.single;
      if (found.length > 1) {
        throw ToolError(
          'Message $id (${box.label}) has more than one attachment named '
          '"$which": pass its number instead.\n${list(found)}',
        );
      }
    }
    // A number written as text, when no attachment has it as its name.
    if (int.tryParse(which) case final number?) {
      return _pick(attachments, number, id, box);
    }
    throw ToolError(
      'Message $id (${box.label}) has no attachment named "$which". Its '
      '$count:\n${list()}',
    );
  }
  final number = which as int;
  if (number < 1 || number > attachments.length) {
    throw ToolError(
      'Message $id (${box.label}) has $count, so there is no attachment '
      '$number: pass a number from 1 to ${attachments.length}, or the file '
      'name.\n${list()}',
    );
  }
  return numbered[number - 1];
}

String _capitalise(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
