# EmailService

A centralized entry point for outbound emails. Every part of the org that needs to send an email — templated, ad-hoc, with attachments, to a Contact/Lead/User or to raw addresses — builds and sends it through this class, so Org-Wide Email Address resolution, error handling, and governor-limit awareness stay consistent everywhere.

## Contents

- `force-app/main/default/classes/EmailService.cls` — the service itself.
- `force-app/main/default/classes/EmailServiceTest.cls` — its test class, 98% code coverage.
- `force-app/main/default/objects/Email_Service_Setting__mdt/` — custom metadata type holding the default Org-Wide Email Address.

## Custom metadata: `Email_Service_Setting__mdt`

A single record, `DeveloperName = 'Default'`, configures the org-wide default. Deploying this repo creates that record for you, with the address left blank — **you need to fill it in yourself**:

| Field | Type | Description |
|---|---|---|
| `Default_Org_Wide_Email_Address__c` | Text | The `Address` value of an existing `OrgWideEmailAddress` record. Every email created through this service falls back to this address when no explicit Org-Wide Email Address Id is provided. |

To set it up in a new org:
1. Setup → Organization-Wide Addresses → create one (and verify it — Salesforce emails a confirmation link).
2. Setup → Custom Metadata Types → Email Service Setting → Manage Records → **Default** → paste that address into `Default_Org_Wide_Email_Address__c`.

Until that's done, `EmailService` still works — emails just go out without an Org-Wide Email Address applied (using the running user's own address instead), unless you pass one explicitly.

## Basic usage

### Send a templated email

```apex
EmailTemplate template = EmailService.getEmailTemplate('Welcome_Email');
Contact contact = [SELECT Id FROM Contact WHERE Email = 'jane@example.com' LIMIT 1];

Messaging.SingleEmailMessage email = EmailService.createTemplatedEmail(
    template.Id, contact.Id, null, true, null
);

EmailService.sendEmails(new List<Messaging.SingleEmailMessage>{ email });
```

### Send an ad-hoc email (no template)

```apex
Messaging.SingleEmailMessage email = EmailService.createEmail(
    new List<String>{ 'ops-team@example.com' },
    'New high-value Opportunity',
    '<p>An Opportunity over $100k just closed.</p>',
    null,
    null
);

EmailService.sendEmails(new List<Messaging.SingleEmailMessage>{ email });
```

### Send a templated email with placeholder replacement

Useful for values a stored Email Template can't merge on its own (e.g. computed text, external data):

```apex
Messaging.SingleEmailMessage email = EmailService.createRenderedTemplatedEmail(
    template.Id,
    contact.Id,
    null,
    true,
    null,
    new Map<String, String>{ '{{DISCOUNT_CODE}}' => 'SAVE20' }
);

EmailService.sendEmails(new List<Messaging.SingleEmailMessage>{ email });
```

### Check for failures instead of throwing

```apex
List<Messaging.SendEmailResult> results = EmailService.sendEmails(emailsToSend);
for (Messaging.SendEmailResult result : results) {
    if (!result.isSuccess()) {
        System.debug('Email failed: ' + result.getErrors());
    }
}
```

### Or let EmailService throw for you

```apex
try {
    EmailService.sendEmailsOrThrow(emailsToSend, 'Failed to send renewal notices');
} catch (EmailService.EmailServiceException ex) {
    // One catch block regardless of whether it was a bad address (SendEmailResult failure)
    // or a hard System.EmailException (e.g. allOrNone = true with an invalid recipient).
    Logger.log(ex.getMessage());
}
```

## Complete examples

These two combine most of the class into something closer to real usage. They're illustrative — `Logger`, `AccountRenewalService`, and `InvoiceGenerator` aren't part of this repo; only `EmailService` is.

### Example 1 — templated notification with CC, an attachment, and limit awareness

```apex
public class AccountRenewalService {

    public static void sendRenewalNotice(Account acc, Contact primaryContact, Blob invoicePdf) {
        // remainingEmailInvocations() — bail out early instead of risking a LimitException.
        if (EmailService.remainingEmailInvocations() < 1) {
            return;
        }

        EmailTemplate template = EmailService.getEmailTemplate('Account_Renewal_Notice');
        if (template == null) {
            return;
        }

        Messaging.SingleEmailMessage email = EmailService.createRenderedTemplatedEmail(
            template.Id,
            primaryContact.Id,
            acc.Id,
            true,
            null,
            new Map<String, String>{ '{{RENEWAL_DATE}}' => acc.Renewal_Date__c.format() }
        );

        EmailService.setAdditionalRecipients(
            email,
            new List<String>{ 'account-managers@example.com' },
            null,
            'billing@example.com'
        );

        EmailService.addAttachment(email, 'Invoice.pdf', 'application/pdf', invoicePdf);

        EmailService.sendEmailsOrThrow(
            new List<Messaging.SingleEmailMessage>{ email },
            'Failed to send renewal notice for ' + acc.Name
        );
    }
}
```

