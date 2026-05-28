# Sample VS Code themes for Querya

Import via **Preferences → Appearance → Import theme…**

| File | Notes |
|------|--------|
| [cyberpunk-neon.json](cyberpunk-neon.json) | Dark cyberpunk: neon cyan/magenta, full `colors` subset + SQL/JSON `tokenColors` |
| [cyberpunk-neon.jsonc](cyberpunk-neon.jsonc) | Same palette in JSONC (comments + trailing commas) |

After import, pick **Imported: Querya Cyberpunk Neon** in **Color preset**.

**Quick test SQL** (syntax colors):

```sql
-- neon comment
SELECT id, name
FROM users
WHERE active = true AND score > 42;
```
