import SwiftUI

// MARK: - 模板标签栏

/// 画布上方的模板标签栏：横向滚动展示所有内置模板，点击加载到画布
struct TemplateTabBar: View {
    /// 当前选中的模板ID
    @Binding var selectedTemplateId: String?
    /// 选择模板回调
    let onSelect: (WorkflowTemplate) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // 分类标题 + 模板标签
                ForEach(WorkflowTemplateDatabase.allCategories, id: \.self) { category in
                    Section {
                        ForEach(WorkflowTemplateDatabase.templates(in: category)) { template in
                            TemplateTabChip(
                                template: template,
                                isSelected: selectedTemplateId == template.id,
                                onTap: {
                                    selectedTemplateId = template.id
                                    onSelect(template)
                                }
                            )
                        }
                    } header: {
                        Text(category)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(.secondarySystemBackground))
        .frame(height: 44)
    }
}

// MARK: - 单个模板标签芯片

/// 模板标签芯片：图标 + 名称
private struct TemplateTabChip: View {
    let template: WorkflowTemplate
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: template.icon)
                    .font(.caption)
                Text(template.name)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemBackground))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
            .foregroundColor(isSelected ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}
