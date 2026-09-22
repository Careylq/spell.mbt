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

## 2026-09-22 · Day 2（续）— `.dic` 解析器 + 词缀条件匹配器

**做了什么**
- `src/dic/`：`.dic` 词典解析。`parse_dic(text, flag_type) -> DicFile raise DicParseError`。
  处理首行词条数、`word/FLAGS`、`word/FLAGS morph...`、`\/` 转义；
  **flag 解码随 `FLAG` 类型变化**（单字符 / long 两位一组 / num 逗号分隔）。
- `src/affix/`：词缀引擎的核心——
  `matches_condition(condition, stem, kind) -> Bool`（Hunspell 的简化正则：`.` `[abc]` `[^abc]` 字面量）
  与 `apply_rule(rule, stem) -> String?`（条件 → strip → add）。

**验证结果（我复跑过）**
```
moon check --target all  → 0 errors, 0 warnings
moon test  --target all  → 55/55 通过
                           [wasm] [wasm-gc] [js] [native] 全部通过
```
切片 1 的 22 个 + 本切片 33 个 = 55 个测试。

**测试抓出的两个"语义 bug"（编译器根本不会报）**
1. 前缀规则的 add 必须**前置**，后缀才后置。第一版把 `PFX 0 re .` 也写成追加，
   `create` 变成了 `createre`。
2. condition 必须对**未 strip 的 stem** 匹配。`SFX y ied [^aeiou]y` 若先 strip 掉 `y`，
   剩下的 `impl` 永远匹配不上以 `y` 结尾的模式。

> 这两条都**不是语法错误**——AI 写出来照样编译通过。
> 这正是本项目把"符合率"当核心证据的原因：**编译器保证语法，测试才保证语义。**

**顺带修正了我自己的一个错误**
我在给实现方的测试基准里把规则 `SFX y ication y` 作用在 `imply` 上的结果写成了
`implification`，**正确答案是 `implication`**（`impl` + `ication`）。
实现方发现并同时断言了两种情况。记录在此，因为它印证了本项目的工作方式：
**谁的断言都不算数，只有跑出来的结果算数。**

**新发现已归档**
本切片又撞上 7 条新坑（`assert_true` 不在 `@debug`、`unused_package` 0029、
`String` 的 UTF-16/码点语义差异、`moon fmt` 会改写 `moon.mod` 等），
全部补进 `docs/MOONBIT_GOTCHAS.md`（现共 18 条）。

**特别值得记的一条**：MoonBit 的 `String` 里
`length()` 是 **UTF-16 code unit** 数、`char_length()` 才是**码点**数，
`get_char(i)` 按 code unit 索引（切在代理对中间会返回 `None`），
`to_array()` 才按码点给出 `Char`。
**做 Unicode 正确的字符匹配必须用 `to_array()`/`char_length()`**——
否则遇到 emoji 或非 BMP 汉字就会出错。本项目的条件匹配已按此实现。

---

## 2026-09-22 · Day 3 — `spell()` 判定引擎 + CLI + 公共 API + 可运行示例

**做了什么**
- `src/spell/`：**判定引擎**（本切片的核心）。
  - `pub struct Dictionary`（不透明类型）+ `Dictionary::from_text(aff, dic)` + `Dictionary::check(self, word) -> Bool`，
    外加 `encoding` / `flag_type` / `rule_count` / `entry_count` 四个只读访问器。
  - **反向查表，不是暴力枚举**：命中词缀派生形式时，从「词」反推词根
    （后缀去掉 `add` 再把 `strip` 接回去；前缀镜像），再校验词根在词典里、带该 flag、
    条件成立，最后用 `apply_rule` 重新生成一次做守卫。一次加载建立 `Map[String, Array[String]]` 索引，
    之后每个词只查表 + 遍历规则，词典只解析一次。
  - **大小写规则**：全小写 / Capitalised / ALL CAPS / 混合大小写（混合只接受精确匹配）。
  - **特殊 flag**：`FORBIDDENWORD` / `KEEPCASE` / `NEEDAFFIX` / `ONLYINCOMPOUND` 在查表时生效。
  - **交叉派生**：同一词根上「一个前缀 + 一个后缀」（两块的 `cross_product = Y`）。
  - **基础复合词**：恰好拆成两个都带 `COMPOUNDFLAG` 的词典词，各自不短于 `COMPOUNDMIN`（缺省 3）。
  - `WORDCHARS` 含 `.` 时接受缩写尾点（`etc.`、`HUNSPELL...`）。
  - **`add` 字段的续接 flag**（`SFX A 0 s/123 .`）在装载时截断成 `s`：第一个词缀要能用；
    通过 `/` 后面的 flag 再链第二个词缀（twofold suffix stripping）**未实现**，已写进 README 限制。
- `src/api/`：薄门面（`load` / `check` / `encoding` / `flag_type_name` / `rule_count` / `entry_count`
  + `pub using` 转出 `Dictionary`、`SpellError`）。模块根 `Careylq/spell` 再转出一次，
  所以 `import { "Careylq/spell" }` 就是最短入口。
- `cmd/main/`：`check` 子命令，严格按 `conformance/README.md` 的契约：
  `--words -` 读 stdin、`--words <file>` 读文件、每个非空输入行输出一行 `1/0`、顺序一致、
  词典只加载一次。**空行不输出**（与 harness 的 `grep .` 对齐）。
  读文件/解析失败 → stderr 报错 + 退出码非 0，绝不静默输出 0。
  另外在 CLI 层做了编码嗅探（见下）。
