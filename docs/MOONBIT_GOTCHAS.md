# MoonBit 编译器验证过的坑（AI 最容易搞错的地方）

本文件记录在实现 `.aff` 解析器过程中，**由编译器/warning 实际验证过**的 MoonBit 语法与工具链陷阱。

**为什么值得记录**：LLM 对 MoonBit 的零样本正确率只有 0–1%（IEEE TSE 论文实测），
所以 AI 生成的 MoonBit 代码"看起来对、实际编译不过"是常态。
这份清单把踩过的坑固化下来，让后续迭代（以及任何 AI 辅助）不用重复踩。

> 环境：`moon 0.1.20260920`（编译器 v0.10.x），macOS arm64。
> 条目均以 `moon check` / `moon explain --diagnostic` 的输出为准。

---

## 1. `inspect` 已废弃

- **症状**：warning `0020`。
- **正确写法**：`@debug.debug_inspect`。
- **连带影响**：`debug_inspect` 打印的是 `Debug` 表示，字符串会带引号
  （`"UTF-8"` 而不是 `UTF-8`）。快照必须重新生成：`moon test --update`
  （`--update` 会自动改写源码里的 `content=` 参数）。

## 2. `derive(Eq, @debug.Debug)` 会触发 warning 0079

- **症状**：`implicit_impl_as_method`（0079）。
- **正确写法**：写显式的 `pub extend` 块：
  ```moonbit
  pub extend T with Eq::{equal, not_equal}
  pub extend T with @debug.Debug::{to_repr}
  ```
- **说明**：这是 `moonbitlang/core` 里每个包的 `extends.mbt` 的做法。
  本项目为此增加了 `src/aff/extends.mbt`——**加上它才是 0 warning**，删掉会有 19 个 warning。

## 3. `unused_mut` 是 **error** 不是 warning 🔴

- **症状**：错误 id `15`。
- **触发条件**：结构体字段声明为 `mut`，但只通过 `arr.push(...)` 修改。
- **原因**：`Array` 是引用类型，往数组里 push **不需要**该字段是 `mut`。
- **教训**：**不要凭直觉加 `mut`**，编译器会当真。

## 4. 带 `raise` 效果的函数必须写返回类型

- **症状**：`Missing type annotation for the return value`。
- **正确写法**：即使返回 `Unit` 也要显式写出，例如
  `fn f(...) -> Unit raise E`。

## 5. 多行 `#|...` 字符串直接当调用参数是废弃语法

- **症状**：warning `0027`。
- **正确写法**：先绑定到 `let`，再作为参数传入。

## 6. 两个已废弃写法

- `not(x)` → 用 `!x`
- `StringView::to_string()` → 用 `to_owned()`

## 7. `suberror` 具名字段的构造与解构

- 构造：`AffParseError(line=..., message=...)`
- 在 **blackbox 测试**的 `catch` 里模式匹配：`AffParseError(line~, message~)`
- **注意**：`moon fmt` 会把 `line=line` 改写成 `line~`。

## 8. `try { ... } catch { ... }` 是表达式

- 可以直接用在赋值右侧。
- 只有一个构造子的 `suberror` **不需要** `_` 兜底分支。

## 9. blackbox 测试里要写 `@包名.` 前缀

- **症状**：warning `25`（`test_unqualified_package`）。
- 在 `_test.mbt` 里本包 API 虽然隐式可见，但**不加 `@aff.` 会出 warning**。
- `pub(all) enum` 的构造子可以写成 `@aff.Num` 这样访问。

## 10. `moon.pkg` 的测试包需要单独声明依赖

- 主 `import { ... }` 块**不覆盖测试包**，需要：
  ```moonbit
  import { ... }
  import { ... } for "test"
  import { ... } for "wbtest"
  ```
- 例如 `@string.parse_int` 需要显式引入 `moonbitlang/core/string`。

## 11. 用 `moon explain` 查清"哪些 warning 实际是 error"

```bash
moon explain --diagnostic            # 列出全部诊断码与名称
moon explain --diagnostic 15         # 查具体码
moon explain --attribute <NAME>      # 查属性
```
例：`unused_mut` = **error id 15**，而 `implicit_impl_as_method` = warning `0079`
（后者不在简表里，需要单独查）。**这是 AI 自学编译器规则最有效的入口。**

---

## 附：`.aff` 解析器的判断取舍（已写进代码注释）

- **注释策略取保守**：只剥离**整行注释**（首个非空白字符是 `#`），
  行内 `#` 原样保留。因此 `SET UTF-8 # note` 会产生多余 token，由具名指令自行忽略。有测试覆盖。
- **AF 别名只作用于 `PFX`/`SFX` 的 flag 参数**；`NOSUGGEST` / `COMPOUNDFLAG` 等处的 flag
  **原样保留**，避免信息丢失。已用「2 条 AF 表 + `NOSUGGEST 100`」的用例验证。
