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

## 2026-09-27 · Day 6 — `ICONV`/`OCONV`：一个有真实影响的缺口

**背景**：离 9/30 验收只剩 3 天。这一轮原计划做 `ICONV`/`OCONV` → `COMPLEXPREFIXES` →
`COMPOUNDMIDDLE`，但只完成了第一项就停了下来，所以这里如实记录**完成了一项**。

**做了什么**
- `src/spell/conversion.mbt`（新）：`ICONV`/`OCONV` 转换表。
- `src/aff/`：解析 `ICONV n` / `OCONV n` 头行 + 声明条数的转换对；
  `from` 的尾随 `_` 是 Hunspell 的"词尾标记"，语义按手册实现并写进类型注释。
- `src/spell/dictionary.mbt`：存取 `iconv`/`oconv`，导出 `Dictionary::apply_oconv`。
- `src/spell/lookup.mbt`：**先应用 `ICONV`、再做 `IGNORE` 过滤** —— 顺序很关键。
- `src/suggest/suggest.mbt`：输出经 `OCONV` 转换。

**为什么这一项优先级最高**：它不是"刷测试套件"，而是**真实词典就需要它**。
真实的 LibreOffice `en_US.aff` 里有：
```
ICONV 1
ICONV ’ '
```
也就是把弯撇号 `’`（U+2019）归一化成直撇号 `'` 再查词。

**实测验证（真实词典）**：
```
don't → 1     don’t → 1        ← 两者都接受
can't → 1     can’t → 1
```
`don't` / `can't` 确实在 `en_US.dic` 里（各 1 条），所以**修复前用弯撇号的写法会被误判为拼写错误**——
这是本轮修掉的一个真实用户可见缺陷，不是测试套件里的数字游戏。

**符合率增量**（脚本实测）：

| 指标 | 本轮前 | 本轮后 |
|---|---|---|
| `.good` | 718/848 = 84.7% | **730/848 = 86.1%** |
| `.wrong` | 579/613 = 94.5% | **579/613 = 94.5%**（不变） |

净增 12 个词，`.wrong` 无回归。

**仍未做**（时间所限，README 已列明）：`COMPLEXPREFIXES`、`COMPOUNDMIDDLE` /
`CHECKCOMPOUNDPATTERN`、德语复合词（规则无法从语料 `.aff` 推导，缺 `LANG de_DE`）。

**AI 使用方式（本日）**
- 转换顺序（`ICONV` 先于 `IGNORE`）不是拍脑袋定的，是让实现方去核对语料里
  `iconv*` / `ignore*` 两个 suite 的相对行为后确定的。
- 收尾时我独立重跑了符合率（而不是采信汇报），并额外用**真实词典 + 弯撇号**做了
  端到端验证——因为"符合率涨了 12 个词"不足以说明这个功能在真实场景下有用。

---

## 2026-09-27 · Day 7 — `MAP` / `ph:` / `PHONE`：把 `.sug` 从 62.4% 推到 76.9%

**背景**：Day 6 结束时 `.sug` 只命中 108/173。上一轮把 65 个未命中的期望行归因到几个
「被刻意跳过的 pass」：`PHONE`/`ph:`（21）、`MAP`（6）、`OCONV`（3，Day 6 已实现）、
`FORCEUCASE`（2），其余归 ngram / distance-2。本轮做前两项。

**做了什么**

1. **`MAP`（先做，规格最小）**
   - `src/aff/`：解析 `MAP n` + 表体，`AffFile::map_groups` 原样保存。
   - `src/suggest/suggest.mbt`：把每个 group 拆成「单字符 / 括号多字符串」两种 alternative
     （`ß(ss)` → `ß` 与 `ss`），然后**递归**地在同一单词的多个位置做替换——
     手册明确说 MAP 是解决「一个词里多次选错相关字母」的，只换一处不够。
   - 递归有 `MAX_MAP_CANDIDATES = 2048` 的预算，异常表不会把引擎拖死。

2. **`ph:` 字典字段 = 手册说的 “inner REP table”**
   - `src/dic/`：新增 `DicEntry::full_word` / `full_flags`。`.dic` 的 morph 字段从**第一个
     含 `:` 的 token** 开始，之前的 token 合成一个词——所以 `a lot ph:alot` 是一个带空格的词，
     `forbidden root/A` 的 flag `A` 属于整个词而不是首字段。`word`（首字段）保持不变，
     因为判定引擎依赖它（`wordpair` 那条 `compound word`）。
   - `src/spell/suggest_rules.mbt`：把每个 `ph:` 值变成 REP 规则，支持手册的三种写法：
     普通 `ph:wich`、尾部 `*`（**pattern 和词都要去掉最后一字符**，`prity*` → `prit`→`prett`）、
     箭头 `ph:hepi->happi`；并额外生成首字母大写与全大写两份，后者让 `OMG` 得到 `OH, MY GOSH!`。
   - 词对也要能被 `check` 接受，所以整词拼写会作为额外的词典条目登记（flag 取最后一个
     词 token 的），否则 `a lot` 这类建议会被 `push_candidate` 的 `check` 过滤掉。

3. **`PHONE` 音码表**
   - 语义来自 **Aspell 的 “Phonetic Code” 章节**（`hunspell(5)` 指向它）与本地
     `hunspell(5)` man page：规则按表序、首个匹配者胜；`(class)` 匹配其一；前导 `-` 表示
     「整段匹配、只替换前段、保留尾部并重新扫描」；`<` 表示「替换后从替换串继续扫描」；
     数字是优先级；`^`/`$` 是词首/词尾锚点；`_` 表示输出空串；无法匹配的字符直接丢弃；
     全大写后转写。
   - 装载时对全部 49,568 个 `en_US` 词条建一次音码索引；`.dic` 带 `ph:` 字段的条目用
     该字段作为音码（`xxxxxxxxxx ph:Brasilia` 与 `Brasilia` 同音）。
   - 建议按输入的大小写打扮（`kt`→`cat`、`Kt`→`Cat`、`KT`→`CAT`），并且**排在所有
     字符类建议之后**，不会顶掉原来的首选。

**逐项实测（`HUNSPELL_DIR=/tmp/hunspell_dl/hunspell-master`）**

