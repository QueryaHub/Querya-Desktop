## Summary

<!-- What changed and why (1–3 sentences). -->

## Linked issue

<!-- Use branch `issue/<number>-<slug>` and/or: -->

Closes #

## Checklist

- [ ] `flutter analyze` and `flutter test` pass locally
- [ ] Scope matches the linked issue only (no drive-by refactors)
- [ ] PR targets **`dev`** (not `main`, unless hotfix)

## Metadata (automation)

If the branch is `issue/<n>-…` or the body contains `Closes #n`, workflow **[PR linked issue metadata](.github/workflows/pr-linked-issue-metadata.yml)** copies **labels** and **milestone** from the linked issue onto this PR.

For **Theme system** work, ensure the issue has milestone **Theme system** and labels such as `theme`, `editor`, `enhancement`.

Manual override when creating the PR:

```bash
gh pr create --base dev \
  --milestone "Theme system" \
  --label "theme,enhancement" \
  --title "feat(theme): short description (#NN)" \
  --body "$(cat <<'EOF'
## Summary
...

Closes #NN
EOF
)"
```
