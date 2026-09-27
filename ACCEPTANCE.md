# 验收自检表（ACCEPTANCE）

依据《2026 9月 MoonBit 黑客松大赛章程》阶段三「项目验收」要求，逐条自检。
**提交完成支持申请前必须全部勾选。**

| # | 章程要求 | 状态 | 证据位置 |
|---|---|---|---|
| 1 | 项目以 **MoonBit 为主要实现语言** | ✅ | 全仓库 `.mbt` 源码；纯 MoonBit，零 FFI，无其它语言实现核心逻辑 |
| 2 | GitHub 仓库**公开可访问**，提交记录清晰 | ✅ | https://github.com/Careylq/spell.mbt ；commit 历史连续、有意义（32 个） |
| 3 | 源代码结构清晰，**能完成声明的核心功能** | ✅ | `src/aff`（.aff 解析）`src/dic`（.dic 解析）`src/affix`（条件匹配）`src/spell`（判定引擎）`src/suggest`（建议引擎）`src/api`（公开 API）`cmd/main`（CLI） |
| 4 | 提供 **README**：项目目标 / 安装方式 / 使用方法 / 示例 / **可复现** | ✅ | `README.mbt.md`（`README.md` 为其符号链接）；含 Quick start、CLI 用法、可复现步骤 |
| 5 | **使用持续集成工具，覆盖检查、构建、测试流程** | ✅ | `.github/workflows/ci.yml` → `moon check` / `moon build` / `moon test` + 跨后端构建 + 符合率报告 |
| 6 | 提供**至少一个可运行示例**或最小使用样例 | ✅ | `examples/basic`（`moon run examples/basic` 可直接运行）；另有 `examples/doccheck` 用本库检查本仓库自己的文档 |
| 7 | 提供**完整测试，覆盖核心功能路径** | ✅ | `moon test --target all` → **176 个测试**（native **180 个**），四个后端全部通过；另有符合率框架 `conformance/` |
| 8 | **发布到 mooncakes.io** | ✅ | `Careylq/spell@0.9.1`（`build_status: success`）· https://mooncakes.io/docs/Careylq/spell |
| 9 | 采用 **OSI 认可的开源许可证** | ✅ | `LICENSE` = Apache-2.0 |
| 10 | 如参考/移植其他开源项目，符合原项目许可证要求 | ✅ | `NOTICE`：参考 Hunspell（LGPL-2.1）的**格式规范与可观察行为**，未复制源码；测试语料与词典均不随仓库分发 |

## 已实测的符合率与正确性

**官方语料符合率**（`bash conformance/run.sh`，154 个测试套件、848 个 `.good` 判定）：

`.good` **841/848 = 99.2%** ｜ `.wrong` **611/613 = 99.7%** ｜ `.sug` **141/173 = 81.5%**

未通过的 `.good` **正好 7 个**，全部集中在 README「Not implemented yet」已明确列出的三项：
ALL-CAPS 输入去匹配混合大小写词条（`allcaps` / `allcaps_utf` / `allcaps2`，6 个判定、
4 个不同拼写：`OPENOFFICE.ORG` `UNICEF'S` `L'AFRIQUE` `IPOD`）、匈牙利 `LANG hu` 的
moving rule（`forróvíz-tartály`）。未通过的 `.wrong` 只有 2 个：
`allcaps2` 的 `iPodos` 与 `limit-multiple-compounding` 的 `foobarbaz`。

> 计分口径说明：早期 `run.sh` 用 `paste -d' '` 按位置配对，**任何含空格的语料行都会
> 错位并被判为失败**（`morph.good` 有 16 行 `drink eat` 这种），因此当时报出的
> `825/848 = 97.3%` 是**低估**。现在改为「每个非空输入行一个判定、直接计数」，
> 并同时打印历史位置配对数字以便对照；`841 - 825 = 16` 就是该度量假象的大小，
> **引擎行为一个字都没变**。

**真实词典差分测试**（`bash conformance/differential.sh`，en_US + `/usr/share/dict/words`）：

235,976 个词上，本库与原生 `hunspell 1.7.3` 的判定差异 **199 个（0.084%）**：
「该拒绝却接受」**198 个**，「该接受却拒绝」**1 个**（`Jean-Christophe`）。
这 198 个是 Hunspell 由派生规则承认、本库尚未覆盖的形态（`-er`/`-ing`/`-ness`/`-ly` 造词），
且**不是回归**——在引入复合词引擎之前的提交上重跑同一测量，得到完全相同的 198/1。

**建议生成符合率**（`bash conformance/suggest.sh`，37 个 `.sug` 文件、173 行非空期望）：
期望的最佳建议被产出 **141/173 = 81.5%**（按输入顺序做最大单调配对）；
期望最佳即我方第一条 **124/173 = 71.7%**；
完全复现整个 `.sug` 文件（Hunspell 自己的判据）**7/37 套**。

## 性能（真实词典，原生二进制对原生二进制）

同一份 `.aff`/`.dic`、同一份词表，本库 `moon build --target native --release` 对 `hunspell 1.7.3`：

| 指标 | 本库 | Hunspell | 倍数 |
|---|---|---|---|
| 进程启动 | 0.0020 s | 0.0030 s | 0.67×（略快） |
| 词典加载（49,568 词条） | 0.030 s | 0.007 s | 慢 4.29× |
| **直接命中，仅查找** | **0.38 µs/词** | 0.36 µs/词 | **1.06×（持平）** |
| 未命中，仅查找 | 9.60 µs/词 | 1.49 µs/词 | 慢 6.44× |

**结论是精确定位的，不是「整体慢 6 倍」**：差距全在**未命中路径**（每个被拒的词要把每条
后缀规则、前缀规则、前缀×后缀叉积和双后缀族全试一遍）与**词典加载**；**直接查表已与
Hunspell 持平**。这两点就是明确、可验证、可排期的下一步优化目标。

## 诚信说明

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

- [x] `moon check --deny-warn --target all` 无错误、无警告
- [x] `moon build` 通过（wasm / wasm-gc / js / native 四后端 release 均成功）
- [x] `moon test --target all` 全部通过（176 / 176 / 176 / 180）
- [x] `moon fmt` 已执行（`moon fmt --check` 干净）
- [x] `moon info` 已执行，`.mbti` diff 为空（公开接口未变）
- [ ] CI 在 GitHub 上显示绿色 —— **推送后确认**
- [x] `README.md` 顶部的符合率数字是**实测**的，不是估的
- [x] `NOTICE` 里的参考范围与许可证声明准确
- [x] `DEVLOG.md` 已补齐到最新（Day 1–11）
- [ ] 申报书承诺的功能**全部实现**；未实现的已在 README「已知限制」中明确标注 —— **需对照本人提交的申报书原文逐条确认**

## 明确未实现（须在 README 中列出）

> 诚信要求：申报书承诺范围之外的功能若未完成，**必须在 README 中明确标注为未实现**，
> 而不是含糊带过。含糊 = 踩「与申报内容明显不符」。
