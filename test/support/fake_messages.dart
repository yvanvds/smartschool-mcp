import 'package:dio/dio.dart';

/// An attachment of a [FakeMessage].
class FakeAttachment {
  const FakeAttachment(this.name, this.size);

  final String name;

  /// As Smartschool formats it, like `123.48 KiB`.
  final String size;
}

/// A message in a [FakeMailbox].
class FakeMessage {
  FakeMessage({
    required this.id,
    required this.sender,
    required this.subject,
    required this.date,
    this.listedAs,
    this.body = '',
    this.unread = false,
    this.flag = 0,
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.attachments = const [],
    this.canReply = true,
  });

  final int id;
  final String sender;

  /// What the box's list shows as the sender, when that is not [sender]:
  /// for a sent message Smartschool lists the recipients there.
  final String? listedAs;
  final String subject;

  /// Like Smartschool's `2024-03-15 14:30`.
  final String date;

  /// HTML.
  final String body;
  bool unread;
  final int flag;
  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final List<FakeAttachment> attachments;

  /// Whether Smartschool allows replies to the message (`canReply`).
  final bool canReply;
}

/// How the fake answers a submit of the compose form (sending a message).
enum SubmitAnswer {
  /// Sends the message and answers with the page that closes the compose
  /// window, like the live platform.
  sent,

  /// Sends the message, but the connection fails before the answer arrives.
  responseLost,

  /// Does not send it and answers with an error page (`var error`).
  errorPage,

  /// Does not send it and answers with some other page.
  otherPage,
}

/// The Messages module of a fake Smartschool: the XML dispatcher
/// (`message list`, `show message`, `attachment list`), the archive endpoint,
/// the module page the archive's box id is read from, and sending: the
/// compose forms, adding recipients to a form and submitting it.
///
/// Responses have the shape of the dartschool fixtures under
/// `test/fixtures/smartschool/requests/post/postboxes/`,
/// `.../post/messages/xhr/archivemessages.json` and
/// `.../{get,post}/composemessage/`, and the behaviour seen live: a box
/// returns its newest [pageSize] messages only, an unknown message id gets a
/// placeholder message instead of nothing, and the archive endpoint lists
/// only the ids it moved from the inbox as successful (for a message already
/// in the archive it answers `{"success":[]}`).
///
/// The reply forms are filled in as seen live: the reply form
/// (`composeType=1`) names the sender (for a sent message, that is the
/// [owner]); the reply-all form (`composeType=2`) of a received message
/// names the To recipients except the [owner] and then the sender in To, and
/// the CC recipients except the [owner] in CC; that of a sent message names
/// its To recipients and then the [owner] in To, and its CC recipients in CC.
/// A message sent to the [owner] also lands in the inbox, with the same id.
class FakeMailbox {
  FakeMailbox({this.owner = 'Jan Peeters'});

  static const pageSize = 50;

  /// The archive endpoint, a form POST outside the XML dispatcher.
  static const archivePath = '/Messages/Xhr/archivemessages';

  /// The platform id (`ssID`) of every fake user.
  static const platformId = 4069;

  /// The user id of the [owner].
  static const ownerId = 146;

  /// The logged-in user's name.
  final String owner;

  final List<FakeMessage> inbox = [];
  final List<FakeMessage> sent = [];
  final List<FakeMessage> archive = [];

  /// The archive folder's box id, shown on the Messages module page.
  int archiveBoxId = 305;

  /// Inbox messages the archive endpoint leaves where they are, leaving
  /// them out of its `success` list.
  final Set<int> refuseToArchive = {};

  /// Messages the box lists but `show message` no longer finds (it answers
  /// with the placeholder), like a message deleted between the two
  /// requests.
  final Set<int> vanished = {};

  /// Every dispatcher call, as `action param=value ...` (params sorted),
  /// every archive request, as `archive msgIDs=1,2`, and every message sent,
  /// as `send to=A,B cc=C subject=S`.
  final List<String> actions = [];

  /// The names the reply form of a received message shows in To instead
  /// of its sender, by message id.
  final Map<int, List<String>> replyFormNames = {};

  /// How the next submits of the compose form are answered.
  SubmitAnswer submitAnswer = SubmitAnswer.sent;

  /// How many submits of the compose form reached the server, sent or not
  /// (counted by the fake server, also without a valid session).
  int submits = 0;

  /// The HTML bodies of the messages sent, in order.
  final List<String> sentBodies = [];

  /// The recipients added to each open compose form, by its `uniqueUsc`.
  final Map<String, ({List<int> to, List<int> cc})> _forms = {};
  int _formsOpened = 0;
  int _messagesSent = 0;

  /// User ids by name, given out on first use.
  late final Map<String, int> _userIds = {owner: ownerId};

