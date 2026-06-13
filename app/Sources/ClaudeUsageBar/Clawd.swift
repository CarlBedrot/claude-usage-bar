import SwiftUI

/// The Clawd mascot, drawn with shapes so it scales crisply and can animate.
/// A blocky clay body with a white sticker outline, ">  <" squint eyes, side
/// nubs, and little legs.
struct ClawdView: View {
    /// 0 = eyes open ">  <", 1 = blink (eyes squeezed to a flat "-  -").
    var blink: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // White sticker outline.
                ClawdBody().fill(.white)
                // Clay body, inset to reveal the outline.
                ClawdBody().fill(Palette.clay).padding(s * 0.07)
                // Eyes: ">" and "<" chevrons that flatten when blinking.
                HStack(spacing: s * 0.20) {
                    Eye(flip: false, blink: blink)
                        .stroke(.black, style: .init(lineWidth: s * 0.055, lineCap: .round, lineJoin: .round))
                        .frame(width: s * 0.15, height: s * 0.22)
                    Eye(flip: true, blink: blink)
                        .stroke(.black, style: .init(lineWidth: s * 0.055, lineCap: .round, lineJoin: .round))
                        .frame(width: s * 0.15, height: s * 0.22)
                }
                .offset(y: -s * 0.03)
            }
            .frame(width: s, height: s)
        }
    }
}

/// Body outline: rounded square + two side nubs + three leg notches at the base.
private struct ClawdBody: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        // Main rounded body.
        let body = CGRect(x: w * 0.10, y: h * 0.06, width: w * 0.80, height: h * 0.80)
        p.addRoundedRect(in: body, cornerSize: CGSize(width: w * 0.12, height: w * 0.12))
        // Side nubs (ears/arms).
        let nubW = w * 0.10, nubH = h * 0.16, nubY = h * 0.40
        p.addRoundedRect(in: CGRect(x: w * 0.02, y: nubY, width: nubW, height: nubH),
                         cornerSize: CGSize(width: w * 0.03, height: w * 0.03))
        p.addRoundedRect(in: CGRect(x: w * 0.88, y: nubY, width: nubW, height: nubH),
                         cornerSize: CGSize(width: w * 0.03, height: w * 0.03))
        // Legs: four stubs below the body.
        let legW = w * 0.12, legY = h * 0.82, legH = h * 0.12
        for i in 0..<4 {
            let x = w * (0.20 + Double(i) * 0.165)
            p.addRect(CGRect(x: x, y: legY, width: legW, height: legH))
        }
        return p
    }
}

/// A ">" (or mirrored "<") chevron eye that flattens toward "-" as blink -> 1.
private struct Eye: Shape {
    var flip: Bool
    var blink: CGFloat

    func path(in rect: CGRect) -> Path {
        let midY = rect.midY
        let openY = rect.height * 0.5 * (1 - blink)   // vertical spread shrinks on blink
        let tipX = flip ? rect.minX : rect.maxX
        let baseX = flip ? rect.maxX : rect.minX
        var p = Path()
        p.move(to: CGPoint(x: baseX, y: midY - openY))
        p.addLine(to: CGPoint(x: tipX, y: midY))
        p.addLine(to: CGPoint(x: baseX, y: midY + openY))
        return p
    }
}

/// Clawd peeking into a corner: tucked out of view, occasionally pokes in with
/// a gentle bob and a blink.
/// One place Clawd can peek from: where it anchors, where it hides (off the
/// edge) and where it pokes in to, plus a little tilt.
struct PeekSpot {
    let alignment: Alignment
    let hidden: CGSize
    let peek: CGSize
    let rot: Double
}

/// Clawd peeking into the popover from one of several edges/corners, choosing a
/// new spot each time. Tucked away between peeks, gently bobbing, blinking.
struct ClawdPeeker: View {
    @State private var spotIndex = 0
    @State private var peeking = false
    @State private var bob = false
    @State private var blink: CGFloat = 0
    private let peekTimer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    /// Five spots: three along the top edge, two rising from the bottom corners.
    static let spots: [PeekSpot] = [
        PeekSpot(alignment: .topTrailing, hidden: .init(width: -8, height: -46), peek: .init(width: -8, height: -7), rot: -6),
        PeekSpot(alignment: .top,         hidden: .init(width: 30, height: -46), peek: .init(width: 30, height: -7), rot: 5),
        PeekSpot(alignment: .topLeading,  hidden: .init(width: 90, height: -46), peek: .init(width: 90, height: -7), rot: 6),
        PeekSpot(alignment: .bottomTrailing, hidden: .init(width: -10, height: 46), peek: .init(width: -10, height: 8), rot: 5),
        PeekSpot(alignment: .bottomLeading,  hidden: .init(width: 10, height: 46), peek: .init(width: 10, height: 8), rot: -5),
    ]

    private var spot: PeekSpot { ClawdPeeker.spots[spotIndex] }

    var body: some View {
        ZStack(alignment: spot.alignment) {
            Color.clear
            ClawdView(blink: blink)
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(peeking ? spot.rot : 0), anchor: .center)
                .offset(x: peeking ? spot.peek.width : spot.hidden.width,
                        y: (peeking ? spot.peek.height : spot.hidden.height) + (bob ? -3 : 0))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                bob = true
            }
        }
        .onReceive(peekTimer) { _ in peek() }
    }

    private func peek() {
        // Pick a fresh spot (different from the last) while hidden, then poke in.
        spotIndex = ClawdPeeker.nextSpot(after: spotIndex)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { peeking = true }
        blinkOnce(after: 1.0)
        blinkOnce(after: 3.2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.4) {
            withAnimation(.easeIn(duration: 0.5)) { peeking = false }
        }
    }

    static func nextSpot(after current: Int) -> Int {
        var next = current
        while next == current {
            next = Int.random(in: 0..<spots.count)
        }
        return next
    }

    private func blinkOnce(after delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeInOut(duration: 0.12)) { blink = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.easeInOut(duration: 0.12)) { blink = 0 }
            }
        }
    }
}
