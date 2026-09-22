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

## 2026-09-22 · Day 4 — 符合率攻坚：54.1% → 84.7%

**背景**
- 起点的实测数字（真实跑完整语料，154 个套件）：

```
.good  : 459/848 = 54.1%     .wrong : 570/613 = 93.0%
```

- 本轮的目标只有一个：把 `.good` 拉上去，**同时不许把 `.wrong` 拉下来**（硬约束：不低于 570）。
  每改一处都重跑 `bash conformance/run.sh`，下面的数字全部来自真实运行。

**逐个特性的前后对比（都是整语料实测）**

| 特性 | `.good` | `.wrong` | 备注 |
|---|---|---|---|
| 起点 | 459/848 | 570/613 | |
| `IGNORE` 字符 | 483/848 | 570/613 | ignore/ignoresug/ignoreutf/right_to_left_mark 全过 |
| `FLAG UTF-8` 编码 bug | 504/848 | 570/613 | flagutf8 2/8 → 4/8；详见下节 |
| `CHECKSHARPS` | 504/848 | 570/613 | checksharps 13/13、checksharpsutf 13/13、checksharpsutf2 12/12（+19） |
| `COMPOUNDRULE` | 624/848 | 570/613 | compoundrule 0/2→2/2，2 0/37→37/37，5 0/7→7/7，7/8 9/29→29/29（+120） |
| 词缀延续标志（二重后缀）+ `AF` 向量 + 派生形 `NEEDAFFIX`/`ONLYINCOMPOUND` | 660/848 | **579**/613 | alias/flag 系列全过，`.wrong` 反而净增 9 |
| 同形异义词（homonym）+ 数字 + `BREAK` | 712/848 | 579/613 | needaffix2/4 1/4→4/4，i53643 0/21→21/21，break 4/12→12/12 |
| 两段式 `COMPOUNDBEGIN`/`COMPOUNDEND` | **718/848 (84.7%)** | **579/613 (94.5%)** | 2999225 1/2→2/2，opentaal_keepcase 0/4→4/4 |

**找到的真 bug：`flagutf8` 不是 `FLAG UTF-8` 的解析问题，是 CLI 的编码嗅探**

- 现象：`flagutf8` 只有 2/8。该 `.aff` **没有 `SET` 行**，但声明了 `FLAG UTF-8`，
  且 flag 是 `ö`/`ü`/`Ü` 这样的多字节字符。
- CLI 的 `sniff_encoding` 在没有 `SET` 时按 Hunspell 默认回落到 Latin-1，于是
  `Ü`（UTF-8 的 `C3 9C`）被解成两个 Latin-1 字符。
- 关键的不一致：`.aff` 解析器把规则 flag 原样存成**一个两字符串**
  `"Ã\u{9C}"`，而 `.dic` 的 `decode_flags`（`FLAG UTF-8`）按**字符**切分，得到
  两个单字符 flag `["Ã", "\u{9C}"]`。两边永远不相等 → `unfoo`/`unfoos` 判错。
- 修法：`sniff_encoding` 在没有 `SET` 时也识别 `FLAG UTF-8`，认定为 UTF-8
  （一个 flag 就是一个 Unicode 字符，只能是 UTF-8）。这是**语义性 bug**，
  编译器不会报，只有语料能抓出来。
- 剩下的 4 个词（`foosbar` 等）当时确实缺"延续标志"特性，不是 bug；本轮后续补上了，
  现在 `flagutf8` 是 8/8。

**最惊险的一次：`.wrong` 一度掉到 560**

- 实现二重后缀后 `.good` 涨到 660，但 `.wrong` 从 570 掉到 **560**：
  `germancompounding` / `germancompoundingold` 各多认了 5 个错词
  （`computer`、`computern`、`arbeit`、`Arbeits`、`arbeits`）。
- 定位：`computer` 被 `PFX D C c/PX C`（德语去大写前缀）+
  `SFX B 0 0/VWXDP .`（空后缀）拼出来。`PFX D` 的 flag `D` 不在词根上，
  而是由那条后缀的**延续标志** `VWXDP` 提供的，所以旧的检查放行了。
- 根因：**延续标志里的 `ONLYINCOMPOUND`/`NEEDAFFIX` 也必须生效**。
  `Arbeits` = `Arbeit` + `SFX A 0 s/UPX .`，`X` 是 `ONLYINCOMPOUND`，
  所以 `Arbeits` 只能在复合词里出现，单独出现必须判错。
