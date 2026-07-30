# ApexTools

Small, dependency-free building blocks for Salesforce Apex projects.

| Component | Purpose |
|---|---|
| `TriggerHandler/` | Trigger handler base class: override only the hooks you need (`beforeInsert` / `afterUpdate` / ...), plus helpers to pick records whose specific fields changed |
| `HttpRequest/` | HTTP callout DI trio: `IHttpRequestHandler` (interface) / `HttpRequestHandler` (production, thin `Http` wrapper) / `MockHttpRequestHandler` (test double — no `HttpCalloutMock` needed) |

## TriggerHandler

```apex
public with sharing class TriggerOppHandler extends TriggerHandler {
  protected override void afterUpdate(Map<Id, SObject> newMap, Map<Id, SObject> oldMap) {
    Set<Id> changedIds = this.getUpdateRecordIdsWithChangedFields(new List<SObjectField>{
      Opportunity.Amount, Opportunity.CloseDate
    });
    (new RecalculateUsecase(changedIds)).invoke();
  }
}
// trigger: (new TriggerOppHandler()).execute();
```

## MockHttpRequestHandler

Responses are declared as `MockResponse` rules and consumed as a **FIFO queue per HTTP method** — tests do not depend on the interleaving order of different callout kinds, while retries of the same method still consume in declared order:

```apex
MockHttpRequestHandler mock = new MockHttpRequestHandler(new List<MockResponse>{
  MockResponse.of('GET').respond('{"message":"not found"}', 404),   // 1st GET
  MockResponse.of('GET').respond(foundBody, 200),                   // 2nd GET
  MockResponse.of('POST').respond(createdMap, 200)                  // any POST (Map is JSON-serialized)
});

new KintoneUpsertUsecase(input, mock).invoke();

Assert.areEqual(1, mock.countByMethod('POST'));   // verification helpers
Assert.areEqual(0, mock.countByMethod('PUT'));
```

- `MockResponse.of(method)` is case-insensitive (`'GET'` / `'get'` both work); `respond()` accepts `String` / `Map<String, Object>` / `List<Object>` bodies
- **A response is consumed once.** When a method's queue is exhausted, `send()` fails with a detailed error (actual request + every queue's state) — call overruns are caught, not hidden
- `.repeat()` on the **last** response of a method makes it answer every further request (e.g. retry tests: fail once, then always succeed)

### Labels — multiple callout sites in one usecase

When one usecase talks to multiple endpoints/APIs, name each callout site with a label (mirroring `MockEloquent`). Production `HttpRequestHandler` ignores labels; the mock routes by them:

```apex
// usecase:
this.http.label(LBL_EXISTS).send(req);

// test:
MockHttpRequestHandler mock = new MockHttpRequestHandler()
  .attach(LBL_EXISTS, MockResponse.of('GET').respond(notFound, 404))
  .attach(LBL_CREATE, MockResponse.of('POST').respond(created, 200));

Assert.areEqual(1, mock.sentRequestsAt(LBL_CREATE).size());
```

- Once `attach()` is used, every `send()` must be preceded by `label()` (consumed per send). A typo'd label fails with the registered-label list
- Declared method vs actual request mismatches surface as errors (branch-bug detection): a `GET` arriving at a label that only declares `POST` fails loudly
- Without `attach()`, `label()` calls are ignored — labeled production code still works with a plain constructor mock
- Verification helpers over `sentRequests`: `countByMethod()` / `requestsTo(endpointPart)` / `sentRequestsAt(label)` / `lastRequest()`
