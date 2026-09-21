import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getProposalDetails from '@salesforce/apex/ProposalApplicantDetailsController.getProposalDetails';

const SIDEBAR_SECTIONS = [
    { key: 'proposal', label: 'Proposal', kind: 'overview' },
    { key: 'projectSummary', number: 1, label: 'Project Summary', kind: 'projectSummary' },
    { key: 'researchEnvironment', number: 2, label: 'Research Environment', kind: 'researchEnvironment' },
    { key: 'applicantCV', number: 3, label: 'Applicant CV', kind: 'applicantCV' },
    { key: 'otherGrants', number: 4, label: 'Other Grants and Applications', kind: 'otherGrants' },
    { key: 'lettersDeclaration', number: 5, label: 'Additional Section for Letters and Declaration', kind: 'lettersDeclaration' }
];

export default class ProposalApplicationForm extends LightningElement {
    _recordId;
    isLoading = false;
    error;
    data;
    activeSectionKey = 'proposal';

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this.loadData();
    }

    @wire(CurrentPageReference)
    wiredPageReference(pageReference) {
        const urlId = pageReference?.state?.c__recordId || pageReference?.state?.recordId;
        if (urlId && !this._recordId) {
            this._recordId = urlId;
            this.loadData();
        }
    }

    async loadData() {
        if (!this._recordId) {
            return;
        }
        this.isLoading = true;
        this.error = undefined;
        try {
            this.data = await getProposalDetails({ proposalId: this._recordId });
        } catch (e) {
            this.error = e?.body?.message || e?.message || 'Unable to load proposal.';
        } finally {
            this.isLoading = false;
        }
    }

    get hasData() {
        return !!this.data;
    }

    get showNoData() {
        return !this.isLoading && !this.error && !this.hasData;
    }

    /* ============================================================
       SIDEBAR
       ============================================================ */

    get sidebarItems() {
        return SIDEBAR_SECTIONS.map((section) => {
            const isActive = section.key === this.activeSectionKey;
            return {
                ...section,
                isActive,
                isOverview: section.kind === 'overview',
                itemClass: 'papf-nav-item' + (isActive ? ' papf-nav-item_active' : '')
            };
        });
    }

    handleSelectSection(event) {
        this.activeSectionKey = event.currentTarget.dataset.key;
    }

    get activeSection() {
        return SIDEBAR_SECTIONS.find((section) => section.key === this.activeSectionKey);
    }

    get isOverviewActive() {
        return this.activeSection?.kind === 'overview';
    }

    get isProjectSummaryActive() {
        return this.activeSection?.kind === 'projectSummary';
    }


    get isResearchEnvironmentActive() {
        return this.activeSection?.kind === 'researchEnvironment';
    }

    get schemeItemName() {
        return this.data?.schemeItemName || '';
    }

    get isIntermediateScheme() {
        return this.schemeItemName.includes('[CPHI]') || this.schemeItemName.includes('[IF]');
    }

    get isOtherGrantsActive() {
        return this.activeSection?.kind === 'otherGrants';
    }

    get isApplicantCVActive() {
        return this.activeSection?.kind === 'applicantCV';
    }

    get isLettersDeclarationActive() {
        return this.activeSection?.kind === 'lettersDeclaration';
    }

    get activePlaceholderLabel() {
        return this.activeSection?.kind === 'placeholder' ? this.activeSection.label : null;
    }

    /* ============================================================
       FIELD LOOKUP HELPERS
       ============================================================ */

    findApiNameByLabel(fieldLabels, labelFragment) {
        if (!fieldLabels) {
            return null;
        }
        const target = labelFragment.toLowerCase();
        const exact = Object.keys(fieldLabels).find((api) => (fieldLabels[api] || '').toLowerCase() === target);
        if (exact) {
            return exact;
        }
        return Object.keys(fieldLabels).find((api) => (fieldLabels[api] || '').toLowerCase().includes(target));
    }

    getProposalValue(labelFragment) {
        const fieldLabels = this.data?.fieldLabels?.Proposal__c;
        const apiName = this.findApiNameByLabel(fieldLabels, labelFragment);
        if (!apiName) {
            return '';
        }
        const value = this.data?.proposal?.[apiName];
        return value === null || value === undefined ? '' : String(value);
    }

    /* ============================================================
       PROJECT SUMMARY FIELDS
       ============================================================ */

    get projectTitle() {
        return this.getProposalValue('Project Title');
    }

    get outlineOfResearch() {
        return this.getProposalValue('Outline of proposed research');
    }

    get keywords() {
        return this.getProposalValue('Keywords');
    }

    get significance() {
        return this.getProposalValue('Significance of the proposed work');
    }

    get researchReferences() {
        return this.getProposalValue('Research references');
    }

    /* ============================================================
       RESEARCH ENVIRONMENT FIELDS
       ============================================================ */

    get apaRecord() {
        return (this.data?.applicants || [])[0] || {};
    }

    get proposalRecord() {
        return this.data?.proposal || {};
    }

    get supervisorSuitability() {
        return (
            this.proposalRecord?.Why_FH_Host_is_Suitable_Choice__c ||
            this.apaRecord?.Why_Host_Laboratory_is_suitable_for_work__c ||
            ''
        );
    }

    get hostInfrastructure() {
        return (
            this.proposalRecord?.Host_Institution_Infrastructure__c ||
            this.apaRecord?.Infrastructure_Facilities_of_Host_Inst__c ||
            ''
        );
    }

    get alternativeArrangements() {
        return (
            this.proposalRecord?.Alternative_Facility_Arrangements__c ||
            this.apaRecord?.Alternative_arrangements_for_facility__c ||
            ''
        );
    }

    get previousCollaboration() {
        return (
            this.proposalRecord?.Previous_Collaboration__c ||
            this.apaRecord?.Collab_with_Supervisor_or_in_Host_Env__c ||
            ''
        );
    }

    get wohiPlan() {
        return (
            this.proposalRecord?.Describe_WOHI_Plan_and_Sponsor_s__c ||
            this.apaRecord?.If_identified_External_Sponsor_s_for_Wo__c ||
            ''
        );
    }

    get hostInstitutionStatus() {
        return this.proposalRecord?.Status_at_the_Host_Institution__c || this.apaRecord?.Status_at_the_Host_Institution__c || '';
    }

    get hasFacultyPosition() {
        return this.hostInstitutionStatus.toLowerCase().includes('already');
    }

    get doesNotHaveFacultyPosition() {
        return !!this.hostInstitutionStatus && !this.hasFacultyPosition;
    }

    get facultyOptionClass() {
        return 'papf-radio-option' + (this.hasFacultyPosition ? ' papf-radio-option_selected' : '');
    }

    get nonFacultyOptionClass() {
        return 'papf-radio-option' + (this.doesNotHaveFacultyPosition ? ' papf-radio-option_selected' : '');
    }

    get appointmentDateDisplay() {
        return (
            this.proposalRecord?.Start_Date_of_Host_Appointment__c ||
            this.apaRecord?.Appointment_Date_at_Host_Institution__c ||
            ''
        );
    }

    get currentPositionAtHost() {
        return (
            this.proposalRecord?.Current_Position_At_Host_Institution__c ||
            this.apaRecord?.Current_position_at_the_Host_Institution__c ||
            ''
        );
    }

    /* ============================================================
       OTHER GRANTS AND APPLICATIONS
       ============================================================ */

    get researchGrants() {
        const records = this.data?.existingGrants || [];

        return records.map((record, index) => ({
            key: record.Id || String(index),
            startDate: record.Start_Date__c || '-',
            durationMonths: record.Duration_In_Months__c || '-',
            currency: record.Currency__c || '-',
            totalAwardAmount: record.Total_Award_Amount__c || '-',
            fundingAgency: record.Funding_Agency__c || '-',
            type: record.Type__c || '-',
            title: record.Title__c || '-',
            roleOfApplicant: record.Role_of_Applicant__c || '-'
        }));
    }

    get hasResearchGrants() {
        return this.researchGrants.length > 0;
    }

    normalizeBoolean(value) {
        if (value === true) {
            return true;
        }
        if (value === false) {
            return false;
        }
        if (typeof value === 'string') {
            const normalized = value.trim().toLowerCase();
            return normalized === 'yes' || normalized === 'true';
        }
        return false;
    }

    hasRawValue(value) {
        return value !== null && value !== undefined && value !== '';
    }

    get firstApplicationRaw() {
        return this.apaRecord?.Is_this_your_first_Application__c;
    }

    get isFirstApplicationYes() {
        return this.normalizeBoolean(this.firstApplicationRaw);
    }

    get firstApplicationYesClass() {
        return 'papf-radio-option' + (this.isFirstApplicationYes ? ' papf-radio-option_selected' : '');
    }

    get firstApplicationNoClass() {
        return 'papf-radio-option' + (this.hasRawValue(this.firstApplicationRaw) && !this.isFirstApplicationYes ? ' papf-radio-option_selected' : '');
    }

    get showPreviousApplicationFields() {
        return this.hasRawValue(this.firstApplicationRaw) && !this.isFirstApplicationYes;
    }

    get otherGrantsRecords() {
        return this.data?.otherGrants || [];
    }

    get previousApplications() {
        return this.otherGrantsRecords
            .filter((record) => (record.Grants_Type__c || '').toLowerCase() === 'previous dbt grants')
            .map((record, index) => ({
                key: record.Id || String(index),
                number: index + 1,
                referenceNumber: record.Previous_Application_Reference_Number__c || '',
                scheme: record.Previous_Scheme__c || '',
                projectTitle: record.Previous_Application_Project_Title__c || '',
                decision: record.Decision_on_previous_application__c || '',
                keyDifference: record.Key_difference_from_previous_application__c || ''
            }));
    }

    get hasPreviousApplications() {
        return this.previousApplications.length > 0;
    }

    get ongoingApplications() {
        return this.otherGrantsRecords
            .filter((record) => (record.Grants_Type__c || '').toLowerCase() === 'other grants')
            .map((record, index) => {
                const type = (record.Type_of_funding__c || '').toLowerCase();
                const role = (record.Your_Role_on_the_Application__c || '').toLowerCase().replace(/[^a-z]/g, '');
                return {
                    key: record.Id || String(index),
                    number: index + 1,
                    fundingAgencyAndScheme: record.Name_of_Ongoing_funding_agency_Scheme__c || '',
                    projectTitle: record.Ongoing_Project_Title__c || '',
                    abstract: record.Abstract_Ongoing__c || '',
                    overlap: record.Overlap_with_current_IA_application__c || '',
                    expectedDate: record.Expected_date_of_decision__c || '',
                    fellowshipClass: 'papf-radio-option' + (type === 'fellowship' ? ' papf-radio-option_selected' : ''),
                    grantClass: 'papf-radio-option' + (type === 'grant' ? ' papf-radio-option_selected' : ''),
                    piClass: 'papf-radio-option' + (role === 'pi' ? ' papf-radio-option_selected' : ''),
                    coPiClass: 'papf-radio-option' + (role === 'copi' ? ' papf-radio-option_selected' : '')
                };
            });
    }

    get hasOngoingApplications() {
        return this.ongoingApplications.length > 0;
    }

    get otherOngoingApplicationsRaw() {
        return this.apaRecord?.Other_Ongoing_Applications__c;
    }

    get isOtherOngoingApplicationsYes() {
        return this.normalizeBoolean(this.otherOngoingApplicationsRaw);
    }

    get otherOngoingYesClass() {
        return 'papf-radio-option' + (this.isOtherOngoingApplicationsYes ? ' papf-radio-option_selected' : '');
    }

    get otherOngoingNoClass() {
        return 'papf-radio-option' + (this.hasRawValue(this.otherOngoingApplicationsRaw) && !this.isOtherOngoingApplicationsYes ? ' papf-radio-option_selected' : '');
    }

    get showOngoingApplicationFields() {
        return this.isOtherOngoingApplicationsYes;
    }

    /* ============================================================
       APPLICANT CV
       ============================================================ */

    get contactRecord() {
        return (this.data?.contacts || [])[0] || {};
    }

    getApaValue(labelFragment) {
        const fieldLabels = this.data?.fieldLabels?.Applicant_Proposal_Association__c;
        const apiName = this.findApiNameByLabel(fieldLabels, labelFragment);
        if (!apiName) {
            return '';
        }
        const value = this.apaRecord?.[apiName];
        return value === null || value === undefined ? '' : String(value);
    }

    getContactValue(labelFragment) {
        const fieldLabels = this.data?.fieldLabels?.Contact;
        const apiName = this.findApiNameByLabel(fieldLabels, labelFragment);
        if (!apiName) {
            return '';
        }
        const value = this.contactRecord?.[apiName];
        return value === null || value === undefined ? '' : String(value);
    }

    getApaRawValue(labelFragment) {
        const fieldLabels = this.data?.fieldLabels?.Applicant_Proposal_Association__c;
        const apiName = this.findApiNameByLabel(fieldLabels, labelFragment);
        return apiName ? this.apaRecord?.[apiName] : undefined;
    }

    get hostAssociationRecord() {
        return (this.data?.hostAssociations || [])[0] || {};
    }

    getHostValue(labelFragment) {
        const fieldLabels = this.data?.fieldLabels?.Applicant_Host_Association__c;
        const apiName = this.findApiNameByLabel(fieldLabels, labelFragment);
        if (!apiName) {
            return '';
        }
        const value = this.hostAssociationRecord?.[apiName];
        return value === null || value === undefined ? '' : String(value);
    }

    getHostRawValue(labelFragment) {
        const fieldLabels = this.data?.fieldLabels?.Applicant_Host_Association__c;
        const apiName = this.findApiNameByLabel(fieldLabels, labelFragment);
        return apiName ? this.hostAssociationRecord?.[apiName] : undefined;
    }

    get hostAccountRecord() {
        return this.data?.hostAccount || {};
    }

    getHostAccountValue(labelFragment) {
        const fieldLabels = this.data?.fieldLabels?.Account;
        const apiName = this.findApiNameByLabel(fieldLabels, labelFragment);
        if (!apiName) {
            return '';
        }
        const value = this.hostAccountRecord?.[apiName];
        return value === null || value === undefined ? '' : String(value);
    }

    getProposalRawValue(labelFragment) {
        const fieldLabels = this.data?.fieldLabels?.Proposal__c;
        const apiName = this.findApiNameByLabel(fieldLabels, labelFragment);
        return apiName ? this.data?.proposal?.[apiName] : undefined;
    }

    get hostInstitutionName() {
        return (
            this.getHostAccountValue('Account Name') ||
            this.getHostAccountValue('Name') ||
            this.getHostValue('Host Institution Name')
        );
    }

    get hostCityTown() {
        return (
            this.getHostAccountValue('City/Town') ||
            this.getHostAccountValue('Billing City') ||
            this.getHostAccountValue('City')
        );
    }

    get hostDistrict() {
        return this.getHostAccountValue('District');
    }

    get hostState() {
        return this.getHostAccountValue('State') || this.getHostAccountValue('Billing State');
    }

    get hostCountry() {
        return this.getHostAccountValue('Country') || this.getHostAccountValue('Billing Country');
    }

    get hostPostcode() {
        return (
            this.getHostAccountValue('Postcode') ||
            this.getHostAccountValue('Postal Code') ||
            this.getHostAccountValue('Billing Zip')
        );
    }

    get hostTelephone() {
        return this.getHostAccountValue('Telephone') || this.getHostAccountValue('Phone');
    }

    get hostEmail() {
        return this.getHostAccountValue('Email Address') || this.getHostAccountValue('Email');
    }

    get hostNotForProfitChecked() {
        return this.normalizeBoolean(
            this.getHostRawValue('not-for-profit') || this.getHostRawValue('not for profit')
        );
    }

    get hostNotForProfitBoxClass() {
        return 'papf-checkbox-box' + (this.hostNotForProfitChecked ? ' papf-checkbox-box_checked' : '');
    }

    get isBasicBiomedicalResearchChecked() {
        return this.normalizeBoolean(this.getProposalRawValue('Basic Biomedical Research'));
    }

    get basicBiomedicalResearchBoxClass() {
        return 'papf-checkbox-box' + (this.isBasicBiomedicalResearchChecked ? ' papf-checkbox-box_checked' : '');
    }

    get postsHeld() {
        const records = this.data?.employmentDetails || [];

        return records.map((record, index) => ({
            key: record.Id || String(index),
            from: record.Start_Date__c || '-',
            to: record.End_Date__c || 'Present',
            position: record.Position__c || '-',
            organisation: record.Organisation__c || '-',
            reportingTo: record.Reporting_To__c || '-',
            isCurrentlyWorking: this.normalizeBoolean(record.I_am_currently_working_here__c)
        }));
    }

    get hasPostsHeld() {
        return this.postsHeld.length > 0;
    }

    get educationEntries() {
        const records = this.data?.educationDetails || [];

        return records.map((record, index) => {
            const isHigherDegree = this.normalizeBoolean(record.Pursuing_Higher_Degree__c);
            return {
                key: record.Id || String(index),
                number: index + 1,
                from: record.Start_Date__c || '-',
                to: record.End_Date__c || '-',
                qualification: record.Qualification__c || '-',
                subject: record.Subject__c || '-',
                country: record.Country__c || '-',
                institution: record.Institution__c || '-',
                department: record.Department_School_Division__c || '-',
                isHigherDegree,
                higherDegreeBoxClass: 'papf-checkbox-box' + (isHigherDegree ? ' papf-checkbox-box_checked' : '')
            };
        });
    }

    get hasEducationEntries() {
        return this.educationEntries.length > 0;
    }

    get higherDegreeThesisTitle() {
        return this.getProposalValue('Title of Thesis/Dissertation');
    }

    get higherDegreeResearchSummary() {
        return this.getProposalValue('Research Summary');
    }

    get orcidId() {
        return this.getContactValue('ORCID');
    }

    get googleScholarLink() {
        return this.getContactValue('Google Scholar');
    }

    get patentEntries() {
        const records = this.data?.patents || [];
        const fieldLabels = this.data?.fieldLabels?.Patents__c;
        const titleApi = this.findApiNameByLabel(fieldLabels, 'Title');
        const inventorsApi = this.findApiNameByLabel(fieldLabels, 'Inventors');
        const grantingAgencyApi = this.findApiNameByLabel(fieldLabels, 'Granting Agency');
        const patentNumberApi = this.findApiNameByLabel(fieldLabels, 'Patent Number');
        const filingDateApi =
            this.findApiNameByLabel(fieldLabels, 'Filing') || this.findApiNameByLabel(fieldLabels, 'Granted Date');
        const statusApi =
            this.findApiNameByLabel(fieldLabels, 'Status of the Application') ||
            this.findApiNameByLabel(fieldLabels, 'Status');

        return records.map((record, index) => ({
            key: record.Id || String(index),
            number: 'g' + (index + 1),
            title: record[titleApi] || '-',
            inventors: record[inventorsApi] || '-',
            grantingAgency: record[grantingAgencyApi] || '-',
            patentNumber: record[patentNumberApi] || '-',
            filingDate: record[filingDateApi] || '-',
            status: record[statusApi] || '-'
        }));
    }

    get hasPatentEntries() {
        return this.patentEntries.length > 0;
    }

    get scientificMeetings() {
        return this.getProposalValue('Scientific meetings');
    }

    get scientificCareerToDate() {
        return this.getProposalValue('Scientific career to date');
    }

    /* ============================================================
       LETTERS AND DECLARATION
       ============================================================ */

    get participants() {
        const records = this.data?.participants || [];
        const contactFieldLabels = this.data?.fieldLabels?.Contact;
        const firstNameApi = this.findApiNameByLabel(contactFieldLabels, 'First Name');
        const lastNameApi = this.findApiNameByLabel(contactFieldLabels, 'Last Name');
        const nationalityApi = this.findApiNameByLabel(contactFieldLabels, 'Nationality');
        const genderApi = this.findApiNameByLabel(contactFieldLabels, 'Gender');
        const telephoneApi =
            this.findApiNameByLabel(contactFieldLabels, 'Phone') ||
            this.findApiNameByLabel(contactFieldLabels, 'Telephone');
        const emailApi = this.findApiNameByLabel(contactFieldLabels, 'Email');

        return records.map((record, index) => {
            const contactData = record.contactData || {};
            return {
                key: record.Id || String(index),
                number: index + 1,
                role: record.Roles__c || '-',
                title: contactData.Title__c || contactData.Title || '-',
                firstName: contactData[firstNameApi] || '-',
                lastName: contactData[lastNameApi] || '-',
                nationality: contactData[nationalityApi] || '-',
                gender: contactData[genderApi] || '-',
                telephone: contactData[telephoneApi] || '-',
                email: contactData[emailApi] || '-'
            };
        });
    }

    get hasParticipants() {
        return this.participants.length > 0;
    }

    get additionalParticipants() {
        const records = this.data?.additionalParticipants || [];

        return records.map((record, index) => ({
            key: record.Id || String(index),
            number: index + 1,
            role: record.Roles__c || '-',
            title: record.Title__c || '-',
            firstName: record.First_Name__c || '-',
            lastName: record.Last_Name__c || '-',
            email: record.Email__c || '-'
        }));
    }

    get hasAdditionalParticipants() {
        return this.additionalParticipants.length > 0;
    }

    get declaration1Checked() {
        return this.normalizeBoolean(this.getApaRawValue('Declaration 1'));
    }

    get declaration2Checked() {
        return this.normalizeBoolean(this.getApaRawValue('Declaration 2'));
    }

    get declaration1BoxClass() {
        return 'papf-checkbox-box' + (this.declaration1Checked ? ' papf-checkbox-box_checked' : '');
    }

    get declaration2BoxClass() {
        return 'papf-checkbox-box' + (this.declaration2Checked ? ' papf-checkbox-box_checked' : '');
    }

    /* ============================================================
       KEY PUBLICATIONS
       ============================================================ */

    get publications() {
        const records = this.data?.publications || [];
        const fieldLabels = this.data?.fieldLabels?.Publications__c;

        const titleApi = this.findApiNameByLabel(fieldLabels, 'title');
        const authorApi = this.findApiNameByLabel(fieldLabels, 'author');
        const roleApi = this.findApiNameByLabel(fieldLabels, 'role');
        const journalApi = this.findApiNameByLabel(fieldLabels, 'journal');
        const citationApi = this.findApiNameByLabel(fieldLabels, 'citation');
        const identifierApi =
            this.findApiNameByLabel(fieldLabels, 'pmid') || this.findApiNameByLabel(fieldLabels, 'doi');

        return records.map((record, index) => ({
            key: record.Id || String(index),
            number: 'f' + (index + 1),
            title: record[titleApi] || '-',
            authors: record[authorApi] || '-',
            role: record[roleApi] || '-',
            journal: record[journalApi] || '-',
            citations: record[citationApi] || '-',
            identifier: record[identifierApi] || '-'
        }));
    }

    get hasPublications() {
        return this.publications.length > 0;
    }

    /* ============================================================
       PROPOSAL OVERVIEW
       ============================================================ */

    get proposalIdDisplay() {
        return this.getProposalValue('Proposal Id') || this.data?.proposal?.Name || '-';
    }

    get proposalStatus() {
        return this.getProposalValue('Proposal Status') || '-';
    }

    get applicationStage() {
        return this.getProposalValue('Application Stages') || '-';
    }
}