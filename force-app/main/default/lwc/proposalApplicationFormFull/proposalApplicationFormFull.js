import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getProposalDetails from '@salesforce/apex/ProposalApplicantDetailsController.getProposalDetails';

/*
 * Full Application sidebar - mirrors the section list from the applicant-facing
 * Full Application form. Only 'projectSummary' is wired up to real fields so
 * far; every other section renders the shared placeholder until its fields
 * are specified and built out the same way.
 */
const SIDEBAR_SECTIONS = [
    { key: 'projectSummary', number: 1, label: 'Project Summary', kind: 'projectSummary' },
    { key: 'researchProposal', number: 2, label: 'Research Proposal', kind: 'researchProposal' },
    { key: 'humanParticipants', number: 3, label: 'Research Involving Human Participants', kind: 'humanParticipants' },
    { key: 'animalExperiments', number: 4, label: 'Research Involving Experiment on Animals', kind: 'animalExperiments' },
    { key: 'applicantCV', number: 5, label: 'Applicant CV', kind: 'applicantCV' },
    { key: 'otherGrants', number: 6, label: 'Other Grants and Applications', kind: 'otherGrants' },
    { key: 'hostInstitutionDetails', number: 7, label: 'Host Institution Details', kind: 'hostInstitutionDetails' },
    { key: 'fellowshipSupervisorDetails', number: 8, label: 'Fellowship Supervisor Details', kind: 'fellowshipSupervisorDetails' },
    { key: 'wohi', number: 9, label: 'Work Outside Host Institution (WOHI)', kind: 'wohi' },
    { key: 'collaboration', number: 10, label: 'Collaboration', kind: 'collaboration' },
    { key: 'disseminationPlans', number: 11, label: 'Dissemination Plans', kind: 'disseminationPlans' },
    { key: 'budget', number: 12, label: 'Budget', kind: 'budget' },
    { key: 'additionalRole', number: 13, label: 'Additional Role', kind: 'additionalRole' },
    { key: 'lettersDeclaration', number: 14, label: 'Additional Section for Letters and Declaration', kind: 'lettersDeclaration' }
];

/*
 * Budget sub-tabs (Section 12 only). Only 'personalSupport' is wired up so
 * far, and even there only the Yes/Yes combination of the two salary-support
 * questions is built - the other combinations and the remaining tabs render
 * the shared placeholder until specified.
 */
const BUDGET_TABS = [
    { key: 'personalSupport', label: 'A. Personal Support', kind: 'personalSupport' },
    { key: 'staff', label: 'B. Staff', kind: 'staff' },
    { key: 'materialsConsumables', label: 'C. Materials & Consumables', kind: 'materialsConsumables' },
    { key: 'equipment', label: 'D. Equipment', kind: 'equipment' },
    { key: 'accessCharges', label: 'E. Access Charges', kind: 'accessCharges' },
    { key: 'animals', label: 'F. Animals', kind: 'animals' },
    { key: 'travelToMeetings', label: 'G. Travel to Meetings', kind: 'travelToMeetings' },
    { key: 'wohiAllowance', label: 'H. WOHI Allowance', kind: 'wohiAllowance' },
    { key: 'miscellaneous', label: 'I. Miscellaneous', kind: 'miscellaneous' },
    { key: 'flexibleFunding', label: 'J. Flexible Funding', kind: 'flexibleFunding' }
];

/*
 * Animals budget sub-tabs (within the F. Animals Budget tab only). Only
 * 'animalPurchase' is wired up so far, per instruction - the other three
 * render the shared placeholder until their fields are specified.
 */
const ANIMAL_SUB_TABS = [
    { key: 'animalPurchase', label: 'Animal Purchase (Max 10)', kind: 'animalPurchase' },
    { key: 'animalMaintenance', label: 'Animal Maintenance (Max 10)', kind: 'animalMaintenance' },
    { key: 'experimentalProcedures', label: 'Experimental Procedures (Max 10)', kind: 'experimentalProcedures' },
    { key: 'associatedCosts', label: 'Associated Costs', kind: 'associatedCosts' }
];

export default class ProposalApplicationFormFull extends LightningElement {
    _recordId;
    isLoading = false;
    error;
    data;
    activeSectionKey = 'projectSummary';
    activeBudgetTabKey = 'personalSupport';
    activeAnimalSubTabKey = 'animalPurchase';

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
            // Same Apex method the Prelim form uses - it already fetches every
            // accessible Proposal__c field generically, so no Apex changes are
            // needed to pick up new Full-stage fields.
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

    get isProjectSummaryActive() {
        return this.activeSection?.kind === 'projectSummary';
    }

    get isResearchProposalActive() {
        return this.activeSection?.kind === 'researchProposal';
    }

    get isHumanParticipantsActive() {
        return this.activeSection?.kind === 'humanParticipants';
    }

    get isAnimalExperimentsActive() {
        return this.activeSection?.kind === 'animalExperiments';
    }

    get isApplicantCVActive() {
        return this.activeSection?.kind === 'applicantCV';
    }

    get isOtherGrantsActive() {
        return this.activeSection?.kind === 'otherGrants';
    }

    get isHostInstitutionDetailsActive() {
        return this.activeSection?.kind === 'hostInstitutionDetails';
    }

    get isWohiActive() {
        return this.activeSection?.kind === 'wohi';
    }

    get isCollaborationActive() {
        return this.activeSection?.kind === 'collaboration';
    }

    get isFellowshipSupervisorDetailsActive() {
        return this.activeSection?.kind === 'fellowshipSupervisorDetails';
    }

    get isDisseminationPlansActive() {
        return this.activeSection?.kind === 'disseminationPlans';
    }

    get isAdditionalRoleActive() {
        return this.activeSection?.kind === 'additionalRole';
    }

    get isLettersDeclarationActive() {
        return this.activeSection?.kind === 'lettersDeclaration';
    }

    get isBudgetActive() {
        return this.activeSection?.kind === 'budget';
    }

    /* ============================================================
       12. BUDGET (sub-tab navigation)
       ============================================================ */

    get budgetTabs() {
        return BUDGET_TABS.map((tab) => {
            const isActive = tab.key === this.activeBudgetTabKey;
            return {
                ...tab,
                isActive,
                itemClass: 'papf-budget-tab' + (isActive ? ' papf-budget-tab_active' : '')
            };
        });
    }

    handleSelectBudgetTab(event) {
        this.activeBudgetTabKey = event.currentTarget.dataset.key;
    }

    get activeBudgetTab() {
        return BUDGET_TABS.find((tab) => tab.key === this.activeBudgetTabKey);
    }

    get isPersonalSupportTabActive() {
        return this.activeBudgetTab?.kind === 'personalSupport';
    }

    get isStaffTabActive() {
        return this.activeBudgetTab?.kind === 'staff';
    }

    get isMaterialsConsumablesTabActive() {
        return this.activeBudgetTab?.kind === 'materialsConsumables';
    }

    get isEquipmentTabActive() {
        return this.activeBudgetTab?.kind === 'equipment';
    }

    get isAccessChargesTabActive() {
        return this.activeBudgetTab?.kind === 'accessCharges';
    }

    get isAnimalsTabActive() {
        return this.activeBudgetTab?.kind === 'animals';
    }

    get isTravelToMeetingsTabActive() {
        return this.activeBudgetTab?.kind === 'travelToMeetings';
    }

    get isWohiAllowanceTabActive() {
        return this.activeBudgetTab?.kind === 'wohiAllowance';
    }

    /* ------------------------------------------------------------
       F. Animals - nested sub-tab navigation
       ------------------------------------------------------------ */

    get animalSubTabs() {
        return ANIMAL_SUB_TABS.map((tab) => {
            const isActive = tab.key === this.activeAnimalSubTabKey;
            return {
                ...tab,
                isActive,
                itemClass: 'papf-animal-subtab' + (isActive ? ' papf-animal-subtab_active' : '')
            };
        });
    }

    handleSelectAnimalSubTab(event) {
        this.activeAnimalSubTabKey = event.currentTarget.dataset.key;
    }

    get activeAnimalSubTab() {
        return ANIMAL_SUB_TABS.find((tab) => tab.key === this.activeAnimalSubTabKey);
    }

    get isAnimalPurchaseSubTabActive() {
        return this.activeAnimalSubTab?.kind === 'animalPurchase';
    }

    get isAssociatedCostsSubTabActive() {
        return this.activeAnimalSubTab?.kind === 'associatedCosts';
    }

    get isAnimalMaintenanceSubTabActive() {
        return this.activeAnimalSubTab?.kind === 'animalMaintenance';
    }

    get isExperimentalProceduresSubTabActive() {
        return this.activeAnimalSubTab?.kind === 'experimentalProcedures';
    }

    get activeAnimalPlaceholderLabel() {
        return this.activeAnimalSubTab?.kind === 'placeholder' ? this.activeAnimalSubTab.label : null;
    }

    get isMiscellaneousTabActive() {
        return this.activeBudgetTab?.kind === 'miscellaneous';
    }

    get isFlexibleFundingTabActive() {
        return this.activeBudgetTab?.kind === 'flexibleFunding';
    }

    get activeBudgetPlaceholderLabel() {
        return this.activeBudgetTab?.kind === 'placeholder' ? this.activeBudgetTab.label : null;
    }

    get activePlaceholderLabel() {
        return this.activeSection?.kind === 'placeholder' ? this.activeSection.label : null;
    }

    /* ============================================================
       FIELD LOOKUP HELPERS (same label-matching pattern as the Prelim form)
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
       1. PROJECT SUMMARY
       ============================================================ */

    // Same Proposal__c field as the Prelim form's Project Title.
    get projectTitle() {
        return this.getProposalValue('Project Title');
    }

    get researchSummaryHighlightingElements() {
        return this.getProposalValue('Proposed Research highlighting Elements');
    }

