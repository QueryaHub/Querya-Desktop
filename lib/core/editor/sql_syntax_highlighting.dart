/// Future work: editable SQL with syntax highlighting (see plan: syntax-highlight-epic).
///
/// Candidates: custom [EditableText] + [TextPainter], or a dedicated code-editor package.
/// Plain [TextField] remains the source of truth until an editor is chosen.
abstract class SqlSyntaxHighlighting {
  const SqlSyntaxHighlighting._();
}
