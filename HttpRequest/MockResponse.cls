/**
 * @description A single mocked HTTP response, declared as a rule:
 * "when a request with this method arrives, respond with this content".
 *
 * <pre>
 * MockResponse.of('GET').respond('{"message":"not found"}', 404)
 * MockResponse.of('post').respond(new Map&lt;String, Object&gt;{ 'id' => '1' }, 200)
 * MockResponse.of('GET').respond('{"ok":true}', 200).repeat()   // sticks forever
 * </pre>
 *
 * The method name is normalized to lowercase internally, so 'GET' / 'get' / 'Get'
 * all declare (and match) the same method.
 */
public with sharing class MockResponse {
  private String method;
  private String body;
  private Integer statusCode;
  private Boolean repeating = false;

  /**
   * @description Private constructor to enforce creation via the `of` factory method.
   *
   * @param method The HTTP method, already normalized to lowercase.
   */
  private MockResponse(String method) {
    this.method = method;
  }

  /**
   * @description Creates a response rule for an HTTP method.
   *
   * @param method The HTTP method (e.g. 'GET', 'post' — case-insensitive).
   * @return A new MockResponse.
   */
  public static MockResponse of(String method) {
    if (String.isBlank(method)) {
      throw new IllegalArgumentException('Method cannot be blank');
    }
    return new MockResponse(method.toLowerCase());
  }

  /**
   * @description Sets the response content from a string body.
   *
   * @param body The response body (may be null for empty-body responses like 204).
   * @param statusCode The response status code.
   * @return This MockResponse (for chaining).
   */
  public MockResponse respond(String body, Integer statusCode) {
    if (statusCode == null) {
      throw new IllegalArgumentException('StatusCode cannot be null');
    }
    this.body = body;
    this.statusCode = statusCode;
    return this;
  }

  /**
   * @description Sets the response content from a map body (JSON-serialized).
   *
   * @param body The response body as a map.
   * @param statusCode The response status code.
   * @return This MockResponse (for chaining).
   */
  public MockResponse respond(Map<String, Object> body, Integer statusCode) {
    if (body == null) {
      throw new IllegalArgumentException('Body map cannot be null');
    }
    return this.respond(JSON.serialize(body), statusCode);
  }

  /**
   * @description Sets the response content from a list body (JSON-serialized).
   *
   * @param body The response body as a list.
   * @param statusCode The response status code.
   * @return This MockResponse (for chaining).
   */
  public MockResponse respond(List<Object> body, Integer statusCode) {
    if (body == null) {
      throw new IllegalArgumentException('Body list cannot be null');
    }
    return this.respond(JSON.serialize(body), statusCode);
  }

  /**
   * @description Marks this response as repeating: once reached, it answers every
   * further request of its method instead of being consumed. Must be the last
   * response declared for its method.
   *
   * @return This MockResponse (for chaining).
   */
  public MockResponse repeat() {
    this.repeating = true;
    return this;
  }

  public String getMethod() {
    return this.method;
  }

  public String getBody() {
    return this.body;
  }

  public Integer getStatusCode() {
    return this.statusCode;
  }

  public Boolean isRepeating() {
    return this.repeating;
  }

  /**
   * @description Whether respond() has been called (a rule without content is invalid).
   *
   * @return True when the response content is configured.
   */
  public Boolean isConfigured() {
    return this.statusCode != null;
  }
}
