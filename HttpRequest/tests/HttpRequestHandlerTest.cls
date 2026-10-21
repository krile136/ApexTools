/**
 * @directory ApexTools/HttpRequest/tests
 */
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

    // Assert - in production, label() is a no-op returning the same instance
    Assert.areEqual(handler, returned);
  }

  @IsTest
  static void testGetBodyAsBlobAndHeader_WhenSendNotCalled_ThenReturnNull() {
    // Arrange
    HttpRequestHandler handler = new HttpRequestHandler();

    // Act & Assert
    Assert.isNull(handler.getBodyAsBlob());
    Assert.isNull(handler.getHeader('Content-Type'));
  }

  /**
   * Answers the first callout, then fails every later one the way an unreachable endpoint does.
   */
  private class FailAfterFirstGenerator implements HttpCalloutMock {
    private Integer calls = 0;

    public HttpResponse respond(HttpRequest request) {
      this.calls++;
      if (this.calls > 1) {
        throw new CalloutException('Read timed out');
      }
      HttpResponse response = new HttpResponse();
      response.setBody('{"status":"success"}');
      response.setStatusCode(200);
      return response;
    }
  }

  @isTest
  static void testSend_WhenSendFailsAfterASuccess_ThenThePreviousResponseIsGone() {
    // Arrange: a failed send() used to leave the previous 200 readable (issue #5)
    Test.setMock(HttpCalloutMock.class, new FailAfterFirstGenerator());
    HttpRequestHandler requestHandler = new HttpRequestHandler();
    HttpRequest request = new HttpRequest();
    request.setEndpoint('https://api.example.com/test');
    request.setMethod('GET');
    requestHandler.send(request);
    Assert.areEqual(200, requestHandler.getStatusCode());

    // Act
    try {
      requestHandler.send(request);
      Assert.fail('The second send() must throw');
    } catch (CalloutException e) {
      Assert.areEqual('Read timed out', e.getMessage());
    }

    // Assert
    Assert.isNull(requestHandler.getStatusCode());
    Assert.isNull(requestHandler.getBody());
    Assert.isNull(requestHandler.getBodyAsBlob());
    Assert.isNull(requestHandler.getHeader('Content-Type'));
  }
}
