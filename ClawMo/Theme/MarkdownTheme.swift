import SwiftUI
import MarkdownUI

extension MarkdownUI.Theme {
    static let clawMo = MarkdownUI.Theme()
        .text {
            ForegroundColor(Theme.textPrimary)
            FontSize(14)
        }
        .link {
            ForegroundColor(Theme.green)
        }
        .strong {
            FontWeight(.semibold)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.9))
            ForegroundColor(Theme.green)
        }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(18)
                    ForegroundColor(Theme.textPrimary)
                }
                .markdownMargin(top: 12, bottom: 6)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(16)
                    ForegroundColor(Theme.textPrimary)
                }
                .markdownMargin(top: 10, bottom: 4)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(15)
                    ForegroundColor(Theme.textPrimary)
                }
                .markdownMargin(top: 8, bottom: 4)
        }
        .codeBlock { configuration in
            configuration.label
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(12)
                    ForegroundColor(.white.opacity(0.85))
                }
                .padding(12)
                .background(Color(red: 12/255, green: 13/255, blue: 14/255))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .markdownMargin(top: 6, bottom: 6)
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.green.opacity(0.4))
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(.white.opacity(0.6))
                        FontSize(13)
                    }
                    .padding(.leading, 10)
            }
            .markdownMargin(top: 4, bottom: 4)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 2, bottom: 2)
        }
        .table { configuration in
            configuration.label
                .markdownTextStyle { FontSize(12) }
                .markdownMargin(top: 6, bottom: 6)
        }
}
