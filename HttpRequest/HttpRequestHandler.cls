public with sharing class HttpRequestHandler implements IHttpRequestHandler {
  private HttpResponse currentHttpResponse;

  public HttpRequestHandler() {
    this.currentHttpResponse = null;
  }

  /**
   * @description No-op in production — labels only route responses in MockHttpRequestHandler.
   *
   * @param label The label naming the purpose of the next send().
   * @return This handler.
   */
  public IHttpRequestHandler label(String label) {
    return this;
  }

  public void send(HttpRequest request) {
    Http http = new Http();
    HttpResponse response = http.send(request);

    this.currentHttpResponse = response;
  }

  public String getBody() {
    if (this.currentHttpResponse == null) {
      return null;
    }

    return this.currentHttpResponse.getBody();
  }

  public Blob getBodyAsBlob() {
    if (this.currentHttpResponse == null) {
      return null;
    }
    return this.currentHttpResponse.getBodyAsBlob();
  }

  public Integer getStatusCode() {
    if (this.currentHttpResponse == null) {
      return null;
    }
    return this.currentHttpResponse.getStatusCode();
  }

  public String getHeader(String name) {
    if (this.currentHttpResponse == null) {
      return null;
    }
    return this.currentHttpResponse.getHeader(name);
  }
}
