import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getReviewerSectionResponses from '@salesforce/apex/ReviewerSectionResponseController.getReviewerSectionResponses';
import saveFullEligibilityDecision from '@salesforce/apex/ReviewerSectionResponseController.saveFullEligibilityDecision';
import getPrelimReviewerEligibilityStatus from '@salesforce/apex/ReviewerSectionResponseController.getPrelimReviewerEligibilityStatus';

export default class ReviewerRatingMatrix extends LightningElement {
    _recordId;
    isLoading = false;
    error;
    reviewers = [];
    feedbackSummary = '';
    isSavingDecision = false;
    showRejectionReason = false;
    rejectionReason = '';
    prelimReviewerEligibilityStatus;
    @api hideDecisionPanel = false;

    get showDecisionPanel() {
        return !this.hideDecisionPanel;
    }

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
            this.reviewers = await getReviewerSectionResponses({ proposalId: this._recordId });
            this.prelimReviewerEligibilityStatus = await getPrelimReviewerEligibilityStatus({ proposalId: this._recordId });
        } catch (e) {
            this.error = e?.body?.message || e?.message || 'Unable to load reviewer ratings.';
            this.reviewers = [];
        } finally {
            this.isLoading = false;
        }
    }

    // Reject/Eligible for Full stay visible at all times, but only become actionable
    // once Prelim_Reviewer_Eligibility_Status__c is 'Submitted' - the same condition
    // the Shortlisting tab itself is already filtered on.
    get isDecisionEnabled() {
        return this.prelimReviewerEligibilityStatus === 'Submitted';
    }

    get isDecisionDisabled() {
        return this.isSavingDecision || !this.isDecisionEnabled;
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
            label: reviewer.reviewerName || 'Unnamed Reviewer',
            applicationStage: reviewer.applicationStage || '—',
            reviewerType: reviewer.reviewerType || '—',
            status: reviewer.status || '—'
        }));
    }

    get reviewerColumnCount() {
        return this.reviewerColumns.length;
    }

    // Top group-header label - "Prelim Reviewers"/"Full Reviewers" when every reviewer
    // shares one stage (the common case, since this component is stage-scoped by the
    // Proposal itself), falling back to plain "Reviewers" if that's ever not true.
    get reviewerGroupHeaderLabel() {
        const stages = new Set(this.reviewerColumns.map((col) => col.applicationStage).filter(Boolean));
        if (stages.size === 1) {
            const stage = stages.values().next().value;
            if (stage === 'Prelims') {
                return 'Prelim Reviewers';
            }
            if (stage === 'Full') {
                return 'Full Reviewers';
            }
        }
        return 'Reviewers';
    }

    get totalColumns() {
        return this.reviewerColumnCount + 1;
    }

    get sectionRows() {
        const orderedNames = [];
        (this.reviewers || []).forEach((reviewer) => {
            (reviewer.sections || []).forEach((section) => {
                if (!orderedNames.includes(section.sectionName)) {
                    orderedNames.push(section.sectionName);
                }
            });
        });

        return orderedNames.map((name) => ({
            key: name,
            sectionName: name,
            cells: (this.reviewers || []).map((reviewer) => {
                const match = (reviewer.sections || []).find((section) => section.sectionName === name);
                return {
                    key: reviewer.mappingId + '-' + name,
                    value: match?.overallComments || ''
                };
            })
        }));
    }

    get overallCommentsCells() {
        return (this.reviewers || []).map((reviewer) => ({
            key: reviewer.mappingId,
            value: reviewer.overallComments || ''
        }));
    }

    get overallRatingCells() {
        return (this.reviewers || []).map((reviewer) => ({
            key: reviewer.mappingId,
            value: reviewer.overallScore || ''
        }));
    }

    get averageRating() {
        const scores = (this.reviewers || [])
            .map((reviewer) => parseFloat(reviewer.overallScore))
            .filter((score) => !isNaN(score));
        if (scores.length === 0) {
            return '—';
        }
        const total = scores.reduce((sum, value) => sum + value, 0);
        return (total / scores.length).toFixed(2);
    }

    handleFeedbackChange(event) {
        this.feedbackSummary = event.target.value;
    }

    handleEligibleForFull() {
        if (!this.feedbackSummary || !this.feedbackSummary.trim()) {
            this.showToast('Error', 'Grants Feedback Summary is required.', 'error');
            return;
        }
        this.saveDecision('Eligible');
    }

    // First click on Rejected just reveals the Reason for Rejection field - the actual
    // rejection only saves once handleConfirmRejection runs with a non-blank reason.
    handleRejectedClick() {
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
        this.saveDecision('Not Eligible');
    }

    async saveDecision(decision) {
        if (!this._recordId) {
            return;
        }
        this.isSavingDecision = true;
        try {
            await saveFullEligibilityDecision({
                proposalId: this._recordId,
                decision,
                feedbackSummary: this.feedbackSummary,
                reasonForRejection: decision === 'Not Eligible' ? this.rejectionReason : null
            });
            this.showToast('Success', `Proposal marked ${decision} for Full.`, 'success');
            this.showRejectionReason = false;
            this.rejectionReason = '';
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