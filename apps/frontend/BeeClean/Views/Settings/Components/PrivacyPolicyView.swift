import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    private let sections: [(icon: String, title: String, text: String)] = [
        ("info.circle.fill", "1. Introduction",
         "Beeclean (\"we\", \"our\", or \"us\") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application Beeclean and any related services (collectively, the \"Service\").\n\nPlease read this Privacy Policy carefully. By using the Service, you consent to the practices described in this policy. If you do not agree with the terms of this Privacy Policy, please do not access the Service.\n\nThis Privacy Policy is tailored for users in the United States and complies with applicable privacy laws including the California Consumer Privacy Act (CCPA) and the General Data Protection Regulation (GDPR) for users in the European Economic Area."),

        ("square.and.arrow.down.fill", "2. Information We Collect",
         "Personal Information: When you create an account or use premium features, we may collect your name and email address, Apple ID information (as provided by Sign in with Apple), subscription status and payment information (processed by Apple), and customer support communications.\n\nDevice and Usage Information: We automatically collect device type, model, and operating system version, unique device identifiers (IDFV/IDFA), app usage statistics and performance metrics, crash logs and diagnostic data, and language and region settings.\n\nPhotos and Media: Beeclean processes your photos and videos locally on your device. We do not upload, store, or have access to your personal media files on our servers. All image analysis, duplicate detection, and cleanup operations happen directly on your iPhone. We only collect metadata about cleanup actions (e.g., \"X duplicates removed\") for analytics purposes, without any identifiable content.\n\nAnalytics Data: We use third-party analytics services (such as Firebase Analytics and App Store Connect Analytics) to understand how users interact with our app. These services collect anonymous usage data. You can opt out of analytics tracking through your device settings."),

        ("arrow.right.arrow.left", "3. How We Use Your Information",
         "We use the information we collect to:\n\n\u{2022} Provide, maintain, and improve the Beeclean Service and its features\n\u{2022} Process your subscriptions and manage your account through Apple's systems\n\u{2022} Send you service-related notifications (e.g., scan completion, subscription updates)\n\u{2022} Respond to your comments, questions, and customer support requests\n\u{2022} Monitor and analyze trends, usage, and activities in connection with the Service\n\u{2022} Detect, prevent, and address technical issues, fraud, or security concerns\n\u{2022} Personalize your experience and deliver content relevant to your interests"),

        ("person.2.fill", "4. Data Sharing and Disclosure",
         "We do not sell, trade, or otherwise transfer your personal information to third parties except in the following circumstances:\n\nService Providers: Apple Inc. (for App Store distribution, in-app purchases, and Sign in with Apple), Firebase (Google) for analytics and crash reporting (data is anonymized), cloud service providers for backend infrastructure (no user media stored).\n\nLegal Requirements: We may disclose your information if required to do so by law or in response to valid requests by public authorities.\n\nBusiness Transfers: If Beeclean is involved in a merger, acquisition, or sale of all or substantially all its assets, your information may be transferred as part of that transaction.\n\nProtection of Rights: We may disclose information to protect the rights, property, or safety of Beeclean, our users, or others."),

        ("lock.shield.fill", "5. Data Security",
         "The security of your data is our top priority. We implement industry-standard security measures:\n\n\u{2022} Local Processing: All photo and video analysis is performed directly on your device. No personal media is uploaded to our servers.\n\u{2022} Encryption: All data transmitted between your device and our servers is encrypted using HTTPS/TLS.\n\u{2022} Access Controls: We restrict access to personal information to employees, contractors, and agents who need to know that information.\n\u{2022} Regular Security Audits: We regularly review our data collection, storage, and processing practices.\n\nHowever, no method of transmission over the Internet or electronic storage is 100% secure. While we strive to use commercially acceptable means to protect your information, we cannot guarantee its absolute security."),

        ("hand.raised.fill", "6. Your Data Rights",
         "Depending on your jurisdiction, you may have the following rights:\n\nAccess & Portability: You can request a copy of the personal information we hold about you in a structured, commonly used, and machine-readable format.\n\nCorrection & Deletion: You may request that we correct inaccurate information or delete your personal data. Note that we may retain certain information as required by law.\n\nRestriction & Objection: You may object to or request restriction of certain processing of your data, particularly for direct marketing purposes.\n\nTo exercise any of these rights, please contact us at support@beeclean.app. We will respond to your request within 30 days."),

        ("eye.slash.fill", "7. Cookies and Tracking",
         "Our mobile application does not use traditional web cookies. However, we may use:\n\n\u{2022} Third-party SDKs: Analytics platforms may use their own tracking technologies. These are configured to respect user privacy choices (e.g., App Tracking Transparency on iOS).\n\u{2022} Device identifiers: For analytics and to detect unique installations, we collect IDFA/IDFV as allowed by your device settings.\n\nYou can control tracking through your iOS Settings under Privacy & Security > Tracking. Opting out may affect certain analytics features but does not impact core functionality of Beeclean."),

        ("figure.and.child.holdinghands", "8. Children's Privacy",
         "Beeclean is not intended for use by children under the age of 13. We do not knowingly collect personal information from children under 13. If you are a parent or guardian and believe your child has provided us with personal information, please contact us immediately at support@beeclean.app and we will promptly delete such information."),

        ("clock.fill", "9. Data Retention",
         "We retain your personal information only for as long as necessary to fulfill the purposes outlined in this Privacy Policy, unless a longer retention period is required or permitted by law.\n\n\u{2022} Account data is retained until you delete your account (through App Store subscription cancellation)\n\u{2022} Analytics data is anonymized and retained for up to 26 months\n\u{2022} Customer support correspondence is retained for 3 years for quality assurance"),

        ("link", "10. Third-Party Services",
         "Our Service integrates with the following third-party services, each with its own privacy policy:\n\n\u{2022} Apple Inc. \u{2014} App Store, in-app purchases, Sign in with Apple\n\u{2022} Firebase (Google) \u{2014} Analytics and crash reporting\n\nWe are not responsible for the privacy practices of these third parties. We encourage you to read their privacy policies before providing any information."),

        ("globe", "11. International Data Transfers",
         "Beeclean is based in the United States. Your information may be stored and processed in the United States or other countries where our service providers operate. By using the Service, you consent to the transfer of your data to these jurisdictions, which may have different data protection laws than your country.\n\nFor users in the European Economic Area (EEA), we ensure appropriate safeguards (such as Standard Contractual Clauses approved by the European Commission) are in place when transferring personal data outside the EEA."),

        ("building.columns.fill", "12. GDPR Compliance",
         "If you are a resident of the European Economic Area (EEA), you have specific data protection rights under the General Data Protection Regulation (GDPR):\n\n\u{2022} The right to be informed about how your data is processed\n\u{2022} The right of access to your personal data\n\u{2022} The right to rectification of inaccurate data\n\u{2022} The right to erasure (the right to be forgotten)\n\u{2022} The right to restrict processing in certain circumstances\n\u{2022} The right to data portability\n\u{2022} The right to object to processing\n\u{2022} Rights related to automated decision-making and profiling\n\nWe will not discriminate against you for exercising any of these rights. To exercise GDPR rights, contact us at support@beeclean.app."),

        ("flag.fill", "13. CCPA Compliance",
         "For California residents, the California Consumer Privacy Act (CCPA) provides specific rights regarding your personal information:\n\n\u{2022} Right to Know: Request disclosure of the personal information we collect, use, or share.\n\u{2022} Right to Delete: Request deletion of your personal information (with exceptions).\n\u{2022} Right to Opt-Out: Direct us not to sell your personal information. We do not sell personal information.\n\u{2022} Right to Non-Discrimination: We will not discriminate for exercising your CCPA rights.\n\nTo make a CCPA request, email us at support@beeclean.app. We may verify your identity before fulfilling your request."),

        ("arrow.clockwise", "14. Updates to This Privacy Policy",
         "We may update this Privacy Policy from time to time to reflect changes in our practices or for other operational, legal, or regulatory reasons. When we make material changes, we will update the \"Last updated\" date, notify you via the app or email, and post the updated policy.\n\nYour continued use of the Service after such modifications constitutes acceptance of the updated Privacy Policy. We encourage you to review this policy periodically."),

        ("envelope.fill", "15. Contact Us",
         "If you have questions or concerns about this Privacy Policy or our data practices, please contact us at support@beeclean.app.")
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
                LegalPageHeader(title: "Privacy Policy") { dismiss() }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // Title block — Bitepal headline above the
                        // document surface so the page has presence
                        // before the user reads a single clause.
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Privacy Policy")
                                .font(.custom("Poppins-Bold", size: 32))
                                .foregroundColor(Color(red: 0.110, green: 0.098, blue: 0.090))

                            Text("Last updated · April 2026")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(Color(hex: "78716C"))
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                        // Each section in its own white card, stacked
                        // with breathing room — clear contrast against
                        // the Bitepal canvas, professional read.
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

// MARK: - Legal Page Header
struct LegalPageHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button {
                HapticManager.shared.arrowNudge(.backward)
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "1C1917"))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color(hex: "F8F8F8"))
                    )
            }

            Spacer()

            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "1C1917"))

            Spacer()

            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
}

