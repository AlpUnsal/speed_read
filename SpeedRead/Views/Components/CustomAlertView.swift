import SwiftUI

struct CustomAlertView: View {
    @ObservedObject var settings = SettingsManager.shared
    @FocusState private var isTextFieldFocused: Bool

    let title: String
    let message: String?
    @Binding var text: String
    let placeholder: String
    let onCancel: () -> Void
    let onSave: () -> Void
    let saveTitle: String
    let showTextField: Bool

    init(title: String, message: String? = nil, text: Binding<String> = .constant(""), placeholder: String = "", saveTitle: String = "Save", showTextField: Bool = true, onCancel: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.title = title
        self.message = message
        self._text = text
        self.placeholder = placeholder
        self.onCancel = onCancel
        self.onSave = onSave
        self.saveTitle = saveTitle
        self.showTextField = showTextField
    }

    var body: some View {
        ZStack {
            // Darkened backdrop
            Color.black.opacity(settings.theme.colorScheme == .light ? 0.3 : 0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    isTextFieldFocused = false
                    onCancel()
                }

            // Alert Card
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text(title)
                        .font(.custom("EBGaramond-Bold", size: 20))
                        .foregroundColor(settings.textColor)
                        .multilineTextAlignment(.center)

                    if let msg = message {
                        Text(msg)
                            .font(.custom("EBGaramond-Regular", size: 16))
                            .foregroundColor(settings.mutedTextColor)
                            .multilineTextAlignment(.center)
                    }
                }

                if showTextField {
                    TextField(placeholder, text: $text)
                        .font(.custom("EBGaramond-Regular", size: 16))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(settings.backgroundColor)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(settings.cardBorderColor.opacity(0.5), lineWidth: 1)
                        )
                        .focused($isTextFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            onSave()
                        }
                }

                HStack(spacing: 12) {
                    Button(action: {
                        isTextFieldFocused = false
                        onCancel()
                    }) {
                        Text("Cancel")
                            .font(.custom("EBGaramond-Bold", size: 16))
                            .foregroundColor(settings.mutedTextColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(settings.backgroundColor)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(settings.cardBorderColor, lineWidth: 1)
                            )
                    }

                    Button(action: {
                        isTextFieldFocused = false
                        onSave()
                    }) {
                        Text(saveTitle)
                            .font(.custom("EBGaramond-Bold", size: 16))
                            .foregroundColor(settings.primaryButtonTextColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(settings.accentColor)
                            .cornerRadius(10)
                    }
                }
            }
            .padding(24)
            .background(settings.cardBackgroundColor)
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(0.15), radius: 20, y: 10)
            .padding(.horizontal, 32)
            .offset(y: isTextFieldFocused ? -80 : 0)
            .animation(.easeOut(duration: 0.25), value: isTextFieldFocused)
        }
        .onAppear {
            if showTextField {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isTextFieldFocused = true
                }
            }
        }
    }
}
