import SwiftUI

/// 폴더 편집 — 이름 / 모양 / 색. 미리보기 + 삭제.
struct FolderEditView: View {
    let folder: Folder
    var isNew: Bool = false
    var onSave: (_ name: String, _ shape: Int?, _ color: Int?, _ labelColor: Int?) -> Void
    var onDelete: () -> Void
    var onClose: () -> Void

    @State private var name: String
    @State private var shapeIndex: Int
    @State private var colorIndex: Int
    @State private var labelIndex: Int
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    init(folder: Folder, isNew: Bool = false,
         onSave: @escaping (String, Int?, Int?, Int?) -> Void,
         onDelete: @escaping () -> Void,
         onClose: @escaping () -> Void) {
        self.folder = folder; self.isNew = isNew
        self.onSave = onSave; self.onDelete = onDelete; self.onClose = onClose
        _name = State(initialValue: folder.name)
        _shapeIndex = State(initialValue: FolderShape.resolve(folder.shape, id: folder.id).index)
        _colorIndex = State(initialValue: folder.color ?? 0)
        _labelIndex = State(initialValue: folder.labelColor ?? 0)
    }

    private var shape: FolderShape { FolderShape.allCases[shapeIndex] }
    private var fillColor: UIColor { FolderPalette.uiColor(colorIndex) }
    private var labelColor: UIColor { FolderLabelPalette.uiColor(labelIndex) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    preview
                    nameField
                    shapeSection
                    colorSection
                    labelSection
                    if !isNew { deleteButton.padding(.top, 8) }
                }
                .padding(20)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(isNew ? "새 폴더" : "폴더 편집").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("취소") { onClose() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isNew ? "추가" : "저장") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        onSave(n.isEmpty ? folder.name : n, shapeIndex, colorIndex, labelIndex)
                    }.fontWeight(.bold)
                }
            }
            .confirmationDialog("이 폴더를 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("삭제", role: .destructive) { onDelete() }
                Button("취소", role: .cancel) {}
            } message: { Text("안에 담긴 스티커는 미분류로 돌아가요.") }
        }
        .presentationDetents([.large])
        .presentationBackground(.black)
    }

    private var preview: some View {
        Image(uiImage: shape.image(name: name.isEmpty ? " " : name, fill: fillColor, label: labelColor, size: 240))
            .resizable().scaledToFit().frame(width: 130, height: 130)
            .padding(.top, 8)
    }

    private var nameField: some View {
        TextField("폴더 이름", text: $name)
            .font(.headline).multilineTextAlignment(.center)
            .padding(.horizontal, 16).frame(height: 48)
            .background(Theme.surface, in: Capsule()).foregroundStyle(Theme.ink)
            .onChange(of: name) { _, v in if v.count > 12 { name = String(v.prefix(12)) } }
    }

    private var shapeSection: some View {
        section("모양") {
            grid {
                ForEach(FolderShape.allCases.indices, id: \.self) { i in
                    cell(selected: shapeIndex == i) { shapeIndex = i } content: {
                        Image(uiImage: FolderShape.allCases[i].image(name: "", fill: fillColor, size: 160))
                            .resizable().scaledToFit().padding(8)
                    }
                }
            }
        }
    }

    private var colorSection: some View {
        section("색") {
            grid {
                ForEach(FolderPalette.hexes.indices, id: \.self) { i in
                    cell(selected: colorIndex == i) { colorIndex = i } content: {
                        Circle().fill(FolderPalette.color(i)).padding(10)
                    }
                }
            }
        }
    }

    private var labelSection: some View {
        section("레이블") {
            grid {
                ForEach(FolderLabelPalette.hexes.indices, id: \.self) { i in
                    cell(selected: labelIndex == i) { labelIndex = i } content: {
                        Circle().fill(FolderLabelPalette.color(i))
                            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                            .padding(10)
                    }
                }
            }
        }
    }

    private var deleteButton: some View {
        Button { confirmDelete = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                Text("폴더 삭제")
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color(hex: 0xFF6B6B))
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(Color(hex: 0xFF6B6B).opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(Color(hex: 0xFF6B6B).opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.bold()).foregroundStyle(Theme.muted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func grid<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            content()
        }
    }

    private func cell<C: View>(selected: Bool, _ action: @escaping () -> Void, @ViewBuilder content: () -> C) -> some View {
        Button(action: action) {
            content()
                .frame(height: 64)
                .frame(maxWidth: .infinity)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.lime, lineWidth: selected ? 3 : 0)
                )
        }
        .buttonStyle(.plain)
    }
}