// MARK: - Legal Section Card (flat, always-visible, own white surface)
//
// Each numbered section renders inside its OWN Bitepal white card —
// stacked with breathing room against the cool-gray canvas so every
// clause has clear visual contrast. No accordion, no tap-to-expand:
// the entire policy stays visible without interaction (hiding legal
// text behind chevrons reads as evasive and creates real liability;
// courts have ruled against "buried" disclosures, so flat
// always-visible is the only defensible pattern here).
//
// Same single-layer chrome as the Settings cards — fill + inset
// stroke composed inside one background ZStack, then
// `.compositingGroup()` so card + shadow rasterize together for
// smooth scrolling.
struct LegalSectionCard: View {
    let icon: String
    let title: String
    let content: String
    let index: Int

    private var inkBlack: Color { Color(red: 0.110, green: 0.098, blue: 0.090) }
    private var bodyText: Color { Color(red: 0.231, green: 0.227, blue: 0.220) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                // Section number badge — honey-tinted, gives the long
                // scroll an at-a-glance position cue.
                Text("\(index + 1)")
                    .font(.custom("Poppins-Bold", size: 12))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "A87408"), Color(hex: "D4A01C")],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(Color(hex: "FBF3E0"))
                    )
                    .overlay(
                        Circle().stroke(Color(hex: "F5B400").opacity(0.30), lineWidth: 0.6)
                    )

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(inkBlack.opacity(0.78))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color(hex: "F4F4F7")))

                Text(title)
                    .font(.custom("Poppins-Bold", size: 17))
                    .foregroundColor(inkBlack)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(content)
                .font(.system(size: 14.5, weight: .regular))
                .foregroundColor(bodyText)
                .multilineTextAlignment(.leading)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            ZStack {
                shape.fill(Color.white)
                shape.strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
            }
        )
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
    }
}

#Preview {
    NavigationStack { PrivacyPolicyView() }
        .preferredColorScheme(.light)
}