| 指标 | 基线 | MAP 后 | `ph:` 后 | `PHONE` 后 |
|---|---|---|---|---|
| `.sug` best | 108/173 = 62.4% | 114/173 | 133/173 = 76.9% | **133/173 = 76.9%** |
| `.sug` as-first | 93/173 = 53.8% | 99/173 | 118/173 = 68.2% | **118/173 = 68.2%** |
| `.sug` exact suites | 5/37 | 7/37 | 7/37 | **7/37** |
| `map` / `maputf` | 0/3 / 0/3 | 3/3 / 3/3 | 3/3 / 3/3 | 3/3 / 3/3 |
| `ph` | 3/11 | 3/11 | 11/11 | 11/11 |
| `ph2` | 1/14 | 1/14 | 12/14 | 12/14 |
| `.good` | 730/848 | 730/848 | 730/848 | 730/848 |
| `.wrong` | 579/613 | 579/613 | 579/613 | 579/613 |

- `PHONE` 本身对语料分数是 **0 增量**：唯一带 `PHONE` 表的 `phone` suite 本来就 1/1（它期望
  的第一条 `Brasilia` 由字符距离就能得到）。它的价值是语义完整（`Brasilian` → `Brazilian`
  现在来自音码匹配）与可测的成本，而不是分数。诚实记录这一点。
- `ph2` 的 14 行里只有 12 行可能拿到：`stembazstem` 需要**三段复合词**，
  `forbiddenroot` 被我们更宽松的 `check` 直接判为正确（于是 `suggest` 提前返回空）。
  这两条不是建议 pass 的问题，是判定引擎的已知缺口。

**真实 en_US 成本（native release，`_build/native/release/build/cmd/main/main.exe`）**

| 词典 | 装载 | 90 个常见错拼的建议 | 每建议 |
|---|---|---|---|
| 真实 `en_US.aff`（无 `PHONE`/`MAP`） | 61.0 ms | 1436 ms | ~15.3 ms |
| 同上 + `phone.aff` 的 105 条 `PHONE` | 127.1 ms | 1522 ms | ~15.5 ms |
| 同上 + 一张 `MAP` 表 | 62.1 ms | 1439 ms | ~15.3 ms |

- 结论：**真实 `en_US` 不含 `PHONE`/`MAP`，因此装载与每条建议的成本都是 0 增量**。
  强行加上 105 条 `PHONE` 时，装载 +66 ms（≈1.3 µs/词条），每条建议 +0.2 ms（约 1%），
  可以接受；`MAP` 的开销在噪声内（~0.02 ms/条）。
- 由于音码索引是装载时一次性建的，`suggest` 每条只多算一次 key + 一次哈希查找。

**仍未做**：`MAXNGRAMSUGS` / ngram 相似度没有实现（任务把它列为「有余力再做」）。
剩下的 40 个未命中里，`forceucase`(2)、`i54633`(2)、`1463589*`(8)、`opentaal_keepcase`(7)
很可能主要靠 ngram 与距离 2 的扩展。本轮选择把余下时间放在测试、成本实测与文档上，
没有硬塞一个半成品 ngram。

**AI 使用方式（本日）**
- `PHONE` 的语义不是从 Hunspell 源码抄的（LGPL，章程禁止）。证据链是：本地
  `hunspell(5)` man page 只写「算法借自 Aspell，详见 Aspell 手册」→ 去读 Debian 上
  Aspell 0.60.8 的 “Phonetic Code” 章节（文档，非代码）→ 用自己写的
  `kaatt`/`cat` 与大小写三个用例把「丢字符 / `-` / `<` / 优先级 / 大小写打扮」逐条钉住。
- 每个 pass 做完立刻重跑**三个 `.sug` 数字 + `.good`/`.wrong`**，不做完两项就一起测，
  否则无法归因。
- `*` 形式的 `ph:` 一开始只去掉了词尾、忘了 pattern 的尾字符，是自写的
  `prity → pretty` 用例抓出来的——再次说明只有跑出来的结果算数。

---

## 2026-09-27 · Day 8 — 收口 `.good`：复合词引擎 + `COMPLEXPREFIXES` + 德语

**背景**：Day 7 结束时 `.good` **730/848 = 86.1%**，`.wrong` 579/613，
`.sug` 133/173。README 的「Not implemented yet」几乎整段是复合词：`COMPOUNDMIDDLE`、
`CHECKCOMPOUNDPATTERN`、复合词内部的词缀、德语 `germancompounding*`（26 词）、
`COMPLEXPREFIXES`、匈牙利 `COMPOUNDSYLLABLE`。本轮逐个关掉。

**逐项实测（`HUNSPELL_DIR=/tmp/hunspell_dl/hunspell-master`，每项后重跑三个数字）**

| 步骤 | `.good` | `.wrong` | `.sug` best |
|---|---|---|---|
| 基线 | 730/848 = 86.1% | 579/613 = 94.5% | 133/173 = 76.9% |
| ① `COMPLEXPREFIXES` | 734/848 | 579/613 | — |
| ② 复合词引擎（n 段 + 词缀部件 + permit/forbid/forceucase） | 777/848 | **591/613** | 140/173 |
| ③ `CHECKCOMPOUNDPATTERN` / dup / triple / case / rep / 词对 / FORBIDDENWORD 派生 | 778/848 | **600/613** | — |
| ④ 德语 + `CIRCUMFIX` | **802/848** | 603/613 | 140/173 |
| ⑤ 小项（前导 `/`、阿拉伯数字、混合大小写、`FORBIDDENWORD` 同形词） | 818/848 | 608/613 | 141/173 |
| ⑥ `LANG tr` 土耳其大小写 + `base_utf` | **825/848 = 97.3%** | **611/613 = 99.7%** | **141/173 = 81.5%** |

每一步都先跑 `.good` 和 `.wrong` 再进下一步；`.sug` 只会因为判定引擎变严而上升
（`ph2` 从 12/14 升到 14/14），从未下降。

**① `COMPLEXPREFIXES`（+4 词，零回归）**

手册：「twofold prefix stripping (but single suffix stripping)」。实现成
`derives_two_prefixes`：内层前缀的 continuation class 给外层前缀发 flag
（`PFX B 0 met/A` → `metouro` 带 `A` → `PFX A 0 tek` → `tekmetouro`），
同时**关掉双后缀路径**。`.aff` 里 `COMPLEXPREFIXES` 只出现在 `complexprefixes*` /
`alias3` 四个套件，它们不需要双后缀，所以「关掉」没有代价。

