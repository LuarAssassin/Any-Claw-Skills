# Testing

`any-claw-skills` uses a mixed verification model:

- scripted repository checks for metadata and docs consistency
- manual or semi-automated prompt flows for skill routing and scaffold validation

## Test Suites

| Suite | Type | Purpose |
|-------|------|---------|
| `tests/install-smoke/run-test.sh` | Scripted + manual notes | Check install metadata and docs are present |
| `tests/docs-consistency/run-test.sh` | Scripted | Check version alignment and release doc consistency |
| `tests/skill-triggering/run-test.sh` | Manual | Verify prompts trigger the intended skills |
| `tests/wizard-flow/run-test.sh` | Manual | Walk the builder through golden path and non-golden path scenarios |
| `tests/expansion-flow/run-test.sh` | Manual | Verify add-channel, add-domain, add-provider, add-tool flows |

## Recommended Verification Order

1. `bash tests/docs-consistency/run-test.sh`
2. `bash tests/install-smoke/run-test.sh`
3. `bash tests/run-all.sh`

## Metadata Consistency Check

```bash
node -e "const fs=require('fs'); const files=['.claude-plugin/plugin.json','.cursor-plugin/plugin.json','gemini-extension.json']; const versions=files.map(f=>JSON.parse(fs.readFileSync(f,'utf8')).version); const market=JSON.parse(fs.readFileSync('.claude-plugin/marketplace.json','utf8')).plugins[0].version; if(!versions.every(v=>v===market)) process.exit(1); console.log(market)"
```

Expected: prints one version string and exits successfully.

## Notes

- CI should run only repository-safe scripted checks.
- Manual prompt flows are still required before broadening GA claims.
