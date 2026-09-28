import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getYearlySchemes from '@salesforce/apex/SchemeReviewerSelectorController.getYearlySchemes';
import getReviewers from '@salesforce/apex/SchemeReviewerSelectorController.getReviewers';
import saveSchemeReviewers from '@salesforce/apex/SchemeReviewerSelectorController.saveSchemeReviewers';

/**
 * Pick Reviewers from the master list and add them as Scheme Reviewers of a Yearly Scheme.
 *
 * Works anywhere: as a Record Action or on a Record Page of Yearly Schemes (recordId is given), or
 * on an App Page / Home Page / Tab (no record) - the Yearly Scheme comes from the yearlySchemeId
 * property, a c__recordId / recordId URL parameter, or a picker shown by the component itself.
 */
export default class SchemeReviewerSelector extends LightningElement {
    _recordId;
    _yearlySchemeId;
    _urlSchemeId;
    _pickedSchemeId;

    // Who is on screen
    schemes = [];
    reviewers = [];
    isLoading = false;
    isSaving = false;
    error;
    searchTerm = '';

    // Row state, by Reviewer Id. Every ticked row is in selected; isActive defaults to true.
    selected = {};
    activeOverrides = {};

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this.loadReviewers();
    }

    // Optional: set on an App / Home / Tab page in App Builder to pin the component to a scheme.
    @api
    get yearlySchemeId() {
        return this._yearlySchemeId;
    }
    set yearlySchemeId(value) {
        this._yearlySchemeId = value;
        this.loadReviewers();
    }

    @wire(CurrentPageReference)
    wiredPageReference(pageReference) {
        const state = pageReference?.state || {};
        this._urlSchemeId = state.c__recordId || state.c__yearlySchemeId || state.recordId || undefined;
        this.loadReviewers();
    }

    get schemeId() {
        return this._recordId || this._yearlySchemeId || this._urlSchemeId || this._pickedSchemeId;
    }

    get needsSchemePicker() {
        return !this._recordId && !this._yearlySchemeId && !this._urlSchemeId;
    }

    async loadSchemes() {
        if (this.schemes.length > 0) {
            return;
        }
        try {
            this.schemes = await getYearlySchemes();
        } catch (e) {
            this.error = this.errorMessage(e, 'Unable to load Yearly Schemes.');
        }
    }

    // Several inputs (recordId, yearlySchemeId, page reference, picker) can each trigger a load
    // while the component initialises; only the latest one is allowed to apply its result.
    _loadSeq = 0;

    async loadReviewers() {
        const seq = ++this._loadSeq;
        if (this.needsSchemePicker) {
            await this.loadSchemes();
        }
        const schemeId = this.schemeId;
        if (!schemeId) {
            this.reviewers = [];
            return;
        }
        this.isLoading = true;
        this.error = undefined;
        try {
            const result = await getReviewers({ yearlySchemeId: schemeId });
            if (seq !== this._loadSeq) {
                return;
            }
            this.reviewers = result;
            this.selected = {};
            this.activeOverrides = {};
        } catch (e) {
            if (seq !== this._loadSeq) {
                return;
            }
            this.reviewers = [];
            this.error = this.errorMessage(e, 'Unable to load Reviewers.');
        } finally {
            if (seq === this._loadSeq) {
                this.isLoading = false;
            }
        }
    }

    handleSchemeChange(event) {
        this._pickedSchemeId = event.detail.value;
        this.loadReviewers();
    }

    handleSearch(event) {
        this.searchTerm = (event.target.value || '').toLowerCase();
    }

    get visibleReviewers() {
        const term = this.searchTerm;
        if (!term) {
            return this.reviewers;
        }
        return this.reviewers.filter((r) =>
            [r.name, r.email, r.organization, r.reviewerType].some((v) => v && v.toLowerCase().includes(term))
        );
    }

    get rows() {
        return this.visibleReviewers.map((r) => {
            const isSelected = !!this.selected[r.id];
            return {
                key: r.id,
                name: r.name || '—',
                email: r.email || '—',
                organization: r.organization || '—',
                reviewerType: r.reviewerType || '—',
                alreadyAdded: r.alreadyAdded,
                selected: isSelected,
                isActive: this.activeOverrides[r.id] !== undefined ? this.activeOverrides[r.id] : true,
                activeDisabled: r.alreadyAdded || !isSelected,
                rowClass: r.alreadyAdded ? 'sel-row_added' : isSelected ? 'sel-row_selected' : ''
            };
        });
    }

    get hasReviewers() {
        return !this.isLoading && !this.error && this.reviewers.length > 0;
    }

    get noResults() {
        return this.hasReviewers && this.visibleReviewers.length === 0;
    }

    get selectableVisible() {
        return this.visibleReviewers.filter((r) => !r.alreadyAdded);
    }

    get allVisibleSelected() {
        return this.selectableVisible.length > 0 && this.selectableVisible.every((r) => this.selected[r.id]);
    }

    get selectedCount() {
        return Object.keys(this.selected).length;
    }

    get saveDisabled() {
        return this.selectedCount === 0 || this.isSaving || !this.schemeId;
    }

    get showEmptyState() {
        return !this.isLoading && !this.error && !!this.schemeId && this.reviewers.length === 0;
    }

    get showPickHint() {
        return !this.schemeId && !this.error;
    }

    handleRowSelect(event) {
        const id = event.currentTarget.dataset.id;
        const selected = { ...this.selected };
        if (event.target.checked) {
            selected[id] = true;
        } else {
            delete selected[id];
        }
        this.selected = selected;
    }

    handleSelectAllVisible(event) {
        const selected = { ...this.selected };
        this.selectableVisible.forEach((r) => {
            if (event.target.checked) {
                selected[r.id] = true;
            } else {
                delete selected[r.id];
            }
        });
        this.selected = selected;
    }

    handleActiveChange(event) {
        const id = event.currentTarget.dataset.id;
        this.activeOverrides = { ...this.activeOverrides, [id]: event.target.checked };
    }

    async handleSave() {
        if (this.saveDisabled) {
            return;
        }
        this.isSaving = true;
        try {
            const selections = Object.keys(this.selected).map((reviewerId) => ({
                reviewerId,
                isActive: this.activeOverrides[reviewerId] !== undefined ? this.activeOverrides[reviewerId] : true
            }));
            const created = await saveSchemeReviewers({
                yearlySchemeId: this.schemeId,
                selectionsJson: JSON.stringify(selections)
            });
            this.showToast('Success', `${created} Scheme Reviewer${created === 1 ? '' : 's'} added.`, 'success');
            this.dispatchEvent(new CustomEvent('saved', { detail: { count: created } }));
            this.closeScreen();
            // Stay useful on a page/tab: reload so the new reviewers show as "Already added".
            await this.loadReviewers();
        } catch (e) {
            this.showToast('Error', this.errorMessage(e, 'Unable to add Scheme Reviewers.'), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleCancel() {
        this.closeScreen();
    }

    // Closes the Record Action modal (a no-op anywhere else) and tells any host to close too.
    closeScreen() {
        this.dispatchEvent(new CloseActionScreenEvent());
        this.dispatchEvent(new CustomEvent('close'));
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errorMessage(e, fallback) {
        return e?.body?.message || e?.message || fallback;
    }
}