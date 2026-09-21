import { LightningElement, wire, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CurrentPageReference } from 'lightning/navigation';

import getCommitteeMasters from '@salesforce/apex/AssignCommitteeController.getCommitteeMasters';
import getTypePicklistValues from '@salesforce/apex/AssignCommitteeController.getTypePicklistValues';
import cloneSelectedMasters from '@salesforce/apex/AssignCommitteeController.cloneSelectedMasters';

export default class AssignCommitteeAction extends LightningElement {

    @api recordId;

    masterRows = [];
    typeOptions = [];
    selectAll = false;

    isLoading = true;
    isSaving = false;
    hasResizedModal = false;
    hasLoaded = false;

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (!this.recordId && currentPageReference) {
            const fromAttributes = currentPageReference.attributes?.recordId;
            const fromState = currentPageReference.state?.recordId;
            const fromStateC = currentPageReference.state?.c__recordId;
            this.recordId = fromAttributes || fromState || fromStateC;
        }
        if (this.recordId && !this.hasLoaded) {
            this.hasLoaded = true;
            this.loadData();
        }
    }

    connectedCallback() {
        if (this.recordId && !this.hasLoaded) {
            this.hasLoaded = true;
            this.loadData();
        }
    }

    async loadData() {
        if (!this.recordId) {
            return;
        }
        this.isLoading = true;
        console.log('AssignCommitteeAction loadData recordId:', this.recordId);
        try {
            const [rows, typeOpts] = await Promise.all([
                getCommitteeMasters({ recordId: this.recordId }),
                getTypePicklistValues()
            ]);
            this.typeOptions = typeOpts.map((o) => ({ label: o.label, value: o.value }));
            this.masterRows = rows.map((r) => ({ ...r }));
            console.log('AssignCommitteeAction masterRows loaded:', this.masterRows.length, JSON.parse(JSON.stringify(this.masterRows)));
            this.selectAll = false;
        } catch (error) {
            console.error('AssignCommitteeAction loadData error:', error);
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    get noMasterRows() {
        return !this.isLoading && this.masterRows.length === 0;
    }

    get masterTabLabel() {
        return `Committee Master Records (${this.masterRows.length})`;
    }

    handleSelectAll(event) {
        const checked = event.target.checked;
        this.selectAll = checked;
        this.masterRows = this.masterRows.map((row) =>
            row.alreadyAdded ? row : { ...row, selected: checked }
        );
    }

    handleRowToggle(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        console.log('AssignCommitteeAction rowToggle:', id, checked);
        this.masterRows = this.masterRows.map((row) =>
            row.masterId === id ? { ...row, selected: checked } : row
        );
        const selectableRows = this.masterRows.filter((row) => !row.alreadyAdded);
        this.selectAll = selectableRows.length > 0 && selectableRows.every((row) => row.selected);
    }

    handleTypeChange(event) {
        const id = event.target.dataset.id;
        const value = event.detail.value;
        console.log('AssignCommitteeAction typeChange:', id, value);
        this.masterRows = this.masterRows.map((row) =>
            row.masterId === id ? { ...row, typePicklist: value } : row
        );
    }

    handleReviewChange(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        console.log('AssignCommitteeAction reviewChange:', id, checked);
        this.masterRows = this.masterRows.map((row) =>
            row.masterId === id ? { ...row, isCommitteeReview: checked } : row
        );
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleSave() {
        const payload = this.masterRows
            .filter((r) => r.selected && !r.alreadyAdded)
            .map((r) => ({
                masterId: r.masterId,
                typePicklist: r.typePicklist,
                isCommitteeReview: r.isCommitteeReview
            }));

        console.log('AssignCommitteeAction save payload:', JSON.parse(JSON.stringify(payload)));

        if (!payload.length) {
            this.showToast('Nothing selected', 'Select at least one committee master to clone.', 'warning');
            return;
        }

        this.isSaving = true;
        try {
            const count = await cloneSelectedMasters({
                recordId: this.recordId,
                selectedRows: payload
            });

            this.showToast('Success', `${count} Committee Member(s) created.`, 'success');
            this.dispatchEvent(new CloseActionScreenEvent());

            eval("$A.get('e.force:refreshView').fire();");
        } catch (error) {
            console.error('AssignCommitteeAction save error:', error);
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    getErrorMessage(error) {
        return error && error.body && error.body.message ? error.body.message : 'Unknown error occurred';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    renderedCallback() {
        // Quick Action screens render inside a fixed-width .slds-modal__container
        // that lives outside this component's shadow DOM (in the parent page),
        // so we widen it directly via the global document the first time we render.
        if (this.hasResizedModal) {
            return;
        }
        const modal = document.querySelector('.slds-modal__container');
        if (modal) {
            modal.style.width = '95vw';
            modal.style.maxWidth = '95vw';
            this.hasResizedModal = true;
        }
    }
}