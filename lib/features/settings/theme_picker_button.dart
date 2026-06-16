import 'dart:async';

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/layout/ui_scale.dart';
import 'package:querya_desktop/core/motion/querya_motion.dart';
import 'package:querya_desktop/core/motion/querya_motion_context.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/theme_definition.dart';
import 'package:querya_desktop/features/settings/theme_preview_card.dart';
import 'package:querya_desktop/shared/widgets/querya_dropdown_tokens.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Debounce delay before requesting a hover preview load.
const Duration themePreviewDebounce = Duration(milliseconds: 120);

/// Dedicated theme picker for large registry lists (50+ themes).
class ThemePickerButton extends material.StatefulWidget {
  const ThemePickerButton({
    super.key,
    required this.themes,
    required this.selectedThemeId,
    required this.onSelected,
    this.onPreviewTheme,
    this.isLoading = false,
    this.expandToParent = false,
    this.width,
  });

  final List<ThemeDefinition> themes;
  final String? selectedThemeId;
  final material.ValueChanged<String> onSelected;

  /// Loads preview data for [themeId] on hover. Must not apply the theme.
  final Future<ThemePreviewResult> Function(String themeId)? onPreviewTheme;

  final bool isLoading;
  final bool expandToParent;
  final double? width;

  static const double menuMaxHeight = 320;

  @override
  material.State<ThemePickerButton> createState() => _ThemePickerButtonState();
}

/// Filters [themes] by lowercase [query] against name, id, and source labels.
List<ThemeDefinition> filterThemeDefinitions(
  List<ThemeDefinition> themes,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return themes;

  return themes
      .where(
        (theme) =>
            theme.name.toLowerCase().contains(normalized) ||
            theme.id.toLowerCase().contains(normalized) ||
            theme.source.name.toLowerCase().contains(normalized) ||
            _sourceBadgeLabel(theme.source)
                .toLowerCase()
                .contains(normalized) ||
            (theme.metadata?.author?.toLowerCase().contains(normalized) ??
                false) ||
            (theme.metadata?.tags.any(
                  (tag) => tag.toLowerCase().contains(normalized),
                ) ??
                false),
      )
      .toList(growable: false);
}

class _ThemePickerButtonState extends material.State<ThemePickerButton> {
  final material.MenuController _controller = material.MenuController();
  final material.ScrollController _scrollController =
      material.ScrollController();
  final material.TextEditingController _searchController =
      material.TextEditingController();
  bool _triggerHovered = false;
  String? _previewThemeId;
  String? _previewThemeLabel;
  QueryaTheme? _previewTheme;
  String? _previewError;
  bool _previewLoading = false;
  Timer? _previewDebounce;
  int _previewRequestSerial = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _resetPreviewState() {
    _previewDebounce?.cancel();
    _previewRequestSerial++;
    _previewThemeId = null;
    _previewThemeLabel = null;
    _previewTheme = null;
    _previewError = null;
    _previewLoading = false;
  }

  void _schedulePreview(ThemeDefinition definition) {
    if (widget.onPreviewTheme == null) return;

    _previewDebounce?.cancel();
    final targetId = definition.id;
    setState(() {
      _previewThemeId = targetId;
      _previewThemeLabel = definition.name;
    });

    _previewDebounce = Timer(themePreviewDebounce, () {
      if (!mounted || _previewThemeId != targetId) return;
      setState(() {
        _previewLoading = true;
        _previewTheme = null;
        _previewError = null;
      });
      unawaited(_loadPreview(targetId));
    });
  }

  Future<void> _loadPreview(String themeId) async {
    final loader = widget.onPreviewTheme;
    if (loader == null || !mounted || _previewThemeId != themeId) return;

    final requestId = ++_previewRequestSerial;
    final result = await loader(themeId);
    if (!mounted || requestId != _previewRequestSerial) return;

    setState(() {
      _previewLoading = false;
      switch (result) {
        case ThemePreviewSuccess(:final theme):
          _previewTheme = theme;
          _previewError = null;
        case ThemePreviewFailure(:final message):
          _previewTheme = null;
          _previewError = message;
        case ThemePreviewLoading():
          _previewLoading = true;
      }
    });
  }

