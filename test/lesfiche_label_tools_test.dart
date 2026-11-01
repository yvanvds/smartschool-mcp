/// The labels of lesfiches (#188): `list_lesfiche_labels`,
/// `create_lesfiche_label` and the `labels` of `create_lesfiche` and
/// `edit_lesfiche`, called over MCP on the real server, session and library,
/// against a fake Smartschool whose labels module serves the school's labels
/// and the own ones and makes an own label as live (dartschool#228: `201`
/// with the label, `name.already.used`, a bare `400` for a long text), and
/// whose Lesfiches module stores the labels of `change-labels` and of the
/// create (a bare `500` for a label without its owner or platform, as live).
library;

import 'package:dart_mcp/client.dart';
import 'package:smartschool_mcp/src/session.dart';
import 'package:smartschool_mcp/src/tools/create_lesfiche_label_tool.dart';
import 'package:smartschool_mcp/src/tools/create_lesfiche_tool.dart';
import 'package:smartschool_mcp/src/tools/edit_lesfiche_tool.dart';
import 'package:smartschool_mcp/src/tools/list_lesfiche_labels_tool.dart';
import 'package:smartschool_mcp/src/tools/list_lesfiches_tool.dart';
import 'package:smartschool_mcp/src/tools/read_lesfiche_tool.dart';
import 'package:test/test.dart';

import 'support/fake_smartschool.dart';
import 'support/mcp.dart';

/// A lesson lesfiche with the school label `JAAR 6`.
final _lesfiche = FakeLesfiche(
  id: 'b0000000-0000-4000-8000-000000000051',
  name: 'Recursie',
  labels: ['JAAR 6'],
);

final _labelsPath = '${fakeLesficheDetailPath(_lesfiche)}/change-labels';

/// The school label `JAAR 6` and the own label `Lussen`, as a write sends
/// them (`LessonContentLabel.toWire`).
final _jaar6 = {
  'identifier': fakeSchoolLabelId('JAAR 6'),
  'id': fakeSchoolLabelId('JAAR 6'),
  'type': 'platform',
  'text': 'JAAR 6',
  'color': 'aqua',
  'isVisible': true,
  'platformId': 4069,
};
final _lussen = {
  'identifier': fakeOwnLabelId('Lussen'),
  'id': fakeOwnLabelId('Lussen'),
  'type': 'user',
  'text': 'Lussen',
  'color': 'steel',
  'isVisible': true,
  'userId': fakePlannerMe,
};