- 修法：新增 `derived_standalone(rules)`——按施加顺序模拟状态机：
  `ONLYINCOMPOUND` 一旦出现在任一延续类里就永不允许单独成词；
  `NEEDAFFIX` 是一个"待满足"状态，被下一个词缀满足（但最后一个词缀若又给出
  `NEEDAFFIX` 则仍不成词）。`prefoopseudosuf` 这类词还要求搜索**施加顺序**，
  因为前缀可以先加、后加或夹在中间。
- 结果：`.wrong` 不只恢复，还从 570 涨到 **579**（`needaffix5` 3/3、
  `onlyincompound2/3`、`fogemorpheme` 之前各漏 1 个）。
- **教训**：增加"接受路径"必然增加误收；`.wrong` 必须每次重测，不能只看 `.good`。

**这次没做、也没假装做的**

- **德语复合词**（`germancompounding` 还剩 16、`germancompoundingold` 还剩 10）：
  需要 `COMPOUNDMIDDLE`、复合词内部的**带词缀部件**、`COMPOUNDPERMITFLAG`、
  `CHECKCOMPOUNDCASE`，以及德语"复合词里的名词自动小写化"这条从语料看不完全清楚的规则
  （`.aff` 里没有 `LANG de_DE`）。这是本轮最大的剩余缺口，但风险高（那两个套件共 100 个
  `.wrong`），决定不半成品上线。
- `COMPLEXPREFIXES`（`alias3` 差 1）、`ICONV`/`OCONV`（`iconv*`/`oconv*`）、
  `COMPOUNDWORDMAX`/`COMPOUNDSYLLABLE`（`hu` 差 7）、
  `CHECKCOMPOUNDPATTERN`（`opentaal_cpdpat*`、`checkcompoundpattern5`）。
- 建议生成 `suggest()`（`.sug` 语料）仍然整体在范围外。

**一个测量工具本身的缺陷（没有去改它）**

- `conformance/run.sh` 用 `paste -d' ' <(grep . good) <(verdicts)` 配对，
  于是**本身含空格的语料行会错位**。`morph.good` 有 16 行是 `drink eat` 这种。
- 库现在把这种行按"空白分隔的一组词，每个都对才算对"处理，16 行全部判对；
  但 harness 只能统计到 10/26（正好是 10 个单词）。
- 选择**不改 harness**：一改，本轮数字就和题目给的基线不可比了。
  这里只如实记录：`morph` 的可测上限是 10/26。

**AI 使用方式（本日）**
- 仍然是"AI 打字、编译器判定"：每改一处就 `moon check` + `moon test`，
  每个特性做完立刻跑整语料，用 `.wrong` 当"护栏"。
- 本轮所有数字都来自真实运行；凡是没做的一律在 README 的
  "Not implemented yet" 和本文件里点名，不含糊。

**本日新增的 MoonBit 坑（已补进 `docs/MOONBIT_GOTCHAS.md`）**
1. `pub struct` 的**私有字段类型也必须是 pub**，否则报 4046
   （`A public definition cannot depend on private type`）。`Dictionary` 是 `pub`，
   所以内部的 `SpellRule` 只能写成 `pub struct`（仍是不透明类型）。
2. 嵌套数组字面量 `[[x]]` 在这里推断不出类型，需要先绑定：
   `let applied : Array[Array[String]] = [rule.cont_flags]`。
3. `x.is_none()` 已废弃（warning 0020），写 `x is None`。
4. `(mask >> p) & 1 == 1` 又会踩 `&` 优先级低于 `==` 的老坑（第 23 条），
   必须 `((mask >> p) & 1) == 1`。

---

## 2026-09-22 · Day 3 — 建议引擎 `suggest()` 与 `.sug` 符合率

**做了什么**
- 新增 `src/suggest/` 包：`pub fn suggest(dict : @spell.Dictionary, word : String, limit : Int) -> Array[String]`。
- 为 `Dictionary` 增加只读访问器（建议引擎需要、判定引擎本来就有但没暴露的数据）：
  `try_chars`、`keyboard`、`word_chars`、`replacements`、`is_no_suggest`，
  并把 `TRY`/`KEY`/`REP`/`NOSUGGEST` 四个字段真正存进 `Dictionary`。