    get nonSpecialistSummary() {
        return this.getProposalValue('Summary of Non-Specialist Audience');
    }

    // Same Keywords__c field as Prelim, rendered as chips instead of plain text.
    get keywordChips() {
        const raw = this.getProposalValue('Keywords');
        if (!raw) {
            return [];
        }
        return raw
            .split(',')
            .map((keyword) => keyword.trim())
            .filter(Boolean)
            .map((keyword, index) => ({ key: index + '-' + keyword, label: keyword }));
    }

    get hasKeywords() {
        return this.keywordChips.length > 0;
    }

    /* ============================================================
       2. RESEARCH PROPOSAL
       ============================================================ */

    get backgroundAndSignificance() {
        return this.getProposalValue('Background And Rationale');
    }

    get aimsAndHypotheses() {
        return this.getProposalValue('Aims & Hypotheses');
    }

    get workLeadingUpToProject() {
        return this.getProposalValue('Work leading up to the Project');
    }

    get experimentalDesignMethods() {
        return this.getProposalValue('Experimental Design & Methods');
    }

    get fullDetailsOfExperiments() {
        return this.getProposalValue('Full details of experiments');
    }

    get researchProposalImpact() {
        return this.getProposalValue('Impact');
    }

    get risksMitigation() {
        return this.getProposalValue('Risks & Mitigation');
    }

    get researchProposalReferences() {
        return this.getProposalValue('References');
    }

    get projectMilestones() {
        const records = this.data?.projectMilestones || [];
        const fieldLabels = this.data?.fieldLabels?.Project_Milestone__c;
        const deliverablesApi = this.findApiNameByLabel(fieldLabels, 'Deliverables mapped to the objective');
        const locationApi = this.findApiNameByLabel(fieldLabels, 'Location Expected to Deliver Milestone');

        return records.map((record, index) => ({
            key: record.Id || String(index),
            milestone: record.Milestone__c || '-',
            deliverables: (deliverablesApi && record[deliverablesApi]) || '-',
            startDate: record.Start_Date__c || '-',
            endDate: record.End_Date__c || '-',
            location: (locationApi && record[locationApi]) || '-'
        }));
    }

    // Gantt input: same milestones as the table, but with the locale-independent ISO dates.
    get ganttMilestones() {
        return (this.data?.projectMilestones || []).map((record) => ({
            milestone: record.Milestone__c,
            startDate: record.startDateIso,
            endDate: record.endDateIso
        }));
    }

    get hasProjectMilestones() {
        return this.projectMilestones.length > 0;
    }

    // Files from User_Documents__c linked to the Proposal, already filtered (Full stage,
    // Submitted/Uploaded) and categorised server-side - see getProposalDetails.
    proposalDocumentsByCategory(category) {
        return (this.data?.proposalDocuments || [])
            .filter((doc) => doc.category === category)
            .map((doc, index) => ({
                key: doc.id || String(index),
                name: doc.name,
                url: doc.url
            }));
    }

    get flowchartDocuments() {
        return this.proposalDocumentsByCategory('flowchart');
    }

    get hasFlowchartDocuments() {
        return this.flowchartDocuments.length > 0;
    }

    get supportDocuments() {
        return this.proposalDocumentsByCategory('document');
    }

    get hasSupportDocuments() {
        return this.supportDocuments.length > 0;
    }

    /* ============================================================
       4. RESEARCH INVOLVING EXPERIMENT ON ANIMALS
       ============================================================ */

    get animalsRecord() {
        return this.data?.animals || {};
    }

    getAnimalsValue(labelFragment) {
        const fieldLabels = this.data?.fieldLabels?.Animals__c;
        const apiName = this.findApiNameByLabel(fieldLabels, labelFragment);
        if (!apiName) {
            return '';
        }
        const value = this.animalsRecord?.[apiName];
        return value === null || value === undefined ? '' : String(value);
    }

    getAnimalsRawValue(labelFragment) {
        const fieldLabels = this.data?.fieldLabels?.Animals__c;
        const apiName = this.findApiNameByLabel(fieldLabels, labelFragment);
        return apiName ? this.animalsRecord?.[apiName] : undefined;
    }

    // MultiselectPicklist values come back ';'-separated.
    splitMultiselect(raw) {
        if (!raw) {
            return [];
        }
        return String(raw)
            .split(';')
            .map((value) => value.trim())
            .filter(Boolean);
    }

    get proposalInvolvesSelections() {
        return this.splitMultiselect(this.getAnimalsRawValue('My Proposal Involves'));
    }

    get hasAnimalsInvolvement() {
        return this.proposalInvolvesSelections.length > 0;
    }

    get involvesYesClass() {
        return 'papf-radio-option' + (this.hasAnimalsInvolvement ? ' papf-radio-option_selected' : '');
    }

    get involvesNoClass() {
        return 'papf-radio-option' + (!this.hasAnimalsInvolvement ? ' papf-radio-option_selected' : '');
    }

    get isAnimalsChecked() {
        return this.proposalInvolvesSelections.includes('The Use of animals');
    }

    get involvesAnimalsBoxClass() {
        return 'papf-checkbox-box' + (this.isAnimalsChecked ? ' papf-checkbox-box_checked' : '');
    }

    get isAnimalTissueChecked() {
        return this.proposalInvolvesSelections.includes('The Use of animal tissue');
    }

    get involvesAnimalTissueBoxClass() {
        return 'papf-checkbox-box' + (this.isAnimalTissueChecked ? ' papf-checkbox-box_checked' : '');
    }

    get isStemCellsChecked() {
        return this.proposalInvolvesSelections.includes('The Use of non-human stem cells');
    }

    get nonHumanStemCellsBoxClass() {
        return 'papf-checkbox-box' + (this.isStemCellsChecked ? ' papf-checkbox-box_checked' : '');
    }

    get proceduresRequireApproval() {
        return this.getAnimalsRawValue('Proposal Carried out on animals') === true;
    }

    get proceduresApprovalYesClass() {
        return 'papf-radio-option' + (this.proceduresRequireApproval ? ' papf-radio-option_selected' : '');
    }

    get proceduresApprovalNoClass() {
        return 'papf-radio-option' + (!this.proceduresRequireApproval ? ' papf-radio-option_selected' : '');
    }

    get ccseaRegistrationNumber() {
        return this.getAnimalsValue('CCSEA registration number');
    }

    get proposedSourceOfAnimals() {
        return this.getAnimalsValue('Proposed source of the animals');
    }

    get severityOfProcedures() {
        return this.getAnimalsValue('Severity of_the procedures on the animal');
    }

    get substantialSeverityProcedures() {
        return this.getAnimalsValue('Any procedures of substantial Severity');
    }

    get whyAnimalUseNecessary() {
        return this.getAnimalsValue('Why is animal use necessary');
    }

    get speciesUsedSelections() {
        return this.splitMultiselect(this.getAnimalsRawValue('Species used'));
    }

    get isRodentsChecked() {
        return this.speciesUsedSelections.includes('Rodents');
    }

    get speciesRodentsBoxClass() {
        return 'papf-checkbox-box' + (this.isRodentsChecked ? ' papf-checkbox-box_checked' : '');
    }

    get isPrimateChecked() {
        return this.speciesUsedSelections.includes('Primate');
    }

    get speciesPrimateBoxClass() {
        return 'papf-checkbox-box' + (this.isPrimateChecked ? ' papf-checkbox-box_checked' : '');
    }

    get isEquidaeChecked() {
        return this.speciesUsedSelections.includes('Equidae');
    }

    get speciesEquidaeBoxClass() {
        return 'papf-checkbox-box' + (this.isEquidaeChecked ? ' papf-checkbox-box_checked' : '');
    }

    get isGeneticallyAlteredChecked() {
        return this.speciesUsedSelections.includes('Genetically Altered');
    }

    get speciesGeneticallyAlteredBoxClass() {
        return 'papf-checkbox-box' + (this.isGeneticallyAlteredChecked ? ' papf-checkbox-box_checked' : '');
    }

    get isOtherAnimalsChecked() {
        return this.speciesUsedSelections.includes('Other Animals');
    }

    get speciesOtherAnimalsBoxClass() {
        return 'papf-checkbox-box' + (this.isOtherAnimalsChecked ? ' papf-checkbox-box_checked' : '');
    }

    get otherAnimalNamesToBeUsed() {
        return this.animalsRecord?.Other_Animal_Names_to_be_Used__c || '';
    }

    get whySpeciesMostAppropriate() {
        return this.getAnimalsValue('Why is/are the species most appropriate');
    }

    get animalSpeciesEntries() {
        const records = this.data?.animalSpecies || [];
        return records.map((record, index) => ({
            key: record.Id || String(index),
            slNo: index + 1,
            species: record.Animal_Species__c || '-',
            strain: record.Animal_Strain__c || '-',
            group: record.Group__c || '-',
            experimentTitle: record.Experiment_Title__c || '-',
            numberOfAnimals: record.No_of_Animals__c ?? '-'
        }));
    }

    get hasAnimalSpeciesEntries() {
        return this.animalSpeciesEntries.length > 0;
    }

    get sampleSizeJustification() {
        return this.getAnimalsValue('Sample size justification Power');
    }

    get biohazardsAssociated() {
        return this.getAnimalsValue('biohazards associated');
    }

    get wasteManagementProtocol() {
        return this.getAnimalsValue('Protocol for waste management');
    }

    get procedureToMinimizeStress() {
        return this.getAnimalsValue('Describe procedure to be implemented');
    }

    get isExperimentTerminal() {
        return this.getAnimalsValue('Exprmnt on animals terminal');
    }

    get iaecReviewTimelines() {
        return this.getAnimalsValue('Reviewed by IAEC, with timelines');
    }