  /// The user id of [name].
  int userId(String name) =>
      _userIds.putIfAbsent(name, () => 200 + _userIds.length);

  String _userName(int id) =>
      _userIds.entries.firstWhere((entry) => entry.value == id).key;

  /// Whether [options] submits a compose form, which sends a message.
  static bool isSubmit(RequestOptions options) =>
      options.method == 'POST' && _isCompose(options);

  static bool _isCompose(RequestOptions options) =>
      options.uri.queryParameters['module'] == 'Messages' &&
      options.uri.queryParameters['file'] == 'composeMessage';

  /// Answers [options] if it is a request for the Messages module.
  ResponseBody? respond(RequestOptions options) {
    if (options.method == 'POST' && options.uri.path == archivePath) {
      return _response(_archive('${options.data}'), Headers.jsonContentType);
    }
    final query = options.uri.queryParameters;
    if (options.uri.path != '/' || query['module'] != 'Messages') return null;
    if (options.method == 'GET' && query['file'] == 'index') {
      return _response(_modulePage(), 'text/html');
    }
    if (options.method == 'GET' && _isCompose(options)) {
      return _response(_composePage(query), 'text/html');
    }
    if (isSubmit(options)) return _submit(options);
    if (options.method == 'POST' &&
        query['file'] == 'searchUsers' &&
        query['function'] == 'addUserToSelected') {
      return _response(
        _addUser((options.data as Map).cast<String, String>()),
        'text/xml',
      );
    }
    if (options.method == 'POST' && query['file'] == 'dispatcher') {
      final data = options.data;
      final command = data is Map ? '${data['command']}' : '$data';
      return _response(_dispatch(command), 'text/xml');
    }
    return null;
  }

  String _dispatch(String command) {
    final action = RegExp(r'<action>(.*?)</action>').firstMatch(command)![1]!;
    final params = {
      for (final match in RegExp(
        r'<param name="([^"]*)"><!\[CDATA\[(.*?)\]\]></param>',
      ).allMatches(command))
        match[1]!: match[2]!,
    };
    actions.add(
      [
        action,
        for (final key in params.keys.toList()..sort()) '$key=${params[key]}',
      ].join(' '),
    );
    final id = int.tryParse(params['msgID'] ?? '');
    return switch (action) {
      'message list' => _list(params['boxType']!, params['boxID'] ?? '0'),
      'show message' => _show(
        id!,
        params['boxType']!,
        limitList: params['limitList'] != 'false',
      ),
      'attachment list' => _attachments(id!, params['boxType']!),
      _ => throw UnsupportedError('fake mailbox: no action "$action"'),
    };
  }

  /// Moves the inbox messages named in [body] (`msgIDs%5B%5D=1&...`) to the
  /// archive and answers with the ids it moved.
  String _archive(String body) {
    final ids = [
      for (final field in body.split('&'))
        if (field.split('=') case [
          final key,
          final value,
        ] when Uri.decodeQueryComponent(key) == 'msgIDs[]')
          int.parse(value),
    ];
    actions.add('archive msgIDs=${ids.join(',')}');
    final moved = <int>[];
    for (final id in ids) {
      if (refuseToArchive.contains(id)) continue;
      final index = inbox.indexWhere((m) => m.id == id);
      if (index < 0) continue;
      archive.add(inbox.removeAt(index));
      moved.add(id);
    }
    return '{"success":[${moved.join(',')}]}';
  }

  List<FakeMessage> _box(String boxType, String boxId) =>
      switch ((boxType, boxId)) {
        ('inbox', '0') => inbox,
        ('inbox', final id) when id == '$archiveBoxId' => archive,
        ('outbox', '0') => sent,
        _ => const [],
      };

  FakeMessage? _find(int id, String boxType) {
    final boxes = boxType == 'outbox' ? [sent] : [inbox, archive];
    for (final box in boxes) {
      for (final message in box) {
        if (message.id == id) return message;
      }
    }
    return null;
  }

  String _list(String boxType, String boxId) {
    final messages = [..._box(boxType, boxId)]
      ..sort((a, b) => b.date.compareTo(a.date));
    final page = messages.take(pageSize);
    return _envelope('message list', '''
<messages>
${page.map(_header).join('\n')}
</messages>''');
  }

  String _header(FakeMessage m) =>
      '''
<message>
  <id>${m.id}</id>
  <from>${_escape(m.listedAs ?? m.sender)}</from>
  <fromImage>https://userpicture20.smartschool.be/User/x</fromImage>
  <subject>${_escape(m.subject)}</subject>
  <date>${m.date}</date>
  <status>${m.unread ? 0 : 1}</status>
  <attachment>${m.attachments.isEmpty ? 0 : 1}</attachment>
  <unread>${m.unread ? 0 : 1}</unread>
  <label>${m.flag}</label>
  <deleted>0</deleted>
  <allowreply>1</allowreply>
  <allowreplyenabled>1</allowreplyenabled>
  <hasreply>0</hasreply>
  <hasForward>0</hasForward>
  <realBox>inbox</realBox>
  <sendDate/>
</message>''';

