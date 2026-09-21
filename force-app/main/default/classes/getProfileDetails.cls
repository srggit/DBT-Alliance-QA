@RestResource(urlMapping='/getProfileDetails')
global with sharing class getProfileDetails {

    @HttpGet
    global static ResponseWrapper doGet() {

        ResponseWrapper response = new ResponseWrapper();

        try {
            RestRequest req = RestContext.request;
            String reviewerId = req.params.get('Reviewer__c');
            String reviewerType = req.params.get('reviewerType');
            System.debug('Reviewer Id = ' + reviewerId);
            System.debug('Reviewer Type = ' + reviewerType);

            if (String.isBlank(reviewerId)) {
                response.success = false;
                response.message = 'Reviewer Id is required';
                return response;
            }

            // ---- Query Reviewer fields + related Education, Employment, Keywords & Domain Tags ----
            if(reviewerType == 'Peer'){
                List<Reviewer__c> reviewers = [
                    SELECT Id, Title__c, First_Name__c, Last_Name__c, Department__c, Alternate_Phone_Number__c,Mobile_Number__c,Designation__c,Email_Address__c,
                        Organisation__r.Name,State_Province__c,Reviewer_Type__c,Country__c, City__c,
                        (SELECT Id, Qualification__c, Institution__c, University__c, Start_Date__c,CGPA_Division__c,
                                End_Date__c, Specify_the_University__c, Specify_Other_Degree__c,
                                Specify_the_pursuing_degree__c, Pursuing_Higher_Degree__c,
                                Likely_date_of_completion__c, Title_of_thesis_Dissertation__c,
                                Research_Summary_During_Highest_Degree__c
                            FROM Education_Details__r
                            ORDER BY End_Date__c DESC),
                        (SELECT Id, Organisation__c, Position__c, Roles_Responsibilities__c,
                                Start_Date__c, End_Date__c, I_am_currently_working_here__c
                            FROM Employment_Details__r
                            ORDER BY Start_Date__c DESC),
                        (SELECT Id, Keyword_Name__c
                            FROM keywords__r
                            ORDER BY Keyword_Name__c DESC),
                            (SELECT Id, Name
                            FROM Reviewer_Domain_Tags__r
                            ORDER BY Name DESC)
                    FROM Reviewer__c
                    WHERE Id = :reviewerId And Reviewer_Type__c = :reviewerType
                    LIMIT 1
                ];
                 if (reviewers.isEmpty()) {
                    response.success = false;
                    response.message = 'Peer Reviewer not found';
                    return response;
                }
                
                    Reviewer__c rev = reviewers[0];

                    // ---- Build wrapper ----
                    response.success = true;
                    response.message = 'Success';
                    response.reviewDetails = wrapReviewer(rev);
                    response.educationDetails = wrapEducationDetails(rev.Education_Details__r);
                    response.employmentDetails = wrapEmploymentDetails(rev.Employment_Details__r);
                    response.keywordDetails = wrapKeywordDetails(rev.keywords__r);
                    response.domainTagsDetails = wrapDomainDetails(rev.Reviewer_Domain_Tags__r);
            }
            if(reviewerType != 'Peer'){
                List<Reviewer__c> reviewers = [
                    SELECT Id, Title__c, First_Name__c, Last_Name__c, Department__c, Alternate_Phone_Number__c,Mobile_Number__c,Designation__c,Email_Address__c,
                        Organisation__r.Name,State_Province__c,Reviewer_Type__c,Country__c, City__c,
                        (SELECT Id, Qualification__c, Institution__c, University__c, Start_Date__c,CGPA_Division__c,
                                End_Date__c, Specify_the_University__c, Specify_Other_Degree__c,
                                Specify_the_pursuing_degree__c, Pursuing_Higher_Degree__c,
                                Likely_date_of_completion__c, Title_of_thesis_Dissertation__c,
                                Research_Summary_During_Highest_Degree__c
                            FROM Education_Details__r
                            ORDER BY End_Date__c DESC),
                        (SELECT Id, Organisation__c, Position__c, Roles_Responsibilities__c,
                                Start_Date__c, End_Date__c, I_am_currently_working_here__c
                            FROM Employment_Details__r
                            ORDER BY Start_Date__c DESC),
                        (SELECT Id, Keyword_Name__c
                            FROM keywords__r
                            ORDER BY Keyword_Name__c DESC),
                            (SELECT Id, Name
                            FROM Reviewer_Domain_Tags__r
                            ORDER BY Name DESC)
                    FROM Reviewer__c
                    WHERE Id = :reviewerId 
                    LIMIT 1
                ];
                 if (reviewers.isEmpty()) {
                    response.success = false;
                    response.message = 'Ex Grantee Reviewer not found';
                    return response;
                }
                
            Reviewer__c rev = reviewers[0];

            // ---- Build wrapper ----
            response.success = true;
            response.message = 'Success';
            response.reviewDetails = wrapReviewer(rev);
            response.educationDetails = wrapEducationDetails(rev.Education_Details__r);
            response.employmentDetails = wrapEmploymentDetails(rev.Employment_Details__r);
            response.keywordDetails = wrapKeywordDetails(rev.keywords__r);
            response.domainTagsDetails = wrapDomainDetails(rev.Reviewer_Domain_Tags__r);
            }
        } catch (Exception e) {
            response.success = false;
            response.message = 'Error: ' + e.getMessage();
        }

        return response;
    }

    // ---- Helper: map Reviewer__c sObject to typed wrapper ----
    private static ReviewerWrapper wrapReviewer(Reviewer__c rev) {
        ReviewerWrapper rw = new ReviewerWrapper();
        rw.id = rev.Id;
        rw.title = rev.Title__c;
        rw.firstName = rev.First_Name__c;
        rw.lastName = rev.Last_Name__c;
        rw.email = rev.Email_Address__c;
        rw.phone = rev.Mobile_Number__c;
        rw.reviewerType = rev.Reviewer_Type__c;
        rw.position = rev.Designation__c;
        rw.department = rev.Department__c;
        rw.organisationName = rev.Organisation__r?.Name;
        rw.city = rev.City__c;
        rw.state = rev.State_Province__c;
        rw.country = rev.Country__c;
        rw.alternatePhoneNumber = rev.Alternate_Phone_Number__c;
        return rw;
    }

    // ---- Helper: map Education_Details__c list to typed wrapper list ----
    private static List<EducationDetailsWrapper> wrapEducationDetails(List<Education_Details__c> records) {
        List<EducationDetailsWrapper> wrappedList = new List<EducationDetailsWrapper>();

        for (Education_Details__c edu : records) {
            EducationDetailsWrapper ew = new EducationDetailsWrapper();
            ew.educationId = edu.Id;
            ew.qualification = edu.Qualification__c;
            ew.institution = edu.Institution__c;
            ew.university = edu.University__c;
            ew.startDate = edu.Start_Date__c;
            ew.endDate = edu.End_Date__c;
            ew.titleOfThesisDissertation = edu.Title_of_thesis_Dissertation__c;
            ew.cgpaGrade = edu.CGPA_Division__c;
            ew.researchSummaryDuringHighestDegree = edu.Research_Summary_During_Highest_Degree__c;
            wrappedList.add(ew);
        }

        return wrappedList;
    }

    // ---- Helper: map Employment_Details__c list to typed wrapper list ----
    private static List<EmploymentDetailsWrapper> wrapEmploymentDetails(List<Employment_Details__c> records) {
        List<EmploymentDetailsWrapper> wrappedList = new List<EmploymentDetailsWrapper>();

        for (Employment_Details__c emp : records) {
            EmploymentDetailsWrapper ew = new EmploymentDetailsWrapper();
            ew.employmentId = emp.Id;
            ew.organisation = emp.Organisation__c;
            ew.position = emp.Position__c;
            ew.description = emp.Roles_Responsibilities__c;
            ew.isCurrentlyWorking = emp.I_am_currently_working_here__c;
            ew.startDate = emp.Start_Date__c;
            ew.endDate = emp.End_Date__c;
            wrappedList.add(ew);
        }

        return wrappedList;
    }

    // ---- Helper: map Keywords__c list to typed wrapper list ----
    private static List<KeywordDetailsWrapper> wrapKeywordDetails(List<Keywords__c> records) {
        List<KeywordDetailsWrapper> wrappedList = new List<KeywordDetailsWrapper>();

        for (Keywords__c ky : records) {
            KeywordDetailsWrapper kw = new KeywordDetailsWrapper();
            kw.keywordDetailId = ky.Id;
            kw.keywordName = ky.Keyword_Name__c;
            wrappedList.add(kw);
        }

        return wrappedList;
    }

    // ---- Helper: map Reviewer_Domain_Tag__c list to typed wrapper list ----
    private static List<DomainTagsWrapper> wrapDomainDetails(List<Reviewer_Domain_Tag__c> records) {
        List<DomainTagsWrapper> wrappedList = new List<DomainTagsWrapper>();

        for (Reviewer_Domain_Tag__c dt : records) {
            DomainTagsWrapper dts = new DomainTagsWrapper();
            dts.domainTagsId = dt.Id;
            dts.domainName = dt.Name;
            wrappedList.add(dts);
        }

        return wrappedList;
    }

    // ---- Wrapper classes ----
    global class ResponseWrapper {
        global Boolean success;
        global String message;
        global ReviewerWrapper reviewDetails;
        global List<EducationDetailsWrapper> educationDetails;
        global List<EmploymentDetailsWrapper> employmentDetails;
        global List<KeywordDetailsWrapper> keywordDetails;
        global List<DomainTagsWrapper> domainTagsDetails;
    }

    global class ReviewerWrapper {
        global String id;
        global String title;
        global String firstName;
        global String lastName;
        global String email;
        global String phone;
        global String reviewerType;
        global String position;
        global String department;
        global String organisationName;
        global String city;
        global String state;
        global String country;
        global String alternatePhoneNumber;
        // PLACEHOLDER: additional fields
    }

    global class EducationDetailsWrapper {
        global String educationId;
        global String qualification;
        global String institution;
        global String university;
        global Date startDate;
        global Date endDate;
        global String cgpaGrade;
        global Date likelyDateOfCompletion;
        global String titleOfThesisDissertation;
        global String researchSummaryDuringHighestDegree;
    }

    global class EmploymentDetailsWrapper {
        global String employmentId;
        global String organisation;
        global String position;
        global String description;
        global Boolean isCurrentlyWorking;
        global Date startDate;
        global Date endDate;
    }

    global class DomainTagsWrapper {
        global String domainTagsId;
        global String domainName;
    }

    global class KeywordDetailsWrapper {
        global String keywordDetailId;
        global String keywordName;
    }
}