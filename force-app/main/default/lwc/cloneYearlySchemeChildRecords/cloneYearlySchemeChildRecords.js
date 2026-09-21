import { LightningElement, api, track, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getYearlySchemeDetails from '@salesforce/apex/YearlySchemeCloneChild.getYearlySchemeDetails';
import getChildRecords from '@salesforce/apex/YearlySchemeCloneChild.getChildRecords';
import cloneYearlyScheme from '@salesforce/apex/YearlySchemeCloneChild.cloneYearlyScheme';
import getQuestionnairesByItem from '@salesforce/apex/YearlySchemeCloneChild.getQuestionnairesByItem';
import getCloneScreenPicklistOptions from '@salesforce/apex/YearlySchemeCloneChild.getCloneScreenPicklistOptions';
import yearlySchemeExists from '@salesforce/apex/YearlySchemeCloneChild.yearlySchemeExists';
import { CurrentPageReference } from 'lightning/navigation';

export default class CloneYearlySchemeChildRecords extends NavigationMixin(LightningElement) {

    @api recordId;
    @track schemeDetails;
    @track parentFormData = {};

    @track checkListRecords = [];
    @track rulesRecords = [];
    @track questionItemRecords = [];

    @track publishStatusOptions = [];
    @track stageForDocumentOptions = [];
    @track checkListStageOptions = [];
    @track rulesStageOptions = [];
    @track rulesValidationTypeOptions = [];
    @track questionItemStageOptions = [];
    @track questionItemTypeOptions = [];
    @track questionItemAttachmentsOptions = [];
    @track applicationStagesOptions = [];   // NEW
    @track requiredDegreeOptions = [];      // NEW

    @track documentsRecords = [];
    @track externalParticipantsRecords = [];
    @track reviewerQuestionTemplateRecords = [];
    @track yearlySchemeInstructionsRecords = [];
    @track committeeMemberRecords = [];
    @track grantsTeamMembersRecords = [];

    @track selectAllCheckList = false;
    @track selectAllRules = false;
    @track selectAllQuestionItems = false;
    @track selectAllDocuments = false;
    @track selectAllExternalParticipants = false;
    @track selectAllReviewerQuestionTemplates = false;
    @track selectAllYearlySchemeInstructions = false;
    @track selectAllCommitteeMembers = false;
    @track selectAllGrantsTeamMembers = false;

    isLoading = true;
    isSaving = false;
    hasLoaded = false;
    
    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        console.log('[wire] @api recordId at wire time:', this.recordId);

        if (!this.recordId && currentPageReference) {
            const fromAttributes = currentPageReference.attributes?.recordId;
            const fromState = currentPageReference.state?.recordId;
            const fromStateC = currentPageReference.state?.c__recordId;

            this.recordId = fromAttributes || fromState || fromStateC;

            console.log('[wire] currentPageReference:', JSON.stringify(currentPageReference));
            console.log('[wire] resolved recordId from CurrentPageReference:', this.recordId,
                '| source:', fromAttributes ? 'attributes.recordId' : fromState ? 'state.recordId' : fromStateC ? 'state.c__recordId' : 'none');
        }

        if (this.recordId && !this.hasLoaded) {
            console.log('[wire] triggering loadData() from wire, recordId =', this.recordId);
            this.hasLoaded = true;
            this.loadData();
        }
    }

    connectedCallback() {
        console.log('[connectedCallback] @api recordId at connect time:', this.recordId);

        if (this.recordId && !this.hasLoaded) {
            console.log('[connectedCallback] triggering loadData() from connectedCallback, recordId =', this.recordId);
            this.hasLoaded = true;
            this.loadData();
        }
    }


    async loadData() {
        this.isLoading = true;
        try {
            const [details, checkList, rules, documents, externalParticipants, reviewerQuestionTemplates, instructions,  committeeMembers, grantsTeamMembers, picklists] = await Promise.all([
                getYearlySchemeDetails({ recordId: this.recordId }),
                getChildRecords({ recordId: this.recordId, objectApiName: 'Eligibility_Check_List__c' }),
                getChildRecords({ recordId: this.recordId, objectApiName: 'Eligibility_Criteria__c' }),
                getChildRecords({ recordId: this.recordId, objectApiName: 'Documents__c'}),
                getChildRecords({ recordId: this.recordId, objectApiName: 'External_Participants__c'}),
                getChildRecords({ recordId: this.recordId, objectApiName: 'Reviewer_Question_Template__c'}),
                getChildRecords({ recordId: this.recordId, objectApiName: 'Yearly_Scheme_Instructions__c'}),
                getChildRecords({ recordId: this.recordId, objectApiName: 'Committee_Member__c'}),
                getChildRecords({ recordId: this.recordId, objectApiName: 'Grants_Team_Members__c'}),
                getCloneScreenPicklistOptions()
            ]);

            this.schemeDetails = details;

            this.publishStatusOptions = picklists.publishStatus || [];
            this.stageForDocumentOptions = picklists.stageForDocument || []; // NEW
            this.checkListStageOptions = picklists.checkListStage || [];
            this.rulesStageOptions = picklists.rulesStage || [];
            this.rulesValidationTypeOptions = picklists.rulesValidationType || [];
            this.questionItemStageOptions = picklists.questionItemStage || [];
            this.questionItemTypeOptions = picklists.questionItemType || [];
            this.questionItemAttachmentsOptions = picklists.questionItemAttachments || []; // NEW
            this.applicationStagesOptions = picklists.applicationStages || []; // NEW
            this.requiredDegreeOptions = picklists.requiredDegree || [];       // NEW
            this.parentFormData = {
                Scheme_Items__c: details.Scheme_Items__c,
                Year__c: details.Year__c,
                Scheme_Start_Date__c: '',
                Second_Stage_Start_Date__c: '',
                Scheme_End_Date__c: '',
                Second_Stage_End_Date__c: '',
                Scheme_Visibility__c: 'Restricted',
                Is_Active__c: details.Is_Active__c,
                CurrencyIsoCode: details.CurrencyIsoCode,
                Team_Size_Limits__c: details.Team_Size_Limits__c,
                Experience_Required__c: details.Experience_Required__c,
                Experience_Required_To__c: details.Experience_Required_To__c,
                Budget_Cap__c: details.Budget_Cap__c,
                Application_Stages__c: details.Application_Stages__c,
                Required_Degree__c: details.Required_Degree__c ? details.Required_Degree__c.split(';') : [],
                Round__c: (details.Round__c || 0) + 1,
            };

            this.checkListRecords = checkList.map((rec) => ({ ...rec, selected: false }));
            this.rulesRecords = rules.map((rec) => ({ ...rec, selected: false }));

            this.documentsRecords = documents.map((rec) => ({ ...rec, selected: false }));
            this.externalParticipantsRecords = externalParticipants.map((rec) => ({ ...rec, selected: false }));
            this.reviewerQuestionTemplateRecords = reviewerQuestionTemplates.map((rec) => ({ ...rec, selected: false }));
            this.yearlySchemeInstructionsRecords = instructions.map((rec) => ({ ...rec, selected: false }));
            this.committeeMemberRecords = committeeMembers.map((rec) => ({ ...rec, selected: false }));
            this.grantsTeamMembersRecords = grantsTeamMembers.map((rec) => ({ ...rec, selected: false }));

            this.selectAllCheckList = false;
            this.selectAllRules = false;
            this.selectAllDocuments = false;
            this.selectAllExternalParticipants = false;
            this.selectAllReviewerQuestionTemplates = false;
            this.selectAllYearlySchemeInstructions = false;
            this.selectAllCommitteeMembers = false;
            this.selectAllGrantsTeamMembers = false;

            await this.loadQuestionnairesForItem(this.parentFormData.Scheme_Items__c);
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    get noCheckListRecords() {
        return !this.checkListRecords.length;
    }
    get noDocumentRecords() {
        return !this.documentsRecords.length;
    }
    get noExternalParticipantRecords() {
        return !this.externalParticipantsRecords.length;
    }

    get noReviewerQuestionTemplateRecords() {
        return !this.reviewerQuestionTemplateRecords.length;
    }

    get noYearlySchemeInstructionRecords() {
        return !this.yearlySchemeInstructionsRecords.length;
    }

    get noCommitteeMemberRecords() {
        return !this.committeeMemberRecords.length;
    }

    get noGrantsTeamMemberRecords() {
        return !this.grantsTeamMembersRecords.length;
    }
    get noRulesRecords() {
        return !this.rulesRecords.length;
    }
    get noQuestionItemRecords() {
        return !this.questionItemRecords.length;
    }
    get noSchemeItemSelected() {
        return !this.parentFormData.Scheme_Items__c;
    }

    get checkListTabLabel() {
        return `Eligibility Check List (${this.checkListRecords.length})`;
    }
    get documentTabLabel() {
        return `Documents (${this.documentsRecords.length})`;
    }
    get externalParticipantsTabLabel() {
        return `External Participants (${this.externalParticipantsRecords.length})`;
    }
    get reviewerQuestionTemplateTabLabel() {
        return `Reviewer Question Templates (${this.reviewerQuestionTemplateRecords.length})`;
    }
    get yearlySchemeInstructionsTabLabel() {
        return `Yearly Scheme Instructions (${this.yearlySchemeInstructionsRecords.length})`;
    }
    get committeeMemberTabLabel() {
        return `Committee Members (${this.committeeMemberRecords.length})`;
    }
    get grantsTeamMembersTabLabel() {
        return `Grants Team Members (${this.grantsTeamMembersRecords.length})`;
    }
    get rulesTabLabel() {
        return `Eligibility Rules (${this.rulesRecords.length})`;
    }
    get questionItemTabLabel() {
        return `Scheme Question Items (${this.questionItemRecords.length})`;
    }

    // ---------- Parent field editing ----------
    handleParentFieldChange(event) {
        const field = event.target.dataset.field;
        let value;
        if (event.target.type === 'checkbox') {
            value = event.target.checked;
        } else if (event.target.type === 'number') {
            value = event.target.value === '' ? null : Number(event.target.value);
        } else {
            value = event.target.value;
        }
        this.parentFormData = { ...this.parentFormData, [field]: value };
    }

    handlePublishStatusChange(event) {
        this.parentFormData = { ...this.parentFormData, Scheme_Visibility__c: event.detail.value };
    }

    handleYearChange(event) {
        this.parentFormData = { ...this.parentFormData, Year__c: event.detail.recordId };
    }

    // NEW: single-select picklist
    handleApplicationStagesChange(event) {
        this.parentFormData = { ...this.parentFormData, Application_Stages__c: event.detail.value };
    }

    // NEW: multi-select picklist — event.detail.value is already an array of selected values
    handleRequiredDegreeChange(event) {
        this.parentFormData = { ...this.parentFormData, Required_Degree__c: event.detail.value };
    }

    handleSelectAllCheckList(event) {
        const checked = event.target.checked;
        this.selectAllCheckList = checked;
        this.checkListRecords = this.checkListRecords.map(row => ({ ...row, selected: checked }));
    }

    handleSelectAllRules(event) {
        const checked = event.target.checked;
        this.selectAllRules = checked;
        this.rulesRecords = this.rulesRecords.map(row => ({ ...row, selected: checked }));
    }

    handleSelectAllQuestionItems(event) {
        const checked = event.target.checked;
        this.selectAllQuestionItems = checked;
        this.questionItemRecords = this.questionItemRecords.map(row => ({ ...row, selected: checked }));
    }

    async handleSchemeItemChange(event) {
        const newSchemeItemId = event.detail.recordId;
        this.parentFormData = { ...this.parentFormData, Scheme_Items__c: newSchemeItemId };
        await this.loadQuestionnairesForItem(newSchemeItemId);
    }
    /* =========================================================
   DOCUMENTS
   ========================================================= */

    handleSelectAllDocuments(event) {

        const checked = event.target.checked;

        this.selectAllDocuments = checked;

        this.documentsRecords =
            this.documentsRecords.map(row => ({
                ...row,
                selected: checked
            }));
    }
    /* =========================================================
   EXTERNAL PARTICIPANTS
   ========================================================= */

    handleSelectAllExternalParticipants(event) {
        const checked = event.target.checked;

        this.selectAllExternalParticipants = checked;

        this.externalParticipantsRecords =
            this.externalParticipantsRecords.map(row => ({
                ...row,
                selected: checked
            }));
    }

    handleExternalParticipantRowToggle(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;

        this.externalParticipantsRecords =
            this.externalParticipantsRecords.map(row =>
                row.Id === id
                    ? { ...row, selected: checked }
                    : row
            );

        this.selectAllExternalParticipants =
            this.externalParticipantsRecords.length > 0 &&
            this.externalParticipantsRecords.every(row => row.selected);
    }


    /* =========================================================
    REVIEWER QUESTION TEMPLATES
    ========================================================= */

    handleSelectAllReviewerQuestionTemplates(event) {
        const checked = event.target.checked;

        this.selectAllReviewerQuestionTemplates = checked;

        this.reviewerQuestionTemplateRecords =
            this.reviewerQuestionTemplateRecords.map(row => ({
                ...row,
                selected: checked
            }));
    }

    handleReviewerQuestionTemplateRowToggle(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;

        this.reviewerQuestionTemplateRecords =
            this.reviewerQuestionTemplateRecords.map(row =>
                row.Id === id
                    ? { ...row, selected: checked }
                    : row
            );

        this.selectAllReviewerQuestionTemplates =
            this.reviewerQuestionTemplateRecords.length > 0 &&
            this.reviewerQuestionTemplateRecords.every(row => row.selected);
    }


    /* =========================================================
    YEARLY SCHEME INSTRUCTIONS
    ========================================================= */

    handleSelectAllYearlySchemeInstructions(event) {
        const checked = event.target.checked;

        this.selectAllYearlySchemeInstructions = checked;

        this.yearlySchemeInstructionsRecords =
            this.yearlySchemeInstructionsRecords.map(row => ({
                ...row,
                selected: checked
            }));
    }

    handleYearlySchemeInstructionRowToggle(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;

        this.yearlySchemeInstructionsRecords =
            this.yearlySchemeInstructionsRecords.map(row =>
                row.Id === id
                    ? { ...row, selected: checked }
                    : row
            );

        this.selectAllYearlySchemeInstructions =
            this.yearlySchemeInstructionsRecords.length > 0 &&
            this.yearlySchemeInstructionsRecords.every(row => row.selected);
    }


    /* =========================================================
    COMMITTEE MEMBERS
    ========================================================= */

    handleSelectAllCommitteeMembers(event) {
        const checked = event.target.checked;

        this.selectAllCommitteeMembers = checked;

        this.committeeMemberRecords =
            this.committeeMemberRecords.map(row => ({
                ...row,
                selected: checked
            }));
    }

    handleCommitteeMemberRowToggle(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;

        this.committeeMemberRecords =
            this.committeeMemberRecords.map(row =>
                row.Id === id
                    ? { ...row, selected: checked }
                    : row
            );

        this.selectAllCommitteeMembers =
            this.committeeMemberRecords.length > 0 &&
            this.committeeMemberRecords.every(row => row.selected);
    }


    /* =========================================================
    GRANTS TEAM MEMBERS
    ========================================================= */

    handleSelectAllGrantsTeamMembers(event) {
        const checked = event.target.checked;

        this.selectAllGrantsTeamMembers = checked;

        this.grantsTeamMembersRecords =
            this.grantsTeamMembersRecords.map(row => ({
                ...row,
                selected: checked
            }));
    }

    handleGrantsTeamMemberRowToggle(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;

        this.grantsTeamMembersRecords =
            this.grantsTeamMembersRecords.map(row =>
                row.Id === id
                    ? { ...row, selected: checked }
                    : row
            );

        this.selectAllGrantsTeamMembers =
            this.grantsTeamMembersRecords.length > 0 &&
            this.grantsTeamMembersRecords.every(row => row.selected);
    }


    handleDocumentRowToggle(event) {

        const id = event.target.dataset.id;
        const checked = event.target.checked;

        this.documentsRecords =
            this.documentsRecords.map(row =>
                row.Id === id
                    ? {
                        ...row,
                        selected: checked
                    }
                    : row
            );

        this.selectAllDocuments =
            this.documentsRecords.length > 0 &&
            this.documentsRecords.every(
                row => row.selected
            );
    }


    handleDocumentStageChange(event) {

        const id = event.target.dataset.id;
        const value = event.detail.value;

        this.documentsRecords =
            this.documentsRecords.map(row =>
                row.Id === id
                    ? {
                        ...row,
                        Stage__c: value
                    }
                    : row
            );
    }


    handleDocumentFieldChange(event) {

        const id = event.target.dataset.id;
        const field = event.target.dataset.field;

        let value;

        if (event.target.type === 'checkbox') {
            value = event.target.checked;
        } else {
            value = event.target.value;
        }

        this.documentsRecords =
            this.documentsRecords.map(row =>
                row.Id === id
                    ? {
                        ...row,
                        [field]: value
                    }
                    : row
            );
    }


    async loadQuestionnairesForItem(schemeItemId) {
        if (!schemeItemId) {
            this.questionItemRecords = [];
            this.selectAllQuestionItems = false;
            return;
        }
        try {
            const questionnaires = await getQuestionnairesByItem({ schemeItemId });
            this.questionItemRecords = questionnaires.map((q) => ({
                Id: q.Id,
                Name: q.Name,
                DisplayName: q.Display_Name__c,
                selected: false,
                Question__c: q.Display_Name__c,
                Mandatory__c: q.Mandatory__c || false,
                Type__c: q.Type__c || '',
                Max_Character__c: q.Max_Limit__c != null ? q.Max_Limit__c : null,
                Min_Character__c: q.Min_Limit__c != null ? q.Min_Limit__c : null,
                Is_Active__c: q.Is_Active__c || false,
                Stage__c: q.Stage__c || '',
                CurrencyIsoCode: q.CurrencyIsoCode || '',
                Attachments__c: '',
                Section__c: q.Section__c || '',
                SL_No__c: q.SL_No__c != null ? q.SL_No__c : null,
                Picklist_Values__c: q.Picklist_Values__c || ''
            }));
            this.selectAllQuestionItems = false;
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        }
    }

    handleCheckListRowToggle(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        this.checkListRecords = this.checkListRecords.map(row => row.Id === id ? { ...row, selected: checked } : row);
        this.selectAllCheckList = this.checkListRecords.length > 0 && this.checkListRecords.every(row => row.selected);
    }
    handleCheckListStageChange(event) {
        const id = event.target.dataset.id;
        const value = event.detail.value;
        this.checkListRecords = this.checkListRecords.map((row) =>
            row.Id === id ? { ...row, Stage__c: value } : row
        );
    }

    // ---------- Row selection + editing: Eligibility Rules ----------
    handleRulesRowToggle(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        this.rulesRecords = this.rulesRecords.map(row => row.Id === id ? { ...row, selected: checked } : row);
        this.selectAllRules = this.rulesRecords.length > 0 && this.rulesRecords.every(row => row.selected);
    }
    handleRulesStageChange(event) {
        const id = event.target.dataset.id;
        const value = event.detail.value;
        this.rulesRecords = this.rulesRecords.map((row) =>
            row.Id === id ? { ...row, Stage__c: value } : row
        );
    }
    handleRulesValidationTypeChange(event) {
        const id = event.target.dataset.id;
        const value = event.detail.value;
        this.rulesRecords = this.rulesRecords.map((row) =>
            row.Id === id ? { ...row, Validation_Type__c: value } : row
        );
    }

    // ---------- Row selection + editing: Scheme Question Items ----------
    handleQuestionItemRowToggle(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        this.questionItemRecords = this.questionItemRecords.map(row => row.Id === id ? { ...row, selected: checked } : row);
        this.selectAllQuestionItems = this.questionItemRecords.length > 0 && this.questionItemRecords.every(row => row.selected);
    }

    handleQuestionItemFieldChange(event) {
        const id = event.target.dataset.id;
        const field = event.target.dataset.field;
        let value;
        if (event.target.type === 'checkbox') {
            value = event.target.checked;
        } else if (event.target.type === 'number') {
            value = event.target.value === '' ? null : Number(event.target.value);
        } else {
            value = event.target.value;
        }
        this.questionItemRecords = this.questionItemRecords.map((row) =>
            row.Id === id ? { ...row, [field]: value } : row
        );
    }

    handleQuestionItemTypeChange(event) {
        const id = event.target.dataset.id;
        const value = event.detail.value;
        this.questionItemRecords = this.questionItemRecords.map((row) =>
            row.Id === id ? { ...row, Type__c: value } : row
        );
    }
    handleQuestionItemStageChange(event) {
        const id = event.target.dataset.id;
        const value = event.detail.value;
        this.questionItemRecords = this.questionItemRecords.map((row) =>
            row.Id === id ? { ...row, Stage__c: value } : row
        );
    }
    handleQuestionItemAttachmentsChange(event) {
        const id = event.target.dataset.id;
        const value = event.detail.value;
        this.questionItemRecords = this.questionItemRecords.map((row) =>
            row.Id === id ? { ...row, Attachments__c: value } : row
        );
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleSave() {
        this.isSaving = true;
        try {
            const newStartDate = this.parentFormData.Scheme_Start_Date__c;
            const previousEndDate = this.schemeDetails.Scheme_End_Date__c;
            const previousEnd = String(previousEndDate).substring(0, 10);
            if (newStartDate && previousEndDate) {

                // Convert both values to YYYY-MM-DD only
                const newStart = String(newStartDate).substring(0, 10);
                const previousEnd = String(previousEndDate).substring(0, 10);

                console.log('New Scheme Start Date:', newStart);
                console.log('Previous Scheme End Date:', previousEnd);

                if (newStart < previousEnd) {
                    const formattedPreviousEnd = previousEnd
                        ? previousEnd.split('-').reverse().join('/')
                        : '';
                    this.showToast(
                        'Invalid Dates',
                        `Scheme Start Date must be greater than or equal to Previous Yearly Scheme End Date. Previous End Date: ${formattedPreviousEnd}`,
                        'error'
                    );

                    this.isSaving = false;
                    return;
                }
            }

            const checkListPayload = this.checkListRecords
                .filter((r) => r.selected)
                .map((r) => ({
                    Id: r.Id,
                    Stage__c: r.Stage__c,
                    CurrencyIsoCode: r.CurrencyIsoCode,
                    Display_Question__c: r.Display_Question__c,
                    Type__c: r.Type__c
                }));

            const rulesPayload = this.rulesRecords
                .filter((r) => r.selected)
                .map((r) => ({
                   Id: r.Id,
                    Name: r.Name,
                    Validation_Type__c: r.Validation_Type__c,
                    Formula__c: r.Formula__c,
                    Is_Active__c: r.Is_Active__c,
                    Fail_Message__c: r.Fail_Message__c,
                    Pass_Message__c: r.Pass_Message__c,
                    Stage__c: r.Stage__c,
                    Eligibility_Type__c: r.Eligibility_Type__c,
                    Eligibility_Criteria_Id__c: r.Eligibility_Criteria_Id__c,
                    Yearly_Scheme__c: r.Yearly_Scheme__c
                }));

            const questionItemPayload = this.questionItemRecords
                .filter((r) => r.selected)
                .map((r) => ({
                    Scheme_Questionnaire__c: r.Id,
                    Question__c: r.Question__c,
                    Mandatory__c: r.Mandatory__c,
                    Type__c: r.Type__c,
                    Max_Character__c: r.Max_Character__c,
                    Min_Character__c: r.Min_Character__c,
                    Is_Active__c: r.Is_Active__c,
                    Stage__c: r.Stage__c,
                    CurrencyIsoCode: r.CurrencyIsoCode,
                    Attachments__c: r.Attachments__c,
                    Section__c: r.Section__c,               
                    SL_No__c: r.SL_No__c,                   
                    Picklist_Values__c: r.Picklist_Values__c
                }));
            const documentsPayload = this.documentsRecords
                .filter((r) => r.selected)
                .map((r) => ({
                    Id: r.Id,
                    Document_Master__c: r.Document_Master__c,
                    Document_Name__c: r.Document_Name__c,
                    Is_Active__c: r.Is_Active__c,
                    Is_Required__c: r.Is_Required__c,
                    Roles__c: r.Roles__c,
                    Stage__c: r.Stage__c,
                    CurrencyIsoCode: r.CurrencyIsoCode
                }));
            const externalParticipantsPayload =
            this.externalParticipantsRecords
                .filter((r) => r.selected)
                .map((r) => ({
                    Id: r.Id,
                    External_Participants__c:
                        r.External_Participants__c,
                    External_Participants_Count__c:
                        r.External_Participants_Count__c,
                    External_Participants_Status__c:
                        r.External_Participants_Status__c,
                    Maximum_Participants_Count__c:
                        r.Maximum_Participants_Count__c,
                    Stage__c:
                        r.Stage__c
                }));
            const reviewerQuestionTemplatePayload =
            this.reviewerQuestionTemplateRecords
                .filter((r) => r.selected)
                .map((r) => ({
                    Id: r.Id,
                    Is_Visible_To_Peer_Reviewer__c:
                        r.Is_Visible_To_Peer_Reviewer__c,
                    Name: r.Name,
                    Question__c: r.Question__c,
                    Scheme_Questionnaire__c:
                        r.Scheme_Questionnaire__c,
                    Section__c: r.Section__c,
                    SL_No__c: r.SL_No__c,
                    Stage__c: r.Stage__c
                }));
            const yearlySchemeInstructionsPayload =
            this.yearlySchemeInstructionsRecords
                .filter((r) => r.selected)
                .map((r) => ({
                    Id: r.Id,
                    Instructions__c: r.Instructions__c,
                    Know_More__c: r.Know_More__c,
                    Name: r.Name,
                    Pages_Name__c: r.Pages_Name__c,
                    Stage__c: r.Stage__c,
                    Type__c: r.Type__c
                }));
            // const committeeMembersPayload =
            // this.committeeMemberRecords
            //     .filter((r) => r.selected)
            //     .map((r) => ({
            //         Id: r.Id,
            //         Alternative_Mobile_Number__c:
            //             r.Alternative_Mobile_Number__c,
            //         Assignment_Count__c:
            //             r.Assignment_Count__c,
            //         City__c: r.City__c,
            //         Committee_Master__c:
            //             r.Committee_Master__c,
            //         Community_Member_Password__c:
            //             r.Community_Member_Password__c,
            //         Country__c: r.Country__c,
            //         Department__c: r.Department__c,
            //         Designation__c: r.Designation__c,
            //         Email__c: r.Email__c,
            //         First_Name__c: r.First_Name__c,
            //         Is_Committee_Review__c:
            //             r.Is_Committee_Review__c,
            //         Last_Name__c: r.Last_Name__c,
            //         Mobile_Number__c:
            //             r.Mobile_Number__c,
            //         Organisation_Name__c:
            //             r.Organisation_Name__c,
            //         Sequence__c: r.Sequence__c,
            //         State__c: r.State__c,
            //         Title__c: r.Title__c,
            //         Type__c: r.Type__c
            //     }));
            // const grantsTeamMembersPayload =
            // this.grantsTeamMembersRecords
            //     .filter((r) => r.selected)
            //     .map((r) => ({
            //         Id: r.Id,
            //         Application_Stages__c:
            //             r.Application_Stages__c,
            //         Grants_Team_Member_Id__c:
            //             r.Grants_Team_Member_Id__c,
            //         User__c: r.User__c
            //     }));
            // Convert Required_Degree__c array back to the ';'-delimited string
            // Salesforce expects for a multi-select picklist field.
            const parentOverrides = {
                ...this.parentFormData,
                Required_Degree__c: Array.isArray(this.parentFormData.Required_Degree__c)
                    ? this.parentFormData.Required_Degree__c.join(';')
                    : this.parentFormData.Required_Degree__c
            };

            const exists = await yearlySchemeExists({
                yearId: this.parentFormData.Year__c,
                schemeItemId: this.parentFormData.Scheme_Items__c
            });

            // if (exists) {
            //     this.showToast(
            //         'Duplicate Record',
            //         'A Yearly Scheme already exists for the selected Year and Scheme.Please Change the Scheme Or Year',
            //         'warning'
            //     );
            //     this.isSaving = false;
            //     return;
            // }

            const newRecordId = await cloneYearlyScheme({
                recordId: this.recordId,
                parentOverrides,
                checkListRecords: checkListPayload,
                rulesRecords: rulesPayload,
                questionItemRecords: questionItemPayload,
                documentsRecords: documentsPayload,
                externalParticipantsRecords: externalParticipantsPayload,
                reviewerQuestionTemplateRecords: reviewerQuestionTemplatePayload,
                yearlySchemeInstructionsRecords: yearlySchemeInstructionsPayload,
                //committeeMembersRecords: committeeMembersPayload,
               // grantsTeamMembersRecords: grantsTeamMembersPayload
            });

            this.showToast('Success', 'Yearly Scheme cloned successfully.', 'success');
            this.dispatchEvent(new CloseActionScreenEvent());

            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: newRecordId,
                    objectApiName: 'Yearly_Schemes__c',
                    actionName: 'view'
                }
            });
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    getErrorMessage(error) {
        return error && error.body && error.body.message ? error.body.message : 'Unknown error occurred';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}