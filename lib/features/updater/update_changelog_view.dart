import 'dart:convert';

import 'package:flutter/material.dart' as material;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Lightweight Markdown-ish renderer for GitHub release notes.
class UpdateChangelogView extends StatelessWidget {
  const UpdateChangelogView({super.key, required this.markdown});

  final String markdown;

  @override
  material.Widget build(material.BuildContext context) {
    if (markdown.trim().isEmpty) {
      return const Text('No release notes provided.').muted().small();
    }

    final lines = const LineSplitter().convert(markdown);
    final children = <material.Widget>[];

    for (final line in lines) {
      if (line.trim().isEmpty) {
        children.add(const material.SizedBox(height: 8));
        continue;
      }

      final trimmed = line.trimLeft();
      if (trimmed.startsWith('### ')) {
        children.add(
          material.Padding(
            padding: const material.EdgeInsets.only(top: 8, bottom: 4),
            child: Text(trimmed.substring(4)).semiBold().small(),
          ),
        );
        continue;
      }
      if (trimmed.startsWith('## ')) {
        children.add(
          material.Padding(
            padding: const material.EdgeInsets.only(top: 10, bottom: 4),
            child: Text(trimmed.substring(3)).semiBold(),
          ),
        );
        continue;
      }
      if (trimmed.startsWith('# ')) {
        children.add(
          material.Padding(
            padding: const material.EdgeInsets.only(top: 12, bottom: 6),
            child: Text(trimmed.substring(2)).semiBold().large(),
          ),
        );
        continue;
      }
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        children.add(
          material.Padding(
            padding: const material.EdgeInsets.only(left: 8, bottom: 4),
            child: material.Row(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              children: [
                const Text('• ').muted(),
                material.Expanded(
                  child: Text(_inlineMarkdown(trimmed.substring(2))).small(),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      children.add(
        material.Padding(
          padding: const material.EdgeInsets.only(bottom: 4),
          child: Text(_inlineMarkdown(line)).small(),
        ),
      );
    }

    if (children.isEmpty) {
      return const Text('No release notes provided.').muted().small();
    }

    return material.SelectionArea(
      child: material.DefaultTextStyle(
        style: material.TextStyle(
          color: Theme.of(context).colorScheme.foreground,
          height: 1.45,
        ),
        child: material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  static String _inlineMarkdown(String input) {
    return input.replaceAllMapped(
      RegExp(r'`([^`]+)`'),
      (match) => match.group(1) ?? '',
    );
  }
}
