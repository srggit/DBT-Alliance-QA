import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CurrentPageReference } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import getEligibilityChecklist from '@salesforce/apex/checkEligibiltyController.getEligibilityChecklist';
import saveEligibilityChecklist from '@salesforce/apex/checkEligibiltyController.saveEligibilityChecklist';

export default class CheckEligibilityComponent extends LightningElement {
    @api recordId;

    checklistItems = [];
    isLoading = false;
    isSaving = false;
    hasLoaded = false;
    pageRecordId;

    @wire(CurrentPageReference)
    wiredPageReference(currentPageReference) {
        if (currentPageReference) {
            this.pageRecordId =
                currentPageReference.attributes?.recordId ||
                currentPageReference.state?.recordId ||
                currentPageReference.state?.c__recordId;
            this.tryLoad();
        }
    }

    get yesNoOptions() {
        return [
            { label: 'Yes', value: 'Yes' },
            { label: 'No', value: 'No' }
        ];
    }

    get hasItems() {
        return this.checklistItems && this.checklistItems.length > 0;
    }

    get resolvedRecordId() {
        return this.recordId || this.pageRecordId || this.getRecordIdFromUrl();
    }

    getRecordIdFromUrl() {
        const url = window.location.href;
        const match = url.match(/\b([a-zA-Z0-9]{18}|[a-zA-Z0-9]{15})\b/);
        return match ? match[1] : undefined;
    }

    tryLoad() {
        if (this.hasLoaded || !this.resolvedRecordId) {
            return;
        }
        this.hasLoaded = true;
        console.log('proposal Id : ' + this.resolvedRecordId);
        this.loadChecklist();
    }

    connectedCallback() {
        this.tryLoad();
    }

    async loadChecklist() {
        const proposalId = this.resolvedRecordId;
        if (!proposalId) {
            return;
        }

        this.isLoading = true;
        try {
            const items = await getEligibilityChecklist({ proposalId });
            this.checklistItems = (items || [])
                .map((item) => ({
                    ...item,
                    isBoolean: item.Type__c === 'Boolean',
                    isLongText: item.Type__c === 'Long Text'
                }))
                .sort((a, b) => (a.isLongText === b.isLongText ? 0 : a.isLongText ? 1 : -1));
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleInputChange(event) {
        const id = event.currentTarget.dataset.id;
        const value =
            event.detail && event.detail.value !== undefined
                ? event.detail.value
                : event.target.value;

        this.checklistItems = this.checklistItems.map((item) =>
            item.Id === id ? { ...item, Answer__c: value } : item
        );
    }

    async handleSave() {
        if (!this.checklistItems || this.checklistItems.length === 0) {
            return;
        }

        this.isSaving = true;
        try {
            await saveEligibilityChecklist({ records: this.checklistItems, proposalId: this.resolvedRecordId });
            this.showToast('Success', 'Eligibility checklist saved.', 'success');
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceErrors(error) {
        let message = 'Unknown error';
        if (error && error.body && error.body.message) {
            message = error.body.message;
        } else if (error && error.message) {
            message = error.message;
        }
        return message;
    }
}