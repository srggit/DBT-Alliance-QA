import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getReviewerSectionResponses from '@salesforce/apex/ReviewerSectionResponseController.getReviewerSectionResponses';


const SECTION_ICONS = {
    'Project Summary': 'utility:description',
    'Research Environment': 'utility:location',
    'Applicant CV': 'utility:user',
    'Other Grants and Applications': 'utility:money',
    default: 'utility:description'
};


const SECTION_THEMES = {
    'Project Summary': {
        themeClass: 'theme-pink',
        subtitle: 'Overview of project objectives, scope and approach.'
    },
    'Research Environment': {
        themeClass: 'theme-green',
        subtitle: 'Evaluation of research facilities and environment.'
    },
    'Applicant CV': {
        themeClass: 'theme-blue',
        subtitle: "Assessment of applicant's qualifications and experience."
    },
    'Other Grants and Applications': {
        themeClass: 'theme-orange',
        subtitle: 'Review of other grants and ongoing applications.'
    }
};

const DEFAULT_THEME = {
    themeClass: 'theme-default',
    subtitle: 'Reviewer feedback for this section.'
};


const REVIEWER_ICON = 'standard:contact';


export default class ReviewerSectionResponses extends LightningElement {

    @api recordId;
    @api hideHeader = false;

    proposalId;
    isLoading = true;
    error;

    reviewers = [];

    sectionCount = 0;

    _loadedRecordId;


    /* ============================================================
       CURRENT PAGE REFERENCE
       ============================================================ */

    @wire(CurrentPageReference)
    wiredPageReference(pageReference) {

        const pageRecordId =
            pageReference?.state?.c__recordId ||
            pageReference?.state?.recordId;

        if (
            pageRecordId &&
            !this.recordId &&
            !this.proposalId
        ) {
            this.proposalId = pageRecordId;
            this._loadedRecordId = pageRecordId;

            this.loadData(this.proposalId);
        }
    }


    /* ============================================================
       LOAD DATA WHEN RECORD ID IS AVAILABLE
       ============================================================ */

    renderedCallback() {

        if (
            this.recordId &&
            this.recordId !== this._loadedRecordId
        ) {
            this._loadedRecordId = this.recordId;
            this.proposalId = this.recordId;

            this.loadData(this.recordId);
        }
    }


    /* ============================================================
       LOAD REVIEWER DATA
       ============================================================ */

    async loadData(proposalId) {

        this.isLoading = true;
        this.error = undefined;

        try {

            const data =
                await getReviewerSectionResponses({
                    proposalId
                });


            const sectionNames = new Set();


            this.reviewers = (data || []).map(
                (reviewer, rIndex) => {

                    const sections =
                        (reviewer.sections || []).map(
                            (section, sIndex) => {

                                sectionNames.add(
                                    section.sectionName
                                );


                                const theme =
                                    SECTION_THEMES[
                                        section.sectionName
                                    ] || DEFAULT_THEME;


                                return {

                                    sectionId:
                                        section.sectionId,

                                    sectionName:
                                        section.sectionName,

                                    sectionNumber:
                                        sIndex + 1,

                                    sectionIcon:
                                        SECTION_ICONS[
                                        section.sectionName
                                        ] ||
                                        SECTION_ICONS.default,

                                    themeClass:
                                        theme.themeClass,

                                    cardClass:
                                        'section-card ' +
                                        theme.themeClass,

                                    subtitle:
                                        theme.subtitle,

                                    hasRating:
                                        !!section.rating,

                                    rating:
                                        section.rating || '-',

                                    overallComments:
                                        section.overallComments || '-'
                                };
                            }
                        );


                    /*
                     * First reviewer's tab is active by default.
                     */
                    const reviewerActive =
                        rIndex === 0;


                    return {

                        mappingId:
                            reviewer.mappingId,

                        reviewerName:
                            reviewer.reviewerName,

                        reviewerType:
                            reviewer.reviewerType,

                        reviewerIcon:
                            REVIEWER_ICON,

                        isActive:
                            reviewerActive,

                        tabClass:
                            reviewerActive
                                ? 'reviewer-tab reviewer-tab-active'
                                : 'reviewer-tab',

                        tabLabel:
                            reviewer.reviewerType
                                ? `${reviewer.reviewerName} (${reviewer.reviewerType})`
                                : reviewer.reviewerName,

                        sections
                    };
                }
            );


            /*
             * Number of unique sections.
             */
            this.sectionCount =
                sectionNames.size;

        } catch (err) {

            this.reviewers = [];

            this.sectionCount = 0;

            this.error =
                this.getErrorMessage(err);

            this.showToast(
                'Error',
                this.error,
                'error'
            );

        } finally {

            this.isLoading = false;
        }
    }


    /* ============================================================
       HAS DATA
       ============================================================ */

    get hasData() {

        return (
            this.reviewers &&
            this.reviewers.length > 0
        );
    }


    /* ============================================================
       SHOW HEADER
       ============================================================ */

    get showHeader() {

        return !this.hideHeader;
    }


    /* ============================================================
       SHOW BADGE
       ============================================================ */

    get showBadge() {

        return this.sectionCount > 0;
    }


    /* ============================================================
       BADGE LABEL
       ============================================================ */

    get badgeLabel() {

        return `${this.sectionCount} Section${this.sectionCount === 1 ? '' : 's'}`;
    }


    /* ============================================================
       SELECT REVIEWER TAB
       ============================================================ */

    handleSelectReviewer(event) {

        const mappingId =
            event.currentTarget.dataset.mappingId;


        this.reviewers =
            this.reviewers.map((reviewer) => {

                const active =
                    reviewer.mappingId === mappingId;


                return {

                    ...reviewer,

                    isActive:
                        active,

                    tabClass:
                        active
                            ? 'reviewer-tab reviewer-tab-active'
                            : 'reviewer-tab'
                };
            });
    }


    /* ============================================================
       TOAST
       ============================================================ */

    showToast(
        title,
        message,
        variant
    ) {

        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }


    /* ============================================================
       ERROR MESSAGE
       ============================================================ */

    getErrorMessage(error) {

        if (
            error?.body?.message
        ) {
            return error.body.message;
        }


        if (
            Array.isArray(error?.body) &&
            error.body.length > 0
        ) {
            return error.body
                .map(
                    (item) => item.message
                )
                .join(', ');
        }


        return (
            error?.message ||
            'Unable to load reviewer section responses.'
        );
    }
}