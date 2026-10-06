import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../intradesk/intradesk_format.dart';
import '../log.dart';
import '../uploads/local_files.dart';
import 'server_tool.dart';

// Sending a message, shared by the tools that send one (`reply_to_message`,
// `send_message`): the files a message takes along ([messageAttachmentsSchema],
// [messageAttachmentsArgument]), the submit that is never repeated, and how
// its outcome is reported.

/// What the description of a tool that sends a message says about its
/// `attachments` argument ([messageAttachmentsArgument]), for files of at
/// most [maxBytes].
String messageAttachmentsDescription(int maxBytes) =>
    'To attach files, pass the full paths of up to $maxLocalFiles files on '
    'this PC in attachments, like C:\\Users\\jan\\Documents\\brief.docx: '
    'files you made for the user (for example in a Cowork project folder) '
    'or that the user names. The server reads any file the user\'s Windows '
    'account can read, up to ${formatFileSize(maxBytes)} each. Each file '
    'goes along under its own name, and no two may have the same name.';

/// The input schema of the `attachments` argument of a tool that sends a
/// message ([messageAttachmentsArgument]).
Schema messageAttachmentsSchema() => Schema.list(
  description:
      'Files from this PC to send along, as confirmed by the user: the full '
      'path of each, like C:\\Users\\jan\\Documents\\brief.docx. Each goes '
      'along under its own name. Optional.',
  items: Schema.string(minLength: 1),
  maxItems: maxLocalFiles,
);

/// [value], the `attachments` argument of a tool that sends a message: the
/// files on this PC that go along with it, in the order given; empty when it
/// is absent or an empty list.
///
/// The paths are checked with [localFilesArgument]: 1 to [maxLocalFiles]
/// absolute paths of existing files of at most [maxBytes], each with a name
/// Smartschool takes, and no two with the same name, ignoring case. Throws a
/// [ToolError] that names the path and says what is wrong, before anything
/// is sent.
List<LocalFile> messageAttachmentsArgument(
  Object? value, {
  int maxBytes = maxLocalFileBytes,
}) {
  if (value == null || (value is List && value.isEmpty)) return const [];
  return localFilesArgument(value, argument: 'attachments', maxBytes: maxBytes);
}

/// Submits a message with [send], the library call that sends it
/// ([MessagesService.sendReply] or [MessagesService.sendMessage]) with the
/// files [attachments], and turns the failures that tell something about the
/// send into what the tools report.
///
/// Runs inside [SmartschoolSession.run], which repeats its action once when
/// Smartschool rejects the session (a [SmartschoolSessionExpiredError]).
/// That cannot send the message twice: the library throws that error only
/// when Smartschool refused the session for a step of the send, the submit
/// included, before handling it, or when the step was not sent because the
/// client logged in again since it loaded the compose form. Either way
/// nothing was sent, and the repeat loads a new compose form.
///
/// The attachments are such steps: the library uploads them, before the
/// submit, into the upload directory of the compose form (its `randomDir`),
/// which belongs to the session the form was loaded in, so it uploads them
/// in that session only (`retryAfterLogin: false`, `sameSessionAs: form`;
/// yvanvds/dartschool#25, #38). An upload that Smartschool refuses the
/// session for is not sent again in a new session: the repeat loads a new
/// compose form, logging in first (a read, which the library retries after
/// logging in, so yvanvds/dartschool#134 does not apply), and uploads the
/// files again into its directory. The message goes with the files of the
/// form it is submitted with only.
///
/// Once the submit (the request that sends the message) has gone out, the
/// library only returns normally when Smartschool answers it with its "sent"
/// page. Any other outcome is a [SmartschoolSendUnconfirmedError]: the
/// message may have reached Smartschool, so it becomes a [SendNotConfirmed]
/// carrying [summary], which the session does not repeat, and the user must
/// check the sent box.
///
/// A [SmartschoolComposeError] (the compose form did not open, or
/// Smartschool did not take a recipient on or off it; the library stopped
/// before the submit) becomes a [ToolError] with [composeRefused]. A
/// [SmartschoolAttachmentUploadError] (Smartschool's upload step did not
/// take one of [attachments], or the file is gone; also before the submit)
/// becomes the [ToolError] of [uploadToolError], with Smartschool's reason
/// when it gave one. Everything else that goes wrong is a login or
/// connection problem, and nothing was sent. [tool] and [what] (like `the
/// reply to message 101`) name the send in the log.
Future<void> submitOnce(
  Future<void> Function() send, {
  required String tool,
  required String what,
  required String summary,
  required String composeRefused,
  Iterable<LocalFile> attachments = const [],
}) async {
  try {
    await send();
  } on SmartschoolAttachmentUploadError catch (error) {
    throw uploadToolError(error, files: attachments, nothingDone: nothingSent)!;
  } on SmartschoolSendUnconfirmedError catch (error) {
    log(
      '$tool: Smartschool did not confirm $what, not retrying: '
      '${_oneLine(error)}',
    );
    throw SendNotConfirmed(summary);
  } on SmartschoolComposeError catch (error) {
    log('$tool: compose form refused: ${_oneLine(error)}');
    throw ToolError(composeRefused);
  }
}

/// The result of a send that Smartschool did not confirm ([SendNotConfirmed]):
/// [what] (like `The reply to message 101`) may or may not have been sent.
CallToolResult notConfirmedResult(String what, SendNotConfirmed error) =>
    CallToolResult(
      isError: true,
      content: [
        TextContent(
          text:
              '$what may or may not have been sent: sending started, but '
              'Smartschool did not confirm it. Do not send it again: first '
              'check the sent box (list_messages with box sent), or ask the '
              'user to check it in Smartschool.\n'
              '${error.summary}',
        ),
      ],
    );

/// Who a message went to, its subject and its attachments, for a tool
/// result: a line per field that has recipients (To always), the subject,
/// and, when it has any, a line with the [attachments], each with its name
/// and size ([describeLocalFiles]).
String sendSummary({
  required List<String> to,
  List<String> cc = const [],
  List<String> bcc = const [],
  required String subject,
  Iterable<LocalFile> attachments = const [],
}) => [
  'To: ${to.join(', ')}',
  if (cc.isNotEmpty) 'CC: ${cc.join(', ')}',
  if (bcc.isNotEmpty) 'BCC: ${bcc.join(', ')}',
  'Subject: $subject',
  if (attachments.isNotEmpty) 'Attachments: ${describeLocalFiles(attachments)}',
].join('\n');

/// The submit of a message went out, but Smartschool did not confirm that it
/// sent the message: it may or may not have been sent. [summary] says to
/// whom ([sendSummary]).
final class SendNotConfirmed implements Exception {
  const SendNotConfirmed(this.summary);

  final String summary;
}

/// [error] on one line, for the log.
String _oneLine(Object error) => '$error'.replaceAll(RegExp(r'\s+'), ' ');
