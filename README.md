# Thunder Note iOS Client

> 阶段 I-0 工程基线。详见根仓 `docs/完整开发计划.md` § D2 与 `docs/客户端架构设计.md` § iOS 端。

## 依赖
- macOS 14+
- Xcode 15.4+
- iOS 17 SDK（部署目标 iOS 16.0+）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（工程文件由 `project.yml` 单点生成）

## 首次设置
```bash
brew install xcodegen
cd thunder_note_ios
xcodegen generate
open ThunderNote.xcodeproj
```

## 常用命令
```bash
# 重新生成工程（修改 project.yml 后必跑）
xcodegen generate

# 模拟器构建
xcodebuild \
  -project ThunderNote.xcodeproj \
  -scheme ThunderNote \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build

# 单测
xcodebuild \
  -project ThunderNote.xcodeproj \
  -scheme ThunderNote \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  test
```

## 目录结构
```
thunder_note_ios/
├── project.yml                # XcodeGen 工程描述（唯一事实源）
├── ThunderNote/               # 主 App target
│   ├── App/                   # 入口、根 View
│   ├── DesignSystem/          # 颜色 / 字号 / 间距 token
│   ├── Core/                  # 缓存、网络、持久化、日志（按需扩展）
│   ├── Features/              # 业务模块（后续阶段填充）
│   └── Resources/             # Info.plist / Assets / 本地化
├── ThunderNoteTests/          # XCTest 单元测试
├── ThunderNoteUITests/        # XCUITest UI 测试
└── ThunderNoteShareExtension/ # 系统分享扩展（I-5 完整接入，当前是占位）
```

## 维护规则
- 工程级配置（target / build settings / Info.plist / 依赖）改 `project.yml`，不要手改生成出来的 `*.xcodeproj`。
- 新增 / 删除 / 重命名源码文件后重新跑一次 `xcodegen generate`。
- iOS 改动一律走 `thunder_note_ios/` 子仓，不要把 iOS 代码放到根仓索引里。
