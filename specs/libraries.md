# 库、脚本与并发边界

本页索引 §19 与 §6.3；词法作用域和私有性见[词法结构](lexical-structure.md)。
条号依据[官方草案 PDF][pdf]；条款链接固定到[LaTeX 提交][spec]。语言兼容基线为 Dart 3.13.5。

状态含义见[总览](README.md#状态与证据)；库测试通过不代表整个 §19 已兼容。

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| [§19 Libraries and Scripts][libraries]：编译单元 | 部分实现 | 源库保留独立文件身份、声明和依赖；支持 `library` 声明。元数据、script tag 和完整顶层声明文法未覆盖。 | [source.dart](../lib/src/source.dart)、[parser.dart](../lib/src/parser.dart)；[behavior_test.dart](../test/behavior_test.dart) |
| [§19.1 Imports][imports] | 部分实现 | 支持立即导入、`as` 前缀及显式/隐式 `dart:core` 处理；系统库只提供当前实现的声明，不等于完整 SDK 库。 | [source.dart](../lib/src/source.dart)、[symbols.dart](../lib/src/symbols.dart)；[behavior_test.dart](../test/behavior_test.dart) 的 `imports.dart`、`core.dart` |
| [§19.1.1 The Imported Namespace][imported] | 部分实现 | 按读取与写入分别解析 getter/setter，可组合独立来源的两侧；本库任一同名声明遮蔽导入两侧，前缀和私有性保持来源身份。扩展及完整命名空间组合尚缺。 | [symbols.dart](../lib/src/symbols.dart) 的 `resolveSymbol`、`resolveWriteSymbol`；[behavior_test.dart](../test/behavior_test.dart) 的 `top-accessor-imports.dart`、`rejected` |
| [§19.1.2 Semantics of Imports][import-semantics]：延迟导入 | 未实现 | `deferred` 被拒绝；没有 `loadLibrary`、加载状态及相应调用时序。 | [parser.dart](../lib/src/parser.dart)；[behavior_test.dart](../test/behavior_test.dart) 的 deferred 拒绝用例 |
| [§19.2 Exports][exports] | 部分实现 | 支持导出、再导出与过滤，读写保留原声明来源；本库声明缺少所需读/写侧时继续查找再导出。导出冲突的全库声明检查仍缺，循环导出和扩展成员尚缺系统验证。 | [source.dart](../lib/src/source.dart)、[symbols.dart](../lib/src/symbols.dart)；[behavior_test.dart](../test/behavior_test.dart) 的 `exports.dart`、`top-accessor-imports.dart`、`export-priority.dart` |
| [§19.3 Namespace Combinators][combinators] | 部分实现 | `show` / `hide` 按指令顺序以 basename 同时过滤 getter/setter 两侧；尚无扩展声明过滤。 | [source.dart](../lib/src/source.dart) 的 `sourceAllows`；[behavior_test.dart](../test/behavior_test.dart) 的 `top-accessor-imports.dart`、`rejected` |
| [§19.4 Conflict Merging of Namespaces][conflicts] | 部分实现 | 同一声明可合并，普通库与系统库按 basename 决定优先级；当前按消费的读/写侧判断歧义，指令顺序不选择目标。完整前缀冲突、扩展及声明时导出冲突规则尚缺。 | [symbols.dart](../lib/src/symbols.dart) 的 `symbolMerge`；[behavior_test.dart](../test/behavior_test.dart) 的 priority、prefix-priority、`top-accessor-imports.dart` 用例 |
| [§19.2][exports]、[§19.4][conflicts]：访问器冲突差异 | 待核对 | 固定草案的 basename 规则与 SDK 3.13.5 analyzer/CFE 不完全一致：一个库提供 getter+setter，另一个仅 getter，仅写该名时交换 import 或 export 顺序可改变 CFE 结果；analyzer 对两种 export 顺序都报告冲突。本实现不仿该顺序选择，不能据此声称完整命名空间兼容。 | [官方固定草案][spec]；[symbols.dart](../lib/src/symbols.dart)；[behavior_test.dart](../test/behavior_test.dart) 为后续差分入口 |
| [§19.5 Parts][parts] | 未实现 | 未解析 `part` / `part of`，没有多编译单元共享同一库作用域、私有性和重复 part 校验。 | [parser.dart](../lib/src/parser.dart)、[source.dart](../lib/src/source.dart)；尚无对应正向行为验证 |
| [§19.6 Scripts][scripts] | 部分实现 | 从导出空间查找 `main`，支持至多两个必需位置参数及可选/命名默认值；当前第一位置实参为 `List<String>`，第二位置实参固定为 `null`。isolate 启动载荷和完整脚本调用语义尚未验收。 | [frontend.dart](../lib/src/frontend.dart) 的 `feGenerateEntry`；[behavior_test.dart](../test/behavior_test.dart) 的 named-entry、two-entry、invalid-entry 与 argv 用例 |
| [§19.7 URIs][uris] | 部分实现 | 处理相对/绝对文件路径及 `dart:core`、`dart:ffi`；缺 `package:`、`file:` URI、条件 URI 和完整 URI 规范化。 | [source.dart](../lib/src/source.dart)、[parser.dart](../lib/src/parser.dart)；[behavior_test.dart](../test/behavior_test.dart) 的路径归一与不支持 URI 拒绝用例 |
| [§6.3 Concurrency][concurrency] | 未实现 | 原生产物没有 isolates、消息端口、spawn 和独立隔离堆；未提供 `dart:isolate` 的程序执行能力。 | [source.dart](../lib/src/source.dart)、[runtime.dart](../lib/src/runtime.dart)；尚无 isolate 原生行为验证 |
| [§19][libraries]：完整命名空间与 URI 组合 | 待核对 | 当前用例覆盖有限的导入图和优先级；未形成完整规范兼容性测试，不能从单一导入程序成功推断一般库系统已完成。 | [behavior_test.dart](../test/behavior_test.dart)；后续补充仍以真实多文件编译执行为依据 |

## 验证边界

`behavior_test.dart` 中的多文件程序对照官方 Dart；拒绝用例只证明当前诊断边界。
[library_test.dart](../test/library_test.dart) 验证原生静态/动态链接调用，不是 Dart §19 的库命名空间兼容证据。

[pdf]: https://dart.dev/to/spec-draft
[spec]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex
[libraries]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L18416
[imports]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L18544
[imported]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L18627
[import-semantics]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L18818
[exports]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L18980
[combinators]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L19084
[conflicts]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L19172
[parts]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L19265
[scripts]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L19336
[uris]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L19386
[concurrency]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L1170
