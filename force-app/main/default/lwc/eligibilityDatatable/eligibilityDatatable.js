import LightningDatatable from 'lightning/datatable';
import badgeCellTemplate from './badgeCell.html';
import proposalCellTemplate from './proposalCell.html';
import schemeCellTemplate from './schemeCell.html';
import dateCellTemplate from './dateCell.html';

export default class EligibilityDatatable extends LightningDatatable {
    static customTypes = {
        badgeCell: {
            template: badgeCellTemplate,
            standardCellLayout: true,
            typeAttributes: ['badgeClass']
        },
        proposalCell: {
            template: proposalCellTemplate,
            standardCellLayout: true,
            typeAttributes: ['line2']
        },
        schemeCell: {
            template: schemeCellTemplate,
            standardCellLayout: true,
            typeAttributes: ['line2']
        },
        dateCell: {
            template: dateCellTemplate,
            standardCellLayout: true,
            typeAttributes: ['line2']
        }
    };
}