  void _onSearchChanged() {
    setState(() {});
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _clearSearch() {
    if (_searchController.text.isEmpty) return;
    _searchController.clear();
  }

  List<ThemeDefinition> get _filteredThemes =>
      filterThemeDefinitions(widget.themes, _searchController.text);

  bool get _enabled => !widget.isLoading;

  String get _triggerLabel {
    if (widget.isLoading) return 'Loading themes…';
    if (widget.selectedThemeId == null) return 'Select theme…';
    for (final theme in widget.themes) {
      if (theme.id == widget.selectedThemeId) return theme.name;
    }
    return widget.selectedThemeId!;
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fieldWidth = widget.expandToParent
        ? null
        : (widget.width != null ? context.scaled(widget.width!) : null);
    final menuWidth = fieldWidth ?? context.scaled(280);
    final menuHeight = context.scaled(ThemePickerButton.menuMaxHeight);
    final radius = context.scaled(QueryaDropdownTokens.menuBorderRadius);

    final anchor = material.MenuAnchor(
      controller: _controller,
      crossAxisUnconstrained: false,
      alignmentOffset: material.Offset(
        0,
        context.scaled(QueryaDropdownTokens.menuAlignmentOffset.dy),
      ),
      consumeOutsideTap: true,
      style: material.MenuStyle(
        backgroundColor: material.WidgetStatePropertyAll(cs.popover),
        surfaceTintColor: material.WidgetStatePropertyAll(cs.popover),
        elevation: const material.WidgetStatePropertyAll(
          QueryaDropdownTokens.menuElevation,
        ),
        shadowColor: const material.WidgetStatePropertyAll(
          QueryaDropdownTokens.menuShadowColor,
        ),
        maximumSize: material.WidgetStatePropertyAll(
          material.Size(menuWidth, menuHeight),
        ),
        minimumSize: material.WidgetStatePropertyAll(
          material.Size(menuWidth, 0),
        ),
        padding:
            const material.WidgetStatePropertyAll(material.EdgeInsets.zero),
        shape: material.WidgetStatePropertyAll(
          material.RoundedRectangleBorder(
            borderRadius: material.BorderRadius.circular(radius),
            side: material.BorderSide(color: cs.border),
          ),
        ),
      ),
      menuChildren: [
        material.SizedBox(
          width: menuWidth,
          height: menuHeight,
          child: _buildMenuPanel(context, cs),
        ),
      ],
      builder: (context, controller, child) {
        final trigger = _buildTrigger(
          context: context,
          controller: controller,
          cs: cs,
          fieldWidth: fieldWidth,
        );
        if (widget.expandToParent) {
          return material.SizedBox(width: double.infinity, child: trigger);
        }
        if (fieldWidth != null) {
          return material.SizedBox(width: fieldWidth, child: trigger);
        }
        return trigger;
      },
    );

    return anchor;
  }

  material.Widget _buildMenuPanel(
      material.BuildContext context, ColorScheme cs) {
    final filteredThemes = _filteredThemes;
    final radius = context.scaled(QueryaDropdownTokens.menuBorderRadius);

    return material.Column(
      children: [
        material.Padding(
          padding: material.EdgeInsets.fromLTRB(
            context.scaled(8),
            context.scaled(8),
            context.scaled(8),
            context.scaled(4),
          ),
          child: material.TextField(
            controller: _searchController,
            style: material.TextStyle(
              fontSize: context.scaled(QueryaDropdownTokens.fontSize),
              color: cs.popoverForeground,
            ),
            decoration: material.InputDecoration(
              isDense: true,
              hintText: 'Search themes…',
              hintStyle: material.TextStyle(color: cs.mutedForeground),
              prefixIcon: material.Icon(
                material.Icons.search,
                size: context.scaled(18),
                color: cs.mutedForeground,
              ),
              prefixIconConstraints: material.BoxConstraints(
                minWidth: context.scaled(36),
                minHeight: context.scaled(32),
              ),
              contentPadding: material.EdgeInsets.symmetric(
                horizontal: context.scaled(8),
                vertical: context.scaled(8),
              ),
              filled: true,
              fillColor: cs.muted.withValues(alpha: 0.18),
              border: material.OutlineInputBorder(
                borderRadius: material.BorderRadius.circular(radius),
                borderSide: material.BorderSide(color: cs.border),
              ),
              enabledBorder: material.OutlineInputBorder(
                borderRadius: material.BorderRadius.circular(radius),
                borderSide: material.BorderSide(color: cs.border),
              ),
              focusedBorder: material.OutlineInputBorder(
                borderRadius: material.BorderRadius.circular(radius),
                borderSide: material.BorderSide(color: cs.ring),
              ),
            ),
          ),
        ),
        if (widget.onPreviewTheme != null)
          material.Padding(
            padding: material.EdgeInsets.fromLTRB(
              context.scaled(8),
              context.scaled(4),
              context.scaled(8),
              context.scaled(4),
            ),
            child: ThemePreviewCard(
              theme: _previewTheme,
              errorMessage: _previewError,
              isLoading: _previewLoading,
              label: _previewThemeLabel,
            ),
          ),
        material.Expanded(
          child: filteredThemes.isEmpty
              ? material.Center(
                  child: material.Padding(
                    padding: material.EdgeInsets.all(context.scaled(12)),
                    child: material.Text(
                      'No themes match your search.',
                      textAlign: material.TextAlign.center,
                      style: material.TextStyle(
                        fontSize: context.scaled(12),
                        color: cs.mutedForeground,
                      ),
                    ),
                  ),
                )
              : material.Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: filteredThemes.length > 8,
                  child: material.ListView.builder(
                    controller: _scrollController,
                    primary: false,
                    padding: QueryaDropdownTokens.menuPadding,
                    itemCount: filteredThemes.length,
                    itemBuilder: (context, index) {
                      final theme = filteredThemes[index];
                      return _ThemePickerRow(
                        definition: theme,
                        selected: theme.id == widget.selectedThemeId,
                        colorScheme: cs,
                        onHover: widget.onPreviewTheme == null
                            ? null
                            : () => _schedulePreview(theme),
                        onSelected: () {
                          widget.onSelected(theme.id);
                          _clearSearch();
                          _resetPreviewState();
                          _controller.close();
                        },
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  material.Widget _buildTrigger({
    required material.BuildContext context,
    required material.MenuController controller,
    required ColorScheme cs,
    required double? fieldWidth,
  }) {
    final borderColor = _enabled
        ? (_triggerHovered ? cs.ring : cs.border)
        : cs.border.withValues(alpha: 0.4);
    final triggerHeight = QueryaDropdownTokens.scaledTriggerHeight(context);
    final chevronGap = context.scaled(QueryaDropdownTokens.triggerChevronGap);
    final chevronSize = context.scaled(QueryaDropdownTokens.triggerChevronSize);
    final radius = context.scaled(QueryaDropdownTokens.menuBorderRadius);

    final triggerBody = material.MouseRegion(
      cursor: _enabled
          ? material.SystemMouseCursors.click
          : material.SystemMouseCursors.basic,
      onEnter: _enabled ? (_) => setState(() => _triggerHovered = true) : null,
      onExit: _enabled ? (_) => setState(() => _triggerHovered = false) : null,
      child: material.AnimatedContainer(
        duration: context.motionDuration(QueryaMotion.fast),
        curve: context.motionCurve(QueryaMotion.enter),
        height: triggerHeight,
        padding: QueryaDropdownTokens.scaledTriggerPadding(context),
        decoration: material.BoxDecoration(
          color: _triggerHovered
              ? cs.muted.withValues(alpha: 0.28)
              : cs.muted.withValues(alpha: 0.14),
          borderRadius: material.BorderRadius.circular(radius),
          border: material.Border.all(color: borderColor),
        ),
        child: material.Row(
          mainAxisAlignment: material.MainAxisAlignment.spaceBetween,
          mainAxisSize: (widget.expandToParent || fieldWidth != null)
              ? material.MainAxisSize.max
              : material.MainAxisSize.min,
          children: [
            material.Expanded(
              child: material.Text(
                _triggerLabel,
                maxLines: 1,
                overflow: material.TextOverflow.ellipsis,
                style: QueryaDropdownTokens.triggerTextStyle(
                  context,
                  _enabled ? cs.popoverForeground : cs.mutedForeground,
                ),
              ),
            ),
            material.SizedBox(width: chevronGap),
            material.Icon(
              material.Icons.keyboard_arrow_down_rounded,
              size: chevronSize,
              color: _enabled
                  ? cs.mutedForeground
                  : cs.mutedForeground.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );

    return material.Material(
      type: material.MaterialType.transparency,
      child: material.InkWell(
        onTap: _enabled
            ? () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  _clearSearch();
                  _resetPreviewState();
                  controller.open();
                }
              }
            : null,
        borderRadius: material.BorderRadius.circular(radius),
        child: triggerBody,
      ),
    );
  }
}

class _ThemePickerRow extends material.StatefulWidget {
  const _ThemePickerRow({
    required this.definition,
    required this.selected,
    required this.colorScheme,
    required this.onSelected,
    this.onHover,
  });

  final ThemeDefinition definition;
  final bool selected;
  final ColorScheme colorScheme;
  final material.VoidCallback onSelected;
  final material.VoidCallback? onHover;

  @override
  material.State<_ThemePickerRow> createState() => _ThemePickerRowState();
}

class _ThemePickerRowState extends material.State<_ThemePickerRow> {
  bool _hovered = false;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = widget.colorScheme;
    final bg = _hovered
        ? cs.accent.withValues(alpha: 0.14)
        : widget.selected
            ? cs.muted.withValues(alpha: 0.32)
            : material.Colors.transparent;
    final itemHeight = QueryaDropdownTokens.scaledMenuItemHeight(context);
    final radius = context.scaled(QueryaDropdownTokens.menuBorderRadius);
    final slot = context.scaled(QueryaDropdownTokens.selectedCheckSlotWidth);

    return material.MouseRegion(
      cursor: material.SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onHover?.call();
      },
      onExit: (_) => setState(() => _hovered = false),
      child: material.Material(
        type: material.MaterialType.transparency,
        child: material.InkWell(
          onTap: widget.onSelected,
          borderRadius: material.BorderRadius.circular(radius),
          child: material.AnimatedContainer(
            duration: context.motionDuration(QueryaMotion.fast),
            curve: context.motionCurve(QueryaMotion.enter),
            constraints: material.BoxConstraints(minHeight: itemHeight),
            padding: material.EdgeInsets.symmetric(
              horizontal: context
                  .scaled(QueryaDropdownTokens.menuItemPadding.horizontal),
              vertical:
                  context.scaled(QueryaDropdownTokens.menuItemPadding.vertical),
            ),
            decoration: material.BoxDecoration(
              color: bg,
              borderRadius: material.BorderRadius.circular(radius),
            ),
            child: material.Row(
              children: [
                material.SizedBox(
                  width: slot,
                  child: widget.selected
                      ? material.Icon(
                          material.Icons.check_rounded,
                          size: context.scaled(
                            QueryaDropdownTokens.selectedCheckSize,
                          ),
                          color: cs.primary,
                        )
                      : null,
                ),
                material.SizedBox(width: context.scaled(6)),
                material.Expanded(
                  child: _ThemePickerRowTitle(
                    definition: widget.definition,
                    colorScheme: cs,
                    selected: widget.selected,
                  ),
                ),
                material.SizedBox(width: context.scaled(6)),
                _SourceBadge(
                  label: _sourceBadgeLabel(widget.definition.source),
                  colorScheme: cs,
                ),
                material.SizedBox(width: context.scaled(6)),
                _BrightnessLabel(
                    isDark: widget.definition.isDark, colorScheme: cs),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemePickerRowTitle extends material.StatelessWidget {
  const _ThemePickerRowTitle({
    required this.definition,
    required this.colorScheme,
    required this.selected,
  });

  final ThemeDefinition definition;
  final ColorScheme colorScheme;
  final bool selected;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = colorScheme;
    final subtitle = definition.metadata?.pickerSubtitle;

    if (subtitle == null) {
      return material.Text(
        definition.name,
        maxLines: 1,
        overflow: material.TextOverflow.ellipsis,
        style: QueryaDropdownTokens.menuItemTextStyle(
          context,
          cs.popoverForeground,
          selected: selected,
        ),
      );
    }

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.start,
      mainAxisSize: material.MainAxisSize.min,
      children: [
        material.Text(
          definition.name,
          maxLines: 1,
          overflow: material.TextOverflow.ellipsis,
          style: QueryaDropdownTokens.menuItemTextStyle(
            context,
            cs.popoverForeground,
            selected: selected,
          ),
        ),
        material.Text(
          subtitle,
          maxLines: 1,
          overflow: material.TextOverflow.ellipsis,
          style: material.TextStyle(
            fontSize: context.scaled(11),
            height: 1.2,
            color: cs.mutedForeground,
          ),
        ),
      ],
    );
  }
}

class _SourceBadge extends material.StatelessWidget {
  const _SourceBadge({
    required this.label,
    required this.colorScheme,
  });

  final String label;
  final ColorScheme colorScheme;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = colorScheme;
    return material.Container(
      padding: material.EdgeInsets.symmetric(
        horizontal: context.scaled(6),
        vertical: context.scaled(2),
      ),
      decoration: material.BoxDecoration(
        color: cs.muted.withValues(alpha: 0.45),
        borderRadius: material.BorderRadius.circular(
          context.scaled(QueryaDropdownTokens.menuBorderRadius),
        ),
        border: material.Border.all(color: cs.border.withValues(alpha: 0.6)),
      ),
      child: material.Text(
        label,
        style: material.TextStyle(
          fontSize: context.scaled(11),
          height: 1.1,
          color: cs.mutedForeground,
          fontWeight: material.FontWeight.w500,
        ),
      ),
    );
  }
}

class _BrightnessLabel extends material.StatelessWidget {
  const _BrightnessLabel({
    required this.isDark,
    required this.colorScheme,
  });

  final bool isDark;
  final ColorScheme colorScheme;

  @override
  material.Widget build(material.BuildContext context) {
    final cs = colorScheme;
    return material.Row(
      mainAxisSize: material.MainAxisSize.min,
      children: [
        material.Icon(
          isDark
              ? material.Icons.dark_mode_outlined
              : material.Icons.light_mode_outlined,
          size: context.scaled(14),
          color: cs.mutedForeground,
        ),
        material.SizedBox(width: context.scaled(4)),
        material.Text(
          isDark ? 'Dark' : 'Light',
          style: material.TextStyle(
            fontSize: context.scaled(11),
            color: cs.mutedForeground,
          ),
        ),
      ],
    );
  }
}

String _sourceBadgeLabel(ThemeSource source) {
  return switch (source) {
    ThemeSource.builtin => 'Built-in',
    ThemeSource.imported => 'Imported',
    ThemeSource.filesystem => 'File',
    ThemeSource.legacyImported => 'Imported',
  };
}
