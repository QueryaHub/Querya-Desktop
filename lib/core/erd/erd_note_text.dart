/// A run of a note line: text, bold or not.
typedef ErdNoteRun = ({String text, bool bold});

/// One line of a note: a bullet when it started with `- ` or `* `.
class ErdNoteLine {
  const ErdNoteLine(this.runs, {this.bullet = false});

  final List<ErdNoteRun> runs;
  final bool bullet;

  String get plain => runs.map((r) => r.text).join();
}

/// Markdown-light text of a sticky note (#1283): `**bold**` and `- ` lists,
/// everything else is plain. An unclosed `**` is kept as typed.
List<ErdNoteLine> parseErdNote(String text) {
  final lines = <ErdNoteLine>[];
  for (final raw in text.split('\n')) {
    var line = raw;
    var bullet = false;
    final m = RegExp(r'^\s*[-*] +').firstMatch(line);
    if (m != null) {
      bullet = true;
      line = line.substring(m.end);
    }
    final runs = <ErdNoteRun>[];
    var bold = false;
    final parts = line.split('**');
    // An odd number of markers leaves the last one unclosed.
    final closed = parts.length.isOdd;
    for (var i = 0; i < parts.length; i++) {
      final last = i == parts.length - 1;
      if (i > 0 && last && !closed && bold) {
        runs.add((text: '**${parts[i]}', bold: false));
      } else if (parts[i].isNotEmpty) {
        runs.add((text: parts[i], bold: bold));
      }
      bold = !bold;
    }
    lines.add(ErdNoteLine(runs, bullet: bullet));
  }
  return lines;
}
