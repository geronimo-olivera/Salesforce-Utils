@IsTest
private class NotificationServiceTest {

    @IsTest
    static void getCustomNotificationTypeReturnsNullForBlankOrMissing() {
        Assert.areEqual(null, NotificationService.getCustomNotificationType(null));
        Assert.areEqual(null, NotificationService.getCustomNotificationType(''));
        Assert.areEqual(null, NotificationService.getCustomNotificationType('Does_Not_Exist'));
    }

    @IsTest
    static void createAndSendNotificationDoNotThrowForNullOrRealCalls() {
        Account account = new Account(Name = 'Notification Test Account');
        insert account;

        Messaging.CustomNotification notification = NotificationService.createNotification(null, 'Title', 'Body', account.Id);

        Test.startTest();
        NotificationService.sendNotification(null, new Set<Id>{ UserInfo.getUserId() });
        NotificationService.sendNotification(notification, null);
        NotificationService.sendNotification(notification, new Set<Id>());
        NotificationService.sendNotification(notification, new Set<Id>{ UserInfo.getUserId() });
        Test.stopTest();
    }

    @IsTest
    static void recordLookupHelpersHandleNullAndReturnExpectedValues() {
        Assert.areEqual(null, NotificationService.getRecordOwnerId(null));
        Assert.areEqual(new Set<Id>(), NotificationService.getRecordFollowerIds(null));

        Account account = new Account(Name = 'Notification Owner Test Account', OwnerId = UserInfo.getUserId());
        insert account;

        Assert.areEqual(UserInfo.getUserId(), NotificationService.getRecordOwnerId(account.Id));

        insert new EntitySubscription(ParentId = account.Id, SubscriberId = UserInfo.getUserId());
        Set<Id> followerIds = NotificationService.getRecordFollowerIds(account.Id);
        Assert.isTrue(followerIds.contains(UserInfo.getUserId()));
    }

    @IsTest
    static void excludeUsersRemovesGivenIdsAndHandlesNulls() {
        Id userId = UserInfo.getUserId();
        Set<Id> withoutSelf = NotificationService.excludeUsers(new Set<Id>{ userId }, new Set<Id>{ userId });
        Assert.isTrue(withoutSelf.isEmpty());

        Assert.areEqual(new Set<Id>(), NotificationService.excludeUsers(null, new Set<Id>{ userId }));
        Assert.areEqual(new Set<Id>{ userId }, NotificationService.excludeUsers(new Set<Id>{ userId }, null));
    }

    @IsTest
    static void recipientsAreSentInGroupsThePlatformAccepts() {
        Set<Id> recipients = new Set<Id>();
        String prefix = User.SObjectType.getDescribe().getKeyPrefix();
        for (Integer i = 0; i < 1201; i++) {
            recipients.add(Id.valueOf(prefix + String.valueOf(i).leftPad(12, '0')));
        }

        List<Set<String>> chunks = NotificationService.chunkRecipients(recipients, NotificationService.MAX_RECIPIENTS_PER_SEND);

        Assert.areEqual(3, chunks.size(), '1201 recipients need three sends');
        Assert.areEqual(500, chunks[0].size(), 'full groups hold 500');
        Assert.areEqual(201, chunks[2].size(), 'the last group holds the rest');
    }

    @IsTest
    static void ownerLookupExplainsObjectsWithoutOwner() {
        Id lineItemId = Id.valueOf(OpportunityLineItem.SObjectType.getDescribe().getKeyPrefix() + '000000000000');
        try {
            NotificationService.getRecordOwnerId(lineItemId);
            Assert.fail('an object without OwnerId should be reported');
        } catch (NotificationService.NotificationServiceException ex) {
            Assert.isTrue(ex.getMessage().contains('OwnerId'), 'the message names the missing field');
        }
    }

    @IsTest
    static void standardUserCanLookUpFollowersAndOwners() {
        User standardUser = UtilsTestData.createStandardUser();
        System.runAs(standardUser) {
            Account account = new Account(Name = 'Standard User Notifications');
            insert account;
            insert new EntitySubscription(ParentId = account.Id, SubscriberId = standardUser.Id);

            Assert.isTrue(NotificationService.getRecordFollowerIds(account.Id).contains(standardUser.Id), 'a non-admin can read the followers of a record they can see');
            Assert.areEqual(standardUser.Id, NotificationService.getRecordOwnerId(account.Id), 'and its owner');
        }
    }
}