- `REP` 的 `_`（表示空格）原样保留，不做转换。
- `compound_min` 缺省为 `0` 表示"未声明"（Hunspell 自己的默认值 3 延后到匹配阶段处理）。
- 无 `SET` 行时 `encoding` 为空字符串。
- 解析是**单趟**的，所以 `AF` 表必须出现在使用它的 `PFX`/`SFX` 之前（与真实文件一致）。

## 12. `assert_true` / `assert_false` **不在** `@debug` 里

- `moonbitlang/core/debug` 只有 `assert_eq` / `debug` / `debug_inspect` / `dump` / `render` / `to_string`。
- 写 `@debug.assert_true(...)` **会编译失败**。它们来自 builtin/prelude，**直接用无限定名即可**。
- `@debug.assert_eq` 可用，但要求类型满足 `Eq + Debug`。

## 13. warning `unused_package`（0029）

- 在 `moon.pkg` 的 `for "test"` / `for "wbtest"` 里列了导入、但**测试文件还没真正用到**时会告警。
- 所以一个写法完全正确的 `moon.pkg`，在测试写好之前也可能"看起来有警告"。别被误导（是 #10 的延续）。

## 14. 🔴 `String` 的 Unicode 语义（做字符匹配必须搞清）

| 方法 | 语义 |
|---|---|
| `length()` | **UTF-16 code unit** 数 |
| `char_length()` | **Unicode 码点**数 |
| `to_array()` | 每个**码点**一个 `Char`（会解码代理对） |
| `get_char(i)` | 按 **code unit** 索引；若正好切在代理对中间返回 `None` |

**结论：做 Unicode 正确的字符匹配/切片，必须用 `to_array()` 或 `char_length()`，
不要用 `length()` / `get_char()`。**

## 15. `moon fmt` 会改写 `moon.mod`

- 它会往 `moon.mod` 里插空行，**弄脏你并不想动的文件**。
- 只检查不写入：`moon fmt --check <包路径>`。
- 本项目因此有几次 `moon.mod` 出现"无意义 diff"，已还原。

## 16. `#|` 多行字符串不处理反斜杠转义

- 所以测试数据里的字面 `\/` 可以原样写，不需要双重转义。

## 17. 跨包使用没问题

- 外部 `pub(all)` 结构体字面量 + 字段简写（pun `{ a, b }`）可用。
- `@aff.Suffix` 这类枚举构造子既能当表达式也能当模式，跨包都正常。

## 18. 已知局限（诚实记录）

- `.aff` / `.dic` 的 **UTF-8 BOM (U+FEFF)**：`Dictionary::from_text` 与 CLI 现已剥离；
  直接调用底层 `parse_aff` / `parse_dic` 仍不剥离。
- `FLAG num` 的值未校验是否为十进制（按规范原样存字符串）。
- `.dic` 计数行之后的文本（如 `4 # comment`）现已忽略（与 Hunspell 的数值扫描一致）。

---

## 19. 🔴 `fn f(self : T, ...)` 作为自由函数是废弃语法（0027）且会变成方法

- **症状**：写
  ```moonbit
  fn lookup(self : Dictionary, word : String) -> Bool { ... }
  pub fn Dictionary::check(self, word) { lookup(self, word) }
  ```
  编译器把 `lookup` 注册成 `Dictionary::lookup`，于是 `lookup(self, word)` 报
  `4021 The value identifier lookup is unbound`；同一批 9 个函数一次报了 24 个错。
- **正确写法**（二选一）：
  1. 写成方法：`fn Dictionary::lookup(self : Dictionary, ...)`，调用 `self.lookup(...)`；
  2. 首参不要叫 `self`：`fn lookup(dict : Dictionary, ...)`。
- **注意**：warning 0027 只报一次在定义行，错误却在每个调用点，很容易误判成作用域问题。

## 20. `pub using` 可以再导出类型与函数

```moonbit
pub using @spell { type Dictionary, type SpellError, load, check }
```
- 模块根（`Careylq/spell` 根包的 `spell.mbt`）用它把 `src/api` 的门面转出去，
  `import { "Careylq/spell" }` 就能 `@spell.load(...)`。
- `pub struct X { a : Int }`（非 `pub(all)`）在 `pkg.generated.mbti` 里**仍会列出字段**，
  但外部不能构造；这不是字段泄漏，只是接口描述。

## 21. `.mbt` 的文档注释代码块也会被 `moon check` 类型检查

