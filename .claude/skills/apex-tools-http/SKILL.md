---
name: apex-tools-http
description: Apex HTTP callouts through ApexTools' IHttpRequestHandler (HttpRequestHandler in production, MockHttpRequestHandler in tests), so tests need no HttpCalloutMock. Use when writing or testing callout code in a project that contains HttpRequestHandler.cls, including injecting IHttpRequestHandler through a constructor, label() / send() / getStatusCode() / getBody() / getBodyAsBlob() / getHeader(), declaring responses with MockResponse.of(method).respond(body, statusCode) / header() / repeat() / fail(), script mode versus label mode with attach(), asserting with countByMethod / requestsTo / sentRequestsAt / lastRequest / sentRequests, retries, branch flows, Content-Type checks on binary responses, and errors such as "Next queued response expects GET", "No mock response available for", "send() was called without label()", "has no attached responses", "Cannot mix attach() with constructor responses", "must be the last one in its queue", "a rule either answers or fails", "has no content", or a JSONException "No response available". Not for editing ApexTools' own source.
---

# ApexTools: HTTP callouts and MockHttpRequestHandler

`IHttpRequestHandler` wraps one callout at a time: `send()` a request, then read the response with the getters. `HttpRequestHandler` is the production implementation over the standard `Http` class. `MockHttpRequestHandler` is the test double: it answers from `MockResponse` rules, checks the HTTP method of every request against them, and records what was sent. Code that takes an `IHttpRequestHandler` needs no `HttpCalloutMock`.

## Rules

1. Depend on `IHttpRequestHandler`. Accept it through a constructor and fall back to `new HttpRequestHandler()` when it is `null`.
2. One handler can serve every callout of a class. Before each `send()`, name the callout site with `label(...)` using a `@TestVisible` constant.
3. Read the response only after a `send()` that returned normally. Check `getStatusCode()` before the body.
4. For binary bodies, also check `getHeader('Content-Type')` before `getBodyAsBlob()`. A wrong endpoint often answers 200 with JSON.
5. In tests, build responses with `MockResponse.of(method)` and `respond(...)` or `fail(...)`. Every rule needs one of the two, not both.
6. Use script mode when the order of callouts is part of what the test asserts. Use label mode otherwise. If unsure, use label mode.
7. Use the label constants of the production class in tests. Don't retype label strings.
8. Write test descriptions and assert messages in the language the project's tests already use (see "Test descriptions").

## IHttpRequestHandler

| Method | Notes |
|---|---|
| `IHttpRequestHandler label(String label)` | Names the next `send()`. `HttpRequestHandler` ignores it. Returns the handler, so chain `send` on it |
| `void send(HttpRequest request)` | Sends the request. A failed send throws `CalloutException` |
| `Integer getStatusCode()` | Status of the last response |
| `String getBody()` | Body as text |
| `Blob getBodyAsBlob()` | Body as bytes (images, PDFs) |
| `String getHeader(String name)` | A response header |

With no response to read (before the first `send()`, or after a `send()` that threw), `HttpRequestHandler` getters return `null` and `MockHttpRequestHandler` getters throw `JSONException` ("No response available"). A test therefore catches code that reads a response that doesn't exist.

## Production code

```apex
public with sharing class ContactSyncService {
  @TestVisible
  private static final String LBL_FIND = 'find';
  @TestVisible
  private static final String LBL_CREATE = 'create';
  @TestVisible
  private static final String LBL_UPDATE = 'update';

  private final Contact contact;
  private final IHttpRequestHandler http;

  public ContactSyncService(Contact contact) {
    this(contact, null);
  }

  @TestVisible
  private ContactSyncService(Contact contact, IHttpRequestHandler http) {
    this.contact = contact;
    this.http = http ?? new HttpRequestHandler();
  }

  public void sync() {
    this.http.label(LBL_FIND).send(this.request('GET', '/contacts/' + this.contact.Id, null));
    Integer status = this.http.getStatusCode();
    if (status == 404) {
      this.http.label(LBL_CREATE).send(this.request('POST', '/contacts', JSON.serialize(this.contact)));
    } else if (status == 200) {
      this.http.label(LBL_UPDATE).send(this.request('PUT', '/contacts/' + this.contact.Id, JSON.serialize(this.contact)));
    } else {
      throw new CalloutException('Lookup failed with status ' + status);
    }
  }

  private HttpRequest request(String method, String path, String body) {
    HttpRequest request = new HttpRequest();
    request.setMethod(method);
    request.setEndpoint('callout:ContactApi' + path);
    if (body != null) {
      request.setBody(body);
    }
    return request;
  }
}
```

