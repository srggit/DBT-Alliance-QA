import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPeerEvaluations from '@salesforce/apex/PeerEvaluationMatrixController.getPeerEvaluations';
import saveCommitteeDecision from '@salesforce/apex/PeerEvaluationMatrixController.saveCommitteeDecision';

export default class PeerEvaluationMatrix extends LightningElement {
    _recordId;
    isLoading = false;
    error;
    reviewers = [];
    isSavingDecision = false;
    showRejectionReason = false;
    rejectionReason = '';
    showFeedbackSummary = false;
    feedbackSummary = '';

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
            this.reviewers = await getPeerEvaluations({ proposalId: this._recordId });
        } catch (e) {
            this.error = e?.body?.message || e?.message || 'Unable to load Peer Evaluation responses.';
            this.reviewers = [];
        } finally {
            this.isLoading = false;
        }
    }

    get hasData() {
        return !this.isLoading && !this.error && this.reviewers && this.reviewers.length > 0;
    }

    get showNoData() {
        return !this.isLoading && !this.error && (!this.reviewers || this.reviewers.length === 0);
    }

    get reviewerColumns() {
        return (this.reviewers || []).map((reviewer) => ({
            key: reviewer.mappingId,
            label: reviewer.reviewerName || 'Unnamed Reviewer'
        }));
    }

    get reviewerColumnCount() {
        return this.reviewerColumns.length;
    }

    get totalColumns() {
        return this.reviewerColumnCount + 1;
    }

    // Rows are the distinct Questions, in first-seen order across all reviewers - the same
    // "column-per-reviewer, row-per-item" transposition reviewerRatingMatrix.js uses for
    // Scheme_Section__c, applied here to Peer_Evaluation__c's Question/Answer pairs instead.
    get questionRows() {
        const orderedQuestions = [];
        (this.reviewers || []).forEach((reviewer) => {
            (reviewer.answers || []).forEach((qa) => {
                if (!orderedQuestions.some((q) => q.question === qa.question)) {
                    orderedQuestions.push({ question: qa.question, description: qa.description });
                }
            });
        });

        return orderedQuestions.map((q, index) => ({
            key: 'q-' + index,
            question: q.question,
            description: q.description,
            cells: (this.reviewers || []).map((reviewer) => {
                const match = (reviewer.answers || []).find((qa) => qa.question === q.question);
                return {
                    key: reviewer.mappingId + '-' + index,
                    value: match?.answer || ''
                };
            })
        }));
    }

    // First click on Reject just reveals the Reason for Rejection field - the actual
    // rejection only saves once handleConfirmRejection runs with a non-blank reason.
    handleReject() {
        this.showRejectionReason = true;
    }

    handleCancelRejection() {
        this.showRejectionReason = false;
        this.rejectionReason = '';
    }

    handleRejectionReasonChange(event) {
        this.rejectionReason = event.target.value;
    }

    handleConfirmRejection() {
        if (!this.rejectionReason || !this.rejectionReason.trim()) {
            this.showToast('Error', 'Reason for Rejection is required.', 'error');
            return;
        }
        this.saveDecision('Reject');
    }

    // Same reveal-then-confirm shape as Reject above - the first click just reveals the
    // Reviewer Feedback Summary field - the actual save only happens once
    // handleConfirmProcessToCommittee runs with a non-blank summary.
    handleProcessToCommittee() {
        this.showFeedbackSummary = true;
    }

    handleCancelProcessToCommittee() {
        this.showFeedbackSummary = false;
        this.feedbackSummary = '';
    }

    handleFeedbackSummaryChange(event) {
        this.feedbackSummary = event.target.value;
    }

    handleConfirmProcessToCommittee() {
        if (!this.feedbackSummary || !this.feedbackSummary.trim()) {
            this.showToast('Error', 'Reviewer Feedback Summary is required.', 'error');
            return;
        }
        this.saveDecision('ProcessToCommittee');
    }

    async saveDecision(decision) {
        if (!this._recordId) {
            return;
        }
        this.isSavingDecision = true;
        try {
            await saveCommitteeDecision({
                proposalId: this._recordId,
                decision,
                rejectionReason: decision === 'Reject' ? this.rejectionReason : null,
                reviewerFeedbackSummary: decision === 'ProcessToCommittee' ? this.feedbackSummary : null
            });
            const message = decision === 'Reject' ? 'Proposal Rejected.' : 'Proposal moved to Committee Review.';
            this.showToast('Success', message, 'success');
            this.showRejectionReason = false;
            this.rejectionReason = '';
            this.showFeedbackSummary = false;
            this.feedbackSummary = '';
            this.dispatchEvent(new CustomEvent('close'));
        } catch (e) {
            this.showToast('Error', e?.body?.message || e?.message || 'Unable to save decision.', 'error');
        } finally {
            this.isSavingDecision = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}