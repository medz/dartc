# 库、脚本与并发边界

本页索引 §19 与 §6.3；词法作用域和私有性见[词法结构](lexical-structure.md)。
条号依据[官方草案 PDF][pdf]；条款链接固定到[固定 LaTeX 源码][spec]。SDK 对照版本见[总览](README.md)。

状态含义见[总览](README.md#状态与证据)。

## 编译单元与库指令语法表示

`package:dartc/ast.dart` 可构造以下语法。构造器检查源码范围、快照归属和子节点顺序，不解析文本或检查库结构是否合法。

| 语言条款 | 可表示的语法 | 验证 |
| --- | --- | --- |
| §19 库与编译单元、§19.6 脚本 | 完整文件范围、可选 `#!` 脚本标记、按源码顺序排列的指令和顶层声明；保留空文件、注释、BOM 和行尾范围 | [unit_test.dart](../test/ast/unit_test.dart) |
| §19 库声明 | 元数据、具名 `library a.b;` 与无名 `library;` | [directives_test.dart](../test/ast/directives_test.dart) |
| §19.1 导入、§19.3 导出 | 元数据、URI、条件 URI、可选 `deferred` 与导入前缀、有序 `show` / `hide` 名单；保留重复名称及省略的条件比较值 | [directives_test.dart](../test/ast/directives_test.dart) |
| §19.5 Parts | `part` 的 URI，以及 `part of` 的 URI 或点分库名；URI 保留相邻字符串结构 | [directives_test.dart](../test/ast/directives_test.dart) |

错误位置的指令和 URI 中的插值也可保留为语法节点，供后续诊断；这不表示语言允许这些写法。URI 解码、条件选择与 part 归属检查见[库装入 API](#库装入-api)；命名空间绑定尚未接入这些节点。编译与执行支持以下表为准。

## 编译单元解析 API

`package:dartc/parser.dart` 的 `parseCompilationUnit(ScanResult)` 返回 `ParseResult<CompilationUnit>`，保留完整文件范围、脚本标记和源码顺序中的指令与声明。

| 语言条款 | 当前解析支持 | 验证 |
| --- | --- | --- |
| §19、§19.6 | 完整文件、空文件、`#!` 脚本标记、具名或无名 library；声明元数据 | [compilation_units_test.dart](../test/parser/compilation_units_test.dart) 文件与指令用例 |
| §19.1、§19.3、§19.7 | import/export、条件 URI、deferred/as 前缀、show/hide；字符串保留 raw、多行与相邻形式，拒绝插值 | [compilation_units_test.dart](../test/parser/compilation_units_test.dart) URI 与命名空间用例 |
| §19.5 | part、URI 或点分名称的 part of；检查指令顺序，保留误放的指令并报告诊断 | [compilation_units_test.dart](../test/parser/compilation_units_test.dart) part 与恢复用例 |

解析不加载依赖或解析 URI，不检查命名空间冲突和 part 的实际归属。文件内的表达式、语句、模式和 switch 沿用各自的解析范围。缺失声明和字符串分别以 `MissingTopLevelDeclaration`、`MissingStringExpression` 表示；调用方须检查 `hasErrors`。

## 库装入 API

`package:dartc/project.dart` 的 `ProjectLoader.load` 从绝对入口 URI 装入库图，返回不可变的 `Project`、各库的定义单元与有序 parts、选中的依赖边及诊断。输入由 `SourceProvider` 提供；`dart:` 源码与条件环境由调用方明确提供，不从宿主运行时推断可用库。文件提供者 `readFileSource` 按 UTF-8 读取，保留 BOM 和行结束符，损坏编码转为替换字符。

| 语言条款 | 当前装入支持 | 验证 |
| --- | --- | --- |
| §19.7 URI、[包配置 v2][package-config] | 相对 URI、`file:`、`package:`、`dart:` 与自定义来源；按 URI 规则解析路径、转义和包映射，保留逻辑 URI，不用符号链接或物理路径合并库身份。包配置支持相对根、暴露目录、嵌套包归属和语言版本；重复名称与冲突目录产生错误 | [uris_test.dart](../test/project/uris_test.dart)、[packages_test.dart](../test/project/packages_test.dart)、[files_test.dart](../test/project/files_test.dart) |
| §19.1、§19.3 导入与导出 | 装入选中库，保留 deferred、前缀和 show/hide 的 AST；未显式导入 `dart:core` 的非 core 库加入隐式 core 依赖。合法循环与共享依赖不会重复装入 | [loading_test.dart](../test/project/loading_test.dart)、[graph_test.dart](../test/project/graph_test.dart) |
| §19.7 条件 URI | 按源码顺序选择首个匹配分支，无匹配使用默认 URI；未定义环境值视为空字符串，省略比较值时与 `"true"` 比较。只读取选中来源，其余分支仍接受词法与语法检查 | [loading_test.dart](../test/project/loading_test.dart) |
| §19.5 Parts | 以 URI 或库名检查 part-of 归属，检查缺失 part-of、重复包含、跨库共用、导入 part、part 中的非法指令及语言版本不一致 | [parts_test.dart](../test/project/parts_test.dart)、[versions_test.dart](../test/project/versions_test.dart) |

`findPackageConfiguration` 从入口目录逐级向上寻找最近的 `.dart_tool/package_config.json`；找到但无效时报告错误，不退回更远配置。旧 `.packages` 格式不在此 API 的支持范围。URI 和 JSON 格式错误使用 `FormatException`；装入过程中的缺失文件、读取异常和源程序错误收集为诊断，调用方须检查 `Project.hasErrors`。

同一 loader 的配置固定；每次装入重新读取可达源码，内容和语言版本未变时复用同一 `LibraryUnit` 与源码快照。每份结果独立保留自己的 AST 和诊断，只有最新启动的装入更新缓存；旧异步请求不能覆盖新缓存。缓存只保留该次可达文件，`clear` 释放缓存。验证见 [reuse_test.dart](../test/project/reuse_test.dart)。

库图尚未执行命名空间合并、名称绑定、类型与常量检查。装入 deferred 依赖表示其源码可供静态检查，不代表已实现执行时的延迟加载；读取 SDK 源码也不代表相应标准库已经能够编译执行。

## 编译与执行

| 规范条目 | 状态 | 支持范围与缺口 | 验证 |
| --- | --- | --- | --- |
| [§19 Libraries and Scripts][libraries]：编译单元 | 部分实现 | 库与物理源文件分别保留身份、声明和依赖；支持具名 `library` 声明，`library;` 要求[文件版本至少 2.19][features]。元数据覆盖[已实现声明子集](classes.md)，文件头的 script tag 范围见[词法结构](lexical-structure.md)；完整顶层声明文法未覆盖。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) |
| [§19.1 Imports][imports] | 部分实现 | 支持立即导入、`as` 前缀及显式/隐式 `dart:core` 处理；可执行文件的 core 入口通过真实 Dart export 提供 StringBuffer、StackTrace 与 pragma 声明，原生内建类型仍保留系统身份。前缀、再导出和用户同名遮蔽按实际声明来源处理；这不是完整 SDK 库。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `imports.dart`、`core.dart` |
| [§19.1 前缀声明][imports]、[§19.1.1 前缀命名空间][imported] | 部分实现 | 声明收集后拒绝 import 前缀与本库或 part 的同 basename 顶层声明重名，包括 setter；同一前缀可组合多个普通 import，未使用的组内歧义不报错。前缀遮蔽同名未加前缀导入及隐式 core 声明，不能作为值、赋值目标或类型使用；局部变量、参数、类型参数和成员仍可遮蔽前缀。[3.7 通配前缀][wildcard-imports] `_` 不绑定可访问名称，旧版本仍可使用 `_.member`；按 SDK 3.13.7，通配前缀仍参与与顶层 `_` 的声明冲突检查。扩展导入及 deferred 行为仍缺。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `prefix-scope.dart`、`prefix-old.dart`、`prefix-wildcards.dart`、`rejectedPrefixes`、`prefix-part-conflict.dart` |
| [§19.7 Conditional URIs][conditional] | 部分实现 | import/export 支持默认 URI 与有序 `if` 条件；按字符串值选择首个匹配，缺省比较 `"true"`，无匹配用默认。所有分支均检查字面量语法并拒插值，仅装入选中库。环境由显式目标给出：core 和现有受限 ffi 注册为 `"true"`，io/isolate/js 等未提供；不继承宿主 VM 能力。自定义环境及 String.fromEnvironment API 未实现。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `conditional-imports.dart`、`conditional-target-io.dart`、`rejected` |
| [§19.1.1 The Imported Namespace][imported] | 部分实现 | 按读取与写入分别解析 getter/setter，可组合独立来源的两侧；本库任一同名声明遮蔽导入两侧，前缀和私有性保持来源身份。扩展及完整命名空间组合尚缺。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `top-accessor-imports.dart`、`rejected` |
| [§19.1.2 Semantics of Imports][import-semantics]：延迟导入 | 未实现 | `deferred` 被拒绝；没有 `loadLibrary`、加载状态及相应调用时序。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 deferred 拒绝用例 |
| [§19.2 Exports][exports] | 部分实现 | 支持导出、再导出与过滤，读写保留原声明来源；本库声明缺少所需读/写侧时继续查找再导出。声明收集后检查所有已加载库的公开导出名称，任一读/写侧冲突即报错，不依赖名称被使用；调用方过滤不能掩盖被导出库自身的冲突。同一声明的菱形再导出、循环、过滤和 part 声明遮蔽已有行为验证；扩展成员及下述 basename 差异仍缺。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `exports.dart`、`top-accessor-imports.dart`、`export-priority.dart`、`export-names-imports.dart`、`rejectedExports` |
| [§19.3 Namespace Combinators][combinators] | 部分实现 | `show` / `hide` 按指令顺序以 basename 同时过滤 getter/setter 两侧；尚无扩展声明过滤。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `top-accessor-imports.dart`、`rejected` |
| [§19.4 Conflict Merging of Namespaces][conflicts] | 部分实现 | 同一声明可合并，普通库与系统库按 basename 决定优先级；读写分别判断歧义，指令顺序不选择目标。导出在声明收集后检查两侧，import 仍只在消费冲突名称时报错；完整前缀冲突及扩展命名空间尚缺。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 priority、prefix-priority、`top-accessor-imports.dart` 用例 |
| [§19.2][exports]、[§19.4][conflicts]：访问器冲突差异 | 待核对 | 固定草案的 basename 规则与 SDK 3.13.5 analyzer/CFE 不完全一致：一个库提供 getter+setter，另一个仅 getter，仅写该名时交换 import 或 export 顺序可改变 CFE 结果；analyzer 对两种 export 顺序都报告冲突。本实现不仿该顺序选择，不能据此声称完整命名空间兼容。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 为差分入口 |
| [§19.5 Parts][parts] | 部分实现 | 支持 URI 与具名 `part of`，同库声明、导入前缀及私有成员共享；物理文件仍保留独立 URI、token 与诊断。纳入前检查匹配的库身份；版本沿各物理文件的 package/header 计算，要求版本及 marker 是否存在均一致，拒绝重复/跨库 part、part 内其他 directive 及直接导入 part。augmentation 与完整库文法仍未覆盖。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `parts-main.dart`、`rejected` |
| [§19.6 Scripts][scripts] | 部分实现 | 从导出空间查找 `main`，支持至多两个必需位置参数及可选/命名默认值；当前第一位置实参为 `List<String>`，第二位置实参固定为 `null`。isolate 启动载荷和完整脚本调用语义尚未验收。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 named-entry、two-entry、invalid-entry 与 argv 用例 |
| [语言版本与包配置][versioning] | 部分实现 | 读取 [package configuration v2][packages]；从入口目录向上选择最近配置，或由 `--packages` 显式指定，整次编译只读取一次。包根覆盖 bin/test 等文件，最深根决定默认 `languageVersion`，文件头可覆盖；使用不支持版本的包仍报错，未使用的未来版本包不阻断编译。无配置时默认 3.13，不解析 pubspec 或旧 `.packages`，不求解和下载依赖；范围见[词法结构](lexical-structure.md)。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 package 配置及版本用例 |
| [§19.7 URIs][uris] | 部分实现 | 支持本地相对 URI、`file:`、`package:` 及 `dart:core`、`dart:ffi`，处理点段、百分号 UTF-8、包根约束。库身份按规范 URI 保存：同一规范 file/relative URI 合并，package 保留包身份，内部双斜线及保留字符编码差异不被磁盘路径归一吞掉；包内相对 URI 按 package 基址解析。非本地 scheme/authority 清晰拒绝，非本地加载及完整 URI 组合验收仍缺。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 package 身份、包内相对 URI 与不支持 URI 拒绝用例 |
| [§6.3 Concurrency][concurrency] | 未实现 | 原生产物没有 isolates、消息端口、spawn 和独立隔离堆；未提供 `dart:isolate` 的程序执行能力。 | 待补充 |
| [§19][libraries]：完整命名空间与 URI 组合 | 待核对 | 导入图、命名空间优先级及 URI 组合的完整一致性覆盖尚缺。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) |

