# package.json.md

Template for the Nano/TypeScript tier scaffold.

## Generated File: `package.json`

```json
{
  "name": "{{PROJECT_NAME}}",
  "version": "0.1.0",
  "description": "{{PROJECT_DESCRIPTION}}",
  "private": true,
  "type": "module",
  "main": "dist/index.js",
  "scripts": {
    "start": "node dist/index.js",
    "build": "tsc",
    "dev": "tsx watch src/index.ts",
    "typecheck": "tsc --noEmit",
    "clean": "rm -rf dist"
  },
  "dependencies": {
    "dotenv": "^16.4.7"
  },
  "devDependencies": {
    "typescript": "^5.7.0",
    "tsx": "^4.19.0",
    "@types/node": "^22.10.0"
  },
  "engines": {
    "node": ">=20.0.0"
  }
}
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{PROJECT_NAME}}` | npm package name, lowercase with hyphens (e.g. `"my-assistant"`) |
| `{{PROJECT_DESCRIPTION}}` | One-line description of the project |

## Notes

- The `dependencies` block ships with only `dotenv`. The scaffold generator should append provider and channel SDKs based on the chosen provider/channel types (e.g. `openai`, `@anthropic-ai/sdk`, `discord.js`, `express`).
- `tsx` is used for development mode with watch/reload support.
- The project uses ES modules (`"type": "module"`).
- TypeScript is a dev dependency; the production artifact is compiled JS in `dist/`.