**② 复合词引擎：从「两段 + 纯词条」改成递归分割**

旧实现只切一刀、只认纯词条。新实现把整词递归切成 n 段，每段按位置要 flag：

- 首段要 `COMPOUNDFLAG` 或 `COMPOUNDBEGIN`，中间段要 `COMPOUNDMIDDLE`，末段要
  `COMPOUNDEND`；`COMPOUNDMIN`（默认 3）限制每段长度。
- **每段本身可以是词缀派生形**：compound flag 可以来自词干，也可以来自词缀的
  continuation class；`COMPOUNDPERMITFLAG` 决定词缀能否出现在「词内部」
  （前缀不在最前、后缀不在最后就需要它）；`COMPOUNDFORBIDFLAG` 让派生形完全退出复合；
  suffix 的 continuation class 带 `ONLYINCOMPOUND` 时是 Fuge-element，后面必须还有一段。
- 非末段的后缀、非首段的前缀属于「内部」，需要 permit；首段前缀、末段后缀不需要。
  这三条是从语料 `compoundaffix{,2,3}` 的 good/wrong 差分出来的，又用本地
  `hunspell 1.7.3` 写了 20 多个探针字典逐条确认（`h1`–`h6`、`d1`–`d7`、`w1`–`w6`）。

**③ 禁止规则和允许规则一起加**：只加允许一定会掉 `.wrong`。本轮同时做：

- `CHECKCOMPOUNDPATTERN endchars[/flag] beginchars[/flag] [replacement]`：边界文本 +
  可选 flag（flag 可以来自词干、词缀规则自身或 continuation class——`checkcompoundpattern5/6/7`
  专门考这三个来源）+ 手册的 `0`（只限未加词缀的词干）+ 可选 replacement（简化形，
  如 `foo`+`bar` → `fozar`/`fur`）。
- `CHECKCOMPOUNDDUP`：**最后两段不能相同**（探针证明 `foofoobar` 合法而 `foobarbar` 非法，
  所以不是「任意相邻重复」）。
- `CHECKCOMPOUNDTRIPLE` / `SIMPLIFIEDTRIPLE`（含 `gh151` 里 SIMPLIFIEDTRIPLE 单独使用、
  借「补回一个字母」放宽 COMPOUNDMIN 的用法）。
- `CHECKCOMPOUNDCASE`：边界两侧任一侧是大写就禁止。
- `CHECKCOMPOUNDREP`：用 `REP`（含 `ph:` 派生规则）替换后得到词典词就禁止。
- `.dic` 词对（`compound word`）禁掉无空格复合（`wordpair`、`ph2`）。
- `FORBIDDENWORD`：词干的派生形同样被禁（`foowordbars`），且**同形词里只要有一个是正常词根
  就仍然合法**（手册「excepts with root homonyms」，`foo/S` + `foo/YX` → `foo` 正确）。

这一阶段 `.wrong` 从 579 涨到 600，`.good` 从 734 涨到 778。

**④ 德语：手册里真的有规则，不是猜的（+26 词）**

上一轮放弃德语的结论（「没有 `LANG de_DE`、没有 decapitalisation rule，无法从语料推导」）
**是错的**。`hunspell(5)` 的 “Compounds” 一节直接给了德语方案：

```
LANG de_DE            # 只用于 sharp s
COMPOUNDBEGIN U / COMPOUNDMIDDLE V / COMPOUNDEND W
COMPOUNDPERMITFLAG P
ONLYINCOMPOUND X
CHECKCOMPOUNDCASE
# decapitalizing prefix / circumfix for positioning in compounds
PFX D Y 29
PFX D A a/PX A
...
```

`germancompounding.aff` 里逐字就是这些（没有 `LANG de_DE`，但 `LANG` 只影响 ß，
而 `CHECKSHARPS` 已经实现）。规则本身是普通的词缀机器：`Arbeit/A-` 没有 `D`，
但 `SFX A 0 0/WXD`（零后缀）把 `D` 放进 continuation class，于是
`PFX D A a/PX` 能作用，得到小写 `arbeit`，并**继承内层后缀的 `W`（末段 flag）**。
我们只需要两处修正：cross product 的 flag 可以来自对侧词缀的 continuation class
（照 `derives_cross` 的 `suffix_first || prefix_first`），以及 Fuge 限制只看「最后应用的
那个后缀」——有前缀时前缀可以是最外层，所以不再强制「后面必须还有一段」。

`CIRCUMFIX` 也是这一步补的：德语旧正字法用 `CIRCUMFIX Y` 让
`SFX A 0 s/VPXDY` 必须和 `PFX D .../PXY` 成对出现，于是
`ComputerArbeitscomputer`（大写 `Arbeits` 单独派生）被拒，
`Computerarbeitscomputer`（成对派生）通过。CIRCUMFIX 对**独立词**也生效：
去掉 `SFX C 0 n .` 后 `Computern` 立刻变错（探针 `old3`）。

`germancompounding` 20/20、`germancompoundingold` 14/14、两边 `.wrong` 各 50/50。

**⑤ 小项（每项都先确认语料里真的值钱）**

- `FULLSTRIP`：**不需要代码**——`apply_rule` 本来就允许 strip 整个词干；`fullstrip`
  套件本来就 8/8。`PSEUDOROOT` 就是 `NEEDAFFIX` 的旧名（手册明说 deprecated），
  直接做别名。
- `.dic` 前导 `/`：`/AB` 是词、`/foo/AB` 是 `/foo` + flag `AB`、字节 `/` 是词 `/`。
  改 `split_word_flags` 跳过首个字符位置的 `/`（`gh1122` +4、`slash` +1）。
- 非 ASCII 数字：`gh353` 用 `WORDCHARS` 列了阿拉伯-印度数字，`is_digit_char` 补上
  U+0660–U+0669 / U+06F0–U+06F9（+3）。
