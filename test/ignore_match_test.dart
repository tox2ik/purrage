import 'package:flutter_test/flutter_test.dart';
import 'package:purrage/state/git_repo.dart';

void main() {
  group('IgnoreMatch.parse', () {
    test('a Windows source keeps its drive letter out of the line number', () {
      final match = IgnoreMatch.parse(
        r'C:/Users/jazzo/.gitignore:135:/es/	es/nvimos-meta/',
      );
      expect(match, isNotNull);
      expect(match!.source, r'C:/Users/jazzo/.gitignore');
      expect(match.line, 135);
      expect(match.pattern, '/es/');
      expect(match.path, 'es/nvimos-meta/');
    });

    test('a relative source parses the same way', () {
      final match = IgnoreMatch.parse('.gitignore:3:*.log\trun.log');
      expect(match!.source, '.gitignore');
      expect(match.line, 3);
      expect(match.pattern, '*.log');
    });

    test('a pattern with a colon survives', () {
      final match = IgnoreMatch.parse(r'C:/r/.gitignore:7:a:b	weird.txt');
      expect(match!.line, 7);
      expect(match.pattern, 'a:b');
    });

    test('an empty answer is null, not a match', () {
      expect(IgnoreMatch.parse(''), isNull);
    });
  });
}
