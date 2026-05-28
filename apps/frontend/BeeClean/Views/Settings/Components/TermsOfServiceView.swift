import SwiftUI

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss

    private let sections: [(icon: String, title: String, text: String)] = [
        ("checkmark.seal.fill", "1. Acceptance of Terms",
         "Welcome to Beeclean! By downloading, installing, accessing, or using the Beeclean mobile application and any related services (collectively, the \"Service\"), you agree to be bound by these Terms & Conditions (\"Terms\"). These Terms constitute a legally binding agreement between you and Beeclean (\"we\", \"us\", or \"our\").\n\nIf you do not agree to these Terms, you may not access or use the Service. By using the Service, you represent that you are at least 13 years of age and have the legal capacity to enter into this agreement.\n\nPlease read these Terms carefully, along with our Privacy Policy, which governs your use of the Service. Accessing or continuing to use the Service after any changes to these Terms constitutes your acceptance of the revised Terms."),

        ("doc.badge.gearshape.fill", "2. Description of Service",
         "Beeclean is a mobile application designed to help users clean, organize, and optimize their iPhone storage. The Service provides tools to:\n\n\u{2022} Identify and remove duplicate photos and videos\n\u{2022} Organize screenshots and similar media\n\u{2022} Compress large files to save storage space\n\u{2022} Clean up contacts and email (with permission)\n\u{2022} Provide storage analytics and insights\n\u{2022} Offer premium features through in-app subscriptions\n\nThe Service is available on iOS devices compatible with our app. We reserve the right to modify, suspend, or discontinue any part of the Service at any time without notice."),

        ("person.fill.checkmark", "3. User Accounts and Registration",
         "While basic cleanup features are available without an account, premium features require registration via Sign in with Apple. Your Apple ID information is handled according to Apple's privacy policy.\n\nYou agree to provide accurate and complete information when creating an account and to keep your account credentials secure. You are responsible for all activities that occur under your account. Notify us immediately of any unauthorized use."),

        ("exclamationmark.triangle.fill", "4. Acceptable Use Policy",
         "You agree to use the Service only for lawful purposes and in accordance with these Terms. You agree NOT to:\n\n\u{2022} Use the Service in any way that violates any applicable law or regulation\n\u{2022} Attempt to gain unauthorized access to our systems, networks, or user accounts\n\u{2022} Interfere with or disrupt the Service or servers connected to the Service\n\u{2022} Use the Service to transmit malware, viruses, or any malicious code\n\u{2022} Reverse engineer, decompile, or attempt to extract the source code of the app\n\u{2022} Use automated scripts or bots to access the Service without our permission\n\u{2022} Misuse the Service to harm other users or their data\n\u{2022} Use the Service for commercial purposes without our written consent"),

        ("lock.shield.fill", "5. Intellectual Property",
         "Our Intellectual Property: The Service and its original content, features, and functionality are owned by Beeclean and are protected by international copyright, trademark, patent, trade secret, and other intellectual property laws. The Service is licensed, not sold, to you. You may not copy, modify, create derivative works from, decompile, or reverse-engineer any part of the Service without our prior written consent.\n\nUser Content: The Service processes your photos and media locally on your device. You retain all ownership rights to your content. However, by using the Service, you grant us a limited, non-exclusive license to access, read, and process your media solely for the purpose of providing the Service to you. We do not claim ownership of your content.\n\nTrademarks: Beeclean, the Beeclean logo, and all related names, logos, product names, and service names are trademarks of Beeclean. You may not use these marks without our prior written permission."),

        ("creditcard.fill", "6. Subscriptions and Billing",
         "Free and Premium Tiers: The Service offers both free and subscription-based (Premium) features. The free version includes basic cleanup tools with limitations.\n\nPayment Processing: All payments are processed through Apple's in-app purchase system. Subscription prices and billing cycles are displayed before purchase. Payment terms are between you and Apple Inc.\n\nAutomatic Renewal: Unless you cancel at least 24 hours before the end of the current billing period, your Premium subscription will automatically renew. You can manage or cancel subscriptions through your Apple ID account settings.\n\nRefunds: All sales are final. Refund requests must be directed to Apple Support, as Apple manages all App Store transactions.\n\nPrice Changes: We may change subscription prices with reasonable notice (at least 30 days) before the change takes effect."),

        ("xmark.shield.fill", "7. Disclaimer of Warranties",
         "THE SERVICE IS PROVIDED \"AS IS\" AND \"AS AVAILABLE\" WITHOUT WARRANTIES OF ANY KIND, EITHER EXPRESS OR IMPLIED. TO THE MAXIMUM EXTENT PERMITTED BY LAW, BEECLEAN DISCLAIMS ALL WARRANTIES, INCLUDING:\n\n\u{2022} MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE\n\u{2022} THAT THE SERVICE WILL BE UNINTERRUPTED, ERROR-FREE, OR FREE FROM HARMFUL COMPONENTS\n\u{2022} THAT THE SERVICE WILL MEET YOUR REQUIREMENTS OR EXPECTATIONS\n\u{2022} THAT THE CONTENT OR INFORMATION PROVIDED THROUGH THE SERVICE IS ACCURATE OR RELIABLE\n\nBeeclean does not warrant that cleanup operations will recover a specific amount of storage space or that no data loss will occur. Always back up important data before performing cleanup operations."),

        ("shield.fill", "8. Limitation of Liability",
         "TO THE MAXIMUM EXTENT PERMITTED BY LAW, BEECLEAN AND ITS OFFICERS, DIRECTORS, EMPLOYEES, AND AGENTS SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES ARISING OUT OF OR RELATED TO YOUR USE OF OR INABILITY TO USE THE SERVICE, INCLUDING:\n\n\u{2022} LOSS OF DATA, FILES, OR PERSONAL INFORMATION\n\u{2022} LOSS OF PROFITS, REVENUE, OR GOODWILL\n\u{2022} BUSINESS INTERRUPTION\n\u{2022} PERSONAL INJURY OR PROPERTY DAMAGE\n\u{2022} ANY DAMAGES ARISING FROM DATA LOSS OR FILE DELETION\n\nOUR TOTAL LIABILITY TO YOU FOR ANY CLAIM ARISING FROM THESE TERMS OR THE SERVICE SHALL NOT EXCEED THE AMOUNT YOU PAID TO US IN THE PAST 12 MONTHS (OR $100 WHICHEVER IS LESS). SOME JURISDICTIONS DO NOT ALLOW THE EXCLUSION OR LIMITATION OF CERTAIN DAMAGES, SO THIS LIMITATION MAY NOT APPLY TO YOU."),

        ("arrow.triangle.2.circlepath", "9. Indemnification",
         "You agree to indemnify, defend, and hold harmless Beeclean and its affiliates, officers, agents, and employees from and against any and all claims, damages, costs, liabilities, and expenses (including reasonable attorneys' fees) arising out of or related to:\n\n\u{2022} Your use of the Service\n\u{2022} Your violation of these Terms\n\u{2022} Your violation of any third-party rights\n\u{2022} Any claim that your content caused damage to a third party\n\nWe reserve the right, at our own expense, to assume the exclusive defense and control of any matter otherwise subject to indemnification by you."),

        ("power", "10. Termination",
         "By You: You may stop using the Service at any time. To terminate your account, delete the app from your device and cancel any active subscription through your Apple ID settings.\n\nBy Beeclean: We may suspend or terminate your access to the Service at our sole discretion, without notice or liability, for any reason including but not limited to violation of these Terms, fraudulent or illegal activity, non-payment of subscription fees, extended periods of inactivity, or technical or security concerns.\n\nEffect of Termination: Upon termination, all rights granted to you under these Terms will immediately cease. Your account data and any content stored on our servers will be deleted in accordance with our data retention policy (local media is never stored on our servers)."),

        ("building.columns.fill", "11. Governing Law",
         "These Terms shall be governed by and construed in accordance with the laws of the State of California, United States, without regard to its conflict of law principles.\n\nAny dispute arising out of or relating to these Terms or the Service shall first be attempted to be resolved through Informal Negotiations. If unsuccessful within 30 days, disputes shall be resolved through binding arbitration in accordance with the rules of the American Arbitration Association.\n\nYou agree that any disputes shall be resolved individually, and you waive any right to participate in a class action or consolidated proceeding."),

        ("arrow.clockwise", "12. Changes to Terms",
         "We may update these Terms from time to time. When we do, we will update the \"Last updated\" date at the top of these Terms, notify you via the app, email (if we have your address), or through the App Store, and provide at least 30 days notice for material changes affecting billing or user rights.\n\nContinued use of the Service after changes constitutes your acceptance of the new Terms. If you do not agree to the modified Terms, you must stop using the Service."),

        ("scissors", "13. Severability",
         "If any provision of these Terms is held to be invalid, illegal, or unenforceable by a court of competent jurisdiction, such provision shall be severed from these Terms. The remaining provisions shall continue in full force and effect."),

        ("hand.raised.fill", "14. No Waiver",
         "Our failure to enforce any right or provision of these Terms will not be considered a waiver of those rights. Any waiver of any provision of these Terms will be effective only if in writing and signed by us."),

        ("doc.text.fill", "15. Entire Agreement",
         "These Terms, together with our Privacy Policy, constitute the entire agreement between you and Beeclean regarding the Service and supersede all prior or contemporaneous agreements, communications, and proposals, whether oral or written."),

        ("envelope.fill", "16. Contact Information",
         "For any questions about these Terms & Conditions, please contact us at support@beeclean.app.")
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: "DDE1F2"), location: 0.0),
                    .init(color: Color(hex: "DDE1F2"), location: 0.45),
                    .init(color: Color(hex: "E3E6EE"), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                LegalPageHeader(title: "Terms of Service") { dismiss() }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // Title block — Bitepal headline above the
                        // document surface so the page has presence
                        // before the user reads a single clause.
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Terms of Service")
                                .font(.custom("Poppins-Bold", size: 32))
                                .foregroundColor(Color(red: 0.110, green: 0.098, blue: 0.090))

                            Text("Last updated · April 2026")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(Color(hex: "78716C"))
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                        // Each section in its own white card, stacked
                        // with breathing room. Same composition as
                        // Privacy Policy so the two legal documents
                        // read as siblings.
                        VStack(spacing: 12) {
                            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                                LegalSectionCard(
                                    icon: section.icon,
                                    title: section.title,
                                    content: section.text,
                                    index: index
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 60)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .navigationBarHidden(true)
        .hidesBottomNavBar()
        .environment(\.colorScheme, .light)
    }
}

#Preview {
    NavigationStack { TermsOfServiceView() }
        .preferredColorScheme(.light)
}
