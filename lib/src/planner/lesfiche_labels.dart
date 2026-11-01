import 'package:dart_mcp/server.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../tools/server_tool.dart';
import '../uploads/local_files.dart';
import 'lesfiches.dart';

// The labels of lesfiches (#188, dartschool#228): the labels a lesfiche can
// get (`LessonContentService.getLabels`: the school's for the Lesfiches
// module, then the user's own), as `list_lesfiche_labels` lists them; the
// `labels` argument of `create_lesfiche` and `edit_lesfiche`, by the text
// of each label (or its id), matched with those labels before anything is
// sent; and the text and colour of a new own label (`create_lesfiche_label`,
// `LessonContentService.createUserLabel`). The library does not change or
// remove a label itself.

/// What the description of a tool that sets the labels of a lesfiche says
/// about the list.
const lesficheLabelsReplaceNote =
    'The list replaces all the labels: to add a label, pass the labels it '
    'has now (as read_lesfiche shows them) plus the new one; to remove one, '
    'pass the others; an empty list removes them all.';

/// The input schema of a `labels` argument ([lesficheLabelsArgument]), with
/// [description] in front of how a label is named.
Schema lesficheLabelsSchema({required String description}) => Schema.list(
  description:
      '$description Each label by its whole text as list_lesfiche_labels '
      'shows it (like JAAR 6), case-insensitive; by its id when a school '
      'label and an own label have the same text.',
  items: Schema.string(minLength: 1),
);

/// [value], the `labels` argument [name] of a tool: labels by their text or
/// id, without the white space around them and without duplicates (as
/// [normalLabel] compares them), in the order given; null when it is
/// absent, and empty for an empty list (no labels).
///
/// Throws a [ToolError] for an item that is not a text with something in
/// it, before anything is sent. [lesficheLabels] matches the items with the
/// labels there are.
List<String>? lesficheLabelsArgument(Object? value, {String name = 'labels'}) {
  if (value == null) return null;
  final items = value is List ? value : [value];
  final labels = <String>[];
  for (final item in items) {
    final text = item is String ? item.trim() : '';
    if (text.isEmpty) {
      throw ToolError(
        'each item of $name must be a label by its text as '
        'list_lesfiche_labels shows it (like JAAR 6); '
        '${item is String ? '"$item"' : '$item'} is not. $nothingSent',
      );
    }
    if (!labels.any((known) => normalLabel(known) == normalLabel(text))) {
      labels.add(text);
    }
  }
  return labels;
}

/// The labels of [available] (`LessonContentService.getLabels`) that
/// [wanted] ([lesficheLabelsArgument], the argument [name]) names, in that
/// order and each once: by its id (ignoring case), else by its text (as
/// [normalLabel] compares them). A label of [stored], the labels the
/// lesfiche has, is found too when [available] does not have it (such as a
/// label that is no longer offered), so that passing the labels it has
/// keeps them.
///
/// Throws a [ToolError] that lists the labels there are when an item names
/// none, and one that gives their ids when a text names more than one (a
/// school label and an own label of the same text), before anything is
/// sent.
List<LessonContentLabel> lesficheLabels(
  List<LessonContentLabel> available,
  List<String> wanted, {
  Iterable<LessonContentLabel> stored = const [],
  String name = 'labels',
}) {
  final known = [
    ...available,
    for (final label in stored)
      if (!available.any((other) => _sameId(other, label))) label,
  ];
  final chosen = <LessonContentLabel>[];
  final unknown = <String>[];
  for (final item in wanted) {
    final byId = [
      for (final label in known)
        if (label.id.toLowerCase() == item.toLowerCase()) label,
    ];
    final matches = byId.isNotEmpty
        ? byId
        : [
            for (final label in known)
              if (normalLabel(label.text) == normalLabel(item)) label,
          ];
    if (matches.isEmpty) {
      unknown.add('"$item"');
    } else if (matches.length > 1) {
      final listed = [
        for (final label in matches)
          '${label.text} (${_kind(label)}, id ${label.id})',
      ];
      throw ToolError(
        '$name holds "$item", which names ${matches.length} labels: '
        '${listed.join(', ')}. Ask the user which one is meant, and pass its '
        'id instead. $nothingSent',
      );
    } else if (!chosen.any((label) => _sameId(label, matches.single))) {
      chosen.add(matches.single);
    }
  }
  if (unknown.isNotEmpty) {
    final texts = {
      for (final label in known)
        if (label.text.trim().isNotEmpty) label.text.trim(),
    };
    throw ToolError(
      '$name holds ${unknown.join(', ')}, which '
      '${unknown.length == 1 ? 'is not a label' : 'are not labels'} a '
      'lesfiche can get. '
      '${texts.isEmpty ? 'There are no labels yet.' : 'The labels are ${texts.join(', ')}.'} '
      'Pass a label by its whole text as list_lesfiche_labels shows it; an '
      'own label that does not exist yet is made with create_lesfiche_label, '
      'after the user has confirmed it. $nothingSent',
    );
  }
  return chosen;
}