    get iaecNotReviewedDetails() {
        return this.getAnimalsValue('if not reviewed by IAEC, With Timelines');
    }

    /* ============================================================
       5. APPLICANT CV (same underlying data as the Prelim form - CV
       content doesn't change by stage)
       ============================================================ */

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

    get contactRecord() {
        return (this.data?.contacts || [])[0] || {};
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
       6. OTHER GRANTS AND APPLICATIONS (same underlying objects as the
       Prelim form: Existing_Grants__c for the research grants table,
       Other_Grants__c split by Grants_Type__c for the two ongoing/
       previous-application blocks)
       ============================================================ */

    hasRawValue(value) {
        return value !== null && value !== undefined && value !== '';
    }

    get apaRecord() {
        return (this.data?.applicants || [])[0] || {};
    }

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
        return (
            'papf-radio-option' +
            (this.hasRawValue(this.firstApplicationRaw) && !this.isFirstApplicationYes
                ? ' papf-radio-option_selected'
                : '')
        );
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
        return (
            'papf-radio-option' +
            (this.hasRawValue(this.otherOngoingApplicationsRaw) && !this.isOtherOngoingApplicationsYes
                ? ' papf-radio-option_selected'
                : '')
        );
    }

    get showOngoingApplicationFields() {
        return this.isOtherOngoingApplicationsYes;
    }

    /* ============================================================
       7. HOST INSTITUTION DETAILS (same underlying objects as the
       Prelim form's Research Environment section: Applicant_Host_Association__c
       + its Host__c lookup to Account, and these 3 Proposal__c fields)
       ============================================================ */

    get proposalRecord() {
        return this.data?.proposal || {};
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

    /* ============================================================
       8. FELLOWSHIP SUPERVISOR DETAILS (Proposal_Participant_Association__c
       where Roles__c = 'Supervisor', + its linked Contact via Participant__c)
       ============================================================ */

    get supervisorParticipant() {
        // Deliberately sourced from data.supervisorParticipant (not data.participants) -
        // the Apex side looks this up without the Stage__c filter so the Supervisor
        // record set up during Prelims keeps showing on the Full form.
        return this.data?.supervisorParticipant || {};
    }

    get supervisorContact() {
        return this.supervisorParticipant?.contactData || {};
    }

    get supervisorTitle() {
        return this.supervisorContact?.Salutation || '';
    }

    get supervisorFirstName() {
        return this.supervisorContact?.FirstName || '';
    }

    get supervisorLastName() {
        return this.supervisorContact?.LastName || '';
    }

    get supervisorNationality() {
        return this.supervisorContact?.Nationality__c || '';
    }

    get supervisorGender() {
        return this.supervisorContact?.Gender__c || '';
    }

    get supervisorDesignation() {
        return this.supervisorContact?.Position__c || '';
    }

    get supervisorDepartment() {
        return this.supervisorContact?.Department || '';
    }

    get supervisorOrganisation() {
        // toMap() resolves a Reference field to its parent's Name, so AccountId
        // here already holds the Account (Organisation) name string.
        return this.supervisorContact?.AccountId || '';
    }

    get supervisorTelephone() {
        return this.supervisorContact?.Phone || '';
    }

    get supervisorEmail() {
        return this.supervisorContact?.Email || '';
    }

    get supervisorHostInstitutionName() {
        return this.hostInstitutionName;
    }

    get supervisorPostdocsCount() {
        const value = this.supervisorParticipant?.Number_of_postdocs_trained_in_your_lab__c;
        return value === null || value === undefined ? '' : String(value);
    }

    get supervisorApplicationAlign() {
        return this.supervisorParticipant?.how_application_align__c || '';
    }

    get supervisorDataManagementPlan() {
        return this.supervisorParticipant?.Share_your_plan_how_you_will_manage__c || '';
    }

    get supervisorPastGrants() {
        return this.supervisorParticipant?.Your_present_past_relevant_grants__c || '';
    }

    // The supervisor's uploaded document lives on the Proposal_Participant_Association__c
    // itself (Document_URL__c / Document_Status__c), not in User_Documents__c.
    get supervisorDocumentUrl() {
        return (this.supervisorParticipant?.Document_URL__c || '').trim();
    }

    get hasSupervisorDocument() {
        return this.supervisorDocumentUrl !== '';
    }

    get supervisorDocumentName() {
        return this.fileNameFromUrl(this.supervisorDocumentUrl);
    }

    get supervisorDocumentStatus() {
        return this.supervisorParticipant?.Document_Status__c || 'Pending';
    }

    get isSupervisorDocumentSubmitted() {
        return ['Submitted', 'Approved', 'ReSubmitted'].includes(this.supervisorDocumentStatus);
    }

    get supervisorDocumentStatusIcon() {
        return this.isSupervisorDocumentSubmitted ? 'utility:success' : 'utility:clock';
    }

    get supervisorDocumentStatusClass() {
        return (
            'papf-status-badge' +
            (this.isSupervisorDocumentSubmitted ? ' papf-status-badge_uploaded' : ' papf-status-badge_pending')
        );
    }

    /* ============================================================
       11. DISSEMINATION PLANS (Proposal__c fields)
       ============================================================ */

    get projectionOfPublications() {
        return this.proposalRecord?.Projection_of_publications__c || '';
    }

    get intellectualPropertyCommercial() {
        return this.proposalRecord?.Intellectual_Property_Commercial__c || '';
    }

    get policyPracticeEngagement() {
        return this.proposalRecord?.Policy_Practice_Engagement__c || '';
    }

    get conferencesAcademicPresentations() {
        return this.proposalRecord?.Conferences_Academic_Presentations__c || '';
    }

    /* ============================================================
       13. ADDITIONAL ROLE (Referees: Additional_Partcipant__c where
       Roles__c = 'Referee'; Sponsors: Proposal_Participant_Association__c
       where Roles__c = 'Sponsor', both looked up without the Stage__c
       filter - same reasoning as the Fellowship Supervisor)
       ============================================================ */

    get referees() {
        const records = this.data?.referees || [];
        return records.map((record, index) => {
            const isUploaded = this.normalizeBoolean(record.DocumentUploaded__c);
            return {
                key: record.Id || String(index),
                number: index + 1,
                role: record.Roles__c || '',
                email: record.Email__c || '',
                title: record.Title__c || '',
                firstName: record.First_Name__c || '',
                lastName: record.Last_Name__c || '',
                isUploaded,
                documentStatusLabel: isUploaded ? 'Uploaded' : 'Pending',
                documentStatusIcon: isUploaded ? 'utility:success' : 'utility:clock',
                documentStatusClass:
                    'papf-status-badge' + (isUploaded ? ' papf-status-badge_uploaded' : ' papf-status-badge_pending')
            };
        });
    }

    get hasReferees() {
        return this.referees.length > 0;
    }

    get sponsors() {
        const records = this.data?.sponsors || [];
        return records.map((record, index) => {
            const contact = record.contactData || {};
            return {
                key: record.Id || String(index),
                number: index + 1,
                role: record.Roles__c || '',
                participantName: contact.Name || '',
                hostInstitutionName: this.hostInstitutionName,
                email: contact.Email || '',
                title: contact.Salutation || '',
                firstName: contact.FirstName || '',
                lastName: contact.LastName || '',
                nationality: contact.Nationality__c || '',
                gender: contact.Gender__c || '',
                designation: contact.Position__c || '',
                department: contact.Department || '',
                organisation: contact.AccountId || '',
                telephone: contact.Phone || '',
                ...this.participantDocumentInfo(record)
            };
        });
    }

    // Document state for a Proposal_Participant_Association__c (Document_Status__c /
    // Document_URL__c live on the association itself) - shared by the Sponsor cards; the
    // Fellowship Supervisor getters below read the same two fields.
    participantDocumentInfo(record) {
        const status = record?.Document_Status__c || 'Pending';
        const isSubmitted = ['Submitted', 'Approved', 'ReSubmitted'].includes(status);
        const url = (record?.Document_URL__c || '').trim();
        return {
            documentStatus: status,
            documentStatusIcon: isSubmitted ? 'utility:success' : 'utility:clock',
            documentStatusClass:
                'papf-status-badge' + (isSubmitted ? ' papf-status-badge_uploaded' : ' papf-status-badge_pending'),
            documentUrl: url,
            hasDocument: url !== '',
            documentName: this.fileNameFromUrl(url)
        };
    }

    // S3 keys look like '<folder>/<uuid>_<original file name>' - show just the file name.
    fileNameFromUrl(url) {
        const raw = (url || '').split('?')[0].split('/').pop() || '';
        let name = raw;
        try {
            name = decodeURIComponent(raw);
        } catch (e) {
            name = raw;
        }
        return name.replace(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}_/i, '');
    }

    get hasSponsors() {
        return this.sponsors.length > 0;
    }

    /* ============================================================
       14. ADDITIONAL SECTION FOR LETTERS AND DECLARATION
       (Risk_Identified__c, Conflicts_of_interest__c,
       Will_the_proposed_research_use__c, Want_Restricted_Reviewer__c
       are on Proposal__c; Declaration_3__c/Declaration_4__c are on
       Applicant_Proposal_Association__c; reviewer tables come from
       Suggested_Reviewer__c, split by Type__c)
       ============================================================ */

    get riskIdentifiedValue() {
        return this.proposalRecord?.Risk_Identified__c || '';
    }

    get isRiskYesSelected() {
        return this.riskIdentifiedValue === 'Yes';
    }

    get isRiskNoSelected() {
        return this.riskIdentifiedValue === 'No';
    }

    get riskYesOptionClass() {
        return 'papf-radio-option' + (this.isRiskYesSelected ? ' papf-radio-option_selected' : '');
    }

    get riskNoOptionClass() {
        return 'papf-radio-option' + (this.isRiskNoSelected ? ' papf-radio-option_selected' : '');
    }