- `src/api` 增加 `suggest` 并用模块根 `pub using` 再导出。
- `cmd/main` 增加 `suggest` 子命令（逐行输出 `, ` 连接的建议，无建议输出空行）；
  `check` 子命令**一行未动**。
- 新增 `conformance/suggest.sh`（**加法式**，不碰 `run.sh` 的 `.good`/`.wrong` 计算）。
- 新增 15 个测试（9 个黑盒 + 6 个白盒）。

**建议引擎实际实现了什么（照 Hunspell 手册的算法）**
1. `REP` 替换：每处出现都替换，`^`/`$` 锚点、`_` 当空格，原文与全小写各跑一遍
   （`phorm→form`、`alot→a lot`、`Ijs→IJs`）。
2. 编辑距离 1：删除、相邻换位、替换、插入；替换/插入只在 `TRY` 字符集里做
   （没有 `TRY` 时退化为 a–z）。这一条是主要的成本控制。
3. 大小写变体：全小写、首字母大写、全大写；再加上**所有格词干**
   （`Unicef's→UNICEF's`）和 `CHECKSHARPS` 的 `ß→SS`（`MÜßIG→MÜSSIG`）。
4. 拆成两个词；`TRY` 或 `WORDCHARS` 含 `-` 时同时给出连字符形式
   （`rottenday→rotten day, rotten-day`）。
5. **有界**编辑距离 2：双删除、长换位、单字符移动、两个独立相邻换位。
   是 O(n²) 而不是 O(n²·|TRY|²)——手册点名的几种方法，不是完整距离 2。
6. 排序：`REP` 最前 → `KEY` 键盘相邻 → `TRY` 位置靠前 → 距离短 → 字典序兜底；
   全部去重，绝不返回输入词本身，候选必须被 `check` 接受且不是 `NOSUGGEST`。

**`.sug` 度量（真实跑出来的数字）**
- 语料 37 个 `.sug`，其中非空期望行共 **173** 行。
- `.sug` 的格式先读清楚了：它是 `hunspell -a` 输出里 `&` 开头的行的**后段**
  （按 `: ` 切掉 `& 原词 计数 偏移`），而且**只保留有建议的词**——没建议的词整行被
  `grep '^&'` 过滤掉了。所以 `.sug` 行号和 `.wrong` 行号**不能按位置一一对应**
  （`rep` 是 11 个错词只剩 8 行，`checksharps` 是 2 剩 1）。
- 因此不能用「第 i 行配第 i 个错词」。我采用的判据：把每个 `.sug` 行的
  **第一个（最佳）建议**，与「某个错词返回的建议列表」做**保序最大配对**
  （动态规划，每个期望行至多用一次、错词顺序递增）。命中 = 该建议出现在该词的建议里。
- **结果：108/173 = 62.4%**。
- 另外两个口径一并记录（README 里也写了）：
  严格「我们的第一条就是期望的第一条」= **93/173 = 53.8%**；
  完整复现整个 `.sug` 文件（Hunspell 自己的判据）= **5/37 套**。
- 没通过的 65 行里，21 行是 `PHONE`/`ph:` 音似表（`ph`/`ph2`/`phone`）、
  6 行 `MAP` 重音、3 行 `OCONV`、2 行 `FORCEUCASE` 驱动的建议，
  其余是 ngram/`MAXNGRAMSUGS` 与两处以上的任意编辑。这些本轮**明确不做**，README 已点名。

**没有回归（每次改动都重跑）**
```
moon check                                  → 0 errors, 0 warnings
moon test --target all                      → 118/118 通过（wasm / wasm-gc / js / native）
bash conformance/run.sh                     → .good 718/848 (84.7%)  .wrong 579/613 (94.5%)
bash conformance/suggest.sh                 → .sug 最佳建议 108/173 (62.4%)
```
`.good`/`.wrong` 与任务给的基线**逐位相同**。判定逻辑一行没改，`suggest` 只加只读访问器。

**性能（自己构造的大词典实测，不是拍脑袋）**
- 20k 词、26 后缀 + 12 前缀全 cross-product（312 个组合）、`TRY` 26 个字母：
  1000 个错词 **7.4s**（含 `moon run` 启动）。
