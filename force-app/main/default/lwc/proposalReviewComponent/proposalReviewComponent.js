import { LightningElement, api, track } from 'lwc';
import getProposals from '@salesforce/apex/ProposalReviewerController.getProposals';
import updateReviewerDecision from '@salesforce/apex/ProposalReviewerController.updateReviewerDecision';
import getAvailableReviewers from '@salesforce/apex/ProposalReviewerController.getAvailableReviewers';
import addReviewersToProposal from '@salesforce/apex/ProposalReviewerController.addReviewersToProposal';
import getSchemeNameOptions from '@salesforce/apex/ProposalReviewerController.getSchemeNameOptions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const STATUS_BADGE_CLASS = {
    'Prelim Review': 'slds-badge slds-badge_purple',
    'Peer Review': 'slds-badge slds-badge_lightblue'
};

export default class ProposalReviewComponent extends LightningElement {

    PAGE_SIZE = 20;

    @track records = [];

    // Optional preset from a parent component: 'NONE' | 'PRELIM' | 'PEER'
    @api initialStatusFilter;

    statusFilter = 'NONE';
    schemeFilter = '';

    @track schemeNameOptions = [];

    isStatusDropdownOpen = false;
    isSchemeDropdownOpen = false;

    get statusOptions() {
        return [
            { label: 'All Statuses', value: 'NONE' },
            { label: 'Prelim Review', value: 'PRELIM' },
            { label: 'Peer Review', value: 'PEER' }
        ];
    }

    /* ============================================================
       FILTER DROPDOWNS (match reference component styling)
       ============================================================ */

    get selectedStatusLabel() {
        const match = this.statusOptions.find(opt => opt.value === this.statusFilter);
        return match ? match.label : 'All Statuses';
    }

    get statusMenuOptions() {
        return this.statusOptions.map(opt => ({
            ...opt,
            itemClass: opt.value === this.statusFilter
                ? 'myec-dd-item myec-dd-item_selected'
                : 'myec-dd-item'
        }));
    }

    get statusTriggerClass() {
        return this.isStatusDropdownOpen
            ? 'myec-dd-trigger myec-dd-trigger_open'
            : 'myec-dd-trigger';
    }

    get selectedSchemeLabel() {
        return this.schemeFilter ? this.schemeFilter : 'All Scheme Names';
    }

    get schemeMenuOptions() {
        const options = [{ label: 'All Scheme Names', value: '' }];

        (this.schemeNameOptions || []).forEach(name => {
            options.push({ label: name, value: name });
        });

        return options.map(opt => ({
            ...opt,
            itemClass: opt.value === this.schemeFilter
                ? 'myec-dd-item myec-dd-item_selected'
                : 'myec-dd-item'
        }));
    }

    get schemeTriggerClass() {
        return this.isSchemeDropdownOpen
            ? 'myec-dd-trigger myec-dd-trigger_open'
            : 'myec-dd-trigger';
    }

    handleToggleStatusDropdown(event) {
        event.stopPropagation();
        this.isSchemeDropdownOpen = false;
        this.isStatusDropdownOpen = !this.isStatusDropdownOpen;
    }

    handleSelectStatus(event) {
        event.stopPropagation();
        this.isStatusDropdownOpen = false;
        this.statusFilter = event.currentTarget.dataset.value;
        this.loadFirstPage();
    }

    handleToggleSchemeDropdown(event) {
        event.stopPropagation();
        this.isStatusDropdownOpen = false;
        this.isSchemeDropdownOpen = !this.isSchemeDropdownOpen;
    }

    handleSelectScheme(event) {
        event.stopPropagation();
        this.isSchemeDropdownOpen = false;
        this.schemeFilter = event.currentTarget.dataset.value;
        this.loadFirstPage();
    }

    get decisionOptions() {
        return [
            { label: 'Pending', value: 'Pending' },
            { label: 'Approved', value: 'Approved' },
            { label: 'Conflict', value: 'Conflict' }
        ];
    }

    currentPage = 1;
    totalPages = 0;
    totalRecords = 0;
    firstCursor = null;
    lastCursor = null;
    pageCursors = {};

    isLoading = false;

    @track reviewerRecords = [];
    showReviewerModal = false;
    reviewerLoading = false;
    selectedProposalId = null;

