# DEVLOG

开发日志。记录设计取舍、AI 使用方式、踩过的坑。

> 章程明确「鼓励参赛者在开发过程中同步撰写博客、开发日志或经验总结」。
> 本文件同时是季度评选「可解释性」维度的材料。

---

## 2026-09-22 · Day 1 — 项目启动与环境

**做了什么**
- 安装 MoonBit 工具链（`moon 0.1.20260920`，编译器 v0.10.x），macOS arm64。
- 用 `moon new` 生成项目骨架。观察到当前工具链已切到新格式：`moon.mod` / `moon.pkg`
  取代了旧的 `moon.mod.json` / `moon.pkg.json`，并且脚手架自带 `AGENTS.md`、
  `.mbt.md` 形式的 README、`.githooks/pre-commit`。
- 确定选题：Hunspell 兼容的拼写检查库。

**设计取舍**
- **独立实现，不移植 Hunspell 源码**。原因有二：① Hunspell 是 LGPL-2.1，直接移植会把
  许可证传染到本项目；② 黑客松章程把「隐瞒项目移植来源或违反第三方许可证限制」列为
  取消资格条款。因此只参考文件格式规范与可观察行为，本项目用 Apache-2.0。
- **测试语料不 vendor**。Hunspell 官方 `tests/` 语料是 LGPL-2.1，放进 Apache-2.0 仓库会
  造成许可证混用。改为 CI 运行时克隆到临时目录，只产出通过率报告。
- **本期范围刻意收窄**：解析器 + 词缀引擎 + `spell()` 判定。建议引擎是难度最高的部分，
  留作下一期，避免 9 月交付半成品而踩「与申报内容明显不符」。

**踩的坑 / 观察**
- 工具链版本比我预期的新：本地是 `moon 0.1.20260920`，脚手架用 `moon.mod`（TOML 风格）
  而不是社区教程里常见的 `moon.mod.json`。**说明：网上大量 MoonBit 资料已经过期，
  必须以本机工具链和官方文档为准。**
- 因此定下工作流铁律：**AI 负责打字，编译器负责判定真假**。每写一个函数就
  `moon check` + `moon test`，不通过不进下一步。

**AI 使用方式（本日）**
- 用 AI 辅助查阅 `.aff` 格式规范与梳理指令清单。
- 所有生成代码都必须经 `moon check` / `moon test` 验证后才算完成。

---

## 2026-09-22 · Day 2 — `.aff` 解析器（第一个功能切片）

**做了什么**
- 新增 `src/aff/` 包：**`.aff` 文件 → 类型化 AST**。
- 公开 API：`pub fn parse_aff(String) -> AffFile raise AffParseError`
- 覆盖的指令：`SET` `FLAG` `AF` `AM` `PFX` `SFX` `REP` `TRY` `KEY` `IGNORE` `WORDCHARS`
  `COMPOUNDMIN` `COMPOUNDFLAG` `COMPOUNDBEGIN/END/MIDDLE` `COMPOUNDRULE`
  `CHECKCOMPOUNDDUP/TRIPLE/REPEAT/SIMPLIFIEDTRIPLE/PATTERN` `ONLYINCOMPOUND`
  `NOSUGGEST` `KEEPCASE` `FORBIDDENWORD` `NEEDAFFIX` `CIRCUMFIX`；
  其余指令（如 `ICONV`）收进 `unrecognized`（带 name/args/line），不静默丢弃。
- 报错带**行号**（`AffParseError(line~, message~)`，`Show` 渲染成 `line N: message`）。

**验证结果（我自己复跑过，不是"据说"）**
```
moon check                 → 0 errors, 0 warnings
moon test --target all     → Total tests: 22, passed: 22, failed: 0
                             [wasm] [wasm-gc] [js] [native] 全部通过
```
> 顺带白拿一个季度奖加分项：**四个后端全部构建+测试通过**，这本身就是可写进 README 的证据。

**踩的坑 → 已固化成文档**
本切片一共撞上 **11 个编译器层面的坑**（`inspect` 已废弃、`unused_mut` 居然是 error 而不是
warning、`derive(Eq, @debug.Debug)` 触发 0079、带 `raise` 必须写返回类型……）。
全部记进 `docs/MOONBIT_GOTCHAS.md`。

**为什么这件事很重要**
LLM 对 MoonBit 的零样本正确率只有 0–1%（IEEE TSE 论文实测），所以"AI 写的 MoonBit
看着对、编译不过"是常态。这 11 条是**被编译器验证过**的，可直接喂给后续的 AI 迭代，
避免重复踩坑。这也解释了为什么本项目的铁律是「AI 打字、编译器判定」。

**AI 使用方式（本日）**
- 由 AI 实现代码，但**每一块都必须通过 `moon check` + `moon test`** 才算完成；
  期间多次由编译器报错驱动修正，没有接受任何未经编译验证的写法。
- 最终成果经我独立复跑确认（不是采信 AI 的自我报告）。

---

## 待续
