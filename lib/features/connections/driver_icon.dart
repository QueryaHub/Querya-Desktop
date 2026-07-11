import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Renders an extension driver icon from a file on disk (SVG or bitmap).
/// Falls back to [fallbackIcon] when the file is missing or unreadable.
class DriverIconImage extends StatelessWidget {
  const DriverIconImage({
    super.key,
    required this.path,
    required this.size,
    this.fallbackIcon = material.Icons.extension_rounded,
  });

  final String path;
  final double size;
  final material.IconData fallbackIcon;

  @override
  material.Widget build(material.BuildContext context) {
    final theme = Theme.of(context);
    final fallback = material.Icon(
      fallbackIcon,
      size: size,
      color: theme.colorScheme.primary,
    );

    final file = File(path);
    if (!file.existsSync()) return fallback;

    if (path.toLowerCase().endsWith('.svg')) {
      return SvgPicture.file(
        file,
        width: size,
        height: size,
        fit: material.BoxFit.contain,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    return material.Image.file(
      file,
      width: size,
      height: size,
      fit: material.BoxFit.contain,
      filterQuality: material.FilterQuality.medium,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}
