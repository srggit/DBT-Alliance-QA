import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import { CloseActionScreenEvent } from 'lightning/actions';
import scheduleInterview from '@salesforce/apex/ScheduleInterviewController.scheduleInterview';

const DEFAULT_STATUS = 'Upcoming';

export default class ScheduleInterview extends LightningElement {
    // App Builder / parent configurable labels (Mode A only).
    @api buttonLabel = 'Schedule Interview';
    @api cardTitle = 'Schedule Interview';

    // Mode A (card + button + custom modal) is opt-in. Default (false) renders
    // the form immediately - the shape used by the Record Action.
    @api showLaunchButton = false;

    // recordId is populated automatically on a record page / record action;
    // a parent component can also set it (or proposalId) directly.
    @api recordId;
    @api proposalId;

    isModalOpen = false;
    isSaving = false;
    errorMessage;
    selectedProposalId;

    get defaultStatus() {
        return DEFAULT_STATUS;
    }

    // proposalId (explicit) wins, then a picker selection, then the host record.
    get resolvedProposalId() {
        return this.proposalId || this.selectedProposalId || this.recordId;
    }

    // Ask the user to pick a Proposal only when there is no context at all.
    get showProposalPicker() {
        return !this.proposalId && !this.recordId;
    }

    // Public API so a parent component can open the modal programmatically.
    @api
    open() {
        this.showLaunchButton = true;
        this.handleOpen();
    }

    handleOpen() {
        this.errorMessage = undefined;
        this.selectedProposalId = this.proposalId || null;
        this.isModalOpen = true;
    }

    handleProposalChange(event) {
        this.selectedProposalId = event.detail.recordId;
    }

    handleCancel() {
        this.isModalOpen = false;
        this.errorMessage = undefined;
        this.closeQuickAction();
    }

    async handleSave() {
        this.errorMessage = undefined;

        const proposalId = this.resolvedProposalId;
        if (!proposalId) {
            this.errorMessage = 'Please select a Proposal.';
            return;
        }

        const inputFields = [...this.template.querySelectorAll('lightning-input-field')];
        let allValid = true;
        inputFields.forEach((field) => {
            if (!field.reportValidity()) {
                allValid = false;
            }
        });
        if (!allValid) {
            return;
        }

        const values = {};
        inputFields.forEach((field) => {
            values[field.fieldName] = field.value;
        });

        this.isSaving = true;
        try {
            const result = await scheduleInterview({
                proposalId,
                startDateTime: values.Start_Date_Time__c,
                endDateTime: values.End_Date_Time__c || null,
                status: values.Status__c || DEFAULT_STATUS
            });

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Interview scheduled',
                    message: `Interview created with ${result.evaluationCount} DCM evaluation record(s).`,
                    variant: 'success'
                })
            );

            // Refresh the host record page when we are on one.
            if (this.recordId) {
                getRecordNotifyChange([{ recordId: this.recordId }]);
            }

            // Let a parent component react (e.g. refresh its own data / navigate).
            this.dispatchEvent(
                new CustomEvent('schedulecomplete', {
                    detail: { interviewId: result.interviewId, proposalId }
                })
            );

            this.isModalOpen = false;
            this.closeQuickAction();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    // Closes the Salesforce-provided Record Action modal. No-op elsewhere.
    closeQuickAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (error?.body?.message) {
            return error.body.message;
        }
        if (typeof error?.message === 'string') {
            return error.message;
        }
        return 'An unexpected error occurred. Please try again.';
    }
}