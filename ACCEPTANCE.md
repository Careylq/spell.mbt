# 验收自检表（ACCEPTANCE）

依据《2026 9月 MoonBit 黑客松大赛章程》阶段三「项目验收」要求，逐条自检。
**提交完成支持申请前必须全部勾选。**

| # | 章程要求 | 状态 | 证据位置 |
|---|---|---|---|
| 1 | 项目以 **MoonBit 为主要实现语言** | ✅ | 全仓库 `.mbt` 源码；纯 MoonBit，零 FFI，无其它语言实现核心逻辑 |
| 2 | GitHub 仓库**公开可访问**，提交记录清晰 | ✅ | https://github.com/Careylq/spell.mbt ；commit 历史连续、有意义（14 个） |
| 3 | 源代码结构清晰，**能完成声明的核心功能** | ✅ | `src/aff`（.aff 解析）`src/dic`（.dic 解析）`src/affix`（条件匹配）`src/spell`（判定引擎）`src/suggest`（建议引擎）`src/api`（公开 API）`cmd/main`（CLI） |
| 4 | 提供 **README**：项目目标 / 安装方式 / 使用方法 / 示例 / **可复现** | ✅ | `README.mbt.md`（`README.md` 为其符号链接）；含 Quick start、CLI 用法、可复现步骤 |
| 5 | **使用持续集成工具，覆盖检查、构建、测试流程** | ✅ | `.github/workflows/ci.yml` → `moon check` / `moon build` / `moon test` + 跨后端构建 |
| 6 | 提供**至少一个可运行示例**或最小使用样例 | ✅ | `examples/basic`（`moon run examples/basic` 可直接运行，输出判定结果） |
| 7 | 提供**完整测试，覆盖核心功能路径** | ✅ | `moon test --target all` → **166 个测试**（native 170 个），四个后端全部通过；另有符合率框架 `conformance/` |
| 8 | **发布到 mooncakes.io** | ✅ | `Careylq/spell@0.3.0`（`build_status: success`）· https://mooncakes.io/docs/Careylq/spell |
| 9 | 采用 **OSI 认可的开源许可证** | ✅ | `LICENSE` = Apache-2.0 |
| 10 | 如参考/移植其他开源项目，符合原项目许可证要求 | ✅ | `NOTICE`：参考 Hunspell（LGPL-2.1）的**格式规范与可观察行为**，未复制源码；测试语料不随仓库分发 |

**已实测的符合率**（`bash conformance/run.sh`，154 个测试套件）：
`.good` **825/848 = 97.3%** ｜ `.wrong` **611/613 = 99.7%** ｜ `.sug` **141/173 = 81.5%**
未通过的 `.good` 里 16 个是 harness 把含空格的 `.good` 行错位的度量问题（`morph.good`），
其余 7 个集中在 README「Not implemented yet」中已明确列出的功能（ALL-CAPS 输入匹配混合大小写词条、
匈牙利 `LANG hu` 的 moving rule、`limit-multiple-compounding` 的三段复合词拼写检查）。

**建议生成符合率**（`bash conformance/suggest.sh`，37 个 `.sug` 文件、173 行非空期望）：
期望的最佳建议被产出 **141/173 = 81.5%**（按输入顺序做最大单调配对）；
期望最佳即我方第一条 **124/173 = 71.7%**；
完全复现整个 `.sug` 文件（Hunspell 自己的判据）**7/37 套**。

ngram 通道**未实现，且是刻意不猜**：`MAXNGRAMSUGS` / `MAXDIFF` / `ONLYMAXDIFF`
已解析进 AST（不再落进 `unrecognized`），但 `hunspell(5)` 手册只写了这是
「基于公共 1/2/3/4 字符序列的相似度检索」并给出 `MAXDIFF` 的默认值 5、范围 0–10
和 `ONLYMAXDIFF` 的「去掉所有差的 ngram 建议」，**没有给相似度评分公式**（各阶
n-gram 权重、归一化、阈值、`MAXNGRAMSUGS` 默认值、何为「差」都没有定义）；
该算法只存在于 LGPL-2.1 的 `suggestmgr.cxx`，本项目不能复制，因此不猜测评分函数。
另需说明：37 个 `.sug` 套件中 12 个显式写 `MAXNGRAMSUGS 0` 关闭该通道，
只有 `1463589`、`1463589_utf`、`base_utf` 写 `1`。
`FORCEUCASE` 驱动的建议通道同样未实现。两点均已在 README 的
「Not implemented yet」中点名。

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
