public interface IHttpRequestHandler {
  /**
   * Names the purpose of the next send() (e.g. 'kintoneExists'). Production
   * implementations ignore it; MockHttpRequestHandler uses it to route the
   * request to the responses attached under the same label.
   */
  IHttpRequestHandler label(String label);
  void send(HttpRequest request);
  String getBody();
  Integer getStatusCode();
}
