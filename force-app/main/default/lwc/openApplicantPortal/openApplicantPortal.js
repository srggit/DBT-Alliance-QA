import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import generateLoginToken from '@salesforce/apex/PortalSsoController.generateLoginToken';

import modal from '@salesforce/resourceUrl/CustomModelCSS1';
import { loadStyle } from 'lightning/platformResourceLoader';

/*
 * Route the React app will read the one-time token from. This is the
 * contract with the portal team - confirm the exact path with them and
 * update this constant to match.
 */
const PORTAL_SSO_URL = 'https://dbt-react-d198b.web.app/sso-login';
const PORTAL_LOGIN_URL = 'https://dbt-react-d198b.web.app/login';

export default class OpenApplicantPortal extends LightningElement {
    _recordId;
    hasRun = false;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this.tryRun();
    }

    // Fallback: some record-action contexts don't populate @api recordId in
    // time (or at all), but the record Id is still present in the page URL.
    @wire(CurrentPageReference)
    wiredPageReference(pageReference) {
        if (!this._recordId) {
            const urlRecordId =
                pageReference?.state?.recordId ||
                pageReference?.attributes?.recordId ||
                pageReference?.state?.c__recordId;
            if (urlRecordId) {
                this._recordId = urlRecordId;
                this.tryRun();
            }
        }
    }

    connectedCallback() {
        debugger;
        loadStyle(this, modal)
            .then(() => {
                console.log('Modal CSS loaded');
            })
            .catch(error => {
                console.error('CSS load failed', error);
            });
    }

    renderedCallback() {
        this.tryRun();
    }

    tryRun() {
        if (this.hasRun || !this._recordId) {
            return;
        }
        this.hasRun = true;
        this.openPortal();
    }

    async openPortal() {
        // Open the tab synchronously, before the await below, so browsers still
        // treat it as a direct result of the user's click and don't block it.
        // We redirect this tab once we know the final URL.
        const newTab = window.open('', '_blank');

        try {
            const token = await generateLoginToken({ proposalId: this._recordId });
            // this.navigate(newTab, `${PORTAL_SSO_URL}?token=${encodeURIComponent(token)}`);
            this.navigate(newTab, `${PORTAL_LOGIN_URL}?token=${encodeURIComponent(token)}&proposalId=${encodeURIComponent(this._recordId)}`);
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
            // Fall back to the plain login page so the user isn't stuck with no way in.
            this.navigate(newTab, PORTAL_LOGIN_URL);
        } finally {
            this.closeAction();
        }
    }

    navigate(targetWindow, url) {
        try {
            if (targetWindow && !targetWindow.closed) {
                targetWindow.location = url;
                return;
            }
        } catch (e) {
            // targetWindow exists but couldn't be redirected (Locker/LWS
            // sandboxing, cross-origin quirk, etc.) - fall through below.
        }
        // Either the popup was blocked, or redirecting the captured
        // reference failed - try a plain, direct window.open as a fallback.
        window.open(url, '_blank');
    }

    closeAction() {
        // Deferring by a tick ensures the action panel's own listener is
        // registered before this event is dispatched, so it reliably closes.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.dispatchEvent(new CloseActionScreenEvent());
        }, 0);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        return error?.body?.message || error?.message || 'Unable to open the Applicant Portal.';
    }
}