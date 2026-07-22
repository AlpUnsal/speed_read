import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var deviceScanner = DeviceBookScanner.shared
    @Environment(\.presentationMode) var presentationMode

    /// The reader session's active mode, when opened from inside the reader.
    /// Reader mode is per-document, so RSVP-only toggles gate on this rather
    /// than the global default. Nil (app-level settings) falls back to the default.
    var sessionMode: ReaderMode? = nil
    
    var body: some View {
        NavigationView {
            ZStack {
                settings.backgroundColor
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        
                        // Visuals Card
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Visuals")
                                .font(.custom("EBGaramond-Bold", size: 18))
                                .foregroundColor(settings.secondaryTextColor)
                                .padding(.leading, 4)
                            
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Theme")
                                        .font(.custom("EBGaramond-Regular", size: 16))
                                        .foregroundColor(settings.textColor)
                                    
                                    Spacer()
                                    
                                    Picker("Theme", selection: $settings.theme) {
                                        ForEach([AppTheme.cream, .white, .grey, .black]) { theme in
                                            Text(theme.rawValue).tag(theme)
                                        }
                                    }
                                    .pickerStyle(SegmentedPickerStyle())
                                    .frame(maxWidth: 200)
                                    
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
                                        ZStack {
                                            Circle()
                                                .fill(settings.cardBackgroundColor)
                                                .frame(width: 32, height: 32)
                                                .overlay(
                                                    Circle()
                                                        .stroke(settings.cardBorderColor, lineWidth: 1)
                                                )
                                            
                                            Image(systemName: "paintpalette")
                                                .font(.system(size: 14))
                                                .foregroundColor([AppTheme.sage, .iceBlue, .cherry, .lilac].contains(settings.theme) ? settings.accentColor : settings.mutedTextColor)
                                        }
                                    }
                                    .padding(.leading, 8)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                
                                Divider()
                                    .background(settings.cardBorderColor.opacity(0.3))
                                    .padding(.leading, 16)
                                
                                // Focus Lines toggle — only relevant for RSVP mode
                                if (sessionMode ?? settings.readerMode) == .rsvp {
                                    HStack {
                                        Toggle("Focus Lines", isOn: $settings.showORPEmphasisLines)
                                            .font(.custom("EBGaramond-Regular", size: 16))
                                            .foregroundColor(settings.textColor)
                                            .tint(settings.accentColor)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)

                                    Rectangle()
                                        .fill(settings.cardBorderColor.opacity(0.3))
                                        .frame(height: 1)
                                        .padding(.leading, 16)

                                    HStack {
                                        Toggle("Dialogue Indicator", isOn: $settings.showDialogueIndicator)
                                            .font(.custom("EBGaramond-Regular", size: 16))
                                            .foregroundColor(settings.textColor)
                                            .tint(settings.accentColor)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)

                                    Rectangle()
                                        .fill(settings.cardBorderColor.opacity(0.3))
                                        .frame(height: 1)
                                        .padding(.leading, 16)

                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Toggle("Smart Pacing", isOn: $settings.smartPacing)
                                                .font(.custom("EBGaramond-Regular", size: 16))
                                                .foregroundColor(settings.textColor)
                                                .tint(settings.accentColor)
                                            Text("Briefly lingers on unfamiliar and long words")
                                                .font(.custom("EBGaramond-Regular", size: 13))
                                                .foregroundColor(settings.secondaryTextColor)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)

                                    if settings.smartPacing {
                                        HStack {
                                            Text("Intensity")
                                                .font(.custom("EBGaramond-Regular", size: 16))
                                                .foregroundColor(settings.textColor)

                                            Spacer()

                                            Picker("Intensity", selection: $settings.smartPacingIntensity) {
                                                ForEach(SmartPacingIntensity.allCases) { intensity in
                                                    Text(intensity.rawValue).tag(intensity)
                                                }
                                            }
                                            .pickerStyle(SegmentedPickerStyle())
                                            .frame(maxWidth: 200)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.bottom, 14)
                                    }
                                }
                            }
                            .background(settings.cardBackgroundColor)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(settings.cardBorderColor.opacity(0.5), lineWidth: 1)
                            )
                        }
                        
                        // Font Card
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Typography")
                                .font(.custom("EBGaramond-Bold", size: 18))
                                .foregroundColor(settings.secondaryTextColor)
                                .padding(.leading, 4)
                            
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Font Family")
                                        .font(.custom("EBGaramond-Regular", size: 16))
                                        .foregroundColor(settings.textColor)
                                    
                                    Spacer()
                                    
                                    Picker("Font Family", selection: $settings.fontName) {
                                        ForEach(settings.availableFonts, id: \.self) { font in
                                            Text(cleanFontName(font))
                                                .font(.custom(font, size: 16))
                                                .tag(font)
                                        }
                                    }
                                    .accentColor(settings.accentColor)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                
                                Divider()
                                    .background(settings.cardBorderColor.opacity(0.3))
                                    .padding(.leading, 16)
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Font Scaling")
                                            .font(.custom("EBGaramond-Regular", size: 16))
                                            .foregroundColor(settings.textColor)
                                        
                                        Spacer()
                                        
                                        Text("\(String(format: "%.2fx", settings.fontSizeMultiplier))")
                                            .font(.custom("EBGaramond-Bold", size: 14))
                                            .foregroundColor(settings.accentColor)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(settings.accentColor.opacity(0.1))
                                            .cornerRadius(6)
                                    }
                                    
                                    Slider(value: $settings.fontSizeMultiplier, in: 0.5...1.25, step: 0.05)
                                        .accentColor(settings.accentColor)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            .background(settings.cardBackgroundColor)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(settings.cardBorderColor.opacity(0.5), lineWidth: 1)
                            )
                        }
                        
                        // Reader Mode Card
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Reader Mode")
                                .font(.custom("EBGaramond-Bold", size: 18))
                                .foregroundColor(settings.secondaryTextColor)
                                .padding(.leading, 4)

                            VStack(spacing: 0) {
                                HStack {
                                    Text("Default Mode")
                                        .font(.custom("EBGaramond-Regular", size: 16))
                                        .foregroundColor(settings.textColor)

                                    Spacer()

                                    Picker("Default Mode", selection: $settings.readerMode) {
                                        ForEach(ReaderMode.allCases) { mode in
                                            Text(mode.rawValue).tag(mode)
                                        }
                                    }
                                    .pickerStyle(SegmentedPickerStyle())
                                    .frame(maxWidth: 180)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            .background(settings.cardBackgroundColor)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(settings.cardBorderColor.opacity(0.5), lineWidth: 1)
                            )
                        }
                        
                        // Device Books Card
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Device Books")
                                .font(.custom("EBGaramond-Bold", size: 18))
                                .foregroundColor(settings.secondaryTextColor)
                                .padding(.leading, 4)

                            VStack(spacing: 0) {
                                HStack {
                                    Text("Linked Folder")
                                        .font(.custom("EBGaramond-Regular", size: 16))
                                        .foregroundColor(settings.textColor)

                                    Spacer()

                                    Text(deviceScanner.folderName ?? "Not set up")
                                        .font(.custom("EBGaramond-Regular", size: 15))
                                        .foregroundColor(deviceScanner.hasFolderAccess ? settings.secondaryTextColor : settings.mutedTextColor)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)

                                Divider()
                                    .background(settings.cardBorderColor.opacity(0.3))
                                    .padding(.leading, 16)

                                Button {
                                    presentationMode.wrappedValue.dismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                        NotificationCenter.default.post(name: NSNotification.Name("ShowFolderPicker"), object: nil)
                                    }
                                } label: {
                                    HStack {
                                        Text(deviceScanner.hasFolderAccess ? "Change Folder" : "Link a Folder")
                                            .font(.custom("EBGaramond-Regular", size: 16))
                                            .foregroundColor(settings.accentColor)
                                        Spacer()
                                        Image(systemName: "folder.badge.plus")
                                            .foregroundColor(settings.accentColor)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                }

                                if deviceScanner.hasFolderAccess {
                                    Divider()
                                        .background(settings.cardBorderColor.opacity(0.3))
                                        .padding(.leading, 16)

                                    Button {
                                        deviceScanner.removeFolderAccess()
                                    } label: {
                                        HStack {
                                            Text("Remove")
                                                .font(.custom("EBGaramond-Regular", size: 16))
                                                .foregroundColor(.red.opacity(0.8))
                                            Spacer()
                                            Image(systemName: "xmark.circle")
                                                .foregroundColor(.red.opacity(0.8))
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 14)
                                    }
                                }
                            }
                            .background(settings.cardBackgroundColor)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(settings.cardBorderColor.opacity(0.5), lineWidth: 1)
                            )
                        }

                        // Footer
                        Text("Axilo v2.0")
                            .font(.custom("EBGaramond-Regular", size: 14))
                            .foregroundColor(settings.mutedTextColor)
                            .padding(.top, 16)
                    }
                    .padding(20)
                }
            }
            .navigationBarTitle("Settings", displayMode: .inline)
            .navigationBarItems(trailing: Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Text("Done")
                    .font(.custom("EBGaramond-Regular", size: 16))
                    .foregroundColor(settings.accentColor)
            })
            
            // Re-apply navigation bar styling for aesthetic blending
            .toolbarBackground(settings.backgroundColor, for: .navigationBar)
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .accentColor(settings.accentColor)
        // Ensure the sheet dynamically adapts background
        .presentationBackground(settings.backgroundColor)
        .presentationDragIndicator(.visible)
    }
    
    private func cleanFontName(_ name: String) -> String {
        name.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "PSMT", with: "")
            .replacingOccurrences(of: "Regular", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

#Preview {
    SettingsView()
}
