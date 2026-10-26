//
//  ContentView.swift
//  Logoer
//
//  Created by apple on 2024/7/18.
//

import SwiftUI
import SDWebImageSwiftUI

struct maskImage {
    let url: URL
    let image: NSImage
}

class DataModel: ObservableObject {
    @Published var fullScreens = [NSRect]()
    @Published var masks = [maskImage]()
    @Published var appIcon = getIcon(app: NSWorkspace.shared.frontmostApplication)
    @Published var battery = getPowerState()
    /// Screens whose menu bar is currently drawn even though they show a full-screen
    /// Space — the pointer was pulled to the top edge, or the user set the menu bar to
    /// stay visible in full screen. The system Apple glyph is drawn again whenever a
    /// screen is in this list, so the mask has to be shown with it; otherwise the
    /// Apple shows through behind the logo.
    @Published var revealedMenuBars = [NSRect]()
}

struct ContentView: View {
    @AppStorage("pinOnScreen") var pinOnScreen = false
    @AppStorage("maskMode") var maskMode = false
    @AppStorage("shadowON") var shadowON = false
    @AppStorage("userColor") var userColor: Color = .green
    @AppStorage("batteryColor") var batteryColor: Color = .white
    @AppStorage("userEmoji") var userEmoji = "🍎"
    @AppStorage("iconStroke") var iconStroke = "no"
    @AppStorage("logoStyle") var logoStyle = "rainbow"
    @AppStorage("userImage") var userImage: URL = URL(fileURLWithPath: "/")
    @ObservedObject var model: DataModel
    var screen: NSScreen!
    var maskURL: URL!

    /// Whether the system Apple glyph is on screen behind us right now: always, except in
    /// a full-screen Space whose menu bar is hidden.
    private var maskIsNeeded: Bool {
        !model.fullScreens.contains(screen.frame) || model.revealedMenuBars.contains(screen.frame)
    }

    var body: some View {
        ZStack {
            //Color.clear
            if let image = model.masks.first(where: { $0.url == maskURL })?.image, maskMode  {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 24, height: screen.hasTopNotchDesign ? 23 : 24)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .offset(y: screen.hasTopNotchDesign ? -0.5 : 0)
                    // In a full-screen Space the system draws no Apple glyph, and the logo is
                    // only there because "Always on Screen" is set — no mask needed. Pulling
                    // the pointer to the top edge brings the menu bar, and with it the Apple
                    // glyph, back; from then on the mask has to be shown or the Apple appears
                    // behind the logo.
                    .opacity(maskIsNeeded ? 1 : 0)
            }
            ZStack {
                if logoStyle == "color" {
                    if #available(macOS 14, *) {
                        ZStack {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 16.5, weight: .black))
                                .foregroundColor(userColor)
                                .offset(x: -0.1, y: -0.2)
                                .shadow(color: Color.black.opacity(shadowON ? 0.3 : 0.0), radius: 1.5, y: 1.5)
                            Image(systemName: "apple.logo")
                                .font(.system(size: 16.5, weight: .black))
                                .foregroundColor(userColor)
                                .offset(y: -0.2)
                            Image(systemName: "apple.logo")
                                .font(.system(size: 16.5, weight: .black))
                                .foregroundColor(userColor)
                                .offset(x: -0.1, y: -0.1)
                            Image(systemName: "apple.logo")
                                .font(.system(size: 16.5, weight: .black))
                                .foregroundColor(userColor)
                                .offset(y: -0.1)
                        }.frame(width: 16, height: 17)
                    } else {
                        logoImage("Apple", template: true)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 17)
                            .foregroundColor(userColor)
                            .offset(x: -0.5, y: -0.5)
                            .shadow(color: Color.black.opacity(shadowON ? 0.3 : 0.0), radius: 1.5, y: 1.5)
                    }
                } else if logoStyle == "battery" {
                    BatteryGlyph(asset: "battery_apple",
                                 color: batteryColor,
                                 levelColor: logoColor(model.battery.levelColor),
                                 level: model.battery.batteryLevel,
                                 acPowered: model.battery.acPowered,
                                 shadowON: shadowON,
                                 appleStyle: true)
                } else if logoStyle.hasPrefix("battery") {
                    BatteryGlyph(asset: logoStyle,
                                 color: batteryColor,
                                 levelColor: logoColor(model.battery.levelColor),
                                 level: model.battery.batteryLevel,
                                 acPowered: model.battery.acPowered,
                                 shadowON: shadowON)
                } else if logoStyle == "rainbow" {
                    ZStack {
                        if #available(macOS 14, *) {
                            logoImage("rainbow")
                                .interpolation(.high)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 17)
                                .mask (
                                    ZStack {
                                        Image(systemName: "apple.logo")
                                            .font(.system(size: 17, weight: .black))
                                        Image(systemName: "apple.logo")
                                            .font(.system(size: 17, weight: .black))
                                            .offset(y: -0.05)
                                    }
                                )
                        } else {
                            logoImage("rainbow")
                                .interpolation(.high)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 17)
                                .mask (
                                    logoImage("Apple", template: true)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 17)
                                )
                                .offset(x: -0.5, y: -0.1)
                        }
                    }
                    .needOffset(x: 0, y: -0.5)
                    .shadow(color: Color.black.opacity(shadowON ? 0.3 : 0.0), radius: 1.5, y: 1.5)
                } else if logoStyle == "emoji" {
                    if maskMode {
                        Text(userEmoji).font(.system(size: 15))
                            .offset(y: screen.hasTopNotchDesign ? 1 : -0.5)
                            .shadow(color: Color.black.opacity(shadowON ? 0.3 : 0.0), radius: 1.5, y: 1.5)
                    } else {
                        Text(userEmoji)
                            .font(.system(size: 15.5))
                            .offset(x: 0.5)
                            .needOffset(x: 0, y: -0.5)
                            .shadow(color: Color.black.opacity(shadowON ? 0.2 : 0.0), radius: 1.5, y: 1.5)
                    }
                } else if logoStyle == "appicon" {
                    let color: Color = (iconStroke != "no") ? (iconStroke == "white" ? .white : .black) : .clear
                    Image(nsImage: dataModel.appIcon)
                        .interpolation(.high)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .shadow(color: color, radius: 0, x: 0.5)
                        .shadow(color: color, radius: 0, x: -0.5)
                        .shadow(color: color, radius: 0, y: 0.3)
                        .shadow(color: color, radius: 0, y: -0.5)
                        .offset(y: screen.hasTopNotchDesign ? 0.5 : -0.5)
                        .needOffset(x: -0.5, y: -0.5)
                        .shadow(color: Color.black.opacity(shadowON ? 0.3 : 0.0), radius: 1.5, y: 1.5)
                } else if logoStyle == "custom" {
                    ZStack {
                        if userImage != URL(fileURLWithPath: "/") {
                            if userImage.pathExtension == "gif" {
                                WebImage(url: userImage)
                                    .interpolation(.high)
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                if let i = NSImage(contentsOf: userImage) {
                                    Image(nsImage: i)
                                        .interpolation(.high)
                                        .resizable()
                                        .scaledToFit()
                                }
                            }
                        }
                    }
                    .frame(width: 18, height: 18)
                    .offset(y: screen.hasTopNotchDesign ? 0.5 : -0.5)
                    .needOffset(x: -0.5, y: -0.5)
                    .shadow(color: Color.black.opacity(shadowON ? 0.3 : 0.0), radius: 1.5, y: 1.5)
                } else {
                    logoImage(logoStyle + (aboveSonoma ? "" : "_old"))
                        .interpolation(.high)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 17)
                        .needOffset(x: -0.5, y: -0.5)
                        .shadow(color: Color.black.opacity(shadowON ? 0.3 : 0.0), radius: 1.5, y: 1.5)
                }
            }.offset(y: screen.hasTopNotchDesign ? -1.5 : 0)
        }
        .opacity((model.fullScreens.contains(screen.frame) && !pinOnScreen) ? 0 : 1)
        .frame(width: 24, height: 24)
    }
}

