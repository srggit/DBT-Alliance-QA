import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { loadStyle } from 'lightning/platformResourceLoader';
import modalResizeCss from '@salesforce/resourceUrl/CustomModelCSS1';
import getProposalSummary from '@salesforce/apex/ProposalApplicantDetailsController.getProposalSummary';

export default class ProposalApplicantDetails extends NavigationMixin(LightningElement) {
    _recordId;
    proposalSummary = {};
    _cssLoaded = false;

    connectedCallback() {
        if (this._cssLoaded) {
            return;
        }
        this._cssLoaded = true;
        // Widens the native Quick Action modal this component runs in when opened as
        // a Record Action - scoped via :has(c-proposal-applicant-details) inside the
        // resource itself, so it only affects a modal that actually contains this
        // component. Harmless no-op on the other targets (Record Page/Tab/App Page),
        // which aren't rendered inside a .slds-modal__container at all.
        loadStyle(this, modalResizeCss).catch(() => {
            // Non-fatal: the component still works at default modal width.
        });
    }

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this.loadSummary();
    }

    proposalIdInput = '';
    activeTabKey = 'details';
    showGrantManagerModal = false;
    showReviewerResponseModal = false;
    showGrantTeamResponseModal = false;
    showReviewerRatingMatrixModal = false;
    showReviewerMappingModal = false;

    @wire(CurrentPageReference)
    wiredPageReference(pageReference) {
        const pageRecordId = pageReference?.state?.c__recordId || pageReference?.state?.recordId;
        if (pageRecordId && !this.recordId) {
            this.recordId = pageRecordId;
        }
    }

    get isFullStage() {
        return this.proposalSummary?.applicationStage === 'Full';
    }

    get isPrelimStage() {
        return !this.isFullStage;
    }

    async loadSummary() {
        if (!this._recordId) {
            return;
        }
        try {
            this.proposalSummary = await getProposalSummary({ proposalId: this._recordId });
        } catch (e) {
            this.proposalSummary = {};
        }
    }

    get bannerSubtitle() {
        const parts = [
            this.proposalSummary?.proposalIdDisplay,
            this.proposalSummary?.applicantName,
            this.proposalSummary?.schemeItemName
        ].filter(Boolean);
        return parts.length > 0
            ? parts.join(' / ')
            : 'View and manage all details related to the proposal and applicant.';
    }

    get showInput() {
        return !this.recordId;
    }

    get detailsTabClass() {
        return this.activeTabKey === 'details' ? 'pad-tab-btn pad-tab-btn_active' : 'pad-tab-btn';
    }

    get reviewerTabClass() {
        return this.activeTabKey === 'reviewer' ? 'pad-tab-btn pad-tab-btn_active' : 'pad-tab-btn';
    }

    get detailsPanelClass() {
        return this.activeTabKey === 'details' ? 'pad-tab-panel' : 'pad-tab-panel pad-tab-panel_hidden';
    }

    get reviewerPanelClass() {
        return this.activeTabKey === 'reviewer'
            ? 'pad-tab-panel pad-tab-panel_reviewer'
            : 'pad-tab-panel pad-tab-panel_reviewer pad-tab-panel_hidden';
    }

    handleTabClick(event) {
        this.activeTabKey = event.currentTarget.dataset.tab;
    }

    handleProposalIdChange(event) {
        this.proposalIdInput = event.target.value;
    }

    handleLoad() {
        if (this.proposalIdInput) {
            this.recordId = this.proposalIdInput;
        }
    }

    handleOpenGrantManager() {
        this.showGrantManagerModal = true;
    }

    handleCloseGrantManager() {
        this.showGrantManagerModal = false;
    }

    handleOpenReviewerResponse() {
        this.showReviewerResponseModal = true;
    }

    handleCloseReviewerResponse() {
        this.showReviewerResponseModal = false;
    }

    handleOpenGrantTeamResponse() {
        this.showGrantTeamResponseModal = true;
    }

    handleCloseGrantTeamResponse() {
        this.showGrantTeamResponseModal = false;
    }

    handleOpenReviewerMapping() {
        this.showReviewerMappingModal = true;
    }

    handleCloseReviewerMapping() {
        this.showReviewerMappingModal = false;
    }

    handleOpenReviewerRatingMatrix() {
        this.showReviewerRatingMatrixModal = true;
    }

    handleCloseReviewerRatingMatrix() {
        this.showReviewerRatingMatrixModal = false;
    }

    async handleOpenApplicationForm() {
        const pageReference = {
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Proposal_Application_Form'
            },
            state: {
                c__recordId: this.recordId
            }
        };
        const url = await this[NavigationMixin.GenerateUrl](pageReference);
        window.open(url, '_blank');
    }

}