void main() {
  late FakeSmartschool server;
  late FakePlanner planner;
  late ServerConnection connection;

  setUp(() async {
    server = FakeSmartschool();
    planner = server.planner..lesfiches.add(_lesfiche);
    final session = SmartschoolSession(
      fakeExtensionSettings(),
      createClient: fakeClientFactory(server, await tempCache()),
    );
    addTearDown(session.close);
    (connection, _) = await connect(
      tools: [
        listLesfichesTool(session),
        readLesficheTool(session),
        listLesficheLabelsTool(session),
        createLesficheTool(session),
        editLesficheTool(session),
        createLesficheLabelTool(session),
      ],
    );
  });

  Future<String> ok(String tool, Map<String, Object?> arguments) async {
    final (result, text) = await callTool(connection, tool, arguments);
    expect(result.isError, isNot(true), reason: text);
    return text;
  }

  Future<String> error(String tool, Map<String, Object?> arguments) async {
    final (result, text) = await callTool(connection, tool, arguments);
    expect(result.isError, isTrue, reason: text);
    return text;
  }

  List<Object?> bodiesOf(String path) => [
    for (final request in planner.requests)
      if (request.method == 'POST' && request.path == path) request.data,
  ];

  int readsOfLabels() => planner.requests
      .where((request) => request.path.startsWith('$fakeLabelsApi/'))
      .length;

  test('the tools are listed: the list read-only, the create of a label a '
      'write Claude Desktop asks approval for, and the lesfiche writes take '
      'labels', () async {
    final tools = {
      for (final tool in (await connection.listTools(ListToolsRequest())).tools)
        tool.name: tool,
    };
    final list = tools['list_lesfiche_labels']!;
    expect(list.toolAnnotations!.readOnlyHint, isTrue);
    expect(list.inputSchema.properties, anyOf(isNull, isEmpty));
    final create = tools['create_lesfiche_label']!;
    expect(create.toolAnnotations!.destructiveHint, isTrue);
    expect(create.toolAnnotations!.idempotentHint, isFalse);
    expect(create.inputSchema.required, ['text']);
    expect(create.inputSchema.properties!.keys, ['text', 'color']);
    expect(
      (create.inputSchema.properties!['color'] as Map)['enum'],
      hasLength(18),
    );
    expect(
      create.description,
      contains(
        'only call this tool after the user has explicitly confirmed '
        'it',
      ),
    );
    for (final name in ['create_lesfiche', 'edit_lesfiche']) {
      expect(
        tools[name]!.inputSchema.properties!.keys,
        contains('labels'),
        reason: name,
      );
    }
    expect(
      tools['edit_lesfiche']!.description,
      contains('The list replaces all the labels'),
    );
  });

  test('list_lesfiche_labels lists the school\'s labels, then the own ones, '
      'with colour and id, and changes nothing', () async {
    final text = await ok('list_lesfiche_labels', {});
    expect(
      text,
      startsWith(
        'The labels a lesfiche can get: 3 school labels and 1 own label.\n'
        '\n'
        'School labels (the school\'s, for the Lesfiches module):\n'
        '- JAAR 6 | colour aqua | id ${fakeSchoolLabelId('JAAR 6')}\n'
        '- TRIMESTER 1 | colour yellow | id '
        '${fakeSchoolLabelId('TRIMESTER 1')}\n'
        '- TRIMESTER 2 | colour yellow | id '
        '${fakeSchoolLabelId('TRIMESTER 2')}\n'
        '\n'
        'Your own labels:\n'
        '- Lussen | colour steel | id ${fakeOwnLabelId('Lussen')}\n'
        '\n'
        'Put labels on a lesfiche with create_lesfiche or edit_lesfiche',
      ),
    );
    expect([
      for (final request in planner.requests) request.path,
    ], containsAll([fakeSchoolLabelsPath, fakeOwnLabelsPath]));
    expect(planner.writes, isEmpty);
  });

  test('list_lesfiche_labels says when the labels module fails', () async {
    planner.failing[fakeOwnLabelsPath] = 500;
    final text = await error('list_lesfiche_labels', {});
    expect(text, contains('gave an answer the server could not use'));
  });

  group('create_lesfiche', () {
    test('makes a lesfiche with a school label and an own label, by their '
        'text in any case, sent as the labels module gives them', () async {
      final text = await ok('create_lesfiche', {
        'name': 'Lussen herhalen',
        'labels': ['jaar 6', 'Lussen', 'JAAR  6'],
      });
      final [body as Map] = bodiesOf(fakeLesficheCreatePath());
      expect(body['labels'], [_jaar6, _lussen]);
      expect(text, contains('\nLabels: JAAR 6, Lussen\n'));
    });

    test('refuses a label that does not exist, before anything is made, '
        'with the labels there are', () async {
      final text = await error('create_lesfiche', {
        'name': 'Lussen herhalen',
        'labels': ['JAAR 6', 'Herhaling'],
      });
      expect(
        text,
        'labels holds "Herhaling", which is not a label a lesfiche can get. '
        'The labels are JAAR 6, TRIMESTER 1, TRIMESTER 2, Lussen. Pass a '
        'label by its whole text as list_lesfiche_labels shows it; an own '
        'label that does not exist yet is made with create_lesfiche_label, '
        'after the user has confirmed it. Nothing was sent.',
      );
      expect(planner.writes, isEmpty);
      expect(planner.lesfiches, [_lesfiche]);
    });

    test('without labels sends none, and reads no labels', () async {
      await ok('create_lesfiche', {'name': 'Zonder labels'});
      final [body as Map] = bodiesOf(fakeLesficheCreatePath());
      expect(body['labels'], isEmpty);
      expect(readsOfLabels(), 0);
    });
  });

  group('edit_lesfiche', () {
    test('adds an own label to the label it has, and gives the lesfiche '
        'back with both', () async {
      final text = await ok('edit_lesfiche', {
        'lesfiche': _lesfiche.id,
        'labels': ['JAAR 6', 'Lussen'],
      });
      expect(bodiesOf(_labelsPath), [
        {
          'newLabels': [_jaar6, _lussen],
        },
      ]);
      expect(
        text,
        startsWith(
          'Changed the labels of the lesson lesfiche "Recursie".\n'
          '\n'
          'Lesfiche ${_lesfiche.id}\n',
        ),
      );
      expect(text, contains('\nLabels: JAAR 6, Lussen\n'));
      expect(
        await ok('list_lesfiches', {
          'label': ['Lussen'],
        }),
        contains('Recursie'),
      );
    });

    test('clears the labels with an empty list, without reading the '
        'labels', () async {
      final text = await ok('edit_lesfiche', {
        'lesfiche': _lesfiche.id,
        'labels': <String>[],
      });
      expect(bodiesOf(_labelsPath), [
        {'newLabels': <Object?>[]},
      ]);
      expect(text, contains('\nLabels: none\n'));
      expect(readsOfLabels(), 0);
    });

    test('changes nothing more for the labels it has', () async {
      final text = await ok('edit_lesfiche', {
        'lesfiche': _lesfiche.id,
        'labels': ['jaar 6'],
      });
      expect(
        text,
        startsWith(
          'Nothing to change: the lesson lesfiche "Recursie" already had '
          'what was given.',
        ),
      );
    });

    test('keeps a label the lesfiche has that is no longer offered', () async {
      planner.schoolLabels.removeWhere((label) => label.text == 'JAAR 6');
      await ok('edit_lesfiche', {
        'lesfiche': _lesfiche.id,
        'labels': ['JAAR 6', 'TRIMESTER 1'],
      });
      final [body as Map] = bodiesOf(_labelsPath);
      expect(
        [
          for (final label in (body['newLabels'] as List).cast<Map>())
            label['text'],
        ],
        ['JAAR 6', 'TRIMESTER 1'],
      );
    });

    test('a text that a school label and an own label have is refused with '
        'their ids, and the id picks one', () async {
      planner.ownLabels.add(const FakeLabel('JAAR 6', color: 'red'));
      final text = await error('edit_lesfiche', {
        'lesfiche': _lesfiche.id,
        'labels': ['Jaar 6'],
      });
      expect(
        text,
        'labels holds "Jaar 6", which names 2 labels: JAAR 6 (school label, '
        'id ${fakeSchoolLabelId('JAAR 6')}), JAAR 6 (own label, id '
        '${fakeOwnLabelId('JAAR 6')}). Ask the user which one is meant, and '
        'pass its id instead. Nothing was sent.',
      );
      expect(planner.writes, isEmpty);

      await ok('edit_lesfiche', {
        'lesfiche': _lesfiche.id,
        'labels': [fakeOwnLabelId('JAAR 6')],
      });
      final [body as Map] = bodiesOf(_labelsPath);
      expect(body['newLabels'], [containsPair('id', fakeOwnLabelId('JAAR 6'))]);
    });

    test('refuses an unknown label before any edit, also of the other '
        'fields', () async {
      final text = await error('edit_lesfiche', {
        'lesfiche': _lesfiche.id,
        'name': 'Recursie 2',
        'labels': ['Bestaat niet'],
      });
      expect(text, startsWith('labels holds "Bestaat niet", which is not a '));
      expect(planner.writes, isEmpty);
    });

    test('refuses a label that is not a text', () async {
      final text = await error('edit_lesfiche', {
        'lesfiche': _lesfiche.id,
        'labels': ['  '],
      });
      expect(text, contains('each item of labels must be a label'));
      expect(planner.requests, isEmpty);
    });
  });

  group('create_lesfiche_label', () {
    test('makes an own label with its colour, which a lesfiche can then '
        'get', () async {
      final text = await ok('create_lesfiche_label', {
        'text': ' Herhaling ',
        'color': 'aqua',
      });
      expect(bodiesOf(fakeOwnLabelsPath), [
        {'text': 'Herhaling', 'color': 'aqua', 'isVisible': true},
      ]);
      expect(
        text,
        startsWith(
          'Made your own label "Herhaling" (colour aqua), id '
          '${fakeOwnLabelId('Herhaling')}.\n'
          'Put it on a lesfiche with edit_lesfiche',
        ),
      );
      expect(
        await ok('list_lesfiche_labels', {}),
        contains('- Herhaling | colour aqua | id '),
      );
      expect(
        await ok('edit_lesfiche', {
          'lesfiche': _lesfiche.id,
          'labels': ['JAAR 6', 'Herhaling'],
        }),
        contains('\nLabels: JAAR 6, Herhaling\n'),
      );
    });

    test('takes the web client\'s colour steel by default', () async {
      await ok('create_lesfiche_label', {'text': 'Herhaling'});
      expect(bodiesOf(fakeOwnLabelsPath), [
        {'text': 'Herhaling', 'color': 'steel', 'isVisible': true},
      ]);
    });

    test('says in plain words that an own label has the text already, and '
        'makes nothing', () async {
      final text = await error('create_lesfiche_label', {'text': 'lussen'});
      expect(
        text,
        startsWith(
          'You already have an own label "lussen" (Smartschool refuses a text '
          'one of your own labels has',
        ),
      );
      expect(text, contains('list_lesfiche_labels shows it'));
      expect(text, endsWith('Nothing was made.'));
      expect(planner.ownLabels, hasLength(1));
    });

    test('refuses a text that is empty or too long, and a colour that is not '
        'one of the web client\'s, before anything is sent', () async {
      expect(
        await error('create_lesfiche_label', {'text': 'x' * 51}),
        'text is 51 characters long, and a label has at most 50: shorten it. '
        'Nothing was sent.',
      );
      expect(
        await error('create_lesfiche_label', {'text': '   '}),
        'text is empty: give the label a text. Nothing was sent.',
      );
      expect(
        await error('create_lesfiche_label', {
          'text': 'Herhaling',
          'color': 'magenta',
        }),
        // The input schema lists the colours, so the server refuses it.
        contains('is not one of the allowed values: aqua, black, blue,'),
      );
      expect(planner.requests, isEmpty);
    });

    test('a label of 50 characters goes out, and the labels module\'s bare '
        '400 is said as a refusal', () async {
      // The fake refuses a text of more than 50 characters; one it refuses
      // for a reason of its own is a bare 400 too.
      planner.failing[fakeOwnLabelsPath] = 400;
      final text = await error('create_lesfiche_label', {'text': 'y' * 50});
      expect(
        text,
        'Smartschool refused the own label "${'y' * 50}" (HTTP 400), without '
        'saying why. A text of more than 50 characters is refused so. '
        'Nothing was made.',
      );
    });

    test('a create whose answer is lost may or may not have been made, and '
        'is not sent again', () async {
      planner.lostAnswers.add(fakeOwnLabelsPath);
      final text = await error('create_lesfiche_label', {'text': 'Herhaling'});
      expect(
        text,
        startsWith(
          'The own label "Herhaling" may or may not have been made: it was '
          'sent, but Smartschool did not confirm it. Do not call '
          'create_lesfiche_label again for it.',
        ),
      );
      expect(bodiesOf(fakeOwnLabelsPath), hasLength(1));
    });
  });
}
