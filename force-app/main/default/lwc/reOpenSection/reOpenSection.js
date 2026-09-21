import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getSchemeSectionsForProposal from '@salesforce/apex/ProposalApplicantDetailsController.getSchemeSectionsForProposal';
import reopenSchemeSections from '@salesforce/apex/ProposalApplicantDetailsController.reopenSchemeSections';

export default class ReOpenSection extends LightningElement {
    _recordId;
    isLoadingSections = false;
    isSaving = false;
    sectionRecords = [];
    selectedSectionIds = new Set();
    sectionReasons = new Map();

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.loadSections();
        }
    }

    @wire(CurrentPageReference)
    wiredPageReference(pageReference) {
        const pageRecordId = pageReference?.state?.c__recordId || pageReference?.state?.recordId;
        if (pageRecordId && !this._recordId) {
            this.recordId = pageRecordId;
        }
    }

    get sections() {
        return this.sectionRecords.map((section) => {
            const reopenStatus = section.Reopen_Status__c || '';
            const isAlreadyReopened = reopenStatus.toLowerCase() === 'reopen';
            const isSelected = !isAlreadyReopened && this.selectedSectionIds.has(section.Id);
            return {
                key: section.Id,
                sectionName: section.Section_Name__c || section.Name,
                dataFilledLabel: section.Data_Filled_Successfully__c ? 'Yes' : 'No',
                reopenStatusLabel: reopenStatus || '—',
                isDisabled: isAlreadyReopened,
                isSelected,
                reason: this.sectionReasons.get(section.Id) ?? (section.Re_Opening_Reason__c || ''),
                isReasonDisabled: isAlreadyReopened || !isSelected
            };
        });
    }

    get hasSections() {
        return this.sectionRecords.length > 0;
    }

    get showEmptyState() {
        return !this.isLoadingSections && !this.hasSections;
    }

    async loadSections() {
        this.isLoadingSections = true;
        this.selectedSectionIds = new Set();
        this.sectionReasons = new Map();
        try {
            this.sectionRecords = await getSchemeSectionsForProposal({ proposalId: this._recordId });
        } catch (e) {
            this.sectionRecords = [];
            this.showToast('Error', this.getErrorMessage(e), 'error');
        } finally {
            this.isLoadingSections = false;
        }
    }

    handleToggleSection(event) {
        const id = event.currentTarget.dataset.id;
        const isChecked = event.target.checked;
        const updated = new Set(this.selectedSectionIds);
        if (isChecked) {
            updated.add(id);
        } else {
            updated.delete(id);
        }
        this.selectedSectionIds = updated;
    }

    handleReasonChange(event) {
        const id = event.currentTarget.dataset.id;
        const updated = new Map(this.sectionReasons);
        updated.set(id, event.target.value);
        this.sectionReasons = updated;
    }

    async handleReopenSelected() {
        if (this.selectedSectionIds.size === 0) {
            this.showToast('Error', 'Select at least one section to reopen.', 'error');
            return;
        }
        const sectionRequests = Array.from(this.selectedSectionIds).map((sectionId) => ({
            sectionId,
            reason: (this.sectionReasons.get(sectionId) || '').trim()
        }));
        if (sectionRequests.some((req) => !req.reason)) {
            this.showToast('Error', 'Enter a reopening reason for every selected section.', 'error');
            return;
        }
        this.isSaving = true;
        try {
            await reopenSchemeSections({ sectionRequests });
            this.showToast('Success', 'Selected sections have been reopened.', 'success');
            await this.loadSections();
            this.dispatchEvent(new CustomEvent('save'));
        } catch (e) {
            this.showToast('Error', this.getErrorMessage(e), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        return error?.body?.message || error?.message || 'Something went wrong.';
    }
}