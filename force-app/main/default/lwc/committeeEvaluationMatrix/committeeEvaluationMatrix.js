import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getCommitteeEvaluations from '@salesforce/apex/CommitteeEvaluationMatrixController.getCommitteeEvaluations';

export default class CommitteeEvaluationMatrix extends LightningElement {
    _recordId;
    isLoading = false;
    error;
    members = [];

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this.loadData();
    }

    @wire(CurrentPageReference)
    wiredPageReference(pageReference) {
        const urlId = pageReference?.state?.c__recordId || pageReference?.state?.recordId;
        if (urlId && !this._recordId) {
            this._recordId = urlId;
            this.loadData();
        }
    }

    async loadData() {
        if (!this._recordId) {
            return;
        }
        this.isLoading = true;
        this.error = undefined;
        try {
            this.members = await getCommitteeEvaluations({ proposalId: this._recordId });
        } catch (e) {
            this.error = e?.body?.message || e?.message || 'Unable to load Committee Evaluation responses.';
            this.members = [];
        } finally {
            this.isLoading = false;
        }
    }

    get hasData() {
        return !this.isLoading && !this.error && this.members && this.members.length > 0;
    }

    get showNoData() {
        return !this.isLoading && !this.error && (!this.members || this.members.length === 0);
    }

    get memberColumns() {
        return (this.members || []).map((member) => ({
            key: member.committeeId,
            label: member.memberName || 'Unnamed Member'
        }));
    }

    get totalColumns() {
        return this.memberColumns.length + 1;
    }

    get memberCount() {
        return this.memberColumns.length;
    }

    // Sections (and, within each section, questions) are ordered by first appearance across
    // all members, the same "first-seen order" convention reviewerRatingMatrix.js and
    // peerEvaluationMatrix.js already use - just with an extra grouping level here, since
    // Committee_Member_Evaluation__c carries a real Section_Detail__c the Peer_Evaluation__c
    // object doesn't.
    get sections() {
        const sectionOrder = [];
        const questionsBySection = new Map();

        (this.members || []).forEach((member) => {
            (member.answers || []).forEach((qa) => {
                const sectionName = qa.section || 'General';
                if (!questionsBySection.has(sectionName)) {
                    questionsBySection.set(sectionName, []);
                    sectionOrder.push(sectionName);
                }
                const questions = questionsBySection.get(sectionName);
                if (!questions.some((q) => q === qa.question)) {
                    questions.push(qa.question);
                }
            });
        });

        return sectionOrder.map((sectionName, sIndex) => ({
            key: 'section-' + sIndex,
            sectionName,
            rows: questionsBySection.get(sectionName).map((question, qIndex) => ({
                key: 'section-' + sIndex + '-q-' + qIndex,
                question,
                cells: (this.members || []).map((member) => {
                    const match = (member.answers || []).find(
                        (qa) => (qa.section || 'General') === sectionName && qa.question === question
                    );
                    return {
                        key: member.committeeId + '-' + sIndex + '-' + qIndex,
                        value: match?.answer || ''
                    };
                })
            }))
        }));
    }
}