- 混合大小写词首字母大写：`ULinda` 找 `uLinda`（`gh106` +2）。
- `forbiddenword`：同形词语义修正（+1 good，+3 wrong）。
- `LANG tr`：`İ`/`ı` 的土耳其大小写（`dotless_i` +5 good +2 wrong，`base_utf` +2 good +2 wrong）。
  非土耳其语下 `İZMİR` → `İzmir`（保留首字符、其余走 Unicode 小写）；但
  `İmply` 必须仍然错，所以非土耳其 `fold_lower` 不做 `İ→i` 映射。这个「保留首字符」
  同时修好了 `base_utf` 的 `İZMİR`。

**⑥ 顺带修的两个真 bug**

1. **词缀 condition 可以省略**：`gh1002.aff` 的 `SFX A us órum` 只有 3 个字段，
   旧解析器直接抛 `missing argument` 导致整个套件加载失败（harness 静默记 0）。
   现在缺省为 `.`。
2. **测试里两条旧断言是错的**：`spell_test.mbt` 断言「三段复合词必须 false」和
   「`FORBIDDENWORD` 同形词禁掉整词」——两条都与语料矛盾，已改成正确语义并各加一个反例。

**仍未做（诚实记录，README 已点名）**：ALL-CAPS 输入匹配混合大小写词条
（`allcaps*` 7 词，手册没有文档化这个大小写算法，不猜）；匈牙利 `LANG hu` 的 moving rule
（`hu` 1 词，手册只提名不定义）；`limit-multiple-compounding` 的三段复合词 typo 检查
（1 词，无指令、手册未描述）。`morph` 的 16 词是 harness 对含空格 `.good` 行的度量错位，
不是库的问题。

**AI 使用方式（本日）**
- 德语规则的证据链：先读 `man 5 hunspell` 的 “Compounds” 一节（文档）→ 发现
  `germancompounding.aff` 就是手册示例 → 用本地 `hunspell 1.7.3` 复制语料字典到 `/tmp`
  做**行为探针**（删掉 `SFX A 0 0/WXD`、删掉 `PFX D`、给 `Arbeit` 直接加 `D`、替换成
  `SFX A 0 s/WXD`），逐条确认「零后缀发 `D` → 前缀作用 → 继承 `W`」这条链。
  **没有读 Hunspell 源码**（LGPL），只看手册 + 可观察行为。
- 所有新测试数据自己写；文档/语料只用于跑，不 vendor、不复制。
- 本地 `hunspell 1.7.3` 与 master 语料并非处处一致（17 个套件有分歧，
  `checkcompoundpattern5/6/7` 差分最明显），所以探针只用来确认**语义机制**，
  最终判据始终是语料 `.good`/`.wrong`。

---

## 2026-09-27 · Day 9 — 生态相关性：公开 API 文档 + `doccheck` 吃自己的狗粮

**背景**
- 评审四个维度里，「与 MoonBit 生态的相关性」此前从未被专门做过。前三个维度
  （完整性、代码质量、开源合规）已有大量投入，这一条是明显短板。
- 本日只做这一条：把「一个纯 MoonBit 的、数据驱动的文本库」真正接进 MoonBit
  生态的使用方式（`moon doc`、mooncakes 包页、可运行示例、dogfooding），并留下
  可复现的实测数字。

**做了什么**

1. **公开 API 文档审计**。用脚本枚举所有 `pub` 声明与 `pub(all)` 结构体/枚举字段，
   逐个检查是否有 `///` 文档。结论：函数、类型、方法此前已经写得相当完整（例如
   `parse_aff`/`parse_dic`/`apply_rule`/`matches_condition`/`Dictionary::from_text`
   都有「做什么 + 行为/错误」两段）。真正的缺口只有：
   - `src/aff/ast.mbt` 里 `AffFile`、`SpecialFlags`、`Replacement`、`PhoneRule`、
     `Conversion`、`AffixKind` 的公开字段没有逐字段说明；
   - `src/dic/ast.mbt` 的 `DicFile.declared_count`；
   - 三处 `pub impl Show` 没有文档；
   - 门面 `suggest` 没有可编译示例。
   逐条补齐后重新跑审计脚本，**剩余缺口 0**。`moon doc` 生成的 HTML 里能搜到新
   文档（例如 “The count on the first line”），说明渲染正确。

2. **`examples/doccheck`：让本库给 MoonBit 项目的文档和注释查错**。
   - MoonBit 可执行包，只依赖 `Careylq/spell` + `moonbitlang/x/fs` 等；
     判定全部走 `@spell.check`，不调用任何外部拼写器。
   - 抽取规则（源码头部与 `examples/README.md` 都写了）：只读 `*.md` / `*.mbt.md`
     与 `*.mbt` 的 `///`、`//` 行；Markdown 里跳过围栏代码块、行内代码、HTML 注释、
     链接目标与含 `/` 的路径/URL；`///` 里的围栏代码块也跳过（否则 `mbt check`
     示例会被当成散文）；候选词必须是纯 ASCII 字母串，紧邻数字/`.`/`_` 的串、
     全大写串、非 ASCII 串一律丢弃；所有格归并到词根，其他含撇号的词跳过；
     小于 3 个字母的词跳过。
   - 允许表 `allowlist.txt`：把词条原样和全小写插进 `.dic` 文本再 `load`，
     所以「这个词算不算对」仍然是库在判定，而不是在库外面绕过。
   - 一条命令：`bash examples/doccheck/run.sh`（脚本在运行时从 jsDelivr 取
     LibreOffice 的 en_US，缓存到临时目录，**不 vendor**）。

