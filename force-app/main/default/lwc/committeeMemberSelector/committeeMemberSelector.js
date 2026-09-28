import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

import getActiveCommitteeMasters from '@salesforce/apex/CommitteeMemberController.getActiveCommitteeMasters';
import getTypePicklistValues from '@salesforce/apex/CommitteeMemberController.getTypePicklistValues';
import getMaxSequence from '@salesforce/apex/CommitteeMemberController.getMaxSequence';
import createCommitteeMembers from '@salesforce/apex/CommitteeMemberController.createCommitteeMembers';

const TYPE_CHAIR = 'Chair';
const TYPE_COCHAIR = 'Co-chair';
const TYPE_DCM = 'DCM';
const SINGLE_SEAT_TYPES = [TYPE_CHAIR, TYPE_COCHAIR];

export default class CommitteeMemberSelector extends LightningElement {
    @api recordId;

    masterRows = [];
    typeOptions = [];
    isLoadingMasters = true;
    isLoadingTypes = true;
    isSaving = false;
    error;
    selectAll = false;
    searchTerm = '';

    // masterIds in the order they were selected (click order), used to stamp Sequence__c
    selectionOrder = [];
    // highest Sequence__c already saved for this Yearly Scheme; new picks continue after it
    baseSequence = 0;

    get isLoading() {
        return this.isLoadingMasters || this.isLoadingTypes;
    }

    get noData() {
        return !this.isLoading && this.masterRows.length === 0;
    }

    get visibleRows() {
        const term = this.searchTerm.trim().toLowerCase();
        if (!term) {
            return this.masterRows;
        }
        return this.masterRows.filter(row => (row.fullName || '').toLowerCase().includes(term));
    }

    get hasVisibleRows() {
        return this.visibleRows.length > 0;
    }

    get noSearchResults() {
        return !this.noData && this.searchTerm.trim() && this.visibleRows.length === 0;
    }

    get createDisabled() {
        return this.isSaving || this.masterRows.filter(row => row.selected).length === 0;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
        // Header checkbox reflects the newly-visible subset, not the pre-search selection.
        const visibleSelectableRows = this.visibleRows.filter(row => !row.alreadyAdded);
        this.selectAll = visibleSelectableRows.length > 0 && visibleSelectableRows.every(row => row.selected);
    }

    // Reactive on recordId (same as wiredMasters below) - recordId isn't always populated
    // yet when connectedCallback() first runs on a quick-action screen, so an imperative
    // call there could silently run with recordId undefined and never retry.
    @wire(getMaxSequence, { yearlySchemeId: '$recordId' })
    wiredMaxSequence({ error, data }) {
        if (data !== undefined) {
            this.baseSequence = data || 0;
            this.renumberSelection();
        } else if (error) {
            console.error('Error loading max sequence:', error);
        }
    }

    @wire(getActiveCommitteeMasters, { yearlySchemeId: '$recordId' })
    wiredMasters({ error, data }) {
        this.isLoadingMasters = false;
        if (data) {
            this.masterRows = data.map(row => ({
                ...row,
                selected: false,
                // Already-added rows show their real, saved Sequence__c/Type__c; new rows
                // get numbered live as they're selected (see renumberSelection) and start blank.
                type: row.alreadyAdded ? row.existingType : '',
                sequenceNumber: row.alreadyAdded ? row.existingSequence : null
            }));
            this.error = undefined;
        } else if (error) {
            this.error = this.reduceErrors(error);
            this.masterRows = [];
            console.error(error);
        }
    }

    @wire(getTypePicklistValues)
    wiredTypes({ error, data }) {
        this.isLoadingTypes = false;
        if (data) {
            this.typeOptions = data.map(option => ({
                label: option.label,
                value: option.value
            }));
            this.error = undefined;
        } else if (error) {
            this.error = this.reduceErrors(error);
            this.typeOptions = [];
            console.error(error);
        }
    }

