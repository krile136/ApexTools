public with sharing class MockHttpRequestHandler implements IHttpRequestHandler {
  @TestVisible
  private List<HttpRequest> sentRequests = new List<HttpRequest>();
  @TestVisible
  private List<MockResponse> mockResponses = new List<MockResponse>();

  private MockResponse currentMockResponse;

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

  public void send(HttpRequest request) {
    if (this.sentRequests.size() == this.mockResponses.size()) {
      throw new CalloutException('No more responses configured, but send() was called.');
    }
    this.sentRequests.add(request);
    this.currentMockResponse = this.mockResponses[this.sentRequests.size() - 1];
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