- 同一份词典单跑 `check` 1000 词约 0.08s。也就是说建议是判定的 ~100 倍开销，
  这是"每个候选都真的跑一次 `check`"的必然结果。
- 极端构造（100 前缀 × 100 后缀全 cross = 10000 组合）下会到 ~150ms/词——
  此时瓶颈是 `check` 的 cross-product 反查，不是距离 2。距离 2 只占候选数的约 1/4，
  去掉也救不了这种词典，所以保留但限制长度（≤20）。
- 长词保护：`> 32` 字符不做距离 1，`> 20` 字符不做距离 2；
  `timelimit` 套件的 70+ 字符词 0.4s 内返回且不挂。**语料测量里没有超时。**

**一个测量脚本自己的坑（值得记）**
- bash 的 `$(...)` 会**吃掉结尾的所有空行**。建议输出的"无建议"是空行，
  如果空行在末尾就会被吞掉，导致探针以为 CLI 坏了。
- 修法：探针故意把"有建议的词"放在最后一行（`phorm / zzzz / helo`），
  这样中间的空行不会被吞。
- `.sug` 的编码也不能想当然：`1463589.aff` 没有 `SET`（默认 Latin-1），
  但 `.sug`/`.wrong` 其实是 UTF-8。脚本按 CLI 的 `decode_words` 规则解码
  （有效 UTF-8 优先，否则用字典编码），否则会拿乱码去比对。

**本日新增的 MoonBit 坑（已补进 `docs/MOONBIT_GOTCHAS.md`）**
1. `moon.pkg` 里 `for "test"` 的 import 块**只能有一块**，写两块会直接
   `Duplicate key 'test-import'` 整个构建计划失败（第 10 条的延伸）。
2. `Array::sort_by` 的比较器返回 `Int`（负数在前）且**不稳定**；要确定性必须自己
   用字典序兜底。`String` 实现了 `Compare`，`a.compare(b)` 可直接用。
3. 顶层 `const` 合法；`let (x, y) = match x { ... }` 这种同名 shadowing 也合法
   ——这两条是"以为不行其实行"的正向记录。

**AI 使用方式（本日）**
- 仍然是"AI 打字、编译器判定 + 语料判定"。先读语料和手册确定算法，再写代码，
  每加一个特性就 `moon check` + `moon test` + 重跑 `.sug`，最后重跑 `.good`/`.wrong` 护栏。
- 排序口径、距离 2 的口径、`.sug` 的判据都写进了 README，避免读者高估数字。

---

## 2026-09-22 · Day 5 — 跨后端缺陷修复：`--words -` 在 native 上读不了管道

**问题（真实缺陷，不是重构）**
- 契约里 `--words -` 从 stdin 逐行读词，`conformance/run.sh` 也依赖它。
- 实现却把 `"/dev/stdin"` 交给 `@fs.read_file_to_bytes`，而它是**先 seek 到末尾拿长度**
  再分配缓冲区。fd 0 是普通文件（`< file`）时可 seek，是**管道**时不可 seek：
  `printf 'hello\nzzzz\n' | main.exe check ... --words -` →
  `spell: cannot read "/dev/stdin": Illegal seek`，rc=1。
- 后端差异是这条缺陷最坑的地方：`moon run`（wasm + moonrun）把 `/dev/stdin` 当预打开
  文件处理，读管道正常。**同一段命令在本地（wasm）通过、在 native 发布版炸。**

**怎么修的（先说结论：不是"报错引导"，是真的把管道读通了）**
- 先查过现成的流式 API：`.mooncakes/moonbitlang/x/fs` 0.5.5 的 `.mbti` 里只有
  `read_file_to_bytes` / `read_file_to_string`，**没有** reader/stream 接口；
  `moonbitlang/x/sys` 和 core 也没有 stdin 读取。所以流式读取得自己做。
- native/llvm 新增 `cmd/main/stdin_native.c`（`moon.pkg` 的 `native-stub`），用
  `fread` 每次读 64 KiB，读到 EOF；MoonBit 侧 `read_all_chunks` 把块累积进
  `Buffer`，再交给原来的 `decode_words`。**全程不需要知道输入长度**，因此管道可用。
  返回 `-1` 时用 `strerror(errno)` 给出可操作报错（点名 native + 建议
  `--words <file>` 或 `< file`）——但这只在真正的 I/O 错误时才可能触发。