  String _show(int id, String boxType, {required bool limitList}) {
    final m = vanished.contains(id) ? null : _find(id, boxType);
    if (m == null) {
      // What Smartschool answers for an unknown id (seen live), with a
      // date the library reads as 1970-01-01.
      return _envelope('show message', '''
<message>
  <id>$id</id>
  <from>Niet beschikbaar</from>
  <to/>
  <subject>* Bericht zonder onderwerp *</subject>
  <date>1970-01-01 00:00</date>
  <body></body>
  <status>0</status>
  <attachment>0</attachment>
  <unread>0</unread>
  <label>0</label>
  <receivers/>
  <ccreceivers/>
  <bccreceivers/>
</message>''');
    }
    // Without limitList=false, Smartschool lists two names per field and
    // counts the rest.
    String receivers(String tag, List<String> names) {
      final listed = limitList ? names.take(2) : names;
      return listed.isEmpty
          ? '<$tag/>'
          : '<$tag>${listed.map((n) => '<to>${_escape(n)}</to>').join()}</$tag>';
    }

    int others(List<String> names) =>
        limitList && names.length > 2 ? names.length - 2 : 0;
    return _envelope('show message', '''
<message>
  <id>${m.id}</id>
  <from>${_escape(m.sender)}</from>
  <to/>
  <subject>${_escape(m.subject)}</subject>
  <date>${m.date}</date>
  <body>${_escape(m.body)}</body>
  <status>${m.unread ? 0 : 1}</status>
  <attachment>${m.attachments.length}</attachment>
  <unread>${m.unread ? 0 : 1}</unread>
  <label>${m.flag}</label>
  ${receivers('receivers', m.to)}
  ${receivers('ccreceivers', m.cc)}
  ${receivers('bccreceivers', m.bcc)}
  <senderPicture>initials_JP</senderPicture>
  <markedInLVS/>
  <fromTeam>0</fromTeam>
  <totalNrOtherToReciviers>${others(m.to)}</totalNrOtherToReciviers>
  <totalnrOtherCcReceivers>${others(m.cc)}</totalnrOtherCcReceivers>
  <totalnrOtherBccReceivers>${others(m.bcc)}</totalnrOtherBccReceivers>
  <canReply>${m.canReply ? 1 : 0}</canReply>
  <hasReply>0</hasReply>
  <hasForward>0</hasForward>
  <sendDate/>
</message>''');
  }

  String _attachments(int id, String boxType) {
    final m = _find(id, boxType);
    final attachments = m?.attachments ?? const [];
    return _envelope('show attachments', '''
<attachmentlist>
${[for (final (i, a) in attachments.indexed) '''
<attachment>
  <fileID>${100 + i}</fileID>
  <name>${_escape(a.name)}</name>
  <mime>PDF-bestand</mime>
  <size>${a.size}</size>
  <icon>mime_pdf</icon>
  <wopiAllowed>1</wopiAllowed>
  <order>$i</order>
</attachment>'''].join('\n')}
</attachmentlist>''');
  }

  /// A compose form (`composeType` 0: new message, 1: reply, 2: reply to
  /// all), with a new `uniqueUsc` and the recipients of a reply filled in.
  String _composePage(Map<String, String> query) {
    final usc = 'usc${++_formsOpened}';
    _forms[usc] = (to: [], cc: []);
    final id = int.tryParse(query['msgID'] ?? '');
    final sentBox = query['boxType'] == 'outbox';
    final message = id == null ? null : _find(id, query['boxType']!);
    var to = const <String>[];
    var cc = const <String>[];
    if (message != null) {
      switch ((query['composeType'], sentBox)) {
        case ('1', true):
          to = [owner];
        case ('1', false):
          to = replyFormNames[id] ?? [message.sender];
        case ('2', true):
          to = [...message.to, owner];
          cc = message.cc;
        case ('2', false):
          to = {
            ...message.to.where((name) => name != owner),
            message.sender,
          }.toList();
          cc = [...message.cc.where((name) => name != owner)];
      }
    }
    String spans(List<String> names, String type) => [
      for (final name in names)
        '<div class="receiverSpan" realuserid="${userId(name)}" '
            'ssidatt="$platformId" userltatt="0" typeatt="$type">'
            '<div class="receiverSpanName userm">${_escape(name)}</div>'
            '<div class="receiverSpanDelete" title="Verwijder"></div></div>',
    ].join('\n');
    return '''
<!DOCTYPE html>
<html lang="nl"><head>
<script>
window.tinymceInitConfig = {
  userID\t: '$ownerId',
  userLT\t: '0',
  ssID\t: '$platformId',
  lang\t: 'nl'
};
</script>
</head><body>
<form id="composeForm" method="post">
<input type="hidden" name="randomDir" value="dir$_formsOpened">
<input type="hidden" name="uniqueUsc" value="$usc">
<input type="hidden" name="encryptedSender" value="76542a9717766d29">
<input type="hidden" name="origMsgID" value="${message?.id ?? 0}">
<input type="hidden" name="composeAction" value="${message == null ? 0 : 2}">
<div id="insertSearchFieldContainer_0_0">
${spans(to, '0')}
</div>
<div id="insertSearchFieldContainer_2_0">
${spans(cc, '2')}
</div>
</form>
</body></html>''';
  }