// Battery indicator over a silhouette (Apple, Linux Tux, Windows 10 window, Android,
// Ubuntu, ChromeOS, Raspberry Pi, FreeBSD). The outline is a filled Rectangle masked by
// the shape rather than `Image(asset).foregroundColor(...)`: `foregroundColor` does not
// tint an SVG that is not template-rendered (a loose resource copied into Resources),
// and the mask approach gives the same result for either storage.
//
// Charging and non-charging are separate artwork:
//   * on AC  — solid silhouette (the `battery_<x>.svg` blob) filled with the background
//              colour, filled up to the level colour, plus a bolt on top;
//   * on battery — outline-only stroke (`battery_<x>_o.svg`), hollow so the terminal's
//              background shows through the body, filled up to the level colour.
// `appleStyle` keeps the pre-existing Apple rendering (hard-coded at 16×17 with the
// +0.3pt inner offset) instead of the shared 16×16 frame.
struct BatteryGlyph: View {
    let asset: String
    let color: Color
    let levelColor: Color
    let level: Int
    let acPowered: Bool
    let shadowON: Bool
    var appleStyle = false

    private var fillHeight: CGFloat {
        level >= 20 ? max(4, CGFloat(level) / 100 * 14) : 14
    }

    private var shapeAsset: String {
        // Prefer the outline variant when unplugged; fall back to the solid if the
        // outline resource is missing (e.g. an older build's assets).
        if !acPowered, NSImage(named: asset + "_o") != nil { return asset + "_o" }
        return asset
    }

    private var shape: some View {
        logoImage(shapeAsset).resizable().scaledToFit()
    }

    var body: some View {
        ZStack {
            Rectangle().fill(color)
                .mask(shape)
                .shadow(color: Color.black.opacity(shadowON ? 0.3 : 0.0), radius: 1.5, y: 1.5)
            Rectangle().fill(levelColor)
                .mask(
                    shape
                        .mask(
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                Rectangle().frame(height: fillHeight)
                            }
                        )
                )
                // The Apple silhouette has always drawn its inner level fill 0.3pt to
                // the right while on AC — preserve that slight highlight offset.
                .offset(x: (appleStyle && acPowered) ? 0.3 : 0)
                .opacity(acPowered ? 1 : 0)
            if acPowered {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 7.5, weight: .black))
                    .frame(width: 16, height: 16)
                    .foregroundColor(.white)
                    .offset(y: aboveSonoma ? 2 : 1.8)
                    .shadow(color: .black, radius: 1)
            }
        }
        .frame(width: 16, height: appleStyle ? 17 : 16)
        .offset(y: aboveSonoma ? -0.5 : 0)
        .needOffset(x: -0.5, y: -0.5)
    }
}

extension View {
    func needOffset(x: CGFloat, y: CGFloat) -> some View {
        if #available(macOS 14, *) {
            return self
        } else {
            return self.offset(x: x, y: y)
        }
    }
}
