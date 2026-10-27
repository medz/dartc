# 词法结构、作用域与错误

本页索引 §6.1、§6.2、§7、§21，记录实现范围与验证入口，不替代规范正文。
条号依据[官方草案 PDF][pdf]；条款链接固定到[LaTeX 提交][spec]。语言兼容基线为 Dart 3.13.5；文件版本选择见下表，不代表完整旧语言兼容。

“部分实现”只说明已有实现路径；“待核对”表示尚缺足够的一致性证据，均不表示整条规范已满足。

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| [§21.1 Lexical Rules][lexical]：字符与 token | 部分实现 | token 保留来源和 UTF-16 区间；已有整数、字符串及所支持运算符扫描，完整词法及非法输入边界尚未覆盖。 | [scanner.dart](../lib/src/scanner.dart)；[behavior_test.dart](../test/behavior_test.dart) |
| [§21.1 Lexical Rules][lexical]：字面量扫描 | 部分实现 | 支持 raw、三引号、转义、插值与相邻字符串；浮点字面量未实现，转义范围和换行边界仍需逐项核对。字面量语义归表达式章节。 | [scanner.dart](../lib/src/scanner.dart)、[parser.dart](../lib/src/parser.dart)；[values.dart](../test/fixtures/values.dart) |
| [Dart 3.6 数字分隔符][separators] | 部分实现 | 文件版本至少 3.6 时，十进制和十六进制整数的数字间允许一个或多个下划线；前缀后、尾部及非数字边界被拒绝。token 保留原 UTF-16 区间，整数文本在扫描边界去除分隔符；浮点和指数形式尚未实现，字符串 `int.parse` 不因该词法特性改变。 | [scanner.dart](../lib/src/scanner.dart)；[values.dart](../test/fixtures/values.dart) 的 `Box.arguments`、`staticContexts`；[behavior_test.dart](../test/behavior_test.dart) 的拒绝用例 |
| [§21.1.1 Reserved Words][reserved] | 部分实现 | parser 在部分文法位置区分关键字与名称；保留字、内建标识符作为声明名或类型名的限制尚不完整。 | [parser.dart](../lib/src/parser.dart)、[resolve_type.dart](../lib/src/resolve_type.dart)；[behavior_test.dart](../test/behavior_test.dart) |
| [语言版本选择][versioning] | 部分实现 | 每个源文件独立选择 2.12–3.13，未标记时采用[所属包的默认版本](libraries.md)，包未指定版本时为 3.13；只采用代码或指令前首个完整的 `// @dart = M.m`。`///`、块注释、含补丁号或其他尾随内容的注释不作标记，后续标记不覆盖首个有效标记；不改写源文本或 UTF-16 偏移。导入方不覆盖被导入文件的默认版本。 | [scanner.dart](../lib/src/scanner.dart) `scanHeader()`、`scanLanguageVersion()`；[source.dart](../lib/src/source.dart) `sourceLoad()`；[behavior_test.dart](../test/behavior_test.dart) 的 `version-header.dart`、`version-markers.dart` 与版本拒绝用例 |
| [§21.1.2 Comments][comments] | 部分实现 | 扫描单行和嵌套块注释，并拒绝未闭合块注释；嵌套层次、行结束符等边界缺完整行为覆盖。 | [scanner.dart](../lib/src/scanner.dart)；[behavior_test.dart](../test/behavior_test.dart) 中的库指令注释用例 |
| [版本化运算符][features] | 部分实现 | `>>>` / `>>>=` 要求文件版本至少 2.14；嵌套泛型的连续右尖括号仍按类型文法解析。没有实现其余所有版本化语法。 | [scanner.dart](../lib/src/scanner.dart)、[parser.dart](../lib/src/parser.dart)；[behavior_test.dart](../test/behavior_test.dart) 的 `version-header.dart`、`version-imports.dart` 与拒绝用例 |
| [§21.2 Operator Precedence][precedence] | 部分实现 | 已支持运算符按递归下降解析，含 `is`/`as`、`??`、条件与赋值；级联、空感知访问等文法未实现，不能视为完整运算符表。 | [parser.dart](../lib/src/parser.dart)；[values.dart](../test/fixtures/values.dart)、[behavior_test.dart](../test/behavior_test.dart) |
| [§6.1 Scoping][scoping]：局部名称 | 部分实现 | 按 binding ID 处理块、参数、循环、switch 分支与 label 作用域，预收集声明及检查重复；闭包、局部函数和模式绑定尚未实现。 | [binding.dart](../lib/src/binding.dart)；[values.dart](../test/fixtures/values.dart) 的绑定用例及 [behavior_test.dart](../test/behavior_test.dart) 的前向引用拒绝用例 |
| [§6.1 Scoping][scoping]：库与成员名称 | 部分实现 | 库名解析和局部到成员查找已有路径；继承、扩展成员等完整查找规则仍缺失。库命名空间另见[库与脚本](libraries.md)。 | [symbols.dart](../lib/src/symbols.dart)、[frontend.dart](../lib/src/frontend.dart)；[behavior_test.dart](../test/behavior_test.dart) |
| [§6.2 Privacy][privacy] | 部分实现 | 按库身份限制下划线私有名，主文件与 parts 共享私有顶层名和实例成员，导入私有名仍被拒绝；继承和扩展组合下的库私有性尚未实现或验证。 | [symbols.dart](../lib/src/symbols.dart)、[frontend.dart](../lib/src/frontend.dart)；[behavior_test.dart](../test/behavior_test.dart) 的 `_private`、`parts-main.dart` 用例 |
| [§7 Errors and Warnings][errors]：编译期诊断 | 部分实现 | 解析、语义及版本错误可带源路径与偏移；部分扫描错误仅报告偏移。现有拒绝用例不覆盖全部规范错误，错误分类与警告机制尚不完整。 | [source.dart](../lib/src/source.dart)、[parser.dart](../lib/src/parser.dart)、[scanner.dart](../lib/src/scanner.dart)；[behavior_test.dart](../test/behavior_test.dart) 的拒绝用例 |
| [§7 Errors and Warnings][errors]：动态错误 | 部分实现 | 范围、类型、只读 List 等边界有失败行为测试；当前终止进程，尚无规范异常对象、捕获与栈展开语义。 | [runtime.dart](../lib/src/runtime.dart)；[behavior_test.dart](../test/behavior_test.dart) 的运行失败用例 |
| [§21.1][lexical]、[§7][errors]：完整一致性覆盖 | 待核对 | 尚无覆盖全部合法和非法 token、关键字位置及诊断类别的规范测试集；真实程序成功不等同于完整词法兼容。 | [test/](../test/)；新增验证应优先扩展已有行为入口 |

## 文件头与验证边界

文件起始可有 BOM，或从 UTF-16 偏移 0 开始的 `#!` script tag；BOM 后的 `#!` 不被当作 script tag。初始空白及注释之后的 token 仍保留原始位置。规范允许版本标记中的空格和 tab；SDK 3.13.5 CFE 对所测含 tab 标记未选择该版本，本实现采用[版本规范][versioning]的空白规则。该差异不表示 SDK 已确认存在缺陷。

行为入口对照官方 Dart 执行结果或检查源码拒绝诊断；源码中存在处理分支不等于对应边界已有执行证据。
名称绑定不应退回按名称猜测库能力；保留的来源身份与词法范围用于后续类型、流分析和 lowering。

[pdf]: https://dart.dev/to/spec-draft
[spec]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex
[scoping]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L942
[privacy]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L1126
[errors]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L1185
[lexical]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L21791
[reserved]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L21801
[comments]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L21837
[precedence]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L21864

[separators]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.6/digit-separators/feature-specification.md

[versioning]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.8/language-versioning/feature-specification.md
[features]: https://github.com/dart-lang/sdk/blob/3.13.5/tools/experimental_features.yaml
