import SwiftUI

/// 修課學生，照 `course_member_page.dart`：名單 API 慢，所以獨占一個畫面，等待時是骨架，搜尋在本機做。
struct CourseMembersView: View {
  @Environment(AppEnvironment.self) private var app
  @State private var model: CourseMembersModel

  init(model: CourseMembersModel) {
    _model = State(initialValue: model)
  }

  var body: some View {
    List {
      if !model.visibleStaff.isEmpty {
        Section {
          ForEach(Array(model.visibleStaff.enumerated()), id: \.offset) { _, member in
            staffRow(member)
          }
        } header: {
          Text(L10n.teachersAndAssistants)
            .textCase(nil)
        }
      }
      Section {
        rows
      } header: {
        Text(header)
          .textCase(nil)
      }
    }
    .listStyle(.insetGrouped)
    // 推進來的頁面用導覽列的搜尋列，背景要等推頁動畫結束才出現；釘在內容頂端就跟著頁面一起出來。
    // 不墊底色：清單捲到搜尋列後面時由系統淡出，和搜尋課程一樣。
    .pinnedTopBar {
      SystemSearchBar(text: Binding(get: { model.query }, set: { model.query = $0 }), prompt: L10n.searchStudent)
        .padding(.horizontal, 8)
    }
    .onChange(of: model.query) {
      Task { await model.filter() }
    }
    .refreshable { await model.load(refresh: true) }
    .navigationTitle(L10n.enrolledStudents)
    .analyticsScreen("/CourseMemberPage")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      if model.members == nil { await model.load(refresh: false) }
    }
  }

  private var header: String {
    let count = model.studentCount
    return count > 0
      ? "\(model.course.name) · \(L10n.peopleCount(String(count)))"
      : model.course.name
  }

  @ViewBuilder private var rows: some View {
    if let members = model.members {
      if let notice = members.notice {
        NoticeBar(message: notice, icon: Lucide.history, actionLabel: L10n.refresh, inList: true) {
          Task { await model.load(refresh: true) }
        }
      }
      if let error = members.error, members.students.isEmpty {
        InlineErrorView(message: error, signedIn: members.signedIn, presenter: app.presenter) {
          await model.load(refresh: true)
        }
      } else {
        ForEach(Array(model.visibleStudents.enumerated()), id: \.offset) { _, member in
          memberRow(member)
        }
      }
    } else {
      // 骨架列數貼著真實人數，載完版面才不會整個跳掉。
      ForEach(0..<skeletonRows, id: \.self) { _ in
        memberRow(CourseMember(name: L10n.enrolledStudents, studentId: L10n.enrolledStudents))
          .redacted(reason: .placeholder)
      }
    }
  }

  private var skeletonRows: Int {
    model.knownCount > 0 ? min(model.knownCount, 5) : 3
  }

  private func memberRow(_ member: CourseMember) -> some View {
    HStack(spacing: 12) {
      avatar(member)
      VStack(alignment: .leading, spacing: 2) {
        Text(member.name)
        if !member.studentId.isEmpty {
          Text(member.studentId)
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, 2)
  }

  /// 老師與助教：角色與 email；有 email 時整列都是複製鈕。
  @ViewBuilder private func staffRow(_ member: CourseMember) -> some View {
    let email = member.email ?? ""
    let content = HStack(spacing: 12) {
      avatar(member)
      VStack(alignment: .leading, spacing: 2) {
        Text(member.name)
          .foregroundStyle(Color.primary)
        if let role = member.role, !role.isEmpty {
          Text(role)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        if !email.isEmpty {
          Text(email)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      if !email.isEmpty {
        Spacer(minLength: 8)
        LucideImage(Lucide.copy, size: 18)
          .foregroundStyle(Color.tatBrand)
      }
    }
    .padding(.vertical, 2)
    if email.isEmpty {
      content
    } else {
      Button {
        UIPasteboard.general.string = email
        app.presenter.toast(L10n.copy, kind: .success)
      } label: {
        content.contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(L10n.copyAction)
    }
  }

  private func avatar(_ member: CourseMember) -> some View {
    AsyncImage(url: member.avatarUrl.flatMap(URL.init(string:))) { phase in
      if let image = phase.image {
        image.resizable().scaledToFill()
      } else {
        Text(member.name.first.map(String.init) ?? "?")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Color(.systemFill))
      }
    }
    .frame(width: 36, height: 36)
    .clipShape(Circle())
  }
}
