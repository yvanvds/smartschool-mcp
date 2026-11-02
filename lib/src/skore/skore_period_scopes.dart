import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_smartschool/flutter_smartschool.dart';

import '../log.dart';

// WORKAROUND (#205, removal tracked in #207, yvanvds/dartschool#236): which
// periods of a gradebook are project periods.
//
// Skore's `init` lists a gradebook's evaluation periods and its project
// periods ("Projecten", #192) in the same `periods`, whatever its page, and
// tells them apart by the period's `scope`: `1` an evaluation period, `2` a
// project period (seen live, 2026-11-02: the project gradebook "Digitale
// vaardigheden" of 5WW1 gave its project period Digit with `scope` 2, a
// normal gradebook its DW1 and DW2 with `scope` 1; `categoryMode` was 1 in
// all of them). flutter_smartschool 0.4.2 does not read `scope`: its
// `getGradebook` gives a project period as an evaluation period, and its
// `getProjectPeriods` gives a normal gradebook's evaluation periods as
// project periods.
//
// Until the library tells them apart, [readingSkoreProjectPeriodIds] reads
// `scope` from the raw answer of the `init` the library sends anyway, with
// a Dio interceptor on the client for the length of one read: no extra
// request is sent.

/// The path of Skore's gradebook RPC service, where `init` goes.
const _rpcPath = '/modules/Skore/backend/gradebook/rpc.php';

/// Skore's `scope` of a project period in `init`'s `periods`.
const _projectScope = 2;

/// Runs [read] on [client] and returns its result with the ids of the
/// project periods (`scope` 2) of gradebook [gradebookId], as the last
/// answer of Skore's `init` about that gradebook during [read] gives them
/// (empty for a gradebook without project periods), or null when no such
/// answer was seen or none could be used (logged), so the caller keeps to
/// what the library gave.
///
/// [read] is a read of the library that sends `init` for the gradebook,
/// such as `getGradebook` or `getProjectPeriods`.
Future<(T, Set<int>?)> readingSkoreProjectPeriodIds<T>(
  SmartschoolClient client,
  int gradebookId,
  Future<T> Function() read,
) async {
  Set<int>? projectPeriodIds;
  final interceptor = InterceptorsWrapper(
    onResponse: (response, handler) {
      final ids = _projectPeriodIds(response, gradebookId);
      if (ids != null) projectPeriodIds = ids;
      handler.next(response);
    },
  );
  client.dio.interceptors.add(interceptor);
  try {
    final value = await read();
    return (value, projectPeriodIds);
  } finally {
    client.dio.interceptors.remove(interceptor);
  }
}

/// The ids of the project periods in [response] when it is Skore's answer
/// to `init` for gradebook [gradebookId]; null for any other answer, and
/// for one not in the shape seen live (logged).
Set<int>? _projectPeriodIds(Response<dynamic> response, int gradebookId) {
  final request = response.requestOptions;
  final data = request.data;
  if (!request.uri.path.endsWith(_rpcPath) ||
      data is! Map ||
      data['rpc_method'] != 'init' ||
      response.statusCode != 200) {
    return null;
  }
  try {
    final body = response.data;
    final json = body is String ? jsonDecode(body) : body;
    final result = json is Map ? json['result'] : null;
    if (result is! Map) return null;
    final owners = result['ownerMap'];
    if (owners is! List ||
        !owners.any((o) => o is Map && _id(o['ownerID']) == gradebookId)) {
      return null;
    }
    final periods = result['periods'];
    if (periods is! List) return null;
    final ids = <int>{};
    for (final period in periods) {
      if (period is! Map) return null;
      final id = _id(period['id']);
      if (id == null) return null;
      if (_id(period['scope']) == _projectScope) ids.add(id);
    }
    return ids;
  } on FormatException catch (error) {
    log('skore gradebook: the period scopes of init: $error');
    return null;
  }
}

/// [value] as Skore gives an id, a number or a string of digits.
int? _id(Object? value) =>
    value is int ? value : int.tryParse('${value ?? ''}'.trim());
