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
    Assert.isTrue(caughtException.getMessage().contains(expectedMessage), caughtException.getMessage());
    Assert.isTrue(caughtException.getMessage().contains('Ordered responses: 1 of 1 consumed'), caughtException.getMessage());
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

  // ===============================================================================
  // Matching mode (when / respond / thenRespond)
  // ===============================================================================

  private static HttpRequest buildRequest(String method, String endpoint) {
    HttpRequest req = new HttpRequest();
    req.setMethod(method);
    req.setEndpoint(endpoint);
    return req;
  }

  @IsTest
  static void testWhen_WhenMethodMatches_ThenReturnsMatchedResponse() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .when().method('GET').respond('{"found":true}', 200)
      .when().method('POST').respond('{"created":true}', 201);

    // Act & Assert (GET)
    mock.send(buildRequest('GET', 'https://example.com/records'));
    Assert.areEqual(200, mock.getStatusCode());
    Assert.areEqual('{"found":true}', mock.getBody());

    // Act & Assert (POST) - 順序ではなくメソッドで応答が決まる
    mock.send(buildRequest('POST', 'https://example.com/records'));
    Assert.areEqual(201, mock.getStatusCode());
    Assert.areEqual('{"created":true}', mock.getBody());
  }

  @IsTest
  static void testWhen_WhenEndpointContainsMatches_ThenReturnsMatchedResponse() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .when().endpointContains('/records.json').respond('{"kind":"record"}', 200)
      .when().endpointContains('/files.json').respond('{"kind":"file"}', 200);

    // Act
    mock.send(buildRequest('GET', 'https://example.cybozu.com/k/v1/files.json'));

    // Assert
    Assert.areEqual('{"kind":"file"}', mock.getBody());
  }

  @IsTest
  static void testWhen_WhenMultipleCriteria_ThenAllMustMatch() {
    // Arrange - method と endpoint の AND
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .when().method('PUT').endpointContains('/records.json').respond('{"updated":true}', 200)
      .when().method('PUT').respond('{"other":true}', 200);

    // Act & Assert - endpoint が合わない PUT は 2 つ目のマッチャーに落ちる
    mock.send(buildRequest('PUT', 'https://example.com/other.json'));
    Assert.areEqual('{"other":true}', mock.getBody());

    mock.send(buildRequest('PUT', 'https://example.com/k/v1/records.json'));
    Assert.areEqual('{"updated":true}', mock.getBody());
  }

  @IsTest
  static void testWhen_WhenMatchedRepeatedly_ThenResponseIsSticky() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .when().method('GET').respond('{"n":1}', 200);

    // Act & Assert - マッチ応答は何度でも返る (順序モードと違い枯渇しない)
    for (Integer i = 0; i < 3; i++) {
      mock.send(buildRequest('GET', 'https://example.com'));
      Assert.areEqual('{"n":1}', mock.getBody());
    }
    Assert.areEqual(3, mock.sentRequests.size());
  }

  @IsTest
  static void testThenRespond_WhenSequenceDefined_ThenAdvancesAndSticksAtLast() {
    // Arrange - GET が 1回目 404 → 2回目以降 200 (upsert の存在確認フロー)
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .when().method('GET').respond('{"message":"not found"}', 404)
      .thenRespond('{"record":{}}', 200);

    // Act & Assert
    mock.send(buildRequest('GET', 'https://example.com'));
    Assert.areEqual(404, mock.getStatusCode());

    mock.send(buildRequest('GET', 'https://example.com'));
    Assert.areEqual(200, mock.getStatusCode());

    mock.send(buildRequest('GET', 'https://example.com'));
    Assert.areEqual(200, mock.getStatusCode(), 'Last response should stick');
  }

  @IsTest
  static void testWhen_WhenFirstRegisteredMatcherWins_ThenOrderRespected() {
    // Arrange - 両方マッチし得る場合は登録順で先勝ち (特殊→一般の順で書く)
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .when().method('GET').endpointContains('/special').respond('{"which":"special"}', 200)
      .when().method('GET').respond('{"which":"general"}', 200);

    // Act & Assert
    mock.send(buildRequest('GET', 'https://example.com/special/1'));
    Assert.areEqual('{"which":"special"}', mock.getBody());

    mock.send(buildRequest('GET', 'https://example.com/other'));
    Assert.areEqual('{"which":"general"}', mock.getBody());
  }

  @IsTest
  static void testSend_WhenNoMatch_ThenFallsBackToOrderedQueue() {
    // Arrange - ハイブリッド: POST はマッチ、GET は順序キューへ
    MockHttpRequestHandler mock = new MockHttpRequestHandler('{"queued":true}', 200);
    mock.when().method('POST').respond('{"matched":true}', 201);

    // Act & Assert
    mock.send(buildRequest('POST', 'https://example.com'));
    Assert.areEqual('{"matched":true}', mock.getBody());

    mock.send(buildRequest('GET', 'https://example.com'));
    Assert.areEqual('{"queued":true}', mock.getBody());
  }

  @IsTest
  static void testSend_WhenNoMatchAndQueueExhausted_ThenDetailedError() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .when().method('POST').endpointContains('/records.json').respond('{"ok":true}', 200);
    CalloutException caughtException = null;

    // Act
    try {
      mock.send(buildRequest('DELETE', 'https://example.com/k/v1/records.json'));
    } catch (CalloutException e) {
      caughtException = e;
    }

    // Assert - 実リクエスト・登録済みマッチャー・キュー状態が全部読める
    Assert.isNotNull(caughtException);
    String message = caughtException.getMessage();
    Assert.isTrue(message.contains('Request: DELETE https://example.com/k/v1/records.json'), message);
    Assert.isTrue(message.contains('method=POST AND endpointContains=/records.json'), message);
    Assert.isTrue(message.contains('Ordered responses: 0 of 0 consumed'), message);
    Assert.areEqual(0, mock.sentRequests.size(), 'Failed request should not be recorded');
  }

  @IsTest
  static void testWhen_WhenCustomMatcherGiven_ThenPredicateIsUsed() {
    // Arrange - ビルダーで表現できない条件は IRequestMatcher で
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .when(new HasRecordKeyMatcher()).respond('{"viaCustom":true}', 200)
      .when().method('POST').respond('{"viaBuilder":true}', 200);

    HttpRequest withKey = buildRequest('POST', 'https://example.com');
    withKey.setBody('{"record":{"name":"x"}}');
    HttpRequest withoutKey = buildRequest('POST', 'https://example.com');
    withoutKey.setBody('{"other":1}');

    // Act & Assert
    mock.send(withKey);
    Assert.areEqual('{"viaCustom":true}', mock.getBody());

    mock.send(withoutKey);
    Assert.areEqual('{"viaBuilder":true}', mock.getBody());
  }

  @IsTest
  static void testHelpers_WhenRequestsSent_ThenCountAndFilterWork() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .when().method('GET').respond('{"a":1}', 200)
      .when().method('POST').respond('{"b":2}', 200);

    // Act
    mock.send(buildRequest('GET', 'https://example.com/k/v1/records.json'));
    mock.send(buildRequest('POST', 'https://example.com/k/v1/records.json'));
    mock.send(buildRequest('GET', 'https://example.com/k/v1/files.json'));

    // Assert
    Assert.areEqual(2, mock.countByMethod('GET'));
    Assert.areEqual(1, mock.countByMethod('POST'));
    Assert.areEqual(0, mock.countByMethod('PUT'));
    Assert.areEqual(2, mock.requestsTo('/records.json').size());
    Assert.areEqual('https://example.com/k/v1/files.json', mock.lastRequest().getEndpoint());
  }

  @IsTest
  static void testLastRequest_WhenNothingSent_ThenReturnsNull() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .when().method('GET').respond('{}', 200);

    // Act & Assert
    Assert.isNull(mock.lastRequest());
  }

  @IsTest
  static void testWhen_WhenEndpointEqualsMatches_ThenExactMatchOnly() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler('{"fallback":true}', 200);
    mock.when().endpointEquals('https://example.com/k/v1/record.json').respond('{"exact":true}', 200);

    // Act & Assert - 完全一致のみマッチ、部分一致はフォールバック
    mock.send(buildRequest('GET', 'https://example.com/k/v1/record.json'));
    Assert.areEqual('{"exact":true}', mock.getBody());

    mock.send(buildRequest('GET', 'https://example.com/k/v1/record.json?id=1'));
    Assert.areEqual('{"fallback":true}', mock.getBody());
  }

  @IsTest
  static void testWhen_WhenMatcherIsNull_ThenThrowsException() {
    // Act & Assert
    try {
      new MockHttpRequestHandler().when(null);
      Assert.fail('Exception should be thrown');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(e.getMessage().contains('Matcher cannot be null'), e.getMessage());
    }
  }

  @IsTest
  static void testRespond_WhenNoCriteria_ThenThrowsException() {
    // Act & Assert
    try {
      new MockHttpRequestHandler().when().respond('{}', 200);
      Assert.fail('Exception should be thrown');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(e.getMessage().contains('at least one condition'), e.getMessage());
    }
  }

  @IsTest
  static void testThenRespond_WhenNoMatcherRegistered_ThenThrowsException() {
    // Act & Assert
    try {
      new MockHttpRequestHandler().thenRespond('{}', 200);
      Assert.fail('Exception should be thrown');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(e.getMessage().contains('requires a preceding when'), e.getMessage());
    }
  }

  /**
   * @description Custom predicate example: matches when the JSON body has a 'record' key.
   */
  private class HasRecordKeyMatcher implements IRequestMatcher {
    public Boolean matches(HttpRequest request) {
      if (request.getBody() == null) {
        return false;
      }
      Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
      return body.containsKey('record');
    }
  }
}
