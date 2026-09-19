import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Bold/primary span for the first case-insensitive [query] hit in [text].
class CommandMatchHighlight extends StatelessWidget {
  const CommandMatchHighlight({
    super.key,
    required this.text,
    required this.query,
  });

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    if (q.isEmpty) return Text(text);
    final lower = text.toLowerCase();
    final needle = q.toLowerCase();
    final index = lower.indexOf(needle);
    if (index < 0) return Text(text);
    final theme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, index)),
          TextSpan(
            text: text.substring(index, index + needle.length),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: theme.primary,
            ),
          ),
          TextSpan(text: text.substring(index + needle.length)),
        ],
      ),
    );
  }
}
