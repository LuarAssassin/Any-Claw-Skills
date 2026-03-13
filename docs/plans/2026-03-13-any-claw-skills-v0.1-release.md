# any-claw-skills v0.1 Release Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reframe `any-claw-skills` into a Claude Code first, publishable v0.1 skill package with a clear golden path, support matrix, release docs, and repeatable verification.

**Architecture:** Keep the repository as a `skills + commands + templates + docs + tests` package, not a generator program. Concentrate release quality on one verified golden path while documenting Beta and Preview surfaces explicitly. Upgrade docs, skill contracts, examples, and release verification in layers so the repo reads like a real product.

**Tech Stack:** Markdown, JSON, shell scripts, GitHub Actions, Claude plugin metadata

---

### Task 1: Establish planning and release doc structure

**Files:**
- Create: `docs/plans/2026-03-13-any-claw-skills-v0.1-design.md`
- Create: `docs/plans/2026-03-13-any-claw-skills-v0.1-release.md`
- Create: `docs/release-checklist.md`
- Create: `docs/support-matrix.md`
- Create: `docs/domain-pack-contract.md`
- Test: `tests/run-all.sh`

**Step 1: Write the failing test**

Define the expected release docs inventory in the checklist:

```text
- docs/release-checklist.md exists
- docs/support-matrix.md exists
- docs/domain-pack-contract.md exists
```

**Step 2: Run test to verify it fails**

Run:

```bash
test -f docs/release-checklist.md && test -f docs/support-matrix.md && test -f docs/domain-pack-contract.md
```

Expected: shell exits non-zero because the files do not exist yet.

**Step 3: Write minimal implementation**

Create the missing docs with narrow v0.1 content:

- release checklist focused on Claude Code first verification
- support matrix with GA/Beta/Preview rows
- domain pack contract covering required files, optional MCP, env vars, integration points, and safety notes

**Step 4: Run test to verify it passes**

Run:

```bash
test -f docs/release-checklist.md && test -f docs/support-matrix.md && test -f docs/domain-pack-contract.md
```

Expected: command succeeds with exit code `0`.

**Step 5: Commit**

```bash
git add docs/plans/2026-03-13-any-claw-skills-v0.1-design.md docs/plans/2026-03-13-any-claw-skills-v0.1-release.md docs/release-checklist.md docs/support-matrix.md docs/domain-pack-contract.md
git commit -m "docs: add v0.1 release planning documents"
```

### Task 2: Reframe the release-facing repository docs

**Files:**
- Modify: `README.md`
- Modify: `STATUS.md`
- Modify: `RELEASE-NOTES.md`
- Create: `CONTRIBUTING.md`
- Create: `CODE_OF_CONDUCT.md`
- Create: `SECURITY.md`
- Test: `docs/support-matrix.md`

**Step 1: Write the failing test**

List the required README sections for v0.1:

```text
What it is
Claude Code first
Golden path
Install
Quick start
Support matrix
Roadmap
```

**Step 2: Run test to verify it fails**

Run:

```bash
rg -n "Claude Code first|Golden Path|Support Matrix|Roadmap" README.md
```

Expected: missing at least one required section.

**Step 3: Write minimal implementation**

- Rewrite `README.md` into a publishable landing page
- Convert `STATUS.md` from file-count tracking to release-readiness tracking
- Rewrite `RELEASE-NOTES.md` to describe v0.1 intent and release scope
- Add contributor, conduct, and security docs with concise maintainer guidance

**Step 4: Run test to verify it passes**

Run:

```bash
rg -n "Claude Code first|Golden Path|Support Matrix|Roadmap" README.md
rg -n "GA|Beta|Preview|Blockers" STATUS.md
```

Expected: both commands return matches for the new release framing.

**Step 5: Commit**

```bash
git add README.md STATUS.md RELEASE-NOTES.md CONTRIBUTING.md CODE_OF_CONDUCT.md SECURITY.md
git commit -m "docs: reframe any-claw-skills for v0.1 release"
```