- `examples/basic/`：可运行示例（`moon run examples/basic`），内嵌自写的小 `.aff`/`.dic`，
  打印编码、flag 模式、规则数、词条数与若干判定（含 `cats`/`boxes`/`happied`/`undos` 等派生形式）。
- `.dic` 解析器顺手修了一个真 bug：**计数行后面的文本要忽略**（Hunspell 用数值扫描，
  语料里有 `4 # Old Persian numbers`），只取第一个空白分隔字段，错误信息仍引用整行。

**验证结果（我复跑过）**
```
moon check --target all   → 0 errors, 0 warnings
moon test  --target all   → 80/80 通过（wasm / wasm-gc / js / native 四个后端）
moon fmt --check          → 通过（含 moon.mod；见下）
CLI 契约                 → printf 'hello\nzzzz\n' | moon run cmd/main -- check --aff p.aff --dic p.dic --words -
                            输出恰为 1 然后 0，退出码 0
坏词典                    → 退出码 1，stdout 为空，stderr 有行号与原因
moon run examples/basic   → 正常运行并打印可人工核对的判定表
```

**真实符合率（跑了完整语料，不是估的）**
```
第一次（只有引擎，无编码/BOM/尾点处理）  good 374/848 = 44.1%   wrong 470/613 = 76.7%
修复后（编码 + BOM + 尾点 + 续接 flag + 计数行注释 + 输入空白）  good 459/848 = 54.1%   wrong 570/613 = 93.0%
```
说明：
- `wrong` 从 76.7% 涨到 93.0%，一部分是**之前 CLI 在 ISO8859 文件上解析失败、一个字都不输出**，
  harness 把「缺输出」也算成未拒绝；编码修好后这些套件才真正给出 `0`。
- 剩下的 `.good` 缺口集中在**明确不做的功能**：`COMPOUNDRULE`/德语复合词、续接 flag
  （twofold affix）、`IGNORE`、`COMPLEXPREFIXES`、`ß → SS` 这类完整 Unicode 大小写映射。
  README 的「Not implemented yet」逐条列了，没有含糊。

**CLI 层的编码处理（值得记）**
- 语料里 `.aff`/`.dic` 有 `ISO8859-1`/`ISO8859-15`（还有无 `SET`、默认 ISO8859-1 的文件），
  但 `.good` 常是 UTF-8 —— 两种编码混在一起。
- 做法：先从 `.aff` 字节里嗅探 `SET`（先跳过 UTF-8 BOM），据此解码 `.aff`/`.dic`；
  词表输入若本身是合法 UTF-8 就按 UTF-8 解，否则回退到词典编码的逐字节解码。
  ISO8859-15 额外映射与 Latin-1 不同的 8 个码位（€、œ/Œ 等）。BOM 一律剥离。
- 这一步把 `base`、`encoding`、`utf8_bom`、`utf8_bom2`、`utf8_nonbmp`、`i54980`、`fullstrip`
  等套件从「整块挂」变成「全过」，其中 `utf8_nonbmp` 还顺带证明了非 BMP 字符是按码点处理的。

**本切片新踩的 MoonBit 坑（已补进 `docs/MOONBIT_GOTCHAS.md`）**
1. **`fn f(self : T, ...)` 作为自由函数是废弃语法**（warning 0027）：编译器会把它当成
   `T::f` 方法，于是同一个文件里按 `f(...)` 调用会报 `unbound value`。
   要么写 `fn T::f(self, ...)` 当方法、用 `self.f(...)` 调，要么把首参改名。
   我一开始写了 9 个 `fn x(self : Dictionary, ...)`，编译器一次报了 24 个错。
2. **`pub using @pkg { type X, fn_name }` 可以做再导出**；模块根用它可以给
   `moon add <模块名>` 一个最短入口。`pub struct`（非 `pub(all)`）在 `.mbti` 里仍会列出字段，
   但它是不可从外部构造的不透明类型（示例与测试都只通过方法使用）。
3. **`.mbt` 的文档注释代码块（```mbt check）也会被 `moon check` 类型检查**，
   而且是在该包的 blackbox 测试上下文里，所以未加 `@本包.` 前缀会触发 warning 0025。
4. `moon fmt --check` 会因为 `moon.mod` 少一个空行而失败（第 15 条坑的另一种表现）；
   接受 `moon fmt` 加的那一行后 `moon fmt --check` 反而通过。本期选择让检查通过。
5. **`&` 的优先级低于 `==`**：`b & 0xC0 == 0x80` 被解析成 `b & (0xC0 == 0x80)`，
   必须写 `(b & 0xC0) == 0x80`。
6. `String` 没有 `ends_with` / `starts_with` / `to_ascii_uppercase`；用
   `strip_prefix` / `strip_suffix`（返回 `StringView?`）和 `contains` 代替。
7. core 没有读文件/读 stdin 的 API：文件与 stdin 走 `moonbitlang/x/fs`（`read_file_to_bytes`），
   非 ASCII 大小写用小写方向走 `moonbitlang/x/unicode`（只有 `to_lowercase(Char)`，没有大写方向）。

**AI 使用方式（本日）**
- 仍然是「AI 打字、编译器判定」：先读 `docs/MOONBIT_GOTCHAS.md` 与既有 `src/`，再写代码，
  每写一块就 `moon check` / `moon test`。上面 7 条坑全部是编译器/测试报出来后才修正的。
- 符合率是**跑完整语料得到的真实数字**，跑了两轮（修复前 / 修复后），没有估算。

---

## 待续
