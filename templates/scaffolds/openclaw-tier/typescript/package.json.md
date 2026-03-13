# package.json.md

Template for the Full/TypeScript (OpenClaw-tier) scaffold.

## Generated File: `package.json`

```json
{
  "name": "{{PROJECT_NAME}}",
  "version": "0.1.0",
  "description": "{{PROJECT_DESCRIPTION}}",
  "type": "module",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "engines": {
    "node": ">=20.0.0"
  },
  "scripts": {
    "start": "node dist/index.js",
    "build": "tsc --project tsconfig.json",
    "dev": "tsx watch src/index.ts",
    "test": "vitest run",
    "test:watch": "vitest",
    "test:coverage": "vitest run --coverage",
    "lint": "eslint 'src/**/*.ts' 'tests/**/*.ts'",
    "lint:fix": "eslint 'src/**/*.ts' 'tests/**/*.ts' --fix",
    "format": "prettier --check 'src/**/*.ts' 'tests/**/*.ts'",
    "format:fix": "prettier --write 'src/**/*.ts' 'tests/**/*.ts'",
    "typecheck": "tsc --noEmit",
    "migrate": "tsx src/storage/migrate.ts",
    "migrate:create": "tsx src/storage/migrate.ts create",
    "docker:build": "docker compose build",
    "docker:up": "docker compose up -d",
    "docker:down": "docker compose down",
    "clean": "rm -rf dist coverage .tsbuildinfo"
  },
  "dependencies": {
    "@anthropic-ai/sdk": "^0.39.0",
    "openai": "^4.78.0",
    "zod": "^3.24.0",
    "yaml": "^2.6.0",
    "pino": "^9.6.0",
    "pino-pretty": "^13.0.0",
    "@opentelemetry/api": "^1.9.0",
    "@opentelemetry/sdk-node": "^0.57.0",
    "@opentelemetry/exporter-trace-otlp-http": "^0.57.0",
    "@opentelemetry/exporter-metrics-otlp-http": "^0.57.0",
    "better-sqlite3": "^11.7.0",
    "pg": "^8.13.0",
    "express": "^4.21.0",
    "ws": "^8.18.0",
    "cors": "^2.8.5",
    "helmet": "^8.0.0",
    "dotenv": "^16.4.0",
    "nanoid": "^5.0.0",
    "p-retry": "^6.2.0",
    "p-queue": "^8.0.0",
    "eventemitter3": "^5.0.0"
  },
  "devDependencies": {
    "typescript": "^5.7.0",
    "tsx": "^4.19.0",
    "vitest": "^2.1.0",
    "@vitest/coverage-v8": "^2.1.0",
    "eslint": "^9.17.0",
    "@eslint/js": "^9.17.0",
    "typescript-eslint": "^8.18.0",
    "prettier": "^3.4.0",
    "@types/node": "^22.10.0",
    "@types/express": "^5.0.0",
    "@types/ws": "^8.5.0",
    "@types/better-sqlite3": "^7.6.0",
    "@types/pg": "^8.11.0",
    "@types/cors": "^2.8.0",
    "msw": "^2.7.0",
    "testcontainers": "^10.16.0"
  }
}
```

## Generated File: `tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Node16",
    "moduleResolution": "Node16",
    "lib": ["ES2022"],
    "outDir": "dist",
    "rootDir": "src",
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noPropertyAccessFromIndexSignature": true,
    "exactOptionalPropertyTypes": false,
    "forceConsistentCasingInFileNames": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "verbatimModuleSyntax": true
  },
  "include": ["src/**/*.ts"],
  "exclude": ["node_modules", "dist", "tests"]
}
```

## Placeholders

| Placeholder | Description |
|-------------|-------------|
| `{{PROJECT_NAME}}` | NPM package name (kebab-case, e.g. `my-agent`) |
| `{{PROJECT_DESCRIPTION}}` | One-line description shown in `npm info` and the repo |
