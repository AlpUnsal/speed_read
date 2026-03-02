import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                // Section: Reader Mode
                /*
                Section(header: Text("Reader Mode")) {
                    Picker("Mode", selection: $settings.readerMode) {
                        ForEach(ReaderMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                */
                
                // Section 1: Visuals
                Section(header: Text("Visuals")) {
                    HStack {
                        Picker("Theme", selection: $settings.theme) {
                            ForEach([AppTheme.cream, .white, .grey, .black]) { theme in
                                Text(theme.rawValue).tag(theme)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        
                        Menu {
                            ForEach([AppTheme.sage, .iceBlue, .cherry, .lilac]) { theme in
                                Button(action: {
                                    settings.theme = theme
                                }) {
                                    HStack {
                                        Text(theme.rawValue)
                                        if settings.theme == theme {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "circle.grid.2x2")
                                .font(.system(size: 16))
                                .foregroundColor([AppTheme.sage, .iceBlue, .cherry, .lilac].contains(settings.theme) ? settings.accentColor : settings.mutedTextColor)
                                .padding(.leading, 8)
                        }
                    }
                    
                    Toggle("Focus Lines", isOn: $settings.showORPEmphasisLines)
                        .font(.system(size: 16))
                        .tint(Color(hex: "E63946"))
                }
                .listRowBackground(settings.cardBackgroundColor)
                
                // Section 3: Font
                Section(header: Text("Font")) {
                    Picker("Font Family", selection: $settings.fontName) {
                        ForEach(settings.availableFonts, id: \.self) { font in
                            Text(cleanFontName(font))
                                .font(.custom(font, size: 16))
                                .tag(font)
                        }
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Font Scaling: \(String(format: "%.2fx", settings.fontSizeMultiplier))")
                        Slider(value: $settings.fontSizeMultiplier, in: 0.5...1.25, step: 0.05)
                            .accentColor(Color(hex: "E63946"))
                    }
                }
                .listRowBackground(settings.cardBackgroundColor)
                
                // About / Info
                Section(footer: Text("Axilo v1.0")) {
                    // Empty section for spacing/footer
                }
                .listRowBackground(settings.backgroundColor)
            }
            .navigationBarTitle("Settings", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
            .scrollContentBackground(.hidden)
            .background(settings.backgroundColor)
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .accentColor(Color(hex: "E63946"))
    }
    
    private func cleanFontName(_ name: String) -> String {
        // Beautify font names for display
        name.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "PSMT", with: "")
            .replacingOccurrences(of: "Regular", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

#Preview {
    SettingsView()
}
