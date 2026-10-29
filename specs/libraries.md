# 库、脚本与并发边界

本页索引 §19 与 §6.3；词法作用域和私有性见[词法结构](lexical-structure.md)。
条号依据[官方草案 PDF][pdf]；条款链接固定到[固定 LaTeX 源码][spec]。SDK 对照版本见[总览](README.md)。

状态含义见[总览](README.md#状态与证据)。

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| [§19 Libraries and Scripts][libraries]：编译单元 | 部分实现 | 库与物理源文件分别保留身份、声明和依赖；支持具名 `library` 声明，`library;` 要求[文件版本至少 2.19][features]。元数据覆盖[已实现声明子集](classes.md)，文件头的 script tag 范围见[词法结构](lexical-structure.md)；完整顶层声明文法未覆盖。 | [source.dart](../lib/src/source.dart)、[parser.dart](../lib/src/parser.dart)；[behavior_test.dart](../test/behavior_test.dart) |
| [§19.1 Imports][imports] | 部分实现 | 支持立即导入、`as` 前缀及显式/隐式 `dart:core` 处理；可执行文件的 core 入口通过真实 Dart export 提供 StringBuffer、StackTrace 与 pragma 声明，原生内建类型仍保留系统身份。前缀、再导出和用户同名遮蔽按实际声明来源处理；这不是完整 SDK 库。 | [source.dart](../lib/src/source.dart)、[symbols.dart](../lib/src/symbols.dart)；[behavior_test.dart](../test/behavior_test.dart) 的 `imports.dart`、`core.dart`；[core.dart](../lib/src/std/core.dart) |
| [§19.7 Conditional URIs][conditional] | 部分实现 | import/export 支持默认 URI 与有序 `if` 条件；按字符串值选择首个匹配，缺省比较 `"true"`，无匹配用默认。所有分支均检查字面量语法并拒插值，仅装入选中库。环境由显式目标给出：core 和现有受限 ffi 注册为 `"true"`，io/isolate/js 等未提供；不继承宿主 VM 能力。自定义环境及 String.fromEnvironment API 未实现。 | [ast.dart](../lib/src/ast.dart) `AstConditionalUri`；[parser.dart](../lib/src/parser.dart) `parserDirective`；[source.dart](../lib/src/source.dart) `sourceTargetLibraries`、`sourceDirectiveUri`；[behavior_test.dart](../test/behavior_test.dart) `conditional-imports.dart`、`conditional-target-io.dart`、`rejected` |
| [§19.1.1 The Imported Namespace][imported] | 部分实现 | 按读取与写入分别解析 getter/setter，可组合独立来源的两侧；本库任一同名声明遮蔽导入两侧，前缀和私有性保持来源身份。扩展及完整命名空间组合尚缺。 | [symbols.dart](../lib/src/symbols.dart) 的 `resolveSymbol`、`resolveWriteSymbol`；[behavior_test.dart](../test/behavior_test.dart) 的 `top-accessor-imports.dart`、`rejected` |
| [§19.1.2 Semantics of Imports][import-semantics]：延迟导入 | 未实现 | `deferred` 被拒绝；没有 `loadLibrary`、加载状态及相应调用时序。 | [parser.dart](../lib/src/parser.dart)；[behavior_test.dart](../test/behavior_test.dart) 的 deferred 拒绝用例 |
| [§19.2 Exports][exports] | 部分实现 | 支持导出、再导出与过滤，读写保留原声明来源；本库声明缺少所需读/写侧时继续查找再导出。声明收集后检查所有已加载库的公开导出名称，任一读/写侧冲突即报错，不依赖名称被使用；调用方过滤不能掩盖被导出库自身的冲突。同一声明的菱形再导出、循环、过滤和 part 声明遮蔽已有行为验证；扩展成员及下述 basename 差异仍缺。 | [source.dart](../lib/src/source.dart)、[symbols.dart](../lib/src/symbols.dart)；[behavior_test.dart](../test/behavior_test.dart) 的 `exports.dart`、`top-accessor-imports.dart`、`export-priority.dart`、`export-names-imports.dart`、`rejectedExports`；[symbols.dart](../lib/src/symbols.dart) 的 `checkExportConflicts` |
| [§19.3 Namespace Combinators][combinators] | 部分实现 | `show` / `hide` 按指令顺序以 basename 同时过滤 getter/setter 两侧；尚无扩展声明过滤。 | [source.dart](../lib/src/source.dart) 的 `sourceAllows`；[behavior_test.dart](../test/behavior_test.dart) 的 `top-accessor-imports.dart`、`rejected` |
| [§19.4 Conflict Merging of Namespaces][conflicts] | 部分实现 | 同一声明可合并，普通库与系统库按 basename 决定优先级；读写分别判断歧义，指令顺序不选择目标。导出在声明收集后检查两侧，import 仍只在消费冲突名称时报错；完整前缀冲突及扩展命名空间尚缺。 | [symbols.dart](../lib/src/symbols.dart) 的 `symbolMerge`；[behavior_test.dart](../test/behavior_test.dart) 的 priority、prefix-priority、`top-accessor-imports.dart` 用例 |
| [§19.2][exports]、[§19.4][conflicts]：访问器冲突差异 | 待核对 | 固定草案的 basename 规则与 SDK 3.13.5 analyzer/CFE 不完全一致：一个库提供 getter+setter，另一个仅 getter，仅写该名时交换 import 或 export 顺序可改变 CFE 结果；analyzer 对两种 export 顺序都报告冲突。本实现不仿该顺序选择，不能据此声称完整命名空间兼容。 | [官方固定草案][spec]；[symbols.dart](../lib/src/symbols.dart)；[behavior_test.dart](../test/behavior_test.dart) 为差分入口 |
| [§19.5 Parts][parts] | 部分实现 | 支持 URI 与具名 `part of`，同库声明、导入前缀及私有成员共享；物理文件仍保留独立 URI、token 与诊断。纳入前检查匹配的库身份；版本沿各物理文件的 package/header 计算，要求版本及 marker 是否存在均一致，拒绝重复/跨库 part、part 内其他 directive 及直接导入 part。augmentation 与完整库文法仍未覆盖。 | [parser.dart](../lib/src/parser.dart)、[source.dart](../lib/src/source.dart)、[symbols.dart](../lib/src/symbols.dart)；[behavior_test.dart](../test/behavior_test.dart) 的 `parts-main.dart`、`rejected` |
| [§19.6 Scripts][scripts] | 部分实现 | 从导出空间查找 `main`，支持至多两个必需位置参数及可选/命名默认值；当前第一位置实参为 `List<String>`，第二位置实参固定为 `null`。isolate 启动载荷和完整脚本调用语义尚未验收。 | [frontend.dart](../lib/src/frontend.dart) 的 `feGenerateEntry`；[behavior_test.dart](../test/behavior_test.dart) 的 named-entry、two-entry、invalid-entry 与 argv 用例 |
| [语言版本与包配置][versioning] | 部分实现 | 读取 [package configuration v2][packages]；从入口目录向上选择最近配置，或由 `--packages` 显式指定，整次编译只读取一次。包根覆盖 bin/test 等文件，最深根决定默认 `languageVersion`，文件头可覆盖；使用不支持版本的包仍报错，未使用的未来版本包不阻断编译。实现输入 runtime/core 保持自身默认版本。无配置时默认 3.13，不解析 pubspec 或旧 `.packages`，不求解和下载依赖；范围见[词法结构](lexical-structure.md)。 | [package_config.dart](../lib/src/package_config.dart)、[packages.dart](../lib/src/driver/packages.dart) `compilerPackages()`、[command.dart](../lib/src/driver/command.dart)、[source.dart](../lib/src/source.dart)；[behavior_test.dart](../test/behavior_test.dart) 的 package 配置及版本用例 |
| [§19.7 URIs][uris] | 部分实现 | 支持本地相对 URI、`file:`、`package:` 及 `dart:core`、`dart:ffi`，处理点段、百分号 UTF-8、包根约束。库身份按规范 URI 保存：同一规范 file/relative URI 合并，package 保留包身份，内部双斜线及保留字符编码差异不被磁盘路径归一吞掉；包内相对 URI 按 package 基址解析。非本地 scheme/authority 清晰拒绝，非本地加载及完整 URI 组合验收仍缺。 | [source_uri.dart](../lib/src/source_uri.dart)、[source.dart](../lib/src/source.dart)；[behavior_test.dart](../test/behavior_test.dart) 的 package 身份、包内相对 URI 与不支持 URI 拒绝用例 |
| [§6.3 Concurrency][concurrency] | 未实现 | 原生产物没有 isolates、消息端口、spawn 和独立隔离堆；未提供 `dart:isolate` 的程序执行能力。 | [source.dart](../lib/src/source.dart)、[runtime.dart](../lib/src/runtime.dart)；尚无 isolate 原生行为验证 |
| [§19][libraries]：完整命名空间与 URI 组合 | 待核对 | 导入图、命名空间优先级及 URI 组合的完整一致性覆盖尚缺。 | [behavior_test.dart](../test/behavior_test.dart) |

package v2 的嵌套根约束在配置边界检查。SDK 3.13.5 在未使用重叠包时接受部分无效配置，本实现按[固定 v2 格式][packages]拒绝；行为测试明确区分该差异，不将其报告为 SDK 完全一致。

[behavior_test.dart](../test/behavior_test.dart) 拥有 Dart 库的多文件行为；[library_test.dart](../test/library_test.dart) 拥有原生静态/动态链接调用，两者验证范围不同。

## StackTrace API

| SDK 条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| [`StackTrace.current`][stack-current] | 部分实现 | 同步捕获当前 Dart 调用链，保留直接调用、递归、闭包和函数值调用；返回独立的不可变轨迹。文本按栈顺序列出函数名，可能包含编译器生成的调用适配器；尚无文件/行号、异步调用链和原生边界轨迹。实现位于 Dart 运行时，不依赖 SDK 或系统符号器。 | [frames.dart](../lib/src/runtime/frames.dart) `rtStackTraceString()`；[values.dart](../test/fixtures/values.dart) `stackTraceValues()`；[roots.dart](../test/fixtures/roots.dart) `stackTraceRoots()`；[behavior_test.dart](../test/behavior_test.dart) NoGC 拒例 |
| [`StackTrace.fromString`][stack-string]、[`empty`][stack-empty]、[`toString`][stack-text] | 部分实现 | `fromString` 保留任意 String，`toString` 返回原文本；`empty` 为可在常量上下文使用的空轨迹。当前用普通 Dart 类及非 const 命名构造器提供 API；SDK 的抽象接口、factory 重定向及用户实现 StackTrace 仍依赖尚缺的类/接口语义。同步抛出携带轨迹，rethrow 保留同一轨迹对象；异常语言边界见[语句](statements.md)。 | [stack_trace.dart](../lib/src/std/core/stack_trace.dart)；[values.dart](../test/fixtures/values.dart) `stackTraceValues()` |

[stack-current]: https://api.dart.dev/stable/3.13.7/dart-core/StackTrace/current.html
[stack-string]: https://api.dart.dev/stable/3.13.7/dart-core/StackTrace/StackTrace.fromString.html
[stack-empty]: https://api.dart.dev/stable/3.13.7/dart-core/StackTrace/empty-constant.html
[stack-text]: https://api.dart.dev/stable/3.13.7/dart-core/StackTrace/toString.html

[pdf]: https://dart.dev/to/spec-draft
[spec]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex
[libraries]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L19943
[imports]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L20085
[imported]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L20176
[import-semantics]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L20388
[exports]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L20562
[combinators]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L20675
[conflicts]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L20771
[parts]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L20872
[scripts]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L20950
[uris]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L21007
[concurrency]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L1239

[versioning]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.8/language-versioning/feature-specification.md
[features]: https://github.com/dart-lang/sdk/blob/3.13.5/tools/experimental_features.yaml

[packages]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.8/language-versioning/package-config-file-v2.md

[conditional]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L21006-L21071
