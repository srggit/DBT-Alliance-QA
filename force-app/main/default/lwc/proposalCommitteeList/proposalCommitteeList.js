import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProposalCommitteeRecords from '@salesforce/apex/ProposalCommitteeListController.getProposalCommitteeRecords';
import updateCommitteeRows from '@salesforce/apex/ProposalCommitteeListController.updateCommitteeRows';
import getCommitteeMasters from '@salesforce/apex/ProposalCommitteeListController.getCommitteeMasters';
import addCommitteeMasters from '@salesforce/apex/ProposalCommitteeListController.addCommitteeMasters';

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

    // "Add" modal state: every Committee Master, the ones ticked (id -> chosen type).
    showAddModal = false;
    isMastersLoading = false;
    isAdding = false;
    masters = [];
    mastersError;
    selectedMasters = {};

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

    // typeEdits holds the pending change per row: { type, committeeReviewer } (only edited keys).
    get rows() {
        return this.records.map((rec) => {
            const edit = this.typeEdits[rec.id] || {};
            return {
                key: rec.id,
                memberName: rec.memberName || '—',
                type: edit.type !== undefined ? edit.type : rec.type,
                typeOptions: TYPE_OPTIONS,
                status: rec.status || '—',
                committeeReviewer: edit.committeeReviewer !== undefined ? edit.committeeReviewer : !!rec.committeeReviewer,
                reviewerResponse: rec.reviewerResponse || '—',
                conflictStatus: rec.conflictStatus || '—',
                overallScore: rec.overallScore != null ? rec.overallScore : '—',
                rowClass: rec.status === 'Submitted' ? 'pcl-row_submitted' : ''
            };
        });
    }

    get showActions() {
        return !this.isLoading && !this.error;
    }

    get hasChanges() {
        return Object.keys(this.typeEdits).length > 0;
    }

    get saveDisabled() {
        return !this.hasChanges || this.isSaving;
    }

    handleTypeChange(event) {
        this.recordEdit(event.currentTarget.dataset.id, 'type', event.detail.value);
    }

    handleReviewerChange(event) {
        this.recordEdit(event.currentTarget.dataset.id, 'committeeReviewer', event.target.checked);
    }

    // Stores the edit, or drops it again when it puts the field back to its saved value.
    recordEdit(recordId, field, newValue) {
        const original = this.records.find((rec) => rec.id === recordId);
        if (!original) {
            return;
        }
        const originalValue = field === 'committeeReviewer' ? !!original.committeeReviewer : original.type;
        const rowEdit = { ...(this.typeEdits[recordId] || {}) };
        if (originalValue === newValue) {
            delete rowEdit[field];
        } else {
            rowEdit[field] = newValue;
        }
        const edits = { ...this.typeEdits };
        if (Object.keys(rowEdit).length === 0) {
            delete edits[recordId];
        } else {
            edits[recordId] = rowEdit;
        }
        this.typeEdits = edits;
    }

    async handleSave() {
        if (!this.hasChanges) {
            return;
        }
        this.isSaving = true;
        try {
            // Send the full row state (edited value or the saved one) for every edited row.
            const updates = Object.keys(this.typeEdits).map((id) => {
                const original = this.records.find((rec) => rec.id === id);
                const edit = this.typeEdits[id];
                return {
                    id,
                    type: edit.type !== undefined ? edit.type : original.type,
                    committeeReviewer:
                        edit.committeeReviewer !== undefined ? edit.committeeReviewer : !!original.committeeReviewer
                };
            });
            await updateCommitteeRows({ updatesJson: JSON.stringify(updates) });
            this.typeEdits = {};
            await refreshApex(this.wiredResult);
            this.showToast('Success', 'Committee members updated.', 'success');
        } catch (e) {
            this.showToast('Error', e?.body?.message || e?.message || 'Unable to save changes.', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    // The host modal (myEligibilityChecks) closes on this event.
    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    async handleOpenAdd() {
        this.selectedMasters = {};
        this.mastersError = undefined;
        this.showAddModal = true;
        this.isMastersLoading = true;
        try {
            this.masters = await getCommitteeMasters({ proposalId: this.recordId });
        } catch (e) {
            this.masters = [];
            this.mastersError = e?.body?.message || e?.message || 'Unable to load Committee Masters.';
        } finally {
            this.isMastersLoading = false;
        }
    }

    handleCloseAdd() {
        this.closeAddDialog();
    }

    // Back to the committee list.
    closeAddDialog() {
        this.showAddModal = false;
        this.selectedMasters = {};
    }

    get masterRows() {
        return this.masters.map((master) => {
            const selected = this.selectedMasters[master.id] !== undefined;
            return {
                key: master.id,
                name: master.name || '—',
                email: master.email || '—',
                organization: master.organization || '—',
                alreadyAdded: master.alreadyAdded,
                selected,
                type: selected ? this.selectedMasters[master.id].type : undefined,
                committeeReviewer: selected ? this.selectedMasters[master.id].committeeReviewer : false,
                typeDisabled: master.alreadyAdded,
                rowClass: master.alreadyAdded ? 'pcl-row_added' : ''
            };
        });
    }

    get hasMasters() {
        return !this.isMastersLoading && !this.mastersError && this.masters.length > 0;
    }

    get selectedCount() {
        return Object.keys(this.selectedMasters).length;
    }

    get addSaveDisabled() {
        return this.selectedCount === 0 || this.isAdding;
    }

    get typeOptions() {
        return TYPE_OPTIONS;
    }

    handleMasterSelect(event) {
        const masterId = event.currentTarget.dataset.id;
        const selected = { ...this.selectedMasters };
        if (event.target.checked) {
            selected[masterId] = { type: 'DCM', committeeReviewer: false };
        } else {
            delete selected[masterId];
        }
        this.selectedMasters = selected;
    }

    // Picking a Type or ticking Reviewer on an unticked row ticks the row automatically
    // (selectedMasters drives all three).
    handleMasterTypeChange(event) {
        this.updateSelection(event.currentTarget.dataset.id, { type: event.detail.value });
    }

    handleMasterReviewerChange(event) {
        this.updateSelection(event.currentTarget.dataset.id, { committeeReviewer: event.target.checked });
    }

    updateSelection(masterId, changes) {
        const current = this.selectedMasters[masterId] || { type: 'DCM', committeeReviewer: false };
        this.selectedMasters = { ...this.selectedMasters, [masterId]: { ...current, ...changes } };
    }

    async handleAddSave() {
        if (this.selectedCount === 0) {
            return;
        }
        this.isAdding = true;
        try {
            const selections = Object.keys(this.selectedMasters).map((masterId) => ({
                masterId,
                type: this.selectedMasters[masterId].type,
                committeeReviewer: this.selectedMasters[masterId].committeeReviewer
            }));
            await addCommitteeMasters({ proposalId: this.recordId, selectionsJson: JSON.stringify(selections) });
            this.closeAddDialog();
            await refreshApex(this.wiredResult);
            this.showToast('Success', 'Committee members added.', 'success');
        } catch (e) {
            this.showToast('Error', e?.body?.message || e?.message || 'Unable to add committee members.', 'error');
        } finally {
            this.isAdding = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}