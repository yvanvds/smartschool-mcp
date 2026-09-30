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
}

/// The Messages module of a fake Smartschool: the XML dispatcher
/// (`message list`, `show message`, `attachment list`), the archive endpoint
/// and the module page the archive's box id is read from.
///
/// Responses have the shape of the dartschool fixtures under
/// `test/fixtures/smartschool/requests/post/postboxes/` and
/// `.../post/messages/xhr/archivemessages.json`, and the behaviour seen
/// live: a box returns its newest [pageSize] messages only, an unknown
/// message id gets a placeholder message instead of nothing, and the archive
/// endpoint lists only the ids it moved from the inbox as successful (for a
/// message already in the archive it answers `{"success":[]}`).
class FakeMailbox {
  static const pageSize = 50;

  /// The archive endpoint, a form POST outside the XML dispatcher.
  static const archivePath = '/Messages/Xhr/archivemessages';

  final List<FakeMessage> inbox = [];
  final List<FakeMessage> sent = [];
  final List<FakeMessage> archive = [];

  /// The archive folder's box id, shown on the Messages module page.
  int archiveBoxId = 305;

  /// Inbox messages the archive endpoint leaves where they are, leaving
  /// them out of its `success` list.
  final Set<int> refuseToArchive = {};

  /// Every dispatcher call, as `action param=value ...` (params sorted), and
  /// every archive request, as `archive msgIDs=1,2`.
  final List<String> actions = [];

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
    final m = _find(id, boxType);
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
  <canReply>1</canReply>
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