    get conflictsOfInterestValues() {
        return this.splitMultiselect(this.proposalRecord?.Conflicts_of_interest__c);
    }

    checkboxClassFor(values, label) {
        return 'papf-checkbox-box' + (values.includes(label) ? ' papf-checkbox-box_checked' : '');
    }

    get isConflictSponsorshipChecked() {
        return this.conflictsOfInterestValues.includes('Research sponsorship agreement');
    }

    get conflictSponsorshipBoxClass() {
        return this.checkboxClassFor(this.conflictsOfInterestValues, 'Research sponsorship agreement');
    }

    get isConflictConsultanciesChecked() {
        return this.conflictsOfInterestValues.includes('Consultancies');
    }

    get conflictConsultanciesBoxClass() {
        return this.checkboxClassFor(this.conflictsOfInterestValues, 'Consultancies');
    }

    get isConflictEquityChecked() {
        return this.conflictsOfInterestValues.includes('Equity holdings');
    }

    get conflictEquityBoxClass() {
        return this.checkboxClassFor(this.conflictsOfInterestValues, 'Equity holdings');
    }

    get isConflictDirectorshipsChecked() {
        return this.conflictsOfInterestValues.includes('Directorships');
    }

    get conflictDirectorshipsBoxClass() {
        return this.checkboxClassFor(this.conflictsOfInterestValues, 'Directorships');
    }

    get isConflictOtherChecked() {
        return this.conflictsOfInterestValues.includes('Other affiliations');
    }

    get conflictOtherBoxClass() {
        return this.checkboxClassFor(this.conflictsOfInterestValues, 'Other affiliations');
    }

    get isConflictNoneChecked() {
        return this.conflictsOfInterestValues.includes('None');
    }

    get conflictNoneBoxClass() {
        return this.checkboxClassFor(this.conflictsOfInterestValues, 'None');
    }

    get researchUseValues() {
        return this.splitMultiselect(this.proposalRecord?.Will_the_proposed_research_use__c);
    }

    get isResearchUsePatentedChecked() {
        return this.researchUseValues.includes('Use of patented/IP technology');
    }

    get researchUsePatentedBoxClass() {
        return this.checkboxClassFor(this.researchUseValues, 'Use of patented/IP technology');
    }

    get isResearchUseAgreementsChecked() {
        return this.researchUseValues.includes('Agreements with commercial/academic/other organisations');
    }

    get researchUseAgreementsBoxClass() {
        return this.checkboxClassFor(this.researchUseValues, 'Agreements with commercial/academic/other organisations');
    }

    get isResearchUseNoneChecked() {
        return this.researchUseValues.includes('None');
    }

    get researchUseNoneBoxClass() {
        return this.checkboxClassFor(this.researchUseValues, 'None');
    }

    get isDeclarationPlagiarismChecked() {
        return this.normalizeBoolean(this.apaRecord?.Declaration_3__c);
    }

    get declarationPlagiarismBoxClass() {
        return 'papf-checkbox-box' + (this.isDeclarationPlagiarismChecked ? ' papf-checkbox-box_checked' : '');
    }

    get isDeclarationAccurateChecked() {
        return this.normalizeBoolean(this.apaRecord?.Declaration_4__c);
    }

    get declarationAccurateBoxClass() {
        return 'papf-checkbox-box' + (this.isDeclarationAccurateChecked ? ' papf-checkbox-box_checked' : '');
    }

    get suggestedReviewers() {
        return this.data?.suggestedReviewers || [];
    }

    get potentialReviewers() {
        return this.suggestedReviewers
            .filter((record) => record.Type__c === 'Suggest')
            .map((record, index) => ({
                key: record.Id || String(index),
                slNo: record.SL_No__c || index + 1,
                fullName: record.Full_Name__c || '',
                email: record.Email__c || '',
                affiliation: record.Affiliation__c || '',
                areaOfExpertise: record.Area_of_expertise__c || '',
                reason: record.Reason__c || ''
            }));
    }

    get hasPotentialReviewers() {
        return this.potentialReviewers.length > 0;
    }

    get wantRestrictedReviewer() {
        return this.normalizeBoolean(this.proposalRecord?.Want_Restricted_Reviewer__c);
    }

    get wantRestrictedReviewerBoxClass() {
        return 'papf-checkbox-box' + (this.wantRestrictedReviewer ? ' papf-checkbox-box_checked' : '');
    }

    get restrictedReviewers() {
        return this.suggestedReviewers
            .filter((record) => record.Type__c === 'Restrict')
            .map((record, index) => ({
                key: record.Id || String(index),
                slNo: record.SL_No__c || index + 1,
                fullName: record.Full_Name__c || '',
                email: record.Email__c || '',
                affiliation: record.Affiliation__c || '',
                areaOfExpertise: record.Area_of_expertise__c || '',
                reason: record.Reason__c || ''
            }));
    }

    get hasRestrictedReviewers() {
        return this.restrictedReviewers.length > 0;
    }

    /* ============================================================
       9. WORK OUTSIDE HOST INSTITUTION (WOHI)
       (WOHI_Collaboration__c where Type__c = 'WOHI', + its child
       WOHI_Collaborator_Visit__c records for the "Application submitted
       for WOHI" table)
       ============================================================ */

    // Files for one WOHI_Collaboration__c - User_Documents__c looks up to it directly (see
    // getProposalDetails' wohiDocuments, already limited to uploaded files with a link).
    documentsForCollaboration(collaborationId) {
        return (this.data?.wohiDocuments || [])
            .filter((doc) => doc.collaborationId === collaborationId)
            .map((doc, index) => ({
                key: doc.id || String(index),
                name: doc.name,
                url: doc.url
            }));
    }

    get wohiApplicants() {
        const collaborations = this.data?.wohiCollaborations || [];
        const visits = this.data?.wohiCollaboratorVisits || [];
        return collaborations
            .filter((record) => record.Type__c === 'WOHI')
            .map((record, index) => ({
                key: record.Id || String(index),
                number: index + 1,
                title: record.Title__c || '',
                firstName: record.FirstName__c || '',
                lastName: record.Last_Name__c || '',
                nationality: record.Nationality__c || '',
                gender: record.Gender__c || '',
                organisation: record.Organisation__c || '',
                department: record.Department__c || '',
                currentPosition: record.Current_Position__c || '',
                cityTown: record.City_Town__c || '',
                district: record.District__c || '',
                state: record.State__c || '',
                postcode: record.Postcode__c || '',
                telephoneNo: record.TelephoneNo__c || '',
                email: record.Email__c || '',
                expertise: record.Expertise__c || '',
                yearsOfExperience: record.Years_of_Experience_as_independent_PI__c || '',
                scientificJustification: record.Scientific_Justification_for_WOHI_lab__c || '',
                expectedOutcome: record.Expected_outcome_from_each_visit__c || '',
                visits: this.mapWohiVisits(visits, record.Id),
                hasVisits: this.mapWohiVisits(visits, record.Id).length > 0,
                documentStatus: record.Wohi_User_Document_Status__c ? 'Submitted' : 'Pending',
                documentStatusClass:
                    'papf-status-badge' +
                    (record.Wohi_User_Document_Status__c
                        ? ' papf-status-badge_uploaded'
                        : ' papf-status-badge_pending'),
                documentStatusIcon: record.Wohi_User_Document_Status__c ? 'utility:success' : 'utility:clock',
                documents: this.documentsForCollaboration(record.Id),
                hasDocuments: this.documentsForCollaboration(record.Id).length > 0
            }));
    }

    mapWohiVisits(visits, collaborationId) {
        return visits
            .filter((visit) => visit.WOHI_Collaboration__c === collaborationId)
            .map((visit, visitIndex) => ({
                key: visit.Id || String(visitIndex),
                aim: visit.Visit_is_related_to_Aim_Objective_No__c || '-',
                duration:
                    visit.Duration_of_visit_in_months__c === null ||
                    visit.Duration_of_visit_in_months__c === undefined
                        ? '-'
                        : String(visit.Duration_of_visit_in_months__c),
                year: visit.Year__c || '-'
            }));
    }

    get hasWohiApplicants() {
        return this.wohiApplicants.length > 0;
    }

    /* ============================================================
       10. COLLABORATION
       (Same WOHI_Collaboration__c object, Type__c = 'Collaborator';
       Scientific_Medical_Academic_colleagues__c is on Proposal__c)
       ============================================================ */

    get proposesToCollaborate() {
        return this.normalizeBoolean(this.proposalRecord?.Scientific_Medical_Academic_colleagues__c);
    }

    get collaborateYesOptionClass() {
        return 'papf-yesno-option' + (this.proposesToCollaborate ? ' papf-yesno-option_selected' : '');
    }

    get collaborateNoOptionClass() {
        return 'papf-yesno-option' + (this.proposesToCollaborate ? '' : ' papf-yesno-option_selected');
    }

    get collaborators() {
        const collaborations = this.data?.wohiCollaborations || [];
        return collaborations
            .filter((record) => record.Type__c === 'Collaborator')
            .map((record, index) => ({
                key: record.Id || String(index),
                number: index + 1,
                title: record.Title__c || '',
                firstName: record.FirstName__c || '',
                lastName: record.Last_Name__c || '',
                nationality: record.Nationality__c || '',
                gender: record.Gender__c || '',
                organisation: record.Organisation__c || '',
                department: record.Department__c || '',
                currentPosition: record.Current_Position__c || '',
                cityTown: record.City_Town__c || '',
                district: record.District__c || '',
                state: record.State__c || '',
                postcode: record.Postcode__c || '',
                telephoneNo: record.TelephoneNo__c || '',
                email: record.Email__c || '',
                expertise: record.Expertise__c || '',
                yearsOfExperience: record.Years_of_Experience_as_independent_PI__c || '',
                extentAndNature: record.Extent_and_nature_of_Collaborator__c || '',
                mtaRequirement: record.Will_the_collaboration_require_MTA__c || '',
                documentStatus: record.Wohi_User_Document_Status__c ? 'Submitted' : 'Pending',
                documentStatusClass:
                    'papf-status-badge' +
                    (record.Wohi_User_Document_Status__c
                        ? ' papf-status-badge_uploaded'
                        : ' papf-status-badge_pending'),
                documentStatusIcon: record.Wohi_User_Document_Status__c ? 'utility:success' : 'utility:clock',
                documents: this.documentsForCollaboration(record.Id),
                hasDocuments: this.documentsForCollaboration(record.Id).length > 0
            }));
    }