- `--words -` 与 `--words <file>` 的分派收进 `read_words_bytes`，`check` 和
  `suggest` 共用；错误仍打印到 stderr、stdout 保持为空、退出码 1。
- **wasm / wasm-gc / js 的读取代码一行没动**：它们的 host 本来就能读管道
  （js 的 `fs.readFileSync` 自己处理不可 seek 的 fd）。如实说：这次修复对这三个后端的
  读取路径**没有改变**。
- 但 js 上还有另一个跨后端差异导致 CLI **根本跑不起来**：Node 的 `process.argv`
  以解释器路径开头，`moon run --target js cmd/main -- check ...` 里 `args[1]` 是
  **脚本路径**而不是子命令。加了 `command_args()`（`#cfg(target="js")`，只丢掉解释器
  那一项，脚本路径占住"程序名"位），四个后端的命令行布局才一致。否则 js 的管道测试
  连读取代码都到不了。

**验证（全部自己跑出来的，不是推断）**
```
# 原生二进制 + 管道：修复前 Illegal seek，修复后
$ printf 'hello\nzzzz\n' | _build/native/release/build/cmd/main/main.exe check \
      --aff /tmp/p.aff --dic /tmp/p.dic --words -
1
0            # rc=0
```
- 四后端（native / wasm / wasm-gc / js）都实测了 `printf | ... --words -`、`< file`、
  `--words <file>`、空 stdin（无输出 rc=0）、无结尾换行（仍有 1 条判定）、
  `suggest` 管道、坏 `.dic`（非 0 退出、stdout 为空、stderr 有信息）。
- 大输入：`cat /usr/share/dict/words | ... --words -`（235976 行）四后端
  输出行数与输入行数**逐位相同**，rc=0。大输入会跨很多个 64 KiB 块，正好覆盖分块循环。
- 新增 `conformance/pipe.sh` 把上面这些固化成回归检查（默认 native；`--all` 连
  wasm/wasm-gc/js 一起测）。`moon test` 里造不出管道，所以这条端到端护栏放在脚本里。

**没有回归（改动后重跑）**
```
moon check --deny-warn --target all         → 0 errors, 0 warnings
moon test --target all                      → wasm/wasm-gc/js 118/118, native 122/122
bash conformance/run.sh                     → .good 718/848 (84.7%)  .wrong 579/613 (94.5%)
bash conformance/suggest.sh                 → 108/173 (62.4%), 93/173 (53.8%), 5/37
bash conformance/pipe.sh --all              → 全部 ok
```
`.good`/`.wrong`/`.sug` 与修复前基线**逐位相同**。新增的 4 个单测（`read_all_chunks`
的分块拼接、空输入、无结尾换行、错误传播）只存在于 native/llvm，因为被测函数本身
按 `#cfg` 只在 native/llvm 编译；wasm/wasm-gc/js 的测试数仍是 118。

**踩的坑（已补进 `docs/MOONBIT_GOTCHAS.md` #33）**
1. **任何"先测长度再读"的 API 都不能用于 pipe/stdin**。`/dev/stdin → /dev/fd/0`，
   fd 0 是管道时不可 seek。跨后端行为还不一致，最容易"本地过、发布炸"。
2. `Bytes::to_string()` 不是 UTF-8 解码，而是带 `b"..."`、`\x0a` 转义的调试表示；
   要拿到文本得用 `@unicode.to_utf8_string`。第一版新增测试就因此挂了 2 个，
   被 `moon test` 抓出来。
3. 未使用的**私有顶层函数**在 `--deny-warn` 下是 error（`unused_value`），
   即使 whitebox 测试引用了它也一样；所以按后端 `#cfg` 出的辅助函数必须同时
   `#cfg` 掉它的测试，否则另一个后端的检查会红。

**AI 使用方式（本日）**
- 先让 AI 去读**实际的 `.mbti` 接口文件**确认"有没有现成的流式 API"，而不是凭印象
  编一个 API 名——结果是确实没有，才决定自己写 `native-stub`。
- 让 AI 先写出会失败的回归测试（分块循环的单测 + `pipe.sh`），再改实现；两个真 bug
  （`Bytes::to_string` 表示、`unused_value` 警告）都是"编译器/测试判定"抓出来的，
  不是靠读代码看出来的。
- 性能与符合率数字一律用脚本重跑，不在日志里估算。

---

## 待续
