import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getResponseSummary from '@salesforce/apex/GrantTeamResponseSummaryController.getResponseSummary';

const STATUS_CLASS_BY_VALUE = {
    Eligible: 'member-status member-status_eligible',
    'Not Eligible': 'member-status member-status_not-eligible',
    'Not Submitted': 'member-status member-status_pending'
};

export default class GrantTeamResponseSummary extends LightningElement {
    _recordId;
    summary = { stages: [] };
    error;
    isLoading = false;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.loadSummary();
        }
    }

    @wire(CurrentPageReference)
    wiredPageReference(pageRef) {
        if (!this._recordId && pageRef) {
            const id = (pageRef.attributes && pageRef.attributes.recordId) ||
                (pageRef.state && pageRef.state.recordId);
            if (id) {
                this._recordId = id;
                this.loadSummary();
            }
        }
    }

    loadSummary() {
        if (!this._recordId) {
            return;
        }
        this.isLoading = true;
        this.error = undefined;
        this.summary = { stages: [] };
        getResponseSummary({ proposalId: this._recordId })
            .then((result) => {
                const stages = (result?.stages || []).map((stage) => {
                    const isComplete = stage.answeredCount === stage.totalCount && stage.totalCount > 0;
                    return {
                        ...stage,
                        headerIcon: 'utility:description',
                        cardClass: `gts-stage-card ${stage.themeClass || ''}`.trim(),
                        summaryBadgeClass: isComplete
                            ? 'stage-summary-badge stage-summary-badge_complete'
                            : 'stage-summary-badge stage-summary-badge_pending',
                        summaryBadgeIcon: isComplete ? 'utility:check' : 'utility:clock',
                        members: (stage.members || []).map((member) => ({
                            ...member,
                            statusClass: STATUS_CLASS_BY_VALUE[member.status] || 'member-status'
                        })),
                        rows: (stage.rows || []).map((row) => ({
                            ...row,
                            answers: (row.answers || []).map((cell) => ({
                                ...cell,
                                cellClass: cell.isYes
                                    ? 'answer-pill answer-pill_yes'
                                    : cell.isNo
                                    ? 'answer-pill answer-pill_no'
                                    : cell.isAnswered
                                    ? 'answer-pill answer-pill_text'
                                    : 'answer-pill answer-pill_pending',
                                tdClass: cell.isAnswered
                                    ? 'gts-td gts-td_member gts-td_member-wrap'
                                    : 'gts-td gts-td_member'
                            }))
                        }))
                    };
                });
                this.summary = { ...result, stages };
            })
            .catch((err) => {
                this.error = err.body?.message || err.message || 'Unknown error';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
}