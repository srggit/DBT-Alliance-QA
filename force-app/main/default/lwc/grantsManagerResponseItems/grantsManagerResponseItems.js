import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CurrentPageReference } from 'lightning/navigation';
import getGrantTeamResponseItems from '@salesforce/apex/GrantTeamResponseItemsController.getGrantTeamResponseItems';
import saveGrantTeamResponseItems from '@salesforce/apex/GrantTeamResponseItemsController.saveGrantTeamResponseItems';

export default class GrantsManagerResponseItems extends LightningElement {
    @api recordId;

    responseItems = [];
    isLoading = false;
    isSaving = false;
    hasLoaded = false;
    pageRecordId;
    responseId;
    isSubmitted = false;

    get yesNoOptions() {
        return [
            { label: 'Yes', value: 'Yes' },
            { label: 'No', value: 'No' }
        ];
    }

    get hasItems() {
        return this.responseItems && this.responseItems.length > 0;
    }

    get resolvedRecordId() {
        return this.recordId || this.pageRecordId;
    }

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

    tryLoad() {
        if (this.hasLoaded || !this.resolvedRecordId) {
            return;
        }
        this.hasLoaded = true;
        this.loadResponseItems();
    }

    connectedCallback() {
        this.tryLoad();
    }

    async loadResponseItems() {
        const proposalId = this.resolvedRecordId;
        if (!proposalId) {
            return;
        }

        this.isLoading = true;
        try {
            const wrapper = await getGrantTeamResponseItems({ proposalId });
            this.responseId = wrapper?.responseId;
            this.isSubmitted = !!wrapper?.isSubmitted;
            this.responseItems = (wrapper?.items || [])
                .map((item) => ({
                    ...item,
                    isBoolean: item.Type__c === 'Boolean',
                    isLongText: item.Type__c === 'Long Text',
                    isRequired: item.Type__c !== 'Long Text' && !this.isSubmitted,
                    isDisabled: this.isSubmitted,
                    displayQuestion:
                        item.Display_Question__c ||
                        (typeof item.Question__c === 'string' ? item.Question__c : null) ||
                        item.Name
                }))
                .sort((a, b) => (a.isLongText === b.isLongText ? 0 : a.isLongText ? 1 : -1))
                .map((item, index) => ({
                    ...item,
                    rowNumber: index + 1,
                    isAnswered: !!item.Answer__c,
                    statusClass: item.Answer__c ? 'gmr-row-status gmr-row-status-filled' : 'gmr-row-status'
                }));
        } catch (error) {
            this.responseItems = [];
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleInputChange(event) {
        if (this.isSubmitted) {
            return;
        }
        const id = event.currentTarget.dataset.id;
        const value =
            event.detail && event.detail.value !== undefined
                ? event.detail.value
                : event.target.value;

        this.responseItems = this.responseItems.map((item) =>
            item.Id === id
                ? {
                      ...item,
                      Answer__c: value,
                      isAnswered: !!value,
                      statusClass: value ? 'gmr-row-status gmr-row-status-filled' : 'gmr-row-status'
                  }
                : item
        );

        const field = event.currentTarget;
        field.setCustomValidity(field.required && !value ? 'This response is required.' : '');
        field.reportValidity();
    }

    async handleSave() {
        if (this.isSubmitted || !this.responseItems || this.responseItems.length === 0) {
            return;
        }

        if (!this.validateAllAnswered()) {
            this.showToast('Error', 'Please answer all the questions before saving.', 'error');
            return;
        }

        this.isSaving = true;
        try {
            await saveGrantTeamResponseItems({
                items: this.responseItems,
                responseId: this.responseId,
                proposalId: this.resolvedRecordId
            });
            this.showToast('Success', 'Grant team response items saved.', 'success');
            this.dispatchEvent(new CustomEvent('close'));
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    validateAllAnswered() {
        const fields = this.template.querySelectorAll('lightning-combobox, lightning-textarea');
        let allValid = true;

        fields.forEach((field) => {
            field.setCustomValidity('');
            if (field.required && !field.value) {
                field.setCustomValidity('This response is required.');
            }
            field.reportValidity();
            if (!field.checkValidity()) {
                allValid = false;
            }
        });

        return allValid;
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
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