    get hasCollaborators() {
        return this.collaborators.length > 0;
    }

    /* ============================================================
       3. RESEARCH INVOLVING HUMAN PARTICIPANTS
       (Includes_Human_Participants_Stem_Cells__c is on Proposal__c;
       everything else is on Human__c, one record per proposal, same
       shape as Animals__c)
       ============================================================ */

    get includesHumanParticipants() {
        return this.proposalRecord?.Includes_Human_Participants_Stem_Cells__c === 'Yes';
    }

    get humanYesOptionClass() {
        return 'papf-yesno-option' + (this.includesHumanParticipants ? ' papf-yesno-option_selected' : '');
    }

    get humanNoOptionClass() {
        return 'papf-yesno-option' + (this.includesHumanParticipants ? '' : ' papf-yesno-option_selected');
    }

    get humanRecord() {
        return this.data?.human || {};
    }

    get requireConsentChecked() {
        return this.normalizeBoolean(this.humanRecord?.Require_Consent_from_study_population__c);
    }

    get requireConsentBoxClass() {
        return 'papf-checkbox-box' + (this.requireConsentChecked ? ' papf-checkbox-box_checked' : '');
    }

    get requireConsentYesOptionClass() {
        return 'papf-radio-option' + (this.requireConsentChecked ? ' papf-radio-option_selected' : '');
    }

    get requireConsentNoOptionClass() {
        return 'papf-radio-option' + (this.requireConsentChecked ? '' : ' papf-radio-option_selected');
    }

    get hospitalFacilityValue() {
        return this.humanRecord?.Project_will_any_hospital_clinical_facil__c || '';
    }

    get hospitalFacilityUseOptionClass() {
        return (
            'papf-radio-option' +
            (this.hospitalFacilityValue === 'I propose to use facilities within a hospital/clinic.'
                ? ' papf-radio-option_selected'
                : '')
        );
    }

    get hospitalFacilityNotRequiredOptionClass() {
        return (
            'papf-radio-option' +
            (this.hospitalFacilityValue === 'My research does not require hospital/clinic facility.'
                ? ' papf-radio-option_selected'
                : '')
        );
    }

    get hospitalFacilityPatientsOptionClass() {
        return (
            'papf-radio-option' +
            (this.hospitalFacilityValue ===
            'My research involves patients being cared for by a hospital/clinical facility.'
                ? ' papf-radio-option_selected'
                : '')
        );
    }

    get hospitalAddress() {
        return this.humanRecord?.Name_Address_of_Hospital_clinical__c || '';
    }

    get showHospitalAddress() {
        return (
            this.hospitalFacilityValue === 'I propose to use facilities within a hospital/clinic.' ||
            this.hospitalFacilityValue ===
                'My research involves patients being cared for by a hospital/clinical facility.'
        );
    }

    // "Attach a letter of participation from clinical collaborator" upload status -
    // sourced from User_Documents__c where Human__c = this Human__c record's Id
    // (already fetched generically alongside every other APA-linked child object).
    get hospitalLetterDocument() {
        const records = this.data?.userDocuments || [];
        return records.find((doc) => doc.Human__c === this.humanRecord?.Id) || null;
    }

    // Files linked to this Human__c record (see getProposalDetails' humanDocuments), already
    // placed by S3 folder: 'letter' = clinical-collaborator letter of participation,
    // 'consent' = informed-consent attachment.
    humanDocumentsByCategory(category) {
        return (this.data?.humanDocuments || [])
            .filter((doc) => doc.category === category)
            .map((doc, index) => ({
                key: doc.id || String(index),
                name: doc.name,
                url: doc.url
            }));
    }

    get humanLetterDocuments() {
        return this.humanDocumentsByCategory('letter');
    }

    get hasHumanLetterDocuments() {
        return this.humanLetterDocuments.length > 0;
    }

    get humanConsentDocuments() {
        return this.humanDocumentsByCategory('consent');
    }

    get hasHumanConsentDocuments() {
        return this.humanConsentDocuments.length > 0;
    }

    get hospitalLetterUploadStatus() {
        if (this.hasHumanLetterDocuments) {
            return 'Uploaded';
        }
        return this.hospitalLetterDocument?.Upload_Status__c || 'Pending';
    }

    get isHospitalLetterUploaded() {
        return (
            this.hospitalLetterUploadStatus === 'Uploaded' ||
            this.hospitalLetterUploadStatus === 'Submitted/Uploaded'
        );
    }

    get hospitalLetterStatusIcon() {
        return this.isHospitalLetterUploaded ? 'utility:success' : 'utility:clock';
    }

    get hospitalLetterStatusClass() {
        return (
            'papf-status-badge' +
            (this.isHospitalLetterUploaded ? ' papf-status-badge_uploaded' : ' papf-status-badge_pending')
        );
    }

    get projectInvolvesValues() {
        return this.splitMultiselect(this.humanRecord?.My_Project_Involve__c);
    }

    get isInvolvesHumanParticipantsChecked() {
        return this.projectInvolvesValues.includes('Human Participants');
    }

    get involvesHumanParticipantsBoxClass() {
        return this.checkboxClassFor(this.projectInvolvesValues, 'Human Participants');
    }

    get isInvolvesStemCellsChecked() {
        return this.projectInvolvesValues.includes('Experiments with human stem cells');
    }

    get involvesStemCellsBoxClass() {
        return this.checkboxClassFor(this.projectInvolvesValues, 'Experiments with human stem cells');
    }

    get isInvolvesPersonalDataChecked() {
        return this.projectInvolvesValues.includes('Personal data');
    }

    get involvesPersonalDataBoxClass() {
        return this.checkboxClassFor(this.projectInvolvesValues, 'Personal data');
    }

    get isInvolvesBiologicalSamplesChecked() {
        return this.projectInvolvesValues.includes('Biological Samples');
    }

    get involvesBiologicalSamplesBoxClass() {
        return this.checkboxClassFor(this.projectInvolvesValues, 'Biological Samples');
    }

    // -- Human participants sub-block --

    get sampleSizeCalculation() {
        return this.humanRecord?.Size_cal_including_statiscal_analysis__c || '';
    }

    get studyPopulationCharacteristics() {
        return this.humanRecord?.Study_Population_Characteristics__c || '';
    }

    get humanEligibilityCriteria() {
        return this.humanRecord?.Eligibility_criteria__c || '';
    }

    get humanAgeMaximumMinimum() {
        return this.humanRecord?.Age_Maximum_minimum__c || '';
    }

    get recruitmentAndRetentionPlan() {
        return this.humanRecord?.Retention_and_retention_plan__c || '';
    }

    get humanTimeline() {
        return this.humanRecord?.Timeline__c || '';
    }

    get humanRegulatoryBodies() {
        return this.humanRecord?.HumaRegulatory_bodies_for_ethical_review__c || '';
    }

    // -- Experiments with human stem cells sub-block --

    get stemCellExperimentNature() {
        return this.humanRecord?.Details_of_stem_Cell_experiment_nature__c || '';
    }

    get stemCellRegulatoryBodies() {
        return this.humanRecord?.regulatory_bodies_human_stem_cells__c || '';
    }

    get stemCellBiohazardsSafety() {
        return this.humanRecord?.Biohazards_SafetyPrecaution__c || '';
    }

    get stemCellWasteProtocol() {
        return this.humanRecord?.What_is_Protocol_for_waste_management__c || '';
    }

    // -- Personal data sub-block --

    get personalDataSource() {
        return this.humanRecord?.Details_of_source_of_personal_data__c || '';
    }

    get personalDataPrivacyMeasures() {
        return this.humanRecord?.Measure_taken_to_protect_privacy_rights__c || '';
    }

    get personalDataRegulatoryBodies() {
        return this.humanRecord?.PersonalRegulatorybodiesethicalreview__c || '';
    }

    // -- Biological samples sub-block --

    get bioSamplesNature() {
        return this.humanRecord?.Biological_samples_nature_of_experimnt__c || '';
    }

    get bioSamplesBiohazards() {
        return this.humanRecord?.biohazards_are_associated_Biological__c || '';
    }

    get bioSamplesRegulatoryBodies() {
        return this.humanRecord?.Regulatory_Bodies_Responsible__c || '';
    }

    /* ============================================================
       12A. PERSONAL SUPPORT (Applicant_Proposal_Association__c)
       Only the Yes/Yes combination of the two salary-support
       questions is built for now, per the shared screenshot - the
       other combinations are deferred.
       ============================================================ */

    formatCurrency(value) {
        const num = Number(value) || 0;
        return '₹' + num.toLocaleString('en-IN', { maximumFractionDigits: 0 });
    }

    get salarySupportFromHost() {
        return this.apaRecord?.Salary_Support_from_Host__c || '';
    }

    get salarySupportFromHostYesClass() {
        return 'papf-radio-option' + (this.salarySupportFromHost === 'Yes' ? ' papf-radio-option_selected' : '');
    }

    get salarySupportFromHostNoClass() {
        return 'papf-radio-option' + (this.salarySupportFromHost === 'No' ? ' papf-radio-option_selected' : '');
    }

