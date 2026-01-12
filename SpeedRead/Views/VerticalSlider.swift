import SwiftUI

struct VerticalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    
    @State private var isDragging = false
    
    // Visual constants
    private let trackWidth: CGFloat = 4
    private let thumbSize: CGFloat = 24
    private let sliderHeight: CGFloat = 200
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Track background
                RoundedRectangle(cornerRadius: trackWidth / 2)
                    .fill(Color(hex: "3A3A3A"))
                    .frame(width: trackWidth, height: sliderHeight)
                
                // Active track (from bottom to thumb)
                RoundedRectangle(cornerRadius: trackWidth / 2)
                    .fill(Color(hex: "E63946").opacity(0.6))
                    .frame(width: trackWidth, height: thumbOffset)
                
                // Thumb
                Circle()
                    .fill(Color(hex: "E5E5E5"))
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    .offset(y: -thumbOffset + thumbSize / 2)
                    .scaleEffect(isDragging ? 1.2 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: isDragging)
            }
            .frame(width: thumbSize, height: sliderHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        updateValue(from: gesture.location.y)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .frame(width: thumbSize + 20, height: sliderHeight + 40)
    }
    
    private var thumbOffset: CGFloat {
        let normalized = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(normalized) * sliderHeight
    }
    
    private func updateValue(from yPosition: CGFloat) {
        // Invert Y because we want up = higher value
        let adjustedY = sliderHeight - (yPosition - 20)
        let normalized = max(0, min(1, adjustedY / sliderHeight))
        let newValue = range.lowerBound + (range.upperBound - range.lowerBound) * Double(normalized)
        value = newValue
    }
}

struct VerticalSliderWithLabel: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    
    var body: some View {
        VStack(spacing: 16) {
            // WPM label at top
            Text("\(Int(value))")
                .font(.custom("EBGaramond-Regular", size: 16))
                .foregroundColor(Color(hex: "888888"))
            
            Text("WPM")
                .font(.custom("EBGaramond-Regular", size: 12))
                .foregroundColor(Color(hex: "666666"))
            
            VerticalSlider(value: $value, range: range)
            
            // Min/Max indicators
            VStack(spacing: 4) {
                Image(systemName: "hare.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "555555"))
                
                Spacer().frame(height: 160)
                
                Image(systemName: "tortoise.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "555555"))
            }
            .opacity(0) // Hidden but preserves layout alignment
        }
    }
}

#Preview {
    ZStack {
        Color(hex: "1A1A1A")
        VerticalSliderWithLabel(value: .constant(300), range: 100...1000)
    }
}
