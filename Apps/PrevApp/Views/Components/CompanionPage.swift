import SwiftUI

/// The common frame of every destination: a heading, a short explanation, an
/// optional trailing accessory, and the page content.
struct CompanionPage<Accessory: View, Content: View>: View {
    private let title: String
    private let subtitle: String
    private let scrolls: Bool
    private let accessory: Accessory
    private let content: Content

    /// Pass `scrolls: false` when the content manages its own scrolling.
    init(title: String, subtitle: String, scrolls: Bool = true,
         @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.scrolls = scrolls
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: title).font(CompanionTypography.pageTitle).accessibilityAddTraits(.isHeader)
                    Text(verbatim: subtitle).font(CompanionTypography.row).foregroundStyle(CompanionInk.hint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                accessory
            }
            .padding(.horizontal, CompanionMetrics.pagePadding)
            .padding(.top, 18)
            .padding(.bottom, 14)
            Divider()
            if scrolls {
                ScrollView {
                    content
                        .padding(CompanionMetrics.pagePadding)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                content
                    .padding(CompanionMetrics.pagePadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(Color.companionPage.ignoresSafeArea())
    }
}

extension CompanionPage where Accessory == EmptyView {
    init(title: String, subtitle: String, scrolls: Bool = true, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, scrolls: scrolls, accessory: { EmptyView() }, content: content)
    }
}
