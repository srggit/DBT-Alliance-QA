@IsTest
private class BulkEligibilityCheckControllerTest {

    @IsTest
    static void getSchemeGroups_requiresSelection() {
        Boolean exceptionThrown = false;
        try {
            BulkEligibilityCheckController.getSchemeGroups(new List<Id>());
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }

        System.assertEquals(true, exceptionThrown, 'Expected error when no Proposals are selected.');
    }

    @IsTest
    static void sendNotifications_requiresSelection() {
        Boolean exceptionThrown = false;
        try {
            BulkEligibilityCheckController.sendNotifications(null);
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }

        System.assertEquals(true, exceptionThrown, 'Expected error when no Proposals are selected.');
    }

    @IsTest
    static void getSchemeGroups_groupsMembersByScheme() {
        List<User> grantsManagers = [
            SELECT Id, Name
            FROM User
            WHERE UserRole.Name LIKE '%Grant%'
            AND IsActive = TRUE
            LIMIT 1
        ];

        if (grantsManagers.isEmpty()) {
            return;
        }

        Yearly_Schemes__c yearlyScheme = new Yearly_Schemes__c();
        insert yearlyScheme;

        insert new Grants_Team_Members__c(
            Name = grantsManagers[0].Name,
            Yearly_Scheme__c = yearlyScheme.Id,
            User__c = grantsManagers[0].Id
        );

        Proposal__c proposal = new Proposal__c(Yearly_Scheme__c = yearlyScheme.Id);
        insert proposal;

        Test.startTest();
        List<BulkEligibilityCheckController.SchemeGroup> groups =
            BulkEligibilityCheckController.getSchemeGroups(new List<Id>{ proposal.Id });
        Test.stopTest();

        System.assertEquals(1, groups.size(), 'Expected one scheme group.');
        System.assertEquals(yearlyScheme.Id, groups[0].schemeId);
        System.assertEquals(1, groups[0].proposalCount);
        System.assertEquals(1, groups[0].members.size(), 'Expected one Grant Team Member.');
        System.assertEquals(grantsManagers[0].Id, groups[0].members[0].userId);
        System.assertEquals(1, groups[0].proposals.size(), 'Expected one Proposal.');
        System.assertEquals(proposal.Id, groups[0].proposals[0].proposalId);
    }

    @IsTest
    static void sendNotifications_noMembersThrows() {
        Yearly_Schemes__c yearlyScheme = new Yearly_Schemes__c();
        insert yearlyScheme;

        Proposal__c proposal = new Proposal__c(Yearly_Scheme__c = yearlyScheme.Id);
        insert proposal;

        Boolean exceptionThrown = false;
        try {
            Test.startTest();
            BulkEligibilityCheckController.sendNotifications(new List<Id>{ proposal.Id });
            Test.stopTest();
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }

        System.assertEquals(true, exceptionThrown, 'Expected error when no Grant Team Members exist for the scheme.');
    }

    @IsTest
    static void sendNotifications_sendsToGrantTeamMembers() {
        List<User> grantsManagers = [
            SELECT Id, Name
            FROM User
            WHERE UserRole.Name LIKE '%Grant%'
            AND IsActive = TRUE
            LIMIT 1
        ];

        if (grantsManagers.isEmpty()) {
            return;
        }

        Yearly_Schemes__c yearlyScheme = new Yearly_Schemes__c();
        insert yearlyScheme;

        insert new Grants_Team_Members__c(
            Name = grantsManagers[0].Name,
            Yearly_Scheme__c = yearlyScheme.Id,
            User__c = grantsManagers[0].Id
        );

        Proposal__c proposal = new Proposal__c(Yearly_Scheme__c = yearlyScheme.Id);
        insert proposal;

        Test.startTest();
        BulkEligibilityCheckController.sendNotifications(new List<Id>{ proposal.Id });
        Test.stopTest();

        List<Eligibility_Check_Assignment__c> assignments = [
            SELECT Proposal__c, Grant_Team_Member__c, Yearly_Scheme__c, Status__c, OwnerId
            FROM Eligibility_Check_Assignment__c
            WHERE Proposal__c = :proposal.Id
        ];
        System.assertEquals(1, assignments.size(), 'Expected one Eligibility Check Assignment to be created.');
        System.assertEquals(grantsManagers[0].Id, assignments[0].Grant_Team_Member__c);
        System.assertEquals(yearlyScheme.Id, assignments[0].Yearly_Scheme__c);
        System.assertEquals('Pending', assignments[0].Status__c);
        System.assertEquals(grantsManagers[0].Id, assignments[0].OwnerId);
    }

    @IsTest
    static void sendNotifications_doesNotDuplicateAssignmentsOnResend() {
        List<User> grantsManagers = [
            SELECT Id, Name
            FROM User
            WHERE UserRole.Name LIKE '%Grant%'
            AND IsActive = TRUE
            LIMIT 1
        ];

        if (grantsManagers.isEmpty()) {
            return;
        }

        Yearly_Schemes__c yearlyScheme = new Yearly_Schemes__c();
        insert yearlyScheme;

        insert new Grants_Team_Members__c(
            Name = grantsManagers[0].Name,
            Yearly_Scheme__c = yearlyScheme.Id,
            User__c = grantsManagers[0].Id
        );

        Proposal__c proposal = new Proposal__c(Yearly_Scheme__c = yearlyScheme.Id);
        insert proposal;

        Test.startTest();
        BulkEligibilityCheckController.sendNotifications(new List<Id>{ proposal.Id });
        BulkEligibilityCheckController.sendNotifications(new List<Id>{ proposal.Id });
        Test.stopTest();

        List<Eligibility_Check_Assignment__c> assignments = [
            SELECT Id
            FROM Eligibility_Check_Assignment__c
            WHERE Proposal__c = :proposal.Id
            AND Grant_Team_Member__c = :grantsManagers[0].Id
        ];
        System.assertEquals(
            1,
            assignments.size(),
            'Expected only one Eligibility Check Assignment for the same Proposal/member pair after resending.'
        );
    }
}