Binary response with a Content-Type check:

```apex
this.http.label(LBL_IMAGE).send(imageRequest);
String contentType = this.http.getHeader('Content-Type');
if (this.http.getStatusCode() != 200 || contentType == null || !contentType.startsWith('image/')) {
  throw new CalloutException('Expected an image, got ' + this.http.getStatusCode() + ' ' + contentType);
}
Blob image = this.http.getBodyAsBlob();
```

## MockResponse

```apex
MockResponse.of('GET').respond('{"message":"not found"}', 404)            // String body
MockResponse.of('DELETE').respond((String) null, 204)                    // empty body: cast null, a bare null is ambiguous
MockResponse.of('post').respond(new Map<String, Object>{ 'id' => 1 }, 201) // Map or List: JSON-serialized
MockResponse.of('GET').respond(imageBytes, 200).header('Content-Type', 'image/png') // Blob body + header
MockResponse.of('GET').respond('{"ok":true}', 200).repeat()               // answers every further request
MockResponse.of('GET').fail('Read timed out')                             // send() throws CalloutException
```

- The method is case-insensitive: `'GET'`, `'get'` and `'Get'` are the same.
- `header()` lookups are case-insensitive. An unset header reads as `null`.
- A text body can be read with `getBodyAsBlob()` (`Blob.valueOf`). A Blob body read with `getBody()` is `toString()`-ed, so read real binary with `getBodyAsBlob()`.
- `repeat()` must be the last rule in its queue. Once reached, it answers every further request in that queue, as long as the method matches.
- `fail(message)`: `send()` records the request, moves on in the queue and throws `CalloutException(message)`. Getters then throw `JSONException`.
- `respond()` and `fail()` on the same rule throw `IllegalArgumentException` ("a rule either answers or fails"). Null status code, null Blob / Map / List body, blank method, blank header name and blank failure message are refused too.

### The method is a contract

Each rule declares the method it answers. If the next rule in the queue declares a different method than the request, `send()` throws `CalloutException` ("Next queued response expects GET, but the request was: POST ...", with scope and queue position). The rule is not consumed and the request is not recorded. A flow that takes the wrong branch fails loudly instead of receiving the wrong response.

## Script mode: the order is the test

Pass the rules to the constructor. They are consumed strictly in order, so the list reads as the expected callout sequence.

```apex
MockHttpRequestHandler mock = new MockHttpRequestHandler(new List<MockResponse>{
  MockResponse.of('GET').respond('{"message":"not found"}', 404),   // 1st: lookup
  MockResponse.of('POST').respond('{"id":"c-1"}', 201)              // 2nd: create
});
// or one rule: new MockHttpRequestHandler(MockResponse.of('GET').respond('{}', 200))
```

- Retries are repeated rules: `500, 500, 200` on three `POST` rules tests "succeeds on the third try". The mock needs no counter.
- In script mode `label()` is ignored. Labeled production code can be tested with a plain script.
- One request too many fails with "No mock response available for: ...", unless the last rule has `repeat()`.

## Label mode: one queue per callout site

Attach rules under labels. Order between sites doesn't matter; within one label the queue is that site's own sequence (for example its retries). Attaching to the same label again appends to its queue.

```apex
@IsTest
private class ContactSyncServiceTest {
  @IsTest
  static void createsWhenNotFound() {
    Contact contact = new Contact(Id = '003000000000001', LastName = 'Smith');
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .attach(ContactSyncService.LBL_FIND, MockResponse.of('GET').respond('{"message":"not found"}', 404))
      .attach(ContactSyncService.LBL_CREATE, MockResponse.of('POST').respond('{"id":"c-1"}', 201))
      .attach(ContactSyncService.LBL_UPDATE, MockResponse.of('PUT').respond('{}', 200));

    Test.startTest();
    new ContactSyncService(contact, mock).sync();
    Test.stopTest();

    Assert.areEqual(1, mock.sentRequestsAt(ContactSyncService.LBL_CREATE).size(), 'Normal: an unknown contact is created');
    Assert.areEqual(0, mock.sentRequestsAt(ContactSyncService.LBL_UPDATE).size(), 'Normal: an unknown contact is not updated');
    Assert.isTrue(
      mock.sentRequestsAt(ContactSyncService.LBL_FIND)[0].getEndpoint().endsWith(contact.Id),
      'Normal: the lookup uses the contact Id'
    );
  }
}
```

