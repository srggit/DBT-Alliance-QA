import { LightningElement, api } from 'lwc';

const INK = '#1E2333';
const SUBTLE = '#8791A8';
const LINE = '#E7E9F0';
const LINE_MONTH = '#E2E5EE';
const LINE_MID = '#C9CEDD';
const LINE_YEAR = '#AEB4C9';
const ACCENTS = ['#4F5FE0', '#0E9F8E', '#DB7A2C', '#C24169', '#7C5CD6', '#2C9AB7'];

const LABEL_COL_WIDTH = 190;
const YEAR_ROW_H = 24;
const HALF_ROW_H = 18;
const MONTH_ROW_H = 20;
const HEADER_H = YEAR_ROW_H + HALF_ROW_H + MONTH_ROW_H;
const ROW_H = 46;
const PX_PER_YEAR = 312;
const MONTH_PX = PX_PER_YEAR / 12;
const MONTH_ABBR = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const MS_PER_DAY = 1000 * 60 * 60 * 24;

// Accepts 'YYYY-MM-DD' (Date fields) or any Date-parsable value; returns a local Date.
function parseDate(value) {
    if (!value || value === '-') return null;
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(value));
    const d = m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : new Date(value);
    return Number.isNaN(d.getTime()) ? null : d;
}

const fmtFull = (d) => d.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
const daysBetween = (a, b) => Math.max(1, Math.round((b - a) / MS_PER_DAY));
const daysInMonth = (y, m) => new Date(y, m + 1, 0).getDate();

export default class ProjectMilestoneGantt extends LightningElement {
    @api milestones = [];
    hoverIdx = null;

    get parsedRows() {
        return (this.milestones || []).map((m, idx) => {
            const start = parseDate(m.startDate);
            const end = parseDate(m.endDate);
            const label = m.milestone && m.milestone !== '-' ? String(m.milestone).trim() : `Milestone ${idx + 1}`;
            return { idx, label, start, end, valid: !!(start && end && end >= start), color: ACCENTS[idx % ACCENTS.length] };
        });
    }

    get years() {
        const valid = this.parsedRows.filter((r) => r.valid);
        if (!valid.length) return [];
        const minY = Math.min(...valid.map((r) => r.start.getFullYear()));
        const maxY = Math.max(...valid.map((r) => r.end.getFullYear()));
        const list = [];
        for (let y = minY; y <= maxY; y++) list.push(y);
        return list;
    }

    get hasData() {
        return this.parsedRows.length > 0;
    }

    get hasTimeline() {
        return this.years.length > 0;
    }

    get emptyMessage() {
        return this.hasData ? 'Add start and end dates to your milestones to see the timeline.' : 'No milestones to display yet.';
    }

    get timelineStyle() {
        return `width:${this.years.length * PX_PER_YEAR}px`;
    }

    get labelColStyle() {
        return `width:${LABEL_COL_WIDTH}px`;
    }

    get labelHeaderStyle() {
        return `height:${HEADER_H}px`;
    }

    get yearCells() {
        return this.years.map((y) => ({
            key: `y${y}`,
            label: String(y),
            style: `width:${PX_PER_YEAR}px;height:${YEAR_ROW_H}px;border-left:1px solid ${LINE_YEAR};color:${INK}`
        }));
    }

    get halfCells() {
        const cells = [];
        this.years.forEach((y) => {
            [['Jan – Jun', LINE_YEAR], ['Jul – Dec', LINE_MID]].forEach(([label, border], i) => {
                cells.push({
                    key: `h${y}-${i}`,
                    label,
                    style: `width:${PX_PER_YEAR / 2}px;height:${HALF_ROW_H}px;border-left:1px solid ${border};color:${SUBTLE}`
                });
            });
        });
        return cells;
    }

    get monthCells() {
        const cells = [];
        this.years.forEach((y) => {
            MONTH_ABBR.forEach((label, m) => {
                const border = m === 6 ? LINE_MID : m === 0 ? LINE_YEAR : LINE_MONTH;
                cells.push({
                    key: `m${y}-${m}`,
                    label,
                    style: `width:${MONTH_PX}px;height:${MONTH_ROW_H}px;border-left:1px solid ${border};border-bottom:1px solid ${LINE_YEAR};color:${SUBTLE}`
                });
            });
        });
        return cells;
    }

    // Position in "equal month units" so bars line up with the equal-width month columns.
    percentFor(date, minYear, totalMonths) {
        const dim = daysInMonth(date.getFullYear(), date.getMonth());
        const units = (date.getFullYear() - minYear) * 12 + date.getMonth() + (date.getDate() - 1) / dim;
        return Math.min(Math.max((units / totalMonths) * 100, 0), 100);
    }

    get gridlines() {
        const years = this.years;
        const totalMonths = years.length * 12;
        const lines = [];
        years.forEach((y, yi) => {
            for (let m = 0; m < 12; m++) {
                const color = m === 0 ? LINE_YEAR : m === 6 ? LINE_MID : LINE_MONTH;
                lines.push({
                    key: `g${y}-${m}`,
                    style: `left:${((yi * 12 + m) / totalMonths) * 100}%;border-left:1px solid ${color}`
                });
            }
        });
        return lines;
    }

    get rows() {
        const years = this.years;
        if (!years.length) return [];
        const minYear = years[0];
        const totalMonths = years.length * 12;
        const gridlines = this.gridlines;
        const lastIdx = this.parsedRows.length - 1;

        return this.parsedRows.map((r, i) => {
            const hovered = this.hoverIdx === r.idx;
            const bg = i % 2 === 1 ? '#FBFBFD' : '#FFFFFF';
            const row = {
                key: `r${r.idx}`,
                idx: r.idx,
                label: r.label,
                valid: r.valid,
                gridlines,
                labelStyle: `height:${ROW_H}px;background:${bg}`,
                dotStyle: `background:${r.valid ? r.color : LINE}`,
                rowStyle: `height:${ROW_H}px;background:${bg};z-index:${hovered ? 50 : 0}`,
                showTooltip: hovered && r.valid
            };
            if (r.valid) {
                const left = this.percentFor(r.start, minYear, totalMonths);
                const right = this.percentFor(r.end, minYear, totalMonths);
                row.barStyle =
                    `left:${left}%;width:${Math.max(right - left, 1)}%;background:${r.color};` +
                    (hovered ? 'box-shadow:0 0 0 2px rgba(0,0,0,0.08)' : '');
                row.tooltipStyle = i === lastIdx ? 'bottom:calc(100% + 8px);left:0' : 'top:calc(100% + 8px);left:0';
                row.tooltipText = `${fmtFull(r.start)} — ${fmtFull(r.end)} (${daysBetween(r.start, r.end)}d)`;
            }
            return row;
        });
    }

    handleBarEnter(event) {
        this.hoverIdx = Number(event.currentTarget.dataset.idx);
    }

    handleBarLeave() {
        this.hoverIdx = null;
    }
}