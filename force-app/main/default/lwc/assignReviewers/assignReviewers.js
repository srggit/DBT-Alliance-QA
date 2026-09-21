import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import { CloseActionScreenEvent } from 'lightning/actions';
import { refreshApex } from '@salesforce/apex';
import getReviewerContacts from '@salesforce/apex/ReviewerController.getReviewerContacts';
import getProposalApplicationStage from '@salesforce/apex/ReviewerController.getProposalApplicationStage';
import createReviewerMappings from '@salesforce/apex/ReviewerController.createReviewerMappings';
import getExistingReviewerCount from '@salesforce/apex/ReviewerController.getExistingReviewerCount';
import { loadStyle } from 'lightning/platformResourceLoader';
import modalResizeCss from '@salesforce/resourceUrl/CustomModelCSS1';

const MINIMUM_REVIEWERS_BY_STAGE = {
    Prelims: 2,
    Full: 3
};
const DEFAULT_MINIMUM_REVIEWERS = 1;

export default class AssignReviewers extends LightningElement {
    @api recordId;

    reviewers = [];
    error;
    isLoading = true;
    isSaving = false;
    wiredReviewersResult;
    applicationStage;
    existingReviewerCount = 0;
    _cssLoaded = false;

    connectedCallback() {
        if (this._cssLoaded) {
            return;
        }
        this._cssLoaded = true;
        // Widens the native Quick Action modal this component runs in - scoped via
        // :has(c-assign-reviewers) inside the resource itself so it only affects a
        // modal that actually contains this component, not every SLDS modal on the
        // page. Harmless no-op when this component is instead embedded in the app's
        // own custom modal (e.g. My Dashboard), which is already sized to match.
        loadStyle(this, modalResizeCss).catch(() => {
            // Non-fatal: the component still works at default modal width.
        });
    }

    // Pass the proposal record Id so Apex can read Keywords__c and return
    // only reviewer contacts whose child keywords contain the proposal terms.
    @wire(getReviewerContacts, { proposalId: '$recordId' })
    wiredReviewers(result) {
        this.wiredReviewersResult = result;
        const { error, data } = result;
        this.isLoading = false;

        if (data) {
            this.reviewers = data.map((reviewer) => ({
                ...reviewer,
                selected: false,
                rowClass: reviewer.isAlreadyMapped ? 'ar-tr_disabled' : ''
            }));
            this.error = undefined;
        } else if (error) {
            this.reviewers = [];
            this.error = error;
            this.showToast('Error', this.getErrorMessage(error), 'error');
        }
    }

    @wire(getProposalApplicationStage, { proposalId: '$recordId' })
    wiredApplicationStage({ data, error }) {
        if (data) {
            this.applicationStage = data;
        } else if (error) {
            this.applicationStage = undefined;
        }
    }

    @wire(getExistingReviewerCount, { proposalId: '$recordId' })
    wiredExistingReviewerCount({ data, error }) {
        if (data) {
            this.existingReviewerCount = data;
        } else if (error) {
            this.existingReviewerCount = 0;
        }
    }

    get hasReviewers() {
        return this.reviewers.length > 0;
    }

    get selectedReviewerIds() {
        return this.reviewers
            .filter((reviewer) => reviewer.selected && !reviewer.isAlreadyMapped)
            .map((reviewer) => reviewer.Id);
    }

    get minimumReviewersRequired() {
        const baseMinimum =
            MINIMUM_REVIEWERS_BY_STAGE[this.applicationStage] || DEFAULT_MINIMUM_REVIEWERS;
        return this.existingReviewerCount >= baseMinimum ? 1 : baseMinimum;
    }

    get hasMinimumReviewersSelected() {
        return this.selectedReviewerIds.length >= this.minimumReviewersRequired;
    }

    get showMinimumReviewersMessage() {
        const baseMinimum =
            MINIMUM_REVIEWERS_BY_STAGE[this.applicationStage] || DEFAULT_MINIMUM_REVIEWERS;
        return !this.hasMinimumReviewersSelected && this.existingReviewerCount < baseMinimum;
    }

    get minimumReviewersMessage() {
        const selected = this.selectedReviewerIds.length;
        const min = this.minimumReviewersRequired;
        const stage = this.applicationStage || 'Prelims';
        return 'Please select at least ' + min + ' reviewer' + (min > 1 ? 's' : '') + ' for the ' + stage + ' stage.';
    }

    get isSubmitDisabled() {
        return this.selectedReviewerIds.length === 0 || !this.hasMinimumReviewersSelected || this.isSaving;
    }

    handleReviewerSelect(event) {
        const reviewerId = event.target.dataset.id;
        const isSelected = event.target.checked;
        const reviewer = this.reviewers.find((item) => item.Id === reviewerId);

        if (!reviewer || reviewer.isAlreadyMapped) {
            return;
        }

        this.reviewers = this.reviewers.map((item) =>
            item.Id === reviewerId ? { ...item, selected: isSelected } : item
        );
    }

    async handleCreateMappings() {
        if (!this.hasMinimumReviewersSelected) {
            return;
        }

        this.isSaving = true;
        try {
            await createReviewerMappings({
                proposalId: this.recordId,
                reviewerIds: this.selectedReviewerIds
            });
            this.showToast('Success', 'Reviewer mappings created successfully.', 'success');
            getRecordNotifyChange([{ recordId: this.recordId }]);
            await refreshApex(this.wiredReviewersResult);
            // CloseActionScreenEvent closes the panel when used as a Quick Action; the plain
            // 'close' event lets a host embedding this in its own modal (e.g. My Dashboard)
            // react the same way it does for the app's other embedded action components.
            this.dispatchEvent(new CloseActionScreenEvent());
            this.dispatchEvent(new CustomEvent('close'));
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    getErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body) && error.body.length > 0) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Unable to load reviewers.';
    }
}