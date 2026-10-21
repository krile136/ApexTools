/**
 * @directory ApexTools/TriggerHandler/tests
 */
@isTest
public with sharing class TriggerHandlerTest {
  private class TestTriggerHandler extends TriggerHandler {
    public TriggerOperation context;

    @TestVisible
    protected override void beforeInsert(List<SObject> newRecords) {
      this.context = TriggerOperation.BEFORE_INSERT;
    }

    @TestVisible
    protected override void beforeUpdate(Map<Id, SObject> newMap, Map<Id, SObject> oldMap) {
      this.context = TriggerOperation.BEFORE_UPDATE;
    }

    @TestVisible
    protected override void beforeDelete(Map<Id, SObject> oldMap) {
      this.context = TriggerOperation.BEFORE_DELETE;
    }

    @TestVisible
    protected override void afterInsert(Map<Id, SObject> newMap) {
      this.context = TriggerOperation.AFTER_INSERT;
    }

    @TestVisible
    protected override void afterUpdate(Map<Id, SObject> newMap, Map<Id, SObject> oldMap) {
      this.context = TriggerOperation.AFTER_UPDATE;
    }

    @TestVisible
    protected override void afterDelete(Map<Id, SObject> oldMap) {
      this.context = TriggerOperation.AFTER_DELETE;
    }

    @TestVisible
    protected override void afterUndelete(Map<Id, SObject> newMap) {
      this.context = TriggerOperation.AFTER_UNDELETE;
    }
  }

  @isTest
  static void testExecute_BeforeInsert() {
    // Arrange
    TestTriggerHandler handler = new TestTriggerHandler();
    handler.triggerContext = TriggerOperation.BEFORE_INSERT;

    // Act
    handler.execute();

    // Assert
    Assert.isTrue(TriggerOperation.BEFORE_INSERT.equals(handler.context));
  }

  @isTest
  static void testExecute_BeforeUpdate() {
    // Arrange
    TestTriggerHandler handler = new TestTriggerHandler();
    handler.triggerContext = TriggerOperation.BEFORE_UPDATE;

    // Act
    handler.execute();

    // Assert
    Assert.isTrue(TriggerOperation.BEFORE_UPDATE.equals(handler.context));
  }

  @isTest
  static void testExecute_BeforeDelete() {
    // Arrange
    TestTriggerHandler handler = new TestTriggerHandler();
    handler.triggerContext = TriggerOperation.BEFORE_DELETE;

    // Act
    handler.execute();

    // Assert
    Assert.isTrue(TriggerOperation.BEFORE_DELETE.equals(handler.context));
  }

  @isTest
  static void testExecute_AfterInsert() {
    // Arrange
    TestTriggerHandler handler = new TestTriggerHandler();
    handler.triggerContext = TriggerOperation.AFTER_INSERT;

    // Act
    handler.execute();

    // Assert
    Assert.isTrue(TriggerOperation.AFTER_INSERT.equals(handler.context));
  }

  @isTest
  static void testExecute_AfterUpdate() {
    // Arrange
    TestTriggerHandler handler = new TestTriggerHandler();
    handler.triggerContext = TriggerOperation.AFTER_UPDATE;

    // Act
    handler.execute();

    // Assert
    Assert.isTrue(TriggerOperation.AFTER_UPDATE.equals(handler.context));
  }

  @isTest
  static void testExecute_AfterDelete() {
    // Arrange
    TestTriggerHandler handler = new TestTriggerHandler();
    handler.triggerContext = TriggerOperation.AFTER_DELETE;
    // Act
    handler.execute();
    // Assert
    Assert.isTrue(TriggerOperation.AFTER_DELETE.equals(handler.context));
  }

  @isTest
  static void testExecute_AfterUndelete() {
    // Arrange
    TestTriggerHandler handler = new TestTriggerHandler();
    handler.triggerContext = TriggerOperation.AFTER_UNDELETE;
    // Act
    handler.execute();
    // Assert
    Assert.isTrue(TriggerOperation.AFTER_UNDELETE.equals(handler.context));
  }

  @isTest
  static void testGetUpdatedRecordsWithChangedFiled_WhenFieldChanged_ThenReturnRecords() {
    // Arrange
    Account oldAccount = new Account(Id = '001000000000001', Name = 'Old Name');
    Account newAccount = new Account(Id = '001000000000001', Name = 'New Name');

    TestTriggerHandler handler = new TestTriggerHandler();
    handler.newRecords = new List<SObject>{ newAccount };
    handler.oldRecordsMap = new Map<Id, SObject>{ oldAccount.Id => oldAccount };

    // Act
    List<SObject> changedRecords = handler.getUpdatedRecordsWithChangedField(Account.Name);

    // Assert
    Assert.areEqual(1, changedRecords.size());
    Assert.areEqual(newAccount.Id, changedRecords[0].Id);
  }

  @isTest
  static void testGetUpdatedIdsWithChangedFiled_WhenFieldChanged_ThenReturnIds() {
    // Arrange
    Account oldAccount = new Account(Id = '001000000000001', Name = 'Old Name');
    Account newAccount = new Account(Id = '001000000000001', Name = 'New Name');

    TestTriggerHandler handler = new TestTriggerHandler();
    handler.newRecords = new List<SObject>{ newAccount };
    handler.oldRecordsMap = new Map<Id, SObject>{ oldAccount.Id => oldAccount };

    // Act
    Set<Id> changedIds = handler.getUpdateRecordIdsWithChangedField(Account.Name);

    // Assert
    Assert.areEqual(1, changedIds.size());
    Assert.isTrue(changedIds.contains(newAccount.Id));
  }

  @isTest
  static void testGetUpdatedRecordsWithChangedFiled_WhenFieldNotChanged_ThenReturnEmpty() {
    // Arrange
    Account oldAccount = new Account(Id = '001000000000001', Name = 'Same Name');
    Account newAccount = new Account(Id = '001000000000001', Name = 'Same Name');
    TestTriggerHandler handler = new TestTriggerHandler();
    handler.newRecords = new List<SObject>{ newAccount };
    handler.oldRecordsMap = new Map<Id, SObject>{ oldAccount.Id => oldAccount };

    // Act
    List<SObject> changedRecords = handler.getUpdatedRecordsWithChangedField(Account.Name);

    // Assert
    Assert.areEqual(0, changedRecords.size());
  }

  @isTest
  static void testGetUpdatedIdsWithChangedFiled_WhenFieldNotChanged_ThenReturnEmpty() {
    // Arrange
    Account oldAccount = new Account(Id = '001000000000001', Name = 'Same Name');
    Account newAccount = new Account(Id = '001000000000001', Name = 'Same Name');
    TestTriggerHandler handler = new TestTriggerHandler();
    handler.newRecords = new List<SObject>{ newAccount };
    handler.oldRecordsMap = new Map<Id, SObject>{ oldAccount.Id => oldAccount };

    // Act
    Set<Id> changedIds = handler.getUpdateRecordIdsWithChangedField(Account.Name);

    // Assert
    Assert.areEqual(0, changedIds.size());
  }

  @isTest
  static void testGetUpdatedRecordsWithChangedField_WhenOnlyCaseChanged_ThenReturnRecords() {
    // Arrange: Apex's String != ignores case, so 'acme' -> 'ACME' used to read as unchanged (issue #4)
    Account oldAccount = new Account(Id = '001000000000001', Name = 'acme');
    Account newAccount = new Account(Id = '001000000000001', Name = 'ACME');

    TestTriggerHandler handler = new TestTriggerHandler();
    handler.newRecords = new List<SObject>{ newAccount };
    handler.oldRecordsMap = new Map<Id, SObject>{ oldAccount.Id => oldAccount };

    // Act
    List<SObject> changedRecords = handler.getUpdatedRecordsWithChangedField(Account.Name);
    Set<Id> changedIds = handler.getUpdateRecordIdsWithChangedField(Account.Name);

    // Assert
    Assert.areEqual(1, changedRecords.size());
    Assert.isTrue(changedIds.contains(newAccount.Id));
  }

  @isTest
  static void testGetUpdatedRecordsWithChangedField_WhenOnlyIdLengthDiffers_ThenNotChanged() {
    // Arrange: a 15- and an 18-character form of the same Id stay equal (both are read back as 18 characters)
    Account oldAccount = new Account(Id = '001000000000001', ParentId = '001000000000002');
    Account newAccount = new Account(Id = '001000000000001', ParentId = '001000000000002AAA');

    TestTriggerHandler handler = new TestTriggerHandler();
    handler.newRecords = new List<SObject>{ newAccount };
    handler.oldRecordsMap = new Map<Id, SObject>{ oldAccount.Id => oldAccount };

    // Act
    List<SObject> changedRecords = handler.getUpdatedRecordsWithChangedField(Account.ParentId);

    // Assert
    Assert.areEqual(0, changedRecords.size());
  }

  @isTest
  static void testGetUpdatedRecordsWithChangedField_WhenValueBecomesNull_ThenReturnRecords() {
    // Arrange
    Account oldAccount = new Account(Id = '001000000000001', Description = 'x');
    Account newAccount = new Account(Id = '001000000000001', Description = null);

    TestTriggerHandler handler = new TestTriggerHandler();
    handler.newRecords = new List<SObject>{ newAccount };
    handler.oldRecordsMap = new Map<Id, SObject>{ oldAccount.Id => oldAccount };

    // Act
    List<SObject> changedRecords = handler.getUpdatedRecordsWithChangedField(Account.Description);

    // Assert
    Assert.areEqual(1, changedRecords.size());
  }

  @isTest
  static void testGetUpdatedRecordsWithChangedField_WhenIdShapedTextChangesCase_ThenReturnRecords() {
    // Arrange: a Text value shaped like an Id is `instanceof Id`, and `!=` would ignore its case
    Account oldAccount = new Account(Id = '001000000000001', AccountNumber = '001000000000002AAA');
    Account newAccount = new Account(Id = '001000000000001', AccountNumber = '001000000000002aaa');

    TestTriggerHandler handler = new TestTriggerHandler();
    handler.newRecords = new List<SObject>{ newAccount };
    handler.oldRecordsMap = new Map<Id, SObject>{ oldAccount.Id => oldAccount };

    // Act
    List<SObject> changedRecords = handler.getUpdatedRecordsWithChangedField(Account.AccountNumber);

    // Assert
    Assert.areEqual(1, changedRecords.size());
  }
}
