import SwiftUI

/// 一整天檢視，照 `classroom_day_grid.dart`：不寫課名，空著留白、現在是一條線，空得最久的排前面。
/// 十四節在手機上放不下，格子橫向捲，教室編號那一欄釘住不動。
struct ClassroomDayGrid: View {
  let day: ClassroomDay
  let sections: [ClassSection]
  let section: Int
  let onTap: (ClassroomRoom) -> Void

  private let cellWidth: CGFloat = 26
  private let cellHeight: CGFloat = 20
  private let rowHeight: CGFloat = 28
  private let gap: CGFloat = 3
  private let nameWidth: CGFloat = 76
  private let headerHeight: CGFloat = 22
  private let groupHeight: CGFloat = 34

  private struct RoomGroup {
    let label: String
    let rooms: [ClassroomRoom]
  }

  private enum CellKind {
    case free, lesson, booked
  }

  private struct CellFills {
    let free: Color
    let lesson: Color
    let booked: Color
  }

  private var groups: [RoomGroup] {
    var groups: [RoomGroup] = []
    if !day.free.isEmpty {
      groups.append(RoomGroup(label: L10n.classroomFreeGroup(String(day.free.count)), rooms: day.free))
    }
    if !day.busy.isEmpty {
      groups.append(RoomGroup(label: L10n.classroomBusyGroup(String(day.busy.count)), rooms: day.busy))
    }
    return groups
  }

  private var gridWidth: CGFloat {
    CGFloat(sections.count) * cellWidth + CGFloat(max(sections.count - 1, 0)) * gap
  }

  var body: some View {
    let groups = self.groups
    // 空格用頁面底色，在卡片上才看得見；借出與排課分兩色，看得出「沒課但也去不了」。
    // 品牌色是 Observation 的值，一次 body 讀一次就好，不必每一格各讀一次。
    let fills = CellFills(
      free: Color(.systemGroupedBackground),
      lesson: Color.tatBrand.opacity(0.5),
      booked: Color(.systemOrange).opacity(0.5))
    HStack(alignment: .top, spacing: 0) {
      names(groups)
        .frame(width: nameWidth, alignment: .leading)
        .zIndex(1)
      ScrollView(.horizontal) {
        ZStack(alignment: .topLeading) {
          VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
              Color.clear.frame(height: groupHeight)
              ForEach(group.rooms, id: \.name) { room in
                cells(room, fills)
              }
            }
          }
          nowLine(groups)
        }
        .padding(.trailing, 14)
      }
      .scrollIndicators(.hidden)
    }
    .padding(EdgeInsets(top: 10, leading: 14, bottom: 14, trailing: 0))
    .background(
      Color(.secondarySystemGroupedBackground), in: ListGroupShape.card)
  }

  /// 釘住的那一欄。分段標題比這一欄寬，但它右邊本來就沒有格子，讓它畫出去即可。
  private func names(_ groups: [RoomGroup]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Color.clear.frame(height: headerHeight)
      ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
        Text(group.label)
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
          .fixedSize()
          .frame(width: nameWidth, height: groupHeight, alignment: .leading)
        ForEach(group.rooms, id: \.name) { room in
          Button {
            onTap(room)
          } label: {
            Text(room.name)
              .font(.footnote)
              .foregroundStyle(Color.primary)
              .frame(width: nameWidth, height: rowHeight, alignment: .leading)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var header: some View {
    HStack(spacing: gap) {
      ForEach(Array(sections.enumerated()), id: \.offset) { index, item in
        Text(item.label)
          .font(.caption.monospacedDigit())
          .foregroundStyle(index == section ? Color.tatBrand : Color.secondary)
          .frame(width: cellWidth)
      }
    }
    .frame(height: headerHeight)
  }

  /// 整條格子也點得開：捲到後面幾節時，手指落在格子上。
  /// 同一種顏色的格子合成一個形狀，一列最多三個：一格一個的話，教室多的大樓切到一整天要一次建五百多個，會卡一下。
  private func cells(_ room: ClassroomRoom, _ fills: CellFills) -> some View {
    let kinds = sections.indices.map { kind(room, $0) }
    func columns(_ target: CellKind) -> [Int] {
      kinds.indices.filter { kinds[$0] == target }
    }
    return Button {
      onTap(room)
    } label: {
      ZStack {
        layer(columns(.free), fills.free)
        layer(columns(.lesson), fills.lesson)
        layer(columns(.booked), fills.booked)
      }
      .frame(width: gridWidth, height: rowHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder private func layer(_ columns: [Int], _ fill: Color) -> some View {
    if !columns.isEmpty {
      CellsShape(columns: columns, cellWidth: cellWidth, cellHeight: cellHeight, gap: gap)
        .fill(fill)
    }
  }

  private func kind(_ room: ClassroomRoom, _ index: Int) -> CellKind {
    guard index < room.slots.count, !room.slots[index].free else { return .free }
    return room.slots[index].booked ? .booked : .lesson
  }

  /// 「現在」那一條線，從節次標題底下才開始畫，跟著格子一起左右移動。
  @ViewBuilder private func nowLine(_ groups: [RoomGroup]) -> some View {
    if section >= 0, section < sections.count {
      let rows = groups.reduce(CGFloat(0)) { $0 + groupHeight + CGFloat($1.rooms.count) * rowHeight }
      Rectangle()
        .fill(Color.tatBrand)
        .frame(width: 2, height: max(rows - (rowHeight - cellHeight) / 2, 0))
        .offset(x: CGFloat(section) * (cellWidth + gap) + cellWidth / 2 - 1, y: headerHeight)
        .allowsHitTesting(false)
    }
  }
}

/// 一列裡同一種顏色的格子，每一格的位置與圓角跟一格一個 `RoundedRectangle` 時一樣。
private struct CellsShape: Shape {
  let columns: [Int]
  let cellWidth: CGFloat
  let cellHeight: CGFloat
  let gap: CGFloat

  func path(in rect: CGRect) -> Path {
    var path = Path()
    for column in columns {
      path.addRoundedRect(
        in: CGRect(
          x: rect.minX + CGFloat(column) * (cellWidth + gap), y: rect.midY - cellHeight / 2,
          width: cellWidth, height: cellHeight),
        cornerSize: CGSize(width: 4, height: 4), style: .continuous)
    }
    return path
  }
}
