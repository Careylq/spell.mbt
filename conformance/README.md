# conformance/ — 符合率测试

用 Hunspell 官方测试语料衡量本库的判定正确率。这是本项目最重要的**可度量质量证据**。

## 为什么语料不放在仓库里

Hunspell 官方 `tests/` 语料随 Hunspell 以 **LGPL-2.1** 发布，而本项目是 **Apache-2.0**。
把 LGPL 文件复制进 Apache-2.0 仓库会造成许可证混用。

**做法**：脚本在运行时把语料克隆到临时目录，只产出报告，不分发语料文件。
（章程要求"符合原项目许可证要求"，这样处理最干净。）

## 语料结构

Hunspell 的 `tests/` 目录是一组组「测试集」，每组由同名文件构成：

| 文件 | 含义 |
|---|---|
| `X.aff` | 词缀规则（输入） |
| `X.dic` | 词典（输入） |
| `X.good` | **必须被判为"正确"的词**（每行一个） |
| `X.wrong` | **必须被判为"错误"的词** |
| `X.sug` | 对上一行的错词，**期望的建议列表** |

实测语料规模（tag `v1.7.4`）：`.good` **136** 个文件、`.wrong` **115** 个、`.sug` **37** 个、`.aff` **170** 个、`.dic` **171** 个。**语料按 tag 钉版本**（`HUNSPELL_REF=` 可覆盖）：上游 master 会前进，新套件会静默改变分母（2026-09-28 上游新增 `compoundaffixmorph`，6 行 `.good`，使总数 848→854 而通过率不变），钉住才能让文档里的绝对数字可复现。

> ⚠️ 注意：语料里的 `.aff` 常用 `SET ISO8859-1`（不是 UTF-8），且有
> 「规则条件末尾带空格」这类细节（例如 `SFX N y ication y ` 的条件是 `y`）。
> 解析器必须按 `SET` 指定的编码处理，并正确 trim 字段。

## CLI 契约（harness 依赖这个接口）

符合率脚本通过 CLI 批量判定单词，接口约定如下：

```bash
# 从 stdin 逐行读词，逐行输出判定结果：1 = 正确，0 = 错误
moon run cmd/main -- check --aff <path.aff> --dic <path.dic> --words - < words.txt
```

输出：每个输入词一行 `1` 或 `0`，顺序与输入一致。

**契约要点**
- 编码、词典加载只做一次，不要每个词重新加载（否则大词典上跑不完）。
- 无法加载词典或 `.aff` 解析失败时，退出码非 0 并打印错误（不要静默输出 0）。

## 运行

```bash
# 自动把 hunspell 浅克隆到临时目录
bash conformance/run.sh

# 或指定已有的 hunspell 检出目录（离线和 CI 缓存时用）
HUNSPELL_DIR=/path/to/hunspell bash conformance/run.sh
```

输出示例（格式固定，方便 diff）：

```
suite                     good            wrong
------------------------------------------------
base                      118/120         95/101
affix_condition           41/41            7/7
...                       (155 suites in total)
------------------------------------------------
TOTAL (155 suites)        847/854          611/613
```

## 计分口径：按判定计数，不按位置配对

CLI 对**每个非空输入行**恰好输出一个判定，所以判定可以**直接数**，不需要任何配对：

```bash
in_lines=$(grep -c . "$good"); out_lines=$(printf '%s\n' "$got" | grep -c .)
# 行数相等时，pass 就是 got 里 "^1$" 的行数
```

早期实现用 `paste -d' '` 把两个流按位置粘起来，于是**任何含空格的语料行都会错位**
并被无条件记为失败（`morph.good` 有 16 行 `drink eat` 这种）。`run.sh` 现在按判定计数，
**同时**打印历史的位置配对总数，两个口径并排可比：

| 口径 | `.good` | `.wrong` |
|---|---|---|
| 按判定计数（现行） | **847/854 = 99.2%** | **611/613 = 99.7%** |
| 按位置配对（历史，仅存档） | 831/854 = 97.3% | 611/613 = 99.7% |

`847 - 831 = 16`，正好是 `morph.good` 里含空格的行数：这是**度量假象**的大小，
不是行为差异。行尾带 TAB 的行（`utf8_bom.good`）两种口径都不受影响，
因为 `awk` 默认按空白切分。行数不等时 `run.sh` 会打印 `!` 警告并退回位置配对，
不会静默给出数字。

## 报告怎么用

1. **README 顶部的"Conformance"表格必须来自这里跑出的真实数字**，不许估。
2. CI 每次运行都会跑，历史数字可追踪。
3. 未通过的用例是下一期的修复清单——把失败用例的文件名记进 `DEVLOG.md`。

