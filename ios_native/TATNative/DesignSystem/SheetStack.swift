import SwiftUI

/// sheet 的外框：導覽列放標題與關閉鈕，把手、圓角與底色交給系統。放在 `.sheet { }` 的最外層，
/// 內容通常是一個 `List`。高度跟著內容，比螢幕高就停在浮動玻璃的最高處、可以捲；上下的留白由這裡統一給。
struct SheetStack<Content: View>: View {
  var title: String?
  var closeLabel = L10n.close
  @ViewBuilder var content: () -> Content
  @Environment(\.dismiss) private var dismiss
  @State private var detents: Set<PresentationDetent> = [.medium, .large]
  @State private var selection: PresentationDetent = .medium
  @State private var extendsUnderHomeIndicator = false

  var body: some View {
    NavigationStack {
      titled
        // 清單預設在第一段上面留一段標題的高度、段與段之間也隔很開，放在 sheet 裡就像多出一塊空白。
        .contentMargins(.top, 12, for: .scrollContent)
        .contentMargins(.bottom, 12 + (extendsUnderHomeIndicator ? Self.homeIndicator : 0), for: .scrollContent)
        // 內容比 sheet 高時，清單在 sheet 升起的途中停在 home indicator 上面、停好才伸進去，最底下那一列會突然冒出來：
        // 一開始就伸進去，用上面的內距把最後一列墊高。底下有按鈕列的不伸，按鈕列要留在安全區域裡。
        .ignoresSafeArea(.container, edges: extendsUnderHomeIndicator ? .bottom : [])
        .listSectionSpacing(.compact)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { SheetCloseButton(label: closeLabel) { dismiss() } }
        .modifier(ContentHeightReader { fit($0, animated: $1, hasBottomBar: $2) })
    }
    .overFloatingTabBar(false)
    .presentationDetents(detents, selection: $selection)
    .presentationDragIndicator(.visible)
  }

  /// 開著的時候內容變高變矮（例如展開空的資料夾），直接把 detent 換掉 sheet 會一格跳到新高度；
  /// 先把新高度加進去再選它，系統才會用動畫過去，動畫結束再拿掉舊的。
  /// 比上限高的一律停在同一個高度：集合裡有好幾個超過上限的高度時，系統會先畫成浮動的玻璃、清掉舊的才貼齊成整頁。
  private func fit(_ height: CGFloat, animated: Bool, hasBottomBar: Bool) {
    let maxHeight = Self.maxFloatingHeight
    let rounded = height.rounded()
    extendsUnderHomeIndicator = rounded >= maxHeight && !hasBottomBar
    let next = PresentationDetent.height(min(rounded, maxHeight))
    guard next != selection else { return }
    guard animated else {
      detents = [next]
      selection = next
      return
    }
    detents.insert(next)
    selection = next
    Task {
      try? await Task.sleep(for: .milliseconds(600))
      if selection == next { detents = [next] }
    }
  }

  private static var keyWindow: UIWindow? {
    UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
  }

  /// sheet 最高到視窗扣掉上下安全區域；離上限 10pt 以內系統就畫成貼齊的不透明整頁，再矮一點才是浮動的玻璃。
  private static var maxFloatingHeight: CGFloat {
    guard let window = keyWindow else { return .infinity }
    return (window.bounds.height - window.safeAreaInsets.top - window.safeAreaInsets.bottom - 11).rounded(.down)
  }

  private static var homeIndicator: CGFloat {
    keyWindow?.safeAreaInsets.bottom ?? 0
  }

  @ViewBuilder private var titled: some View {
    if let title {
      content().navigationTitle(title)
    } else {
      content()
    }
  }
}

/// 捲動內容連同上下內距，扣掉視窗底部的安全區域，就是 `.height` 要的值。iOS 17 量不到，sheet 維持半頁與整頁兩段。
/// 內距在 sheet 升起的過程中不準：上方一開始多算一段 sheet 自己的安全區域，底部會多或少一段，方向看從哪裡呈現。
private struct ContentHeightReader: ViewModifier {
  let onChange: (_ height: CGFloat, _ animated: Bool, _ hasBottomBar: Bool) -> Void
  @State private var latest: Sample?
  @State private var applied: Sample?
  @State private var appliedAt: Date?
  @State private var minTop = CGFloat.infinity

  private struct Sample: Equatable {
    var content: CGFloat
    var top: CGFloat
    var bottom: CGFloat
  }

  func body(content: Content) -> some View {
    if #available(iOS 18, *) {
      let homeIndicator = Self.windowBottomInset ?? 0
      content
        .onScrollGeometryChange(for: Sample?.self) { geometry in
          // 導覽列還沒排進來時上方內距是 0，量到的只有內容。
          guard geometry.contentSize.height > 0, geometry.contentInsets.top > 0 else { return nil }
          return Sample(
            content: geometry.contentSize.height, top: geometry.contentInsets.top, bottom: geometry.contentInsets.bottom)
        } action: { _, sample in
          guard let sample else { return }
          // 上方多算的那段之後只會消失，導覽列本身不會變矮：一律取看過最小的。
          minTop = min(minTop, sample.top)
          latest = sample
        }
        .task(id: latest) {
          guard var sample = latest else { return }
          // 底部第一筆是對的：剛開時一律沿用，之後剛好少一段安全區域的也沿用（清單會停在少的那邊好幾百毫秒）。
          if let applied, isStarting || abs(applied.bottom - sample.bottom - homeIndicator) < 1 {
            sample.bottom = applied.bottom
          }
          // 剛開的 0.1 秒內直接換，趕在 sheet 升起來之前把高度定下來。
          if isStarting {
            apply(sample, homeIndicator: homeIndicator, animated: false)
            return
          }
          // 之後內容沒變、只有內距在變（sheet 在動、鍵盤進出）就等內距停下來才換；內容變了就馬上換。
          if let applied, abs(applied.content - sample.content) < 4 {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
          }
          apply(sample, homeIndicator: homeIndicator, animated: true)
        }
        // 同一個 sheet 關掉再開會留著上一次的狀態，下一次就不會從頭量。
        .onDisappear {
          latest = nil
          applied = nil
          appliedAt = nil
          minTop = .infinity
        }
    } else {
      content
    }
  }

  private var isStarting: Bool {
    appliedAt.map { Date.now.timeIntervalSince($0) < 0.1 } ?? true
  }

  private func apply(_ sample: Sample, homeIndicator: CGFloat, animated: Bool) {
    if appliedAt == nil { appliedAt = .now }
    applied = sample
    let bottomChrome = sample.bottom - homeIndicator
    onChange(sample.content + minTop + max(0, bottomChrome), animated, bottomChrome > 1)
  }

  private static var windowBottomInset: CGFloat? {
    UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.windows.first }
      .first?.safeAreaInsets.bottom
  }
}
