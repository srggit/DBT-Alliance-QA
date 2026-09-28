import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getReviewerAssignmentsForProposal from '@salesforce/apex/ProposalReviewerController.getReviewerAssignmentsForProposal';
import updateReviewerDecision from '@salesforce/apex/ProposalReviewerController.updateReviewerDecision';
import getAvailableReviewers from '@salesforce/apex/ProposalReviewerController.getAvailableReviewers';
import addReviewersToProposal from '@salesforce/apex/ProposalReviewerController.addReviewersToProposal';

const PAGE_SIZE = 20;

export default class AssignReviewersModal extends LightningElement {
    _recordId;
    isLoading = false;
    error;
    proposalRow;
    reviewers = [];

    // Add Reviewer sub-modal
    showAddReviewerModal = false;
    reviewerLoading = false;
    reviewerRecords = [];
    selectedReviewerIds = new Set();
    reviewerNameSearch = '';
    reviewerEmailSearch = '';
    reviewerCurrentPage = 1;
    reviewerTotalPages = 0;
    reviewerTotalRecords = 0;
    reviewerFirstCursor = null;
    reviewerLastCursor = null;
    reviewerPageCursors = {};

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this.loadData();
    }

    get decisionOptions() {
        return [
            { label: 'Pending', value: 'Pending' },
            { label: 'Approved', value: 'Approved' },
            { label: 'Conflict', value: 'Conflict' }
        ];
    }

    async loadData() {
        if (!this._recordId) {
            return;
        }
        this.isLoading = true;
        this.error = undefined;
        try {
            const row = await getReviewerAssignmentsForProposal({ proposalId: this._recordId });
            this.proposalRow = row;
            this.reviewers = (row?.reviewerDetails || []).map((reviewer) => {
                const reason = reviewer.conflictReason || '';
                return {
                    ...reviewer,
                    showConflictReason: false,
                    isEditingConflict: false,
                    conflictReasonLength: reason.length,
                    organizationLabel: reviewer.organizationName || '—',
                    rowClass: reviewer.hasOrganizationConflict ? 'arm-tr arm-tr_org-conflict' : 'arm-tr',
                    orgConflictIcon: reviewer.hasOrganizationConflict ? 'utility:warning' : null
                };
            });
        } catch (e) {
            this.error = this.getErrorMessage(e);
            this.proposalRow = undefined;
            this.reviewers = [];
        } finally {
            this.isLoading = false;
        }
    }

    get hasData() {
        return !this.isLoading && !this.error;
    }

    get hasReviewers() {
        return this.reviewers.length > 0;
    }

    get modalTitle() {
        return this.proposalRow ? 'Reviewers · ' + this.proposalRow.applicationId : 'Reviewers';
    }

    get applicantNameLabel() {
        return this.proposalRow?.applicantName || '—';
    }

    get applicantOrganizationLabel() {
        return this.proposalRow?.applicantOrganization || '—';
    }

    handleDecisionChange(event) {
        const reviewerId = event.target.dataset.id;
        const decision = event.detail.value;

        this.reviewers = this.reviewers.map((reviewer) => {
            if (reviewer.reviewerMappingId !== reviewerId) {
                return reviewer;
            }
            const hasExistingReason = !!reviewer.conflictReason;
            return {
                ...reviewer,
                decision,
                showConflictReason: decision === 'Conflict' && !hasExistingReason,
                isEditingConflict: decision === 'Conflict' && !hasExistingReason,
                conflictReason: decision === 'Conflict' ? reviewer.conflictReason : '',
                conflictReasonLength: decision === 'Conflict' ? (reviewer.conflictReason || '').length : 0
            };
        });

        if (decision === 'Approved' || decision === 'Pending') {
            this.saveReviewerDecision(reviewerId, decision, '');
        }
    }

    handleConflictReasonClick(event) {
        const reviewerId = event.currentTarget.dataset.id;
        this.reviewers = this.reviewers.map((reviewer) =>
            reviewer.reviewerMappingId === reviewerId
                ? { ...reviewer, isEditingConflict: true, showConflictReason: true, conflictReasonLength: (reviewer.conflictReason || '').length }
                : reviewer
        );
    }

    handleConflictReasonChange(event) {
        const reviewerId = event.target.dataset.id;
        const reason = event.target.value || '';
        this.reviewers = this.reviewers.map((reviewer) =>
            reviewer.reviewerMappingId === reviewerId
                ? { ...reviewer, conflictReason: reason, conflictReasonLength: reason.length }
                : reviewer
        );
    }

    async handleConflictSave(event) {
        const reviewerId = event.currentTarget.dataset.id;
        const reviewer = this.reviewers.find((r) => r.reviewerMappingId === reviewerId);
        if (!reviewer) {
            return;
        }
        const reason = (reviewer.conflictReason || '').trim();
        if (!reason) {
            this.showToast('Error', 'Conflict Reason is required.', 'error');
            return;
        }
        if (reason.length > 255) {
            this.showToast('Error', 'Conflict Reason cannot exceed 255 characters.', 'error');
            return;
        }

        this.isLoading = true;
        try {
            await updateReviewerDecision({ reviewerMappingId: reviewerId, decision: 'Conflict', conflictReason: reason });
            this.reviewers = this.reviewers.map((r) =>
                r.reviewerMappingId === reviewerId
                    ? { ...r, decision: 'Conflict', conflictReason: reason, conflictReasonLength: reason.length, showConflictReason: false, isEditingConflict: false }
                    : r
            );
            this.showToast('Success', 'Reviewer conflict has been saved successfully.', 'success');
        } catch (e) {
            this.showToast('Error', this.getErrorMessage(e), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async saveReviewerDecision(reviewerId, decision, conflictReason) {
        this.isLoading = true;
        try {
            await updateReviewerDecision({ reviewerMappingId: reviewerId, decision, conflictReason });
            this.showToast('Success', this.getSuccessMessage(decision), 'success');
        } catch (e) {
            this.showToast('Error', this.getErrorMessage(e), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /* ============================================================
       ADD REVIEWER SUB-MODAL
       ============================================================ */

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    handleOpenAddReviewer() {
        this.reviewerNameSearch = '';
        this.reviewerEmailSearch = '';
        this.selectedReviewerIds = new Set();
        this.reviewerCurrentPage = 1;
        this.reviewerTotalPages = 0;
        this.reviewerTotalRecords = 0;
        this.reviewerFirstCursor = null;
        this.reviewerLastCursor = null;
        this.reviewerPageCursors = {};
        this.showAddReviewerModal = true;
        this.loadReviewers(null, 'FIRST');
    }

    async loadReviewers(cursorId, direction) {
        this.reviewerLoading = true;
        try {
            const result = await getAvailableReviewers({
                proposalId: this._recordId,
                nameSearch: this.reviewerNameSearch,
                emailSearch: this.reviewerEmailSearch,
                cursorId,
                direction
            });
            this.reviewerRecords = (result.records || []).map((reviewer) => ({
                ...reviewer,
                selected: this.selectedReviewerIds.has(reviewer.reviewerId)
            }));
            this.reviewerTotalRecords = result.totalRecords || 0;
            this.reviewerTotalPages = result.totalPages || 0;
            this.reviewerFirstCursor = result.firstCursor;
            this.reviewerLastCursor = result.lastCursor;
        } catch (e) {
            this.showToast('Error', this.getErrorMessage(e), 'error');
        } finally {
            this.reviewerLoading = false;
        }
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
        } else {
            this.selectedReviewerIds.delete(reviewerId);
        }
        this.reviewerRecords = this.reviewerRecords.map((reviewer) =>
            reviewer.reviewerId === reviewerId ? { ...reviewer, selected: checked } : reviewer
        );
    }

    async handleSaveReviewers() {
        if (this.selectedReviewerIds.size === 0) {
            this.showToast('Error', 'Please select at least one reviewer.', 'error');
            return;
        }
        this.reviewerLoading = true;
        try {
            await addReviewersToProposal({
                proposalId: this._recordId,
                reviewerIds: Array.from(this.selectedReviewerIds)
            });
            this.showToast('Success', 'Reviewer(s) added successfully.', 'success');
            this.showAddReviewerModal = false;
            await this.loadData();
        } catch (e) {
            this.showToast('Error', this.getErrorMessage(e), 'error');
        } finally {
            this.reviewerLoading = false;
        }
    }

    handleCloseAddReviewerModal() {
        this.showAddReviewerModal = false;
        this.reviewerRecords = [];
        this.selectedReviewerIds = new Set();
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

    get reviewerDisablePrevious() {
        return this.reviewerLoading || this.reviewerCurrentPage <= 1;
    }

    get reviewerDisableNext() {
        return this.reviewerLoading || this.reviewerCurrentPage >= this.reviewerTotalPages;
    }

    get reviewerStartRecord() {
        return this.reviewerTotalRecords === 0 ? 0 : (this.reviewerCurrentPage - 1) * PAGE_SIZE + 1;
    }

    get reviewerEndRecord() {
        return Math.min(this.reviewerCurrentPage * PAGE_SIZE, this.reviewerTotalRecords);
    }

    get disableSaveReviewers() {
        return this.reviewerLoading || this.selectedReviewerIds.size === 0;
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
        return error?.body?.message || error?.message || 'Something went wrong while processing the request.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}