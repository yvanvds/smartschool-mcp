import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import 'server_tool.dart';

// Sending a message, shared by the tools that send one (`reply_to_message`,
// `send_message`): the submit that is never repeated, and how its outcome is
// reported.

/// Submits a message with [send], the library call that sends it
/// ([MessagesService.sendReply] or [MessagesService.sendMessage]), and turns
/// the failures that tell something about the send into what the tools
/// report.
///
/// Runs inside [SmartschoolSession.run], which repeats its action once when
/// Smartschool rejects the session (a [SmartschoolSessionExpiredError]).
/// That cannot send the message twice: the library throws that error only
/// when Smartschool refused the session for a step of the send, the submit
/// included, before handling it, or when the step was not sent because the
/// client logged in again since it loaded the compose form. Either way
/// nothing was sent, and the repeat loads a new compose form.
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
/// before the submit) becomes a [ToolError] with [composeRefused]. Everything
/// else that goes wrong is a login or connection problem, and nothing was
/// sent. [tool] and [what] (like `the reply to message 101`) name the send in
/// the log.
Future<void> submitOnce(
  Future<void> Function() send, {
  required String tool,
  required String what,
  required String summary,
  required String composeRefused,
}) async {
  try {
    await send();
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

/// Who a message went to and its subject, for a tool result: a line per
/// field that has recipients (To always), then the subject.
String sendSummary({
  required List<String> to,
  List<String> cc = const [],
  List<String> bcc = const [],
  required String subject,
}) => [
  'To: ${to.join(', ')}',
  if (cc.isNotEmpty) 'CC: ${cc.join(', ')}',
  if (bcc.isNotEmpty) 'BCC: ${bcc.join(', ')}',
  'Subject: $subject',
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
