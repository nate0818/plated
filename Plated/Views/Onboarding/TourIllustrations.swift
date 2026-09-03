import SwiftUI

/// A toque, drawn rather than borrowed.
///
/// SF Symbols has a frying pan and a fork and knife and no chef's hat, and
/// the emoji is a whole person. Three puffs and a band is the whole shape,
/// and drawing it means it takes the app's own colours and sits at whatever
/// size the seat it lands on happens to be.
struct ChefHat: View {
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            // The crown: three overlapping puffs.
            Circle()
                .frame(width: size * 0.46, height: size * 0.46)
                .offset(x: -size * 0.24, y: -size * 0.10)
            Circle()
                .frame(width: size * 0.56, height: size * 0.56)
                .offset(y: -size * 0.22)
            Circle()
                .frame(width: size * 0.46, height: size * 0.46)
                .offset(x: size * 0.24, y: -size * 0.10)
            // The band.
            RoundedRectangle(cornerRadius: size * 0.10, style: .continuous)
                .frame(width: size * 0.62, height: size * 0.26)
                .offset(y: size * 0.20)
        }
        .frame(width: size, height: size)
        .foregroundStyle(Color.canvas)
        .shadow(color: Color.ink.opacity(0.16), radius: 3, y: 1)
    }
}

/// The seats arriving one at a time, and the hat landing on whoever cooks.
///
/// Staggered rather than simultaneous: four circles appearing together is a
/// picture, four arriving in order is a table filling up. The hat comes last
/// and from above, because it is the answer to a question the other four
/// have just finished asking.
struct TourSeats: View {
    var isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var seated = 0
    @State private var hatOn = false

    private let seats: [(String, PersonTone)] = [
        ("A", .tomatoPair), ("C", .basilPair), ("N", .grapePair), ("A", .amberPair),
    ]
    /// The one at the stove tonight.
    private let cooking = 2

    var body: some View {
        HStack(spacing: -12) {
            ForEach(Array(seats.enumerated()), id: \.offset) { index, seat in
                AvatarCircle(initials: seat.0, tone: seat.1, size: 62)
                    .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 3))
                    .overlay(alignment: .top) {
                        if index == cooking {
                            ChefHat(size: 30)
                                .offset(y: hatOn ? -18 : -46)
                                .opacity(hatOn ? 1 : 0)
                                .rotationEffect(.degrees(hatOn ? -12 : 4), anchor: .bottom)
                        }
                    }
                    .scaleEffect(index < seated ? 1 : 0.6)
                    .opacity(index < seated ? 1 : 0)
                    // Later seats sit above earlier ones, so the hat is
                    // never clipped by the neighbour it overlaps.
                    .zIndex(Double(index))
            }
        }
        .frame(height: 96)
        .onAppear { play() }
        .onChange(of: isActive) { _, active in
            if active { play() } else { reset() }
        }
        .accessibilityHidden(true)
    }

    private func play() {
        guard isActive else { return }
        guard !reduceMotion else {
            seated = seats.count
            hatOn = true
            return
        }
        reset()
        for index in seats.indices {
            withAnimation(.plPop.delay(Double(index) * 0.09)) { seated = index + 1 }
        }
        withAnimation(.plPop.delay(Double(seats.count) * 0.09 + 0.14)) { hatOn = true }
    }

    private func reset() {
        seated = 0
        hatOn = false
    }
}

/// The week filling in, left to right.
///
/// The same date chips the plan draws, at the same radius and stroke, with
/// today carrying the one tinted card DESIGN.md allows. The nights land in
/// order and today rises last, which is the shape of actually planning a
/// week rather than a picture of one already planned.
struct TourWeek: View {
    var isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var planned = 0
    @State private var todayUp = false

    private let nights = 7
    private let today = 3
    /// The nights already cooked by the time you reach today.
    private let done = 3

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<nights, id: \.self) { day in
                let isToday = day == today
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(isToday ? Color.tomatoTint : Color.cardFill)
                    .frame(width: 34, height: isToday ? 78 : 62)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                            .strokeBorder(isToday ? Color.tomato.opacity(0.16) : Color.hairline,
                                          lineWidth: 1)
                    }
                    .overlay(alignment: .top) {
                        Circle()
                            .fill(day <= done ? Color.basil : Color.hairline)
                            .frame(width: 6, height: 6)
                            .padding(.top, 10)
                            .scaleEffect(day < planned ? 1 : 0)
                    }
                    .scaleEffect(y: isToday && todayUp ? 1 : (isToday ? 0.88 : 1), anchor: .bottom)
                    .opacity(day < planned ? 1 : 0.35)
            }
        }
        .frame(height: 96)
        .onAppear { play() }
        .onChange(of: isActive) { _, active in
            if active { play() } else { reset() }
        }
        .accessibilityHidden(true)
    }

    private func play() {
        guard isActive else { return }
        guard !reduceMotion else {
            planned = nights
            todayUp = true
            return
        }
        reset()
        for day in 0..<nights {
            withAnimation(.plSnap.delay(Double(day) * 0.07)) { planned = day + 1 }
        }
        withAnimation(.plPop.delay(Double(nights) * 0.07 + 0.10)) { todayUp = true }
    }

    private func reset() {
        planned = 0
        todayUp = false
    }
}
