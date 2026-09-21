import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSchemeGroups from '@salesforce/apex/BulkEligibilityCheckController.getSchemeGroups';
import sendNotifications from '@salesforce/apex/BulkEligibilityCheckController.sendNotifications';

const STATUS_VARIANTS = {
    Submitted: 'status-submitted',
    'Under Review': 'status-review',
    Approved: 'status-submitted',
    Rejected: 'status-rejected'
};

export default class BulkEligibilityCheck extends LightningElement {
    @api recordIds = [];

    groups = [];
    error;
    isLoading = true;
    isSending = false;
    hasSent = false;

    connectedCallback() {
        this.loadGroups();
    }

    async loadGroups() {
        this.isLoading = true;
        try {
            const data = await getSchemeGroups({ proposalIds: this.recordIds });
            this.groups = (data || []).map((group) => this.decorateGroup(group));
            this.error = undefined;
        } catch (error) {
            this.groups = [];
            this.error = this.getErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    decorateGroup(group) {
        const members = (group.members || []).map((member) => ({
            ...member,
            initials: this.getInitials(member.name),
            emailHref: member.email ? `mailto:${member.email}` : null
        }));

        const proposals = (group.proposals || []).map((proposal) => ({
            ...proposal,
            statusClass: `status-badge ${STATUS_VARIANTS[proposal.status] || 'status-default'}`
        }));

        return {
            ...group,
            members,
            proposals,
            hasMembers: members.length > 0,
            memberCountLabel: `${members.length} Member${members.length === 1 ? '' : 's'}`,
            proposalCountLabel: `${proposals.length} Proposal${proposals.length === 1 ? '' : 's'}`
        };
    }

    getInitials(name) {
        if (!name) {
            return '';
        }
        return name
            .split(' ')
            .filter(Boolean)
            .map((part) => part[0].toUpperCase())
            .slice(0, 2)
            .join('');
    }

    get hasGroups() {
        return this.groups.length > 0;
    }

    get totalMemberCount() {
        return this.groups.reduce((total, group) => total + (group.members ? group.members.length : 0), 0);
    }

    get isSendDisabled() {
        return this.isSending || this.hasSent || this.totalMemberCount === 0;
    }

    async handleNotifyClick() {
        this.isSending = true;
        try {
            await sendNotifications({ proposalIds: this.recordIds });
            this.hasSent = true;
            this.showToast('Success', 'Grant Team Members have been notified.', 'success');
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isSending = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body) && error.body.length > 0) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.message || 'Something went wrong.';
    }
}