    get salarySupportDuringWohi() {
        return this.apaRecord?.Salary_support_during_WOHI__c || '';
    }

    get salarySupportDuringWohiYesClass() {
        return 'papf-radio-option' + (this.salarySupportDuringWohi === 'Yes' ? ' papf-radio-option_selected' : '');
    }

    get salarySupportDuringWohiNoClass() {
        return 'papf-radio-option' + (this.salarySupportDuringWohi === 'No' ? ' papf-radio-option_selected' : '');
    }

    get showSalarySupportDuringWohiQuestion() {
        return this.salarySupportFromHost === 'Yes';
    }

    get showPersonalSupportBreakdown() {
        return this.salarySupportFromHost === 'Yes' && this.salarySupportDuringWohi === 'Yes';
    }

    get showHostOnlyBreakdown() {
        return this.salarySupportFromHost === 'Yes' && this.salarySupportDuringWohi === 'No';
    }

    get showIaSalaryBreakdown() {
        return this.salarySupportFromHost === 'No';
    }

    get showOtherSalaryCombinationNote() {
        return !this.showPersonalSupportBreakdown && !this.showHostOnlyBreakdown && !this.showIaSalaryBreakdown;
    }

    get hostSalaryYear1() {
        return this.apaRecord?.Host_Salary_Year1__c || 0;
    }

    get hostSalaryYear2() {
        return this.apaRecord?.Host_Salary_Year2__c || 0;
    }

    get hostSalaryYear3() {
        return this.apaRecord?.Host_Salary_Year3__c || 0;
    }

    get hostSalaryYear4() {
        return this.apaRecord?.Host_Salary_Year4__c || 0;
    }

    get hostSalaryYear5() {
        return this.apaRecord?.Host_Salary_Year5__c || 0;
    }

    get hostSalaryYear1Display() {
        return this.formatCurrency(this.hostSalaryYear1);
    }

    get hostSalaryYear2Display() {
        return this.formatCurrency(this.hostSalaryYear2);
    }

    get hostSalaryYear3Display() {
        return this.formatCurrency(this.hostSalaryYear3);
    }

    get hostSalaryYear4Display() {
        return this.formatCurrency(this.hostSalaryYear4);
    }

    get hostSalaryYear5Display() {
        return this.formatCurrency(this.hostSalaryYear5);
    }

    get hostSalaryTotalDisplay() {
        return this.formatCurrency(this.apaRecord?.Total_Host_Salary_Formula__c);
    }

    get personalSalaryYear1() {
        return this.apaRecord?.Personal_Salary_Year1__c || 0;
    }

    get personalSalaryYear2() {
        return this.apaRecord?.Personal_Salary_Year2__c || 0;
    }

    get personalSalaryYear3() {
        return this.apaRecord?.Personal_Salary_Year3__c || 0;
    }

    get personalSalaryYear4() {
        return this.apaRecord?.Personal_Salary_Year4__c || 0;
    }

    get personalSalaryYear5() {
        return this.apaRecord?.Personal_Salary_Year5__c || 0;
    }

    get personalSalaryYear1Display() {
        return this.formatCurrency(this.personalSalaryYear1);
    }

    get personalSalaryYear2Display() {
        return this.formatCurrency(this.personalSalaryYear2);
    }

    get personalSalaryYear3Display() {
        return this.formatCurrency(this.personalSalaryYear3);
    }

    get personalSalaryYear4Display() {
        return this.formatCurrency(this.personalSalaryYear4);
    }

    get personalSalaryYear5Display() {
        return this.formatCurrency(this.personalSalaryYear5);
    }

    get personalSalaryTotalDisplay() {
        return this.formatCurrency(this.apaRecord?.Total_Personal_Salary_Formula__c);
    }

    // "Personal Support Total" row - reverted back to a client-side sum (the
    // Personal_Support_Tab_Cost_* rollup fields were giving wrong results) -
    // Host + Personal when both salary-support questions are Yes, Host alone
    // when the WOHI question is No.

    get personalSupportTotalYear1Display() {
        const personal = this.showPersonalSupportBreakdown ? this.personalSalaryYear1 : 0;
        return this.formatCurrency(this.hostSalaryYear1 + personal);
    }

    get personalSupportTotalYear2Display() {
        const personal = this.showPersonalSupportBreakdown ? this.personalSalaryYear2 : 0;
        return this.formatCurrency(this.hostSalaryYear2 + personal);
    }

    get personalSupportTotalYear3Display() {
        const personal = this.showPersonalSupportBreakdown ? this.personalSalaryYear3 : 0;
        return this.formatCurrency(this.hostSalaryYear3 + personal);
    }

    get personalSupportTotalYear4Display() {
        const personal = this.showPersonalSupportBreakdown ? this.personalSalaryYear4 : 0;
        return this.formatCurrency(this.hostSalaryYear4 + personal);
    }

    get personalSupportTotalYear5Display() {
        const personal = this.showPersonalSupportBreakdown ? this.personalSalaryYear5 : 0;
        return this.formatCurrency(this.hostSalaryYear5 + personal);
    }

    get personalSupportGrandTotalDisplay() {
        const hostTotal = Number(this.apaRecord?.Total_Host_Salary_Formula__c) || 0;
        const personalTotal = this.showPersonalSupportBreakdown
            ? Number(this.apaRecord?.Total_Personal_Salary_Formula__c) || 0
            : 0;
        return this.formatCurrency(hostTotal + personalTotal);
    }

    // -- IA salary breakdown (shown instead, when Salary_Support_from_Host__c = 'No') --

    get iaSalaryYear1Display() {
        return this.formatCurrency(this.apaRecord?.IA_Salary_Year1__c);
    }

    get iaSalaryYear2Display() {
        return this.formatCurrency(this.apaRecord?.IA_Salary_Year2__c);
    }

    get iaSalaryYear3Display() {
        return this.formatCurrency(this.apaRecord?.IA_Salary_Year3__c);
    }

    get iaSalaryYear4Display() {
        return this.formatCurrency(this.apaRecord?.IA_Salary_Year4__c);
    }

    get iaSalaryYear5Display() {
        return this.formatCurrency(this.apaRecord?.IA_Salary_Year5__c);
    }

    get iaSalaryTotalDisplay() {
        return this.formatCurrency(this.apaRecord?.Total_IA_Salary_Formula__c);
    }

    /* ============================================================
       12B. STAFF (Staff_Budget__c, RecordType = 'Staff')
       Staff_Budget__c is shared across several Budget tabs via
       RecordType (Staff / Materials_and_Consumables / Access_Charges),
       so it's fetched once generically and filtered here by RecordType.
       ============================================================ */

    get staffRows() {
        const records = this.data?.staffBudgets || [];
        return records
            .filter((record) => record.RecordTypeDeveloperName === 'Staff')
            .map((record, index) => ({
                key: record.Id || String(index),
                jobTitle:
                    record.Job_Title__c === 'Other'
                        ? record.Other_Job_title__c || 'Other'
                        : record.Job_Title__c || '',
                year1: Number(record.Year_1__c) || 0,
                year2: Number(record.Year_2__c) || 0,
                year3: Number(record.Year_3__c) || 0,
                year4: Number(record.Year_4__c) || 0,
                year5: Number(record.Year_5__c) || 0,
                year1Display: this.formatCurrency(record.Year_1__c),
                year2Display: this.formatCurrency(record.Year_2__c),
                year3Display: this.formatCurrency(record.Year_3__c),
                year4Display: this.formatCurrency(record.Year_4__c),
                year5Display: this.formatCurrency(record.Year_5__c),
                totalDisplay: this.formatCurrency(record.Total_Salary_formula__c)
            }));
    }

    get hasStaffRows() {
        return this.staffRows.length > 0;
    }

    // "Total" row - fetched directly from the Applicant_Proposal_Association__c
    // rollup fields (Staff_Year1__c...Staff_Total__c) rather than summed
    // client-side, so it always matches whatever Salesforce itself rolled up.

    get staffTotalYear1Display() {
        return this.formatCurrency(this.apaRecord?.Staff_Year1__c);
    }

    get staffTotalYear2Display() {
        return this.formatCurrency(this.apaRecord?.Staff_Year2__c);
    }

    get staffTotalYear3Display() {
        return this.formatCurrency(this.apaRecord?.Staff_Year3__c);
    }

    get staffTotalYear4Display() {
        return this.formatCurrency(this.apaRecord?.Staff_Year4__c);
    }

    get staffTotalYear5Display() {
        return this.formatCurrency(this.apaRecord?.Staff_Year5__c);
    }

    get staffGrandTotalDisplay() {
        return this.formatCurrency(this.apaRecord?.Staff_Total__c);
    }

    get staffSalaryJustification() {
        return this.apaRecord?.Staff_and_Salary_Justification__c || '';
    }

    /* ============================================================
       12C. MATERIALS & CONSUMABLES (Staff_Budget__c,
       RecordType = 'Materials_and_Consumables')
       ============================================================ */

    get materialsConsumablesRows() {
        const records = this.data?.staffBudgets || [];
        return records
            .filter((record) => record.RecordTypeDeveloperName === 'Materials_and_Consumables')
            .map((record, index) => ({
                key: record.Id || String(index),
                title: record.Material_Name__c || '',
                year1Display: this.formatCurrency(record.Year_1__c),
                year2Display: this.formatCurrency(record.Year_2__c),
                year3Display: this.formatCurrency(record.Year_3__c),
                year4Display: this.formatCurrency(record.Year_4__c),
                year5Display: this.formatCurrency(record.Year_5__c),
                totalDisplay: this.formatCurrency(record.Total_Salary_formula__c)
            }));
    }

    get hasMaterialsConsumablesRows() {
        return this.materialsConsumablesRows.length > 0;
    }

    // "Total" row - fetched directly from the Applicant_Proposal_Association__c
    // rollup fields rather than summed client-side.

