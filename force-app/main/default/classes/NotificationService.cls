public inherited sharing class NotificationService {

    /** Messaging.CustomNotification.send accepts at most 500 recipients per call. */
    @TestVisible
    private static final Integer MAX_RECIPIENTS_PER_SEND = 500;

    /** Salesforce requires a LIMIT of at most 1000 when a non-admin user queries EntitySubscription. */
    private static final Integer MAX_FOLLOWERS = 1000;

    /**
     * Returns a Custom Notification Type by Developer Name.
     * @param developerName The DeveloperName of the CustomNotificationType.
     * @return The matching CustomNotificationType, or null if not found or developerName is blank.
     */
    public static CustomNotificationType getCustomNotificationType(String developerName) {
        if (String.isBlank(developerName)) { return null; }
        List<CustomNotificationType> types = [
            SELECT Id, DeveloperName, MasterLabel
            FROM CustomNotificationType
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];
        return types.isEmpty() ? null : types[0];
    }

    /**
     * Builds a custom notification. Call sendNotification to actually deliver it.
     * @param notificationTypeId The Id of the CustomNotificationType to send under (see getCustomNotificationType).
     * @param title The notification title.
     * @param body The notification body.
     * @param targetId Optional record Id. When provided, clicking the notification navigates there.
     * @return A configured Messaging.CustomNotification, not yet sent.
     */
    public static Messaging.CustomNotification createNotification(Id notificationTypeId, String title, String body, Id targetId) {
        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setNotificationTypeId(notificationTypeId);
        notification.setTitle(title);
        notification.setBody(body);
        if (targetId != null) { notification.setTargetId(targetId); }
        return notification;
    }

    /**
     * Sends a custom notification (the bell icon) to the given recipients. Salesforce accepts at most 500
     * recipients per send, so larger sets are sent in groups of 500.
     * @param notification The notification to send, built via createNotification.
     * @param recipientIds User Ids to notify. No-op if null or empty.
     */
    public static void sendNotification(Messaging.CustomNotification notification, Set<Id> recipientIds) {
        if (notification == null || recipientIds == null || recipientIds.isEmpty()) { return; }
        try {
            for (Set<String> chunk : chunkRecipients(recipientIds, MAX_RECIPIENTS_PER_SEND)) {
                notification.send(chunk);
            }
        } catch (Exception ex) {
            NotificationServiceException wrapped = new NotificationServiceException('Failed to send notification to ' + recipientIds.size() + ' recipient(s): ' + ex.getMessage());
            wrapped.initCause(ex);
            throw wrapped;
        }
    }

    /**
     * Returns the Ids of the Users following the given record, for "notify everyone following this record" scenarios.
     * Returns at most 1000 followers: Salesforce requires that LIMIT when a non-admin user runs this query.
     * @param recordId The record whose followers to look up.
     * @return A set of User Ids following recordId. Empty if recordId is null or nobody follows it.
     */
    public static Set<Id> getRecordFollowerIds(Id recordId) {
        Set<Id> followerIds = new Set<Id>();
        if (recordId == null) { return followerIds; }
        for (EntitySubscription subscription : [
            SELECT SubscriberId
            FROM EntitySubscription
            WHERE ParentId = :recordId
            LIMIT :MAX_FOLLOWERS
        ]) {
            followerIds.add(subscription.SubscriberId);
        }
        return followerIds;
    }

    /**
     * Returns the owner Id of the given record, for "notify the record owner" scenarios.
     * Works against any SObject type that has an OwnerId field.
     * @param recordId The record to look up the owner of.
     * @return The record's OwnerId, or null if recordId is null.
     * @throws NotificationServiceException if the record's object has no OwnerId, e.g. the detail side of a master-detail.
     */
    public static Id getRecordOwnerId(Id recordId) {
        if (recordId == null) { return null; }
        Schema.DescribeSObjectResult describe = recordId.getSObjectType().getDescribe();
        String objectApiName = describe.getName();
        if (!describe.fields.getMap().containsKey('ownerid')) {
            throw new NotificationServiceException(objectApiName + ' has no OwnerId field, so its records have no owner to notify.');
        }
        List<SObject> records = Database.query(
            'SELECT OwnerId FROM ' + String.escapeSingleQuotes(objectApiName) + ' WHERE Id = :recordId LIMIT 1'
        );
        return records.isEmpty() ? null : (Id) records[0].get('OwnerId');
    }

    /**
     * Removes specific Ids from a recipient set — most commonly used to avoid notifying the user
     * who triggered the action about their own action.
     * @param userIds The recipient Ids to filter. Can be null.
     * @param idsToExclude The Ids to remove. Can be null.
     * @return A new set containing userIds minus idsToExclude.
     */
    public static Set<Id> excludeUsers(Set<Id> userIds, Set<Id> idsToExclude) {
        Set<Id> result = userIds != null ? new Set<Id>(userIds) : new Set<Id>();
        if (idsToExclude != null) { result.removeAll(idsToExclude); }
        return result;
    }

    /**
     * Splits recipient Ids into groups the platform accepts in one send.
     * @param recipientIds The Ids to split.
     * @param size The maximum group size.
     * @return the Ids as strings, in groups of at most size.
     */
    @TestVisible
    private static List<Set<String>> chunkRecipients(Set<Id> recipientIds, Integer size) {
        List<Set<String>> chunks = new List<Set<String>>();
        Set<String> current = new Set<String>();
        for (Id recipientId : recipientIds) {
            current.add(recipientId);
            if (current.size() == size) {
                chunks.add(current);
                current = new Set<String>();
            }
        }
        if (!current.isEmpty()) { chunks.add(current); }
        return chunks;
    }

    /**
     * Exception thrown when sending a custom notification fails.
     */
    public class NotificationServiceException extends Exception {}
}
