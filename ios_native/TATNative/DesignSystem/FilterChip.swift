import SwiftUI

/// 篩選籤，照 Flutter 版的 `TatFilterChip`：沒選是描邊，選中是品牌色淡底加打勾。iOS 26 是玻璃，選中的玻璃淡淡帶品牌色。
struct FilterChip: View {
  let label: String
  var icon: LucideIcon?
  let isOn: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if isOn {
          LucideImage(Lucide.check, size: 16)
        } else if let icon {
          LucideImage(icon, size: 16)
        }
        Text(label)
          .font(.subheadline.weight(.medium))
      }
      .padding(.horizontal, 12)
      .frame(minHeight: 34)
      .chipSurface(isOn: isOn)
      .contentShape(Capsule())
    }
    .chipButtonStyle()
    .accessibilityAddTraits(isOn ? .isSelected : [])
  }
}

extension View {
  /// 籤的底色與字色，成績的學期籤也用。
  /// 同一排不包 `GlassEffectContainer`：在水平捲動列裡隔著 `if #available` 包容器，選中時多出打勾的籤不會重算寬度，字被截掉。
  /// 放進水平 `ScrollView` 要加 `.scrollClipDisabled()`：iOS 26 的玻璃陰影比列高長，被裁掉會在籤下面留一條直線。
  func chipSurface(isOn: Bool, outlined: Bool = true, offColor: Color = .primary) -> some View {
    modifier(ChipSurface(isOn: isOn, outlined: outlined, offColor: offColor))
  }

  /// iOS 26 按下去由玻璃自己回饋，`.plain` 會再把整顆籤淡掉。
  @ViewBuilder
  func chipButtonStyle() -> some View {
    if #available(iOS 26, *) {
      buttonStyle(ChipPressStyle())
    } else {
      buttonStyle(.plain)
    }
  }
}

private struct ChipSurface: ViewModifier {
  let isOn: Bool
  let outlined: Bool
  let offColor: Color
  @Environment(\.isEnabled) private var isEnabled

  func body(content: Content) -> some View {
    if #available(iOS 26, *) {
      // 字色和玻璃在同一段動畫裡換，才不會一前一後。
      content.animation(.easeOut(duration: 0.2)) {
        $0
          .foregroundStyle(isOn ? Color.tatBrand : Color(.label))
          .glassEffect(
            (isOn ? Glass.regular.tint(Color.tatBrand.opacity(0.3)) : Glass.regular).interactive(isEnabled),
            in: Capsule())
      }
    } else {
      content
        .foregroundStyle(isOn ? Color.tatBrand : offColor)
        .background(isOn ? Color.tatBrand.opacity(0.14) : Color.clear, in: Capsule())
        .overlay {
          if outlined { Capsule().strokeBorder(Color(.separator), lineWidth: isOn ? 0 : 1) }
        }
    }
  }
}

private struct ChipPressStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label.opacity(isEnabled ? 1 : 0.5)
  }
}
