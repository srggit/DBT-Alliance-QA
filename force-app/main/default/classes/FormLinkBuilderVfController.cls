public class FormLinkBuilderVfController {
    public String encodedUrl { get; private set; }

    public FormLinkBuilderVfController() {
        Map<String, Object> data = new Map<String, Object>{
            'title' => 'Mr.',
            'firstName' => 'Tapas',
            'lastName' => 'Kumar',
            'email' => 'rahul123rajkr@gmail.com',
            'phone' => '09931724719',
            'expertise' => 'Planning',
            'yearsOfExperienceAsIndependentPI' => 2
        };

        encodedUrl = FormLinkBuilder.buildEncodedUrl(data);
    }
}