    // "Reviewers" pop-out (new compact view; inline table kept for now)
    showReviewersModal = false;
    reviewersModalProposalId = null;

    selectedReviewerIds = new Set();
    reviewerNameSearch = '';
    reviewerEmailSearch = '';
    reviewerCurrentPage = 1;
    reviewerTotalPages = 0;
    reviewerTotalRecords = 0;
    reviewerFirstCursor = null;
    reviewerLastCursor = null;
    reviewerPageCursors = {};

    connectedCallback() {
        this._handleWindowClick = () => {
            this.isStatusDropdownOpen = false;
            this.isSchemeDropdownOpen = false;
        };
        window.addEventListener('click', this._handleWindowClick);

        const allowed = ['NONE', 'PRELIM', 'PEER'];
        if (allowed.includes(this.initialStatusFilter)) {
            this.statusFilter = this.initialStatusFilter;
        }

        this.loadSchemeOptions();
        this.loadFirstPage();
    }

    disconnectedCallback() {
        window.removeEventListener('click', this._handleWindowClick);
    }

    loadSchemeOptions() {
        getSchemeNameOptions()
            .then(result => {
                this.schemeNameOptions = result || [];
            })
            .catch(error => {
                console.error('Error loading scheme names:', error);
            });
    }

    /* Shared shaping of proposal rows returned by the controller */
    mapRecords(result) {
        return (result.records || []).map(record => {
            const reviewers = (record.reviewerDetails || []).map((reviewer, index) => {
                const reason = reviewer.conflictReason || '';
                return {
                    ...reviewer,
                    isFirst: index === 0,
                    showConflictReason: false,
                    isEditingConflict: false,
                    conflictReasonLength: reason.length,
                    organizationLabel: reviewer.organizationName || '—',
                    rowClass: reviewer.hasOrganizationConflict
                        ? 'eligibility-tr prc-reviewer-row_org-conflict'
                        : 'eligibility-tr',
                    orgConflictIcon: reviewer.hasOrganizationConflict ? 'utility:warning' : null
                };
            });

            return {
                ...record,
                reviewerDetails: reviewers,
                hasReviewers: reviewers.length > 0,
                hasNoReviewers: reviewers.length === 0,
                rowSpan: reviewers.length > 0 ? reviewers.length : 1,
                applicantNameLabel: record.applicantName || '—',
                applicantOrganizationLabel: record.applicantOrganization || '—',
                schemeNameLabel: record.schemeName || '—',
                statusBadgeClass:
                    STATUS_BADGE_CLASS[record.proposalStatus] || 'slds-badge slds-badge_neutral'
            };
        });
    }

    /* ============================================================
       "REVIEWERS" POP-OUT
       Reuses the same records/handlers as the inline table so any
       decision change stays in sync across both views.
       ============================================================ */

    get reviewersModalRecord() {
        return this.records.find(
            record => record.proposalId === this.reviewersModalProposalId
        );
    }

    get reviewersModalReviewers() {
        const record = this.reviewersModalRecord;
        return record ? record.reviewerDetails : [];
    }

    get hasReviewersModalReviewers() {
        return this.reviewersModalReviewers.length > 0;
    }

    get reviewersModalTitle() {
        const record = this.reviewersModalRecord;
        return record ? 'Reviewers · ' + record.applicationId : 'Reviewers';
    }

    handleOpenReviewers(event) {
        this.reviewersModalProposalId = event.currentTarget.dataset.id;
        this.showReviewersModal = true;
    }

    handleCloseReviewersModal() {
        this.showReviewersModal = false;
        this.reviewersModalProposalId = null;
    }

    loadFirstPage() {
        this.currentPage = 1;
        this.pageCursors = {};
        this.firstCursor = null;
        this.lastCursor = null;
        this.loadData(null, 'NEXT');
    }

