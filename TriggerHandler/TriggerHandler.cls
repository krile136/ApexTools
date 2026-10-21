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
   * 更新 (before/after update) で使う。insert のときは比べる旧値が無いので、全件を返す。
   * delete / undelete のときは `Trigger.new` / `Trigger.oldMap` の片方が無いので使わないこと。
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
   * 更新 (before/after update) で使う。insert のときは比べる旧値が無いので、全件の Id を返す。
   * ただし before insert では Id が未採番なので、`{null}` になる。使うなら after insert で。
   * delete / undelete のときは `Trigger.new` / `Trigger.oldMap` の片方が無いので使わないこと。
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
   * 更新 (before/after update) で使う。insert のときは比べる旧値が無いので、全件を返す。
   * delete / undelete のときは `Trigger.new` / `Trigger.oldMap` の片方が無いので使わないこと。
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
        if (isChanged(record.get(field), oldRecord.get(field))) {
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
   * 更新 (before/after update) で使う。insert のときは比べる旧値が無いので、全件の Id を返す。
   * ただし before insert では Id が未採番なので、`{null}` になる。使うなら after insert で。
   * delete / undelete のときは `Trigger.new` / `Trigger.oldMap` の片方が無いので使わないこと。
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
        if (isChanged(record.get(field), oldRecord.get(field))) {
          recordIds.add(record.Id);
          break;
        }
      }
    }
    return recordIds;
  }

  /**
   * 値が変わったかを判定する。
   *
   * Apex の文字列の `==` / `!=` (と `Object.equals()`) は大文字小文字を区別しないため、
   * `'acme'` → `'ACME'` のような表記だけの更新を「変わっていない」と判定してしまう
   * (API v67.0 で実測。issue #4)。両方が String のときだけ `String.equals()` で比べる。
   *
   * Id 型の項目もここで String として比べる。Id の値も `instanceof String` が true になる (実測)。
   * 項目から読んだ Id は 18 桁に正規化されて届く (実測: 15 桁を代入しても長さ 18) ので、
   * 15 桁と 18 桁の差は出ない。`instanceof Id` で Id を先に分ける案は却下した。Id の形をした
   * 文字列 (他 org の Id を写した Text 項目など) も `instanceof Id` が true になり (実測)、
   * そこで `!=` を使うと大文字小文字だけの変更をまた見逃すため。
   *
   * DML で送られた値のうち、保存時に正規化されるものは、before update の時点で正規化済みだった (実測)。選択リストの
   * `'prospecting'` は `'Prospecting'` に、Email の大文字は小文字に、複数選択リストの
   * `'B;A'` は `'A;B'` になってから届くので、「保存すれば元と同じ表記に戻る更新」を
   * 変更と誤判定しない。リッチテキストは確かめていない。
   * ただし、同じ before update の中で Apex が代入した値 (先に動いたハンドラーが
   * `StageName = 'prospecting'` と書いた場合など) は正規化前なので、変更として判定する。
   *
   * @param newValue 更新後の値
   * @param oldValue 更新前の値
   * @return 値が変わっていれば true
   */
  private static Boolean isChanged(Object newValue, Object oldValue) {
    if (newValue instanceof String && oldValue instanceof String) {
      return !((String) newValue).equals((String) oldValue);
    }
    return newValue != oldValue;
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
