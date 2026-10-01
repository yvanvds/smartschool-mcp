import 'package:dart_mcp/server.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';
import '../messages/markdown_to_html.dart';
import '../messages/message_box.dart';
import '../messages/reply_recipients.dart';
import '../session.dart';
import 'arguments.dart';
import 'server_tool.dart';

/// `reply_to_message`: sends a reply to a message, to its sender or to
/// everyone on it.
///
/// Sending cannot be undone, so the tool is marked destructive (for Claude
/// Desktop to ask for approval before every call) and never sends a reply
/// twice by itself: see [_send].
///
/// The reply is a new message with the original subject after one `Re:`:
/// the library cannot send it as a reply linked to the original yet
/// (yvanvds/dartschool#26).
ServerTool replyToMessageTool(SmartschoolSession session) {
  final sends = _OneAtATime();
  return ServerTool(
    definition: Tool(
      name: 'reply_to_message',
      title: 'Reply to a Smartschool message',
      description:
          'Sends a reply to a Smartschool message. Sending cannot be undone. '
          'Before calling this tool, read the message with read_message, '
          'show the user the exact text of the reply and who will receive '
          'it, and only call it after the user has explicitly confirmed '
          'both. Who receives it: a reply to a message in the inbox or the '
          'archive goes to its sender; with reply_all it goes to the sender '
          'and to everyone in To and CC except the user. A reply to a '
          'message in the sent box goes to its To recipients; with reply_all '
          'also to its CC recipients. The subject is the original subject '
          'with one "Re:" in front. Write body as plain text or simple '
          'Markdown: a blank line between paragraphs, lines starting with '
          '"- " or "1. " for lists, **bold**, *italic* and '
          '[text](https://...) links. HTML in body is not interpreted: it '
          'is sent as text. Attachments, and messages that are not replies, '
          'are not supported. The result says to whom the reply was sent. '
          'If the result says the reply may or may not have been sent, do '
          'not call this tool again for it: check the sent box with '
          'list_messages (box sent) and tell the user.',
      inputSchema: Schema.object(
        properties: {
          'message_id': Schema.int(
            description:
                'The id of the message to reply to, from '
                'list_messages.',
            minimum: 1,
          ),
          'body': Schema.string(
            description:
                'The text of the reply, as confirmed by the user: plain text '
                'or simple Markdown.',
            minLength: 1,
          ),
          'reply_all': Schema.bool(
            description:
                'Reply to everyone on the message instead of only the '
                'sender (for a sent message: also to its CC recipients). '
                'Default false.',
          ),
          'box': MessageBox.schema(
            description:
                'The box list_messages showed the message in: inbox '
                '(default), sent or archive.',
          ),
        },
        required: ['message_id', 'body'],
      ),
      annotations: ToolAnnotations(
        title: 'Reply to a Smartschool message',
        readOnlyHint: false,
        destructiveHint: true,
        idempotentHint: false,
        openWorldHint: true,
      ),
    ),
    handler: (request) => _reply(session, sends, request.arguments ?? const {}),
  );
}

Future<CallToolResult> _reply(
  SmartschoolSession session,
  _OneAtATime sends,
  Map<String, Object?> arguments,
) async {
  final id = requiredIntArgument(arguments, 'message_id');
  final box = MessageBox.parse(arguments['box']);
  final replyAll = arguments['reply_all'] as bool? ?? false;
  final body = (arguments['body'] as String? ?? '').trim();
  if (body.isEmpty) {
    throw const ToolError(
      'body is empty: pass the text of the reply. Nothing was sent.',
    );
  }
  final html = markdownToHtml(body);

  try {
    final (:recipients, :subject) = await sends.run(
      () => session.run(
        (client) => _send(client, box, id, replyAll: replyAll, html: html),
      ),
    );
    return CallToolResult(
      content: [
        TextContent(
          text:
              'Sent the reply to message $id.\n'
              '${_summary(recipients, subject)}',
        ),
      ],
    );
  } on _NotConfirmed catch (error) {
    return CallToolResult(
      isError: true,
      content: [
        TextContent(
          text:
              'The reply to message $id may or may not have been sent: '
              'sending started, but Smartschool did not confirm it. Do not '
              'send it again: first check the sent box (list_messages with '
              'box sent), or ask the user to check it in Smartschool.\n'
              '${_summary(error.recipients, error.subject)}',
        ),
      ],
    );
  }
}

