# Vendored `shadcn_flutter`

Upstream: `shadcn_flutter` **0.0.52** (pub.dev).

## Patch

`lib/src/components/overlay/toast.dart`: **ToastLayer** no longer wraps the stack in
`ForwardableData` + `Data.inherit` (double inherited layer). Only `Data.inherit` remains.

This avoids Flutter **InheritedNotifier.notifyClients** / **line 6417** assertions when
the window is resized or after hot reload (stale dependent vs ancestor).

If you upgrade `shadcn_flutter`, re-copy the package and re-apply this patch, or
check whether upstream fixed the issue.
