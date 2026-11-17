import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/changes.dart';
import 'package:purrage/state/status.dart';

import 'support/fake_repo.dart';

StatusRow row(String path, [Section section = Section.untracked]) => StatusRow(
      section: section,
      kind: section == Section.untracked ? RowKind.untracked : RowKind.modified,
      path: path,
      code: section == Section.untracked ? '??' : 'M ',
    );

void main() {
  group('StatusRow', () {
    test('name, folder and key are computed once', () {
      final file = row('lib/State/Repo.dart', Section.staged);
      expect(file.name, 'Repo.dart');
      expect(file.folder, 'lib/State');
      expect(file.folderLower, 'lib/state');
      expect(file.nameLower, 'repo.dart');
      expect(file.key, '${Section.staged.index}\u0000lib/State/Repo.dart');
      expect(identical(file.name, file.name), isTrue);
      expect(identical(file.folderLower, file.folderLower), isTrue);
      expect(identical(file.key, file.key), isTrue);
    });

    test('a directory keeps its slash on the name', () {
      final dir = row('es/inner/');
      expect(dir.isDirectory, isTrue);
      expect(dir.name, 'inner/');
      expect(dir.folder, 'es');
    });

    test('compare: section, then folder, then name, ignoring case', () {
      final rows = [
        row('b/a.txt'),
        row('A/z.txt'),
        row('a/B.txt'),
        row('top.txt', Section.staged),
        row('Z.txt'),
      ]..sort(StatusRow.compare);
      expect(rows.map((r) => r.path), ['top.txt', 'Z.txt', 'a/B.txt', 'A/z.txt', 'b/a.txt']);
    });

    test('sorting 5,000 rows reads the cached keys, not new strings', () {
      final rows = [
        for (var i = 4999; i >= 0; i--) row('Dir${i % 50}/Sub${i % 7}/File$i.dart'),
      ];
      final before = {for (final r in rows) r: r.folderLower};
      final clock = Stopwatch()..start();
      rows.sort(StatusRow.compare);
      clock.stop();
      for (final r in rows) {
        expect(identical(before[r], r.folderLower), isTrue);
      }
      // Generous: a per-comparison toLowerCase used to cost tens of ms here.
      expect(clock.elapsedMilliseconds, lessThan(500));
    });
  });

  group('Changes items', () {
    Future<Changes> loaded(List<StatusRow> rows) async {
      final changes = Changes(FakeRepo(rows));
      await changes.load();
      return changes;
    }

    test('one header per non-empty section, with its count, then its rows', () async {
      final changes = await loaded([
        row('a.txt', Section.staged),
        row('b.txt', Section.changed),
        row('c.txt'),
        row('d.txt'),
      ]);
      final items = changes.items;
      expect(items.whereType<HeaderItem>().map((h) => (h.section, h.count)), [
        (Section.staged, 1),
        (Section.changed, 1),
        (Section.untracked, 2),
      ]);
      expect(items.whereType<RowItem>().map((r) => r.index), [0, 1, 2, 3]);
      expect(items.whereType<RowItem>().map((r) => r.row.path), ['a.txt', 'b.txt', 'c.txt', 'd.txt']);
    });

    test('a cursor move keeps the same item list; a filter builds a new one', () async {
      final changes = await loaded([for (var i = 0; i < 50; i++) row('f$i.txt')]);
      final items = changes.items;
      await changes.move(1);
      await changes.extendSelection(3);
      await changes.click(10);
      expect(identical(changes.items, items), isTrue);

      await changes.setFilter('f1');
      expect(identical(changes.items, items), isFalse);
      expect(changes.items.whereType<HeaderItem>().single.count, changes.visible.length);
    });

    test('the selection count follows moves, ranges, toggles and filters', () async {
      final changes = await loaded([for (var i = 0; i < 20; i++) row('f$i.txt')]);
      expect(changes.selectionCount, 1);
      await changes.extendSelection(4);
      expect(changes.selectionCount, 5);
      await changes.toggleFocused();
      expect(changes.selectionCount, 4);
      await changes.selectAll();
      expect(changes.selectionCount, 20);
      await changes.setFilter('f1');
      expect(changes.selectionCount, 1);
      expect(changes.selectedRows, hasLength(1));
    });

    test('the staged count is kept with the rows', () async {
      final changes = await loaded([row('a.txt'), row('b.txt'), row('c.txt', Section.staged)]);
      expect(changes.stagedCount, 1);
      await changes.click(1);
      await changes.trackSelected();
      expect(changes.stagedCount, 2);
    });
  });
}