- `/// ```mbt check` 里的代码在该包的 **blackbox 测试上下文**编译。
- 因此文档示例里写未限定的本包函数会触发 warning `0025 test_unqualified_package`，
  要写成 `@api.foo`。README.mbt.md 的代码块同理（它属于根包，所以用 `@spell.` 前缀）。
- 好处：README 的 Quick start 不会再「文档和代码脱节」——写错就编译失败。

## 22. `moon fmt --check` 与 `moon.mod` 空行（第 15 条的延伸）

- `moon fmt` 会给 `moon.mod` 插一个空行；只要不接受它，`moon fmt --check` 就**必然失败**。
- 本期选择接受这个空行，于是 `moon fmt --check` 通过。CI 只跑 `moon check/build/test`，
  不受影响。

## 23. `&` 的优先级低于 `==`

- `b & 0xC0 == 0x80` 被解析成 `b & (0xC0 == 0x80)`，类型检查报
  `Expr Type Mismatch: has type Int, wanted Bool`。
- 必须写 `(b & 0xC0) == 0x80`。

## 24. `String` 没有 `ends_with` / `starts_with` / `to_ascii_uppercase`

- 匹配前后缀用 `strip_prefix` / `strip_suffix`（返回 `StringView?`），
  包含判断用 `contains`；大小写只在 `Char` 上有 `to_ascii_uppercase` / `to_ascii_lowercase`。
- 大小写折叠的非 ASCII 部分要用 `moonbitlang/x/unicode` 的 `to_lowercase(Char)`
  （**只有小写方向**，没有 `to_uppercase`）。

## 25. core 没有文件 / stdin API

- 读文件用 `moonbitlang/x/fs`：`read_file_to_bytes` / `read_file_to_string`；
  需要自己按编码解码时先拿 `Bytes`。
- 读 stdin 可以直接把 `"/dev/stdin"` 交给 `read_file_to_bytes`（`moon run` 默认 wasm +
  moonrun 会正常解析这个伪路径；macOS 与 Linux 均可用）。
- `@env.args()` 第 0 个元素是程序自身路径，用户参数从下标 1 开始；
  退出码用 `moonbitlang/x/sys` 的 `exit(Int)`（wasm 后端映射到 `proc_exit`）。

## 26. 🔴 `pub struct` 的**私有字段类型也必须是 `pub`**

- **症状**：给 `pub struct Dictionary` 加一个字段，字段类型是 `priv struct SpellRule`，
  报错 `4046 A public definition cannot depend on private type`。
- **说明**：字段本身是私有的（`Dictionary` 是不透明类型），但编译器仍然要求
  字段**类型**的可见性不低于容器。`priv enum CpdAtom` 放在 `pub struct` 的字段里
  同样报 4046。
- **两种修法**：
  1. 把类型改成 `pub struct X { ... }`（字段仍私有，外部不能构造，`.mbti` 里只多一个
     不透明类型名）；
  2. 不要把这个类型放进 `pub` 结构体字段——例如只存 `Array[String]`（原始文本），
     在私有函数里现解析。本项目 `COMPOUNDRULE` 就是这么做：字段存 `Array[String]`，
     `parse_compound_rule` 在匹配时调用。

## 27. 嵌套数组字面量 `[[x]]` 推断不出类型

- **症状**：`self.derived_standalone([[rule.cont_flags]])` 报 4014
  `Expr Type Mismatch: has type Array[String], wanted String`。
- **正确写法**：先绑定并标注类型，再传：
  ```moonbit
  let applied : Array[Array[String]] = [rule.cont_flags]
  if !self.derived_standalone(applied) { ... }
  ```
- **同类**：`entries[word] = [flags]` 给 `Map[String, Array[Array[String]]]` 赋值时
  也要先绑定。

## 28. `x.is_none()` / `x.is_some()` 已废弃（warning 0020）

- **正确写法**：`x is None` / `x is Some(_)`（`match` 一直都可以）。
- 注意 `x is None && y is None` 里的 `is` 与 `&&` 结合正常，不需要额外括号。

## 29. `>>`/`&`/`==` 的优先级（第 23 条的延伸）

- `(mask >> p) & 1 == 1` 被解析成 `(mask >> p) & (1 == 1)`，报类型错并附带
  warning 0051 `ambiguous_precedence`。
- 必须写 `((mask >> p) & 1) == 1`。**只要 `&` 和 `==` 同现，就加括号。**

## 30. 🔴 一个 `moon.pkg` 里 `for "test"` import 块只能有一个

- **症状**：`moon check` 直接失败在「构建计划」阶段，报
  `Unable to read moon.pkg ... Duplicate key 'test-import' found in moon.pkg.`
  （不是普通的语法/类型诊断，而是整个模块发现失败。）
- **触发**：给测试新增依赖时，又在文件末尾写了一个 `import { ... } for "test"`。
  第 10 条说的是"主 import 块不覆盖测试包"，**不是**"可以写多块"。
- **正确写法**：并进已有的 `for "test"` 块；`for "wbtest"` 同理。
- 实测：`src/suggest/moon.pkg` 一开始同时有主块 + 两块 `for "test"`，就是这个错误。

## 31. `Array::sort_by` 的比较器返回 `Int`，且**不稳定**；`String` 自带 `compare`

- 签名：`pub fn[T] Array::sort_by(Self[T], (T, T) -> Int) -> Unit`，
  返回负数表示 `a` 在前（与 core 测试里的 `a.compare(b)` 一致）。
- **不稳定**：相等元素的相对顺序不保证。要确定性输出，比较器必须是**全序**，
  例如最后用 `a.word.compare(b.word)` 兜底。`String` 实现了 `Compare`，
  所以 `"a".compare("b")` 可直接用，不需要手写逐字符比较。
- 本次建议引擎就靠"排名键 + 字典序兜底"保证同一输入每次输出一致。

## 32. 顶层 `const` 可用，`match` 的 `let` 绑定可以 shadowing

- `const MAX_EDIT_LEN : Int = 32` 在包顶层合法（core 里大量使用；
  `let` 也行，但 `const` 语义更准确）。
- `let (body, at_end) = match body { Some(r) => (r.to_owned(), true), None => (body, false) }`
  这种**先绑定再在同一条 `let` 里复用同名变量**是允许的，解析器不会混淆。
- 这两条都不是坑，而是"AI 常以为不行、实际可以"的写法，记下来省一次试错。

---

## 33. 🔴 原生后端的 `--words -` 读不了**管道**（wasm 后端可以）

- **背景**：CLI 的 `--words -` 约定从 stdin 逐行读词（见 `conformance/README.md`）。
  实现是把 `"/dev/stdin"` 交给 `@fs.read_file_to_bytes`。
- **症状**：`printf 'hello\nzzzz\n' | <native-binary> check ... --words -`
  失败并打印 `spell: cannot read "/dev/stdin": Illegal seek`，退出码 1。
- **原因**：`read_file_to_bytes` 需要先 seek 到末尾拿到长度。macOS 上
  `/dev/stdin -> /dev/fd/0`：fd 0 是**管道**时不可 seek；fd 0 是**重定向的普通
  文件**时可 seek。
- **后端差异（关键）**：`moon run`（wasm + moonrun）把 `/dev/stdin` 当预打开文件
  处理，读管道正常；`--target native` 走真实文件系统，因此**只有 native 会失败**。
  同一段命令在两个后端行为不同，很容易在本地（moon run）测过、CI/发布版（native）
  才炸。
- **规避**：用 `< file` 重定向（`conformance/run.sh` 就是这么做的），或者直接传
  `--words <file>`。`bench/run.sh` 一律传显式文件路径，所以不受影响。
- **实测**（moon 0.1.20260920 / macOS 26.6.2 arm64）：

```bash
printf 'hello\nzzzz\n' | main.exe check --aff a.aff --dic d.dic --words -   # Illegal seek, rc=1
main.exe check --aff a.aff --dic d.dic --words - < words.txt              # 1 / 0, rc=0
printf 'hello\nzzzz\n' | moon run cmd/main -- check --aff a.aff --dic d.dic --words -   # 1 / 0, rc=0
```

---

## 附二：实现过程中被测试抓出来的两个真 bug（值得记住）

这两条是**语义性错误**，不是语法错误——编译器不会报，只有测试能抓：

1. **前缀规则必须"前置" add，后缀才"后置"**。
   第一版把 `PFX 0 re .` 也写成了追加，于是 `create` 变成 `createre`。
   正确结果：`recreate`。（典型的"想当然"错误）
2. **condition 必须对「未 strip 的 stem」匹配**。
   `SFX y ied [^aeiou]y` 要对 `imply` 生效：若先 strip 掉 `y` 变成 `impl`，
   就**永远不可能**匹配 `[^aeiou]y`（该模式以 `y` 结尾）。
   先匹配 condition、再 strip、最后 add，顺序不能错。

> 这两条说明：**"AI 写的代码能编译" ≠ "语义正确"**。
> 编译器只保证语法和类型，语义必须靠测试（这也是本项目以符合率作为核心证据的原因）。

---

## 附三：我给出的测试基准里也有一个错误（已修正）

我在给实现方的规则对照表中写了：

| 规则 | 词根 | 我预期的结果 |
|---|---|---|
| SFX, `y`, `ication`, `y` | `imply` | `implification` ❌ |

**这是错的。** 正确答案是 **`implication`**（`impl` + `ication`）；
`implification` 需要真实的 en_US 里另一条 `ification` 规则。

实现方发现并同时断言了两种情况（`ication` → `implication`、`ification` → `implification`）。
**记录下来是因为这正好印证了本项目的工作方式：谁来断言都不算数，只有跑出来的结果算数。**