  /// Adds a recipient to the compose form named by `uniqueUsc`.
  String _addUser(Map<String, String> fields) {
    final form = _forms[fields['uniqueUsc']];
    final id = int.parse(fields['id']!);
    if (form == null ||
        fields['typeId'] != 'users' ||
        fields['ssid'] != '$platformId') {
      throw UnsupportedError('fake mailbox: cannot add user $id to $fields');
    }
    (fields['type'] == '2' ? form.cc : form.to).add(id);
    return '''
<users>
<user>
<type>${fields['type']}</type>
<ssID>$platformId</ssID>
<parentNodeId>${fields['parentNodeId']}</parentNodeId>
<userID>U$id</userID>
<name>${_escape(_userName(id))}</name>
<userLT>0</userLT>
<userType>U</userType>
<typeId>users</typeId>
<realUserId>$id</realUserId>
</user>
</users>''';
  }

  /// Sends the message of the submitted compose form (or not, see
  /// [submitAnswer]).
  ResponseBody _submit(RequestOptions options) {
    final fields = {
      for (final MapEntry(:key, :value) in (options.data as FormData).fields)
        key: value,
    };
    final form = _forms.remove(fields['uniqueUsc']);
    if (form == null) {
      throw UnsupportedError('fake mailbox: submit of an unknown form');
    }
    switch (submitAnswer) {
      case SubmitAnswer.errorPage:
        return _response(
          '<html><body><script>var error = "Er is een onbekende fout '
              'opgetreden";</script></body></html>',
          'text/html',
        );
      case SubmitAnswer.otherPage:
        return _response('<html><body>Berichten</body></html>', 'text/html');
      case SubmitAnswer.sent || SubmitAnswer.responseLost:
        break;
    }
    final to = [for (final id in form.to) _userName(id)];
    final cc = [for (final id in form.cc) _userName(id)];
    final subject = fields['subject']!;
    final body = fields['message']!;
    final id = 9000 + ++_messagesSent;
    final date = '2024-04-01 10:${_messagesSent.toString().padLeft(2, '0')}';
    sentBodies.add(body);
    actions.add('send to=${to.join(',')} cc=${cc.join(',')} subject=$subject');
    FakeMessage copy({required bool unread}) => FakeMessage(
      id: id,
      sender: owner,
      listedAs: unread ? null : to.join(', '),
      subject: subject,
      date: date,
      body: body,
      unread: unread,
      to: to,
      cc: cc,
    );
    sent.add(copy(unread: false));
    if (to.contains(owner) || cc.contains(owner)) inbox.add(copy(unread: true));
    if (submitAnswer == SubmitAnswer.responseLost) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Connection reset by peer',
      );
    }
    return _response(
      '<!DOCTYPE html><html lang="nl"><body><div id="smscMain">'
          '<script>\$(document).ready(function() { checkOpenerActions(); '
          'window.close(); });</script></div></body></html>',
      'text/html',
    );
  }

  String _modulePage() =>
      '''
<html><body>
<div class="postbox" boxtype="inbox" boxid="0">Postvak in</div>
<div class="postboxsub" boxtype="inbox" boxid="$archiveBoxId" boxname="Berichten archief" id="div_inbox_$archiveBoxId">
  <div class="postbox_ico_sub archive" boxtype="inbox" boxid="$archiveBoxId" boxname="Berichten archief"></div>
</div>
</body></html>''';

  static String _envelope(String subsystem, String data) =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<server>
  <response>
    <status>ok</status>
    <actions>
      <action>
        <subsystem>$subsystem</subsystem>
        <command>rebuild</command>
        <data>
$data
        </data>
      </action>
    </actions>
  </response>
</server>''';

  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static ResponseBody _response(String body, String contentType) =>
      ResponseBody.fromString(
        body,
        200,
        headers: {
          Headers.contentTypeHeader: [contentType],
        },
      );
}
