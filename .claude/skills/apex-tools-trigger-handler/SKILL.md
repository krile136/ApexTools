---
name: apex-tools-trigger-handler
description: Apex triggers and trigger handlers built on ApexTools' TriggerHandler base class. Use when writing or changing a .trigger file or a class that extends TriggerHandler in a project that contains TriggerHandler.cls, including the one-line trigger body `new XxxTriggerHandler().execute()`, overriding beforeInsert / beforeUpdate / beforeDelete / afterInsert / afterUpdate / afterDelete / afterUndelete / andFinally, acting only on records whose fields changed with getUpdatedRecordsWithChangedField / getUpdatedRecordsWithChangedFields / getUpdateRecordIdsWithChangedField / getUpdateRecordIdsWithChangedFields, a case-only change such as 'acme' to 'ACME', a Set<Id> that contains null in before insert, a NullPointerException from a change helper in a delete trigger, andFinally not running, "TriggerHandler used outside of triggers / testing", a hook that never fires, and testing a handler. Not for editing ApexTools' own source.
---

# ApexTools: TriggerHandler

`TriggerHandler` is a virtual base class. The trigger creates a handler and calls `execute()`. `execute()` reads `Trigger.operationType`, calls the matching hook, then calls `andFinally()`. Every hook is `protected virtual` and empty, so a handler overrides only the hooks it needs. The class also gives update hooks helpers that return only the records whose given fields changed.

## Rules

1. One trigger per object. Declare all seven events and write one line: `new <Object>TriggerHandler().execute();`.
2. A handler `extends TriggerHandler` and overrides hooks as `protected override void`. Don't add empty overrides.
3. Keep hooks thin: choose the records (often with a change helper), then pass them or their Ids to a class that does the work. That class can be unit-tested without DML.
4. In update hooks, use the change helpers instead of comparing `Trigger.oldMap` values by hand.
5. Don't call the change helpers in delete or undelete hooks.
6. Use the Id helpers (`getUpdateRecordIds...`) in after hooks only. In before insert the records have no Id yet.
7. Create a handler only inside a trigger or a test. The base constructor throws anywhere else.
8. `TriggerHandler` has no recursion guard and no bypass switch. If a handler updates records of its own object, make the update idempotent, or add your own guard in the handler.

## Trigger file

```apex
trigger OpportunityTrigger on Opportunity(
  before insert, before update, before delete,
  after insert, after update, after delete, after undelete
) {
  new OpportunityTriggerHandler().execute();
}
```

A hook runs only when the trigger declares its event. Declaring all seven means a hook added later works without editing the trigger.

## Hooks

| Hook | Arguments `execute()` passes |
|---|---|
| `beforeInsert(List<SObject> newRecords)` | `Trigger.new` |
| `beforeUpdate(Map<Id, SObject> newMap, Map<Id, SObject> oldMap)` | `Trigger.newMap`, `Trigger.oldMap` |
| `beforeDelete(Map<Id, SObject> deletedMap)` | `Trigger.oldMap` |
| `afterInsert(Map<Id, SObject> newMap)` | `Trigger.newMap` |
| `afterUpdate(Map<Id, SObject> newMap, Map<Id, SObject> oldMap)` | `Trigger.newMap`, `Trigger.oldMap` |
| `afterDelete(Map<Id, SObject> deletedMap)` | `Trigger.oldMap` |
| `afterUndelete(Map<Id, SObject> undeletedMap)` | `Trigger.newMap` |
| `andFinally()` | nothing |

- `beforeInsert` gets a list because new records have no Id yet.
- `andFinally()` runs after the hook of every event. It does not run when the hook throws: `execute()` has no `try` / `finally`.
- Parameter names in your override may differ from the base class. Types and order must match.

## Handler example

```apex
public with sharing class OpportunityTriggerHandler extends TriggerHandler {
  protected override void beforeUpdate(Map<Id, SObject> newMap, Map<Id, SObject> oldMap) {
    // Records returned in a before hook are Trigger.new: values you set are saved.
    for (SObject record : this.getUpdatedRecordsWithChangedField(Opportunity.StageName)) {
      Opportunity opportunity = (Opportunity) record;
      if (opportunity.StageName == 'Closed Lost') {
        opportunity.NextStep = null;
      }
    }
  }

  protected override void afterUpdate(Map<Id, SObject> newMap, Map<Id, SObject> oldMap) {
    Set<Id> changedIds = this.getUpdateRecordIdsWithChangedFields(
      new List<SObjectField>{ Opportunity.AccountId, Opportunity.StageName }
    );
    if (changedIds.isEmpty()) {
      return;
    }
    new OpportunityFollowUpService(changedIds).run();
  }

  protected override void afterInsert(Map<Id, SObject> newMap) {
    new OpportunityFollowUpService(newMap.keySet()).run();
  }
}
```

