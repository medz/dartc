# Dart 语言兼容性

本目录跟踪 Dart 语言条款、dartc 的支持范围、缺口和行为验证。当前兼容基线为 **Dart SDK 3.13.7**；完整语言及所需标准库尚未实现。

编译与执行支持对应 dartc 0.5 的编译器，测试链接固定到相关源码版本。新 API 的语法支持单独列出，不代表相应程序已能编译或执行：

| API | 支持范围与验证 |
| --- | --- |
| 扫描 | [词法规则、token 与词法诊断](lexical-structure.md#扫描-api) |
| 文本解析：编译单元与声明 | [文件与指令](libraries.md#编译单元解析-api)、[类及成员](classes.md#类与成员解析)、[顶层声明](functions.md#顶层声明解析) |
| AST：编译单元与声明 | [库指令](libraries.md#编译单元与库指令语法表示)、[类及相关声明](classes.md#类与成员语法表示)、[元数据](classes.md#元数据语法表示)、[函数](functions.md#函数语法表示)、[变量](variables.md#变量语法表示) |
| AST：类型与程序体 | [类型](types.md#类型语法表示)、[表达式](expressions.md#表达式语法表示)、[语句](statements.md#语句语法表示)、[模式](patterns.md#模式语法表示) |
| 解析 | [表达式](expressions.md#表达式解析-api)、[类型](types.md#类型解析-api)、[语句](statements.md#语句解析-api)、[形参](functions.md#形参解析-api)、[函数体](functions.md#函数体解析-api)、[模式](patterns.md#模式解析-api)的解析、诊断与边界 |

AST API 接受手工构造的节点，检查源码范围、快照归属和子节点顺序。parser API 已接入编译单元、声明、类型、形参、函数体、表达式和语句；模式、if-case 和 switch 均已接入文本解析。名称绑定、类型检查和执行尚未接入这些节点。

安装与使用见 [README](../README.md)。

## 目标范围

以本目录的语言条款和目标标准库为实现范围，以下两类能力明确排除：

- **全部 JavaScript 互操作**：包括 `dart:js`、`dart:js_util`、`package:js`、`dart:js_interop`、`dart:js_interop_unsafe`，以及这些 API 的兼容实现。此范围也适用于后续 Wasm 目标。
- **动态反射**：不实现 `dart:mirrors` 及其运行时枚举声明、按反射对象访问和调用成员的能力。

这两项是项目明确的范围选择，不作为待补齐的实现缺口。其他尚缺的语言或目标标准库能力仍按实现缺口跟踪。`Type`、`runtimeType`、`is`/`as`、泛型类型信息、`dynamic` 调用、`noSuchMethod` 和元数据注解继续按 Dart 语义实现；排除 `dart:mirrors` 不删除这些要求。原生 `dart:ffi` 与库导出仍在目标范围内。

Wasm 是后续输出目标，尚不代表已经实现或验证。其模块导入/导出和宿主 ABI 按目标设计；提供 Wasm 输出不自动恢复上述 JS 互操作库支持。

上游与本项目的范围应区分：官方已弃用[旧 JS 互操作机制](https://dart.dev/interop/js-interop/past-js-interop)，现代 `dart:js_interop` 仍由[官方 Wasm 工具链](https://dart.dev/web/wasm)支持；全部排除 JS 互操作是 dartc 的项目选择。[Dart 官方公告](https://groups.google.com/a/dartlang.org/g/announce)列出的 `dart:mirrors` 计划为 Dart 3.14 弃用、Dart 4.0 移除，不表示当前 3.13.7 基线已经删除该库。

## 规范来源

- [官方规范入口](https://dart.dev/resources/language/spec)说明 Dart 3 主规范仍在完善，尚未覆盖当前全部语言特性。
- 主规范引用 [2026-10-14 草案 PDF](https://dart.dev/to/spec-draft)的章节名和编号；其封面仍标为 `Version 2.13-dev`，不能把它当作完整的 Dart 3 规范。可追溯源码固定为 [dart-lang/language@6a254a68](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)。PDF 地址会更新；核对历史引用时以固定源码及条款名为准。
- 草案尚未整合的规则引用官方 [accepted 特性规范](https://github.com/dart-lang/language/tree/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted)。`future-releases` 和未接受的提案不自动进入兼容基线。
- 本机官方 SDK 和 [SDK 语言测试](https://github.com/dart-lang/sdk/tree/3.13.7/tests/language)用于差分验证，结果记录实际 SDK 版本与工具链指纹。遇到规范草案与参考实现不一致，应在对应条目记录具体差异和来源，不能静默选择方便实现的行为。

章节号只用于定位所引用的草案，不作为本项目自己的规则编号。标准库 API 使用对应 API 文档作补充引用；实现若干库方法不能作为语言条款已经满足的证据。

## 章节索引

| 规范章节 | 跟踪文件 | 当前边界 |
|---|---|---|
| §1–5 Scope、Conformance、References、Definitions、Notation | 本页 | 定义兼容目标与来源；尚未满足完整一致性要求 |
| §6 Overview；§7 Errors and Warnings；§21 Reference | [词法、作用域与诊断](lexical-structure.md)、[并发边界](libraries.md) | 部分实现；isolate 并发未实现 |
| §8 Variables | [变量](variables.md) | 部分实现 |
| §9 Functions | [函数](functions.md) | 部分实现 |
| §10 Classes；§11 Interfaces；§12 Mixins；§13 Extensions；§14 Enums；§16 Metadata | [类及相关声明](classes.md) | 普通及泛型类、非泛型父接口、工厂构造、枚举和元数据部分实现；mixin 和 extension 仍缺 |
| §15 Generics；§20 Types | [类型与泛型](types.md) | 核心类型、List 实参、泛型别名与泛型函数直接调用部分实现；普通及 const 泛型实例、成员代入和实际类型检查部分实现；泛型父接口与泛型函数值仍缺 |
| §17 Expressions | [表达式](expressions.md) | 部分实现 |
| §18 Statements | [语句](statements.md) | 部分实现 |
| §19 Libraries and Scripts | [库与脚本](libraries.md) | 相对库依赖与入口部分实现 |

## 主规范之外的特性

下表补充主规范的索引；状态仍由相应跟踪文件中的具体行为和证据决定。

| 官方特性规范 | 跟踪位置 | 当前边界 |
|---|---|---|
| [空安全](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md) | [类型](types.md)、[变量](variables.md) | 已有底类型与部分赋值、提升规则；完整提升、推断及控制流仍有缺口 |
| [增强枚举](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.17/enhanced-enums/feature-specification.md) | [类](classes.md) | 非泛型枚举的值、字段、const 与重定向构造、工厂构造、方法、静态成员和 implements 已支持；类型参数、mixin 及值名为 `name` 的枚举仍缺 |
| [super 形参](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.17/super-parameters/feature-specification.md) | [类](classes.md) | 非泛型生成式构造中的类型推断、默认值继承与参数转发已支持；泛型类情形仍缺 |
| [Records](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/records/feature-specification.md)、[Patterns](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/feature-specification.md)及[穷尽性](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/exhaustiveness.md) | [类型](types.md)、[模式、switch 与 if-case](patterns.md)、[语句](statements.md) | switch 表达式、if-case、标量/对象/List 模式、局部解构声明/赋值及模式循环头部分实现；模式 switch 语句部分实现；Map/record 解构未实现 |
| [类修饰符](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/class-modifiers/feature-specification.md)、[Extension types](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.3/extension-types/feature-specification.md) | [类](classes.md)、[类型](types.md) | 类修饰符部分实现；extension type 的静态及运行时语义未实现 |
| [数字分隔符](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.6/digit-separators/feature-specification.md) | [词法](lexical-structure.md) | 部分实现；整数、小数及指数中的数字分隔符可用 |
| [通配变量](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/wildcard-variables/feature-specification.md) | [变量](variables.md) | 已有局部绑定行为，完整声明位置规则待核对 |
| [基于界限的推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/inference-using-bounds/design-document.md) | [类型](types.md)、[函数](functions.md#基于界限的推断) | 3.7 起在普通泛型调用和普通及 const 泛型构造推断中组合下界与声明上界，支持 List、可空及函数签名；完整 F-bound 与泛型父接口仍缺 |
| [Null-aware elements](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.8/null-aware-elements/feature-specification.md) | [表达式](expressions.md) | List 的运行时及常量元素已支持；Set/Map 未实现 |
| [Constructor tear-offs](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.15/constructor-tearoffs/feature-specification.md) | [类](classes.md#构造器函数值)、[函数](functions.md#函数值) | 非泛型用户类构造器、工厂、重定向及普通类别名提取已支持；泛型类/别名及标准库构造器提取仍缺 |
| [Dot shorthands](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.10/dot-shorthands/feature-specification.md) | [表达式](expressions.md#点简写)、[模式](patterns.md) | 已有构造器与静态成员的上下文简写、选择器链、常量、相等操作数和模式已支持；非泛型用户类构造器函数值可用于常量模式；泛型类及未实现声明类别仍缺 |
| [私有命名形参](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.12/private-named-parameters/feature-specification.md) | [函数](functions.md) | 字段形参和主构造器声明参数的公共名映射、冲突校验及 super 形参公共名称关联 |
| [Primary constructors](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.13/primary-constructors/feature-specification.md) | [类](classes.md#主构造器) | 普通及泛型类的主构造器、字段声明参数与推断、初始化作用域、常量求值及生成式/工厂构造简写已支持；泛型父类及其余声明类别仍缺 |

## 状态与证据

- **部分实现**：已列出的行为有实现或行为测试，后面明确保留缺口；不表示整条规范符合。
- **未实现**：尚无相应语言实现。解析失败或主动拒绝不等于已正确实现其静态错误规则。
- **明确排除**：仅指[目标范围](#目标范围)中明确列出的能力，不代表已实现或已验证其拒绝行为。
- **待核对**：当前证据不足，先核对规范、源码和实际运行，再确定状态。
- **已实现**：所引用的明确条款范围、必要行为及错误规则均已核对，并附验证证据；不将此状态扩展到整章或整个语言。当前各章仍有缺口，尚无整章符合性结论。

测试链接定位各条目的行为证据，不代表整章兼容。macOS 与 Linux 的 ARM64/x86-64 目标采用相同的语言兼容目标。