- Attach both branches of a branch flow, then assert which one was consumed.
- Once anything is attached, every `send()` needs a `label()` first. The label is used by one `send()` only.
- An unknown label fails with "Label 'x' has no attached responses" and lists the registered labels.
- `attach()` after constructor rules throws `IllegalArgumentException` ("Cannot mix attach() with constructor responses").

## Asserting what was sent

| Method | Returns |
|---|---|
| `countByMethod(String method)` | Number of sent requests with that method (case-insensitive) |
| `requestsTo(String endpointPart)` | Sent requests whose endpoint contains the text (case-sensitive), in send order |
| `sentRequestsAt(String label)` | Requests sent under the label, in send order. Label mode only |
| `lastRequest()` | The last sent request, or `null` |
| `sentRequests` | All sent requests (`@TestVisible` field) |

Check the request body with `getBody()` on the recorded `HttpRequest`, for example `JSON.deserializeUntyped(mock.lastRequest().getBody())`.

## Testing failures

```apex
Contact contact = new Contact(Id = '003000000000001', LastName = 'Smith');
MockHttpRequestHandler mock = new MockHttpRequestHandler(new List<MockResponse>{
  MockResponse.of('GET').fail('Read timed out')
});

try {
  new ContactSyncService(contact, mock).sync();
  Assert.fail('Error: a timeout must reach the caller');
} catch (CalloutException e) {
  Assert.areEqual('Read timed out', e.getMessage(), 'Error: the timeout message is kept');
}
```

The mock reports contract errors (wrong method, empty queue, missing or unknown label) as `CalloutException` too. If the code under test catches `CalloutException` to handle timeouts, it also swallows a mismatch between the script and the flow. In such tests, assert what was sent (`countByMethod`, `sentRequestsAt`) as well as the outcome.

## Test descriptions

Write test descriptions and assert messages in the language the project's tests already use, and keep its case labels: `Normal:` / `Error:` / `Edge:` in English projects, `正常系:` / `異常系:` / `エッジケース:` in Japanese ones.

## Common mistakes

| Symptom | Cause | Fix |
|---|---|---|
| "Methods defined as TestMethod do not support Web service callouts" | Test used the production `HttpRequestHandler` | Pass a `MockHttpRequestHandler` through the constructor |
| "Next queued response expects GET, but the request was: POST ..." | Flow order or branch differs from the script | Fix the code, or the script if the script was wrong |
| "No mock response available for: ..." | More requests than rules in the queue | Add rules, or end the queue with `repeat()` |
| "send() was called without label()" | Label mode, and the code sent without `label()` | Call `this.http.label(LBL_X).send(request)` |
| "Label 'x' has no attached responses" | Typo, or the label was never attached | Use the production class's label constants |
| "Cannot mix attach() with constructor responses" | Script rules plus `attach()` | Pick one mode |
| "A repeat() response must be the last one in its queue" | Rule added after a `repeat()` rule | Move `repeat()` to the last rule |
| "MockResponse for method 'get' has no content" | `MockResponse.of(...)` without `respond` / `fail` | Add `respond(...)` or `fail(...)` |
| "Ambiguous method signature: void respond(NULL, Integer)" | `respond(null, 204)` matches the String, Blob, Map and List overloads | Write `respond((String) null, 204)` |
| `JSONException`: "No response available" | Getter called before `send()`, or after a `send()` that threw | Read the response only after a successful `send()` |
| `sentRequestsAt(label)` is empty although the request was sent | Script mode doesn't record labels | Use label mode, or `requestsTo` / `countByMethod` |
| Getter returns `null` in production after a failure | The failed `send()` cleared the previous response | Catch the `CalloutException`; don't read the getters after it |
| Corrupt image saved, status 200 | Endpoint returned JSON or HTML | Check `Content-Type` before `getBodyAsBlob()` |