package v2 的重复名称、重复规范化根及嵌套根约束在配置边界检查。包数组顺序不影响大小写敏感的名称查找或最深根的文件归属；`behavior_test.dart` 的 package 用例覆盖多层嵌套、相邻目录前缀、根外文件、空配置和乱序配置。SDK 3.13.5 在未使用重叠包时接受部分无效配置，本实现按[固定 v2 格式][packages]拒绝库目录包含嵌套根或位于嵌套根中的两种重叠；行为测试明确区分该差异，不将其报告为 SDK 完全一致。

[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 拥有 Dart 库的多文件行为；[library_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/library_test.dart) 拥有原生静态/动态链接调用，两者验证范围不同。

没有显式 `dartc` 包映射时，提供内置的 `package:dartc/export.dart`；包配置中的映射优先。独立二进制、传递依赖、part、显式覆盖和包映射的行为验证由 [package_release_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/package_release_test.dart) 拥有。

## StackTrace API

| SDK 条目 | 状态 | 支持范围与缺口 | 验证 |
| --- | --- | --- | --- |
| [`StackTrace.current`][stack-current] | 部分实现 | 同步捕获当前 Dart 调用链，保留直接调用、递归、闭包和函数值调用；返回独立的不可变轨迹。文本按栈顺序列出函数名，可能包含编译器生成的调用适配器；尚无文件/行号、异步调用链和原生边界轨迹。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `stackTraceValues()`；[roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart) `stackTraceRoots()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) NoGC 拒例 |
| [`StackTrace.fromString`][stack-string]、[`empty`][stack-empty]、[`toString`][stack-text] | 部分实现 | `fromString` 保留任意 String，`toString` 返回原文本；`empty` 为可在常量上下文使用的空轨迹。当前用普通 Dart 类及非 const 命名构造器提供 API；SDK 的抽象接口、factory 重定向及用户实现 StackTrace 仍依赖尚缺的类/接口语义。同步抛出携带轨迹，rethrow 保留同一轨迹对象；异常语言边界见[语句](statements.md)。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `stackTraceValues()` |

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
[features]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.19/unnamed-libraries/feature-specification.md

[packages]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.8/language-versioning/package-config-file-v2.md

[conditional]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L21006-L21071

[wildcard-imports]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/wildcard-variables/feature-specification.md#imports

[package-config]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.8/language-versioning/package-config-file-v2.md
