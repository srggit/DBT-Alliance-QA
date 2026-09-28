import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProposalCommitteeRecords from '@salesforce/apex/ProposalCommitteeListController.getProposalCommitteeRecords';
import updateCommitteeTypes from '@salesforce/apex/ProposalCommitteeListController.updateCommitteeTypes';

const TYPE_OPTIONS = [
    { label: 'Chair', value: 'Chair' },
    { label: 'Co-chair', value: 'Co-chair' },
    { label: 'DCM', value: 'DCM' }
];

export default class ProposalCommitteeList extends LightningElement {
    @api recordId;

    records = [];
    isLoading = true;
    error;
    isSaving = false;
    wiredResult;
    typeEdits = {};

    @wire(getProposalCommitteeRecords, { proposalId: '$recordId' })
    wiredCommitteeRecords(result) {
        this.wiredResult = result;
        this.isLoading = false;
        const { data, error } = result;
        if (data) {
            this.records = data;
            this.error = undefined;
        } else if (error) {
            this.records = [];
            this.error = error?.body?.message || error?.message || 'Unable to load Proposal Committee records.';
        }
    }

    get hasRecords() {
        return !this.isLoading && !this.error && this.records.length > 0;
    }

    get rows() {
        return this.records.map((rec) => ({
            key: rec.id,
            memberName: rec.memberName || '—',
            type: this.typeEdits[rec.id] !== undefined ? this.typeEdits[rec.id] : rec.type,
            typeOptions: TYPE_OPTIONS,
            status: rec.status || '—',
            committeeReviewerLabel: rec.committeeReviewer ? 'Yes' : 'No',
            reviewerResponse: rec.reviewerResponse || '—',
            conflictStatus: rec.conflictStatus || '—',
            overallScore: rec.overallScore != null ? rec.overallScore : '—'
        }));
    }

    get hasChanges() {
        return Object.keys(this.typeEdits).length > 0;
    }

    get saveDisabled() {
        return !this.hasChanges || this.isSaving;
    }

    handleTypeChange(event) {
        const recordId = event.currentTarget.dataset.id;
        const newValue = event.detail.value;
        const original = this.records.find((rec) => rec.id === recordId);
        const edits = { ...this.typeEdits };
        if (original && original.type === newValue) {
            delete edits[recordId];
        } else {
            edits[recordId] = newValue;
        }
        this.typeEdits = edits;
    }

    async handleSave() {
        if (!this.hasChanges) {
            return;
        }
        this.isSaving = true;
        try {
            const updates = Object.keys(this.typeEdits).map((id) => ({ id, type: this.typeEdits[id] }));
            await updateCommitteeTypes({ updates });
            this.typeEdits = {};
            await refreshApex(this.wiredResult);
            this.showToast('Success', 'Committee Member type updated.', 'success');
        } catch (e) {
            this.showToast('Error', e?.body?.message || e?.message || 'Unable to save changes.', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}