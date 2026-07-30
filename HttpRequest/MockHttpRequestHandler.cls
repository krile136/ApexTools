/**
 * @description Test double for IHttpRequestHandler with two complementary modes:
 *
 * 1. Ordered mode (original): responses passed to a constructor are consumed
 *    positionally, one per send(). Best for retry / pagination tests where the
 *    call order itself is the subject.
 * 2. Matching mode: responses registered via when() are returned whenever the
 *    request matches, regardless of order. Best for multi-callout flows
 *    (e.g. GET existence check, then POST or PUT) where the branch taken is
 *    the subject, not the call order.
 *
 * Resolution is hybrid: matchers are evaluated first (in registration order,
 * first match wins), and non-matching requests fall back to the ordered queue.
 * A matched response is sticky (returned every time); use thenRespond() to
 * define a per-matcher sequence whose last response sticks.
 *
 * <pre>
 * MockHttpRequestHandler mock = new MockHttpRequestHandler()
 *   .when().method('GET').endpointContains('/records.json').respond(existsBody, 200)
 *   .when().method('POST').respond(createdBody, 200)
 *   .when().method('PUT').respond('{"message":"bad request"}', 400);
 *
 * new KintoneUpsertUsecase(input, mock).invoke();
 *
 * Assert.areEqual(1, mock.countByMethod('POST'));
 * Assert.areEqual(0, mock.countByMethod('PUT'));
 * </pre>
 */
