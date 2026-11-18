# ApexTools

**Small, dependency-free building blocks for Salesforce Apex projects.**



📚 **Documentation: [krileworks.com](https://krileworks.com/apex-stem/docs/apex-tools-guide)** — guides, API reference, and design deep-dives all live there.
(日本語ドキュメント: [https://krileworks.com/ja/apex-stem/docs/apex-tools-guide](https://krileworks.com/ja/apex-stem/docs/apex-tools-guide))

ApexTools is part of [**Apex Stem**](https://krileworks.com/apex-stem), a set of independent, dependency-free Salesforce Apex frameworks.

## Installation

### A) Unlocked Package (recommended)

```bash
sf package install -p 04tgK000000b1YDQAY -o <your-org> -w 10
```

Or install from the browser:

- Production / Developer Edition: `https://login.salesforce.com/packaging/installPackage.apexp?p0=04tgK000000b1YDQAY`
- Sandbox: `https://test.salesforce.com/packaging/installPackage.apexp?p0=04tgK000000b1YDQAY`

Current version: **v1.2.1** (`04tgK000000b1YDQAY`). Install IDs for every release are listed on the [Releases](https://github.com/krile136/ApexTools/releases) page.

Why the package: tests inside an installed unlocked package are **excluded from `RunLocalTests`**, and its code is **excluded from your org's coverage calculation** — your deploys stay fast and unaffected by this framework's test suite.

### B) Git Submodule

```bash
git submodule add https://github.com/krile136/ApexTools.git force-app/main/default/classes/ApexTools
git submodule update --init --recursive
```

`sf project deploy start -d force-app/main/default/classes/ApexTools` deploys it like any source folder.

## AI agents

This repository ships agent skills and a rule for [Claude Code](https://claude.com/claude-code) under `.claude/`:

| Path | Purpose |
|---|---|
| `.claude/rules/apex-tools.md` | Short rules applied to `*.cls` and `*.trigger` files: one-line triggers, thin handlers on `TriggerHandler`, change helpers instead of hand-written comparisons, callouts through an injected `IHttpRequestHandler` |
| `.claude/skills/apex-tools-trigger-handler/` | Trigger files, `TriggerHandler` hooks, the change helpers and their behavior outside update, testing handlers |
| `.claude/skills/apex-tools-http/` | `IHttpRequestHandler` in production code, `MockResponse`, script and label modes of `MockHttpRequestHandler`, spies, simulated failures |

The skills describe the version of the tag they come from. After you upgrade ApexTools, update the skills from the matching tag too.

### Git submodule or clone

The files are already in your project inside the ApexTools folder. Claude Code picks them up once it reads a file in that folder. Nothing to copy.

### Unlocked package

The package installs only Apex classes. Copy the skills and the rule from the git tag that matches your installed version (replace `v1.2.1` with it):

```bash
rm -rf /tmp/apex-tools
git clone --depth 1 --branch v1.2.1 https://github.com/krile136/ApexTools.git /tmp/apex-tools
mkdir -p .claude/skills .claude/rules
cp -r /tmp/apex-tools/.claude/skills/* .claude/skills/
cp /tmp/apex-tools/.claude/rules/apex-tools.md .claude/rules/
```

Run it from your project root. It overwrites earlier copies of these skills and leaves your other skills alone.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
