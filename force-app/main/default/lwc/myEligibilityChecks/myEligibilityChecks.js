import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getMyEligibilityChecks from '@salesforce/apex/MyEligibilityChecksController.getMyEligibilityChecks';
import markEligibleForFull from '@salesforce/apex/MyEligibilityChecksController.markEligibleForFull';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const COLUMN_DEFS = [
    { key: 'proposalIdDisplay', label: 'Proposal Id', sortable: true },
    { key: 'applicantName', label: 'Applicant', sortable: true },
    { key: 'yearlyScheme', label: 'Yearly Scheme', sortable: true },
    { key: 'schemeItemName', label: 'Scheme Item', sortable: true },
    { key: 'proposalStatus', label: 'Proposal Status', sortable: true },
    { key: 'applicationStage', label: 'Application Stage', sortable: true },
    { key: 'status', label: 'Status', sortable: true },
    { key: 'eligibility', label: 'My Verdict', sortable: true },
    { key: 'assignedDateLabel', label: 'Assigned On', sortable: true },
    // { key: 'dueDateLabel', label: 'Due Date', sortable: false },
    { key: 'action', label: 'Action', sortable: false }
];

const BADGE_CLASS_BY_VALUE = {
    Approved: 'slds-badge slds-badge_success',
    Rejected: 'slds-badge slds-badge_error',
    Prelims: 'slds-badge slds-badge_purple',
    'In Review': 'slds-badge slds-badge_warning',
    Submitted: 'slds-badge slds-badge_success',
    Draft: 'slds-badge slds-badge_neutral',
    Eligible: 'slds-badge slds-badge_success',
    'Not Eligible': 'slds-badge slds-badge_error',
    Full: 'slds-badge slds-badge_lightblue'
};

export default class MyEligibilityChecks extends NavigationMixin(LightningElement) {
    data = [];
    isLoading = true;
    error;
    searchKey = '';
    selectedSchemeItem = '';
    selectedApplicationStage = '';
    sortBy;
    sortDirection;
    pageNumber = 1;
    pageSize = 10;
    isSchemeItemDropdownOpen = false;
    isApplicationStageDropdownOpen = false;
    activeListTab = 'assigned';
    selectedProposalIds = new Set();
    isMarkingEligible = false;
    wiredResult;
    showGrantTeamResponseModal = false;
    selectedProposalIdForGrantTeamResponse;
    showCheckEligibilityModal = false;
    selectedProposalIdForCheckEligibility;
    showReviewerResponseModal = false;
    selectedProposalIdForReviewerResponse;
    showPeerEvaluationModal = false;
    selectedProposalIdForPeerEvaluation;
    showReviewerMappingModal = false;
    selectedProposalIdForReviewerMapping;
    reviewerMappingApplicationStage;
    showProposalReviewerModal = false;
    proposalReviewerInitialStatusFilter = 'PRELIM';

    connectedCallback() {
        this._handleWindowClick = () => {
            this.isSchemeItemDropdownOpen = false;
            this.isApplicationStageDropdownOpen = false;
        };
        window.addEventListener('click', this._handleWindowClick);
    }

    disconnectedCallback() {
        window.removeEventListener('click', this._handleWindowClick);
    }

    @wire(getMyEligibilityChecks)
    wiredResponses(result) {
        this.wiredResult = result;
        const { error, data } = result;
        this.isLoading = false;
        if (data) {
            this.data = data.map((row) => {
                const assigned = this.formatDateParts(row.createdDate);
                return {
                    ...row,
                    proposalSubLabel: 'Proposal',
                    yearlySchemeSubLabel: 'Yearly Scheme',
                    schemeItemNameLabel: row.schemeItemName || '—',
                    applicantNameLabel: row.applicantName || '—',
                    assignedDateLabel: assigned.date,
                    assignedTimeLabel: assigned.time,
                    dueDateLabel: row.dueDate || '—',
                    dueDateSubLabel: '',
                    proposalStatusBadgeClass: this.getBadgeClass(row.proposalStatus),
                    appStageBadgeClass: this.getBadgeClass(row.applicationStage),
                    statusLabel: row.status || '—',
                    statusBadgeClass: this.getBadgeClass(row.status),
                    eligibilityLabel: row.eligibility || '—',
                    eligibilityBadgeClass: this.getBadgeClass(row.eligibility),
                    proposalEligibilityLabel: row.proposalEligibility || 'Pending',
                    proposalEligibilityBadgeClass: this.getBadgeClass(row.proposalEligibility)
                };
            });
            this.error = undefined;
        } else if (error) {
            this.data = [];
            this.error = this.getErrorMessage(error);
            this.showToast('Error', this.error, 'error');
        }
    }

