import 'package:flutter_test/flutter_test.dart';
import 'package:glustered/state/status.dart';

StatusRow row(String path, {Section section = Section.untracked}) =>
    StatusRow(section: section, kind: RowKind.untracked, path: path, code: '??');

void main() {
  group('filterRows', () {
    final rows = [
      row('lib/state/repo.dart'),
      row('lib/ui/shell.dart'),
      row('README.md'),
      row('build/out.txt'),
    ];

    test('an empty or blank query keeps every row', () {
      expect(filterRows(rows, ''), rows);
      expect(filterRows(rows, '   '), rows);
    });

    test('a plain substring narrows the list', () {
      expect(filterRows(rows, 'lib/').map((r) => r.path), ['lib/state/repo.dart', 'lib/ui/shell.dart']);
      expect(filterRows(rows, 'shell').map((r) => r.path), ['lib/ui/shell.dart']);
    });

    test('matching ignores case', () {
      expect(filterRows(rows, 'readme').map((r) => r.path), ['README.md']);
      expect(filterRows(rows, 'REPO').map((r) => r.path), ['lib/state/repo.dart']);
    });

    test('surrounding spaces are ignored', () {
      expect(
        filterRows(rows, '  dart  ').map((r) => r.path),
        ['lib/state/repo.dart', 'lib/ui/shell.dart'],
      );
    });

    test('no match gives an empty list', () {
      expect(filterRows(rows, 'nope'), isEmpty);
    });

    test('the original list is not mutated', () {
      filterRows(rows, 'lib');
      expect(rows, hasLength(4));
    });
  });
}