    loadData(cursorId, direction) {
        this.isLoading = true;

        getProposals({
            cursorId: cursorId,
            direction: direction,
            statusFilter: this.statusFilter,
            schemeFilter: this.schemeFilter
        })
        .then(result => {
            this.records = this.mapRecords(result);

            this.totalRecords = result.totalRecords || 0;
            this.totalPages = result.totalPages || 0;
            this.firstCursor = result.firstCursor;
            this.lastCursor = result.lastCursor;
        })
        .catch(error => {
            console.error('Error loading proposals:', error);
            this.showToast('Error', this.getErrorMessage(error), 'error');
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    handleDecisionChange(event) {
        const reviewerId = event.target.dataset.id;
        const decision = event.detail.value;

        this.records = this.records.map(record => {
            return {
                ...record,
                reviewerDetails: record.reviewerDetails.map(reviewer => {
                    if (reviewer.reviewerMappingId === reviewerId) {
                        const hasExistingReason = !!reviewer.conflictReason;

                        return {
                            ...reviewer,
                            decision: decision,
                            showConflictReason: decision === 'Conflict' && !hasExistingReason,
                            isEditingConflict: decision === 'Conflict' && !hasExistingReason,
                            conflictReason: decision === 'Conflict' ? reviewer.conflictReason : '',
                            conflictReasonLength: decision === 'Conflict' ? (reviewer.conflictReason || '').length : 0
                        };
                    }

                    return reviewer;
                })
            };
        });

        // Approved saves immediately
        if (decision === 'Approved') {
            this.saveReviewerDecision(reviewerId, 'Approved', '');
        }
        // Pending saves immediately
        else if (decision === 'Pending') {
            this.saveReviewerDecision(reviewerId, 'Pending', '');
        }
        // Conflict waits for reason + Save
    }

    handleConflictReasonClick(event) {
        const reviewerId = event.currentTarget.dataset.id;

        this.records = this.records.map(record => {
            return {
                ...record,
                reviewerDetails: record.reviewerDetails.map(reviewer => {
                    if (reviewer.reviewerMappingId === reviewerId) {
                        return {
                            ...reviewer,
                            isEditingConflict: true,
                            showConflictReason: true,
                            conflictReasonLength: (reviewer.conflictReason || '').length
                        };
                    }

                    return reviewer;
                })
            };
        });
    }

    handleConflictReasonChange(event) {
        const reviewerId = event.target.dataset.id;
        const reason = event.target.value || '';

        this.records = this.records.map(record => {
            return {
                ...record,
                reviewerDetails: record.reviewerDetails.map(reviewer => {
                    if (reviewer.reviewerMappingId === reviewerId) {
                        return {
                            ...reviewer,
                            conflictReason: reason,
                            conflictReasonLength: reason.length
                        };
                    }

                    return reviewer;
                })
            };
        });
    }

    async handleConflictSave(event) {
        const reviewerId = event.currentTarget.dataset.id;

        let reviewerToSave = null;

        this.records.forEach(record => {
            record.reviewerDetails.forEach(reviewer => {
                if (reviewer.reviewerMappingId === reviewerId) {
                    reviewerToSave = reviewer;
                }
            });
        });

        if (!reviewerToSave) {
            return;
        }

        const reason = (reviewerToSave.conflictReason || '').trim();

        if (!reason) {
            this.showToast('Error', 'Conflict Reason is required.', 'error');
            return;
        }

        if (reason.length > 255) {
            this.showToast('Error', 'Conflict Reason cannot exceed 255 characters.', 'error');
            return;
        }

        try {
            this.isLoading = true;

            await updateReviewerDecision({
                reviewerMappingId: reviewerId,
                decision: 'Conflict',
                conflictReason: reason
            });

            this.records = this.records.map(record => {
                return {
                    ...record,
                    reviewerDetails: record.reviewerDetails.map(reviewer => {
                        if (reviewer.reviewerMappingId === reviewerId) {
                            return {
                                ...reviewer,
                                decision: 'Conflict',
                                conflictReason: reason,
                                conflictReasonLength: reason.length,
                                showConflictReason: false,
                                isEditingConflict: false
                            };
                        }

                        return reviewer;
                    })
                };
            });

            this.showToast('Success', 'Reviewer conflict has been saved successfully.', 'success');
        }
        catch (error) {
            console.error('Error saving conflict:', error);
            this.showToast('Error', this.getErrorMessage(error), 'error');
        }
        finally {
            this.isLoading = false;
        }
    }

    saveReviewerDecision(reviewerId, decision, conflictReason) {
        this.isLoading = true;

        updateReviewerDecision({
            reviewerMappingId: reviewerId,
            decision: decision,
            conflictReason: conflictReason
        })
        .then(() => {
            this.showToast('Success', this.getSuccessMessage(decision), 'success');
        })
        .catch(error => {
            console.error('Error updating reviewer:', error);
            this.showToast('Error', this.getErrorMessage(error), 'error');
        })
        .finally(() => {
            this.isLoading = false;
        });
    }

    handleAddReviewer(event) {
        this.selectedProposalId = event.currentTarget.dataset.id;

        this.reviewerNameSearch = '';
        this.reviewerEmailSearch = '';
        this.selectedReviewerIds = new Set();

        this.reviewerCurrentPage = 1;
        this.reviewerTotalPages = 0;
        this.reviewerTotalRecords = 0;
        this.reviewerFirstCursor = null;
        this.reviewerLastCursor = null;
        this.reviewerPageCursors = {};

        this.showReviewerModal = true;

        this.loadReviewers(null, 'FIRST');
    }

    loadReviewers(cursorId, direction) {
        this.reviewerLoading = true;

        getAvailableReviewers({
            proposalId: this.selectedProposalId,
            nameSearch: this.reviewerNameSearch,
            emailSearch: this.reviewerEmailSearch,
            cursorId: cursorId,
            direction: direction
        })
        .then(result => {
            this.reviewerRecords = (result.records || []).map(reviewer => {
                return {
                    ...reviewer,
                    selected: this.selectedReviewerIds.has(reviewer.reviewerId)
                };
            });

            this.reviewerTotalRecords = result.totalRecords || 0;
            this.reviewerTotalPages = result.totalPages || 0;
            this.reviewerFirstCursor = result.firstCursor;
            this.reviewerLastCursor = result.lastCursor;
        })
        .catch(error => {
            console.error('Error loading reviewers:', error);
            this.showToast('Error', this.getErrorMessage(error), 'error');
        })
        .finally(() => {
            this.reviewerLoading = false;
        });
    }

    handleReviewerNameSearch(event) {
        this.reviewerNameSearch = event.detail.value || '';
        this.reviewerCurrentPage = 1;
        this.reviewerPageCursors = {};

        this.loadReviewers(null, 'FIRST');
    }

    handleReviewerEmailSearch(event) {
        this.reviewerEmailSearch = event.detail.value || '';
        this.reviewerCurrentPage = 1;
        this.reviewerPageCursors = {};

        this.loadReviewers(null, 'FIRST');
    }

    handleReviewerSelection(event) {
        const reviewerId = event.target.dataset.id;
        const checked = event.target.checked;

        if (checked) {
            this.selectedReviewerIds.add(reviewerId);
        }
        else {
            this.selectedReviewerIds.delete(reviewerId);
        }

        this.reviewerRecords = this.reviewerRecords.map(reviewer => {
            if (reviewer.reviewerId === reviewerId) {
                return {
                    ...reviewer,
                    selected: checked
                };
            }

            return reviewer;
        });
    }

    async handleSaveReviewers() {
        if (this.selectedReviewerIds.size === 0) {
            this.showToast('Error', 'Please select at least one reviewer.', 'error');
            return;
        }

        try {
            this.reviewerLoading = true;

            await addReviewersToProposal({
                proposalId: this.selectedProposalId,
                reviewerIds: Array.from(this.selectedReviewerIds)
            });

            this.showToast('Success', 'Reviewer(s) added successfully.', 'success');

            this.showReviewerModal = false;

            // Refresh main list
            this.loadData(this.firstCursor, 'NEXT');
        }
        catch (error) {
            console.error('Error adding reviewers:', error);
            this.showToast('Error', this.getErrorMessage(error), 'error');
        }
        finally {
            this.reviewerLoading = false;
        }
    }

    handleCloseReviewerModal() {
        this.showReviewerModal = false;
        this.selectedProposalId = null;
        this.reviewerRecords = [];
        this.selectedReviewerIds = new Set();
        this.reviewerNameSearch = '';
        this.reviewerEmailSearch = '';
        this.reviewerCurrentPage = 1;
        this.reviewerTotalPages = 0;
        this.reviewerTotalRecords = 0;
        this.reviewerFirstCursor = null;
        this.reviewerLastCursor = null;
        this.reviewerPageCursors = {};
    }

    handleReviewerNext() {
        if (this.reviewerCurrentPage >= this.reviewerTotalPages) {
            return;
        }

        this.reviewerPageCursors[this.reviewerCurrentPage + 1] = this.reviewerLastCursor;

        const nextCursor = this.reviewerLastCursor;

        this.reviewerCurrentPage++;

        this.loadReviewers(nextCursor, 'NEXT');
    }

    handleReviewerPrevious() {
        if (this.reviewerCurrentPage <= 1) {
            return;
        }

        const cursor = this.reviewerPageCursors[this.reviewerCurrentPage];

        this.reviewerCurrentPage--;

        this.loadReviewers(cursor, 'PREV');
    }

    handleReviewerFirst() {
        if (this.reviewerCurrentPage <= 1) {
            return;
        }

        this.reviewerCurrentPage = 1;
        this.reviewerPageCursors = {};

        this.loadReviewers(null, 'FIRST');
    }

    handleReviewerLast() {
        if (this.reviewerTotalPages === 0 || this.reviewerCurrentPage >= this.reviewerTotalPages) {
            return;
        }

        this.reviewerCurrentPage = this.reviewerTotalPages;

        this.loadReviewers(null, 'LAST');
    }

    handleNext() {
        if (this.currentPage >= this.totalPages) {
            return;
        }

        this.pageCursors[this.currentPage + 1] = this.lastCursor;

        const nextCursor = this.lastCursor;

        this.currentPage++;

        this.loadData(nextCursor, 'NEXT');
    }

    handlePrevious() {
        if (this.currentPage <= 1) {
            return;
        }

        const cursor = this.pageCursors[this.currentPage];

        this.currentPage--;

        this.loadData(cursor, 'PREV');
    }

    handleFirst() {
        if (this.currentPage <= 1) {
            return;
        }

        this.loadFirstPage();
    }

    async handleLast() {
        if (this.totalPages === 0 || this.currentPage >= this.totalPages) {
            return;
        }

        while (this.currentPage < this.totalPages) {
            this.pageCursors[this.currentPage + 1] = this.lastCursor;

            const nextCursor = this.lastCursor;

            this.currentPage++;

            try {
                this.isLoading = true;

                const result = await getProposals({
                    cursorId: nextCursor,
                    direction: 'NEXT',
                    statusFilter: this.statusFilter,
                    schemeFilter: this.schemeFilter
                });

                this.records = this.mapRecords(result);

                this.totalRecords = result.totalRecords || 0;
                this.totalPages = result.totalPages || 0;
                this.firstCursor = result.firstCursor;
                this.lastCursor = result.lastCursor;
            }
            catch (error) {
                console.error('Error loading last page:', error);

                this.showToast('Error', this.getErrorMessage(error), 'error');

                this.currentPage--;

                break;
            }
            finally {
                this.isLoading = false;
            }
        }
    }

    get disablePrevious() {
        return (
            this.isLoading ||
            this.currentPage <= 1
        );
    }

    get disableNext() {
        return (
            this.isLoading ||
            this.currentPage >= this.totalPages
        );
    }

    get startRecord() {
        if (this.totalRecords === 0) {
            return 0;
        }

        return ((this.currentPage - 1) * this.PAGE_SIZE) + 1;
    }

    get endRecord() {
        const end = this.currentPage * this.PAGE_SIZE;

        return Math.min(end, this.totalRecords);
    }

    get reviewerDisablePrevious() {
        return (
            this.reviewerLoading ||
            this.reviewerCurrentPage <= 1
        );
    }

    get reviewerDisableNext() {
        return (
            this.reviewerLoading ||
            this.reviewerCurrentPage >= this.reviewerTotalPages
        );
    }

    get reviewerStartRecord() {
        if (this.reviewerTotalRecords === 0) {
            return 0;
        }

        return ((this.reviewerCurrentPage - 1) * this.PAGE_SIZE) + 1;
    }

    get reviewerEndRecord() {
        const end = this.reviewerCurrentPage * this.PAGE_SIZE;

        return Math.min(end, this.reviewerTotalRecords);
    }

    get disableSaveReviewers() {
        return (
            this.reviewerLoading ||
            this.selectedReviewerIds.size === 0
        );
    }

    getSuccessMessage(decision) {
        if (decision === 'Approved') {
            return 'Reviewer has been approved successfully.';
        }

        if (decision === 'Conflict') {
            return 'Reviewer has been marked as conflict successfully.';
        }

        return 'Reviewer decision has been reset to pending.';
    }

    getErrorMessage(error) {
        return error?.body?.message || 'Something went wrong while processing the request.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
}