### Task 3: Tighten Claude Code plugin metadata and release consistency

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Possibly modify: `gemini-extension.json`
- Test: `README.md`

**Step 1: Write the failing test**

Define a version string target and required description alignment:

```json
{
  "version": "0.1.0",
  "description": "Claude Code first domain-oriented assistant builder"
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
node -e "const fs=require('fs'); const p=JSON.parse(fs.readFileSync('.claude-plugin/plugin.json','utf8')); const m=JSON.parse(fs.readFileSync('.claude-plugin/marketplace.json','utf8')); if(p.version!==m.plugins[0].version) process.exit(1)"
```

Expected: fail if versions drift or descriptions remain misaligned with v0.1 positioning.

**Step 3: Write minimal implementation**

- Align plugin metadata wording with the release framing
- Ensure version values and core descriptions match across plugin files
- Only update non-Claude metadata if the new wording would otherwise contradict README claims

**Step 4: Run test to verify it passes**

Run:

```bash
node -e "const fs=require('fs'); const p=JSON.parse(fs.readFileSync('.claude-plugin/plugin.json','utf8')); const m=JSON.parse(fs.readFileSync('.claude-plugin/marketplace.json','utf8')); if(p.version!==m.plugins[0].version) process.exit(1); console.log(p.version)"
```

Expected: command prints the aligned version and exits successfully.

