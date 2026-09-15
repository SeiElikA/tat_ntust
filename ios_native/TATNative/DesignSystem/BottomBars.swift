import SwiftUI

extension View {
  /// 釘在底部的一列（回覆列、動作列）。iOS 26 用 `safeAreaBar`：內容捲到它後面時由系統淡出，
  /// 不墊一塊不透明的底；之前的系統照舊墊 `.bar`。左右留白由這裡給，列本身不要再加。
  func pinnedBottomBar<Bar: View>(@ViewBuilder _ bar: @escaping () -> Bar) -> some View {
    modifier(PinnedBar(edge: .bottom, bar: bar))
  }

  /// 釘在頂端、不跟著內容捲走的一列（篩選籤、搜尋列），做法同 `pinnedBottomBar`。
  func pinnedTopBar<Bar: View>(@ViewBuilder _ bar: @escaping () -> Bar) -> some View {
    modifier(PinnedBar(edge: .top, bar: bar))
  }

  /// page 樣式的 `TabView` 會把每一頁裁在安全區域裡，分頁列、導覽列與釘住的列後面就看不到內容。讓它延伸出去，
  /// 再把讓出來的高度交給每一頁的捲動內容（`pageScrollInset`）。上方要釘一列時 `pinnedTopBar` 掛在這之外，
  /// 這裡才量得到那一列；用 `safeAreaInset` 或和 `TabView` 排進同一個 `VStack` 的列，內容透不過去。
  func extendsUnderBars() -> some View {
    modifier(ExtendsUnderBars())
  }

  /// 放在 page 樣式分頁裡的捲動內容：第一列從上方的列下面開始，最後一列捲得到分頁列上面。不在那種分頁裡時什麼都不做。
  func pageScrollInset() -> some View {
    modifier(PageScrollInset())
  }

  /// 這一層底下的頁面浮在分頁列上方：`MainTabView` 打開；sheet 會繼承 environment，最外層要關掉（`SheetStack` 已經關了）。
  func overFloatingTabBar(_ on: Bool = true) -> some View {
    environment(\.overFloatingTabBar, on)
  }
}

private enum BarEdge {
  static let content: CGFloat = 16
  /// iOS 26 浮動分頁列離螢幕邊的距離，系統沒有提供這個值。
  static let tabBar: CGFloat = 21
}

private struct PinnedBar<Bar: View>: ViewModifier {
  let edge: VerticalEdge
  let bar: () -> Bar
  @Environment(\.overFloatingTabBar) private var overTabBar
  @Environment(\.horizontalSizeClass) private var horizontal
  @Environment(\.verticalSizeClass) private var vertical

  func body(content: Content) -> some View {
    if #available(iOS 26, *) {
      content.safeAreaBar(edge: edge, spacing: 0) { bar().padding(.horizontal, sideInset) }
    } else {
      content.safeAreaInset(edge: edge, spacing: 0) { bar().padding(.horizontal, sideInset).background(.bar) }
    }
  }

  /// 上方的列各自跟內容切齊，這裡不加。iPad 的分頁列在上方（寬的視窗兩個方向都是 regular），底部列跟內容切齊。
  private var sideInset: CGFloat {
    guard edge == .bottom else { return 0 }
    if #available(iOS 26, *), overTabBar, horizontal == .compact || vertical == .compact {
      return BarEdge.tabBar
    }
    return BarEdge.content
  }
}

private struct ExtendsUnderBars: ViewModifier {
  func body(content: Content) -> some View {
    GeometryReader { proxy in
      if #available(iOS 26, *) {
        content
          .environment(
            \.pageInsets,
            EdgeInsets(top: proxy.safeAreaInsets.top, leading: 0, bottom: proxy.safeAreaInsets.bottom, trailing: 0)
          )
          .ignoresSafeArea(edges: .vertical)
      } else {
        // 之前的導覽列與 `.bar` 不是隨捲動淡出的樣式，上方維持原樣，只延伸到底部。
        content
          .environment(\.pageInsets, EdgeInsets(top: 0, leading: 0, bottom: proxy.safeAreaInsets.bottom, trailing: 0))
          .ignoresSafeArea(edges: .bottom)
      }
    }
  }
}

private struct PageScrollInset: ViewModifier {
  @Environment(\.pageInsets) private var insets

  func body(content: Content) -> some View {
    // 上下要用同一種 placement：上面用 `.automatic`、下面用 `.scrollContent` 時上面那段不會生效，內容會跑到導覽列底下。
    content
      .contentMargins(.top, insets.top, for: .scrollContent)
      .contentMargins(.bottom, insets.bottom, for: .scrollContent)
  }
}

private struct PageInsetsKey: EnvironmentKey {
  static let defaultValue = EdgeInsets()
}

private struct OverFloatingTabBarKey: EnvironmentKey {
  static let defaultValue = false
}

private extension EnvironmentValues {
  var pageInsets: EdgeInsets {
    get { self[PageInsetsKey.self] }
    set { self[PageInsetsKey.self] = newValue }
  }

  var overFloatingTabBar: Bool {
    get { self[OverFloatingTabBarKey.self] }
    set { self[OverFloatingTabBarKey.self] = newValue }
  }
}