/// Sends the reply with [client] and returns to whom and with which subject.
///
/// Runs inside [SmartschoolSession.run], which repeats it once when
/// Smartschool rejects the session. That is only safe as long as nothing has
/// been sent: [MessagesService.sendMessage] loads a compose form and
/// registers the recipients on it, which can be repeated, and then submits
/// the form, which sends the message. So once the submit request has gone
/// out, every failure becomes a [_NotConfirmed], which the session does not
/// retry: the message may have reached Smartschool, so the user must check
/// the sent box instead. A submit is only taken as sent when Smartschool
/// answers it with its "sent" page. Since flutter_smartschool 0.3.0,
/// `sendMessage` checks that too and throws a
/// [SmartschoolSendUnconfirmedError] otherwise, which is such a failure
/// after the submit; using that instead of the watch is #17.
///
/// Everything that goes wrong before the submit is a [ToolError] or a
/// login or connection problem, and nothing was sent.
Future<({ReplyRecipients recipients, String subject})> _send(
  SmartschoolClient client,
  MessageBox box,
  int id, {
  required bool replyAll,
  required String html,
}) async {
  final messages = MessagesService(client);
  try {
    final message = await box.message(messages, id);
    if (message == null) {
      throw ToolError(
        'There is no message with id $id in the ${box.name} box. Take the '
        'id from list_messages and pass the box it was listed in. Nothing '
        'was sent.',
      );
    }
    if (!message.canReply) {
      throw ToolError(
        'Smartschool does not allow replies to message $id. Nothing was '
        'sent.',
      );
    }
    final recipients = await loadReplyRecipients(
      client,
      messages,
      box,
      id,
      replyAll: replyAll,
    );
    if (recipients.to.isEmpty) {
      throw ToolError(
        'Smartschool gives no one to send a reply to message $id to'
        '${box == MessageBox.sent ? ' (a reply to a sent message goes to its '
                  'To recipients, and it has none, for example when it only '
                  'went to BCC recipients)' : ''}. '
        'Nothing was sent. The user can reply in Smartschool itself.',
      );
    }
    if (box != MessageBox.sent &&
        !replyAll &&
        (recipients.to.length > 1 || recipients.cc.isNotEmpty)) {
      // Smartschool's reply form names only the sender. Anything else is
      // not a plain reply, so rather not send it.
      throw ToolError(
        "Smartschool's reply form for message $id does not name just the "
        'sender, so the reply was not sent. The user can reply in '
        'Smartschool itself.',
      );
    }
    final subject = MessagesService.ensureReplySubject(message.subject);

    final watch = _SubmitWatch();
    client.dio.interceptors.add(watch);
    try {
      await messages.sendMessage(
        SendMessageParams(
          to: recipients.to,
          cc: recipients.cc,
          subject: subject,
          bodyHtml: html,
        ),
      );
    } catch (error) {
      if (watch.submits > 0) {
        log(
          'reply_to_message: sending the reply to message $id failed after '
          'the submit went out, not retrying: ${_oneLine(error)}',
        );
        throw _NotConfirmed(recipients, subject);
      }
      if (error is SmartschoolComposeError) {
        // The form did not open, or Smartschool did not take a recipient on
        // it; either way the library stopped before the submit.
        log('reply_to_message: compose form refused: ${_oneLine(error)}');
        throw const ToolError(
          'Smartschool did not open its form for a new message, or did not '
          'accept a recipient on it, so nothing was sent. The account may '
          'not be allowed to send messages, or to send to one of the '
          'recipients; the details are in the server log.',
        );
      }
      rethrow;
    } finally {
      client.dio.interceptors.remove(watch);
    }
    if (watch.submits != 1 || !watch.confirmed) {
      log(
        'reply_to_message: Smartschool did not confirm the reply to message '
        '$id (submits: ${watch.submits}, answer: ${watch.answer})',
      );
      throw _NotConfirmed(recipients, subject);
    }
    return (recipients: recipients, subject: subject);
  } finally {
    await messages.dispose();
  }
}

/// [error] on one line, for the log: a [DioException] shows the error it
/// wraps rather than its own multi-line description.
String _oneLine(Object error) => switch (error) {
  DioException(error: final Object inner) => '$inner',
  DioException(:final type, :final message) => 'DioException [$type]: $message',
  _ => '$error',
}.replaceAll(RegExp(r'\s+'), ' ');

String _summary(ReplyRecipients recipients, String subject) => [
  'To: ${recipients.toNames}',
  if (recipients.cc.isNotEmpty) 'CC: ${recipients.ccNames}',
  'Subject: $subject',
].join('\n');

/// The reply's submit went out, but Smartschool did not confirm that it
/// sent the message: it may or may not have been sent.
final class _NotConfirmed implements Exception {
  const _NotConfirmed(this.recipients, this.subject);

  final ReplyRecipients recipients;
  final String subject;
}

/// Watches the requests of one [MessagesService.sendMessage] call: whether
/// its submit (the POST of the compose form) went out, and whether
/// Smartschool answered it with the page it shows after sending.
///
/// Added last to the client's interceptors, so a request it sees goes to
/// Smartschool next. It cannot tell two sends apart, so sends run one at a
/// time ([_OneAtATime]).
final class _SubmitWatch extends Interceptor {
  /// How many submits went out.
  int submits = 0;

  /// Whether Smartschool answered the last submit with its "sent" page.
  bool confirmed = false;

  /// The status of the answer to the last submit, for the log.
  String answer = 'none';

  /// What the page Smartschool answers a sent message with does: it closes
  /// the compose window (seen live, and in the library's fixture
  /// `post/composemessage/on_send.html`).
  static const _sentPage = 'window.close()';

  static bool _isSubmit(RequestOptions options) =>
      options.method == 'POST' &&
      options.uri.queryParameters['module'] == 'Messages' &&
      options.uri.queryParameters['file'] == 'composeMessage';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_isSubmit(options)) submits++;
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (_isSubmit(response.requestOptions)) {
      final page = '${response.data}';
      confirmed = response.statusCode == 200 && page.contains(_sentPage);
      answer =
          'HTTP ${response.statusCode}, '
          '${confirmed ? 'the sent page' : 'not the sent page'}';
    }
    handler.next(response);
  }
}

/// Runs actions one after the other.
final class _OneAtATime {
  Future<void> _last = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final result = _last.then((_) => action());
    _last = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}
