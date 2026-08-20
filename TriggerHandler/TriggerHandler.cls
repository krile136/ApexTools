/**
 * @directory ApexTools/TriggerHandler
 */
public virtual class TriggerHandler {
  @TestVisible
  private TriggerOperation triggerContext;
  @TestVisible
  private List<SObject> newRecords;
  @TestVisible
  private Map<Id, SObject> oldRecordsMap;

  protected TriggerHandler() {
    if (!Trigger.isExecuting && !Test.isRunningTest()) {
      throw new TriggerHandlerException('TriggerHandler used outside of triggers / testing');
    }
  }

  /**
   * トリガーコンテキストに応じたメソッドを呼び出します。
   */
  public void execute() {
    TriggerOperation context = this.triggerContext ?? Trigger.operationType;
    switch on context {
      when BEFORE_INSERT {
        this.beforeInsert(Trigger.new);
      }
      when BEFORE_UPDATE {
        this.beforeUpdate(Trigger.newMap, Trigger.oldMap);
      }
      when BEFORE_DELETE {
        this.beforeDelete(Trigger.oldMap);
      }
      when AFTER_INSERT {
        this.afterInsert(Trigger.newMap);
      }
      when AFTER_UPDATE {
        this.afterUpdate(Trigger.newMap, Trigger.oldMap);
      }
      when AFTER_DELETE {
        this.afterDelete(Trigger.oldMap);
      }
      when AFTER_UNDELETE {
        this.afterUndelete(Trigger.newMap);
      }
    }
    this.andFinally();
  }

  /**
   * 指定したフィールド(単一)が変更された更新レコードを取得します。
   *
   * @param field 変更を検出するフィールド
   * @return 指定したフィールドが変更された更新レコードのリスト
   */
  @TestVisible
  protected List<SObject> getUpdatedRecordsWithChangedField(SObjectField field) {
    return this.getUpdatedRecordsWithChangedFields(new List<SObjectField>{ field });
  }

  /**
   * 指定したフィールド(単一)が変更された更新レコードのIDを取得します。
   *
   * @param field 変更を検出するフィールド
   * @return 指定したフィールドが変更された更新レコードのIDのセット
   */
  @TestVisible
  protected Set<Id> getUpdateRecordIdsWithChangedField(SObjectField field) {
    return this.getUpdateRecordIdsWithChangedFields(new List<SObjectField>{ field });
  }

  /**
   * 指定したフィールド群のいずれかが変更された更新レコードを取得します。
   *
   * @param fields 変更を検出するフィールド群
   * @return 指定したフィールド群のいずれかが変更された更新レコードのリスト
   */
  @TestVisible
  protected List<SObject> getUpdatedRecordsWithChangedFields(List<SObjectField> fields) {
    List<SObject> updatedRecords = new List<SObject>();
    List<SObject> newRecords = this.newRecords ?? Trigger.new;
    Map<Id, SObject> oldRecordsMap = this.oldRecordsMap ?? Trigger.oldMap;

    if (oldRecordsMap == null || oldRecordsMap.isEmpty()) {
      return newRecords;
    }

    for (SObject record : newRecords) {
      SObject oldRecord = oldRecordsMap.get(record.Id);
      for (SObjectField field : fields) {
        if (record.get(field) != oldRecord.get(field)) {
          updatedRecords.add(record);
          break;
        }
      }
    }
    return updatedRecords;
  }

  /**
   * 指定したフィールド群のいずれかが変更された更新レコードのIDを取得します。
   *
   * @param fields 変更を検出するフィールド群
   * @return 指定したフィールド群のいずれかが変更された更新レコードのIDのセット
   */
  @TestVisible
  protected Set<Id> getUpdateRecordIdsWithChangedFields(List<SObjectField> fields) {
    Set<Id> recordIds = new Set<Id>();
    List<SObject> newRecords = this.newRecords ?? Trigger.new;
    Map<Id, SObject> oldRecordsMap = this.oldRecordsMap ?? Trigger.oldMap;

    if (oldRecordsMap == null || oldRecordsMap.isEmpty()) {
      for (SObject record : newRecords) {
        recordIds.add(record.Id);
      }
      return recordIds;
    }

    for (SObject record : newRecords) {
      SObject oldRecord = oldRecordsMap.get(record.Id);
      for (SObjectField field : fields) {
        if (record.get(field) != oldRecord.get(field)) {
          recordIds.add(record.Id);
          break;
        }
      }
    }
    return recordIds;
  }

  protected virtual void beforeInsert(List<SObject> newRecords) {
  }
  protected virtual void beforeUpdate(Map<Id, SObject> updatedRecordsMap, Map<Id, SObject> oldRecordsMap) {
  }
  protected virtual void beforeDelete(Map<Id, SObject> deletedRecordsMap) {
  }
  protected virtual void afterInsert(Map<Id, SObject> newRecordsMap) {
  }
  protected virtual void afterUpdate(Map<Id, SObject> updatedRecordsMap, Map<Id, SObject> oldRecordsMap) {
  }
  protected virtual void afterDelete(Map<Id, SObject> deletedRecordsMap) {
  }
  protected virtual void afterUndelete(Map<Id, SObject> undeletedRecordsMap) {
  }

  /**
   * トリガー処理の最後に必ず実行されるメソッド
   */
  protected virtual void andFinally() {
  }

  private class TriggerHandlerException extends Exception {
  }
}