3. **在本仓库上实测（真实运行，非估算）**

   | 运行 | 文件 | 检查词数 | 判错 token | 去重词数 |
   |---|---|---|---|---|
   | 首次，无允许表 | 32 | 16,602 | 461 | 110 |
   | 加 `allowlist.txt`（101 条） | 32 | 16,602 | **0** | **0** |
   | `--include-tests`（带允许表） | 46 | 18,042 | 14 | 11 |

   **110 个去重词逐个人工复核：真拼写错误 0 个，假阳性 110 个。** 分类是：项目术语
   （`wasm`、`stdin`、`backend`、`aff`、`dic`）、Hunspell 术语（`Fuge`、`endchars`、
   `circumfix`、`ngram`）、专有名词（`MoonBit`、`macOS`、`jsDelivr`、`WordNet`、
   `aspell`、`nuspell`）、英式拼写（`judgement`、`licence`、`behaviour`、`modelled`）、
   以及 SCOWL size 60 恰好没有的普通词（`seekable`、`runnable`、`matcher`、
   `lookups`、`substring`、`unclosed`）。它们全部进了允许表。
   `--include-tests` 剩下的 11 个是测试注释里故意的错拼与后缀片段
   （`abc`、`aeiou`、`krom`、`sxzh`、`-ication`……）——这正是默认不扫测试文件的原因。

   **诚实结论**：通用英语词典在技术仓库上首次运行几乎 100% 是假阳性，
   允许表不是「锦上添花」，而是让工具可用的必需机制。这也顺带证明了不能靠
   「首次运行是否干净」来判断这类工具的价值。真拼写错误是 0，是实测结果，
   不是为了好看而写的 0。

**新增的坑（编译器和运行时验证）**
- `String::substring` 已废弃（warning 0020），`--deny-warn` 下直接失败；改用切片
  `s[start:end]` / `s[start:]`（返回 `StringView`，要 `String` 就 `.to_owned()`）
  或 `strip_prefix`。已补进 `docs/MOONBIT_GOTCHAS.md` 第 41 条。
- 写这个示例时真的踩出一个抽取 bug：`drop_slash_tokens` 复用 `StringBuilder` 却没重置，
  导致相邻单词被拼成一个词（`theconditionisread`）。编译器不会报，只有跑输出才能
  看出来——再次印证「能编译 ≠ 正确」。

**测试与验证**
- `examples/doccheck` 新增 9 个白盒测试（抽取规则、围栏、允许表合并、路径过滤）。
- `moon check --deny-warn --target all` 干净；`moon fmt` / `moon info` 已跑。
- 符合率未回归：`.good` 825/848、`.wrong` 611/613、`.sug` 141/173（重测命令见
  README 的 Conformance 一节）。

**仍然没做 / 局限**
- 抽取器很薄，已知假阳性与假阴性都写在 `examples/README.md`：未闭合反引号会漏文本、
  多行字符串里的 `//` 会被当注释、连字符词按两个词查、拼写正确但用错的词一律查不出。
- `--include-tests` 会报出测试夹具，故意不把它们加进允许表。

---

## 2026-09-27 · Day 10 — ngram 通道：把手册读完，然后诚实地不做

**做了什么**
- 复核 `hunspell(5)` 手册里 ngram 相关的**全部**内容（Ubuntu 1.7.0 / 1.7.2、
  Arch 1.7.3、语料自带的 `man/hunspell.5`，以及它的匈牙利语译本
  `man/hu/hunspell.5`）。它只写了四件事：
  * 建议参数一节：ngram 是「基于公共 1/2/3/4 字符序列的词典相似度检索」；
  * `MAXNGRAMSUGS num`：最多几条 ngram 建议，`0` 关闭；
  * `MAXDIFF [0-10]`：相似度因子，默认 `5`，`0` = 更少但至少 1 条，
    `10` = `MAXNGRAMSUGS`；
  * `ONLYMAXDIFF`：去掉所有「差的」ngram 建议（默认保留一条）。
- 唯一的额外信息来自匈牙利语译本：它给 `MAXNGRAMSUGS` 标了一个默认值 `5`
  （英文原文没写默认值），并说建议是按「n 长片段匹配」**加权**的——但仍然没有权重、
  没有公式、没有阈值。连默认值都只出现在译本里，说明不能靠手册复刻评分。
- 因此**没有实现 ngram 评分**：手册没有写各阶 n-gram 的权重、归一化、`MAXDIFF`
  对应的阈值、`MAXNGRAMSUGS` 的默认值，也没有定义什么叫「差」。这些只存在于
  Hunspell 的 LGPL-2.1 `suggestmgr.cxx`，本项目不能复制，评分函数不能猜。
- 实现了手册里**说得清楚**的那一半：解析 `MAXNGRAMSUGS` / `MAXDIFF` /
  `ONLYMAXDIFF` 进 AST（`AffFile::max_ngram_sugs` / `max_diff` / `only_max_diff`），
  它们不再落进 `unrecognized`。缺失用 `Int?` 表示，所以「文件没写」与「写了 0
  （关闭）」可以区分——这正是 `MAXNGRAMSUGS 0` 的语义需要的。

**设计取舍**
- **不猜评分函数**。任务明确「猜出来的评分器比诚实的缺口更糟」；而且实测语料里
  37 个 `.sug` 套件有 12 个显式 `MAXNGRAMSUGS 0`（关闭）、3 个写 `1`、其余没写。
  猜一个默认开启的 ngram 通道，最可能的结果是把这 12 个套件**弄回归**，而不是提高
  通过率。宁可不做。
- **AST 保真**：`max_ngram_sugs` / `max_diff` 用 `Int?` 而非 `Int`，因为手册只给了
  `MAXDIFF` 的默认值 5，没给 `MAXNGRAMSUGS` 的默认值；`None` 表示「文件没写」，
  默认值留给未来的消费者决定。`MAXDIFF` 的值按文件原样存（不因超出 0–10 报错），
  避免真实词典里一个越界值让整个 `.aff` 解析失败。

**测试与验证**
- `src/aff/aff_test.mbt` 新增 2 个测试：三条指令被解析且 `unrecognized` 为空；
  缺省为 `None`/`false`，而 `MAXNGRAMSUGS 0` 是 `Some(0)` 而不是 `None`。
- 全后端：wasm / wasm-gc / js **166/166**，native **170/170**。
- `moon check --deny-warn --target all` 干净；`moon fmt` / `moon info` 已跑。
- 符合率重测**未回归**：`.good` 825/848、`.wrong` 611/613、`.sug` 141/173
  （as-first 124/173、exact 7/37）。

**仍然没做 / 局限**
- ngram 候选生成与 `FORCEUCASE` 驱动的建议仍缺席，缺席原因（手册未定义评分）已写进
  README「Not implemented yet」。
- 通道性能未测——没有通道就没有可测的通道成本。作为参照，当前（无词典扫描的）建议
  引擎在真实 `en_US`（49,568 条）上约 **0.26 s 载入 + 每词约 0.04 s**
  （wasm/moonrun，含进程启动，5 词 0.57 s、20 词 1.04 s、空输入 0.26 s）。
  任何未来的 ngram 通道都要对每个错词扫全词典，必须先用长度窗口/早停限界再上线。
