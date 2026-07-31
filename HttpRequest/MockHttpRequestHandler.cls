/**
 * @description Test double for IHttpRequestHandler.
 *
 * Responses are declared as MockResponse rules and consumed as a FIFO queue
 * **per HTTP method**, so tests do not depend on the interleaving order of
 * different callout kinds (e.g. GET existence check, then POST or PUT),
 * while retries of the same method still consume in declared order.
 *
 * <pre>
 * MockHttpRequestHandler mock = new MockHttpRequestHandler(new List&lt;MockResponse&gt;{
 *   MockResponse.of('GET').respond('{"message":"not found"}', 404),
 *   MockResponse.of('GET').respond(foundBody, 200),
 *   MockResponse.of('POST').respond(createdBody, 200)
 * });
 * </pre>
 *
 * A response is consumed once; when a method's queue is exhausted the next
 * send() fails with a detailed error (call overruns are caught, not hidden).
 * Declare `.repeat()` on the last response of a method to make it answer
 * every further request instead.
 *
 * When one usecase talks to multiple endpoints/APIs, split the callout sites
 * by label (mirroring MockEloquent):
 *
 * <pre>
 * // usecase:  this.http.label(LBL_EXISTS).send(req);
 * MockHttpRequestHandler mock = new MockHttpRequestHandler()
 *   .attach(LBL_EXISTS, MockResponse.of('GET').respond(notFound, 404))
 *   .attach(LBL_CREATE, MockResponse.of('POST').respond(created, 200));
 * </pre>
 *
 * Once attach() is used, every send() must be preceded by label() (the label
 * is consumed per send). Without attach(), label() calls are ignored, so
 * labeled production code can still be tested with a plain constructor mock.
 */
