/**
 * @description MockHttpRequestHandler のテストクラス
 */
@IsTest
private class MockHttpRequestHandlerTest {
  @IsTest
  static void testSend_WhenMapConstructorUsed_ThenReturnsCorrectResponse() {
    // Arrange
    Map<String, Object> bodyMap = new Map<String, Object>{ 'id' => 'map123', 'success' => true };
    Map<String, Object> responseData = new Map<String, Object>{ 'body' => bodyMap, 'statusCode' => 200 };

    MockHttpRequestHandler mock = new MockHttpRequestHandler(responseData);
    HttpRequest req = new HttpRequest();

    // Act
    mock.send(req);
    String actualBody = mock.getBody();
    Integer actualStatusCode = mock.getStatusCode();

    // Assert
    Map<String, Object> expectedBodyMap = new Map<String, Object>{ 'id' => 'map123', 'success' => true };
    Map<String, Object> actualBodyMap = (Map<String, Object>) JSON.deserializeUntyped(actualBody);
    Assert.areEqual(200, actualStatusCode, 'StatusCode should be 200');
    Assert.areEqual(expectedBodyMap, actualBodyMap, 'Body should match the expected map');
    Assert.areEqual(1, mock.sentRequests.size(), 'Should store one request');
    Assert.areEqual(req, mock.sentRequests[0], 'Stored request should match');
  }

  @IsTest
  static void testSend_WhenListConstructorUsed_ThenReturnsMultipleResponsesInOrder() {
    // Arrange
    String expectedBody1 = '{"status":"pending"}';
    String expectedBody2 = '{"status":"completed"}';

    List<Map<String, Object>> responseDataList = new List<Map<String, Object>>{
      new Map<String, Object>{ 'body' => new Map<String, Object>{ 'status' => 'pending' }, 'statusCode' => 202 },
      new Map<String, Object>{ 'body' => new Map<String, Object>{ 'status' => 'completed' }, 'statusCode' => 200 }
    };

    MockHttpRequestHandler mock = new MockHttpRequestHandler(responseDataList);
    HttpRequest req1 = new HttpRequest();
    HttpRequest req2 = new HttpRequest();

    // Act (1回目)
    mock.send(req1);
    String actualBody1 = mock.getBody();
    Integer actualStatusCode1 = mock.getStatusCode();

    // Act (2回目)
    mock.send(req2);
    String actualBody2 = mock.getBody();
    Integer actualStatusCode2 = mock.getStatusCode();

    // Assert (1回目)
    Assert.areEqual(202, actualStatusCode1, 'First status code should be 202');
    Assert.areEqual(expectedBody1, actualBody1, 'First body should be pending');

    // Assert (2回目)
    Assert.areEqual(200, actualStatusCode2, 'Second status code should be 200');
    Assert.areEqual(expectedBody2, actualBody2, 'Second body should be completed');

    // Assert (リクエスト保存の確認)
    Assert.areEqual(2, mock.sentRequests.size(), 'Should store two requests');
    Assert.areEqual(req1, mock.sentRequests[0], 'First stored request');
    Assert.areEqual(req2, mock.sentRequests[1], 'Second stored request');
  }

  @IsTest
  static void testSend_WhenStringConstructorUsed_ThenReturnsCorrectResponse() {
    // Arrange
    String expectedBody = '{"message":"Created"}'; // String (JSON)
    Integer expectedStatusCode = 201;

    MockHttpRequestHandler mock = new MockHttpRequestHandler(expectedBody, expectedStatusCode);
    HttpRequest req = new HttpRequest();

    // Act
    mock.send(req);
    String actualBody = mock.getBody();
    Integer actualStatusCode = mock.getStatusCode();

    // Assert
    Assert.areEqual(expectedStatusCode, actualStatusCode, 'StatusCode should be 201');
    Assert.areEqual(expectedBody, actualBody, 'Body should be the raw string');
    Assert.areEqual(1, mock.sentRequests.size(), 'Should store one request');
  }

  @IsTest
  static void testConstructor_WhenBodyIsList_ThenSerializesListCorrectly() {
    // Arrange
    String expectedBody = '[{"id":1},{"id":2}]'; // List
    List<Object> bodyList = new List<Object>{ new Map<String, Object>{ 'id' => 1 }, new Map<String, Object>{ 'id' => 2 } };
    Map<String, Object> responseData = new Map<String, Object>{ 'body' => bodyList, 'statusCode' => 200 };

    MockHttpRequestHandler mock = new MockHttpRequestHandler(responseData);
    HttpRequest req = new HttpRequest();

    // Act
    mock.send(req);
    String actualBody = mock.getBody();

    // Assert
    Assert.areEqual(expectedBody, actualBody, 'Body should be serialized list');
  }

  @IsTest
  static void testConstructor_WhenStatusCodeIsString_ThenInitializesSuccessfully() {
    // Arrange
    Map<String, Object> responseData = new Map<String, Object>{
      'body' => 'OK',
      'statusCode' => '200' // ★ String 型のステータスコード
    };

    MockHttpRequestHandler mock = new MockHttpRequestHandler(responseData);
    HttpRequest req = new HttpRequest();

    // Act
    mock.send(req);
    Integer actualStatusCode = mock.getStatusCode();

    // Assert
    Assert.areEqual(200, actualStatusCode, 'String StatusCode should be converted to Integer');
  }

  @IsTest
  static void testGetBody_WhenSendNotCalled_ThenThrowsException() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler('Body', 200);
    String expectedMessage = 'No response available. Ensure send() has been called.';
    JSONException caughtException = null;

    // Act
    Test.startTest();
    try {
      mock.getBody();
    } catch (JSONException e) {
      caughtException = e;
    }
    Test.stopTest();

