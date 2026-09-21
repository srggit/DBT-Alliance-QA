import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import { CloseActionScreenEvent } from 'lightning/actions';
import getConversation from '@salesforce/apex/CaseMessagesController.getConversation';
import sendReply from '@salesforce/apex/CaseMessagesController.sendReply';

export default class CaseMessages extends LightningElement {
    _recordId;
    _loaded = false;

    header = {};
    messages = [];
    replyBody = '';
    isLoading = false;
    isSending = false;
    errorMessage;

    _scrollPending = false;

    // recordId is injected on a record page / record action. It can arrive
    // slightly after connectedCallback, so load from the setter instead.
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        if (value && value !== this._recordId) {
            this._recordId = value;
            this.loadConversation(true);
        }
    }

    // Fallback 1: pull the Case Id from the page reference (state / attributes).
    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (this._recordId || !pageRef) {
            return;
        }
        const fromRef =
            pageRef.attributes?.recordId ||
            pageRef.state?.recordId ||
            pageRef.state?.c__recordId;
        if (fromRef) {
            this._recordId = fromRef;
            this.loadConversation(true);
        }
    }

    connectedCallback() {
        if (!this._recordId) {
            // Fallback 2: parse the Case Id out of the browser URL.
            const fromUrl = this.extractRecordIdFromUrl();
            if (fromUrl) {
                this._recordId = fromUrl;
            }
        }
        if (this._recordId) {
            this.loadConversation(true);
        }
    }

    renderedCallback() {
        if (this._scrollPending) {
            this._scrollPending = false;
            this.scrollToBottom();
        }
    }

    get hasMessages() {
        return this.messages.length > 0;
    }

    get sendDisabled() {
        return this.isSending || !this._recordId || this.stripHtml(this.replyBody).length === 0;
    }

    async loadConversation(markRead) {
        if (!this._recordId || this._loaded) {
            return;
        }
        this._loaded = true;
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const conv = await getConversation({ caseId: this._recordId, markRead });
            this.applyConversation(conv);
        } catch (error) {
            this._loaded = false;
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleReplyChange(event) {
        this.replyBody = event.target.value;
    }

    async handleSend() {
        if (this.sendDisabled) {
            return;
        }
        this.isSending = true;
        this.errorMessage = undefined;
        try {
            const conv = await sendReply({ caseId: this._recordId, body: this.replyBody });
            this.replyBody = '';
            this.applyConversation(conv);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Reply sent',
                    message: 'Your message has been added to the conversation.',
                    variant: 'success'
                })
            );
            if (this._recordId) {
                getRecordNotifyChange([{ recordId: this._recordId }]);
            }
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isSending = false;
        }
    }

    handleUploadFinished() {
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Attachment added',
                message: 'File attached to the case.',
                variant: 'success'
            })
        );
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    applyConversation(conv) {
        this.header = {
            caseNumber: conv.caseNumber,
            subject: conv.subject,
            status: conv.status,
            createdDate: conv.createdDate,
            applicantName: conv.applicantName,
            committeeMemberName: conv.committeeMemberName,
            committeeMemberOrg: conv.committeeMemberOrg
        };
        this.messages = (conv.messages || []).map((m, idx) => ({
            ...m,
            key: m.id || `tmp-${idx}`,
            rowClass: m.inbound ? 'msg-row msg-row_inbound' : 'msg-row msg-row_outbound',
            bubbleClass: m.inbound
                ? 'msg-bubble msg-bubble_inbound'
                : 'msg-bubble msg-bubble_outbound',
            // "Seen" indicator only on the Grant Team's outbound messages.
            showStatus: !m.inbound,
            statusLabel: m.readByCommittee ? 'Seen' : 'Delivered',
            statusClass: m.readByCommittee ? 'msg-status msg-status_seen' : 'msg-status'
        }));
        this._scrollPending = true;
    }

    // Matches an 18- or 15-char Salesforce Id in a Lightning or Classic URL.
    extractRecordIdFromUrl() {
        try {
            const url = window.location.href;
            const patterns = [
                /\/lightning\/r\/(?:[^/]+\/)?([a-zA-Z0-9]{18}|[a-zA-Z0-9]{15})(?:\/|$|\?)/,
                /[?&](?:recordId|c__recordId|id)=([a-zA-Z0-9]{18}|[a-zA-Z0-9]{15})/,
                /\/([a-zA-Z0-9]{18}|[a-zA-Z0-9]{15})(?:\/view|\/edit|$)/
            ];
            for (const re of patterns) {
                const match = url.match(re);
                if (match && match[1]) {
                    return match[1];
                }
            }
        } catch (e) {
            // window not available / parsing failed - ignore
        }
        return undefined;
    }

    scrollToBottom() {
        const container = this.template.querySelector('.msg-scroll');
        if (container) {
            container.scrollTop = container.scrollHeight;
        }
    }

    stripHtml(value) {
        if (!value) {
            return '';
        }
        return value
            .replace(/<[^>]+>/g, ' ')
            .replace(/&nbsp;/g, ' ')
            .replace(/\s+/g, ' ')
            .trim();
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