public with sharing class MockHttpRequestHandler implements IHttpRequestHandler {
  @TestVisible
  private List<HttpRequest> sentRequests = new List<HttpRequest>();
  private List<String> sentLabels = new List<String>();

  private Map<String, ResponseQueue> defaultQueues = new Map<String, ResponseQueue>();
  private Map<String, Map<String, ResponseQueue>> labelToQueues = new Map<String, Map<String, ResponseQueue>>();

  private MockResponse currentMockResponse;
  private String pendingLabel;

  /**
   * @description Creates an empty handler. Register responses with attach() (label mode).
   */
  public MockHttpRequestHandler() {
    this.currentMockResponse = null;
  }

  /**
   * @description Creates a handler with a single response rule.
   *
   * @param response The mocked response.
   */
  public MockHttpRequestHandler(MockResponse response) {
    this.register(this.defaultQueues, response);
    this.currentMockResponse = null;
  }

  /**
   * @description Creates a handler with multiple response rules, consumed as a
   * FIFO queue per HTTP method.
   *
   * @param responses The mocked responses.
   */
  public MockHttpRequestHandler(List<MockResponse> responses) {
    if (responses == null || responses.isEmpty()) {
      throw new IllegalArgumentException('Responses cannot be null or empty');
    }
    for (MockResponse response : responses) {
      this.register(this.defaultQueues, response);
    }
    this.currentMockResponse = null;
  }

  // =================================================================================
  // Label mode (mirrors MockEloquent attach / label)
  // =================================================================================

  /**
   * @description Attaches a response rule under a label. Once attach() is used,
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
   * @description Attaches multiple response rules under a label.
   *
   * @param label The label naming a callout site.
   * @param responses The mocked responses.
   * @return This handler (for chaining).
   */
  public MockHttpRequestHandler attach(String label, List<MockResponse> responses) {
    if (String.isBlank(label)) {
      throw new IllegalArgumentException('Label cannot be blank');
    }
    if (responses == null || responses.isEmpty()) {
      throw new IllegalArgumentException('Responses cannot be null or empty');
    }
    if (!this.defaultQueues.isEmpty()) {
      throw new IllegalArgumentException(
        'Cannot mix attach() with constructor responses. Use either the constructor (single callout site) or attach() with labels (multiple callout sites).'
      );
    }
    if (!this.labelToQueues.containsKey(label)) {
      this.labelToQueues.put(label, new Map<String, ResponseQueue>());
    }
    for (MockResponse response : responses) {
      this.register(this.labelToQueues.get(label), response);
    }
    return this;
  }

  /**
   * @description Routes the next send() to the responses attached under the label.
   * Ignored when no attach() was used (plain constructor mode).
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

    Map<String, ResponseQueue> scope;
    if (!this.labelToQueues.isEmpty()) {
      if (consumedLabel == null) {
        throw new CalloutException(
          'attach() responses are label-scoped, but send() was called without label().\n' +
            'Call handler.label(\'<label>\').send(request). Registered labels: ' +
            String.join(new List<String>(this.labelToQueues.keySet()), ', ')
        );
      }
      scope = this.labelToQueues.get(consumedLabel);
      if (scope == null) {
        throw new CalloutException(
          this.buildNoResponseMessage(request, consumedLabel, new Map<String, ResponseQueue>())
        );
      }
    } else {
      consumedLabel = null;
      scope = this.defaultQueues;
    }

    String method = request.getMethod() == null ? null : request.getMethod().toLowerCase();
    ResponseQueue queue = scope.get(method);
    if (queue == null || queue.isExhausted()) {
      throw new CalloutException(this.buildNoResponseMessage(request, consumedLabel, scope));
    }

    this.sentRequests.add(request);
    this.sentLabels.add(consumedLabel);
    this.currentMockResponse = queue.next();
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
   * @description Registers a response into the method-keyed queue map of a scope.
   *
   * @param scope The queue map (default or per-label).
   * @param response The response to register.
   */
  private void register(Map<String, ResponseQueue> scope, MockResponse response) {
    if (response == null) {
      throw new IllegalArgumentException('Response cannot be null');
    }
    if (!response.isConfigured()) {
      throw new IllegalArgumentException(
        'MockResponse for method \'' + response.getMethod() + '\' has no content. Call respond(...) before registering.'
      );
    }
    if (!scope.containsKey(response.getMethod())) {
      scope.put(response.getMethod(), new ResponseQueue());
    }
    scope.get(response.getMethod()).add(response);
  }

  /**
   * @description Builds the detailed no-response error: the actual request, the
   * label (when routed), and every queue's consumption state.
   *
   * @param request The request that could not be answered.
   * @param label The consumed label, or null in constructor mode.
   * @param scope The queue map that was searched.
   * @return The composed error message.
   */
  private String buildNoResponseMessage(HttpRequest request, String label, Map<String, ResponseQueue> scope) {
    List<String> lines = new List<String>();
    lines.add('No mock response available for: ' + request.getMethod() + ' ' + request.getEndpoint());
    if (label != null) {
      if (this.labelToQueues.containsKey(label)) {
        lines.add('Label: \'' + label + '\'');
      } else {
        lines.add(
          'Label: \'' + label + '\' has no attached responses. Registered labels: ' +
            String.join(new List<String>(this.labelToQueues.keySet()), ', ')
        );
      }
    }
    if (scope.isEmpty()) {
      lines.add('Queues: none');
    } else {
      List<String> states = new List<String>();
      for (String method : scope.keySet()) {
        states.add('[' + method + ': ' + scope.get(method).describe() + ']');
      }
      lines.add('Queues: ' + String.join(states, ', '));
    }
    return String.join(lines, '\n');
  }

  // =================================================================================
  // Inner classes
  // =================================================================================

  /**
   * @description FIFO queue of responses for one HTTP method. A repeat() response
   * pins the pointer, answering every further request of the method.
   */
  private class ResponseQueue {
    private List<MockResponse> responses = new List<MockResponse>();
    private Integer pointer = 0;

    public void add(MockResponse response) {
      if (!this.responses.isEmpty() && this.responses[this.responses.size() - 1].isRepeating()) {
        throw new IllegalArgumentException(
          'A repeat() response must be the last one declared for its method (\'' + response.getMethod() + '\').'
        );
      }
      this.responses.add(response);
    }

    public Boolean isExhausted() {
      return this.pointer >= this.responses.size();
    }

    public MockResponse next() {
      MockResponse response = this.responses[this.pointer];
      if (!response.isRepeating()) {
        this.pointer++;
      }
      return response;
    }

    public String describe() {
      Boolean endsRepeating = !this.responses.isEmpty() &&
        this.responses[this.responses.size() - 1].isRepeating();
      return this.pointer + ' of ' + this.responses.size() + ' consumed' + (endsRepeating ? ' (last repeats)' : '');
    }
  }
}
