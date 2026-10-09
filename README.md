# ComfyUIDemo

> ComfyUI 工作流 iOS 端演示应用。纯原生 Swift + SwiftUI，最低 iOS 16，支持 iPhone 8 Plus，巨魔（TrollStore）侧载未签名 IPA。

## 功能特性

- **JSON 导入**：支持粘贴 JSON 文本或从「文件」App 选择 `.json` 文件
- **本地保存**：可将编辑后的工作流 JSON 保存到应用文档目录
- **画布渲染**：基于 SwiftUI Canvas 高性能渲染分组、连线、节点与控件
- **分组渲染**：支持 ComfyUI Groups 分组背景框与标题展示
- **控件渲染**：节点内部 widgets_values 只读展示（文本/数值/开关样式）
- **手势交互**：单指拖拽平移、双指缩放，缩放范围 0.1x ~ 1.5x
- **节点详情检查器**：点击节点弹出半屏面板，三标签页切换（参数/插槽/原始JSON），展示上下游连接关系
- **色彩体系**：节点按类型自动着色（加载器蓝/采样器红/条件黄/潜空间粉等），连线颜色与源插槽类型一致
- **重置视角**：一键适配整个工作流（含分组）到屏幕中央
- **自动适配**：支持所有 iPhone 屏幕尺寸及横竖屏切换
- **容错解析**：单个节点/分组解析失败不影响整体，损坏节点自动隔离
- **独立页面**：画布为独立全屏页面，顶部导航栏返回+重置，不与主页UI冲突

## 技术栈

| 项目 | 说明 |
|------|------|
| 语言 | Swift 5.9 |
| UI 框架 | SwiftUI（iOS 16+） |
| 渲染引擎 | SwiftUI Canvas |
| 构建工具 | XcodeGen（project.yml） |
| 最低系统 | iOS 16.0 |
| 目标设备 | iPhone 8 Plus 及更新 |
| 打包方式 | GitHub Actions → 未签名 IPA |
| 安装方式 | TrollStore 巨魔侧载 |

## 项目结构

```
ComfyUIDemo/
├── ComfyUIDemoApp.swift          # 应用入口
├── ContentView.swift             # 主页（导航 + 画布容器）
├── Info.plist                    # 应用配置
├── Assets.xcassets/              # 资源目录
├── Models/
│   └── WorkflowModel.swift       # 工作流/节点/插槽/连线数据模型
├── Views/
│   ├── WorkflowCanvasPage.swift  # 独立画布页面（导航栏 + 返回 + 重置）
│   ├── WorkflowCanvasView.swift  # 画布视图（核心渲染 + 手势）
│   ├── JsonImportView.swift      # JSON 导入/编辑页面
│   └── NodeDetailSheet.swift     # 节点详情弹窗
└── Utils/
    ├── JsonParser.swift          # JSON 解析与校验
    ├── CanvasMath.swift          # 画布数学（包围盒/缩放钳位）
    └── ScreenAdapter.swift       # 屏幕适配工具
```

## 本地构建

```bash
# 安装 XcodeGen
brew install xcodegen

# 生成 Xcode 工程
xcodegen generate

# 打开工程
open ComfyUIDemo.xcodeproj
```

## CI/CD

推送代码到 `main` 分支后，GitHub Actions 自动构建未签名 IPA，产物在 Actions 页面下载。

- 工作流文件：`.github/workflows/build.yml`
- 运行环境：macOS 14
- 产物名称：`ComfyUIDemo-unsigned`

## 巨魔安装

1. 从 GitHub Actions 下载 `ComfyUIDemo.ipa`
2. 通过 TrollStore 安装到设备
3. 无需开发者证书，无需签名

## 适配说明

- **缩放边界**：最小 0.1x（超大工作流）、最大 1.5x（单节点不过度放大）
- **手势并发**：`SimultaneousGesture` 同时处理拖拽与缩放，`lastOffset` / `lastZoom` 累加
- **高性能渲染**：变换在 Canvas 内部 `translateBy` / `scaleBy` 执行，避免离屏渲染
- **插槽定位**：输出插槽在节点右侧，输入插槽在左侧，按索引垂直分布

## 版本

- v1.0.0：初始版本，支持 JSON 导入、画布渲染、节点详情、手势交互
