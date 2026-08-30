/// Formatter and validator for XML and HTML strings.
abstract final class XmlHtmlFormatter {
  /// Validates [xml] string and returns null if valid, or an error message if invalid.
  static String? validate(String xml) {
    final trimmed = xml.trim();
    if (trimmed.isEmpty) return null;

    final tagStack = <String>[];
    final tagRegex = RegExp(r'<(/)?([a-zA-Z0-9_\-:]+)([^>]*)>');
    final matches = tagRegex.allMatches(trimmed);

    if (matches.isEmpty) {
      if (trimmed.contains('<') || trimmed.contains('>')) {
        return 'Malformed XML/HTML tags';
      }
      return null;
    }

    for (final match in matches) {
      final fullMatch = match.group(0)!;
      final isClosing = match.group(1) != null;
      final tagName = match.group(2)!;
      final rest = match.group(3) ?? '';

      // Check for self-closing tag: <tag ... /> or XML declaration <?xml ... ?> or comment <!-- ... -->
      if (fullMatch.startsWith('<?') ||
          fullMatch.startsWith('<!') ||
          rest.trim().endsWith('/')) {
        continue;
      }

      // Void HTML elements that do not require closing tags
      const voidTags = {
        'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input',
        'link', 'meta', 'param', 'source', 'track', 'wbr'
      };
      if (voidTags.contains(tagName.toLowerCase())) {
        continue;
      }

      if (isClosing) {
        if (tagStack.isEmpty) {
          return 'Unexpected closing tag </$tagName>';
        }
        final last = tagStack.removeLast();
        if (last.toLowerCase() != tagName.toLowerCase()) {
          return 'Mismatched closing tag: expected </$last>, got </$tagName>';
        }
      } else {
        tagStack.add(tagName);
      }
    }

    if (tagStack.isNotEmpty) {
      return 'Unclosed tag: <${tagStack.last}>';
    }

    return null;
  }

  /// Formats / pretty-prints [xml] with [indent] spaces per level.
  static String format(String xml, {int indent = 2}) {
    final trimmed = xml.trim();
    if (trimmed.isEmpty) return xml;

    final indentStr = ' ' * indent;
    final buffer = StringBuffer();
    var level = 0;

    final tokenRegex = RegExp(r'(<!--[\s\S]*?-->|<\?[^>]*\?>|<![^>]*>|<[^>]+>|[^<]+)');
    final matches = tokenRegex.allMatches(trimmed);

    for (final match in matches) {
      var token = match.group(0)!.trim();
      if (token.isEmpty) continue;

      if (token.startsWith('</')) {
        // Closing tag
        if (level > 0) level--;
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.write(indentStr * level);
        buffer.write(token);
      } else if (token.startsWith('<') && token.endsWith('/>')) {
        // Self closing tag
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.write(indentStr * level);
        buffer.write(token);
      } else if (token.startsWith('<?') || token.startsWith('<!')) {
        // Directive / comment
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.write(indentStr * level);
        buffer.write(token);
      } else if (token.startsWith('<') && token.endsWith('>')) {
        // Opening tag
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.write(indentStr * level);
        buffer.write(token);
        level++;
      } else {
        // Text node
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.write(indentStr * level);
        buffer.write(token);
      }
    }

    return buffer.toString();
  }

  /// Minifies [xml] by removing newlines and extraneous spaces between tags.
  static String minify(String xml) {
    return xml
        .replaceAll(RegExp(r'>\s+<'), '><')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