public with sharing class MockHttpRequestHandler implements IHttpRequestHandler {
  @TestVisible
  private List<HttpRequest> sentRequests = new List<HttpRequest>();
  @TestVisible
  private List<MockResponse> mockResponses = new List<MockResponse>();
  @TestVisible
  private List<MatcherEntry> matcherEntries = new List<MatcherEntry>();

  private MockResponse currentMockResponse;
  private Integer orderedConsumedCount = 0;

  /**
   * @description Creates an empty handler for matching mode. Register responses with when().
   */
  public MockHttpRequestHandler() {
    this.currentMockResponse = null;
  }

  public MockHttpRequestHandler(Map<String, Object> responseData) {
    if (responseData == null) {
      throw new IllegalArgumentException('Response data cannot be null');
    }
    MockResponse mockResponse = new MockResponse(responseData);
    this.mockResponses.add(mockResponse);
    this.currentMockResponse = null;
  }

  public MockHttpRequestHandler(List<Map<String, Object>> responseDataList) {
    if (responseDataList == null || responseDataList.isEmpty()) {
      throw new IllegalArgumentException('Response data list cannot be null or empty');
    }
    for (Map<String, Object> responseData : responseDataList) {
      MockResponse mockResponse = new MockResponse(responseData);
      this.mockResponses.add(mockResponse);
    }
    this.currentMockResponse = null;
  }

  public MockHttpRequestHandler(String body, Integer statusCode) {
    Map<String, Object> responseData = new Map<String, Object>{ 'body' => body, 'statusCode' => statusCode };
    MockResponse mockResponse = new MockResponse(responseData);
    this.mockResponses.add(mockResponse);
    this.currentMockResponse = null;
  }

  // =================================================================================
  // Matching DSL
  // =================================================================================

  /**
   * @description Starts a request matcher definition. Chain criteria (method /
   * endpointContains / endpointEquals / bodyContains, AND-combined) and finish
   * with respond() to register.
   *
   * @return A RequestCriteria builder.
   */
  public RequestCriteria when() {
    return new RequestCriteria(this, null);
  }

  /**
   * @description Starts a request matcher definition seeded with a custom predicate.
   * Criteria chained afterwards are AND-combined with the predicate.
   *
   * @param matcher A custom IRequestMatcher implementation.
   * @return A RequestCriteria builder.
   */
  public RequestCriteria when(IRequestMatcher matcher) {
    if (matcher == null) {
      throw new IllegalArgumentException('Matcher cannot be null');
    }
    return new RequestCriteria(this, matcher);
  }

  /**
   * @description Appends a follow-up response to the most recently registered matcher,
   * forming a per-matcher sequence. The last response of the sequence is sticky.
   *
   * @param body The response body.
   * @param statusCode The response status code.
   * @return This handler (for chaining).
   */
  public MockHttpRequestHandler thenRespond(String body, Integer statusCode) {
    return this.thenRespond(new Map<String, Object>{ 'body' => body, 'statusCode' => statusCode });
  }

  /**
   * @description Appends a follow-up response (Map form) to the most recently registered matcher.
   *
   * @param responseData A map containing 'body' and 'statusCode'.
   * @return This handler (for chaining).
   */
  public MockHttpRequestHandler thenRespond(Map<String, Object> responseData) {
    if (this.matcherEntries.isEmpty()) {
      throw new IllegalArgumentException('thenRespond() requires a preceding when(...).respond(...)');
    }
    this.matcherEntries[this.matcherEntries.size() - 1].responses.add(new MockResponse(responseData));
    return this;
  }

  // =================================================================================
  // IHttpRequestHandler
  // =================================================================================

  public void send(HttpRequest request) {
    // Matchers first, in registration order (first match wins).
    for (MatcherEntry entry : this.matcherEntries) {
      if (entry.criteria.isMatch(request)) {
        this.sentRequests.add(request);
        this.currentMockResponse = entry.nextResponse();
        return;
      }
    }
    // Fallback: the ordered queue (original behavior).
    if (this.orderedConsumedCount >= this.mockResponses.size()) {
      throw new CalloutException(this.buildNoResponseMessage(request));
    }
    this.sentRequests.add(request);
    this.currentMockResponse = this.mockResponses[this.orderedConsumedCount];
    this.orderedConsumedCount++;
  }

  public String getBody() {
    if (this.currentMockResponse == null) {
      throw new JSONException('No response available. Ensure send() has been called.');
    }
    return this.currentMockResponse.body;
  }

  public Integer getStatusCode() {
    if (this.currentMockResponse == null) {
      throw new JSONException('No response available. Ensure send() has been called.');
    }
    return this.currentMockResponse.statusCode;
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
   * @description Builds the detailed no-response error: the actual request, the
   * registered matchers, and the ordered queue consumption state.
   *
   * @param request The request that could not be answered.
   * @return The composed error message.
   */
  private String buildNoResponseMessage(HttpRequest request) {
    List<String> lines = new List<String>();
    lines.add('No more responses configured, but send() was called.');
    lines.add('Request: ' + request.getMethod() + ' ' + request.getEndpoint());
    if (this.matcherEntries.isEmpty()) {
      lines.add('Registered matchers: none');
    } else {
      List<String> descriptions = new List<String>();
      for (MatcherEntry entry : this.matcherEntries) {
        descriptions.add('[' + entry.criteria.describe() + ']');
      }
      lines.add('Registered matchers (no match): ' + String.join(descriptions, ', '));
    }
    lines.add('Ordered responses: ' + this.orderedConsumedCount + ' of ' + this.mockResponses.size() + ' consumed');
    return String.join(lines, '\n');
  }

  // =================================================================================
  // Inner classes
  // =================================================================================

  /**
   * @description Criteria builder returned by when(). All chained criteria are
   * AND-combined; respond() registers the matcher and returns the handler.
   */
  public class RequestCriteria {
    private MockHttpRequestHandler parent;
    private IRequestMatcher customMatcher;
    private String methodValue;
    private String endpointContainsValue;
    private String endpointEqualsValue;
    private String bodyContainsValue;

    private RequestCriteria(MockHttpRequestHandler parent, IRequestMatcher customMatcher) {
      this.parent = parent;
      this.customMatcher = customMatcher;
    }

    /**
     * @description Matches on the HTTP method (case-insensitive).
     *
     * @param method The HTTP method (e.g. 'POST').
     * @return This builder (for chaining).
     */
    public RequestCriteria method(String method) {
      if (String.isBlank(method)) {
        throw new IllegalArgumentException('method cannot be blank');
      }
      this.methodValue = method;
      return this;
    }

    /**
     * @description Matches when the endpoint contains the given fragment.
     *
     * @param endpointPart The endpoint fragment.
     * @return This builder (for chaining).
     */
    public RequestCriteria endpointContains(String endpointPart) {
      if (String.isBlank(endpointPart)) {
        throw new IllegalArgumentException('endpointPart cannot be blank');
      }
      this.endpointContainsValue = endpointPart;
      return this;
    }

    /**
     * @description Matches when the endpoint equals the given value exactly.
     *
     * @param endpoint The full endpoint.
     * @return This builder (for chaining).
     */
    public RequestCriteria endpointEquals(String endpoint) {
      if (String.isBlank(endpoint)) {
        throw new IllegalArgumentException('endpoint cannot be blank');
      }
      this.endpointEqualsValue = endpoint;
      return this;
    }

    /**
     * @description Matches when the request body contains the given fragment.
     *
     * @param bodyPart The body fragment.
     * @return This builder (for chaining).
     */
    public RequestCriteria bodyContains(String bodyPart) {
      if (String.isBlank(bodyPart)) {
        throw new IllegalArgumentException('bodyPart cannot be blank');
      }
      this.bodyContainsValue = bodyPart;
      return this;
    }

    /**
     * @description Registers this matcher with a sticky response and returns the handler.
     *
     * @param body The response body.
     * @param statusCode The response status code.
     * @return The parent handler (for chaining further when() calls).
     */
    public MockHttpRequestHandler respond(String body, Integer statusCode) {
      return this.respond(new Map<String, Object>{ 'body' => body, 'statusCode' => statusCode });
    }

    /**
     * @description Registers this matcher with a sticky response (Map form) and returns the handler.
     *
     * @param responseData A map containing 'body' and 'statusCode'.
     * @return The parent handler (for chaining further when() calls).
     */
    public MockHttpRequestHandler respond(Map<String, Object> responseData) {
      if (
        this.customMatcher == null &&
        this.methodValue == null &&
        this.endpointContainsValue == null &&
        this.endpointEqualsValue == null &&
        this.bodyContainsValue == null
      ) {
        throw new IllegalArgumentException('when() requires at least one condition before respond()');
      }
      MatcherEntry entry = new MatcherEntry();
      entry.criteria = this;
      entry.responses.add(new MockResponse(responseData));
      this.parent.matcherEntries.add(entry);
      return this.parent;
    }

    /**
     * @description Evaluates all criteria (AND) against a request.
     *
     * @param request The request to evaluate.
     * @return True when every criterion matches.
     */
    private Boolean isMatch(HttpRequest request) {
      if (
        this.methodValue != null &&
        (request.getMethod() == null || !request.getMethod().equalsIgnoreCase(this.methodValue))
      ) {
        return false;
      }
      if (this.endpointEqualsValue != null && request.getEndpoint() != this.endpointEqualsValue) {
        return false;
      }
      if (
        this.endpointContainsValue != null &&
        (request.getEndpoint() == null || !request.getEndpoint().contains(this.endpointContainsValue))
      ) {
        return false;
      }
      if (
        this.bodyContainsValue != null &&
        (request.getBody() == null || !request.getBody().contains(this.bodyContainsValue))
      ) {
        return false;
      }
      if (this.customMatcher != null && !this.customMatcher.matches(request)) {
        return false;
      }
      return true;
    }

    /**
     * @description Human-readable summary of the criteria (used in error messages).
     *
     * @return The criteria summary.
     */
    private String describe() {
      List<String> parts = new List<String>();
      if (this.methodValue != null) {
        parts.add('method=' + this.methodValue);
      }
      if (this.endpointEqualsValue != null) {
        parts.add('endpointEquals=' + this.endpointEqualsValue);
      }
      if (this.endpointContainsValue != null) {
        parts.add('endpointContains=' + this.endpointContainsValue);
      }
      if (this.bodyContainsValue != null) {
        parts.add('bodyContains=' + this.bodyContainsValue);
      }
      if (this.customMatcher != null) {
        parts.add('custom matcher');
      }
      return String.join(parts, ' AND ');
    }
  }

  /**
   * @description A registered matcher with its response sequence. The pointer
   * advances per match and sticks at the last response.
   */
  @TestVisible
  private class MatcherEntry {
    public RequestCriteria criteria;
    public List<MockResponse> responses = new List<MockResponse>();
    private Integer responsePointer = 0;

    public MockResponse nextResponse() {
      MockResponse response = this.responses[this.responsePointer];
      if (this.responsePointer < this.responses.size() - 1) {
        this.responsePointer++;
      }
      return response;
    }
  }

  @TestVisible
  private class MockResponse {
    public String body;
    public Integer statusCode;

    public MockResponse(Map<String, Object> responseData) {
      if (responseData == null) {
        throw new IllegalArgumentException('Response data cannot be null');
      }
      if (responseData.get('body') == null || responseData.get('statusCode') == null) {
        throw new IllegalArgumentException('Response data must contain body and statusCode');
      }

      Object bodyData = responseData.get('body');
      if (responseData.get('body') instanceof Map<String, Object>) {
        this.body = JSON.serialize((Map<String, Object>) bodyData);
      } else if (responseData.get('body') instanceof List<Object>) {
        this.body = JSON.serialize((List<Object>) bodyData);
      } else if (responseData.get('body') instanceof String) {
        this.body = (String) bodyData;
      } else {
        throw new IllegalArgumentException('Body must be a Map, List, or String');
      }

      Object sc = responseData.get('statusCode');
      if (sc instanceof Integer) {
        this.statusCode = (Integer) sc;
      } else if (sc instanceof String) {
        this.statusCode = Integer.valueOf((String) sc);
      } else {
        throw new IllegalArgumentException('StatusCode must be an Integer or String');
      }
    }
  }
}
