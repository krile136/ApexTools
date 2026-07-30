@isTest
public with sharing class HttpRequestHandlerTest {
  @isTest
  static void testHttpRequestHandler_WhenSend_ThenCanGetBodyAndStatusCode() {
    // Arrange
    HttpResponse mockResponse = new HttpResponse();
    mockResponse.setBody('{"status":"success"}');
    mockResponse.setStatusCode(200);
    Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator(mockResponse));

    // Act
    HttpRequestHandler requestHandler = new HttpRequestHandler();
    HttpRequest request = new HttpRequest();
    request.setEndpoint('https://api.example.com/test');
    request.setMethod('GET');
    requestHandler.send(request);
    String responseBody = requestHandler.getBody();
    Integer statusCode = requestHandler.getStatusCode();

    // Assert
    Assert.areEqual('{"status":"success"}', responseBody);
    Assert.areEqual(200, statusCode);
  }

  @isTest
  static void testHttpRequestHandler_WhenNoRequest_ThenGetBodyAndStatusCodeReturnNull() {
    // Arrange
    HttpRequestHandler requestHandler = new HttpRequestHandler();

    // Act
    String responseBody = requestHandler.getBody();
    Integer statusCode = requestHandler.getStatusCode();

    // Assert
    Assert.isNull(responseBody);
    Assert.isNull(statusCode);
  }

  private class MockHttpResponseGenerator implements HttpCalloutMock {
    private HttpResponse response;

    public MockHttpResponseGenerator(HttpResponse response) {
      this.response = response;
    }

    public HttpResponse respond(HttpRequest req) {
      return this.response;
    }
  }

  @IsTest
  static void testLabel_WhenCalled_ThenNoOpAndReturnsSelf() {
    // Arrange
    HttpRequestHandler handler = new HttpRequestHandler();

    // Act
    IHttpRequestHandler returned = handler.label('anything');

    // Assert - 本番実装では label は no-op で自身を返す
    Assert.areEqual(handler, returned);
  }
}
