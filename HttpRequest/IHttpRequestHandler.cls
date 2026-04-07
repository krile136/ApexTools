public interface IHttpRequestHandler {
  void send(HttpRequest request);
  String getBody();
  Integer getStatusCode();
}
