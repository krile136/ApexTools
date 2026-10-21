/**
 * @directory ApexTools/HttpRequest
 */
public interface IHttpRequestHandler {
  /**
   * Names the purpose of the next send() (e.g. 'kintoneExists'). Production
   * implementations ignore it; MockHttpRequestHandler uses it to route the
   * request to the responses attached under the same label.
   */
  IHttpRequestHandler label(String label);
  void send(HttpRequest request);

  // The getters below have no response to read before send(), or after a send() that threw
  // (CalloutException). HttpRequestHandler returns null then; MockHttpRequestHandler throws a
  // JSONException, so a test notices code that reads a response that does not exist.
  String getBody();
  Blob getBodyAsBlob();
  Integer getStatusCode();
  String getHeader(String name);
}
