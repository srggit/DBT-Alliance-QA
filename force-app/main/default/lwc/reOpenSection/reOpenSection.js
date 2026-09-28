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
        // Read straight off the rendered inputs rather than the tracked
        // selectedSectionIds/sectionReasons state - that state is only updated by onchange
        // (fires on blur/Enter), so a checkbox ticked or a reason typed just before clicking
        // this button, without first leaving the field, could still read as unselected/blank
        // here even though it's visibly checked/filled on screen.
        const checkboxEls = Array.from(this.template.querySelectorAll('[data-role="reopen-checkbox"]'));
        const reasonEls = Array.from(this.template.querySelectorAll('[data-role="reopen-reason"]'));

        const reasonById = new Map();
        reasonEls.forEach((el) => reasonById.set(el.dataset.id, (el.value || '').trim()));

        const selectedIds = checkboxEls.filter((el) => el.checked).map((el) => el.dataset.id);

        if (selectedIds.length === 0) {
            this.showToast('Error', 'Select at least one section to reopen.', 'error');
            return;
        }

        const sectionRequests = selectedIds.map((sectionId) => ({
            sectionId,
            reason: reasonById.get(sectionId) || ''
        }));
        if (sectionRequests.some((req) => !req.reason)) {
            this.showToast('Error', 'Enter a reopening reason for every selected section.', 'error');
            return;
        }
        this.isSaving = true;
        try {
            // Sent as a JSON string, not the raw list - see reopenSchemeSections' doc comment
            // for why (the bare List<InnerWrapperClass> wire binding was dropping field values).
            await reopenSchemeSections({ sectionRequestsJson: JSON.stringify(sectionRequests) });
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