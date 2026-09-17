import SwiftUI

struct PapercutLandscape: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                MountainBackShape()
                    .fill(PapercutPalette.mountainFar)
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 5)
                    .frame(height: 170)

                MountainMidShape()
                    .fill(PapercutPalette.mountainMid)
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 5)
                    .frame(height: 145)

                Circle()
                    .fill(PapercutPalette.sun)
                    .frame(width: 84, height: 84)
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 5)
                    .offset(y: 44)

                WaterShape()
                    .fill(PapercutPalette.water)
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 5)
                    .frame(height: 92)

                SunReflectionShape()
                    .fill(PapercutPalette.sun)
                    .frame(width: 128, height: 38)
                    .offset(y: -15)

                HStack {
                    forestLeft
                        .frame(width: 95, height: 150)
                        .shadow(color: .black.opacity(0.22), radius: 5, y: 5)

                    Spacer(minLength: max(0, proxy.size.width - 190))

                    forestRight
                        .frame(width: 95, height: 150)
                        .shadow(color: .black.opacity(0.22), radius: 5, y: 5)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var forestLeft: some View {
        ZStack(alignment: .bottomLeading) {
            TreeShape(
                points: [
                    (18, 25), (4, 67), (15, 67), (0, 107), (15, 107),
                    (15, 150), (24, 150), (24, 107), (39, 107), (24, 67), (35, 67)
                ],
                sourceWidth: 76
            )
            .fill(PapercutPalette.forestMid)
            .frame(width: 76, height: 150)

            TreeShape(
                points: [
                    (55, 8), (39, 60), (52, 60), (35, 112), (51, 112),
                    (51, 150), (60, 150), (60, 112), (76, 112), (59, 60), (72, 60)
                ],
                sourceWidth: 76
            )
            .fill(PapercutPalette.forestFront)
            .frame(width: 76, height: 150)
        }
    }

    private var forestRight: some View {
        ZStack(alignment: .bottomTrailing) {
            TreeShape(
                points: [
                    (70, 22), (56, 65), (67, 65), (52, 107), (67, 107),
                    (67, 150), (76, 150), (76, 107), (91, 107), (76, 65), (87, 65)
                ],
                sourceWidth: 95
            )
            .fill(PapercutPalette.forestMid)

            TreeShape(
                points: [
                    (35, 5), (19, 58), (32, 58), (15, 111), (31, 111),
                    (31, 150), (40, 150), (40, 111), (56, 111), (39, 58), (52, 58)
                ],
                sourceWidth: 95
            )
            .fill(PapercutPalette.forestFront)
        }
    }
}
