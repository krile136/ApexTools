/**
 * @description MockHttpRequestHandler のテストクラス
 */
@IsTest
private class MockHttpRequestHandlerTest {
  private static HttpRequest buildRequest(String method, String endpoint) {
    HttpRequest req = new HttpRequest();
    req.setMethod(method);
    req.setEndpoint(endpoint);
    return req;
  }

  // ===============================================================================
  // Method-keyed queues (constructor mode)
  // ===============================================================================

  @IsTest
  static void testSend_WhenSingleResponse_ThenReturnsIt() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler(
      MockResponse.of('GET').respond('{"found":true}', 200)
    );
    HttpRequest req = buildRequest('GET', 'https://example.com/records');

    // Act
    mock.send(req);

    // Assert
    Assert.areEqual(200, mock.getStatusCode());
    Assert.areEqual('{"found":true}', mock.getBody());
    Assert.areEqual(1, mock.sentRequests.size());
    Assert.areEqual(req, mock.sentRequests[0]);
  }

  @IsTest
  static void testSend_WhenMethodCaseDiffers_ThenNormalizedAndMatched() {
    // Arrange - of('get') 小文字宣言でも GET リクエストにマッチ
    MockHttpRequestHandler mock = new MockHttpRequestHandler(
      MockResponse.of('get').respond('{"ok":true}', 200)
    );

    // Act
    mock.send(buildRequest('GET', 'https://example.com'));

    // Assert
    Assert.areEqual(200, mock.getStatusCode());
  }

  @IsTest
  static void testSend_WhenSameMethodQueued_ThenConsumedInOrder() {
    // Arrange - GET は宣言順に消費される (存在確認 404 → 作成後 200)
    MockHttpRequestHandler mock = new MockHttpRequestHandler(new List<MockResponse>{
      MockResponse.of('GET').respond('{"message":"not found"}', 404),
      MockResponse.of('GET').respond('{"record":{}}', 200)
    });

    // Act & Assert
    mock.send(buildRequest('GET', 'https://example.com'));
    Assert.areEqual(404, mock.getStatusCode());

    mock.send(buildRequest('GET', 'https://example.com'));
    Assert.areEqual(200, mock.getStatusCode());
  }

  @IsTest
  static void testSend_WhenMethodsInterleaved_ThenOrderIndependent() {
    // Arrange - 宣言順は GET, GET, POST だが、呼び出し順に依存しない
    MockHttpRequestHandler mock = new MockHttpRequestHandler(new List<MockResponse>{
      MockResponse.of('GET').respond('{"n":1}', 200),
      MockResponse.of('GET').respond('{"n":2}', 200),
      MockResponse.of('POST').respond('{"created":true}', 201)
    });

    // Act & Assert - POST を先に呼んでも POST の応答が返る
    mock.send(buildRequest('POST', 'https://example.com'));
    Assert.areEqual(201, mock.getStatusCode());

    mock.send(buildRequest('GET', 'https://example.com'));
    Assert.areEqual('{"n":1}', mock.getBody());

    mock.send(buildRequest('GET', 'https://example.com'));
    Assert.areEqual('{"n":2}', mock.getBody());
  }

  @IsTest
  static void testRepeat_WhenDeclaredOnLast_ThenAnswersForever() {
    // Arrange - 1回目 404、以降ずっと 200
    MockHttpRequestHandler mock = new MockHttpRequestHandler(new List<MockResponse>{
      MockResponse.of('GET').respond('{"message":"not found"}', 404),
      MockResponse.of('GET').respond('{"record":{}}', 200).repeat()
    });

    // Act & Assert
    mock.send(buildRequest('GET', 'https://example.com'));
    Assert.areEqual(404, mock.getStatusCode());
    for (Integer i = 0; i < 3; i++) {
      mock.send(buildRequest('GET', 'https://example.com'));
      Assert.areEqual(200, mock.getStatusCode(), 'repeat() response should answer every further GET');
    }
  }

  @IsTest
  static void testRegister_WhenRepeatIsNotLast_ThenThrowsException() {
    // Act & Assert - repeat() の後ろに同メソッドの応答は積めない (到達不能のため)
    try {
      new MockHttpRequestHandler(new List<MockResponse>{
        MockResponse.of('GET').respond('{"a":1}', 200).repeat(),
        MockResponse.of('GET').respond('{"b":2}', 200)
      });
      Assert.fail('Exception should be thrown');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(e.getMessage().contains('must be the last'), e.getMessage());
    }
  }

  @IsTest
  static void testSend_WhenQueueExhausted_ThenDetailedErrorAndRequestNotRecorded() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler(
      MockResponse.of('GET').respond('{"ok":true}', 200)
    );
    mock.send(buildRequest('GET', 'https://example.com/first'));
    CalloutException caughtException = null;

    // Act - 2回目の GET は枯渇
    try {
      mock.send(buildRequest('GET', 'https://example.com/second'));
    } catch (CalloutException e) {
      caughtException = e;
    }

    // Assert - 実リクエストとキュー状態が読めるエラー
    Assert.isNotNull(caughtException);
    String message = caughtException.getMessage();
    Assert.isTrue(message.contains('No mock response available for: GET https://example.com/second'), message);
    Assert.isTrue(message.contains('[get: 1 of 1 consumed]'), message);
    Assert.areEqual(1, mock.sentRequests.size(), 'Failed request should not be recorded');
  }

  @IsTest
  static void testSend_WhenMethodHasNoQueue_ThenDetailedError() {
    // Arrange - DELETE の応答は未宣言
    MockHttpRequestHandler mock = new MockHttpRequestHandler(
      MockResponse.of('POST').respond('{"ok":true}', 200)
    );
    CalloutException caughtException = null;

    // Act
    try {
      mock.send(buildRequest('DELETE', 'https://example.com'));
    } catch (CalloutException e) {
      caughtException = e;
    }

    // Assert
    Assert.isNotNull(caughtException);
    Assert.isTrue(caughtException.getMessage().contains('[post: 0 of 1 consumed]'), caughtException.getMessage());
  }

  // ===============================================================================
  // MockResponse content forms
  // ===============================================================================

  @IsTest
  static void testRespond_WhenMapBody_ThenJsonSerialized() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler(
      MockResponse.of('GET').respond(new Map<String, Object>{ 'id' => 'map123', 'success' => true }, 200)
    );

    // Act
    mock.send(buildRequest('GET', 'https://example.com'));

    // Assert
    Map<String, Object> actualBody = (Map<String, Object>) JSON.deserializeUntyped(mock.getBody());
    Assert.areEqual('map123', actualBody.get('id'));
    Assert.areEqual(true, actualBody.get('success'));
  }

  @IsTest
  static void testRespond_WhenListBody_ThenJsonSerialized() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler(
      MockResponse.of('GET').respond(new List<Object>{ 'a', 'b' }, 200)
    );

    // Act
    mock.send(buildRequest('GET', 'https://example.com'));

    // Assert
    List<Object> actualBody = (List<Object>) JSON.deserializeUntyped(mock.getBody());
    Assert.areEqual(2, actualBody.size());
    Assert.areEqual('a', actualBody[0]);
  }

  @IsTest
  static void testGuards_WhenInvalidDeclarations_ThenThrowExceptions() {
    // of の空メソッド
    try {
      MockResponse.of('');
      Assert.fail('Exception should be thrown');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(e.getMessage().contains('Method cannot be blank'), e.getMessage());
    }
    // statusCode null
    try {
      MockResponse.of('GET').respond('{}', null);
      Assert.fail('Exception should be thrown');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(e.getMessage().contains('StatusCode cannot be null'), e.getMessage());
    }
    // respond 未呼び出しの登録
    try {
      new MockHttpRequestHandler(MockResponse.of('GET'));
      Assert.fail('Exception should be thrown');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(e.getMessage().contains('has no content'), e.getMessage());
    }
    // 空リスト
    try {
      new MockHttpRequestHandler(new List<MockResponse>());
      Assert.fail('Exception should be thrown');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(e.getMessage().contains('cannot be null or empty'), e.getMessage());
    }
  }

  @IsTest
  static void testGetBody_WhenSendNotCalled_ThenThrowsException() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler(
      MockResponse.of('GET').respond('{}', 200)
    );

    // Act & Assert
    try {
      mock.getBody();
      Assert.fail('Exception should be thrown');
    } catch (JSONException e) {
      Assert.isTrue(e.getMessage().contains('Ensure send() has been called'), e.getMessage());
    }
  }

  // ===============================================================================
  // Binary bodies and headers
  // ===============================================================================

  @IsTest
  static void testGetBodyAsBlob_WhenBlobConfigured_ThenSameBytesReturned() {
    // Arrange - 実際のバイナリ (非テキスト) のバイト列
    Blob imageBytes = EncodingUtil.base64Decode('/9j/4AAQSkZJRgABAQAAAQ==');
    MockHttpRequestHandler mock = new MockHttpRequestHandler(
      MockResponse.of('GET').respond(imageBytes, 200).header('Content-Type', 'image/jpeg')
    );

    // Act
    mock.send(buildRequest('GET', 'https://api.sansan.com/v1/bizCards/xxx/image'));

    // Assert
    Assert.areEqual(
      EncodingUtil.base64Encode(imageBytes),
      EncodingUtil.base64Encode(mock.getBodyAsBlob()),
      'Blob body should round-trip byte-identically'
    );
    Assert.areEqual(200, mock.getStatusCode());
  }

  @IsTest
  static void testGetHeader_WhenConfigured_ThenCaseInsensitiveLookup() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler(
      MockResponse.of('GET').respond('{}', 200).header('Content-Type', 'application/json')
    );

    // Act
    mock.send(buildRequest('GET', 'https://example.com'));

    // Assert - HTTP ヘッダは大文字小文字を区別しない / 未設定は null
    Assert.areEqual('application/json', mock.getHeader('Content-Type'));
    Assert.areEqual('application/json', mock.getHeader('content-type'));
    Assert.isNull(mock.getHeader('X-Request-Id'));
  }

  @IsTest
  static void testGetBodyAsBlob_WhenStringConfigured_ThenFallsBackToValueOf() {
    // Arrange - 既存の String 本文の書き方でも getBodyAsBlob() が使える (移行容易性)
    MockHttpRequestHandler mock = new MockHttpRequestHandler(
      MockResponse.of('GET').respond('{"ok":true}', 200)
    );

    // Act
    mock.send(buildRequest('GET', 'https://example.com'));

    // Assert
    Assert.areEqual('{"ok":true}', mock.getBodyAsBlob().toString());
  }

  @IsTest
  static void testContentTypeGuard_WhenWrongEndpoint_ThenGuardCatchesIt() {
    // Arrange - 実事故の再現: 画像エンドポイントのつもりが JSON が返る誤ったURL。
    // Content-Type ガードがあれば HTTP 200 でも壊れた画像を画面に流さず検知できる
    MockHttpRequestHandler mock = new MockHttpRequestHandler(
      MockResponse.of('GET').respond('{"bizCardId":"xxx"}', 200).header('Content-Type', 'application/json')
    );

    // Act
    mock.send(buildRequest('GET', 'https://api.sansan.com/v1/bizCards/xxx'));

    // Assert - ガード側の判定がモックの枠内で検証できる
    Assert.areEqual(200, mock.getStatusCode());
    Assert.isFalse(mock.getHeader('Content-Type').startsWith('image/'),
      'The guard condition itself is testable inside the framework now');
  }

  // ===============================================================================
  // Label mode (attach / label)
  // ===============================================================================

  @IsTest
  static void testAttach_WhenLabeled_ThenRoutedByLabel() {
    // Arrange - 同じ GET でもラベルで応答を出し分けられる
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .attach('exists', MockResponse.of('GET').respond('{"message":"not found"}', 404))
      .attach('fetch', MockResponse.of('GET').respond('{"record":{}}', 200));

    // Act & Assert
    mock.label('fetch').send(buildRequest('GET', 'https://example.com'));
    Assert.areEqual(200, mock.getStatusCode());

    mock.label('exists').send(buildRequest('GET', 'https://example.com'));
    Assert.areEqual(404, mock.getStatusCode());
  }

  @IsTest
  static void testSend_WhenAttachUsedWithoutLabel_ThenThrowsException() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .attach('exists', MockResponse.of('GET').respond('{}', 200));

    // Act & Assert
    try {
      mock.send(buildRequest('GET', 'https://example.com'));
      Assert.fail('Exception should be thrown');
    } catch (CalloutException e) {
      Assert.isTrue(e.getMessage().contains('without label()'), e.getMessage());
      Assert.isTrue(e.getMessage().contains('exists'), e.getMessage());
    }
  }

  @IsTest
  static void testSend_WhenUnknownLabel_ThenThrowsException() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .attach('exists', MockResponse.of('GET').respond('{}', 200));
    CalloutException caughtException = null;

    // Act
    try {
      mock.label('tyop').send(buildRequest('GET', 'https://example.com'));
    } catch (CalloutException e) {
      caughtException = e;
    }

    // Assert - タイポしたラベルと登録済みラベル一覧が読める
    Assert.isNotNull(caughtException);
    Assert.isTrue(caughtException.getMessage().contains('\'tyop\' has no attached responses'), caughtException.getMessage());
    Assert.isTrue(caughtException.getMessage().contains('exists'), caughtException.getMessage());
  }

  @IsTest
  static void testLabel_WhenConsumed_ThenNextSendNeedsLabelAgain() {
    // Arrange - ラベルは send 1回で消費される (MockEloquent と同じ)
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .attach('fetch', new List<MockResponse>{
        MockResponse.of('GET').respond('{"n":1}', 200),
        MockResponse.of('GET').respond('{"n":2}', 200)
      });
    mock.label('fetch').send(buildRequest('GET', 'https://example.com'));

    // Act & Assert
    try {
      mock.send(buildRequest('GET', 'https://example.com'));
      Assert.fail('Exception should be thrown');
    } catch (CalloutException e) {
      Assert.isTrue(e.getMessage().contains('without label()'), e.getMessage());
    }
  }

  @IsTest
  static void testLabel_WhenNoAttachUsed_ThenIgnored() {
    // Arrange - label() 付き本番コードを、素のコンストラクタモックでもテストできる
    MockHttpRequestHandler mock = new MockHttpRequestHandler(
      MockResponse.of('GET').respond('{"ok":true}', 200)
    );

    // Act
    mock.label('anything').send(buildRequest('GET', 'https://example.com'));

    // Assert
    Assert.areEqual(200, mock.getStatusCode());
  }

  @IsTest
  static void testAttach_WhenMixedWithConstructorResponses_ThenThrowsException() {
    // Act & Assert
    try {
      new MockHttpRequestHandler(MockResponse.of('GET').respond('{}', 200))
        .attach('exists', MockResponse.of('GET').respond('{}', 200));
      Assert.fail('Exception should be thrown');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(e.getMessage().contains('Cannot mix attach()'), e.getMessage());
    }
  }

  @IsTest
  static void testSend_WhenLabeledMethodMismatch_ThenDetailedError() {
    // Arrange - POST を宣言したラベルに GET が来たら分岐バグとして検知
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .attach('create', MockResponse.of('POST').respond('{}', 200));
    CalloutException caughtException = null;

    // Act
    try {
      mock.label('create').send(buildRequest('GET', 'https://example.com'));
    } catch (CalloutException e) {
      caughtException = e;
    }

    // Assert
    Assert.isNotNull(caughtException);
    Assert.isTrue(caughtException.getMessage().contains('GET'), caughtException.getMessage());
    Assert.isTrue(caughtException.getMessage().contains('[post: 0 of 1 consumed]'), caughtException.getMessage());
  }

  // ===============================================================================
  // Verification helpers
  // ===============================================================================

  @IsTest
  static void testHelpers_WhenRequestsSent_ThenCountAndFilterWork() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler(new List<MockResponse>{
      MockResponse.of('GET').respond('{"a":1}', 200).repeat(),
      MockResponse.of('POST').respond('{"b":2}', 200)
    });

    // Act
    mock.send(buildRequest('GET', 'https://example.com/k/v1/records.json'));
    mock.send(buildRequest('POST', 'https://example.com/k/v1/records.json'));
    mock.send(buildRequest('GET', 'https://example.com/k/v1/files.json'));

    // Assert
    Assert.areEqual(2, mock.countByMethod('GET'));
    Assert.areEqual(1, mock.countByMethod('post'));
    Assert.areEqual(0, mock.countByMethod('PUT'));
    Assert.areEqual(2, mock.requestsTo('/records.json').size());
    Assert.areEqual('https://example.com/k/v1/files.json', mock.lastRequest().getEndpoint());
  }

  @IsTest
  static void testSentRequestsAt_WhenLabeled_ThenFilteredByLabel() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .attach('exists', MockResponse.of('GET').respond('{}', 404))
      .attach('create', MockResponse.of('POST').respond('{}', 200));

    // Act
    mock.label('exists').send(buildRequest('GET', 'https://example.com/a'));
    mock.label('create').send(buildRequest('POST', 'https://example.com/b'));

    // Assert
    Assert.areEqual(1, mock.sentRequestsAt('exists').size());
    Assert.areEqual('https://example.com/a', mock.sentRequestsAt('exists')[0].getEndpoint());
    Assert.areEqual(1, mock.sentRequestsAt('create').size());
    Assert.areEqual(0, mock.sentRequestsAt('nothing').size());
  }

  @IsTest
  static void testLastRequest_WhenNothingSent_ThenReturnsNull() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler(
      MockResponse.of('GET').respond('{}', 200)
    );

    // Act & Assert
    Assert.isNull(mock.lastRequest());
  }
}
