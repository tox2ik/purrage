import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The declarative UI rules, measured on the source of `lib/ui/` the way the
/// review measured them: a `build` is under 50 lines, an event handler closure
/// holds one statement, and only `widgets.dart` sets the pointer cursor.
void main() {
  final files = Directory('lib/ui')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();

  String name(File file) => file.path.replaceAll(r'\', '/');

  test('every build is under 50 lines', () {
    final long = <String>[];
    var measured = 0;
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (final span in buildSpans(lines)) {
        measured++;
        if (span.$2 >= 50) long.add('${name(file)}:${span.$1 + 1} build is ${span.$2} lines');
      }
    }
    expect(long, isEmpty);
    expect(measured, greaterThan(30), reason: 'the measure must find the builds');
  });

  test('no event handler closure has more than one statement', () {
    final busy = <String>[];
    for (final file in files) {
      final text = file.readAsStringSync();
      for (final at in handlerBlocks(text)) {
        final statements = topLevelStatements(text, at.$2);
        if (statements > 1) {
          final line = '\n'.allMatches(text.substring(0, at.$1)).length + 1;
          busy.add('${name(file)}:$line handler has $statements statements');
        }
      }
    }
    expect(busy, isEmpty);
  });

  test('only widgets.dart sets the pointer cursor', () {
    final elsewhere = [
      for (final file in files)
        if (!name(file).endsWith('/widgets.dart') &&
            file.readAsStringSync().contains('SystemMouseCursors.click'))
          name(file),
    ];
    expect(elsewhere, isEmpty);
  });

  test('the measures themselves', () {
    expect(buildSpans(['  Widget build(BuildContext context) {', '    return x;', '  }']), [(0, 3)]);
    expect(buildSpans(['  Widget build(BuildContext context) => Text(', "    'a',", '  );']), [(0, 3)]);
    const two = 'onPressed: () { a(); b(); },';
    expect(topLevelStatements(two, handlerBlocks(two).single.$2), 2);
    const one = 'onTap: () { if (x) { a(); b(); } },';
    expect(topLevelStatements(one, handlerBlocks(one).single.$2), 1);
  });
}

/// (first line index, length in lines) of every `Widget build(` in [lines],
/// from the signature to the closing brace or the `;` of an arrow body.
List<(int, int)> buildSpans(List<String> lines) {
  final spans = <(int, int)>[];
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].contains('Widget build(BuildContext')) continue;
    var depth = 0;
    var started = false;
    final arrow = lines[i].contains('=>') && !lines[i].trimRight().endsWith('{');
    for (var j = i; j < lines.length; j++) {
      for (final char in lines[j].split('')) {
        if (char == '{' || char == '(' || char == '[') {
          depth++;
          started = true;
        } else if (char == '}' || char == ')' || char == ']') {
          depth--;
        } else if (arrow && char == ';' && depth == 0) {
          spans.add((i, j - i + 1));
          j = lines.length;
          break;
        }
      }
      if (!arrow && started && depth == 0 && j < lines.length) {
        spans.add((i, j - i + 1));
        break;
      }
    }
  }
  return spans;
}

/// (offset of the handler name, offset of its block's `{`) for every
/// `onSomething: (...) {` or `onSomething: (...) async {` closure.
List<(int, int)> handlerBlocks(String text) => [
      for (final match in RegExp(r'\bon[A-Z]\w*\s*:\s*\([^()]*\)\s*(async\s*)?\{').allMatches(text))
        (match.start, match.end - 1),
    ];

/// Statements at the top level of the block that opens at [open].
int topLevelStatements(String text, int open) {
  var depth = 0;
  var count = 0;
  var sawCode = false;
  for (var i = open; i < text.length; i++) {
    final char = text[i];
    if (char == '{' || char == '(' || char == '[') {
      depth++;
    } else if (char == '}' || char == ')' || char == ']') {
      depth--;
      if (depth == 0) return count + (sawCode ? 1 : 0);
      // A block statement (`if (...) { ... }`) ends at its brace, not a `;`.
      if (depth == 1 && char == '}') {
        count++;
        sawCode = false;
      }
    } else if (char == ';' && depth == 1) {
      count++;
      sawCode = false;
    } else if (depth == 1 && char.trim().isNotEmpty) {
      sawCode = true;
    }
  }
  return count;
}
