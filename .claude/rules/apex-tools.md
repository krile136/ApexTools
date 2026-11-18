---
paths: ["**/*.cls", "**/*.trigger"]
---

# ApexTools

This project uses ApexTools for trigger handlers (`TriggerHandler.cls`) and HTTP callouts (`IHttpRequestHandler`, `HttpRequestHandler`, `MockHttpRequestHandler`, `MockResponse`).

- A trigger declares all seven events and contains one line: `new <Object>TriggerHandler().execute();`. Put no logic in the trigger file.
- A handler `extends TriggerHandler` and overrides only the hooks it needs, as `protected override void`. Keep hooks thin: pick the records, then call a class that does the work.
- To act only when fields changed, use `getUpdatedRecordsWithChangedField(s)` or `getUpdateRecordIdsWithChangedField(s)` in update hooks. Don't hand-write old/new comparison loops.
- Code that makes callouts depends on `IHttpRequestHandler`, accepts it through a constructor and falls back to `new HttpRequestHandler()` when it is `null`. Don't call `new Http().send(...)` directly.
- Unit tests pass a `MockHttpRequestHandler` built from `MockResponse` rules. Don't write `HttpCalloutMock` classes for code that takes an `IHttpRequestHandler`.
- Check `getStatusCode()` (and `getHeader('Content-Type')` for binary bodies) before reading the body.
- Write test descriptions and assert messages in the language the project's tests already use, and keep its case labels (for example `正常系:` / `異常系:` / `エッジケース:`, or `Normal:` / `Error:` / `Edge:`).
- Before writing code, load the matching skill: `apex-tools-trigger-handler` for triggers and handlers, `apex-tools-http` for callouts and their tests.

These rules don't apply to ApexTools' own source and tests (`TriggerHandler/`, `HttpRequest/` and their test classes).
