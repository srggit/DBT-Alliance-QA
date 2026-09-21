import { LightningElement, wire, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CurrentPageReference } from 'lightning/navigation';

import getYearlySchemeInfo from '@salesforce/apex/ReviewerQuestionTemplateActionController.getYearlySchemeInfo';
import getQuestionnairesByItem from '@salesforce/apex/ReviewerQuestionTemplateActionController.getQuestionnairesByItem';
import getExistingReviewerTemplates from '@salesforce/apex/ReviewerQuestionTemplateActionController.getExistingReviewerTemplates';
import saveReviewerQuestionTemplates from '@salesforce/apex/ReviewerQuestionTemplateActionController.saveReviewerQuestionTemplates';

const STAGE_PRELIMS = 'Prelims';
const STAGE_FULL = 'Full';
const UNASSIGNED_SECTION = 'Unassigned';

export default class ReviewerQuestionTemplateAction extends LightningElement {

    @api recordId;
    schemeInfo;

    templateRecords = [];
    activeStageTab = 'prelims';

    isLoading = true;
    isSaving = false;
    hasResizedModal = false;
    hasLoaded = false;

    // Quick Actions do not auto-inject @api recordId; resolve it from the
    // page reference state, same pattern as addSchemeQuestionItemsAction.
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
        try {
            const [info, existingItems] = await Promise.all([
                getYearlySchemeInfo({ recordId: this.recordId }),
                getExistingReviewerTemplates({ recordId: this.recordId })
            ]);

            this.schemeInfo = info;

            const existingByQuestionnaire = new Map();
            existingItems.forEach((rec) => {
                existingByQuestionnaire.set(rec.Scheme_Questionnaire__c, rec);
            });

            const questionnaires = await getQuestionnairesByItem({ schemeItemId: info.Scheme_Items__c });

            this.templateRecords = questionnaires.map((q) => {
                const existing = existingByQuestionnaire.get(q.Id);
                const stage = q.Stage__c;

                if (existing) {
                    // Already turned into a Reviewer Question Template: show saved
                    // values, locked for editing.
                    return {
                        Id: q.Id,
                        DisplayName: q.Display_Name__c,
                        Stage__c: stage,
                        alreadyAdded: true,
                        addedMessage: `Already added by ${existing.CreatedBy?.Name || 'someone'} on ${new Date(existing.CreatedDate).toLocaleDateString()}.`,
                        selected: false,
                        Question__c: existing.Question__c,
                        Section__c: existing.Section__c,
                        SL_No__c: existing.SL_No__c,
                        Is_Visible_To_Peer_Reviewer__c: existing.Is_Visible_To_Peer_Reviewer__c
                    };
                }

                // Not yet added: fresh, editable defaults.
                // Full-stage rows default the peer-review visibility checkbox to
                // checked; Prelims-stage rows don't expose that column at all,
                // so the underlying value is irrelevant but kept false for clarity.
                return {
                    Id: q.Id,
                    DisplayName: q.Display_Name__c,
                    Stage__c: stage,
                    alreadyAdded: false,
                    addedMessage: '',
                    selected: false,
                    Question__c: q.Display_Name__c,
                    Section__c: q.Section__c || '',
                    SL_No__c: q.SL_No__c,
                    Is_Visible_To_Peer_Reviewer__c: stage === STAGE_FULL
                };
            });
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    get noSchemeItem() {
        return this.schemeInfo && !this.schemeInfo.Scheme_Items__c;
    }

    get prelimsRecords() {
        return this.templateRecords.filter((row) => row.Stage__c === STAGE_PRELIMS);
    }

    get fullRecords() {
        return this.templateRecords.filter((row) => row.Stage__c === STAGE_FULL);
    }

    get noPrelimsRecords() {
        return !this.prelimsRecords.length;
    }

    get noFullRecords() {
        return !this.fullRecords.length;
    }

    get prelimsTabLabel() {
        return `Prelims (${this.prelimsRecords.length})`;
    }

    get fullTabLabel() {
        return `Full (${this.fullRecords.length})`;
    }

    get isPrelimsStageActive() {
        return this.activeStageTab === 'prelims';
    }

    get isFullStageActive() {
        return this.activeStageTab === 'full';
    }

    get prelimsTabButtonClass() {
        return this.isPrelimsStageActive ? 'stage-tab-button active' : 'stage-tab-button';
    }

    get fullTabButtonClass() {
        return this.isFullStageActive ? 'stage-tab-button active' : 'stage-tab-button';
    }

    handleStageTabClick(event) {
        this.activeStageTab = event.currentTarget.dataset.stage;
    }

    // Section sub-tabs are derived fresh from templateRecords on every access,
    // so counts, membership, and each group's "select all" checkbox state all
    // stay in sync automatically as rows are toggled or Section__c is edited.
    get prelimsSectionGroups() {
        return this.groupBySection(this.prelimsRecords, STAGE_PRELIMS);
    }

    get fullSectionGroups() {
        return this.groupBySection(this.fullRecords, STAGE_FULL);
    }

    groupBySection(records, stage) {
        const map = new Map();
        records.forEach((row) => {
            const sectionKey = row.Section__c && row.Section__c.trim() ? row.Section__c.trim() : UNASSIGNED_SECTION;
            if (!map.has(sectionKey)) {
                map.set(sectionKey, []);
            }
            map.get(sectionKey).push(row);
        });

        const sectionKeys = Array.from(map.keys()).sort((a, b) => {
            if (a === UNASSIGNED_SECTION) return 1;
            if (b === UNASSIGNED_SECTION) return -1;
            return a.localeCompare(b);
        });

        return sectionKeys.map((sectionKey) => {
            const sectionRecords = map.get(sectionKey);
            const selectable = sectionRecords.filter((r) => !r.alreadyAdded);
            return {
                key: `${stage}-${sectionKey}`,
                stage,
                section: sectionKey,
                tabLabel: `${sectionKey} (${sectionRecords.length})`,
                records: sectionRecords,
                allSelected: selectable.length > 0 && selectable.every((r) => r.selected)
            };
        });
    }

    handleSelectAll(event) {
        const checked = event.target.checked;
        const stage = event.target.dataset.stage;
        const section = event.target.dataset.section;

        this.templateRecords = this.templateRecords.map((row) => {
            const rowSection = row.Section__c && row.Section__c.trim() ? row.Section__c.trim() : UNASSIGNED_SECTION;
            if (row.Stage__c === stage && rowSection === section && !row.alreadyAdded) {
                return { ...row, selected: checked };
            }
            return row;
        });
    }

    handleRowToggle(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        this.templateRecords = this.templateRecords.map((row) =>
            row.Id === id ? { ...row, selected: checked } : row
        );
    }

    handleFieldChange(event) {
        const id = event.target.dataset.id;
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.templateRecords = this.templateRecords.map((row) =>
            row.Id === id ? { ...row, [field]: value } : row
        );
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleSave() {
        const payload = this.templateRecords
            .filter((r) => r.selected && !r.alreadyAdded)
            .map((r) => ({
                Scheme_Questionnaire__c: r.Id,
                Question__c: r.Question__c,
                Section__c: r.Section__c,
                SL_No__c: r.SL_No__c,
                Stage__c: r.Stage__c,
                // Prelims stage never exposes the checkbox in the UI, so force
                // false regardless of whatever default sits in memory.
                Is_Visible_To_Peer_Reviewer__c: r.Stage__c === STAGE_FULL ? r.Is_Visible_To_Peer_Reviewer__c : false
            }));

        if (!payload.length) {
            this.showToast('Nothing selected', 'Select at least one questionnaire to add.', 'warning');
            return;
        }

        this.isSaving = true;
        try {
            const count = await saveReviewerQuestionTemplates({
                recordId: this.recordId,
                templateRecords: payload
            });

            this.showToast('Success', `${count} Reviewer Question Template(s) created.`, 'success');
            this.dispatchEvent(new CloseActionScreenEvent());

            eval("$A.get('e.force:refreshView').fire();");
        } catch (error) {
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
        if (this.hasResizedModal) {
            return;
        }
        const modal = document.querySelector('.slds-modal__container');
        if (modal) {
            modal.style.width = '85vw';
            modal.style.maxWidth = '85vw';
            this.hasResizedModal = true;
        }
    }
}










// import { LightningElement, wire, api } from 'lwc';
// import { CloseActionScreenEvent } from 'lightning/actions';
// import { ShowToastEvent } from 'lightning/platformShowToastEvent';
// import { CurrentPageReference } from 'lightning/navigation';

// import getYearlySchemeInfo from '@salesforce/apex/ReviewerQuestionTemplateActionController.getYearlySchemeInfo';
// import getQuestionnairesByItem from '@salesforce/apex/ReviewerQuestionTemplateActionController.getQuestionnairesByItem';
// import getExistingReviewerTemplates from '@salesforce/apex/ReviewerQuestionTemplateActionController.getExistingReviewerTemplates';
// import saveReviewerQuestionTemplates from '@salesforce/apex/ReviewerQuestionTemplateActionController.saveReviewerQuestionTemplates';

// const STAGE_PRELIMS = 'Prelims';
// const STAGE_FULL = 'Full';
// const UNASSIGNED_SECTION = 'Unassigned';

// export default class ReviewerQuestionTemplateAction extends LightningElement {

//     @api recordId;
//     schemeInfo;

//     templateRecords = [];

//     isLoading = true;
//     isSaving = false;
//     hasResizedModal = false;
//     hasLoaded = false;

//     // Quick Actions do not auto-inject @api recordId; resolve it from the
//     // page reference state, same pattern as addSchemeQuestionItemsAction.
//     @wire(CurrentPageReference)
//     getStateParameters(currentPageReference) {
//         if (!this.recordId && currentPageReference) {
//             const fromAttributes = currentPageReference.attributes?.recordId;
//             const fromState = currentPageReference.state?.recordId;
//             const fromStateC = currentPageReference.state?.c__recordId;
//             this.recordId = fromAttributes || fromState || fromStateC;
//         }

//         if (this.recordId && !this.hasLoaded) {
//             this.hasLoaded = true;
//             this.loadData();
//         }
//     }

//     connectedCallback() {
//         if (this.recordId && !this.hasLoaded) {
//             this.hasLoaded = true;
//             this.loadData();
//         }
//     }

//     async loadData() {
//         if (!this.recordId) {
//             return;
//         }
//         this.isLoading = true;
//         try {
//             const [info, existingItems] = await Promise.all([
//                 getYearlySchemeInfo({ recordId: this.recordId }),
//                 getExistingReviewerTemplates({ recordId: this.recordId })
//             ]);

//             this.schemeInfo = info;

//             const existingByQuestionnaire = new Map();
//             existingItems.forEach((rec) => {
//                 existingByQuestionnaire.set(rec.Scheme_Questionnaire__c, rec);
//             });

//             const questionnaires = await getQuestionnairesByItem({ schemeItemId: info.Scheme_Items__c });

//             this.templateRecords = questionnaires.map((q) => {
//                 const existing = existingByQuestionnaire.get(q.Id);
//                 const stage = q.Stage__c;

//                 if (existing) {
//                     // Already turned into a Reviewer Question Template: show saved
//                     // values, locked for editing.
//                     return {
//                         Id: q.Id,
//                         DisplayName: q.Display_Name__c,
//                         Stage__c: stage,
//                         alreadyAdded: true,
//                         addedMessage: `Already added by ${existing.CreatedBy?.Name || 'someone'} on ${new Date(existing.CreatedDate).toLocaleDateString()}.`,
//                         selected: false,
//                         Question__c: existing.Question__c,
//                         Section__c: existing.Section__c,
//                         SL_No__c: existing.SL_No__c,
//                         Is_Visible_To_Peer_Reviewer__c: existing.Is_Visible_To_Peer_Reviewer__c
//                     };
//                 }

//                 // Not yet added: fresh, editable defaults.
//                 // Full-stage rows default the peer-review visibility checkbox to
//                 // checked; Prelims-stage rows don't expose that column at all,
//                 // so the underlying value is irrelevant but kept false for clarity.
//                 return {
//                     Id: q.Id,
//                     DisplayName: q.Display_Name__c,
//                     Stage__c: stage,
//                     alreadyAdded: false,
//                     addedMessage: '',
//                     selected: false,
//                     Question__c: q.Display_Name__c,
//                     Section__c: q.Section__c || '',
//                     SL_No__c: q.SL_No__c,
//                     Is_Visible_To_Peer_Reviewer__c: stage === STAGE_FULL
//                 };
//             });
//         } catch (error) {
//             this.showToast('Error', this.getErrorMessage(error), 'error');
//         } finally {
//             this.isLoading = false;
//         }
//     }

//     get noSchemeItem() {
//         return this.schemeInfo && !this.schemeInfo.Scheme_Items__c;
//     }

//     get prelimsRecords() {
//         return this.templateRecords.filter((row) => row.Stage__c === STAGE_PRELIMS);
//     }

//     get fullRecords() {
//         return this.templateRecords.filter((row) => row.Stage__c === STAGE_FULL);
//     }

//     get noPrelimsRecords() {
//         return !this.prelimsRecords.length;
//     }

//     get noFullRecords() {
//         return !this.fullRecords.length;
//     }

//     get prelimsTabLabel() {
//         return `Prelims (${this.prelimsRecords.length})`;
//     }

//     get fullTabLabel() {
//         return `Full (${this.fullRecords.length})`;
//     }

//     // Section sub-tabs are derived fresh from templateRecords on every access,
//     // so counts, membership, and each group's "select all" checkbox state all
//     // stay in sync automatically as rows are toggled or Section__c is edited.
//     get prelimsSectionGroups() {
//         return this.groupBySection(this.prelimsRecords, STAGE_PRELIMS);
//     }

//     get fullSectionGroups() {
//         return this.groupBySection(this.fullRecords, STAGE_FULL);
//     }

//     groupBySection(records, stage) {
//         const map = new Map();
//         records.forEach((row) => {
//             const sectionKey = row.Section__c && row.Section__c.trim() ? row.Section__c.trim() : UNASSIGNED_SECTION;
//             if (!map.has(sectionKey)) {
//                 map.set(sectionKey, []);
//             }
//             map.get(sectionKey).push(row);
//         });

//         const sectionKeys = Array.from(map.keys()).sort((a, b) => {
//             if (a === UNASSIGNED_SECTION) return 1;
//             if (b === UNASSIGNED_SECTION) return -1;
//             return a.localeCompare(b);
//         });

//         return sectionKeys.map((sectionKey) => {
//             const sectionRecords = map.get(sectionKey);
//             const selectable = sectionRecords.filter((r) => !r.alreadyAdded);
//             return {
//                 key: `${stage}-${sectionKey}`,
//                 stage,
//                 section: sectionKey,
//                 tabLabel: `${sectionKey} (${sectionRecords.length})`,
//                 records: sectionRecords,
//                 allSelected: selectable.length > 0 && selectable.every((r) => r.selected)
//             };
//         });
//     }

//     handleSelectAll(event) {
//         const checked = event.target.checked;
//         const stage = event.target.dataset.stage;
//         const section = event.target.dataset.section;

//         this.templateRecords = this.templateRecords.map((row) => {
//             const rowSection = row.Section__c && row.Section__c.trim() ? row.Section__c.trim() : UNASSIGNED_SECTION;
//             if (row.Stage__c === stage && rowSection === section && !row.alreadyAdded) {
//                 return { ...row, selected: checked };
//             }
//             return row;
//         });
//     }

//     handleRowToggle(event) {
//         const id = event.target.dataset.id;
//         const checked = event.target.checked;
//         this.templateRecords = this.templateRecords.map((row) =>
//             row.Id === id ? { ...row, selected: checked } : row
//         );
//     }

//     handleFieldChange(event) {
//         const id = event.target.dataset.id;
//         const field = event.target.dataset.field;
//         const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
//         this.templateRecords = this.templateRecords.map((row) =>
//             row.Id === id ? { ...row, [field]: value } : row
//         );
//     }

//     handleCancel() {
//         this.dispatchEvent(new CloseActionScreenEvent());
//     }

//     async handleSave() {
//         const payload = this.templateRecords
//             .filter((r) => r.selected && !r.alreadyAdded)
//             .map((r) => ({
//                 Scheme_Questionnaire__c: r.Id,
//                 Question__c: r.Question__c,
//                 Section__c: r.Section__c,
//                 SL_No__c: r.SL_No__c,
//                 Stage__c: r.Stage__c,
//                 // Prelims stage never exposes the checkbox in the UI, so force
//                 // false regardless of whatever default sits in memory.
//                 Is_Visible_To_Peer_Reviewer__c: r.Stage__c === STAGE_FULL ? r.Is_Visible_To_Peer_Reviewer__c : false
//             }));

//         if (!payload.length) {
//             this.showToast('Nothing selected', 'Select at least one questionnaire to add.', 'warning');
//             return;
//         }

//         this.isSaving = true;
//         try {
//             const count = await saveReviewerQuestionTemplates({
//                 recordId: this.recordId,
//                 templateRecords: payload
//             });

//             this.showToast('Success', `${count} Reviewer Question Template(s) created.`, 'success');
//             this.dispatchEvent(new CloseActionScreenEvent());

//             eval("$A.get('e.force:refreshView').fire();");
//         } catch (error) {
//             this.showToast('Error', this.getErrorMessage(error), 'error');
//         } finally {
//             this.isSaving = false;
//         }
//     }

//     getErrorMessage(error) {
//         return error && error.body && error.body.message ? error.body.message : 'Unknown error occurred';
//     }

//     showToast(title, message, variant) {
//         this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
//     }

//     renderedCallback() {
//         if (this.hasResizedModal) {
//             return;
//         }
//         const modal = document.querySelector('.slds-modal__container');
//         if (modal) {
//             modal.style.width = '85vw';
//             modal.style.maxWidth = '85vw';
//             this.hasResizedModal = true;
//         }
//     }
// }












// import { LightningElement, wire, api } from 'lwc';
// import { CloseActionScreenEvent } from 'lightning/actions';
// import { ShowToastEvent } from 'lightning/platformShowToastEvent';
// import { CurrentPageReference } from 'lightning/navigation';

// import getYearlySchemeInfo from '@salesforce/apex/ReviewerQuestionTemplateActionController.getYearlySchemeInfo';
// import getQuestionnairesByItem from '@salesforce/apex/ReviewerQuestionTemplateActionController.getQuestionnairesByItem';
// import getExistingReviewerTemplates from '@salesforce/apex/ReviewerQuestionTemplateActionController.getExistingReviewerTemplates';
// import saveReviewerQuestionTemplates from '@salesforce/apex/ReviewerQuestionTemplateActionController.saveReviewerQuestionTemplates';

// export default class ReviewerQuestionTemplateAction extends LightningElement {

//     @api recordId;
//     schemeInfo;

//     templateRecords = [];
//     selectAll = false;

//     isLoading = true;
//     isSaving = false;
//     hasResizedModal = false;
//     hasLoaded = false;

//     // Quick Actions do not auto-inject @api recordId; resolve it from the
//     // page reference state, same pattern as addSchemeQuestionItemsAction.
//     @wire(CurrentPageReference)
//     getStateParameters(currentPageReference) {
//         if (!this.recordId && currentPageReference) {
//             const fromAttributes = currentPageReference.attributes?.recordId;
//             const fromState = currentPageReference.state?.recordId;
//             const fromStateC = currentPageReference.state?.c__recordId;
//             this.recordId = fromAttributes || fromState || fromStateC;
//         }

//         if (this.recordId && !this.hasLoaded) {
//             this.hasLoaded = true;
//             this.loadData();
//         }
//     }

//     connectedCallback() {
//         if (this.recordId && !this.hasLoaded) {
//             this.hasLoaded = true;
//             this.loadData();
//         }
//     }

//     async loadData() {
//         if (!this.recordId) {
//             return;
//         }
//         this.isLoading = true;
//         try {
//             const [info, existingItems] = await Promise.all([
//                 getYearlySchemeInfo({ recordId: this.recordId }),
//                 getExistingReviewerTemplates({ recordId: this.recordId })
//             ]);

//             this.schemeInfo = info;

//             const existingByQuestionnaire = new Map();
//             existingItems.forEach((rec) => {
//                 existingByQuestionnaire.set(rec.Scheme_Questionnaire__c, rec);
//             });

//             const questionnaires = await getQuestionnairesByItem({ schemeItemId: info.Scheme_Items__c });

//             this.templateRecords = questionnaires.map((q) => {
//                 const existing = existingByQuestionnaire.get(q.Id);

//                 if (existing) {
//                     // Already turned into a Reviewer Question Template: show saved
//                     // values, locked for editing.
//                     return {
//                         Id: q.Id,
//                         DisplayName: q.Display_Name__c,
//                         alreadyAdded: true,
//                         addedMessage: `Already added by ${existing.CreatedBy?.Name || 'someone'} on ${new Date(existing.CreatedDate).toLocaleDateString()}.`,
//                         selected: false,
//                         Question__c: existing.Question__c,
//                         Section__c: existing.Section__c,
//                         SL_No__c: existing.SL_No__c,
//                         Is_Visible_To_Peer_Reviewer__c: existing.Is_Visible_To_Peer_Reviewer__c
//                     };
//                 }

//                 // Not yet added: fresh, editable defaults.
//                 return {
//                     Id: q.Id,
//                     DisplayName: q.Display_Name__c,
//                     alreadyAdded: false,
//                     addedMessage: '',
//                     selected: false,
//                     Question__c: q.Display_Name__c,
//                     Section__c: q.Section__c || '',
//                     SL_No__c: q.SL_No__c,
//                     Is_Visible_To_Peer_Reviewer__c: false
//                 };
//             });

//             this.selectAll = false;
//         } catch (error) {
//             this.showToast('Error', this.getErrorMessage(error), 'error');
//         } finally {
//             this.isLoading = false;
//         }
//     }

//     get noSchemeItem() {
//         return this.schemeInfo && !this.schemeInfo.Scheme_Items__c;
//     }
//     get noRecords() {
//         return !this.templateRecords.length;
//     }
//     get tabLabel() {
//         return `Available Scheme Questionnaires (${this.templateRecords.length})`;
//     }

//     handleSelectAll(event) {
//         const checked = event.target.checked;
//         this.selectAll = checked;
//         this.templateRecords = this.templateRecords.map((row) =>
//             row.alreadyAdded ? row : { ...row, selected: checked }
//         );
//     }

//     handleRowToggle(event) {
//         const id = event.target.dataset.id;
//         const checked = event.target.checked;
//         this.templateRecords = this.templateRecords.map((row) =>
//             row.Id === id ? { ...row, selected: checked } : row
//         );
//         const selectableRows = this.templateRecords.filter((row) => !row.alreadyAdded);
//         this.selectAll = selectableRows.length > 0 && selectableRows.every((row) => row.selected);
//     }

//     handleFieldChange(event) {
//         const id = event.target.dataset.id;
//         const field = event.target.dataset.field;
//         const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
//         this.templateRecords = this.templateRecords.map((row) =>
//             row.Id === id ? { ...row, [field]: value } : row
//         );
//     }

//     handleCancel() {
//         this.dispatchEvent(new CloseActionScreenEvent());
//     }

//     async handleSave() {
//         const payload = this.templateRecords
//             .filter((r) => r.selected && !r.alreadyAdded)
//             .map((r) => ({
//                 Scheme_Questionnaire__c: r.Id,
//                 Question__c: r.Question__c,
//                 Section__c: r.Section__c,
//                 SL_No__c: r.SL_No__c,
//                 Is_Visible_To_Peer_Reviewer__c: r.Is_Visible_To_Peer_Reviewer__c
//             }));

//         if (!payload.length) {
//             this.showToast('Nothing selected', 'Select at least one questionnaire to add.', 'warning');
//             return;
//         }

//         this.isSaving = true;
//         try {
//             const count = await saveReviewerQuestionTemplates({
//                 recordId: this.recordId,
//                 templateRecords: payload
//             });

//             this.showToast('Success', `${count} Reviewer Question Template(s) created.`, 'success');
//             this.dispatchEvent(new CloseActionScreenEvent());

//             eval("$A.get('e.force:refreshView').fire();");
//         } catch (error) {
//             this.showToast('Error', this.getErrorMessage(error), 'error');
//         } finally {
//             this.isSaving = false;
//         }
//     }

//     getErrorMessage(error) {
//         return error && error.body && error.body.message ? error.body.message : 'Unknown error occurred';
//     }

//     showToast(title, message, variant) {
//         this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
//     }

//     renderedCallback() {
//         if (this.hasResizedModal) {
//             return;
//         }
//         const modal = document.querySelector('.slds-modal__container');
//         if (modal) {
//             modal.style.width = '85vw';
//             modal.style.maxWidth = '85vw';
//             this.hasResizedModal = true;
//         }
//     }
// }