**Step 5: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json gemini-extension.json
git commit -m "meta: align plugin metadata for v0.1"
```

### Task 4: Rework the meta skill and builder around support tiers

**Files:**
- Modify: `skills/using-any-claw-skills/SKILL.md`
- Modify: `skills/build-assistant/SKILL.md`
- Modify: `skills/build-assistant/complexity-tiers.md`
- Modify: `skills/build-assistant/stack-selection.md`
- Modify: `skills/build-assistant/project-structure.md`
- Modify: `skills/build-assistant/config-templates.md`
- Test: `tests/skill-triggering/run-test.sh`
- Test: `tests/wizard-flow/run-test.sh`

**Step 1: Write the failing test**

Add required v0.1 expectations:

```text
- The meta skill states Claude Code first positioning
- The builder recommends the golden path
- The builder explains GA/Beta/Preview choices
```

**Step 2: Run test to verify it fails**

Run:

```bash
rg -n "Claude Code first|golden path|GA|Beta|Preview" skills/using-any-claw-skills/SKILL.md skills/build-assistant/SKILL.md
```

Expected: at least one required phrase is missing.

**Step 3: Write minimal implementation**

- Update the meta skill to explain package scope and routing
- Update the builder skill so the default recommendation favors the GA path
- Add support-tier language to the builder references and structure docs
- Keep the package template-driven rather than turning the skill into a generator spec

**Step 4: Run test to verify it passes**

Run:

```bash
rg -n "Claude Code first|golden path|GA|Beta|Preview" skills/using-any-claw-skills/SKILL.md skills/build-assistant/SKILL.md
```

Expected: all framing terms appear in the skill docs.

**Step 5: Commit**

```bash
git add skills/using-any-claw-skills/SKILL.md skills/build-assistant/SKILL.md skills/build-assistant/complexity-tiers.md skills/build-assistant/stack-selection.md skills/build-assistant/project-structure.md skills/build-assistant/config-templates.md
git commit -m "skills: center build flow on the v0.1 golden path"
```

### Task 5: Add support-tier guardrails to extension skills

**Files:**
- Modify: `skills/add-domain/SKILL.md`
- Modify: `skills/add-domain/domain-catalog.md`
- Modify: `skills/add-channel/SKILL.md`
- Modify: `skills/add-channel/channel-matrix.md`
- Modify: `skills/add-provider/SKILL.md`
- Modify: `skills/add-provider/provider-matrix.md`
- Modify: `skills/add-tool/SKILL.md`
- Modify: `skills/add-tool/tool-patterns.md`
- Test: `tests/skill-triggering/run-test.sh`

**Step 1: Write the failing test**

Document the expected extension flow behavior:

```text
- Inspect the current project contract first
- Mention support tiers before recommending unstable additions
- Keep generated-project assumptions explicit
```

**Step 2: Run test to verify it fails**

Run:

```bash
rg -n "support tier|generated project|inspect.*project|contract" skills/add-*/SKILL.md
```

Expected: missing guidance in one or more extension skills.

**Step 3: Write minimal implementation**

- Add inspection and compatibility checks to each extension skill
- Make support-tier messaging explicit in reference matrices
- Keep the instructions focused on expanding a project produced by `any-claw-skills`

**Step 4: Run test to verify it passes**

Run:

```bash
rg -n "support tier|generated project|inspect.*project|contract" skills/add-*/SKILL.md
```

Expected: each extension skill shows the new guardrails.

**Step 5: Commit**

```bash
git add skills/add-domain/SKILL.md skills/add-domain/domain-catalog.md skills/add-channel/SKILL.md skills/add-channel/channel-matrix.md skills/add-provider/SKILL.md skills/add-provider/provider-matrix.md skills/add-tool/SKILL.md skills/add-tool/tool-patterns.md
git commit -m "skills: add support-tier guardrails to extension flows"
```

### Task 6: Create a golden path example bundle

**Files:**
- Create: `docs/examples/golden-path-standard-python-productivity.md`
- Possibly create: `docs/examples/README.md`
- Reference: `templates/scaffolds/copaw-tier/python/`
- Reference: `templates/channels/cli.python.md`
- Reference: `templates/channels/telegram.python.md`
- Reference: `templates/providers/openai.python.md`
- Reference: `templates/domains/productivity/`
- Test: `docs/support-matrix.md`

**Step 1: Write the failing test**

Define the required example sections:

```text
scenario
selected options
generated tree
critical files
run steps
```

**Step 2: Run test to verify it fails**

Run:

```bash
test -f docs/examples/golden-path-standard-python-productivity.md
```

Expected: command fails because the example doc does not exist yet.

**Step 3: Write minimal implementation**

Document one concrete example outcome for the GA path:

- user choices
- resulting directory structure
- how scaffold, provider, channels, and domain pack fit together
- how a user would run and extend the generated project

**Step 4: Run test to verify it passes**

Run:

```bash
rg -n "Scenario|Selected Options|Generated Tree|Critical Files|Run Steps" docs/examples/golden-path-standard-python-productivity.md
```

Expected: the example doc contains every required section.

**Step 5: Commit**

```bash
git add docs/examples/golden-path-standard-python-productivity.md docs/examples/README.md
git commit -m "docs: add a golden path example bundle"
```

### Task 7: Restructure the test suite around release verification

**Files:**
- Modify: `tests/run-all.sh`
- Modify: `tests/skill-triggering/run-test.sh`
- Modify: `tests/wizard-flow/run-test.sh`
- Create: `tests/install-smoke/run-test.sh`
- Create: `tests/expansion-flow/run-test.sh`
- Create: `tests/docs-consistency/run-test.sh`
- Create: `docs/testing.md`

**Step 1: Write the failing test**

Define the expected suite names:

```text
install smoke
skill triggering
wizard flow
expansion flow
docs consistency
```

**Step 2: Run test to verify it fails**

Run:

```bash
find tests -maxdepth 2 -type f | sort
```

Expected: the new suite directories are missing.

**Step 3: Write minimal implementation**

- Create the missing test suite directories and scripts
- Update `tests/run-all.sh` to orchestrate the expanded verification flow
- Rewrite `docs/testing.md` so maintainers know what each suite proves
- Keep the suite honest: clearly separate manual, scripted, and CI-safe checks

**Step 4: Run test to verify it passes**

Run:

```bash
test -f tests/install-smoke/run-test.sh && test -f tests/expansion-flow/run-test.sh && test -f tests/docs-consistency/run-test.sh
bash tests/run-all.sh
```

Expected: the files exist and the orchestrator prints the new suite structure without shell errors.

**Step 5: Commit**

```bash
git add tests/run-all.sh tests/skill-triggering/run-test.sh tests/wizard-flow/run-test.sh tests/install-smoke/run-test.sh tests/expansion-flow/run-test.sh tests/docs-consistency/run-test.sh docs/testing.md
git commit -m "test: add release verification suites"
```

### Task 8: Add GitHub workflows and contribution templates

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `.github/ISSUE_TEMPLATE/bug_report.md`
- Create: `.github/ISSUE_TEMPLATE/feature_request.md`
- Create: `.github/pull_request_template.md`
- Possibly create: `.github/FUNDING.yml`
- Test: `tests/run-all.sh`

**Step 1: Write the failing test**

List required repo automation files:

```text
.github/workflows/ci.yml
.github/ISSUE_TEMPLATE/bug_report.md
.github/ISSUE_TEMPLATE/feature_request.md
.github/pull_request_template.md
```

**Step 2: Run test to verify it fails**

Run:

```bash
test -f .github/workflows/ci.yml && test -f .github/ISSUE_TEMPLATE/bug_report.md && test -f .github/ISSUE_TEMPLATE/feature_request.md && test -f .github/pull_request_template.md
```

Expected: command fails because the `.github` tree does not exist yet.

**Step 3: Write minimal implementation**

- Add a simple CI workflow that runs repository-safe verification scripts
- Add issue and PR templates aligned with the release support model
- Add funding config only if maintainer-facing branding warrants it

**Step 4: Run test to verify it passes**

Run:

```bash
test -f .github/workflows/ci.yml && test -f .github/ISSUE_TEMPLATE/bug_report.md && test -f .github/ISSUE_TEMPLATE/feature_request.md && test -f .github/pull_request_template.md
```

Expected: command succeeds with exit code `0`.

**Step 5: Commit**

```bash
git add .github/workflows/ci.yml .github/ISSUE_TEMPLATE/bug_report.md .github/ISSUE_TEMPLATE/feature_request.md .github/pull_request_template.md .github/FUNDING.yml
git commit -m "chore: add release workflow and contribution templates"
```

### Task 9: Verify release readiness and close the loop

**Files:**
- Modify: `STATUS.md`
- Modify: `RELEASE-NOTES.md`
- Test: `tests/run-all.sh`
- Test: `.claude-plugin/plugin.json`
- Test: `.claude-plugin/marketplace.json`

**Step 1: Write the failing test**

Define the final verification outputs:

```text
- release docs exist
- tests/run-all.sh executes cleanly
- plugin metadata versions match
- status board reflects current support levels
```

**Step 2: Run test to verify it fails**

Run:

```bash
bash tests/run-all.sh
node -e "const fs=require('fs'); const p=JSON.parse(fs.readFileSync('.claude-plugin/plugin.json','utf8')); const m=JSON.parse(fs.readFileSync('.claude-plugin/marketplace.json','utf8')); if(p.version!==m.plugins[0].version) process.exit(1)"
```

Expected: at least one check fails before the full release reshaping is done.

**Step 3: Write minimal implementation**

- Update status tracking to reflect actual release state
- Finalize release notes wording and version references
- Fix any inconsistencies discovered by the suite

**Step 4: Run test to verify it passes**

Run:

```bash
bash tests/run-all.sh
node -e "const fs=require('fs'); const p=JSON.parse(fs.readFileSync('.claude-plugin/plugin.json','utf8')); const m=JSON.parse(fs.readFileSync('.claude-plugin/marketplace.json','utf8')); if(p.version!==m.plugins[0].version) process.exit(1); console.log('metadata ok')"
```

Expected: the test runner completes without shell errors and the metadata check prints `metadata ok`.

**Step 5: Commit**

```bash
git add STATUS.md RELEASE-NOTES.md
git commit -m "release: prepare any-claw-skills v0.1"
```

## Notes for Execution

- This workspace currently is not inside a git repository, so the commit steps will need either a git-initialized checkout or should be skipped with that constraint documented.
- Keep implementation strictly repository-scoped: no standalone generator executable should be introduced.
- If any existing template claims stronger support than the new matrix allows, downgrade the docs before adding more scope.
