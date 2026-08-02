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

Two modes, routed by **labels only** — the HTTP method on each `MockResponse` is a **declared contract**, checked against the actual request when the response is served.

### Script mode — the constructor list is the flow's script

Reading the list top to bottom IS the expected callout sequence. A request that deviates from the script (wrong order, wrong method) fails with a detailed error instead of silently receiving the wrong response:

```apex
MockHttpRequestHandler mock = new MockHttpRequestHandler(new List<MockResponse>{
  MockResponse.of('GET').respond('{"message":"not found"}', 404),   // 1st callout
  MockResponse.of('POST').respond(createdBody, 201),                // 2nd callout
  MockResponse.of('GET').respond(foundBody, 200)                    // 3rd callout
});
```

### Label mode — one queue per callout site

For multi-site and branch flows, name each callout site (mirroring `MockEloquent`). Cross-site call order does not matter; the queue within a label is that site's own sequence (e.g. retries):

```apex
// usecase:  this.http.label(LBL_EXISTS).send(req);
MockHttpRequestHandler mock = new MockHttpRequestHandler()
  .attach(LBL_EXISTS, MockResponse.of('GET').respond(notFound, 404))
  .attach(LBL_CREATE, MockResponse.of('POST').respond(created, 201))
  .attach(LBL_UPDATE, MockResponse.of('PUT').respond(updated, 200));   // the untaken branch may stay attached

new KintoneUpsertUsecase(input, mock).invoke();

Assert.areEqual(1, mock.sentRequestsAt(LBL_CREATE).size());   // assert which branch ran
Assert.areEqual(0, mock.sentRequestsAt(LBL_UPDATE).size());
```

- `MockResponse.of(method)` is case-insensitive; `respond()` accepts `String` / `Map<String, Object>` / `List<Object>` / `Blob` bodies
- **A response is consumed once.** Exhausted queues and method mismatches fail with the request, scope, and queue state — call overruns and wrong branches are caught, not hidden. A mismatch consumes nothing and records nothing
- `.repeat()` on the **last** response of a queue makes it answer every further request (retry tests: fail once, then always succeed)
- Once `attach()` is used, every `send()` needs a preceding `label()` (consumed per send). A typo'd label fails with the registered-label list. Without `attach()`, `label()` is ignored — labeled production code still works with a plain script mock
- Verification helpers over `sentRequests`: `countByMethod()` / `requestsTo(endpointPart)` / `sentRequestsAt(label)` / `lastRequest()`

### Binary bodies and headers

`MockResponse` can carry a `Blob` body and response headers, so binary endpoints (e.g. business-card images) stay inside the DI framework instead of falling back to a raw `new Http()`:

```apex
MockHttpRequestHandler mock = new MockHttpRequestHandler(
  MockResponse.of('GET').respond(imageBytes, 200).header('Content-Type', 'image/jpeg')
);
```

Recommended production guard — an HTTP 200 with the wrong Content-Type usually means the wrong endpoint (a real incident: `/bizCards/{id}` was called instead of `/bizCards/{id}/image`, returning JSON that was then base64-encoded as a broken image):

```apex
this.http.label(LBL_CARD_IMAGE).send(req);
String contentType = this.http.getHeader('Content-Type');
if (this.http.getStatusCode() == 200 && (contentType == null || !contentType.startsWith('image/'))) {
  throw new CalloutException('Expected an image response but got Content-Type=' + contentType);
}
Blob image = this.http.getBodyAsBlob();
```

`getBodyAsBlob()` falls back to `Blob.valueOf(stringBody)` for text-configured responses, and `getHeader()` is case-insensitive.