    // Assert
    Assert.isNotNull(caughtException, 'A JSONException should have been thrown');
    Assert.areEqual(expectedMessage, caughtException.getMessage(), 'Exception message should match');
  }

  @IsTest
  static void testGetStatusCode_WhenSendNotCalled_ThenThrowsException() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler('Body', 200);
    String expectedMessage = 'No response available. Ensure send() has been called.';
    JSONException caughtException = null;

    // Act
    Test.startTest();
    try {
      mock.getStatusCode();
    } catch (JSONException e) {
      caughtException = e;
    }
    Test.stopTest();

    // Assert
    Assert.isNotNull(caughtException, 'A JSONException should have been thrown');
    Assert.areEqual(expectedMessage, caughtException.getMessage(), 'Exception message should match');
  }

  @IsTest
  static void testSend_WhenCalledMoreThanConfigured_ThenThrowsException() {
    // Arrange
    // (1回分のレスポンスしか設定しない)
    MockHttpRequestHandler mock = new MockHttpRequestHandler('Body', 200);
    HttpRequest req1 = new HttpRequest();
    HttpRequest req2 = new HttpRequest();
    String expectedMessage = 'No more responses configured, but send() was called.';
    CalloutException caughtException = null;

    // Act
    Test.startTest();
    mock.send(req1); // 1回目は成功
    try {
      mock.send(req2); // 2回目で失敗するはず
    } catch (CalloutException e) {
      caughtException = e;
    }
    Test.stopTest();

    // Assert
    Assert.isNotNull(caughtException, 'A CalloutException should have been thrown');
    Assert.areEqual(expectedMessage, caughtException.getMessage(), 'Exception message should match');
  }

  // --- MockResponse (Inner Class) Constructor Exception Tests ---

  @IsTest
  static void testConstructor_WhenMapIsNull_ThenThrowsException() {
    IllegalArgumentException caughtException = null;
    Test.startTest();
    try {
      new MockHttpRequestHandler((Map<String, Object>) null);
    } catch (IllegalArgumentException e) {
      caughtException = e;
    }
    Test.stopTest();
    Assert.isNotNull(caughtException, 'Exception should be thrown');
    Assert.areEqual('Response data cannot be null', caughtException.getMessage());
  }

  @IsTest
  static void testConstructor_WhenListIsNull_ThenThrowsException() {
    IllegalArgumentException caughtException = null;
    Test.startTest();
    try {
      new MockHttpRequestHandler((List<Map<String, Object>>) null);
    } catch (IllegalArgumentException e) {
      caughtException = e;
    }
    Test.stopTest();
    Assert.isNotNull(caughtException, 'Exception should be thrown');
    Assert.areEqual('Response data list cannot be null or empty', caughtException.getMessage());
  }

  @IsTest
  static void testConstructor_WhenListIsEmpty_ThenThrowsException() {
    IllegalArgumentException caughtException = null;
    Test.startTest();
    try {
      new MockHttpRequestHandler(new List<Map<String, Object>>());
    } catch (IllegalArgumentException e) {
      caughtException = e;
    }
    Test.stopTest();
    Assert.isNotNull(caughtException, 'Exception should be thrown');
    Assert.areEqual('Response data list cannot be null or empty', caughtException.getMessage());
  }

  @IsTest
  static void testConstructor_WhenBodyIsMissing_ThenThrowsException() {
    IllegalArgumentException caughtException = null;
    Map<String, Object> responseData = new Map<String, Object>{
      'statusCode' => 200 // body が欠けている
    };
    Test.startTest();
    try {
      new MockHttpRequestHandler(responseData);
    } catch (IllegalArgumentException e) {
      caughtException = e;
    }
    Test.stopTest();
    Assert.isNotNull(caughtException, 'Exception should be thrown');
    Assert.areEqual('Response data must contain body and statusCode', caughtException.getMessage());
  }

  @IsTest
  static void testConstructor_WhenStatusCodeIsMissing_ThenThrowsException() {
    IllegalArgumentException caughtException = null;
    Map<String, Object> responseData = new Map<String, Object>{
      'body' => 'OK' // statusCode が欠けている
    };
    Test.startTest();
    try {
      new MockHttpRequestHandler(responseData);
    } catch (IllegalArgumentException e) {
      caughtException = e;
    }
    Test.stopTest();
    Assert.isNotNull(caughtException, 'Exception should be thrown');
    Assert.areEqual('Response data must contain body and statusCode', caughtException.getMessage());
  }

  @IsTest
  static void testConstructor_WhenBodyIsInvalidType_ThenThrowsException() {
    IllegalArgumentException caughtException = null;
    Map<String, Object> responseData = new Map<String, Object>{
      'body' => 12345, // Invalid type (Integer)
      'statusCode' => 200
    };
    Test.startTest();
    try {
      new MockHttpRequestHandler(responseData);
    } catch (IllegalArgumentException e) {
      caughtException = e;
    }
    Test.stopTest();
    Assert.isNotNull(caughtException, 'Exception should be thrown');
    Assert.areEqual('Body must be a Map, List, or String', caughtException.getMessage());
  }

  @IsTest
  static void testConstructor_WhenStatusCodeIsInvalidType_ThenThrowsException() {
    IllegalArgumentException caughtException = null;
    Map<String, Object> responseData = new Map<String, Object>{
      'body' => 'OK',
      'statusCode' => new List<Integer>{ 200 } // Invalid type (List)
    };
    Test.startTest();
    try {
      new MockHttpRequestHandler(responseData);
    } catch (IllegalArgumentException e) {
      caughtException = e;
    }
    Test.stopTest();
    Assert.isNotNull(caughtException, 'Exception should be thrown');
    Assert.areEqual('StatusCode must be an Integer or String', caughtException.getMessage());
  }
}
