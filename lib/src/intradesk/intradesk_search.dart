import '../messages/message_search.dart';
import 'intradesk_index.dart';

/// The items among [items] whose name matches [query], best first.
///
/// An item matches when every word of [query] occurs in its path (the
/// folder names above it and its own name) and at least one in its own
/// name, ignoring case and accents, also as part of a longer word: `formulier
/// uitstap` finds `Formulieren / uitstap.docx`, while `formulieren` finds
/// the folder but not every file in it. The items with the most words in
/// their own name come first, then in path order.
List<IntradeskItem> matchIntradeskItems(
  Iterable<IntradeskItem> items,
  SearchQuery query,
) {
  final hits = <({IntradeskItem item, int inName, String path})>[];
  for (final item in items) {
    final name = foldForSearch(item.name);
    final inName = query.terms.where(name.contains).length;
    if (inName == 0) continue;
    final path = foldForSearch(item.path);
    if (inName < query.terms.length && !query.terms.every(path.contains)) {
      continue;
    }
    hits.add((item: item, inName: inName, path: path));
  }
  hits.sort((a, b) {
    final byWords = b.inName.compareTo(a.inName);
    return byWords != 0 ? byWords : a.path.compareTo(b.path);
  });
  return [for (final hit in hits) hit.item];
}
