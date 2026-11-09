/**
 * File Name   :	UtilsTestData.cls
 * Description :	Test-only helpers shared by the utility test classes, mainly a non-admin user to run code
 *                  as with System.runAs, so permission problems show up in tests instead of in production.
 **/
@IsTest
public class UtilsTestData {

    /** Standard profile names in the languages this repo is tested in. Profile names are translated per org language. */
    private static final Set<String> STANDARD_PROFILE_NAMES = new Set<String>{ 'Standard User', 'Usuario estándar' };

    /**
     * Inserts an active user with the Standard User profile: a Salesforce license, no "Modify All Data",
     * no "View All Data". Falls back to any profile with that shape if the name is translated differently.
     * @return the inserted user, ready for System.runAs.
     */
    public static User createStandardUser() {
        List<Profile> profiles = [
            SELECT Id, Name
            FROM Profile
            WHERE UserLicense.Name = 'Salesforce'
            AND PermissionsModifyAllData = false
            AND PermissionsViewAllData = false
            AND PermissionsCustomizeApplication = false
            ORDER BY Name
        ];
        Profile chosen;
        for (Profile candidate : profiles) {
            if (STANDARD_PROFILE_NAMES.contains(candidate.Name)) { chosen = candidate; break; }
        }
        if (chosen == null && !profiles.isEmpty()) { chosen = profiles[0]; }
        Assert.isNotNull(chosen, 'the org needs a non-admin Salesforce profile to run these tests');

        String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User user = new User(
            ProfileId = chosen.Id,
            FirstName = 'Standard',
            LastName = 'Tester',
            Alias = 'stdtst',
            Email = 'standard.tester@example.com',
            Username = 'standard.tester.' + unique + '@example.com',
            TimeZoneSidKey = 'America/Montevideo',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert user;
        return user;
    }
}