    // Scoped to the currently visible (search-filtered) rows only - rows hidden by the
    // search box keep whatever selection state they already had.
    handleSelectAll(event) {
        const checked = event.target.checked;
        this.selectAll = checked;
        const visibleIds = new Set(this.visibleRows.map(row => row.masterId));

        this.masterRows = this.masterRows.map(row => {
            if (row.alreadyAdded || !visibleIds.has(row.masterId)) {
                return row;
            }
            // Default newly-checked rows to DCM so the user only has to touch the
            // Type dropdown for the one Chair and one Co-chair they want to designate.
            const type = checked && !row.type ? TYPE_DCM : row.type;
            return { ...row, selected: checked, type: checked ? type : row.type };
        });

        // Select All has no individual click order, so fall back to table order (already
        // alphabetical). Hidden rows already in selectionOrder are left untouched.
        if (checked) {
            const alreadyOrdered = new Set(this.selectionOrder);
            const newlyChecked = this.visibleRows
                .filter(row => !row.alreadyAdded && !alreadyOrdered.has(row.masterId))
                .map(row => row.masterId);
            this.selectionOrder = [...this.selectionOrder, ...newlyChecked];
        } else {
            const visibleSelectableIds = new Set(
                this.visibleRows.filter(row => !row.alreadyAdded).map(row => row.masterId)
            );
            this.selectionOrder = this.selectionOrder.filter(id => !visibleSelectableIds.has(id));
        }
        this.renumberSelection();
    }

    handleRowSelect(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        this.masterRows = this.masterRows.map(row => {
            if (row.masterId !== id) {
                return row;
            }
            // Default to DCM on check so the user only has to touch the Type dropdown
            // for the one Chair and one Co-chair they want to designate.
            const type = checked && !row.type ? TYPE_DCM : row.type;
            return { ...row, selected: checked, type };
        });
        if (checked) {
            this.selectionOrder = [...this.selectionOrder, id];
        } else {
            this.selectionOrder = this.selectionOrder.filter(existingId => existingId !== id);
        }
        this.renumberSelection();
        // Scoped to visible rows so the header checkbox reflects the current search view.
        const visibleSelectableRows = this.visibleRows.filter(row => !row.alreadyAdded);
        this.selectAll = visibleSelectableRows.length > 0 && visibleSelectableRows.every(row => row.selected);
    }

    // Stamps sequenceNumber on every currently-selected row, in click order,
    // continuing after the highest Sequence__c already saved for this Yearly Scheme.
    // Already-added rows keep showing their real, saved existingSequence untouched.
    renumberSelection() {
        const sequenceByMasterId = new Map();
        this.selectionOrder.forEach((id, index) => {
            sequenceByMasterId.set(id, this.baseSequence + index + 1);
        });
        this.masterRows = this.masterRows.map(row => {
            if (row.alreadyAdded) {
                return { ...row, sequenceNumber: row.existingSequence };
            }
            return {
                ...row,
                sequenceNumber: sequenceByMasterId.has(row.masterId) ? sequenceByMasterId.get(row.masterId) : null
            };
        });
    }

    handleTypeChange(event) {
        const id = event.target.dataset.id;
        const value = event.detail.value;
        // Chair and Co-chair are single-seat: picking one for this row bumps whoever
        // currently holds it (among selected, non-locked rows) back down to DCM.
        const bumpOthers = SINGLE_SEAT_TYPES.includes(value);
        this.masterRows = this.masterRows.map(row => {
            if (row.masterId === id) {
                return { ...row, type: value };
            }
            if (bumpOthers && row.selected && !row.alreadyAdded && row.type === value) {
                return { ...row, type: TYPE_DCM };
            }
            return row;
        });
    }

    async handleCreate() {
        const selectedRows = this.masterRows.filter(row => row.selected);

        if (!selectedRows.length) {
            this.showToast('Warning', 'Select at least one committee member.', 'warning');
            return;
        }

        const missingType = selectedRows.some(row => !row.type);
        if (missingType) {
            this.showToast('Warning', 'Select a Type for every selected committee member.', 'warning');
            return;
        }

        const payload = selectedRows.map(row => ({
            masterId: row.masterId,
            typeValue: row.type,
            sequence: row.sequenceNumber
        }));

        console.log('payload =====> ', payload);

        this.isSaving = true;
        try {
            const count = await createCommitteeMembers({
                yearlySchemeId: this.recordId,
                selectedRowsJson: JSON.stringify(payload)
            });
            this.showToast('Success', `${count} Committee Member(s) created.`, 'success');
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceErrors(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return 'Unknown error occurred';
    }
}