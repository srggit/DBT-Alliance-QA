/**
* @description Combined REST API returning the full Proposal Budget breakdown
*              (Personal Support, Staff, Materials, Equipment, Access Charges,
*              Animals, Travel to Meetings, WOHI Allowance, Miscellaneous, FA).
*
* Endpoint : /services/apexrest/ProposalBudget/
* Params   : proposalId (required unless apaId supplied)
*            apaId       (optional - if omitted, earliest APA for the proposal is used)
*/
 
@RestResource(urlMapping='/ProposalBudget/*')
global without sharing class GetProposalBudgetAPI {

    @HttpGet
    global static void doGet() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            String proposalId = req.params.get('proposalId');
            String apaId      = req.params.get('apaId');

            if (String.isBlank(proposalId) && String.isBlank(apaId)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new Map<String, String>{ 'error' => 'proposalId is required (apaId is optional).' }
                ));
                return;
            }

            // If only apaId was passed, resolve proposalId from it first
            // (resolveAPARecord() always filters by Proposal__c, so we need it either way).
            if (String.isBlank(proposalId) && String.isNotBlank(apaId)) {
                List<Applicant_Proposal_Association__c> seed = [
                    SELECT Id, Proposal__c
                    FROM Applicant_Proposal_Association__c
                    WHERE Id = :apaId
                    LIMIT 1
                ];
                if (seed.isEmpty()) {
                    res.statusCode = 404;
                    res.responseBody = Blob.valueOf(JSON.serialize(
                        new Map<String, String>{ 'error' => 'No Applicant Proposal Association found for apaId: ' + apaId }
                    ));
                    return;
                }
                proposalId = seed[0].Proposal__c;
            }

            BudgetResponseWrapper response = getBudgetDetails(proposalId, apaId);

            if (response == null) {
                res.statusCode = 404;
                res.responseBody = Blob.valueOf(JSON.serialize(
                    new Map<String, String>{ 'error' => 'No Applicant Proposal Association found for the given Id(s).' }
                ));
                return;
            }

            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(response));
        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(
                new Map<String, String>{ 'error' => e.getMessage() + ' | Line: ' + e.getLineNumber() }
            ));
        }
    }

    // ============================================================
    // ORCHESTRATOR
    // ============================================================
    public static BudgetResponseWrapper getBudgetDetails(String proposalId, String apaId) {
        SObject resolved = resolveAPARecord(proposalId, apaId);
        if (resolved == null) {
            return null;
        }

        Id resolvedApaId = resolved.Id;

        // ---- Single query for every field that lives directly on the APA record ----
        Applicant_Proposal_Association__c apa = [
            SELECT Id, Proposal__c,
                   // A. Personal Support
                   Personal_Support_Justification__c,
                   Host_Salary_Year1__c, Host_Salary_Year2__c, Host_Salary_Year3__c, Host_Salary_Year4__c, Host_Salary_Year5__c, Total_Host_Salary__c,
                   IA_Salary_Year1__c, IA_Salary_Year2__c, IA_Salary_Year3__c, IA_Salary_Year4__c, IA_Salary_Year5__c, Total_IA_Salary__c,
                   Personal_Salary_Year1__c, Personal_Salary_Year2__c, Personal_Salary_Year3__c, Personal_Salary_Year4__c, Personal_Salary_Year5__c, Total_Personal_Salary__c,
                   // B/C/E justifications
                   Staff_and_Salary_Justification__c, Material_Justification__c, Access_Charges_Justification__c,
                   // D. Equipment justification
                   Equipment_Justification__c,
                   // G. Travel to Meetings
                   Travel_to_Meetings_Cost__c, Travel_to_Meetings_Year__c, Travel_to_Meetings_Justification__c,
                   // I. Miscellaneous justification
                   Miscellaneous_Justification__c,
                   // J. Flexible Funding Allowance
                   FA_for_Year1__c, FA_for_Year2__c, FA_for_Year3__c, FA_for_Year4__c, FA_for_Year5__c, Total_FA_cost__c
            FROM Applicant_Proposal_Association__c
            WHERE Id = :resolvedApaId
            LIMIT 1
        ];

        BudgetResponseWrapper response = new BudgetResponseWrapper();
        response.apaId       = apa.Id;
        response.proposalId  = apa.Proposal__c;

        response.personalSupport          = buildPersonalSupportWrapper(apa);
        response.travelToMeetings         = buildTravelToMeetingsWrapper(apa);
        response.flexibleFundingAllowance = buildFlexibleFundingAllowanceWrapper(apa);

        buildStaffMaterialsAndAccessCharges(apa, response);

        response.equipment     = buildEquipmentWrapper(apa.Id, apa.Equipment_Justification__c);
        response.miscellaneous = buildMiscellaneousWrapper(apa.Id, apa.Miscellaneous_Justification__c);
        response.wohiAllowance = buildWOHIAllowanceWrapper(apa.Id);
        // Animals__c is linked to Proposal (Master-Detail), NOT to the APA.
        response.animals       = buildAnimalsWrapper(apa.Proposal__c);

        // K. Grand Total — lives on Proposal__c itself (rollup/stored field), not on the APA.
        response.grandTotal    = buildGrandTotalWrapper(apa.Proposal__c);

        return response;
    }

    // ============================================================
    // A. PERSONAL SUPPORT  (Image 1)
    // ============================================================
    private static PersonalSupportWrapper buildPersonalSupportWrapper(Applicant_Proposal_Association__c a) {
        PersonalSupportWrapper w = new PersonalSupportWrapper();
        w.justification = a.Personal_Support_Justification__c;

        w.hostSalaryYear1 = a.Host_Salary_Year1__c; w.hostSalaryYear2 = a.Host_Salary_Year2__c;
        w.hostSalaryYear3 = a.Host_Salary_Year3__c; w.hostSalaryYear4 = a.Host_Salary_Year4__c;
        w.hostSalaryYear5 = a.Host_Salary_Year5__c; w.totalHostSalary = a.Total_Host_Salary__c;

        w.iaSalaryYear1 = a.IA_Salary_Year1__c; w.iaSalaryYear2 = a.IA_Salary_Year2__c;
        w.iaSalaryYear3 = a.IA_Salary_Year3__c; w.iaSalaryYear4 = a.IA_Salary_Year4__c;
        w.iaSalaryYear5 = a.IA_Salary_Year5__c; w.totalIASalary = a.Total_IA_Salary__c;

        w.personalSalaryYear1 = a.Personal_Salary_Year1__c; w.personalSalaryYear2 = a.Personal_Salary_Year2__c;
        w.personalSalaryYear3 = a.Personal_Salary_Year3__c; w.personalSalaryYear4 = a.Personal_Salary_Year4__c;
        w.personalSalaryYear5 = a.Personal_Salary_Year5__c; w.totalPersonalSalary = a.Total_Personal_Salary__c;

        w.personalSupportGrandTotal = nz(a.Total_Host_Salary__c) + nz(a.Total_IA_Salary__c) + nz(a.Total_Personal_Salary__c);
        return w;
    }

    // ============================================================
    // B / C / E — Staff, Materials & Consumables, Access Charges  (Images 2, 3, 5)
    // All three share the Staff_Budget__c object, differentiated by RecordType.
    // ⚠ VERIFY the RecordType.DeveloperName values in org before deploying.
    // ============================================================
    private static void buildStaffMaterialsAndAccessCharges(Applicant_Proposal_Association__c a, BudgetResponseWrapper response) {
        response.staff         = new StaffWrapper();
        response.materials     = new MaterialsWrapper();
        response.accessCharges = new AccessChargesWrapper();

        response.staff.justification         = a.Staff_and_Salary_Justification__c;
        response.materials.justification     = a.Material_Justification__c;
        response.accessCharges.justification = a.Access_Charges_Justification__c;

        List<Staff_Budget__c> lineItems = [
            SELECT Id, Name, Applicant_Proposal_Association__c, Job_Title__c, Other_Job_title__c,
                   Material_Name__c, Total__c, Year_1__c, Year_2__c, Year_3__c, Year_4__c, Year_5__c,
                   RecordTypeId, RecordType.DeveloperName, RecordType.Name
            FROM Staff_Budget__c
            WHERE Applicant_Proposal_Association__c = :a.Id
        ];

        for (Staff_Budget__c item : lineItems) {
            String rtName = item.RecordType != null ? item.RecordType.DeveloperName : '';
            BudgetLineItemWrapper line = toBudgetLineItem(item);

            if (rtName.containsIgnoreCase('Staff')) {
                response.staff.items.add(line);
            } else if (rtName.containsIgnoreCase('Materials_and_Consumables')) {
                response.materials.items.add(line);
            } else if (rtName.containsIgnoreCase('Access_Charges')) {
                response.accessCharges.items.add(line);
            }
            // else: unmapped RecordType — silently skipped; verify RT names if items go missing
        }

        applyTotals(response.staff.items, response.staff);
        applyTotals(response.materials.items, response.materials);
        applyTotals(response.accessCharges.items, response.accessCharges);
    }

    private static BudgetLineItemWrapper toBudgetLineItem(Staff_Budget__c item) {
        BudgetLineItemWrapper line = new BudgetLineItemWrapper();
        line.recordId = item.Id;
        line.label = String.isNotBlank(item.Job_Title__c) ? item.Job_Title__c
                    : String.isNotBlank(item.Other_Job_title__c) ? item.Other_Job_title__c
                    : item.Material_Name__c;
        line.otherLabel = item.Other_Job_title__c;
        line.year1 = item.Year_1__c; line.year2 = item.Year_2__c; line.year3 = item.Year_3__c;
        line.year4 = item.Year_4__c; line.year5 = item.Year_5__c;
        line.totalCost = item.Total__c;
        return line;
    }

    // Shared "Total" row + grand total calculator for Staff / Materials / Access Charges
    private static void applyTotals(List<BudgetLineItemWrapper> items, BudgetSectionTotalsWrapper section) {
        Decimal t1 = 0, t2 = 0, t3 = 0, t4 = 0, t5 = 0, grand = 0;
        for (BudgetLineItemWrapper li : items) {
            t1 += nz(li.year1); t2 += nz(li.year2); t3 += nz(li.year3);
            t4 += nz(li.year4); t5 += nz(li.year5); grand += nz(li.totalCost);
        }
        section.totalYear1 = t1; section.totalYear2 = t2; section.totalYear3 = t3;
        section.totalYear4 = t4; section.totalYear5 = t5; section.grandTotal = grand;
    }

    // ============================================================
    // D. EQUIPMENT  (Image 4)
    // ============================================================
    private static EquipmentWrapper buildEquipmentWrapper(Id apaId, String justification) {
        EquipmentWrapper w = new EquipmentWrapper();
        w.justification = justification;

        List<Equipment__c> equipRecords = [
            SELECT Id, Name, Applicant_Proposal_Association__c, Equipment_Name__c, Cost_per_Item__c,
                   Contribution_from_other_sources__c, Maintain_Charges__c, Quantity__c,
                   Total_Charges__c, Year_Required__c
            FROM Equipment__c
            WHERE Applicant_Proposal_Association__c = :apaId
        ];

        Decimal grand = 0;
        for (Equipment__c e : equipRecords) {
            EquipmentItemWrapper item = new EquipmentItemWrapper();
            item.recordId = e.Id;
            item.equipmentName = e.Equipment_Name__c;
            item.quantity = e.Quantity__c;
            item.costPerItem = e.Cost_per_Item__c;
            item.maintainCharges = e.Maintain_Charges__c;
            item.contributionFromOtherSources = e.Contribution_from_other_sources__c;
            item.yearRequired = e.Year_Required__c;
            item.totalCost = e.Total_Charges__c;
            w.items.add(item);
            grand += nz(e.Total_Charges__c);
        }
        w.grandTotal = grand;
        return w;
    }

    // ============================================================
    // I. MISCELLANEOUS  (Image 8)
    // ============================================================
    private static MiscellaneousWrapper buildMiscellaneousWrapper(Id apaId, String justification) {
        MiscellaneousWrapper w = new MiscellaneousWrapper();
        w.justification = justification;

        List<Miscellaneous__c> miscRecords = [
            SELECT Id, Name, Applicant_Proposal_Association__c, Cost_Description__c,
                   Year_1_Cost__c, Year_2_Cost__c, Year_3_Cost__c, Year_4_Cost__c, Year_5_Cost__c, Total_Cost__c
            FROM Miscellaneous__c
            WHERE Applicant_Proposal_Association__c = :apaId
        ];

        Decimal t1 = 0, t2 = 0, t3 = 0, t4 = 0, t5 = 0, grand = 0;
        for (Miscellaneous__c m : miscRecords) {
            MiscellaneousItemWrapper item = new MiscellaneousItemWrapper();
            item.recordId = m.Id;
            item.itemDescription = m.Cost_Description__c;
            item.year1 = m.Year_1_Cost__c; item.year2 = m.Year_2_Cost__c; item.year3 = m.Year_3_Cost__c;
            item.year4 = m.Year_4_Cost__c; item.year5 = m.Year_5_Cost__c;
            item.totalCost = m.Total_Cost__c;
            w.items.add(item);
            t1 += nz(m.Year_1_Cost__c); t2 += nz(m.Year_2_Cost__c); t3 += nz(m.Year_3_Cost__c);
            t4 += nz(m.Year_4_Cost__c); t5 += nz(m.Year_5_Cost__c); grand += nz(m.Total_Cost__c);
        }
        w.totalYear1 = t1; w.totalYear2 = t2; w.totalYear3 = t3; w.totalYear4 = t4; w.totalYear5 = t5;
        w.grandTotal = grand;
        return w;
    }

    // ============================================================
    // G. TRAVEL TO MEETINGS  (Image 6)
    // ============================================================
    private static TravelToMeetingsWrapper buildTravelToMeetingsWrapper(Applicant_Proposal_Association__c a) {
        TravelToMeetingsWrapper w = new TravelToMeetingsWrapper();
        w.requestedAmount = a.Travel_to_Meetings_Cost__c;
        w.yearRequired = a.Travel_to_Meetings_Year__c;
        w.justification = a.Travel_to_Meetings_Justification__c;
        return w;
    }

    // ============================================================
    // H. WOHI ALLOWANCE  (Image 7)
    // ============================================================
    private static WOHIAllowanceWrapper buildWOHIAllowanceWrapper(Id apaId) {
        WOHIAllowanceWrapper w = new WOHIAllowanceWrapper();

        List<WOHI_Allowance__c> wohiRecords = [
            SELECT Id, Name, Allowance_Type__c, Applicant_Proposal_Association__c,
                   Year1_Cost__c, Year2_Cost__c, Year3_Cost__c, Year4_Cost__c, Year5_Cost__c, Total_Cost__c
            FROM WOHI_Allowance__c
            WHERE Applicant_Proposal_Association__c = :apaId
        ];

        Decimal t1 = 0, t2 = 0, t3 = 0, t4 = 0, t5 = 0, grand = 0;
        for (WOHI_Allowance__c wa : wohiRecords) {
            WOHIAllowanceItemWrapper item = new WOHIAllowanceItemWrapper();
            item.recordId = wa.Id;
            item.allowanceType = wa.Allowance_Type__c;
            item.year1 = wa.Year1_Cost__c; item.year2 = wa.Year2_Cost__c; item.year3 = wa.Year3_Cost__c;
            item.year4 = wa.Year4_Cost__c; item.year5 = wa.Year5_Cost__c;
            item.totalCost = wa.Total_Cost__c;
            w.items.add(item);
            t1 += nz(wa.Year1_Cost__c); t2 += nz(wa.Year2_Cost__c); t3 += nz(wa.Year3_Cost__c);
            t4 += nz(wa.Year4_Cost__c); t5 += nz(wa.Year5_Cost__c); grand += nz(wa.Total_Cost__c);
        }
        w.totalYear1 = t1; w.totalYear2 = t2; w.totalYear3 = t3; w.totalYear4 = t4; w.totalYear5 = t5;
        w.grandTotal = grand;
        return w;
    }

    // ============================================================
    // J. FLEXIBLE FUNDING ALLOWANCE  (Image 9)
    // ============================================================
    private static FlexibleFundingAllowanceWrapper buildFlexibleFundingAllowanceWrapper(Applicant_Proposal_Association__c a) {
        FlexibleFundingAllowanceWrapper w = new FlexibleFundingAllowanceWrapper();
        w.year1 = a.FA_for_Year1__c; w.year2 = a.FA_for_Year2__c; w.year3 = a.FA_for_Year3__c;
        w.year4 = a.FA_for_Year4__c; w.year5 = a.FA_for_Year5__c;
        w.totalCost = a.Total_FA_cost__c;
        return w;
    }

    // ============================================================
    // F. ANIMALS  (Images 10, 11) — wrapper-within-wrapper
    // Animals__c → Proposal__c (Master-Detail).  Children:
    //   Animal_Species__c            (child relationship Animal_Species__r)
    //   Animal_Associated_costs__c   (child relationship Animal_Associated_costs__r)
    // ============================================================
    private static AnimalsWrapper buildAnimalsWrapper(Id proposalId) {
        List<Animals__c> animalRecords = [
            SELECT Id, Name,
                   Animal_Purchase_Cost_Justification__c,
                   Animal_Maintenance_Cost_Justification__c,
                   Animal_Exp_Procedure_Cost_Justification__c,
                   Animal_Associated_Cost_Justification__c,
                   (SELECT Id, Name, Animal_Species__c, Animal_Strain__c, Animals__c, No_of_Animals__c,
                           Purchase_cost_per_animal__c, Purchase_total_number__c, Purchase_Year_Required__c, Source_of_supply__c,
                           Maintenance_cost_per_animal__c, Maintenance_total_number__c, Maintenance_Year_Required__c, Institute_Place_for_Maintenance__c,
                           Exp_Procedure_cost_per_animal__c, Exp_Procedure_total_number__c, Exp_Procedure_Year_Required__c,
                           Experiment_Title__c, Group__c, Institute_Place_for_Exp_Procedure__c,
                           Exp_Procedure_Total_cost__c, Maintenance_Total_cost__c, Purchase_Total_cost__c
                    FROM Animal_Species__r),
                   (SELECT Id, Name, Animals__c, Cost_Description__c, Total_Cost__c,
                           Year_1_Cost__c, Year_2_Cost__c, Year_3_Cost__c, Year_4_Cost__c, Year_5_Cost__c
                    FROM Animal_Associated_costs__r)
            FROM Animals__c
            WHERE Proposal__c = :proposalId
            LIMIT 1
        ];

        if (animalRecords.isEmpty()) {
            return null;
        }

        Animals__c animalRec = animalRecords[0];

        AnimalsWrapper wrapper = new AnimalsWrapper();
        wrapper.animalRecordId = animalRec.Id;
        wrapper.purchaseJustification        = animalRec.Animal_Purchase_Cost_Justification__c;
        wrapper.maintenanceJustification     = animalRec.Animal_Maintenance_Cost_Justification__c;
        wrapper.expProcedureJustification    = animalRec.Animal_Exp_Procedure_Cost_Justification__c;
        wrapper.associatedCostJustification  = animalRec.Animal_Associated_Cost_Justification__c;

        wrapper.animalPurchase       = new AnimalPurchaseWrapper();
        wrapper.animalMaintenance    = new AnimalMaintenanceWrapper();
        wrapper.animalExpProcedures  = new AnimalExpProcedureWrapper();
        wrapper.animalAssociatedCosts = new AnimalAssociatedCostWrapper();

        Decimal purchaseGrand = 0, maintenanceGrand = 0, expProcedureGrand = 0, associatedGrand = 0;

        for (Animal_Species__c species : animalRec.Animal_Species__r) {
            String speciesLabel = buildSpeciesLabel(species.Animal_Species__c, species.Animal_Strain__c);

            // -- Animal Purchase (Image 10, top table) --
            if (species.Purchase_total_number__c != null || species.Purchase_Total_cost__c != null) {
                AnimalPurchaseItemWrapper item = new AnimalPurchaseItemWrapper();
                item.recordId = species.Id;
                item.speciesSource = speciesLabel;
                item.quantity = species.Purchase_total_number__c;
                item.costPerAnimal = species.Purchase_cost_per_animal__c;
                item.source = species.Source_of_supply__c;
                item.yearRequired = species.Purchase_Year_Required__c;
                item.totalCost = species.Purchase_Total_cost__c;
                wrapper.animalPurchase.items.add(item);
                purchaseGrand += nz(species.Purchase_Total_cost__c);
            }

            // -- Animal Maintenance (Image 10, bottom table) --
            if (species.Maintenance_total_number__c != null || species.Maintenance_Total_cost__c != null) {
                AnimalMaintenanceItemWrapper item = new AnimalMaintenanceItemWrapper();
                item.recordId = species.Id;
                item.speciesSource = speciesLabel;
                item.quantity = species.Maintenance_total_number__c;
                item.costPerAnimal = species.Maintenance_cost_per_animal__c;
                item.source = species.Institute_Place_for_Maintenance__c;
                item.yearRequired = species.Maintenance_Year_Required__c;
                item.totalCost = species.Maintenance_Total_cost__c;
                wrapper.animalMaintenance.items.add(item);
                maintenanceGrand += nz(species.Maintenance_Total_cost__c);
            }

            // -- Animal Experimental Procedures (Image 11, top table) --
            if (species.Exp_Procedure_total_number__c != null || species.Exp_Procedure_Total_cost__c != null) {
                AnimalExpProcedureItemWrapper item = new AnimalExpProcedureItemWrapper();
                item.recordId = species.Id;
                item.speciesDetails = speciesLabel + ' (' + (String.isNotBlank(species.Group__c) ? species.Group__c : '-') + ')';
                item.quantity = species.Exp_Procedure_total_number__c;
                item.costPerAnimal = species.Exp_Procedure_cost_per_animal__c;
                item.source = species.Institute_Place_for_Exp_Procedure__c;
                item.experimentTitle = species.Experiment_Title__c;
                item.groupName = species.Group__c;
                item.yearRequired = species.Exp_Procedure_Year_Required__c;
                item.totalCost = species.Exp_Procedure_Total_cost__c;
                wrapper.animalExpProcedures.items.add(item);
                expProcedureGrand += nz(species.Exp_Procedure_Total_cost__c);
            }
        }

        // -- Animal Associated Costs (Image 11, bottom table) --
        for (Animal_Associated_costs__c cost : animalRec.Animal_Associated_costs__r) {
            AnimalAssociatedCostItemWrapper item = new AnimalAssociatedCostItemWrapper();
            item.recordId = cost.Id;
            item.itemDescription = cost.Cost_Description__c;
            item.year1 = cost.Year_1_Cost__c; item.year2 = cost.Year_2_Cost__c; item.year3 = cost.Year_3_Cost__c;
            item.year4 = cost.Year_4_Cost__c; item.year5 = cost.Year_5_Cost__c;
            item.totalCost = cost.Total_Cost__c;
            wrapper.animalAssociatedCosts.items.add(item);
            associatedGrand += nz(cost.Total_Cost__c);
        }

        wrapper.animalPurchase.grandTotal        = purchaseGrand;
        wrapper.animalMaintenance.grandTotal      = maintenanceGrand;
        wrapper.animalExpProcedures.grandTotal    = expProcedureGrand;
        wrapper.animalAssociatedCosts.grandTotal  = associatedGrand;

        return wrapper;
    }

    // ============================================================
    // K. GRAND TOTAL (Proposal-level rollup fields)
    // These 6 fields live directly on Proposal__c, not on the APA or any
    // child budget object. They appear to be either formula/rollup fields
    // or fields maintained by a separate process — verify which before relying
    // on them for real-time accuracy after an unsaved edit.
    // ============================================================
    private static ProposalGrandTotalWrapper buildGrandTotalWrapper(Id proposalId) {
        if (proposalId == null) {
            return null;
        }

        List<Proposal__c> proposalRecords = [
            SELECT Id,
                   Grand_Total_Cost__c,
                   Grand_Total_Year1__c,
                   Grand_Total_Year2__c,
                   Grand_Total_Year3__c,
                   Grand_Total_Year4__c,
                   Grand_Total_Year5__c
            FROM Proposal__c
            WHERE Id = :proposalId
            LIMIT 1
        ];

        if (proposalRecords.isEmpty()) {
            return null;
        }

        Proposal__c p = proposalRecords[0];

        ProposalGrandTotalWrapper w = new ProposalGrandTotalWrapper();
        w.grandTotalCost  = p.Grand_Total_Cost__c;
        w.grandTotalYear1 = p.Grand_Total_Year1__c;
        w.grandTotalYear2 = p.Grand_Total_Year2__c;
        w.grandTotalYear3 = p.Grand_Total_Year3__c;
        w.grandTotalYear4 = p.Grand_Total_Year4__c;
        w.grandTotalYear5 = p.Grand_Total_Year5__c;
        return w;
    }

    private static String buildSpeciesLabel(String species, String strain) {
        String label = String.isNotBlank(species) ? species : '';
        if (String.isNotBlank(strain)) {
            label += ' (' + strain + ')';
        }
        return label;
    }

    // ============================================================
    // SHARED UTILITIES
    // ============================================================
    private static Decimal nz(Decimal val) {
        return val != null ? val : 0;
    }

    private static List<String> getAccessibleFieldNames(Schema.SObjectType sObjType) {
        List<String> fieldNames = new List<String>();
        Map<String, Schema.SObjectField> fieldMap = sObjType.getDescribe().fields.getMap();
        for (Schema.SObjectField field : fieldMap.values()) {
            Schema.DescribeFieldResult dfr = field.getDescribe();
            if (dfr.isAccessible()) {
                fieldNames.add(dfr.getName());
            }
        }
        return fieldNames;
    }

    private static SObject resolveAPARecord(Id proposalId, String apaId) {
        // Pass the SObjectType TOKEN (not Schema.SObjectType.<name>, which returns a DescribeSObjectResult).
        List<String> fieldNames = getAccessibleFieldNames(Applicant_Proposal_Association__c.SObjectType);
        String baseSelect = 'SELECT ' + String.join(fieldNames, ', ')
            + ' FROM Applicant_Proposal_Association__c WHERE Proposal__c = :proposalId';

        List<SObject> results;

        if (String.isNotBlank(apaId)) {
            String query = baseSelect + ' AND Id = :apaId LIMIT 1';
            results = Database.query(query);
        } else {
            String query = baseSelect + ' ORDER BY CreatedDate ASC LIMIT 1';
            results = Database.query(query);
        }

        return results.isEmpty() ? null : results[0];
    }

    // ============================================================
    // WRAPPER CLASSES — one per screenshot section
    // ============================================================

    public class BudgetResponseWrapper {
        public Id apaId;
        public Id proposalId;
        public PersonalSupportWrapper personalSupport;                 // Image 1
        public StaffWrapper staff;                                     // Image 2
        public MaterialsWrapper materials;                             // Image 3
        public EquipmentWrapper equipment;                             // Image 4
        public AccessChargesWrapper accessCharges;                     // Image 5
        public AnimalsWrapper animals;                                 // Images 10 & 11
        public TravelToMeetingsWrapper travelToMeetings;                // Image 6
        public WOHIAllowanceWrapper wohiAllowance;                     // Image 7
        public MiscellaneousWrapper miscellaneous;                     // Image 8
        public FlexibleFundingAllowanceWrapper flexibleFundingAllowance; // Image 9
        public ProposalGrandTotalWrapper grandTotal;                    // K. Proposal-level grand totals
    }

    // ---------- A. Personal Support (Image 1) ----------
    public class PersonalSupportWrapper {
        public String justification;
        public Decimal hostSalaryYear1, hostSalaryYear2, hostSalaryYear3, hostSalaryYear4, hostSalaryYear5, totalHostSalary;
        public Decimal iaSalaryYear1, iaSalaryYear2, iaSalaryYear3, iaSalaryYear4, iaSalaryYear5, totalIASalary;
        public Decimal personalSalaryYear1, personalSalaryYear2, personalSalaryYear3, personalSalaryYear4, personalSalaryYear5, totalPersonalSalary;
        public Decimal personalSupportGrandTotal;
    }

    // Shared base for Staff / Materials / Access Charges (same shape as screenshots 2, 3, 5)
    public virtual class BudgetSectionTotalsWrapper {
        public String justification;
        public List<BudgetLineItemWrapper> items = new List<BudgetLineItemWrapper>();
        public Decimal totalYear1, totalYear2, totalYear3, totalYear4, totalYear5, grandTotal;
    }

    public class BudgetLineItemWrapper {
        public Id recordId;
        public String label;
        public String otherLabel;
        public Decimal year1, year2, year3, year4, year5, totalCost;
    }

    // ---------- B. Staff (Image 2) ----------
    public class StaffWrapper extends BudgetSectionTotalsWrapper {}

    // ---------- C. Materials & Consumables (Image 3) ----------
    public class MaterialsWrapper extends BudgetSectionTotalsWrapper {}

    // ---------- E. Access Charges (Image 5) ----------
    public class AccessChargesWrapper extends BudgetSectionTotalsWrapper {}

    // ---------- D. Equipment (Image 4) ----------
    public class EquipmentWrapper {
        public String justification;
        public List<EquipmentItemWrapper> items = new List<EquipmentItemWrapper>();
        public Decimal grandTotal;
    }
    public class EquipmentItemWrapper {
        public Id recordId;
        public String equipmentName;
        public Decimal quantity;
        public Decimal costPerItem;
        public Decimal maintainCharges;
        public Decimal contributionFromOtherSources;
        public String yearRequired;
        public Decimal totalCost;
    }

    // ---------- G. Travel to Meetings (Image 6) ----------
    public class TravelToMeetingsWrapper {
        public Decimal requestedAmount;
        public String yearRequired;
        public String justification;
    }

    // ---------- H. WOHI Allowance (Image 7) ----------
    public class WOHIAllowanceWrapper {
        public List<WOHIAllowanceItemWrapper> items = new List<WOHIAllowanceItemWrapper>();
        public Decimal totalYear1, totalYear2, totalYear3, totalYear4, totalYear5, grandTotal;
    }
    public class WOHIAllowanceItemWrapper {
        public Id recordId;
        public String allowanceType;
        public Decimal year1, year2, year3, year4, year5, totalCost;
    }

    // ---------- I. Miscellaneous (Image 8) ----------
    public class MiscellaneousWrapper {
        public String justification;
        public List<MiscellaneousItemWrapper> items = new List<MiscellaneousItemWrapper>();
        public Decimal totalYear1, totalYear2, totalYear3, totalYear4, totalYear5, grandTotal;
    }
    public class MiscellaneousItemWrapper {
        public Id recordId;
        public String itemDescription;
        public Decimal year1, year2, year3, year4, year5, totalCost;
    }

    // ---------- J. Flexible Funding Allowance (Image 9) ----------
    public class FlexibleFundingAllowanceWrapper {
        public Decimal year1, year2, year3, year4, year5, totalCost;
    }

    // ---------- K. Grand Total (Proposal-level) ----------
    public class ProposalGrandTotalWrapper {
        public Decimal grandTotalCost;
        public Decimal grandTotalYear1;
        public Decimal grandTotalYear2;
        public Decimal grandTotalYear3;
        public Decimal grandTotalYear4;
        public Decimal grandTotalYear5;
    }

    // ---------- F. Animals (Images 10 & 11) — wrapper inside wrapper ----------
    public class AnimalsWrapper {
        public Id animalRecordId;
        public String purchaseJustification;
        public String maintenanceJustification;
        public String expProcedureJustification;
        public String associatedCostJustification;

        public AnimalPurchaseWrapper animalPurchase;             // nested
        public AnimalMaintenanceWrapper animalMaintenance;       // nested
        public AnimalExpProcedureWrapper animalExpProcedures;    // nested
        public AnimalAssociatedCostWrapper animalAssociatedCosts;// nested
    }

    public class AnimalPurchaseWrapper {
        public List<AnimalPurchaseItemWrapper> items = new List<AnimalPurchaseItemWrapper>();
        public Decimal grandTotal;
    }
    public class AnimalPurchaseItemWrapper {
        public Id recordId;
        public String speciesSource;
        public Decimal quantity;
        public Decimal costPerAnimal;
        public String source;
        public String yearRequired;
        public Decimal totalCost;
    }

    public class AnimalMaintenanceWrapper {
        public List<AnimalMaintenanceItemWrapper> items = new List<AnimalMaintenanceItemWrapper>();
        public Decimal grandTotal;
    }
    public class AnimalMaintenanceItemWrapper {
        public Id recordId;
        public String speciesSource;
        public Decimal quantity;
        public Decimal costPerAnimal;
        public String source;
        public String yearRequired;
        public Decimal totalCost;
    }

    public class AnimalExpProcedureWrapper {
        public List<AnimalExpProcedureItemWrapper> items = new List<AnimalExpProcedureItemWrapper>();
        public Decimal grandTotal;
    }
    public class AnimalExpProcedureItemWrapper {
        public Id recordId;
        public String speciesDetails;
        public Decimal quantity;
        public Decimal costPerAnimal;
        public String source;
        public String experimentTitle;
        public String groupName;
        public String yearRequired;
        public Decimal totalCost;
    }

    public class AnimalAssociatedCostWrapper {
        public List<AnimalAssociatedCostItemWrapper> items = new List<AnimalAssociatedCostItemWrapper>();
        public Decimal grandTotal;
    }
    public class AnimalAssociatedCostItemWrapper {
        public Id recordId;
        public String itemDescription;
        public Decimal year1, year2, year3, year4, year5, totalCost;
    }
}