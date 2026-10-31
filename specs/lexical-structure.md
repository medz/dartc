# 词法结构、作用域与错误

本页索引 §6.1、§6.2、§7、§21，记录实现范围与验证入口，不替代规范正文。
条号依据[官方草案 PDF][pdf]；条款链接固定到[固定 LaTeX 源码][spec]。SDK 对照版本见[总览](README.md)；文件版本选择见下表，不代表完整旧语言兼容。

状态含义见[总览](README.md#状态与证据)。

## 扫描 API

以下为 `package:dartc/scanner.dart` 的词法支持范围。编译与执行支持见下一节。

| 规范条目 | 状态 | 支持范围与缺口 | 验证 |
| --- | --- | --- | --- |
| [§21.1 Lexical Rules][lexical]：字符与 token | 部分实现 | ASCII 标识符、当前稳定关键词、标点及运算符按最长匹配扫描，包括 `[]`、`[]=` 和 `>>>`。保留原始文本与 UTF-16 范围；非法字符产生诊断并保留 invalid token，扫描继续到 EOF。UTF-8 解码由源码提供方负责。 | [scanner_test.dart](../test/scanner/scanner_test.dart)；[token_test.dart](../test/scanner/token_test.dart) |
| [§21.1][lexical]、[数字分隔符][separators]：数字 | 部分实现 | 十进制和十六进制整数、小数、指数、数字间连续下划线；小数点与成员访问、级联分开。缺失数字和非法分隔符有独立错误代码。扫描不转换数值、不判断数值范围。 | [numbers_test.dart](../test/scanner/numbers_test.dart) |
| [字符串与插值][strings] | 部分实现 | 单双引号、raw、三引号、转义形状与 Unicode 范围检查；简单插值与表达式插值有明确边界，支持嵌套插值。相邻字符串分别保留，字符串值解码、拼接和插值求值尚未接入。 | [strings_test.dart](../test/scanner/strings_test.dart) |
| [§21.1.2 Comments][comments]、文件头 | 部分实现 | 支持单行、文档与嵌套块注释。仅跳过偏移 0 的 BOM，仅在偏移 0 识别 script tag。版本标记保留为注释，尚未选择或限制文件语言版本。 | [scanner_test.dart](../test/scanner/scanner_test.dart) |
| [§7 Errors and Warnings][errors]：词法诊断 | 部分实现 | 错误带稳定代码和源码区间；未闭合注释、字符串、插值及非法转义分别报告。未闭合字符串只返回实际存在的文本，不补造引号或花括号。括号配对、关键字位置限制和语法恢复由 parser 负责。 | [scanner_test.dart](../test/scanner/scanner_test.dart)；[strings_test.dart](../test/scanner/strings_test.dart) |

版本选择归 project，版本语法检查归 parser；字面量求值归后续分析。

## 解析语言版本

`package:dartc/parser.dart` 的各解析入口接受 `languageVersion: LanguageVersion(major, minor)`，默认 `LanguageVersion.current`，当前为 3.13。支持选择 2.12–3.13；超出范围返回诊断和可恢复的语法树。调用方根据文件与包配置选择版本，parser 不读取包配置，也不自行解释 `// @dart` 注释。

版本检查覆盖非函数类型别名、泛型元数据、无符号右移、函数与构造器 tear-off 的明确语法、super 形参、命名实参后的位置实参、增强枚举、无名 library、类修饰符、record、模式、扩展类型、数字分隔符、空感知集合元素、点简写、主构造器及空声明体。旧版 switch 的 case 使用常量表达式文法。验证见 [language_versions_test.dart](../test/parser/language_versions_test.dart)。

需要名称或类型信息才能判断的版本规则仍归语义分析，包括通配名字的绑定、私有命名参数的公开名称，以及推断和提升规则。版本检查不把解析成功等同于完整旧语言兼容。

## 文件版本选择 API

`ProjectLoader` 按[语言版本规范][versioning]和[包配置 v2][package-config]选择每个文件的版本：先取所属包的 `languageVersion`，无配置时使用 loader 的默认版本，再应用文件头第一个有效的 `// @dart = major.minor` 标记。标记必须位于首个语言 token 之前，允许前置 script tag、BOM、其他注释以及标记内的空格或 tab；块注释内、文档注释内及代码之后的内容不作为版本标记。源文件标记可以高于包默认版本；超出支持范围或数值不可表示时产生诊断。

定义库与 part 分别按自身所属包和文件头选择版本，随后检查实际版本及显式标记是否一致；仅有一侧写出标记也会产生错误，即使版本值等于默认值。解析器只接收最终选定的版本。验证见 [versions_test.dart](../test/project/versions_test.dart)、[parts_test.dart](../test/project/parts_test.dart) 和 [packages_test.dart](../test/project/packages_test.dart)。

## 编译与执行

| 规范条目 | 状态 | 支持范围与缺口 | 验证 |
| --- | --- | --- | --- |
| [§21.1 Lexical Rules][lexical]：字符与 token | 部分实现 | token 保留来源和 UTF-16 区间；源码按 UTF-8 容错解码，非法序列按最长合法前缀替换为 U+FFFD，保留起始 BOM；字符串与注释可含替换字符，标识符中的替换字符被拒绝。已有整数、double、字符串及所支持运算符扫描，完整词法与诊断分类尚未覆盖。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `utf8-source.dart`、`utf8-identifier.dart` |
| [§21.1 Lexical Rules][lexical]：字面量扫描 | 部分实现 | 支持 raw、三引号、转义、插值与相邻字符串；支持小数与指数形式；转义范围和换行边界仍需逐项核对。字面量语义归表达式章节。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) |
| [Dart 3.6 数字分隔符][separators] | 部分实现 | 文件版本至少 3.6 时，十进制/十六进制整数及小数/指数的数字间允许一个或多个下划线；前缀后、尾部及非数字边界被拒绝。字符串 `int.parse`、`double.parse` 不因该词法特性改变。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) 的 `Box.arguments`、`staticContexts`、`doubleValues`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的拒绝用例 |
| [§21.1.1 Reserved Words][reserved] | 部分实现 | 类、typedef 与类型参数的声明名共用 typeIdentifier 的保留字和内建标识符限制；上下文标识符仍可作名。其余文法位置的限制尚不完整。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) |
| [语言版本选择][versioning] | 部分实现 | 每个源文件独立选择 2.12–3.13，未标记时采用[所属包的默认版本](libraries.md)，包未指定版本时为 3.13；只采用代码或指令前首个完整的 `// @dart = M.m`。`///`、块注释、含补丁号或其他尾随内容的注释不作标记，后续标记不覆盖首个有效标记；不改写源文本或 UTF-16 偏移。导入方不覆盖被导入文件的默认版本。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `version-header.dart`、`version-markers.dart` 与版本拒绝用例 |
| [§21.1.2 Comments][comments] | 部分实现 | 扫描单行和嵌套块注释，并拒绝未闭合块注释；嵌套层次、行结束符等边界缺完整行为覆盖。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 中的库指令注释用例 |
| [版本化运算符][features] | 部分实现 | `>>>` / `>>>=` 要求文件版本至少 2.14；嵌套泛型的连续右尖括号仍按类型文法解析。没有实现其余所有版本化语法。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `version-header.dart`、`version-imports.dart` 与拒绝用例 |
| [§21.2 Operator Precedence][precedence] | 部分实现 | 支持 `/`、`/=`、`is`/`as`、`??`、条件、赋值、级联和空短路访问；具体求值与语义边界见[表达式](expressions.md)，完整优先级及文法组合仍待核验。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `cascadeValues`、`nullAwareValues`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `rejected` |
| [§6.1 Scoping][scoping]：局部名称 | 部分实现 | 支持块、参数、循环、switch 分支与 label 作用域，检查重复声明；局部与匿名函数保持独立函数体作用域，外层捕获保留原声明身份；switch 表达式绑定见[模式](patterns.md)。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) 的绑定用例；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的前向引用拒绝用例 |
| [§6.1 Scoping][scoping]：库与成员名称 | 部分实现 | 库名解析、局部到成员及已支持继承层次的查找已有路径；扩展成员和完整泛型查找仍缺失。库命名空间另见[库与脚本](libraries.md)。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) |
| [§6.2 Privacy][privacy] | 部分实现 | 按库身份限制下划线私有名，主文件与 parts 共享私有顶层名和实例成员，导入私有名仍被拒绝；继承成员和 super 构造按声明库检查，同名私有成员不会跨库覆写。扩展组合仍缺。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `_private`、`parts-main.dart`、`inheritance-imports.dart` 用例 |
| [§7 Errors and Warnings][errors]：编译期诊断 | 部分实现 | 扫描、解析、语义及版本错误携带原始源码与 UTF-16 区间；CLI 在 stderr 显示源路径、从 1 开始的行列和原始源码行，列按 UTF-16 code unit 计数，CRLF 作为一次换行。现有拒绝用例不覆盖全部规范错误，错误分类与警告机制尚不完整。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `diagnostic-*` 与拒绝用例 |
| [§7 Errors and Warnings][errors]：动态错误 | 部分实现 | 同步 throw/rethrow、catch/finally 及部分运行时错误已有对象与栈展开；各操作的支持与未实现异常边界见[表达式](expressions.md)和[语句](statements.md)，完整动态错误语义仍未完成。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的运行失败用例 |
| [§21.1][lexical]、[§7][errors]：完整一致性覆盖 | 待核对 | 尚无覆盖全部合法和非法 token、关键字位置及诊断类别的规范测试集；真实程序成功不等同于完整词法兼容。 | [test/legacy/](https://github.com/medz/dartc/tree/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/) |

数字扫描区分十六进制整数与十进制小数/指数形式，支持 `.5`；小数点不吞并成员访问或级联。整数、小数和指数中的分隔符均要求 3.6 及以上版本并位于数字之间。未使用函数中的非法指数或分隔符也必须诊断；语义范围与精确转换规则见[数字表达式](expressions.md)。

## 文件头

文件起始可有 BOM，或从 UTF-16 偏移 0 开始的 `#!` script tag；BOM 后的 `#!` 不被当作 script tag。初始空白及注释不改变后续 token 的源码位置。[语言版本规范][versioning]允许版本标记中使用空格和 tab，dartc 接受这两种写法；SDK 3.13.5 CFE 未识别含 tab 的版本标记。

[pdf]: https://dart.dev/to/spec-draft
[strings]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L8667
[spec]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex
[scoping]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L989
[privacy]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L1190
[errors]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L1255
[lexical]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L23587
[reserved]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L23598
[comments]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L23637
[precedence]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L23666

[separators]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.6/digit-separators/feature-specification.md

[versioning]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.8/language-versioning/feature-specification.md
[features]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.14/triple-shift-operator/feature-specification.md

[package-config]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.8/language-versioning/package-config-file-v2.md
