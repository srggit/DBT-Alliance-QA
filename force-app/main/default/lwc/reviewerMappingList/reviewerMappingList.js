import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getReviewerMappingsForProposal from '@salesforce/apex/ReviewerMappingController.getReviewerMappingsForProposal';

export default class ReviewerMappingList extends LightningElement {
    _recordId;
    isLoading = false;
    mappingRecords = [];

    @api applicationStage;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.loadMappings();
        }
    }

    @wire(CurrentPageReference)
    wiredPageReference(pageReference) {
        const pageRecordId = pageReference?.state?.c__recordId || pageReference?.state?.recordId;
        if (pageRecordId && !this._recordId) {
            this.recordId = pageRecordId;
        }
    }

    async loadMappings() {
        this.isLoading = true;
        try {
            this.mappingRecords = await getReviewerMappingsForProposal({
                proposalId: this._recordId,
                applicationStage: this.applicationStage
            });
        } catch (e) {
            this.mappingRecords = [];
            this.showToast('Error', this.getErrorMessage(e), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    get mappings() {
        return this.mappingRecords.map((rm) => ({
            key: rm.Id,
            reviewerFullName: rm.Reviewer_Name__c || '—',
            reviewerType: rm.Reviewer_Type__c || '—',
            applicationStage: rm.Application_Stages__c || '—',
            status: rm.Status__c || '—',
            rowClass: rm.Status__c === 'Submitted' ? 'rml-row rml-row_submitted' : 'rml-row',
            evaluationSubmissionDate: this.formatDate(rm.Evaluation_Submission_Date__c),
            escalationTaskCreated: rm.Escalation_Task_Created__c ? 'Yes' : 'No',
            invitationResponded: rm.Invitation_Responded__c ? 'Yes' : 'No',
            invitationRespondedDate: this.formatDate(rm.Invitation_Responded_Date__c),
            invitationSentDate: this.formatDate(rm.Invitation_Sent_Date__c),
            overallScore: rm.Overall_Score__c != null ? rm.Overall_Score__c : '—'
        }));
    }

    get hasMappings() {
        return this.mappingRecords.length > 0;
    }

    get showEmptyState() {
        return !this.isLoading && !this.hasMappings;
    }

    formatDate(dateStr) {
        if (!dateStr) {
            return '—';
        }
        const parts = dateStr.split('-');
        if (parts.length !== 3) {
            return dateStr;
        }
        const parsed = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
        return parsed.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: '2-digit' });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        return error?.body?.message || error?.message || 'Something went wrong.';
    }
}