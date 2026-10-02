import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'fake_download.dart';

/// An attachment of a [FakeMessage].
class FakeAttachment {
  const FakeAttachment(this.name, this.size, {this.content});

  final String name;

  /// As Smartschool formats it, like `123.48 KiB`.
  final String size;

  /// What a download of it gets; without it, the download is answered with
  /// a 404.
  final Uint8List? content;
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

  /// Smartschool's colour flag: 0 none, 1 green, 2 yellow, 3 red, 4 blue.
  int flag;
  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final List<FakeAttachment> attachments;

  /// Whether Smartschool allows replies to the message (`canReply`).
  final bool canReply;
}

/// [count] messages an hour apart, newest first: ids [firstId] and up, the
/// first dated [newest] (Smartschool time, like `2024-04-30 18:00`), each
/// with the subject `$subject <n>` (n counting from 0) and the body
/// `<p>Bericht <n></p>`.
List<FakeMessage> hourlyMessages(
  int count, {
  required int firstId,
  required String newest,
  String subject = 'Bericht',
}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final start = DateTime.parse('${newest}Z');
  final messages = <FakeMessage>[];
  for (var i = 0; i < count; i++) {
    final date = start.subtract(Duration(hours: i));
    messages.add(
      FakeMessage(
        id: firstId + i,
        sender: 'Collega $i',
        subject: '$subject $i',
        date:
            '${date.year}-${two(date.month)}-${two(date.day)} '
            '${two(date.hour)}:${two(date.minute)}',
        body: '<p>Bericht $i</p>',
      ),
    );
  }
  return messages;
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
/// (`message list`, `show message`, `attachment list`, changing the read
/// state and the flag: `mark message read`, `mark message unread`,
/// `save msglabel`, and moving a message to the trash: `quickmove
/// messages`), attachment downloads, the archive endpoint,
/// the module page the archive's box id is read from, and sending: the
/// compose forms, adding recipients to a form and taking them off, and
/// submitting it.
///
/// Responses have the shape of the dartschool fixtures under
/// `test/fixtures/smartschool/requests/post/postboxes/`,
/// `.../post/messages/xhr/archivemessages.json` and
/// `.../{get,post}/composemessage/`, and the behaviour seen live: a box is
/// listed [pageSize] headers at a time, newest first (a `message list`
/// answers with the first page, each `continue_messages` with the next, see
/// [listElsewhere]), an unknown message id gets a placeholder message instead
/// of nothing, and the archive endpoint lists only the ids it moved from the
/// inbox as successful (for a message already in the archive it answers
/// `{"success":[]}`).
///
/// The reply forms are filled in as seen live: the reply form
/// (`composeType=1`) names the sender (for a sent message, that is the
/// [owner]); the reply-all form (`composeType=2`) of a received message
/// names the To recipients except the [owner] and then the sender in To, and
/// the CC recipients except the [owner] in CC; that of a sent message names
/// its To recipients and then the [owner] in To, its CC recipients in CC and
/// its BCC recipients in BCC. As live, the recipients a reply form names are
/// registered with it already (yvanvds/dartschool#26), and its submit links
/// the message to the one it answers (`origMsgID`, `composeAction` `2`). In
/// the sent box, `show message` starts each recipient name with the
/// recipient's read state (`+`).
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

  /// The messages moved to the trash, in the order they were moved. A
  /// message the [owner] sent to themselves can be in it twice, with the
  /// same id: its inbox copy and its sent-box copy.
  final List<FakeMessage> trash = [];

  /// The archive folder's box id, shown on the Messages module page.
  int archiveBoxId = 305;

  /// Inbox messages the archive endpoint leaves where they are, leaving
  /// them out of its `success` list.
  final Set<int> refuseToArchive = {};

  /// Messages whose read state or flag Smartschool does not change: it
  /// answers `mark message read`, `mark message unread` and `save msglabel`
  /// for them without a message, which the library returns as null. What
  /// Smartschool answers when it changes nothing has not been seen.
  final Set<int> refuseToChange = {};

  /// Messages whose read state or flag Smartschool does not change, but it
  /// answers with their state as it is, as if it had.
  final Set<int> keepUnchanged = {};

  /// Messages the box lists but `show message` no longer finds (it answers
  /// with the placeholder), like a message deleted between the two
  /// requests.
  final Set<int> vanished = {};

  /// Messages a `quickmove messages` to the trash leaves where they are. It
  /// answers as for a message it moved, as the live platform answers every
  /// move (yvanvds/dartschool#60).
  final Set<int> refuseToTrash = {};

  /// Every dispatcher call, as `action param=value ...` (params sorted),
  /// every archive request, as `archive msgIDs=1,2`, and every message sent,
  /// as `send to=A,B cc=C bcc=D subject=S`, or for a reply submitted with
  /// the reply form of message 101, `send reply-to=101 to=...`.
  final List<String> actions = [];

  /// The names the reply form of a received message shows in To instead
  /// of its sender, by message id.
  final Map<int, List<String>> replyFormNames = {};

  /// Recipients Smartschool does not register on a compose form: it answers
  /// adding them with an empty body, as seen live for an unknown user
  /// (yvanvds/dartschool#39).
  final Set<String> unregistered = {};

  /// Recipients Smartschool does not take off a compose form: it answers
  /// taking them off with an empty list, as seen live for an entry the form
  /// does not have (yvanvds/dartschool#42).
  final Set<String> notRemovable = {};

  /// How the next submits of the compose form are answered.
  SubmitAnswer submitAnswer = SubmitAnswer.sent;

  /// How many submits of the compose form reached the server, sent or not
  /// (counted by the fake server, also without a valid session).
  int submits = 0;

  /// The HTML bodies of the messages sent, in order.
  final List<String> sentBodies = [];

  /// The attachments downloaded, in order, as `<message id>/<number>`
  /// (counting from 1).
  final List<String> attachmentDownloads = [];

  /// Whether attachment downloads announce their size (`Content-Length`)
  /// and name (`Content-Disposition`).
  bool announceAttachmentDownloads = true;

  /// The name attachment downloads give in `Content-Disposition`, instead
  /// of the attachment's own.
  String? attachmentDownloadName;

  /// The attachment downloads cancelled before all of the file was sent; a
  /// test waits for them with `attachmentStops.reached`.
  final attachmentStops = StoppedDownloads();

  /// How many attachment downloads were cancelled before all of the file
  /// was sent.
  int get stoppedAttachmentDownloads => attachmentStops.count;

  /// Called with each dispatcher call, as [actions] records it, before it is
  /// answered, so that a test can change the mailbox in between: for
  /// example [listElsewhere] between two pages of a listing.
  void Function(String action)? beforeAnswer;

  /// How many headers of each box were sent since the box was last listed,
  /// by `boxType/boxID`: the box's paging position.
  ///
  /// As seen live (yvanvds/dartschool#15, #76), Smartschool keeps the
  /// paging position per user and box, not in the session: a `message list`
  /// of a box, in any session of the account, restarts it at the second
  /// page, and each `continue_messages` of the box answers with the page
  /// after the position, whichever listing sent it. A new login keeps the
  /// positions: Smartschool goes on with the next page in the new session.
  /// A `continue_messages` of a box that was not listed is answered like
  /// one after the last page (only `rebuildfinish`); what Smartschool
  /// answers then has not been seen.
  final Map<String, int> _paging = {};

  /// The recipients registered on each open compose form, by its
  /// `uniqueUsc`: user ids by field (`typeatt`: `0` To, `2` CC, `3` BCC).
  final Map<String, Map<String, List<int>>> _forms = {};
  int _formsOpened = 0;
  int _messagesSent = 0;

  /// User ids by name, given out on first use.
  late final Map<String, int> _userIds = {owner: ownerId};

  /// The user id of [name].
  int userId(String name) =>
      _userIds.putIfAbsent(name, () => 200 + _userIds.length);

  String _userName(int id) =>
      _userIds.entries.firstWhere((entry) => entry.value == id).key;

  /// Lists the box ([boxType], [boxId]) the way a `message list` in another
  /// session of the account does, such as the user opening the box in the
  /// web client: it restarts the box's paging position (see [_paging]), so
  /// the next `continue_messages` of a listing that got past its second page
  /// answers with the second page again. Not recorded in [actions].
  void listElsewhere({String boxType = 'inbox', String boxId = '0'}) =>
      _list(boxType, boxId);

  /// Whether [options] submits a compose form, which sends a message.
  static bool isSubmit(RequestOptions options) =>
      options.method == 'POST' && _isCompose(options);

  static bool _isCompose(RequestOptions options) =>
      options.uri.queryParameters['module'] == 'Messages' &&
      options.uri.queryParameters['file'] == 'composeMessage';

  /// Answers [options] if it is a request for the Messages module; an
  /// attachment download stops sending once [cancelled] completes (see
  /// [fakeDownload]).
  ResponseBody? respond(RequestOptions options, {Future<void>? cancelled}) {
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
    if (options.method == 'GET' && query['file'] == 'download') {
      return _downloadAttachment(int.parse(query['fileID']!), cancelled);
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
    if (options.method == 'POST' &&
        query['file'] == 'searchUsers' &&
        query['function'] == 'deleteUsersFromSelected') {
      return _response(
        _removeUsers((options.data as Map).cast<String, String>()),
        'application/xml; charset=UTF-8',
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
    beforeAnswer?.call(actions.last);
    final id = int.tryParse(params['msgID'] ?? '');
    return switch (action) {
      'message list' => _list(params['boxType']!, params['boxID'] ?? '0'),
      'continue_messages' => _continue(params['boxType']!, params['boxID']!),
      'show message' => _show(
        id!,
        params['boxType']!,
        limitList: params['limitList'] != 'false',
      ),
      'attachment list' => _attachments(id!, params['boxType']!),
      'mark message read' => _change(
        'status',
        _find(id!, params['boxType']!),
        (m) => m.unread = false,
        (m) => m.unread ? 0 : 1,
      ),
      'mark message unread' => _change(
        'status',
        _box(
          params['boxType']!,
          params['boxID']!,
        ).where((m) => m.id == id).firstOrNull,
        (m) => m.unread = true,
        (m) => m.unread ? 0 : 1,
      ),
      'save msglabel' => _change(
        'label',
        _find(id!, params['boxType']!),
        (m) => m.flag = int.parse(params['msgLabel']!),
        (m) => m.flag,
      ),
      'quickmove messages' => _moveToTrash(id!, params),
      _ => throw UnsupportedError('fake mailbox: no action "$action"'),
    };
  }

  /// Moves message [id] out of the box that [params] name (`boxType` and
  /// `boxID`: the archive's folder, for a message in the archive) to the
  /// trash, as `quickmove messages` with `toBoxType` `trash` and `toBoxID`
  /// `0` does, and leaves a copy in another box where it is: the sent-box
  /// copy of a message the [owner] sent to themselves, for a move out of the
  /// inbox (yvanvds/dartschool#60).
  ///
  /// Answers like the live platform, with a `silent` action whether it moved
  /// a message or not (the dartschool fixture `quickmove messages.xml`); see
  /// [refuseToTrash]. A moved message is no longer found by `show message`
  /// with the box type it was moved out of: what Smartschool answers then
  /// has not been seen (yvanvds/dartschool#96), so the fake answers with the
  /// placeholder, as for a message in another box (yvanvds/dartschool#16).
  String _moveToTrash(int id, Map<String, String> params) {
    if (params['toBoxType'] != 'trash' || params['toBoxID'] != '0') {
      throw UnsupportedError('fake mailbox: quickmove other than to the trash');
    }
    final box = _box(params['boxType']!, params['boxID']!);
    final index = box.indexWhere((m) => m.id == id);
    if (index >= 0 && !refuseToTrash.contains(id)) {
      trash.add(box.removeAt(index));
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<server><response><status>ok</status><actions><action>'
        '<subsystem>message list</subsystem><command>silent</command>'
        '<data><message /></data></action></actions></response></server>';
  }

  /// Changes the read state or the flag of [message] with [apply] and
  /// answers with its new [command] (`status` or `label`), [value], like
  /// the live answers; see [refuseToChange] and [keepUnchanged].
  ///
  /// `mark message unread` names the message's box (`boxID`, the folder of
  /// the archive), so it finds only a message in that box. `mark message
  /// read` and `save msglabel` name only the box type: they find a message
  /// in the archive too, by its id. Whether Smartschool does that has not
  /// been seen (yvanvds/dartschool#94).
  String _change(
    String command,
    FakeMessage? message,
    void Function(FakeMessage message) apply,
    int Function(FakeMessage message) value,
  ) {
    var answer = '';
    if (message != null && !refuseToChange.contains(message.id)) {
      if (!keepUnchanged.contains(message.id)) apply(message);
      answer =
          '<message><id>${message.id}</id>'
          '<$command>${value(message)}</$command></message>';
    }
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<server>
  <response>
    <status>ok</status>
    <actions>
      <action>
        <subsystem>message list</subsystem>
        <command>$command</command>
        <data>$answer</data>
      </action>
    </actions>
  </response>
</server>''';
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

  /// The messages of a box, newest first (the highest id first among
  /// messages of the same minute, so that pages do not overlap).
  List<FakeMessage> _sorted(String boxType, String boxId) =>
      [..._box(boxType, boxId)]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });

  String _list(String boxType, String boxId) {
    final messages = _sorted(boxType, boxId);
    final page = messages.take(pageSize).toList();
    _paging['$boxType/$boxId'] = page.length;
    return _listing(
      'rebuild',
      page,
      more: messages.length > page.length,
      boxType: boxType,
      boxId: boxId,
    );
  }

  String _continue(String boxType, String boxId) {
    final messages = _sorted(boxType, boxId);
    final from = _paging['$boxType/$boxId'] ?? messages.length;
    final page = messages.skip(from).take(pageSize).toList();
    _paging['$boxType/$boxId'] = from + page.length;
    return _listing(
      page.isEmpty ? null : 'rebuildcontinue',
      page,
      more: from + page.length < messages.length,
      boxType: boxType,
      boxId: boxId,
    );
  }

  /// A page of a box listing, shaped like the live answers: the headers of
  /// [page] in a [command] action (`rebuild` for a `message list`,
  /// `rebuildcontinue` for a `continue_messages`, none after the last page),
  /// then a `continue_messages` action when the box holds [more] headers, or
  /// a `rebuildfinish` action when not.
  String _listing(
    String? command,
    List<FakeMessage> page, {
    required bool more,
    required String boxType,
    required String boxId,
  }) {
    final headers = command == null
        ? ''
        : '''
      <action>
        <subsystem>message list</subsystem>
        <command>$command</command>
        <data>
<messages>
${page.map(_header).join('\n')}
</messages>
        </data>
      </action>''';
    final end = more
        ? '<action><subsystem>message list</subsystem>'
              '<command>continue_messages</command><data><details>'
              '<boxID>$boxId</boxID><boxType>$boxType</boxType></details>'
              '</data></action>'
        : '<action><subsystem>message list</subsystem>'
              '<command>rebuildfinish</command><data><message/></data>'
              '</action>';
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<server>
  <response>
    <status>ok</status>
    <actions>
$headers
      $end
    </actions>
  </response>
</server>''';
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
      // What Smartschool answers for an id the box does not hold (seen
      // live, yvanvds/dartschool#16): a placeholder with an empty status and
      // no date, which the library returns as null.
      return _envelope('show message', '''
<message>
  <id>$id</id>
  <from>Niet beschikbaar</from>
  <to/>
  <subject>* Bericht zonder onderwerp *</subject>
  <date>wrong input format</date>
  <body></body>
  <status/>
  <attachment>0</attachment>
  <unread/>
  <label/>
  <receivers/>
  <ccreceivers/>
  <bccreceivers/>
  <canReply/>
</message>''');
    }
    // Without limitList=false, Smartschool lists two names per field and
    // counts the rest. In the sent box, each name starts with the
    // recipient's read state, `+` (read) or `-` (unread), seen live
    // (yvanvds/dartschool#34); here every recipient has read it.
    final marker = boxType == 'outbox' ? '+' : '';
    String receivers(String tag, List<String> names) {
      final listed = limitList ? names.take(2) : names;
      return listed.isEmpty
          ? '<$tag/>'
          : '<$tag>${listed.map((n) => '<to>$marker${_escape(n)}</to>').join()}</$tag>';
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
  <fileID>${_fileId(m!, i)}</fileID>
  <name>${_escape(a.name)}</name>
  <mime>PDF-bestand</mime>
  <size>${a.size}</size>
  <icon>mime_pdf</icon>
  <wopiAllowed>1</wopiAllowed>
  <order>$i</order>
</attachment>'''].join('\n')}
</attachmentlist>''');
  }

  /// The `fileID` of attachment [index] of [message]: unique in the mailbox.
  static int _fileId(FakeMessage message, int index) =>
      message.id * 100 + index + 1;

  /// The download of the attachment with [fileId]; a 404 for one without
  /// content (what Smartschool answers then has not been seen).
  ResponseBody _downloadAttachment(int fileId, Future<void>? cancelled) {
    for (final message in [...inbox, ...archive, ...sent]) {
      for (final (index, attachment) in message.attachments.indexed) {
        if (_fileId(message, index) != fileId) continue;
        attachmentDownloads.add('${message.id}/${index + 1}');
        final content = attachment.content;
        if (content == null) break;
        return fakeDownload(
          content,
          name: attachmentDownloadName ?? attachment.name,
          announce: announceAttachmentDownloads,
          stopped: attachmentStops.add,
          cancelled: cancelled,
        );
      }
    }
    return ResponseBody.fromString('Not found', 404);
  }

  /// A compose form (`composeType` 0: new message, 1: reply, 2: reply to
  /// all), with a new `uniqueUsc` and the recipients of a reply filled in
  /// and registered with it.
  String _composePage(Map<String, String> query) {
    final usc = 'usc${++_formsOpened}';
    final id = int.tryParse(query['msgID'] ?? '');
    final sentBox = query['boxType'] == 'outbox';
    final message = id == null ? null : _find(id, query['boxType']!);
    var to = const <String>[];
    var cc = const <String>[];
    var bcc = const <String>[];
    if (message != null) {
      switch ((query['composeType'], sentBox)) {
        case ('1', true):
          to = [owner];
        case ('1', false):
          to = replyFormNames[id] ?? [message.sender];
        case ('2', true):
          to = [...message.to, owner];
          cc = message.cc;
          bcc = message.bcc;
        case ('2', false):
          to = {
            ...message.to.where((name) => name != owner),
            message.sender,
          }.toList();
          cc = [...message.cc.where((name) => name != owner)];
      }
    }
    _forms[usc] = {
      '0': [for (final name in to) userId(name)],
      '2': [for (final name in cc) userId(name)],
      '3': [for (final name in bcc) userId(name)],
    };
    String spans(List<String> names, String type) => [
      for (final name in names)
        '<div class="receiverSpan" idatt="U${userId(name)}" '
            'realuserid="${userId(name)}" ssidatt="$platformId" '
            'userltatt="0" typeatt="$type">'
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
<div id="insertSearchFieldContainer_3_0">
${spans(bcc, '3')}
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
    final field = form[fields['type']]!;
    // Smartschool answers a second registration in the same field with an
    // empty body too (yvanvds/dartschool#39).
    if (unregistered.contains(_userName(id)) || field.contains(id)) return '';
    field.add(id);
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

  /// Takes the entries named in the field `xml` off the compose form named by
  /// `uniqueUsc`, answering like the live platform: a list of the entries it
  /// took off, empty for one the form does not have (or one in
  /// [notRemovable]).
  String _removeUsers(Map<String, String> fields) {
    final form = _forms[fields['uniqueUsc']];
    if (form == null) {
      throw UnsupportedError('fake mailbox: cannot take users off $fields');
    }
    final removed = <String>[];
    for (final user in RegExp(
      r'<user><type>(\d+)</type><userid>U(\d+)</userid>'
      r'<ssid>(\d+)</ssid><userlt>(\d+)</userlt></user>',
    ).allMatches(fields['xml']!)) {
      final type = user[1]!;
      final id = int.parse(user[2]!);
      if (user[3] != '$platformId' ||
          notRemovable.contains(_userName(id)) ||
          !(form[type]?.remove(id) ?? false)) {
        continue;
      }
      removed.add(
        '<user><type>$type</type><ssID>${user[3]}</ssID>'
        '<userID>U$id</userID><userLT>${user[4]}</userLT></user>',
      );
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '${removed.isEmpty ? '<users />' : '<users>${removed.join()}</users>'}';
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
    List<String> names(String field) => [
      for (final id in form[field]!) _userName(id),
    ];
    final to = names('0');
    final cc = names('2');
    final bcc = names('3');
    final subject = fields['subject']!;
    final body = fields['message']!;
    final id = 9000 + ++_messagesSent;
    final date = '2024-04-01 10:${_messagesSent.toString().padLeft(2, '0')}';
    // A reply form carries the id of the message it answers.
    final answers = fields['origMsgID'] ?? '0';
    final reply = fields['composeAction'] == '2' && answers != '0'
        ? 'reply-to=$answers '
        : '';
    sentBodies.add(body);
    actions.add(
      'send ${reply}to=${to.join(',')} cc=${cc.join(',')} '
      'bcc=${bcc.join(',')} subject=$subject',
    );
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
      bcc: bcc,
    );
    sent.add(copy(unread: false));
    if ([...to, ...cc, ...bcc].contains(owner)) inbox.add(copy(unread: true));
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
