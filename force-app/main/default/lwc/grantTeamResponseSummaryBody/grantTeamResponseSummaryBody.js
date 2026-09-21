import { LightningElement, api } from 'lwc';

export default class GrantTeamResponseSummaryBody extends LightningElement {
    @api summary = { stages: [] };
}