/// Whether [a] and [b] are the same labels, by id (ignoring case and order).
bool sameLabels(
  Iterable<LessonContentLabel> a,
  Iterable<LessonContentLabel> b,
) {
  final left = {for (final label in a) label.id.toLowerCase()};
  final right = {for (final label in b) label.id.toLowerCase()};
  return left.length == right.length && left.containsAll(right);
}

bool _sameId(LessonContentLabel a, LessonContentLabel b) =>
    a.id.toLowerCase() == b.id.toLowerCase();

/// `school label`, `own label`, or the module's kind of a label it is
/// neither.
String _kind(LessonContentLabel label) => label.isSchoolLabel
    ? 'school label'
    : label.isUserLabel
    ? 'own label'
    : 'label of the kind "${label.type}"';

/// One line of [label]: `- JAAR 6 | colour aqua | id 4069_...`, with
/// `hidden` when it is not visible.
String formatLesficheLabel(LessonContentLabel label) => [
  '- ${label.text.trim().isEmpty ? '(no text)' : label.text.trim()}',
  'colour ${label.color ?? 'none'}',
  if (!label.isVisible) 'hidden',
  'id ${label.id}',
].join(' | ');

/// The labels a lesfiche can get ([labels], as `getLabels` gives them), as
/// `list_lesfiche_labels` shows them: the school's, then the own ones, each
/// a line ([formatLesficheLabel]), with how they are put on a lesfiche.
String formatLesficheLabels(List<LessonContentLabel> labels) {
  final school = [
    for (final label in labels)
      if (label.isSchoolLabel) label,
  ];
  final own = [
    for (final label in labels)
      if (label.isUserLabel) label,
  ];
  final other = [
    for (final label in labels)
      if (!label.isSchoolLabel && !label.isUserLabel) label,
  ];
  String count(int n, String what) => n == 1 ? '1 $what' : '$n ${what}s';
  return [
    'The labels a lesfiche can get: ${count(school.length, 'school label')} '
        'and ${count(own.length, 'own label')}.',
    '',
    'School labels (the school\'s, for the Lesfiches module):',
    if (school.isEmpty) '- none',
    for (final label in school) formatLesficheLabel(label),
    '',
    'Your own labels:',
    if (own.isEmpty) '- none',
    for (final label in own) formatLesficheLabel(label),
    if (other.isNotEmpty) ...[
      '',
      'Labels of another kind, which a lesfiche cannot get from this server:',
      for (final label in other) formatLesficheLabel(label),
    ],
    '',
    'Put labels on a lesfiche with create_lesfiche or edit_lesfiche '
        '(labels, each by its text); list_lesfiches filters by them. Make an '
        'own label with create_lesfiche_label. This server does not change or '
        'remove a label itself: that is done in Smartschool.',
  ].join('\n');
}

/// The colours a new own label can get, as a tool's description and errors
/// list them.
final lesficheLabelColors = LessonContentService.labelColors.join(', ');

/// [value], the `text` argument of `create_lesfiche_label`: the text of a
/// new own label, without the white space around it.
///
/// Throws a [ToolError] for an empty text, and one longer than the
/// [LessonContentService.maxLabelLength] characters the web client takes
/// (the labels module answers it with a bare `400`), before anything is
/// sent.
String lesficheLabelTextArgument(Object? value) {
  final text = value is String ? value.trim() : '';
  if (text.isEmpty) {
    throw const ToolError('text is empty: give the label a text. $nothingSent');
  }
  if (text.length > LessonContentService.maxLabelLength) {
    throw ToolError(
      'text is ${text.length} characters long, and a label has at most '
      '${LessonContentService.maxLabelLength}: shorten it. $nothingSent',
    );
  }
  return text;
}

/// [value], the `color` argument of `create_lesfiche_label`: one of
/// [LessonContentService.labelColors] (case and white space do not
/// matter); [LessonContentService.defaultLabelColor] when it is absent or
/// empty.
///
/// Throws a [ToolError] that lists the colours for anything else.
String lesficheLabelColorArgument(Object? value) {
  final text = value is String ? value.trim().toLowerCase() : null;
  if (value == null || text == '') {
    return LessonContentService.defaultLabelColor;
  }
  if (LessonContentService.labelColors.contains(text)) return text!;
  throw ToolError(
    'color is ${value is String ? '"$value"' : '$value'}, which is not one of '
    'the colours of a label: $lesficheLabelColors. $nothingSent',
  );
}
