import 'package:flutter/widgets.dart';
import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Brightens every channel (x1.9 and a small lift), alpha untouched.
const _liftDarkIcon = material.ColorFilter.matrix(<double>[
  1.9, 0, 0, 0, 40, //
  0, 1.9, 0, 0, 40,
  0, 0, 1.9, 0, 40,
  0, 0, 0, 1, 0,
]);

/// Renders a bundled or extension-provided database icon with one fallback.
class DriverIcon extends StatelessWidget {
  const DriverIcon({
    super.key,
    required this.size,
    required this.fallbackIcon,
    this.assetPath,
    this.filePath,
  }) : assert(assetPath == null || filePath == null);

  final double size;
  final material.IconData fallbackIcon;
  final String? assetPath;
  final String? filePath;

  @override
  material.Widget build(material.BuildContext context) {
    final fallback = material.Icon(
      fallbackIcon,
      size: size,
      color: context.colors.primary,
    );

    if (filePath != null) {
      return DriverIconImage(
        path: filePath!,
        size: size,
        fallbackIcon: fallbackIcon,
      );
    }
    if (assetPath != null) {
      final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).toInt();
      final image = material.Image.asset(
        assetPath!,
        width: size,
        height: size,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
        fit: material.BoxFit.contain,
        filterQuality: material.FilterQuality.medium,
        errorBuilder: (_, __, ___) => fallback,
      );
      // The MySQL dolphin is dark blue and nearly vanishes on a dark surface
      // (#1824): lift it there, leave the light theme alone.
      if (assetPath!.endsWith('mysql_icon.png') &&
          material.Theme.of(context).brightness == material.Brightness.dark) {
        return material.ColorFiltered(
          colorFilter: _liftDarkIcon,
          child: image,
        );
      }
      return image;
    }
    return fallback;
  }
}

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
    final fallback = material.Icon(
      fallbackIcon,
      size: size,
      color: context.colors.primary,
    );

    final file = File(path);

    if (path.toLowerCase().endsWith('.svg')) {
      return SvgPicture.file(
        file,
        width: size,
        height: size,
        fit: material.BoxFit.contain,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).toInt();
    return material.Image.file(
      file,
      width: size,
      height: size,
      cacheWidth: cacheSize,
      cacheHeight: cacheSize,
      fit: material.BoxFit.contain,
      filterQuality: material.FilterQuality.medium,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}