- `docs/MOONBIT_GOTCHAS.md` 本次**没有新增条目**：给 `pub(all) struct` 加字段、
  字段类型用 `Int?` 在本工具链上 `moon check --deny-warn` 干净通过，没有触发新坑；
  且「加字段不需要新 `extend`」已由第 37 条覆盖。按该文件「只记验证过的坑」的约定，
  不硬凑条目。

---

## 2026-09-27 · Day 11 — 收口不是「只改文档」：把一次真实性能回归挖出来并修掉

原来计划 0.9.1 只做文档同步。做之前先把 README 的性能表重测了一遍，结果**对不上**：
README 记的是直接命中 **0.34 µs/词**，实测是 **0.75 µs/词**。差了 2.2 倍，必须查清。

**归因（不是猜，是 A/B）**

怀疑对象是 `check_one` 里那个遍历全部后缀规则的 `forbidden_derived`。读完短路结构后
**排除**了它：`lookup_word` 是 `||` 的第一个分支，直接命中时后面根本不会执行。
于是改用最笨也最可靠的办法——在同一台机器、同一条命令上，对 `en_US` 自带的
49,568 个词计时，然后用 `git stash` 回到改动前再测一遍：

| 版本 | all-hits 每词 | all-misses 每词 |
|---|---|---|
| 改动前 | **0.746 µs** | 9.81 µs |
| 只修 `apply_conversion` | **0.403 µs** | 9.54 µs |
| 再修 `check_word_group` | **0.323 µs** | 9.28 µs |

**两个真凶（都是「先付成本再判断」，不是算法错）**

1. `apply_conversion`：`conversion_pattern()` + `to_array()` 写在**每个字符位置**的循环里，
   而 `conversion_pattern` 是纯函数、`table` 在循环内不变。en_US 有 `ICONV 1`，于是每检查
   一个词就新分配「词长 × 规则数」个数组。更讽刺的是 `prepare_conversions` 的注释白纸黑字
   写着「the per-word cost is a linear scan **without re-parsing the patterns**」——
   这个设计意图在实现里从未落地。
2. `check_word_group`：由 `check` 在**真正的查表之前**无条件调用，每次都先分配
   `Array[String]` + `StringBuilder` + 把整词复制成一个新 `String`，然后才发现
   `parts.length() < 2`（绝大多数输入就是一行一个词）。三次分配全是白付。

修法都是**语义等价**的：前者把不变量提出循环 + 加一个零分配预扫描；后者抽出一个
零分配的 `has_whitespace` 必要条件检查。命名上特意避开 `has_word_group`——`"  drink  "`
含空白却不是词组，它只是必要条件，名字必须如实说这件事。

**为什么要写 10 个新测试**

改的正是 `apply_conversion`，而它**一个测试都没有**（尽管它实现了 `ICONV`/`OCONV`）。
先补测试再谈优化：最长优先/末尾锚定的排序、`_` 锚定、空 pattern 跳过、「输出不再被
重扫」、按码点而非字节匹配、无命中快速路径。补完后做了**变异测试**证明这些测试真的会咬人：
把快速路径改成「只看首字符」，5 个测试失败（`"café" != "cafe"`）。

**验证（三条独立证据）**

- 全量测试：wasm / wasm-gc / js **176/176**，native **180/180**（原 166/170）。
- 全量符合率：`.good` **841/848 = 99.2%**、`.wrong` **611/613 = 99.7%**，与改动前**逐字一致**。
- 差分测试：`/usr/share/dict/words` 235,976 词，**198 该拒绝却接受、1 该接受却拒绝**，
  与改动前**逐字一致**。
- hunspell 的 `iconv`/`iconv2`/`iconv3`/`oconv`/`oconv2`/`iconv_break_overflow`
  六套用例 100% 通过——正好打在被改的代码路径上。

**顺手修掉的一个度量 bug**

`conformance/run.sh` 一直用 `paste -d' '` 按位置配对，任何含空格的语料行都会错位并被
判为失败。`morph.good` 正好有 16 行 `drink eat` 这种。改成「每非空输入行一个判定、直接
计数」后：`.good` **825/848 → 841/848 = 99.2%**，差值 16 就是假象的大小。**引擎行为一个
字都没变**，但之前那个 97.3% 一直是低估。这就是为什么 Day 6 之后每一次「未回归」的声明
都值得重新验一遍——度量的口径本身也可能是错的。

**新增的差分测试（`conformance/differential.sh`）**

手写语料答不了「真实词表上到底多常不一致」。新脚本把词典抓临时目录（**不入库**），
用本库和 `hunspell -l` 各判一遍，双向打印分歧。它**不进 CI**：需要系统装 hunspell，
而且它只做测量、不判定通过失败——把测量伪装成门禁是错的。

**性能现状（诚实版）**

优化后直接命中与 hunspell **基本持平**（0.38 vs 0.36 µs/词，1.06×，在噪声内）；
但 **miss 路径仍慢 6.4 倍**（9.60 vs 1.49 µs/词），因为一个被拒绝的词要把每条后缀规则、
每条前缀规则、前缀×后缀叉积和双后缀族全试一遍，而命中只是一次 map 访问。
**所以下一个真正的优化目标是 miss 路径和词典载入，不是直接查表。**

---

## 2026-09-27 · Day 12 — 拿申报书当验收合同，逐条对，然后发现一处"写了但没做"

收口做完之后，把**申报书**当成合同逐条核了一遍。依据是章程三条硬约束：

- L227「申请完成支持时，应**完成申报阶段约定的主要功能**」
- L245 驳回情形「未完成申报 **Proposal 中的主要目标**」
- L247 取消资格情形「项目无法运行、无法复现或**与申报内容明显不符**」

注意它是**单向**的：多做了不算违背，**少做了才算**。

**核对结果**

核心功能范围 6 项**全部交付**，而且两条"承诺里写得很细"的地方经得起查：

- 「未实现的指令会统一记录不直接丢弃」→ `AffFile.unrecognized : Array[UnknownDirective]`，
  且有测试断言它的 `name` / `args` / `line`；