    get materialsConsumablesTotalYear1Display() {
        return this.formatCurrency(this.apaRecord?.Materials_and_Consumables_Year1__c);
    }

    get materialsConsumablesTotalYear2Display() {
        return this.formatCurrency(this.apaRecord?.Materials_and_Consumables_Year2__c);
    }

    get materialsConsumablesTotalYear3Display() {
        return this.formatCurrency(this.apaRecord?.Materials_and_Consumables_Year3__c);
    }

    get materialsConsumablesTotalYear4Display() {
        return this.formatCurrency(this.apaRecord?.Materials_and_Consumables_Year4__c);
    }

    get materialsConsumablesTotalYear5Display() {
        return this.formatCurrency(this.apaRecord?.Materials_and_Consumables_Year5__c);
    }

    get materialsConsumablesGrandTotalDisplay() {
        return this.formatCurrency(this.apaRecord?.Materials_and_Consumables_Total__c);
    }

    get materialsConsumablesJustification() {
        return this.apaRecord?.Material_Justification__c || '';
    }

    /* ============================================================
       12D. EQUIPMENT (Equipment__c - a separate object from
       Staff_Budget__c). Total Cost per row is calculated manually
       here for now (Cost per Item x Quantity + Maintenance Charges -
       Contribution from other sources) rather than trusting a stored
       field - per instruction, may change later.
       ============================================================ */

    get equipmentRows() {
        const records = this.data?.equipmentItems || [];
        return records.map((record, index) => {
            const costPerItem = Number(record.Cost_per_Item__c) || 0;
            const quantity = Number(record.Quantity__c) || 0;
            const maintainCharges = Number(record.Maintain_Charges__c) || 0;
            const contribution = Number(record.Contribution_from_other_sources__c) || 0;
            const total = costPerItem * quantity + maintainCharges - contribution;
            return {
                key: record.Id || String(index),
                title: record.Equipment_Name__c || '',
                yearRequired: record.Year_Required__c || '',
                quantity: record.Quantity__c || '',
                costPerItemDisplay: this.formatCurrency(costPerItem),
                maintainChargesDisplay: this.formatCurrency(maintainCharges),
                contributionDisplay: this.formatCurrency(contribution),
                total,
                totalDisplay: this.formatCurrency(total)
            };
        });
    }

    get hasEquipmentRows() {
        return this.equipmentRows.length > 0;
    }

    get equipmentGrandTotalDisplay() {
        return this.formatCurrency(this.equipmentRows.reduce((sum, row) => sum + row.total, 0));
    }

    get equipmentJustification() {
        return this.apaRecord?.Equipment_Justification__c || '';
    }

    /* ============================================================
       12E. ACCESS CHARGES (Staff_Budget__c,
       RecordType = 'Access_Charges')
       ============================================================ */

    get accessChargesRows() {
        const records = this.data?.staffBudgets || [];
        return records
            .filter((record) => record.RecordTypeDeveloperName === 'Access_Charges')
            .map((record, index) => ({
                key: record.Id || String(index),
                title: record.Material_Name__c || '',
                year1Display: this.formatCurrency(record.Year_1__c),
                year2Display: this.formatCurrency(record.Year_2__c),
                year3Display: this.formatCurrency(record.Year_3__c),
                year4Display: this.formatCurrency(record.Year_4__c),
                year5Display: this.formatCurrency(record.Year_5__c),
                totalDisplay: this.formatCurrency(record.Total_Salary_formula__c)
            }));
    }

    get hasAccessChargesRows() {
        return this.accessChargesRows.length > 0;
    }

    // "Total" row - fetched directly from the Applicant_Proposal_Association__c
    // rollup fields, per instruction.

    get accessChargesTotalYear1Display() {
        return this.formatCurrency(this.apaRecord?.Access_Charges_Year1__c);
    }

    get accessChargesTotalYear2Display() {
        return this.formatCurrency(this.apaRecord?.Access_Charges_Year2__c);
    }

    get accessChargesTotalYear3Display() {
        return this.formatCurrency(this.apaRecord?.Access_Charges_Year3__c);
    }

    get accessChargesTotalYear4Display() {
        return this.formatCurrency(this.apaRecord?.Access_Charges_Year4__c);
    }

    get accessChargesTotalYear5Display() {
        return this.formatCurrency(this.apaRecord?.Access_Charges_Year5__c);
    }

    get accessChargesGrandTotalDisplay() {
        return this.formatCurrency(this.apaRecord?.Access_Charges_Total__c);
    }

    get accessChargesJustification() {
        return this.apaRecord?.Access_Charges_Justification__c || '';
    }

    /* ============================================================
       12I. MISCELLANEOUS (Miscellaneous__c - a separate object,
       looked up to the APA like Equipment__c)
       ============================================================ */

    get miscellaneousRows() {
        const records = this.data?.miscellaneousItems || [];
        return records.map((record, index) => ({
            key: record.Id || String(index),
            title: record.Cost_Description__c || '',
            year1Display: this.formatCurrency(record.Year_1_Cost__c),
            year2Display: this.formatCurrency(record.Year_2_Cost__c),
            year3Display: this.formatCurrency(record.Year_3_Cost__c),
            year4Display: this.formatCurrency(record.Year_4_Cost__c),
            year5Display: this.formatCurrency(record.Year_5_Cost__c),
            totalDisplay: this.formatCurrency(record.Total_Cost_Formula__c)
        }));
    }

    get hasMiscellaneousRows() {
        return this.miscellaneousRows.length > 0;
    }

    // "Total" row - fetched directly from the Applicant_Proposal_Association__c
    // rollup fields, per instruction.

    get miscellaneousTotalYear1Display() {
        return this.formatCurrency(this.apaRecord?.Miscellaneous_Year1__c);
    }

    get miscellaneousTotalYear2Display() {
        return this.formatCurrency(this.apaRecord?.Miscellaneous_Year2__c);
    }

    get miscellaneousTotalYear3Display() {
        return this.formatCurrency(this.apaRecord?.Miscellaneous_Year3__c);
    }

    get miscellaneousTotalYear4Display() {
        return this.formatCurrency(this.apaRecord?.Miscellaneous_Year4__c);
    }

    get miscellaneousTotalYear5Display() {
        return this.formatCurrency(this.apaRecord?.Miscellaneous_Year5__c);
    }

    get miscellaneousGrandTotalDisplay() {
        return this.formatCurrency(this.apaRecord?.Miscellaneous_Total__c);
    }

    get miscellaneousJustification() {
        return this.apaRecord?.Miscellaneous_Justification__c || '';
    }

    /* ============================================================
       12J. FLEXIBLE FUNDING (Applicant_Proposal_Association__c)
       Automatically allocated per the scheme guidelines - no child
       object, no user input. Grand Total = Subtotal (the FA_for_YearX
       fields) + (Subtotal x FA_Percent), computed dynamically from
       the live FA_Percent__c value so it keeps working if that
       percentage ever changes.
       ============================================================ */

    get faYear1() {
        return Number(this.apaRecord?.FA_for_Year1__c) || 0;
    }

    get faYear2() {
        return Number(this.apaRecord?.FA_for_Year2__c) || 0;
    }

    get faYear3() {
        return Number(this.apaRecord?.FA_for_Year3__c) || 0;
    }

    get faYear4() {
        return Number(this.apaRecord?.FA_for_Year4__c) || 0;
    }

    get faYear5() {
        return Number(this.apaRecord?.FA_for_Year5__c) || 0;
    }

    get faYear1Display() {
        return this.formatCurrency(this.faYear1);
    }

    get faYear2Display() {
        return this.formatCurrency(this.faYear2);
    }

    get faYear3Display() {
        return this.formatCurrency(this.faYear3);
    }

    get faYear4Display() {
        return this.formatCurrency(this.faYear4);
    }

    get faYear5Display() {
        return this.formatCurrency(this.faYear5);
    }

    get faTotalDisplay() {
        return this.formatCurrency(this.apaRecord?.Total_FA_cost__c);
    }

    get faPercent() {
        return Number(this.apaRecord?.FA_Percent__c) || 0;
    }

    get faPercentMultiplier() {
        return 1 + this.faPercent / 100;
    }

    get faGrandTotalLabel() {
        return `Grand Total (subtotal 1+${this.faPercent}%)`;
    }

    get faGrandTotalYear1Display() {
        return this.formatCurrency(this.faYear1 * this.faPercentMultiplier);
    }

    get faGrandTotalYear2Display() {
        return this.formatCurrency(this.faYear2 * this.faPercentMultiplier);
    }

    get faGrandTotalYear3Display() {
        return this.formatCurrency(this.faYear3 * this.faPercentMultiplier);
    }

    get faGrandTotalYear4Display() {
        return this.formatCurrency(this.faYear4 * this.faPercentMultiplier);
    }

    get faGrandTotalYear5Display() {
        return this.formatCurrency(this.faYear5 * this.faPercentMultiplier);
    }

    get faGrandTotalCostDisplay() {
        const total = Number(this.apaRecord?.Total_FA_cost__c) || 0;
        return this.formatCurrency(total * this.faPercentMultiplier);
    }

    // "Grand Total" row shows the overall A-to-J budget rollup across every
    // Budget tab (Applicant_Proposal_Association__c.A_to_J_Cost_Year1__c...Total__c),
    // not just the Flexible Funding subtotal.

    get aToJCostYear1Display() {
        return this.formatCurrency(this.apaRecord?.A_to_J_Cost_Year1__c);
    }

    get aToJCostYear2Display() {
        return this.formatCurrency(this.apaRecord?.A_to_J_Cost_Year2__c);
    }

    get aToJCostYear3Display() {
        return this.formatCurrency(this.apaRecord?.A_to_J_Cost_Year3__c);
    }

