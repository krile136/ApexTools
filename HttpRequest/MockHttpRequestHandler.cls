/**
 * @description Test double for IHttpRequestHandler with two modes:
 *
 * 1. Script mode (no labels): the constructor list is the flow's script,
 *    consumed strictly in order — reading it top to bottom IS the expected
 *    callout sequence. Each MockResponse declares the HTTP method it expects,
 *    and a request that does not match the next queued response fails with a
 *    detailed error (no silent wrong-response delivery).
 *
 * <pre>
 * MockHttpRequestHandler mock = new MockHttpRequestHandler(new List&lt;MockResponse&gt;{
 *   MockResponse.of('GET').respond('{"message":"not found"}', 404),   // 1st callout
 *   MockResponse.of('POST').respond(createdBody, 201),                // 2nd callout
 *   MockResponse.of('GET').respond(foundBody, 200)                    // 3rd callout
 * });
 * </pre>
 *
 * 2. Label mode: each callout site gets its own named queue (mirroring
 *    MockEloquent's attach). Cross-site call order does not matter; the queue
 *    within a label is that site's own sequence (e.g. retries). Branch flows
 *    ("GET, then POST or PUT") attach both branches and assert which one was
 *    consumed via sentRequestsAt().
 *
 * <pre>
 * // usecase:  this.http.label(LBL_EXISTS).send(req);
 * MockHttpRequestHandler mock = new MockHttpRequestHandler()
 *   .attach(LBL_EXISTS, MockResponse.of('GET').respond(notFound, 404))
 *   .attach(LBL_CREATE, MockResponse.of('POST').respond(created, 201))
 *   .attach(LBL_UPDATE, MockResponse.of('PUT').respond(updated, 200));
 * </pre>
 *
 * A response is consumed once; an exhausted queue fails with a detailed error
 * (call overruns are caught, not hidden). Declare `.repeat()` on the last
 * response of a queue to make it answer every further request instead.
 *
 * Once attach() is used, every send() must be preceded by label() (the label
 * is consumed per send). Without attach(), label() calls are ignored, so
 * labeled production code can still be tested with a plain script mock.
 * @directory ApexTools/HttpRequest
 */