- 「解析出错标注对应行号」→ `AffParseError(line~, message~)`，格式就是 `"line N: message"`。

「本期暂不实现」4 项里：`suggest()` 和**完整复合词引擎**两项**反而做完了**
（申报书只承诺"仅支持 COMPOUNDMIN / COMPOUNDFLAG 基础场景"，实际做到了德语式复合词、
`COMPOUNDRULE`、`COMPOUNDWORDMAX`、`COMPLEXPREFIXES`）；FFI 绑定与编辑器插件确实没做。

**发现的真缺口**

申报书的**使用场景 2** 写的是：「通过命令行工具运行，输入 Markdown 文件或目录，输出可疑词
清单**与退出码**，可以嵌在流程里**自动拦截**拼写错误」。

实测：`examples/doccheck` **有没有拼写错误都返回 0**。`run()` 里只有参数错误（2）和读文件
失败（1）两条非零路径，**根本没有"发现拼写错误 → 非零"这一条**。也就是说这句话当时是
**不成立的**——想拿它拦 CI，只能去解析文本输出。

这正是"逐条对申报书"的价值：**它不是形式主义，它能查出一句自己写下的、听起来很合理、
但从未真正实现的话。**

**修法（0.9.2）**

- `doccheck` 现在：`0` = allowlist 之后没有拼写错误；`1` = 发现拼写错误；`2` = 参数或 I/O 错误。
  采用 linter/grep 的通行约定，`1` 专门留给"发现问题"。
- 加 `--no-fail` 逃生阀：强制返回 0，给只想要数字的调用方（本仓库自己的测量就是这么跑的）。
- **`run.sh` 必须一起改**：它的选项透传只认 `--include-tests | --quiet`，不加 `--no-fail`
  的话这个 flag 会被**当成目标目录**，报 "not a directory"。这种"wrapper 白名单"式的坑不写
  下来下次还会踩。
- 决策**不**改 `cmd/main check` 的退出码：它输出的是**逐行判定流**，而 conformance 与 bench
  的 harness 都读这个流；如果被拒的词让进程非零退出，`bench/run.sh` 的 `timed()` 会直接
  判为"测量失败"。**门禁是 `doccheck` 的职责，不是判定流的职责。** 这一点写进了 README 与
  `examples/README.md`，免得以后有人"顺手统一"。

**验证**

- 7 个用例逐个实跑：干净→0、有错→1、有错+`--no-fail`→0、缺 `--dic`→2、词典不存在→2、
  目录不存在→2、本仓库→0。
- 用真实的 shell `if` 写法证明门禁成立：干净时步骤通过，有错时步骤失败。
- 新增 2 个白盒测试（`exit_status` 与 `--no-fail` 的解析，含"flag 后面跟的目录仍是目录"）。
  全后端 **178 / 182** 通过。
- **刻意没有重跑符合率与基准**：这次改动只在 `examples/doccheck/` 下，`src/`、`cmd/` 一行未动，
  所以那些数字**在结构上不可能变化**。与其跑一遍然后含糊地说"已验证"，不如说清为什么不必跑。

---

## 2026-09-27 · Day 13 — 把自己当成评委，从零装一遍自己的包

文章发出去之后，做了一件之前一直没做的事：**建一个全新的 MoonBit 项目，`moon add Careylq/spell`，
然后照抄自己 README 的 Quick start。** 结果第一步就撞墙。

**实测撞到的四处（每一处都复现了报错）**

| # | 现象 | 报错原文 |
|---|---|---|
| 1 | README 全文**没出现过 `moon.pkg`** | `Package "spell" not found in the loaded packages` |
| 2 | 测试文件需要 `for "test"` 作用域 | `unused_package`（`--deny-warn` 下报错原文是 `Error Warning`，**测试却是通过的**） |
| 3 | `load` 会抛错，不能直接放进 `fn main` | `[4122] Function with error is not allowed in \`fn main\`` |
| 4 | CLI 章节没说运行位置 | 消费者执行 `moon run Careylq/spell/cmd/main` → `failed to resolve path` |

**这四处的共同点：库里没有一行代码有问题。** 全部是"文档承诺了、但按文档做不出来"。
这恰好命中验收标准第 4 条（README 要说明安装方式、使用方法，**并可复现**）与生态相关性维度。
`examples/basic` 里其实一直有正确写法（`load(...) catch { error => ... }`），
但 README 的 Quick start 只有 `test {}` 块，没人会去翻例子才知道要 `catch`。

修法：Install 一节直接给出 `moon.pkg` 两种写法（普通 / `for "test"`），
Quick start 补一个**受 `moon check` 编译**的 `catch` 块并点出 `fn main raise`，
CLI 一节写明"要在本仓库克隆里跑"。发 **0.9.4**。

**顺带纠正了自己的一处过度承诺**

README 开头一直写着"any MoonBit code block below is verified by `moon check`"。实测：**只有标了
`mbt check` 的块会被编译**，没标的不编译。两种写法各做了一次变异测试确认——标了的那块改坏类型
→ `Failed with 0 warnings, 1 errors`；没标的那块改坏类型 → 照样通过。声明已改成事实。

**章程口径纠正：阶段三 9 条，不是 10 条**

我一直写"验收 10 条"，实际读原文是 **9 条**——第 9 条含"OSI 许可证"和"参考移植合规"两个子句，
我把两个子句拆成了两行，于是变成了"10"。现在 `ACCEPTANCE.md` 明说是"9 条 → 10 行（第 9 条拆两行）"，
**避免评委数不上 10 条时以为我在凑**。

同时发现**第七章还有独立的 10 条「开源与成果提交要求」**（公开发布 / 完整源码 / 开发历史 / README /
OSI 许可证 / 注明参考来源 / 遵守第三方许可 / 不侵权 / **生成代码与数据来源合法** / 同意宣传），
之前完全没对照过。已补成第二张表。

第 9 条对本项目尤其关键：**开发过程用了 AI 辅助，所以"代码来源可核验"是重点。** 好消息是材料现成：
`DEVLOG.md`（逐日记了哪些由 AI 生成、怎么验证）、`docs/MOONBIT_GOTCHAS.md`（43 条）、
`CHANGELOG.md`、以及刚发表的知乎/掘金文章。

