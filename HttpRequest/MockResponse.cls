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
  private Blob bodyBlob;
  private Integer statusCode;
  private Map<String, String> headers = new Map<String, String>();
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
   * @description Sets the response content from a binary body (e.g. an image).
   * Read it back via getBodyAsBlob().
   *
   * @param body The response body as a Blob.
   * @param statusCode The response status code.
   * @return This MockResponse (for chaining).
   */
  public MockResponse respond(Blob body, Integer statusCode) {
    if (body == null) {
      throw new IllegalArgumentException('Body blob cannot be null');
    }
    if (statusCode == null) {
      throw new IllegalArgumentException('StatusCode cannot be null');
    }
    this.bodyBlob = body;
    this.statusCode = statusCode;
    return this;
  }

  /**
   * @description Sets a response header (e.g. Content-Type). Lookup via
   * getHeader() is case-insensitive, as HTTP headers are.
   *
   * @param name The header name.
   * @param value The header value.
   * @return This MockResponse (for chaining).
   */
  public MockResponse header(String name, String value) {
    if (String.isBlank(name)) {
      throw new IllegalArgumentException('Header name cannot be blank');
    }
    this.headers.put(name.toLowerCase(), value);
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

  /**
   * @description Returns the string body. When only a Blob body was set, it is
   * converted via toString() — valid for text blobs; truly binary responses
   * should be read via getBodyAsBlob() instead.
   */
  public String getBody() {
    if (this.body != null) {
      return this.body;
    }
    if (this.bodyBlob != null) {
      return this.bodyBlob.toString();
    }
    return null;
  }

  /**
   * @description Returns the binary body. When only a string body was set, it
   * falls back to Blob.valueOf(body), so text-configured responses can also be
   * read as a Blob.
   */
  public Blob getBodyAsBlob() {
    if (this.bodyBlob != null) {
      return this.bodyBlob;
    }
    if (this.body != null) {
      return Blob.valueOf(this.body);
    }
    return null;
  }

  /**
   * @description Returns a response header value (case-insensitive), or null when unset.
   */
  public String getHeader(String name) {
    if (name == null) {
      return null;
    }
    return this.headers.get(name.toLowerCase());
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
