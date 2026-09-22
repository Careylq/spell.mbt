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

## 本切片未做（有意留到后续）

条件匹配、`COMPOUNDRULE`/`PATTERN` 匹配、`AM` 别名解析进 morph 字段、
`ICONV`/`OCONV`、`.dic` 解析、`AF` 表出现在使用之后的情形。