**我在这一节犯的两个错（都记下来）**

1. **一个"没跑"的脚本让我得出了相反结论。** 我用 `python3 /dev/stdin <<'EOF'` 写探针，
   有一次脚本根本没执行（没有输出），而我**把"没有报错"当成了"特性不存在"**，
   差点把 README 里一句**正确**的声明当成错误去"修"。教训：**验证脚本必须回显它做了什么**
   （`print("wrote ...")` + 校验文件确实存在），否则"沉默"会被误读成"通过"。
2. **`git checkout -- <file>` 把我未提交的 5 处编辑一起清掉了。** 当时是为了撤销一个变异测试，
   结果连正要提交的改动一起回滚。教训：变异测试要在**干净的工作区**上做，或者先 stash／先提交。

**副作用：README 的示例变成了真测试**

补进 Quick start 的那个 `catch` 示例是 ```mbt check` 块，而它含一个 `test {}`，
于是 **`moon test` 真的会执行它**——测试数从 178/182 变成 **179/183**。

这件事有两面，都值得记：

- 好的一面：README 承诺的行为从"只是被编译"升级成"被测试执行"，**文档再也不能腐烂**。
  这正好对应验收标准第 4 条的"**可复现**"。
- 麻烦的一面：文章和封面已经发布了，上面写的是 178/182。**我不回改已发布的内容**——
  正文保留原样，只在文末加一条带日期的更正说明，并让 README 明确写清：
  文章说 178/182、仓库现在是 179/183、原因是这个、**冲突时以仓库为准**。
  这恰好是文章自己的论点（数字会过期，要重测），所以不算难看。

**下一步**：10 月场是独立场次，截止 **10/24**（此前不知道）。按你的决定先休息到 10/1。

---

## 2026-09-27 · Day 14 — 把"承诺"变成"可被 CI 拦住的东西"

这一轮做了四件你选的事，共同点都是**把已经写在文档里的承诺变成可执行、可验证的东西**。

**① `examples/ci-gate`：让申报书场景 2 从散文变成演示**

申报书场景 2 承诺"输出可疑词清单**与退出码**，可以嵌在流程里**自动拦截**"。
0.9.2 把退出码修好了，但仓库里**没有"怎么用"的示范**——承诺仍然只活在散文里。

新示例离线自包含：自己写一本五词词典（**不联网、不 vendor**），跑五个用例并断言退出码
（干净→0、有错→1、有错+`--no-fail`→0、词典文件缺失→2、无参数→2），然后打印可以直接抄的
workflow 片段。任何一条不符就返回非零，所以 CI 能跑它——本仓库的 CI 就跑。

写这个示例时它**当场抓出了我自己的 fixture bug**：我的"干净"文档里有 Markdown 标题
`# Notes`，而 `Notes` 不在那本四词词典里，于是"干净树"用例返回 1。把 `notes` 加进词典才对。
**示例能抓自己的作者，说明它是真的在跑。**

**② 顺手修掉一个我自己引入的不一致**

写 ci-gate 文档时我写下"环境故障不能被误诊成文档问题"，然后发现
`examples/doccheck/run.sh` **在抓不到词典时返回 1**——而 1 的含义正是"发现拼写错误"。
这正好犯了我刚写下的那条错误。改为返回 **3**，契约变成
`0 干净 / 1 有拼写错误 / 2 用法或 I/O 错误 / 3 取不到词典`。

3 不是装饰：**正因为有 3，CI 才能"对真拼写错误变红、对网络抖动放行"**。
我用"临时移开词典缓存 + 把 CDN 指向死端口"验证了 3 真的可达（rc=3），恢复后正常路径仍是 0。

**③ `check-all.sh`：一条命令做完终检**

你选了 9/29 由我做终检。与其到时候手打七八条命令，不如固化成脚本。它分成两段，**故意不同**：

- **Phase 1 闸门**（失败即返回非零）：`moon check --deny-warn` / `fmt --check` / `test` /
  `.mbti` 未变 / 离线的退出码契约。**这一段不联网。**
- **Phase 2 测量**（只报告，永不失败）：doccheck / 符合率 / `.sug` / 差分 / 基准，
  各自写进文件，最后提取头条数字。某一项没网就明确说 SKIP，不编数字。

变异测试确认闸门有效：放一个类型错误的临时文件进去 → 相关闸门报 FAILED、整体 rc=1。
另外我给它加了一个**显式警告**：doccheck 有标记词时不是"悄悄通过 phase 2"，
而是打印出是哪几个词，并提醒"这是 CI 的阻塞步骤，CI 会红"。用它跑旧的报告，
它准确报出了 `misconfiguration`。

**④ 中文 README：用 `.mbt.md` 而不是 `.md`**

关键决定：中文版命名为 **`README.zh.mbt.md`**（`README.zh.md` 是符号链接）。
理由很实际——**这样中文版里的 MoonBit 代码块也会被 `moon check` 编译、`test` 块会被
`moon test` 执行**，中文文档就没法和它描述的代码脱节。已实测：加进去之后测试数
179/183 → **182/186**。

代价是**已发表文章里的 178/182 又远了一格**。处理方式不变：不回改正文，
把发表后更正说明写清三次变化（178→179 是英文 Quick start 的 `catch` 块，→182 是中文版的
三个块），并让 README 继续声明"冲突时以仓库和脚本为准"。

**⑤ 一个反直觉的荣誉：这次 bench 说我们更快**

同一台机器、同一条命令再跑一次基准，直接命中是 **0.34 µs/词 vs hunspell 0.38（0.89×，
我们更快）**；而 0.9.1 那次是 0.38 vs 0.36（1.06×，我们略慢）。

**同一份代码，两次结论相反——这本身就说明这个比值在噪声里。** 所以我没去挑好看的那次写进
README，而是把**实测区间**写进去：直接命中在 **0.89×–1.06×** 之间摆动，未命中在
**6.30×–6.44×**。这样以后谁再跑出第三次，文档也不会被打脸——
**这才是"报告一个测量"和"报告一个结论"的区别。**

**这一步的教训**

承诺写在文档里只是散文；**只有当你把它接到一条会失败的检查上，它才成为工程。**
这一轮四件事都是这句话的同一个动作。

---

## 待续