public with sharing class MockHttpRequestHandler implements IHttpRequestHandler {
  @TestVisible
  private List<HttpRequest> sentRequests = new List<HttpRequest>();
  private List<String> sentLabels = new List<String>();

  private ResponseQueue defaultQueue = new ResponseQueue();
  private Map<String, ResponseQueue> labelToQueue = new Map<String, ResponseQueue>();

  private MockResponse currentMockResponse;
  private String pendingLabel;

  /**
   * @description Creates an empty handler. Register responses with attach() (label mode).
   */
  public MockHttpRequestHandler() {
    this.currentMockResponse = null;
  }

  /**
   * @description Creates a handler whose script is a single response.
   *
   * @param response The mocked response.
   */
  public MockHttpRequestHandler(MockResponse response) {
    this.register(this.defaultQueue, response);
    this.currentMockResponse = null;
  }

  /**
   * @description Creates a handler whose script is the given response sequence,
   * consumed strictly in order.
   *
   * @param responses The mocked responses, in expected callout order.
   */
  public MockHttpRequestHandler(List<MockResponse> responses) {
    if (responses == null || responses.isEmpty()) {
      throw new IllegalArgumentException('Responses cannot be null or empty');
    }
    for (MockResponse response : responses) {
      this.register(this.defaultQueue, response);
    }
    this.currentMockResponse = null;
  }

  // =================================================================================
  // Label mode (mirrors MockEloquent attach / label)
  // =================================================================================

  /**
   * @description Attaches a response under a label. Once attach() is used,
   * every send() must be routed with label().
   *
   * @param label The label naming a callout site.
   * @param response The mocked response.
   * @return This handler (for chaining).
   */
  public MockHttpRequestHandler attach(String label, MockResponse response) {
    return this.attach(label, new List<MockResponse>{ response });
  }

  /**
   * @description Attaches a response sequence under a label. The list is that
   * callout site's own script (e.g. retry attempts), consumed in order.
   * Attaching to the same label again appends to its queue.
   *
   * @param label The label naming a callout site.
   * @param responses The mocked responses, in expected order for this site.
   * @return This handler (for chaining).
   */
  public MockHttpRequestHandler attach(String label, List<MockResponse> responses) {
    if (String.isBlank(label)) {
      throw new IllegalArgumentException('Label cannot be blank');
    }
    if (responses == null || responses.isEmpty()) {
      throw new IllegalArgumentException('Responses cannot be null or empty');
    }
    if (!this.defaultQueue.isEmpty()) {
      throw new IllegalArgumentException(
        'Cannot mix attach() with constructor responses. Use either the constructor script (single flow) or attach() with labels (multiple callout sites).'
      );
    }
    if (!this.labelToQueue.containsKey(label)) {
      this.labelToQueue.put(label, new ResponseQueue());
    }
    for (MockResponse response : responses) {
      this.register(this.labelToQueue.get(label), response);
    }
    return this;
  }

  /**
   * @description Routes the next send() to the queue attached under the label.
   * Ignored when no attach() was used (script mode).
   *
   * @param label The label naming the purpose of the next send().
   * @return This handler.
   */
  public IHttpRequestHandler label(String label) {
    this.pendingLabel = label;
    return this;
  }

  // =================================================================================
  // IHttpRequestHandler
  // =================================================================================

  public void send(HttpRequest request) {
    String consumedLabel = this.pendingLabel;
    this.pendingLabel = null;

    ResponseQueue queue;
    String scopeName;
    if (!this.labelToQueue.isEmpty()) {
      if (consumedLabel == null) {
        throw new CalloutException(
          'attach() responses are label-scoped, but send() was called without label().\n' +
            'Call handler.label(\'<label>\').send(request). Registered labels: ' +
            String.join(new List<String>(this.labelToQueue.keySet()), ', ')
        );
      }
      queue = this.labelToQueue.get(consumedLabel);
      if (queue == null) {
        throw new CalloutException(
          'No mock response available for: ' + request.getMethod() + ' ' + request.getEndpoint() + '\n' +
            'Label \'' + consumedLabel + '\' has no attached responses. Registered labels: ' +
            String.join(new List<String>(this.labelToQueue.keySet()), ', ')
        );
      }
      scopeName = 'label \'' + consumedLabel + '\'';
    } else {
      consumedLabel = null;
      queue = this.defaultQueue;
      scopeName = 'the default script';
    }

    if (queue.isExhausted()) {
      throw new CalloutException(
        'No mock response available for: ' + request.getMethod() + ' ' + request.getEndpoint() + '\n' +
          'Scope: ' + scopeName + '\n' +
          'Queue: ' + queue.describe()
      );
    }

    // Method contract check: the next queued response declares which HTTP method
    // it answers. A mismatch means the flow deviated from the declared script
    // (wrong branch, wrong order, wrong endpoint wiring) — fail loudly without
    // consuming the response or recording the request.
    MockResponse nextResponse = queue.peek();
    if (request.getMethod() == null || !request.getMethod().equalsIgnoreCase(nextResponse.getMethod())) {
      throw new CalloutException(
        'Next queued response expects ' + nextResponse.getMethod().toUpperCase() +
          ', but the request was: ' + request.getMethod() + ' ' + request.getEndpoint() + '\n' +
          'Scope: ' + scopeName + '\n' +
          'Queue: ' + queue.describe()
      );
    }

    queue.advance();
    this.sentRequests.add(request);
    this.sentLabels.add(consumedLabel);
    this.currentMockResponse = nextResponse;
  }

  public String getBody() {
    if (this.currentMockResponse == null) {
      throw new JSONException('No response available. Ensure send() has been called.');
    }
    return this.currentMockResponse.getBody();
  }

  public Blob getBodyAsBlob() {
    if (this.currentMockResponse == null) {
      throw new JSONException('No response available. Ensure send() has been called.');
    }
    return this.currentMockResponse.getBodyAsBlob();
  }

  public Integer getStatusCode() {
    if (this.currentMockResponse == null) {
      throw new JSONException('No response available. Ensure send() has been called.');
    }
    return this.currentMockResponse.getStatusCode();
  }

  public String getHeader(String name) {
    if (this.currentMockResponse == null) {
      throw new JSONException('No response available. Ensure send() has been called.');
    }
    return this.currentMockResponse.getHeader(name);
  }

  // =================================================================================
  // Verification helpers
  // =================================================================================

  /**
   * @description Counts sent requests by HTTP method (case-insensitive).
   *
   * @param method The HTTP method (e.g. 'POST').
   * @return The number of sent requests with that method.
   */
  public Integer countByMethod(String method) {
    Integer count = 0;
    for (HttpRequest request : this.sentRequests) {
      if (request.getMethod() != null && request.getMethod().equalsIgnoreCase(method)) {
        count++;
      }
    }
    return count;
  }

  /**
   * @description Returns the sent requests whose endpoint contains the given fragment.
   *
   * @param endpointPart The endpoint fragment to search for.
   * @return The matching requests, in send order.
   */
  public List<HttpRequest> requestsTo(String endpointPart) {
    List<HttpRequest> matched = new List<HttpRequest>();
    for (HttpRequest request : this.sentRequests) {
      if (request.getEndpoint() != null && request.getEndpoint().contains(endpointPart)) {
        matched.add(request);
      }
    }
    return matched;
  }

  /**
   * @description Returns the requests sent under the given label, in send order.
   *
   * @param label The label to filter by.
   * @return The matching requests.
   */
  public List<HttpRequest> sentRequestsAt(String label) {
    List<HttpRequest> matched = new List<HttpRequest>();
    for (Integer i = 0; i < this.sentRequests.size(); i++) {
      if (this.sentLabels[i] == label) {
        matched.add(this.sentRequests[i]);
      }
    }
    return matched;
  }

  /**
   * @description Returns the most recently sent request, or null if none was sent.
   *
   * @return The last HttpRequest, or null.
   */
  public HttpRequest lastRequest() {
    if (this.sentRequests.isEmpty()) {
      return null;
    }
    return this.sentRequests[this.sentRequests.size() - 1];
  }

  // =================================================================================
  // Private helpers
  // =================================================================================

  /**
   * @description Validates and appends a response to a queue.
   *
   * @param queue The target queue (default script or per-label).
   * @param response The response to register.
   */
  private void register(ResponseQueue queue, MockResponse response) {
    if (response == null) {
      throw new IllegalArgumentException('Response cannot be null');
    }
    if (!response.isConfigured()) {
      throw new IllegalArgumentException(
        'MockResponse for method \'' + response.getMethod() + '\' has no content. Call respond(...) before registering.'
      );
    }
    queue.add(response);
  }

  // =================================================================================
  // Inner classes
  // =================================================================================

  /**
   * @description FIFO queue of responses. A repeat() response pins the pointer,
   * answering every further request of its scope.
   */
  private class ResponseQueue {
    private List<MockResponse> responses = new List<MockResponse>();
    private Integer pointer = 0;

    public void add(MockResponse response) {
      if (!this.responses.isEmpty() && this.responses[this.responses.size() - 1].isRepeating()) {
        throw new IllegalArgumentException(
          'A repeat() response must be the last one in its queue (\'' + response.getMethod() + '\' was added after it).'
        );
      }
      this.responses.add(response);
    }

    public Boolean isEmpty() {
      return this.responses.isEmpty();
    }

    public Boolean isExhausted() {
      return this.pointer >= this.responses.size();
    }

    public MockResponse peek() {
      return this.responses[this.pointer];
    }

    public void advance() {
      if (!this.responses[this.pointer].isRepeating()) {
        this.pointer++;
      }
    }

    public String describe() {
      Boolean endsRepeating = !this.responses.isEmpty() &&
        this.responses[this.responses.size() - 1].isRepeating();
      return this.pointer + ' of ' + this.responses.size() + ' consumed' + (endsRepeating ? ' (last repeats)' : '');
    }
  }
}