`OpportunityFollowUpService` stands for your own class that does the work.

## Change helpers

All four are `protected` methods of the base class. Call them from a hook with `this.`.

| Method | Returns |
|---|---|
| `getUpdatedRecordsWithChangedField(SObjectField field)` | `List<SObject>`: records whose field changed |
| `getUpdatedRecordsWithChangedFields(List<SObjectField> fields)` | `List<SObject>`: records where at least one of the fields changed |
| `getUpdateRecordIdsWithChangedField(SObjectField field)` | `Set<Id>` of the same records |
| `getUpdateRecordIdsWithChangedFields(List<SObjectField> fields)` | `Set<Id>` of the same records |

Note the names: the record versions say `Updated`, the Id versions say `Update`.

How they compare:

- They compare each record in `Trigger.new` with its row in `Trigger.oldMap`, field by field, and keep the record at the first changed field.
- Two strings are compared case-sensitively. `'acme'` to `'ACME'` counts as a change. Every other type is compared with `!=`.
- A value that another before-update step assigned in a different case from the stored value counts as a change, even if the platform would store the same text.
- The records are the `Trigger.new` objects themselves, not copies. In before hooks you can set fields on them. In after hooks they are read-only, as `Trigger.new` always is.

Outside update:

| Event | Result |
|---|---|
| before / after insert | No old values, so every record is returned. The Id versions return every Id, which is `{null}` in before insert. |
| before / after delete | Don't call. `Trigger.new` is `null`, and the helpers throw `NullPointerException`. |
| after undelete | Don't call. `Trigger.oldMap` is `null`, so every record is returned and nothing is compared. |

A hook shared by insert and update (for example `beforeInsert` and `beforeUpdate` both calling one method that uses a helper) works: insert gets all records, update gets the changed ones.

## Testing a handler

The trigger context comes from the platform, so test a handler through DML on its object:

```apex
@IsTest
private class OpportunityTriggerHandlerTest {
  @IsTest
  static void closingAsLostClearsNextStep() {
    Opportunity opportunity = new Opportunity(
      Name = 'Test', StageName = 'Prospecting', CloseDate = Date.today(), NextStep = 'Call'
    );
    insert opportunity;

    Test.startTest();
    opportunity.StageName = 'Closed Lost';
    update opportunity;
    Test.stopTest();

    Opportunity saved = [SELECT NextStep FROM Opportunity WHERE Id = :opportunity.Id];
    Assert.isNull(saved.NextStep, 'Normal: closing an opportunity as lost clears its next step');
  }
}
```

- Keep these tests few: one per hook behavior, plus one that saves more than 200 records in one DML, because the platform calls the trigger in chunks of 200.
- Test the logic in the classes the hooks call, with unit tests that need no DML.
- Write test descriptions and assert messages in the language the project's tests already use, and keep its case labels (`Normal:` / `Error:` / `Edge:` in English projects, `正常系:` / `異常系:` / `エッジケース:` in Japanese ones).
- `TriggerHandler` has `@TestVisible` private fields (`triggerContext`, `newRecords`, `oldRecordsMap`) that exist for ApexTools' own tests. Don't build your tests on them: `execute()` still passes `Trigger.new` / `Trigger.newMap` / `Trigger.oldMap` to the hooks, which are `null` outside a trigger.

## Common mistakes

| Symptom | Cause | Fix |
|---|---|---|
| A hook never runs | The trigger doesn't declare that event | Declare all seven events in the trigger |
| Hook body runs twice per save | Two triggers on the object, or the handler called twice | One trigger per object, one `execute()` call |
| `TriggerHandler used outside of triggers / testing` | Handler created from a batch, controller or anonymous Apex | Call the work class directly; create handlers only in triggers |
| `Set<Id>` with one `null` element | Id helper called in before insert | Use the record helper, or move the code to after insert |
| `NullPointerException` from a change helper | Called in a delete hook | Use the `deletedMap` argument directly |
| Undelete hook treats every record as changed | Change helper called in undelete | Don't filter by change in undelete |
| A case-only edit now runs the update logic | String comparison is case-sensitive | Expected. Compare with `equalsIgnoreCase` in your own code if case must be ignored |
| `andFinally()` skipped | A hook threw | Don't rely on `andFinally()` for cleanup after failures |
| Field set in an after hook: "Record is read-only" | After-hook records are read-only | Set fields in the before hook, or update a copy with DML |
| Handler updates its own object and the trigger runs again | No built-in recursion guard | Make the update idempotent, or guard with your own static flag |
| `override` doesn't compile ("@Override specified for non-overriding method") | Parameter types or order differ from the base hook, e.g. `beforeInsert(Map<Id, SObject>)` | Match the signatures in the hook table |
