/**
 * @description Test class for MockHttpRequestHandler
 * @directory ApexTools/HttpRequest/tests
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
  // Script mode (constructor list = the flow's script, consumed strictly in order)
  // ===============================================================================

  @IsTest
  static void testScript_WhenFlowFollowsScript_ThenConsumedInOrder() {
    // Arrange - script: existence-check GET 404 -> create POST 201 -> re-fetch GET 200
    MockHttpRequestHandler mock = new MockHttpRequestHandler(new List<MockResponse>{
      MockResponse.of('GET').respond('{"message":"not found"}', 404),
      MockResponse.of('POST').respond('{"created":true}', 201),
      MockResponse.of('GET').respond('{"record":{}}', 200)
    });

    // Act & Assert - consumed one step at a time, following the script
    mock.send(buildRequest('GET', 'https://example.com/records/1'));
    Assert.areEqual(404, mock.getStatusCode());

    mock.send(buildRequest('POST', 'https://example.com/records'));
    Assert.areEqual(201, mock.getStatusCode());

    mock.send(buildRequest('GET', 'https://example.com/records/1'));
    Assert.areEqual(200, mock.getStatusCode());
    Assert.areEqual(3, mock.sentRequests.size());
  }

  @IsTest
  static void testScript_WhenOrderDeviates_ThenMethodMismatchAndNothingConsumed() {
    // Arrange - the first step of the script is a GET
    MockHttpRequestHandler mock = new MockHttpRequestHandler(new List<MockResponse>{
      MockResponse.of('GET').respond('{"a":1}', 200),
      MockResponse.of('POST').respond('{"b":2}', 201)
    });
    CalloutException caughtException = null;

    // Act - deviate from the script by sending POST first
    try {
      mock.send(buildRequest('POST', 'https://example.com/records'));
    } catch (CalloutException e) {
      caughtException = e;
    }

    // Assert - the error names the expected method and the actual request; nothing is consumed or recorded
    Assert.isNotNull(caughtException);
    String message = caughtException.getMessage();
    Assert.isTrue(message.contains('Next queued response expects GET'), message);
    Assert.isTrue(message.contains('the request was: POST https://example.com/records'), message);
    Assert.isTrue(message.contains('Queue: 0 of 2 consumed'), message);
    Assert.areEqual(0, mock.sentRequests.size(), 'Mismatched request should not be recorded');

    // Act & Assert - resending in the correct order proceeds normally (the queue was not corrupted)
    mock.send(buildRequest('GET', 'https://example.com/records/1'));
    Assert.areEqual(200, mock.getStatusCode());
  }

  @IsTest
  static void testScript_WhenSingleResponse_ThenReturnsIt() {
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
    Assert.areEqual(req, mock.sentRequests[0]);
  }

  @IsTest
  static void testScript_WhenMethodCaseDiffers_ThenMatched() {
    // Arrange - a lowercase of('get') declaration still matches a GET request
    MockHttpRequestHandler mock = new MockHttpRequestHandler(
      MockResponse.of('get').respond('{"ok":true}', 200)
    );

    // Act
    mock.send(buildRequest('GET', 'https://example.com'));

    // Assert
    Assert.areEqual(200, mock.getStatusCode());
  }

  @IsTest
  static void testScript_WhenRepeatOnLast_ThenAnswersForeverWithMethodCheck() {
    // Arrange - 404 on the first call, then 200 forever
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

    // Assert - the method contract check stays active while repeating
    try {
      mock.send(buildRequest('POST', 'https://example.com'));
      Assert.fail('Exception should be thrown');
    } catch (CalloutException e) {
      Assert.isTrue(e.getMessage().contains('Next queued response expects GET'), e.getMessage());
    }
  }

  @IsTest
  static void testScript_WhenExhausted_ThenDetailedErrorAndRequestNotRecorded() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler(
      MockResponse.of('GET').respond('{"ok":true}', 200)
    );
    mock.send(buildRequest('GET', 'https://example.com/first'));
    CalloutException caughtException = null;

    // Act - the script is exhausted on the second call
    try {
      mock.send(buildRequest('GET', 'https://example.com/second'));
    } catch (CalloutException e) {
      caughtException = e;
    }

    // Assert
    Assert.isNotNull(caughtException);
    String message = caughtException.getMessage();
    Assert.isTrue(message.contains('No mock response available for: GET https://example.com/second'), message);
    Assert.isTrue(message.contains('Scope: the default script'), message);
    Assert.isTrue(message.contains('Queue: 1 of 1 consumed'), message);
    Assert.areEqual(1, mock.sentRequests.size(), 'Failed request should not be recorded');
  }

  @IsTest
  static void testRegister_WhenRepeatIsNotLast_ThenThrowsException() {
    // Act & Assert - no response can be queued after repeat() (it would be unreachable)
    try {
      new MockHttpRequestHandler(new List<MockResponse>{
        MockResponse.of('GET').respond('{"a":1}', 200).repeat(),
        MockResponse.of('POST').respond('{"b":2}', 201)
      });
      Assert.fail('Exception should be thrown');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(e.getMessage().contains('must be the last'), e.getMessage());
    }
  }

  // ===============================================================================
  // Label mode - branch flows (GET first, then either POST or PUT)
  // ===============================================================================

  @IsTest
  static void testLabel_WhenCreateBranchTaken_ThenOnlyCreateConsumed() {
    // Arrange - upsert flow: existence-check GET returns 404 -> the POST (create) branch runs.
    // Both branches are attached; which one was consumed tells which branch ran
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .attach('exists', MockResponse.of('GET').respond('{"message":"not found"}', 404))
      .attach('create', MockResponse.of('POST').respond('{"created":true}', 201))
      .attach('update', MockResponse.of('PUT').respond('{"updated":true}', 200));

    // Act - the create-branch flow
    mock.label('exists').send(buildRequest('GET', 'https://example.com/records/1'));
    Assert.areEqual(404, mock.getStatusCode());
    mock.label('create').send(buildRequest('POST', 'https://example.com/records'));
    Assert.areEqual(201, mock.getStatusCode());

    // Assert - only create was consumed; update stays unused (an unused attach is harmless)
    Assert.areEqual(1, mock.sentRequestsAt('exists').size());
    Assert.areEqual(1, mock.sentRequestsAt('create').size());
    Assert.areEqual(0, mock.sentRequestsAt('update').size());
    Assert.areEqual(0, mock.countByMethod('PUT'));
  }

  @IsTest
  static void testLabel_WhenUpdateBranchTaken_ThenOnlyUpdateConsumed() {
    // Arrange - existence-check GET returns 200 -> the PUT (update) branch runs
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .attach('exists', MockResponse.of('GET').respond('{"record":{}}', 200))
      .attach('create', MockResponse.of('POST').respond('{"created":true}', 201))
      .attach('update', MockResponse.of('PUT').respond('{"updated":true}', 200));

    // Act - the update-branch flow
    mock.label('exists').send(buildRequest('GET', 'https://example.com/records/1'));
    mock.label('update').send(buildRequest('PUT', 'https://example.com/records/1'));

    // Assert
    Assert.areEqual(1, mock.sentRequestsAt('update').size());
    Assert.areEqual(0, mock.sentRequestsAt('create').size());
    Assert.areEqual(0, mock.countByMethod('POST'));
  }

  @IsTest
  static void testLabel_WhenRetrySequence_ThenConsumesInOrderAndExhausts() {
    // Arrange - retry script for a single site: 500, 500, then 200
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .attach('sync', new List<MockResponse>{
        MockResponse.of('POST').respond('{"error":"server"}', 500),
        MockResponse.of('POST').respond('{"error":"server"}', 500),
        MockResponse.of('POST').respond('{"ok":true}', 200)
      });

    // Act & Assert - the queue is consumed exactly one step at a time
    mock.label('sync').send(buildRequest('POST', 'https://example.com/sync'));
    Assert.areEqual(500, mock.getStatusCode());
    mock.label('sync').send(buildRequest('POST', 'https://example.com/sync'));
    Assert.areEqual(500, mock.getStatusCode());
    mock.label('sync').send(buildRequest('POST', 'https://example.com/sync'));
    Assert.areEqual(200, mock.getStatusCode());

    // Assert - the fourth call (an overrun) is caught as exhaustion
    try {
      mock.label('sync').send(buildRequest('POST', 'https://example.com/sync'));
      Assert.fail('Exception should be thrown');
    } catch (CalloutException e) {
      Assert.isTrue(e.getMessage().contains('Scope: label \'sync\''), e.getMessage());
      Assert.isTrue(e.getMessage().contains('Queue: 3 of 3 consumed'), e.getMessage());
    }
  }

  @IsTest
  static void testLabel_WhenMixedMethodSequenceInLabel_ThenOrderEnforced() {
    // Arrange - one site script with two steps, GET -> PUT (order enforced by the method contract)
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .attach('flow', new List<MockResponse>{
        MockResponse.of('GET').respond('{"n":1}', 200),
        MockResponse.of('PUT').respond('{"n":2}', 200)
      });

    // Act & Assert - sending PUT first violates the script
    try {
      mock.label('flow').send(buildRequest('PUT', 'https://example.com'));
      Assert.fail('Exception should be thrown');
    } catch (CalloutException e) {
      Assert.isTrue(e.getMessage().contains('Next queued response expects GET'), e.getMessage());
    }

    // Assert - the correct order proceeds normally
    mock.label('flow').send(buildRequest('GET', 'https://example.com'));
    Assert.areEqual('{"n":1}', mock.getBody());
    mock.label('flow').send(buildRequest('PUT', 'https://example.com'));
    Assert.areEqual('{"n":2}', mock.getBody());
  }

  @IsTest
  static void testLabel_WhenQueueHeadMethodMismatch_ThenDetailedError() {
    // Arrange - a GET arriving at a site that declares POST is caught as a branch bug
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .attach('create', MockResponse.of('POST').respond('{}', 201));
    CalloutException caughtException = null;

    // Act
    try {
      mock.label('create').send(buildRequest('GET', 'https://example.com'));
    } catch (CalloutException e) {
      caughtException = e;
    }

    // Assert
    Assert.isNotNull(caughtException);
    String message = caughtException.getMessage();
    Assert.isTrue(message.contains('Next queued response expects POST'), message);
    Assert.isTrue(message.contains('Scope: label \'create\''), message);
  }

  @IsTest
  static void testAttach_WhenSameLabelTwice_ThenAppendsToQueue() {
    // Arrange - attaching to the same label appends to its queue
    MockHttpRequestHandler mock = new MockHttpRequestHandler()
      .attach('sync', MockResponse.of('POST').respond('{"n":1}', 500))
      .attach('sync', MockResponse.of('POST').respond('{"n":2}', 200));

    // Act & Assert
    mock.label('sync').send(buildRequest('POST', 'https://example.com'));
    Assert.areEqual(500, mock.getStatusCode());
    mock.label('sync').send(buildRequest('POST', 'https://example.com'));
    Assert.areEqual(200, mock.getStatusCode());
  }

  // ===============================================================================
  // Label mode - routing rules
  // ===============================================================================

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
  static void testSend_WhenUnknownLabel_ThenThrowsWithRegisteredLabels() {
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

    // Assert - the typo'd label and the registered-label list are both readable
    Assert.isNotNull(caughtException);
    Assert.isTrue(caughtException.getMessage().contains('\'tyop\' has no attached responses'), caughtException.getMessage());
    Assert.isTrue(caughtException.getMessage().contains('exists'), caughtException.getMessage());
  }

  @IsTest
  static void testLabel_WhenConsumed_ThenNextSendNeedsLabelAgain() {
    // Arrange - a label is consumed per send (same as MockEloquent)
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
    // Arrange - labeled production code can still be tested with a plain script mock
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
    // blank method passed to of()
    try {
      MockResponse.of('');
      Assert.fail('Exception should be thrown');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(e.getMessage().contains('Method cannot be blank'), e.getMessage());
    }
    // null statusCode
    try {
      MockResponse.of('GET').respond('{}', null);
      Assert.fail('Exception should be thrown');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(e.getMessage().contains('StatusCode cannot be null'), e.getMessage());
    }
    // registering without calling respond()
    try {
      new MockHttpRequestHandler(MockResponse.of('GET'));
      Assert.fail('Exception should be thrown');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(e.getMessage().contains('has no content'), e.getMessage());
    }
    // empty list
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
    // Arrange - genuinely binary (non-text) bytes
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

    // Assert - HTTP headers are case-insensitive / unset headers are null
    Assert.areEqual('application/json', mock.getHeader('Content-Type'));
    Assert.areEqual('application/json', mock.getHeader('content-type'));
    Assert.isNull(mock.getHeader('X-Request-Id'));
  }

  @IsTest
  static void testGetBodyAsBlob_WhenStringConfigured_ThenFallsBackToValueOf() {
    // Arrange - getBodyAsBlob() also works for string-configured responses (easy migration)
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
    // Arrange - reproduces a real incident: a wrong URL returns JSON where an image was expected.
    // A Content-Type guard catches it despite the HTTP 200, before a broken image reaches the UI
    MockHttpRequestHandler mock = new MockHttpRequestHandler(
      MockResponse.of('GET').respond('{"bizCardId":"xxx"}', 200).header('Content-Type', 'application/json')
    );

    // Act
    mock.send(buildRequest('GET', 'https://api.sansan.com/v1/bizCards/xxx'));

    // Assert - the guard condition itself is verifiable inside the mock framework
    Assert.areEqual(200, mock.getStatusCode());
    Assert.isFalse(mock.getHeader('Content-Type').startsWith('image/'),
      'The guard condition itself is testable inside the framework now');
  }

  // ===============================================================================
  // Verification helpers
  // ===============================================================================

  @IsTest
  static void testHelpers_WhenRequestsSent_ThenCountAndFilterWork() {
    // Arrange
    MockHttpRequestHandler mock = new MockHttpRequestHandler(new List<MockResponse>{
      MockResponse.of('GET').respond('{"a":1}', 200),
      MockResponse.of('POST').respond('{"b":2}', 200),
      MockResponse.of('GET').respond('{"c":3}', 200)
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
      .attach('create', MockResponse.of('POST').respond('{}', 201));

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