### Example 2 — bulk ad-hoc emails with an existing Salesforce File and per-email error handling

```apex
public class InvoiceGenerator {

    public static void emailGeneratedInvoices(List<Account> accounts, Map<Id, Id> invoiceContentDocumentIdByAccountId) {
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Account acc : accounts) {
            Id contentDocumentId = invoiceContentDocumentIdByAccountId.get(acc.Id);
            if (contentDocumentId == null) {
                continue;
            }

            Messaging.SingleEmailMessage email = EmailService.createEmail(
                new List<String>{ acc.Billing_Contact_Email__c },
                'Your invoice is ready',
                '<p>Hi ' + acc.Name + ', your latest invoice is attached.</p>',
                null,
                null
            );

            // setFileAttachments() — the PDF already exists as a Salesforce File, no need to
            // re-fetch its Blob like addAttachment() would require.
            EmailService.setFileAttachments(email, new List<Id>{ contentDocumentId });

            emails.add(email);
        }

        // allOrNone = false — one Account with a bad billing email shouldn't stop the rest of the batch.
        List<Messaging.SendEmailResult> results = EmailService.sendEmails(emails, false);

        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                Logger.log('Failed to email invoice for ' + accounts[i].Name + ': ' + results[i].getErrors());
            }
        }
    }
}
```

Between the two examples, every method on `EmailService` is used: `getEmailTemplate`, `getOrgWideEmailAddress` (indirectly, via the default lookup), `createTemplatedEmail`, `createRenderedTemplatedEmail`, `createEmail`, `setAdditionalRecipients`, `addAttachment`, `setFileAttachments`, `sendEmails` (both overloads), `sendEmailsOrThrow`, and `remainingEmailInvocations`.

## Error handling

Every failure — a per-email rejection (`Messaging.SendEmailResult.isSuccess() == false`, e.g. an invalid address with `allOrNone = false`) or a hard failure (`System.EmailException`, e.g. `allOrNone = true` and one recipient is invalid) — surfaces as a single `EmailService.EmailServiceException` from `sendEmailsOrThrow`, so callers only need one `catch` block regardless of what went wrong.

### Placeholders in HTML bodies

`createRenderedTemplatedEmail` HTML-escapes the replacement values it puts into the HTML body, so a value that came from user input (a name, a comment) can't inject markup or links into the email. The subject and the plain-text body get the values as they are. If you really need to insert HTML, build the body yourself and use `createEmail`.

### Emails to Users

When the target (`whoId`) is a User, Salesforce doesn't allow saving the email as an activity. The service switches `saveAsActivity` off for User targets instead of letting the send fail.

### The daily limit

`remainingEmailInvocations()` only covers the per-transaction limit (10 `sendEmail` calls). Single emails to external addresses also count against a daily org limit. Before a large send, call `EmailService.hasDailyEmailCapacity(count)` to fail early instead of halfway through.

### A default address that doesn't exist

If `Email_Service_Setting__mdt.Default` points to an address that isn't an Org-Wide Email Address in the org, emails are sent from the running user instead, and the service logs a warning once per transaction.

## Permissions

- **Org-Wide Email Address:** the running user's profile must be allowed to use it. On the address in Setup, choose "Allow All Profiles to Use this From Address", or add each profile that sends. Otherwise the send fails and `sendEmailsOrThrow` throws. Jobs run as the user who started them, so for a Batch or Queueable that's the user who must be allowed.
- **Email deliverability:** Setup → Deliverability must allow "All email". Sandboxes are created with "System email only", which blocks these emails for every user, admins included.
- **Templates:** Apex can use any template no matter which folder it's in, so users don't need folder access.

## Testing

`EmailServiceTest` deploys and runs at **98% code coverage** with 10 test methods, one of them as a standard user. Its only helper is the shared `UtilsTestData`, which creates that user. Salesforce simulates `Messaging.sendEmail` automatically in test context, so no `HttpCalloutMock`-style setup is needed. The only real limitation: the "found" branch of `getOrgWideEmailAddress`/`getDefaultOrgWideEmailAddress` can't be exercised with a real `OrgWideEmailAddress`, since that object doesn't support DML inserts from Apex tests. The test templates are created inside `System.runAs`, because inserting a setup object such as `EmailTemplate` in the same transaction as an Account fails with `MIXED_DML_OPERATION`.
