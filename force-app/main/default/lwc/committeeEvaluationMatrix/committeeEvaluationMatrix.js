import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCommitteeEvaluations from '@salesforce/apex/CommitteeEvaluationMatrixController.getCommitteeEvaluations';
import saveCommitteeDecision from '@salesforce/apex/CommitteeEvaluationMatrixController.saveCommitteeDecision';

export default class CommitteeEvaluationMatrix extends LightningElement {
    _recordId;
    isLoading = false;
    isSavingDecision = false;
    showRejectionReason = false;
    feedbackSummary = '';
    rejectionReason = '';
    error;
    members = [];

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
            this.members = await getCommitteeEvaluations({ proposalId: this._recordId });
        } catch (e) {
            this.error = e?.body?.message || e?.message || 'Unable to load Committee Evaluation responses.';
            this.members = [];
        } finally {
            this.isLoading = false;
        }
    }

    handleFeedbackChange(event) {
        this.feedbackSummary = event.target.value;
    }

    handleRejectionReasonChange(event) {
        this.rejectionReason = event.target.value;
    }

    // First click on Reject just reveals the Reason for Rejection field - the rejection
    // only saves once handleConfirmRejection runs with a non-blank reason.
    handleRejectClick() {
        this.showRejectionReason = true;
    }

    handleCancelRejection() {
        this.showRejectionReason = false;
        this.rejectionReason = '';
    }

    handleConfirmRejection() {
        if (!this.rejectionReason || !this.rejectionReason.trim()) {
            this.showToast('Error', 'Reason for Rejection is required.', 'error');
            return;
        }
        this.saveDecision('Reject', 'Proposal rejected.');
    }

    handleProceed() {
        if (!this.feedbackSummary || !this.feedbackSummary.trim()) {
            this.showToast('Error', 'Committee Feedback Summary is required.', 'error');
            return;
        }
        this.saveDecision('Proceed', 'Proposal moved to Chair/Co-Chair stage.');
    }

    async saveDecision(decision, successMessage) {
        if (!this._recordId) {
            return;
        }
        this.isSavingDecision = true;
        try {
            await saveCommitteeDecision({
                proposalId: this._recordId,
                decision,
                feedbackSummary: this.feedbackSummary,
                reasonForRejection: decision === 'Reject' ? this.rejectionReason : null
            });
            this.showToast('Success', successMessage, 'success');
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

    activeTab = 'committee';

    get isCommitteeTab() {
        return this.activeTab === 'committee';
    }

    get isReviewersTab() {
        return this.activeTab === 'reviewers';
    }

    get bannerTitle() {
        return this.isReviewersTab ? 'Peer Evaluation Responses' : 'Committee Evaluation Responses';
    }

    get bannerSubtitle() {
        return this.isReviewersTab
            ? 'Compare Peer Evaluation question answers across all submitted Full-stage reviewers.'
            : 'Compare Committee Evaluation answers, grouped by section, across all submitted committee members.';
    }

    get committeeTabClass() {
        return 'cem-tab' + (this.isCommitteeTab ? ' cem-tab_active' : '');
    }

    get reviewersTabClass() {
        return 'cem-tab' + (this.isReviewersTab ? ' cem-tab_active' : '');
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    get showDecisionPanel() {
        return !this.isLoading && !this.error;
    }

    get hasData() {
        return !this.isLoading && !this.error && this.members && this.members.length > 0;
    }

    get showNoData() {
        return !this.isLoading && !this.error && (!this.members || this.members.length === 0);
    }

    get memberColumns() {
        return (this.members || []).map((member) => ({
            key: member.committeeId,
            label: member.memberName || 'Unnamed Member',
            status: member.status || '—'
        }));
    }

    get totalColumns() {
        return this.memberColumns.length + 1;
    }

    get memberCount() {
        return this.memberColumns.length;
    }

    // Sections (and, within each section, questions) are ordered by first appearance across
    // all members, the same "first-seen order" convention reviewerRatingMatrix.js and
    // peerEvaluationMatrix.js already use - just with an extra grouping level here, since
    // Committee_Member_Evaluation__c carries a real Section_Detail__c the Peer_Evaluation__c
    // object doesn't.
    get sections() {
        const sectionOrder = [];
        const questionsBySection = new Map();

        (this.members || []).forEach((member) => {
            (member.answers || []).forEach((qa) => {
                const sectionName = qa.section || 'General';
                if (!questionsBySection.has(sectionName)) {
                    questionsBySection.set(sectionName, []);
                    sectionOrder.push(sectionName);
                }
                const questions = questionsBySection.get(sectionName);
                if (!questions.some((q) => q === qa.question)) {
                    questions.push(qa.question);
                }
            });
        });

        return sectionOrder.map((sectionName, sIndex) => ({
            key: 'section-' + sIndex,
            sectionName,
            rows: questionsBySection.get(sectionName).map((question, qIndex) => ({
                key: 'section-' + sIndex + '-q-' + qIndex,
                question,
                cells: (this.members || []).map((member) => {
                    const match = (member.answers || []).find(
                        (qa) => (qa.section || 'General') === sectionName && qa.question === question
                    );
                    return {
                        key: member.committeeId + '-' + sIndex + '-' + qIndex,
                        value: match?.answer || ''
                    };
                })
            }))
        }));
    }
}