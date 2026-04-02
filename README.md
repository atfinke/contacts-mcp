# contacts-mcp

Local MCP server that exposes Apple Contacts data through a `Contacts.framework` helper app.

Built entirely by OpenAI GPT-5.4 via Codex.

## Install

```bash
git clone https://github.com/<your-account>/contacts-mcp.git
cd contacts-mcp
./bootstrap.sh
```

## Run

```bash
npm run start
```

## Permissions

Run `contacts_permissions` once with `prompt: true`.

The helper app is intended to be built with the project's normal code signing so macOS can attribute Contacts access to a stable app identity.

If the prompt does not appear from inside Codex, launch the helper app directly once:

```bash
open ContactsMCPHelperApp/build/Build/Products/Release/ContactsMCPHelperApp.app
```

When opened directly, the app will request Contacts access and show a status alert. After that initial grant, the MCP tools can read visible contacts normally.

Lookup behavior is intentionally narrow: `contacts_lookup_phone`, `contacts_lookup_email`, and `contacts_search_name` return zero or more ranked matches, `contacts_get_contact` fetches one unified contact by identifier, and the server does not expose any write path.

Phone lookup uses the framework predicate first, then falls back to canonical digit matching when needed. Email lookup uses the framework predicate first, then falls back to exact case-insensitive comparison.
Name search uses the framework name predicate first, then backfills ranked matches across full name, nickname, organization, and component fields when needed.

## MCP config

```json
{
  "mcpServers": {
    "contacts": {
      "command": "node",
      "args": ["/absolute/path/to/contacts-mcp/dist/index.js"],
      "env": {
        "CONTACTS_MCP_HELPER_APP_PATH": "/absolute/path/to/contacts-mcp/ContactsMCPHelperApp/build/Build/Products/Release/ContactsMCPHelperApp.app"
      }
    }
  }
}
```

## Verify

```bash
npm run verify
```
