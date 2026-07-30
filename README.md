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

Two complementary modes:

### Ordered mode — for retry / pagination tests

Responses are consumed positionally, one per `send()`:

```apex
MockHttpRequestHandler mock = new MockHttpRequestHandler(new List<Map<String, Object>>{
  new Map<String, Object>{ 'body' => '{"status":"pending"}', 'statusCode' => 202 },
  new Map<String, Object>{ 'body' => '{"status":"done"}', 'statusCode' => 200 }
});
```

### Matching mode — for multi-callout flows

Responses are selected by request matching, regardless of call order. Matchers are evaluated in registration order (first match wins) and non-matching requests fall back to the ordered queue:

```apex
MockHttpRequestHandler mock = new MockHttpRequestHandler()
  .when().method('GET').endpointContains('/records.json').respond(existsBody, 200)
  .when().method('POST').respond(createdBody, 200)
  .when().method('PUT').respond('{"message":"bad request"}', 400);

new KintoneUpsertUsecase(input, mock).invoke();

Assert.areEqual(1, mock.countByMethod('POST'));   // verification helpers
Assert.areEqual(0, mock.countByMethod('PUT'));
```

- Criteria: `method()` / `endpointContains()` / `endpointEquals()` / `bodyContains()` — AND-combined
- A matched response is **sticky** (returned every time). Chain `.thenRespond(...)` for a per-matcher sequence whose last response sticks (e.g. GET → 404 first, then 200)
- Conditions the builder cannot express: implement `IRequestMatcher` and pass it to `when(matcher)`
- Verification helpers over `sentRequests`: `countByMethod(method)` / `requestsTo(endpointPart)` / `lastRequest()`
- When no response is available, the error lists the actual request, all registered matchers, and the queue state — no more guessing why `No more responses configured` happened