当前失败清单是**封闭的**，一共 7 个 `.good` 判定 + 2 个 `.wrong` 判定：

| 套件 | 词 | 方向 |
|---|---|---|
| `allcaps` | `OPENOFFICE.ORG`, `UNICEF'S`, `L'AFRIQUE` | 该接受却拒绝 |
| `allcaps_utf` | `OPENOFFICE.ORG`, `UNICEF'S` | 该接受却拒绝 |
| `allcaps2` | `IPOD` | 该接受却拒绝 |
| `hu` | `forróvíz-tartály` | 该接受却拒绝 |
| `allcaps2` | `iPodos` | 该拒绝却接受 |
| `limit-multiple-compounding` | `foobarbaz` | 该拒绝却接受 |

前 6 个都是同一件事：**全大写输入去匹配混合大小写的词典形式**（`OpenOffice.org`、
`iPod`）。`hunspell(5)` 只用 flag 记录了这个行为，没有给出算法，所以没有可实现的依据
（见 README「Not implemented yet」）。`hu` 那条是 `COMPOUNDFORBIDFLAG` 词干的匈牙利
"移动规则"。

## 建议生成：`conformance/suggest.sh`（`.sug`）

`.sug` 不是「一错词一行」，而是 `hunspell -a` 输出里 `&` 行的后段
（切掉 `& 原词 计数 偏移: `），并且**只保留有建议的词**；没有建议的词整行不存在。
所以 `.sug` 行号与 `.wrong` 行号**不能按位置配对**（例如 `rep` 11 个错词只有 8 行）。

`bash conformance/suggest.sh` 是**加法式**测量，绝不修改 `run.sh` 的 `.good`/`.wrong` 计算：

```bash
HUNSPELL_DIR=/path/to/hunspell bash conformance/suggest.sh
```

它定义的判据（README 表格里的 `.sug` 行）：

- **总数** = 所有 `.sug` 文件里的非空期望行（173）。
- **命中** = 该行第一个（最佳）建议，出现在某个错词返回的建议列表里；
  期望行与错词做**保序最大配对**（每行至多配一个错词，错词顺序递增），
  所以不要求在建议列表里排第一。实测 **141/173 = 81.5%**。
- 另附两个更严格的口径：期望最佳就是我们的第一条 **124/173 = 71.7%**；
  完整复现整个 `.sug` 文件（Hunspell 自己的判据）**7/37 套**。

度量本身要求 `python3`（只用来做配对和编码解码），缺失时会明确报错而不是给假数字。

## 与真实 hunspell 的差分测试：`conformance/differential.sh`

`run.sh` 用的是手写用例；差分测试回答的是另一个问题：**在一份真实词表上，我们到底
多常和 hunspell 不一致**。手写用例答不了这个。

```bash
bash conformance/differential.sh                 # 默认 /usr/share/dict/words
bash conformance/differential.sh path/to/words   # 指定词表
```

它把词典抓到临时目录（**不入库**），用本库和 `hunspell -l` 各判一遍，双向打印分歧：

- **该拒绝却接受**（我们太宽）——`FALSE ACCEPTS`
- **该接受却拒绝**（我们太严）——`FALSE REJECTS`

实测（`/usr/share/dict/words`，235,976 个非空行，en_US）：

| 指标 | 数量 | 占词表 |
|---|---|---|
| 本库拒绝 | 192,502 | — |
| hunspell 拒绝 | 192,699 | — |
| **该拒绝却接受** | **198** | **0.084%** |
| **该接受却拒绝** | **1** | **0.000%** |
| 合计分歧 | 199 | 0.084% |

两行方向相反，按定义读：那 1 个「该接受却拒绝」是 `Jean-Christophe`，即本库**比 hunspell 严**
的那一个词；198 个「该拒绝却接受」是本库**比 hunspell 宽松** —— 这些词 hunspell 判错、本库判对，
形如 `sparingness` / `winkered` / `towser` / `yester` 的 `-ness`/`-er`/`-ed` 派生形态
（本库的词缀引擎在 hunspell 不接受的词干上放行了这些后缀）。

这 198 个**不是回归**：在引入复合词的提交之前的 `git worktree` 上重跑同一测量，得到
完全相同的 198/1，即**新增 0、修复 0**。

脚本的退出码只反映"测量是否做得成"：分歧数是**结果**不是失败，所以有分歧也返回 0。
它**不进 CI**：一是需要系统装 hunspell，二是它不判定通过/失败，放进 CI 只会把
"测量"伪装成"门禁"。