    getBadgeClass(value) {
        return BADGE_CLASS_BY_VALUE[value] || 'slds-badge slds-badge_neutral';
    }

    formatDateParts(isoString) {
        if (!isoString) {
            return { date: '—', time: '' };
        }
        const parsed = new Date(isoString);
        const date = parsed.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: '2-digit' });
        const time = parsed.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
        return { date, time };
    }

    get schemeItemOptions() {
        const uniqueNames = [...new Set(this.data.map((row) => row.schemeItemName).filter(Boolean))].sort();
        return [
            { label: 'All Scheme Items', value: '' },
            ...uniqueNames.map((name) => ({ label: name, value: name }))
        ];
    }

    get applicationStageOptions() {
        const uniqueStages = [...new Set(this.data.map((row) => row.applicationStage).filter(Boolean))].sort();
        return [
            { label: 'All Application Stages', value: '' },
            ...uniqueStages.map((stage) => ({ label: stage, value: stage }))
        ];
    }

    get selectedSchemeItemLabel() {
        const match = this.schemeItemOptions.find((opt) => opt.value === this.selectedSchemeItem);
        return match ? match.label : 'All Scheme Items';
    }

    get selectedApplicationStageLabel() {
        const match = this.applicationStageOptions.find((opt) => opt.value === this.selectedApplicationStage);
        return match ? match.label : 'All Application Stages';
    }

    get schemeItemMenuOptions() {
        return this.schemeItemOptions.map((opt) => ({
            ...opt,
            itemClass: opt.value === this.selectedSchemeItem ? 'myec-dd-item myec-dd-item_selected' : 'myec-dd-item'
        }));
    }

    get applicationStageMenuOptions() {
        return this.applicationStageOptions.map((opt) => ({
            ...opt,
            itemClass:
                opt.value === this.selectedApplicationStage ? 'myec-dd-item myec-dd-item_selected' : 'myec-dd-item'
        }));
    }

    get schemeItemTriggerClass() {
        return this.isSchemeItemDropdownOpen ? 'myec-dd-trigger myec-dd-trigger_open' : 'myec-dd-trigger';
    }

    get applicationStageTriggerClass() {
        return this.isApplicationStageDropdownOpen ? 'myec-dd-trigger myec-dd-trigger_open' : 'myec-dd-trigger';
    }

    handleToggleSchemeItemDropdown(event) {
        event.stopPropagation();
        this.isApplicationStageDropdownOpen = false;
        this.isSchemeItemDropdownOpen = !this.isSchemeItemDropdownOpen;
    }

    handleToggleApplicationStageDropdown(event) {
        event.stopPropagation();
        this.isSchemeItemDropdownOpen = false;
        this.isApplicationStageDropdownOpen = !this.isApplicationStageDropdownOpen;
    }

    handleSelectSchemeItem(event) {
        event.stopPropagation();
        this.selectedSchemeItem = event.currentTarget.dataset.value;
        this.pageNumber = 1;
        this.isSchemeItemDropdownOpen = false;
    }

    handleSelectApplicationStage(event) {
        event.stopPropagation();
        this.selectedApplicationStage = event.currentTarget.dataset.value;
        this.pageNumber = 1;
        this.isApplicationStageDropdownOpen = false;
    }

    get assignedTasksTabClass() {
        return this.activeListTab === 'assigned' ? 'myec-tab-btn myec-tab-btn_active' : 'myec-tab-btn';
    }

    get underEligibilityCheckTabClass() {
        return this.activeListTab === 'underEligibilityCheck' ? 'myec-tab-btn myec-tab-btn_active' : 'myec-tab-btn';
    }

    get eligibilityCheckedTabClass() {
        return this.activeListTab === 'checked' ? 'myec-tab-btn myec-tab-btn_active' : 'myec-tab-btn';
    }

    get inProgressTabClass() {
        return this.activeListTab === 'inProgress' ? 'myec-tab-btn myec-tab-btn_active' : 'myec-tab-btn';
    }

    get needsReviewersTabClass() {
        return this.activeListTab === 'needsReviewers' ? 'myec-tab-btn myec-tab-btn_active' : 'myec-tab-btn';
    }

    get fullApplicationTabClass() {
        return this.activeListTab === 'fullApplication' ? 'myec-tab-btn myec-tab-btn_active' : 'myec-tab-btn';
    }

    get peerReviewTabClass() {
        return this.activeListTab === 'peerReview' ? 'myec-tab-btn myec-tab-btn_active' : 'myec-tab-btn';
    }

    get peerShortlistingTabClass() {
        return this.activeListTab === 'peerShortlisting' ? 'myec-tab-btn myec-tab-btn_active' : 'myec-tab-btn';
    }

    get committeeReviewTabClass() {
        return this.activeListTab === 'committeeReview' ? 'myec-tab-btn myec-tab-btn_active' : 'myec-tab-btn';
    }

    get peerEligibilityTabClass() {
        return this.activeListTab === 'peerEligibility' ? 'myec-tab-btn myec-tab-btn_active' : 'myec-tab-btn';
    }

    get assignedTasksLabel() {
        return `Assigned Schemes (${this.assignedTasksCount})`;
    }

    get underEligibilityCheckLabel() {
        return `Eligibility Check (${this.underEligibilityCheckCount})`;
    }

    get eligibilityCheckedLabel() {
        return `Prelim Review (${this.eligibilityCheckedCount})`;
    }

    get inProgressLabel() {
        return `Shortlisting (${this.inProgressCount})`;
    }

    get needsReviewersLabel() {
        return `Not Eligible (${this.needsReviewersCount})`;
    }

    get fullApplicationLabel() {
        return `Full Application (${this.fullApplicationCount})`;
    }

    get peerReviewLabel() {
        return `Peer Review (${this.peerReviewCount})`;
    }

    get peerShortlistingLabel() {
        return `Peer Shortlisting (${this.peerShortlistingCount})`;
    }

    get committeeReviewLabel() {
        return `Committee Review (${this.committeeReviewCount})`;
    }

    get peerEligibilityLabel() {
        return `FA Eligibility (${this.peerEligibilityCount})`;
    }

    // Row-predicate methods - single source of truth for each tab's condition, used by
    // both the *Count getters (tab badge numbers) and filteredData (actual rows shown).
    isAssignedSchemeRow(row) {
        return row.proposalStatus === 'Eligibility Check' && row.status === 'Pending';
    }

    isUnderEligibilityCheckRow(row) {
        return row.proposalStatus === 'Eligibility Check' && row.status === 'Submitted';
    }

    isPrelimReviewResultRow(row) {
        return row.proposalStatus === 'Prelim Review' && row.status === 'Submitted';
    }

    isShortlistingRow(row) {
        return row.proposalStatus === 'Shortlisting' && row.prelimReviewerEligibilityStatus === 'Submitted';
    }

    isNeedsReviewersRow(row) {
        return row.proposalStatus === 'Rejected' && row.eligibleForPrelim === 'Not Eligible';
    }

    isFullApplicationRow(row) {
        return row.proposalStatus === 'Full Application'
            && row.movedToFullStageByGrantTeamMember === true;
    }

    isPeerReviewRow(row) {
        return row.proposalStatus === 'Peer Review';
    }

    isPeerShortlistingRow(row) {
        return row.proposalStatus === 'Peer Shortlisting' && row.peerReviewerEligibilityStatus === 'Submitted';
    }

    isCommitteeReviewRow(row) {
        return row.proposalStatus === 'Committee Review' && row.recommendedForCommitteeReview === 'Yes';
    }

    isPeerEligibilityRow(row) {
        return row.proposalStatus === 'Peer_Eligibility_Check'
            && row.peerApplicationStage === 'Final Submit';
    }

    get assignedTasksTooltip() {
        return "Proposal_Status__c = 'Eligibility Check' AND Grants_Team_Response__c.Status__c = 'Pending' (Newly Assigned Proposal)";
    }

    get underEligibilityCheckTooltip() {
        return "Proposal_Status__c = 'Eligibility Check' AND Grants_Team_Response__c.Status__c = 'Submitted'";
    }

    get eligibilityCheckedTooltip() {
        return "Proposal_Status__c = 'Prelim Review' AND Grants_Team_Response__c.Status__c = 'Submitted' (Waiting for Reviewers to submit their response)";
    }

    get inProgressTooltip() {
        return "Proposal_Status__c = 'Shortlisting' AND Prelim_Reviewer_Eligibility_Status__c = 'Submitted' (when both reviewers submit their response)";
    }

    get needsReviewersTooltip() {
        return "Proposal_Status__c = 'Rejected' AND Proposal__r.Eligible_For_Prelim__c = 'Not Eligible' (rejected at the Prelim eligibility check stage)";
    }

    get fullApplicationTooltip() {
        return "Proposal_Status__c = 'Full Application' AND Proposal__r.Moved_to_Full_Stage_By_Grant_Team_Member__c = true";
    }

    get peerReviewTooltip() {
        return "Proposal_Status__c = 'Peer Review'";
    }

    get peerShortlistingTooltip() {
        return "Proposal_Status__c = 'Peer Shortlisting' AND Proposal__r.Peer_Reviewer_Eligibility_Status__c = 'Submitted'";
    }

    get committeeReviewTooltip() {
        return "Proposal_Status__c = 'Committee Review' AND Proposal__r.Recommended_for_Committee_Review__c = 'Yes'";
    }

    get peerEligibilityTooltip() {
        return "Proposal_Status__c = 'Peer_Eligibility_Check' AND Proposal__r.Peer_Application_Stage__c = 'Final Submit'";
    }

    get assignedTasksCount() {
        return this.baseFilteredRows.filter((row) => this.isAssignedSchemeRow(row)).length;
    }

    get underEligibilityCheckCount() {
        return this.baseFilteredRows.filter((row) => this.isUnderEligibilityCheckRow(row)).length;
    }

    get eligibilityCheckedCount() {
        return this.baseFilteredRows.filter((row) => this.isPrelimReviewResultRow(row)).length;
    }

    get inProgressCount() {
        return this.baseFilteredRows.filter((row) => this.isShortlistingRow(row)).length;
    }

    get needsReviewersCount() {
        return this.baseFilteredRows.filter((row) => this.isNeedsReviewersRow(row)).length;
    }

    get fullApplicationCount() {
        return this.baseFilteredRows.filter((row) => this.isFullApplicationRow(row)).length;
    }

    get peerReviewCount() {
        return this.baseFilteredRows.filter((row) => this.isPeerReviewRow(row)).length;
    }

    get peerShortlistingCount() {
        return this.baseFilteredRows.filter((row) => this.isPeerShortlistingRow(row)).length;
    }

    get committeeReviewCount() {
        return this.baseFilteredRows.filter((row) => this.isCommitteeReviewRow(row)).length;
    }

    get peerEligibilityCount() {
        return this.baseFilteredRows.filter((row) => this.isPeerEligibilityRow(row)).length;
    }

    handleSelectListTab(event) {
        this.activeListTab = event.currentTarget.dataset.tab;
        this.pageNumber = 1;
        this.selectedProposalIds = new Set();
    }

    get baseFilteredRows() {
        let rows = this.data;

        if (this.selectedSchemeItem) {
            rows = rows.filter((row) => row.schemeItemName === this.selectedSchemeItem);
        }

        if (this.selectedApplicationStage) {
            rows = rows.filter((row) => row.applicationStage === this.selectedApplicationStage);
        }

        if (!this.searchKey) {
            return rows;
        }
        const key = this.searchKey.toLowerCase();
        return rows.filter((row) =>
            (row.proposalIdDisplay || '').toLowerCase().includes(key) ||
            (row.applicantName || '').toLowerCase().includes(key) ||
            (row.proposalStatus || '').toLowerCase().includes(key) ||
            (row.yearlyScheme || '').toLowerCase().includes(key) ||
            (row.schemeItemName || '').toLowerCase().includes(key) ||
            (row.applicationStage || '').toLowerCase().includes(key) ||
            (row.status || '').toLowerCase().includes(key) ||
            (row.eligibility || '').toLowerCase().includes(key)
        );
    }

    get filteredData() {
        if (this.activeListTab === 'underEligibilityCheck') {
            return this.baseFilteredRows.filter((row) => this.isUnderEligibilityCheckRow(row));
        }
        if (this.activeListTab === 'checked') {
            return this.baseFilteredRows.filter((row) => this.isPrelimReviewResultRow(row));
        }
        if (this.activeListTab === 'inProgress') {
            return this.baseFilteredRows.filter((row) => this.isShortlistingRow(row));
        }
        if (this.activeListTab === 'needsReviewers') {
            return this.baseFilteredRows.filter((row) => this.isNeedsReviewersRow(row));
        }
        if (this.activeListTab === 'fullApplication') {
            return this.baseFilteredRows.filter((row) => this.isFullApplicationRow(row));
        }
        if (this.activeListTab === 'peerReview') {
            return this.baseFilteredRows.filter((row) => this.isPeerReviewRow(row));
        }
        if (this.activeListTab === 'peerShortlisting') {
            return this.baseFilteredRows.filter((row) => this.isPeerShortlistingRow(row));
        }
        if (this.activeListTab === 'committeeReview') {
            return this.baseFilteredRows.filter((row) => this.isCommitteeReviewRow(row));
        }
        if (this.activeListTab === 'peerEligibility') {
            return this.baseFilteredRows.filter((row) => this.isPeerEligibilityRow(row));
        }
        return this.baseFilteredRows.filter((row) => this.isAssignedSchemeRow(row));
    }

    get sortedData() {
        const data = [...this.filteredData];
        if (!this.sortBy) {
            return data;
        }
        const direction = this.sortDirection === 'asc' ? 1 : -1;
        data.sort((a, b) => {
            const aVal = a[this.sortBy] ?? '';
            const bVal = b[this.sortBy] ?? '';
            if (aVal < bVal) return -1 * direction;
            if (aVal > bVal) return 1 * direction;
            return 0;
        });
        return data;
    }

    get paginatedData() {
        const start = (this.pageNumber - 1) * this.pageSize;
        const page = this.sortedData.slice(start, start + this.pageSize);
        const isPrelimReviewTab = this.activeListTab === 'checked';
        const isInProgress = this.activeListTab === 'inProgress';
        return page.map((row) => ({
            ...row,
            displayEligibilityLabel: isPrelimReviewTab ? row.proposalEligibilityLabel : row.eligibilityLabel,
            displayEligibilityBadgeClass: isPrelimReviewTab
                ? row.proposalEligibilityBadgeClass
                : row.eligibilityBadgeClass,
            isSelected: isInProgress ? this.selectedProposalIds.has(row.proposalId) : false
        }));
    }

    get isInProgressTab() {
        return this.activeListTab === 'inProgress';
    }

    get isNeedsReviewersTab() {
        return this.activeListTab === 'needsReviewers';
    }

    // Both Shortlisting and Needs Reviewer Assignment key off Proposal__r.Eligible_For_Prelim__c,
    // so both show the extra Official Eligibility column alongside My Verdict.
    get isUnderEligibilityCheckTab() {
        return this.activeListTab === 'underEligibilityCheck';
    }

    get showOfficialEligibilityExtraColumn() {
        return this.isInProgressTab || this.isNeedsReviewersTab || this.isUnderEligibilityCheckTab;
    }

    get isPeerEligibilityTab() {
        return this.activeListTab === 'peerEligibility';
    }

    get isPeerReviewTab() {
        return this.activeListTab === 'peerReview';
    }

    get isPeerShortlistingTab() {
        return this.activeListTab === 'peerShortlisting';
    }

    get showGrantTeamResponseButton() {
        return this.isPrelimReviewTab || this.isUnderEligibilityCheckTab || this.isPeerEligibilityTab || this.isPeerReviewTab
            || this.isNeedsReviewersTab;
    }

    get showReviewerResponseListButton() {
        return this.isPrelimReviewTab || this.isPeerReviewTab;
    }

    get showProposalReviewerButton() {
        return this.isPrelimReviewTab || this.isPeerReviewTab;
    }

    get selectedProposalCount() {
        return this.selectedProposalIds.size;
    }

    get hasSelectedProposals() {
        return this.selectedProposalCount > 0;
    }

    get markEligibleLabel() {
        return `Mark Eligible for Full (${this.selectedProposalCount})`;
    }

    handleToggleRowSelect(event) {
        const proposalId = event.currentTarget.dataset.proposalId;
        const isChecked = event.target.checked;
        const updated = new Set(this.selectedProposalIds);
        if (isChecked) {
            updated.add(proposalId);
        } else {
            updated.delete(proposalId);
        }
        this.selectedProposalIds = updated;
    }

    async handleMarkEligibleForFull() {
        if (this.selectedProposalIds.size === 0) {
            this.showToast('Error', 'Select at least one proposal.', 'error');
            return;
        }
        this.isMarkingEligible = true;
        try {
            await markEligibleForFull({ proposalIds: Array.from(this.selectedProposalIds) });
            this.showToast('Success', 'Selected proposals marked Eligible for Full.', 'success');
            this.selectedProposalIds = new Set();
            await refreshApex(this.wiredResult);
        } catch (e) {
            this.showToast('Error', this.getErrorMessage(e), 'error');
        } finally {
            this.isMarkingEligible = false;
        }
    }

    get totalRecords() {
        return this.filteredData.length;
    }

    get totalPages() {
        return Math.ceil(this.totalRecords / this.pageSize) || 1;
    }

    get showingFrom() {
        return this.totalRecords === 0 ? 0 : (this.pageNumber - 1) * this.pageSize + 1;
    }

    get showingTo() {
        return Math.min(this.pageNumber * this.pageSize, this.totalRecords);
    }

    get noData() {
        return !this.isLoading && !this.error && this.data.length === 0;
    }

    get hasData() {
        return !this.isLoading && !this.error && this.data.length > 0;
    }

    get countLabel() {
        return `${this.totalRecords}`;
    }

    get isPrelimReviewTab() {
        return this.activeListTab === 'checked';
    }

    get isAssignedTab() {
        return this.activeListTab === 'assigned';
    }

    get showYearlySchemeColumn() {
        return false;
    }

    get showSchemeItemColumn() {
        return false;
    }

    get showStatusColumn() {
        return !this.isAssignedTab;
    }

    get showEligibilityColumn() {
        return !this.isAssignedTab;
    }

    get columnMeta() {
        const isPrelimReviewTab = this.isPrelimReviewTab;
        const showOfficialEligibilityExtraColumn = this.showOfficialEligibilityExtraColumn;
        let defs = [];
        COLUMN_DEFS.forEach((col) => {
            if (col.key === 'status') {
                defs.push(col);
                if (isPrelimReviewTab) {
                    defs.push({ key: 'eligibility', label: 'My Verdict', sortable: true });
                }
                return;
            }
            if (col.key === 'eligibility') {
                if (isPrelimReviewTab) {
                    defs.push({ key: 'proposalEligibility', label: 'Official Eligibility', sortable: true });
                    return;
                }
                defs.push(col);
                if (showOfficialEligibilityExtraColumn) {
                    defs.push({ key: 'proposalEligibility', label: 'Official Eligibility', sortable: true });
                }
                return;
            }
            defs.push(col);
        });
        const hiddenKeys = ['yearlyScheme', 'schemeItemName'];
        if (this.isAssignedTab) {
            hiddenKeys.push('status', 'eligibility');
        }
        defs = defs.filter((col) => !hiddenKeys.includes(col.key));
        return defs.map((col) => {
            const key = col.key;
            const label = col.label;
            const isActive = col.sortable && this.sortBy === key;
            return {
                ...col,
                key,
                label,
                thClass: 'eligibility-th' + (col.sortable ? ' eligibility-th_sortable' : ''),
                sortIconName: isActive && this.sortDirection === 'desc' ? 'utility:arrowdown' : 'utility:arrowup',
                sortIconClass: 'eligibility-sort-icon' + (isActive ? ' eligibility-sort-icon_active' : '')
            };
        });
    }

    get pageNumbers() {
        const pages = [];
        for (let i = 1; i <= this.totalPages; i++) {
            pages.push({
                value: i,
                variant: i === this.pageNumber ? 'brand' : 'neutral'
            });
        }
        return pages;
    }

    handleSearch(event) {
        this.searchKey = event.target.value;
        this.pageNumber = 1;
    }

    handleSort(event) {
        const key = event.currentTarget.dataset.key;
        if (this.sortBy === key) {
            this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortBy = key;
            this.sortDirection = 'asc';
        }
    }

    handlePreviousPage() {
        if (this.pageNumber > 1) {
            this.pageNumber--;
        }
    }

    handleNextPage() {
        if (this.pageNumber < this.totalPages) {
            this.pageNumber++;
        }
    }

    handleFirstPage() {
        this.pageNumber = 1;
    }

    handleLastPage() {
        this.pageNumber = this.totalPages;
    }

    handlePageSelect(event) {
        this.pageNumber = parseInt(event.target.name, 10);
    }

    handleOpenClick(event) {
        this.openProposalApplicantDetails(event.currentTarget.dataset.proposalId);
    }

    handleOpenGrantTeamResponse(event) {
        this.selectedProposalIdForGrantTeamResponse = event.currentTarget.dataset.proposalId;
        this.showGrantTeamResponseModal = true;
    }

    handleCloseGrantTeamResponse() {
        this.showGrantTeamResponseModal = false;
        this.selectedProposalIdForGrantTeamResponse = undefined;
    }

    handleOpenCheckEligibility(event) {
        this.selectedProposalIdForCheckEligibility = event.currentTarget.dataset.proposalId;
        this.showCheckEligibilityModal = true;
    }

    handleCloseCheckEligibility() {
        this.showCheckEligibilityModal = false;
        this.selectedProposalIdForCheckEligibility = undefined;
        refreshApex(this.wiredResult);
    }

    handleOpenReviewerResponse(event) {
        this.selectedProposalIdForReviewerResponse = event.currentTarget.dataset.proposalId;
        this.showReviewerResponseModal = true;
    }

    handleCloseReviewerResponse() {
        this.showReviewerResponseModal = false;
        this.selectedProposalIdForReviewerResponse = undefined;
        refreshApex(this.wiredResult);
    }

    handleOpenPeerEvaluation(event) {
        this.selectedProposalIdForPeerEvaluation = event.currentTarget.dataset.proposalId;
        this.showPeerEvaluationModal = true;
    }

    handleClosePeerEvaluation() {
        this.showPeerEvaluationModal = false;
        this.selectedProposalIdForPeerEvaluation = undefined;
        refreshApex(this.wiredResult);
    }

    handleOpenReviewerMapping(event) {
        this.reviewerMappingApplicationStage = this.isPeerReviewTab ? 'Full' : 'Prelims';
        this.selectedProposalIdForReviewerMapping = event.currentTarget.dataset.proposalId;
        this.showReviewerMappingModal = true;
    }

    handleCloseReviewerMapping() {
        this.showReviewerMappingModal = false;
        this.selectedProposalIdForReviewerMapping = undefined;
    }

    handleOpenProposalReviewer() {
        this.proposalReviewerInitialStatusFilter = this.isPeerReviewTab ? 'PEER' : 'PRELIM';
        this.showProposalReviewerModal = true;
    }

    handleCloseProposalReviewer() {
        this.showProposalReviewerModal = false;
    }

    handleOpenApplicationFormClick(event) {
        this.openProposalApplicationForm(event.currentTarget.dataset.proposalId);
    }

    handleMoreClick() {
        this.showToast('Info', 'More actions coming soon.', 'info');
    }

    handleOpenProposalRecord(event) {
        this.openProposalRecordPage(event.currentTarget.dataset.proposalId);
    }

    async openProposalRecordPage(proposalId) {
        const pageReference = {
            type: 'standard__recordPage',
            attributes: {
                recordId: proposalId,
                objectApiName: 'Proposal__c',
                actionName: 'view'
            }
        };
        const url = await this[NavigationMixin.GenerateUrl](pageReference);
        window.open(url, '_blank');
    }

    async openProposalApplicantDetails(proposalId) {
        const pageReference = {
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Proposal_Details'
            },
            state: {
                c__recordId: proposalId
            }
        };
        const url = await this[NavigationMixin.GenerateUrl](pageReference);
        window.open(url, '_blank');
    }

    async openProposalApplicationForm(proposalId) {
        const pageReference = {
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Proposal_Application_Form'
            },
            state: {
                c__recordId: proposalId
            }
        };
        const url = await this[NavigationMixin.GenerateUrl](pageReference);
        window.open(url, '_blank');
    }

    getErrorMessage(error) {
        return error?.body?.message || error?.message || 'Something went wrong.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}