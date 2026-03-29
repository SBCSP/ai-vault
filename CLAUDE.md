# AI VaultIO - Claude Code Notes

## Releasing a New Version

To release a new version, three things must be updated:

1. **`pubspec.yaml`** — Update the `version:` field (e.g., `version: 1.1.0+2`)
2. **`lib/providers/version_provider.dart`** — Update the `appVersion` constant to match (e.g., `const String appVersion = '1.1.0';`). This is what displays in the app bar.
3. **Git tag + push** — Tag the commit and push the tag to trigger the GitHub Actions release workflow:
   ```bash
   git tag v1.1.0
   git push origin v1.1.0
   ```

The workflow at `.github/workflows/release-macos.yml` triggers on `v*` tags, builds a macOS `.dmg`, and publishes it as a GitHub Release. The release version comes from the git tag (`GITHUB_REF_NAME`), not from `pubspec.yaml`.

## Build Commands

- `flutter pub get` — Install dependencies
- `flutter build macos` — Build macOS app
- `scripts/build_dmg.sh` — Build local .dmg with ad-hoc code signing

## Database Migrations

Schema version is in `lib/database/database.dart` (`schemaVersion`). When adding a new table or column, bump the version and add a migration in `_onUpgrade`. Current schema version: **10**.

## Architecture

- **State management**: Riverpod (`StateNotifierProvider`, `StreamProvider`, `Provider`)
- **Database**: Drift ORM with SQLite
- **Encryption**: `EncryptionService` encrypts sensitive fields (secret values, note/idea bodies)
- **Audit logging**: `AuditLogger` class injected into action providers; auth events logged from `lock_screen.dart` to avoid circular dependencies
- **MCP client**: `McpService` manages connections to MCP servers via `mcp_dart` package; tools are passed to Ollama's `/api/chat` as function-calling tools; tool call results loop back to the LLM

## Wiki Maintenance

The in-app wiki lives in `wiki/` and is bundled as a Flutter asset. The wiki index is `wiki/wiki.json`. **Whenever you change code — adding features, modifying behavior, changing settings, updating configurations, or fixing bugs — you MUST update the relevant wiki pages to stay in sync.** This includes:

- **New features**: Add a new markdown page under the appropriate section and register it in `wiki/wiki.json`.
- **Changed behavior**: Update the wiki page that documents the affected feature.
- **New settings/configuration**: Document them in the relevant wiki page (e.g., `wiki/features/` or `wiki/advanced/`).
- **Removed features**: Remove or update the corresponding wiki page and its entry in `wiki/wiki.json`.
- **Version bumps**: Update `wiki/advanced/changelog.md` with a summary of what changed.

The wiki is indexed for RAG so users can ask the LLM about app features. Stale wiki content means the LLM gives wrong answers. Keep it accurate.
