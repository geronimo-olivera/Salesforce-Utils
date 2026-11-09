# Salesforce Utils

Reusable Apex services for the work that repeats in every Salesforce project: HTTP callouts, emails, custom notifications, Salesforce Files and collection handling. Each one is a single entry point, so defaults, limits and errors are handled the same way everywhere. Every utility has its own doc under [`docs/`](docs/).

## Utilities

- **HttpCalloutService** — centralized service for outbound HTTP callouts (GET/POST/PUT/PATCH/DELETE, JSON helpers, consistent error handling). See [`docs/HttpCalloutService.md`](docs/HttpCalloutService.md) for usage examples.
- **EmailService** — centralized service for outbound emails (templated, ad-hoc, attachments, CC/BCC/reply-to, consistent error handling). See [`docs/EmailService.md`](docs/EmailService.md) for usage examples and how to configure its `Email_Service_Setting__mdt` default.
- **NotificationService** — centralized service for custom notifications (the bell icon), with helpers to notify a record's followers, its owner, or explicit users, and consistent error handling. See [`docs/NotificationService.md`](docs/NotificationService.md) for usage examples and how to set up a Custom Notification Type.
- **FileService** — centralized service for Salesforce Files (ContentVersion / ContentDocument / ContentDocumentLink): create files and new versions, link and unlink them to records with every ShareType and Visibility option, update links, list a record's files, download (Blob, Base64, or URL), public links, and consistent error handling. See [`docs/FileService.md`](docs/FileService.md) for usage examples and the ShareType/Visibility rules.
- **CollectionUtils** — static helpers for the collection work that repeats in every trigger and service: extract Ids and values, group, index, filter, detect field changes (including "changed to"), sum/min/max and rollups per parent, and split a list into chunks. Fields are passed as tokens (`Opportunity.AccountId`), so a typo doesn't compile. See [`docs/CollectionUtils.md`](docs/CollectionUtils.md) for the full reference and examples.

## Related frameworks

These used to live here too. Each one is now its own project, with its own docs, tests and one-click deploy:

- [Trigger Handler Framework](https://github.com/geronimo-olivera/Trigger-Handler-Framework) — metadata-driven trigger dispatch with a recursion guard.
- [Field Transition Framework](https://github.com/geronimo-olivera/Field-Transition-Framework) — blocks a field change until configurable conditions are met, with a Lightning checklist.
- [Async Apex Framework](https://github.com/geronimo-olivera/Async-Apex-Framework) — retries, failure emails and on/off switches for Batch and Queueable Apex.

## Deploy to an org

You need [VS Code with the Salesforce Extension Pack](https://developer.salesforce.com/tools/vscode/) and an authenticated org.

1. Clone this repo and open it in VS Code.
2. Authenticate to your target org (`SFDX: Authorize an Org`, or `sf org login web` from the CLI).
3. Right-click [`manifest/package.xml`](manifest/package.xml) and choose **SFDX: Deploy Source in Manifest to Org**.

[`manifest/package.xml`](manifest/package.xml) lists every utility's components together.

## License

Released under the [MIT License](LICENSE).
