# 验收自检表（ACCEPTANCE）

依据《2026 9月 MoonBit 黑客松大赛章程》阶段三「项目验收」要求，逐条自检。
**提交完成支持申请前必须全部勾选。**

| # | 章程要求 | 状态 | 证据位置 |
|---|---|---|---|
| 1 | 项目以 **MoonBit 为主要实现语言** | ☐ | 全仓库 `.mbt` 源码；无其它语言实现核心逻辑 |
| 2 | GitHub 仓库**公开可访问**，提交记录清晰 | ☐ | 仓库公开；commit 历史连续、有意义 |
| 3 | 源代码结构清晰，**能完成声明的核心功能** | ☐ | `src/aff` `src/dic` `src/affix` `src/check`；与申报书范围一致 |
| 4 | 提供 **README**：项目目标 / 安装方式 / 使用方法 / 示例 / **可复现** | ☐ | `README.md`；可复现步骤见「Quick start」 |
| 5 | **使用持续集成工具，覆盖检查、构建、测试流程** | ☐ | `.github/workflows/ci.yml`（moon check / build / test） |
| 6 | 提供**至少一个可运行示例**或最小使用样例 | ☐ | `examples/`；`docs/EXAMPLES.mbt.md`（示例受类型检查） |
| 7 | 提供**完整测试，覆盖核心功能路径** | ☐ | `moon test`；符合率报告见 `conformance/` |
| 8 | **发布到 mooncakes.io** | ☐ | `moon publish` → 包名：`<待填>` |
| 9 | 采用 **OSI 认可的开源许可证** | ☐ | `LICENSE` = Apache-2.0 |
| 10 | 如参考/移植其他开源项目，符合原项目许可证要求 | ☐ | `NOTICE`：参考 Hunspell（LGPL-2.1），未复制源码；语料不随仓库分发 |

## 提交前的最后检查

- [ ] `moon check` 无错误、无警告
- [ ] `moon build` 通过
- [ ] `moon test` 全部通过
- [ ] `moon fmt` 已执行
- [ ] `moon info` 已执行，`.mbti` diff 符合预期
- [ ] CI 在 GitHub 上显示绿色
- [ ] `README.md` 顶部的符合率数字是**实测**的，不是估的
- [ ] `NOTICE` 里的参考范围与许可证声明准确
- [ ] `DEVLOG.md` 已补齐到最新
- [ ] 申报书承诺的功能**全部实现**；未实现的已在 README「已知限制」中明确标注

## 明确未实现（须在 README 中列出）

> 诚信要求：申报书承诺范围之外的功能若未完成，**必须在 README 中明确标注为未实现**，
> 而不是含糊带过。含糊 = 踩「与申报内容明显不符」。