    get aToJCostYear4Display() {
        return this.formatCurrency(this.apaRecord?.A_to_J_Cost_Year4__c);
    }

    get aToJCostYear5Display() {
        return this.formatCurrency(this.apaRecord?.A_to_J_Cost_Year5__c);
    }

    get aToJCostTotalDisplay() {
        return this.formatCurrency(this.apaRecord?.A_to_J_Cost_Total__c);
    }

    /* ============================================================
       12F. ANIMALS - Animal Purchase sub-tab
       (Animal_Species__c, child of Animals__c, already fetched
       generically for Section 4 - reused here for the Budget tab.
       Total Cost per row and the grand total are both calculated
       manually, same as Equipment.)
       ============================================================ */

    get animalPurchaseRows() {
        const records = this.data?.animalSpecies || [];
        return records.map((record, index) => {
            const total = Number(record.Purchase_Total_cost__c) || 0;
            return {
                key: record.Id || String(index),
                species: record.Animal_Species__c || '',
                strain: record.Animal_Strain__c || '',
                costPerAnimalDisplay: this.formatCurrency(record.Purchase_cost_per_animal__c),
                yearRequired: record.Purchase_Year_Required__c || '',
                sourceOfSupply: record.Source_of_supply__c || '',
                totalNumber: record.Purchase_total_number__c || '',
                total,
                totalDisplay: this.formatCurrency(total)
            };
        });
    }

    get hasAnimalPurchaseRows() {
        return this.animalPurchaseRows.length > 0;
    }

    get animalPurchaseGrandTotalDisplay() {
        return this.formatCurrency(this.animalPurchaseRows.reduce((sum, row) => sum + row.total, 0));
    }

    get animalPurchaseJustification() {
        return this.animalsRecord?.Animal_Purchase_Cost_Justification__c || '';
    }

    /* ============================================================
       12F. ANIMALS - Associated Costs sub-tab
       (Animal_Associated_costs__c, another child of Animals__c,
       distinct from Animal_Species__c)
       ============================================================ */

    get associatedCostRows() {
        const records = this.data?.animalAssociatedCosts || [];
        return records.map((record, index) => ({
            key: record.Id || String(index),
            title: record.Cost_Description__c || '',
            year1Display: this.formatCurrency(record.Year_1_Cost__c),
            year2Display: this.formatCurrency(record.Year_2_Cost__c),
            year3Display: this.formatCurrency(record.Year_3_Cost__c),
            year4Display: this.formatCurrency(record.Year_4_Cost__c),
            year5Display: this.formatCurrency(record.Year_5_Cost__c),
            totalDisplay: this.formatCurrency(record.Total_Cost_Formula__c)
        }));
    }

    get hasAssociatedCostRows() {
        return this.associatedCostRows.length > 0;
    }

    // "Total" row - fetched directly from the Applicant_Proposal_Association__c
    // rollup fields rather than summed client-side.

    get associatedCostsTotalYear1Display() {
        return this.formatCurrency(this.apaRecord?.Animal_Associated_cost_Year1__c);
    }

    get associatedCostsTotalYear2Display() {
        return this.formatCurrency(this.apaRecord?.Animal_Associated_cost_Year2__c);
    }

    get associatedCostsTotalYear3Display() {
        return this.formatCurrency(this.apaRecord?.Animal_Associated_cost_Year3__c);
    }

    get associatedCostsTotalYear4Display() {
        return this.formatCurrency(this.apaRecord?.Animal_Associated_cost_Year4__c);
    }

    get associatedCostsTotalYear5Display() {
        return this.formatCurrency(this.apaRecord?.Animal_Associated_cost_Year5__c);
    }

    get associatedCostsGrandTotalDisplay() {
        return this.formatCurrency(this.apaRecord?.Animal_Associated_Cost_Total__c);
    }

    get associatedCostsJustification() {
        return this.animalsRecord?.Animal_Associated_Cost_Justification__c || '';
    }

    /* ============================================================
       12F. ANIMALS - Animal Maintenance sub-tab
       (same Animal_Species__c records as Animal Purchase, just the
       Maintenance_* fields; Species/Strain are read-only here too
       since they're set on the Purchase tab)
       ============================================================ */

    get animalMaintenanceRows() {
        const records = this.data?.animalSpecies || [];
        return records.map((record, index) => {
            const total = Number(record.Maintenance_Total_cost__c) || 0;
            return {
                key: record.Id || String(index),
                species: record.Animal_Species__c || '',
                strain: record.Animal_Strain__c || '',
                costPerAnimalDisplay: this.formatCurrency(record.Maintenance_cost_per_animal__c),
                yearRequired: record.Maintenance_Year_Required__c || '',
                institutePlace: record.Institute_Place_for_Maintenance__c || '',
                totalNumber: record.Maintenance_total_number__c || '',
                total,
                totalDisplay: this.formatCurrency(total)
            };
        });
    }

    get hasAnimalMaintenanceRows() {
        return this.animalMaintenanceRows.length > 0;
    }

    get animalMaintenanceGrandTotalDisplay() {
        return this.formatCurrency(this.animalMaintenanceRows.reduce((sum, row) => sum + row.total, 0));
    }

    get animalMaintenanceJustification() {
        return this.animalsRecord?.Animal_Maintenance_Cost_Justification__c || '';
    }

    /* ============================================================
       12F. ANIMALS - Experimental Procedures sub-tab
       (same Animal_Species__c records again, Exp_Procedure_* fields)
       ============================================================ */

    get experimentalProcedureRows() {
        const records = this.data?.animalSpecies || [];
        return records.map((record, index) => {
            const total = Number(record.Exp_Procedure_Total_cost__c) || 0;
            return {
                key: record.Id || String(index),
                species: record.Animal_Species__c || '',
                strain: record.Animal_Strain__c || '',
                costPerAnimalDisplay: this.formatCurrency(record.Exp_Procedure_cost_per_animal__c),
                yearRequired: record.Exp_Procedure_Year_Required__c || '',
                institutePlace: record.Institute_Place_for_Exp_Procedure__c || '',
                totalNumber: record.Exp_Procedure_total_number__c || '',
                total,
                totalDisplay: this.formatCurrency(total)
            };
        });
    }

    get hasExperimentalProcedureRows() {
        return this.experimentalProcedureRows.length > 0;
    }

    get experimentalProcedureGrandTotalDisplay() {
        return this.formatCurrency(this.experimentalProcedureRows.reduce((sum, row) => sum + row.total, 0));
    }

    get experimentalProcedureJustification() {
        return this.animalsRecord?.Animal_Exp_Procedure_Cost_Justification__c || '';
    }

    /* ============================================================
       12G. TRAVEL TO MEETINGS (Applicant_Proposal_Association__c) -
       single entry, no child object, no total row.
       ============================================================ */

    get travelToMeetingsYear() {
        return this.apaRecord?.Travel_to_Meetings_Year__c || '';
    }

    get travelToMeetingsCostDisplay() {
        return this.formatCurrency(this.apaRecord?.Travel_to_Meetings_Cost__c);
    }

    get travelToMeetingsJustification() {
        return this.apaRecord?.Travel_to_Meetings_Justification__c || '';
    }

    /* ============================================================
       12H. WOHI ALLOWANCE (WOHI_Allowance__c - a separate object,
       looked up to the APA like Equipment__c/Miscellaneous__c; one
       record per Allowance_Type__c, shown in a fixed row order).
       Total row calculated manually, per instruction.
       ============================================================ */

    get wohiAllowanceRows() {
        const records = this.data?.wohiAllowances || [];
        const types = [
            { type: 'Sustenance', hint: 'Max ₹3,50,000/month' },
            { type: 'Travel', hint: 'Max ₹4,00,000' },
            { type: 'Domestic', hint: 'Max ₹50,000/month' },
            { type: 'Other', hint: '' }
        ];
        return types.map((entry) => {
            const record = records.find((rec) => rec.Allowance_Type__c === entry.type) || {};
            const year1 = Number(record.Year1_Cost__c) || 0;
            const year2 = Number(record.Year2_Cost__c) || 0;
            const year3 = Number(record.Year3_Cost__c) || 0;
            const year4 = Number(record.Year4_Cost__c) || 0;
            const year5 = Number(record.Year5_Cost__c) || 0;
            const total = Number(record.Total_Cost_Formula__c) || 0;
            return {
                key: entry.type,
                type: entry.type,
                hint: entry.hint,
                year1,
                year2,
                year3,
                year4,
                year5,
                total,
                year1Display: this.formatCurrency(year1),
                year2Display: this.formatCurrency(year2),
                year3Display: this.formatCurrency(year3),
                year4Display: this.formatCurrency(year4),
                year5Display: this.formatCurrency(year5),
                totalDisplay: this.formatCurrency(total)
            };
        });
    }

    get wohiAllowanceTotalYear1Display() {
        return this.formatCurrency(this.wohiAllowanceRows.reduce((sum, row) => sum + row.year1, 0));
    }

    get wohiAllowanceTotalYear2Display() {
        return this.formatCurrency(this.wohiAllowanceRows.reduce((sum, row) => sum + row.year2, 0));
    }

    get wohiAllowanceTotalYear3Display() {
        return this.formatCurrency(this.wohiAllowanceRows.reduce((sum, row) => sum + row.year3, 0));
    }

    get wohiAllowanceTotalYear4Display() {
        return this.formatCurrency(this.wohiAllowanceRows.reduce((sum, row) => sum + row.year4, 0));
    }

    get wohiAllowanceTotalYear5Display() {
        return this.formatCurrency(this.wohiAllowanceRows.reduce((sum, row) => sum + row.year5, 0));
    }

    get wohiAllowanceGrandTotalDisplay() {
        return this.formatCurrency(this.wohiAllowanceRows.reduce((sum, row) => sum + row.total, 0));
    }
}