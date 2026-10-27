# Dart 语言兼容性

本目录按 Dart Language Specification 跟踪 dartc 的语言实现。兼容基线为 **Dart SDK 3.13.5 的原生语言语义**。这里只记录条款引用、当前实现、缺口和验证入口，不保存或改写官方规范副本。

编译器结构、IR、ABI、运行时和自举设计见 [architecture.md](../doc/architecture.md)，安装与使用见 [README](../README.md)。

## 规范来源

- [官方规范入口](https://dart.dev/resources/language/spec)说明 Dart 3 主规范仍在完善，尚未覆盖当前全部语言特性。
- 主规范引用 [2026-10-14 草案 PDF](https://dart.dev/to/spec-draft)的章节名和编号；其封面仍标为 `Version 2.13-dev`，不能把它当作完整的 Dart 3.13.5 规范。可追溯源码固定为 [dart-lang/language@6a254a68](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)。PDF 地址会更新；核对历史引用时以固定源码及条款名为准。
- 草案尚未整合的规则引用官方 [accepted 特性规范](https://github.com/dart-lang/language/tree/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted)。`future-releases` 和未接受的提案不自动进入兼容基线。
- 官方 SDK 3.13.5 和 [SDK 语言测试](https://github.com/dart-lang/sdk/tree/3.13.5/tests/language)用于差分验证。遇到规范草案与参考实现不一致，应在对应条目记录具体差异和来源，不能静默选择方便实现的行为。

章节号只用于定位所引用的草案，不作为本项目自己的规则编号。标准库 API 使用对应 API 文档作补充引用；实现若干库方法不能作为语言条款已经满足的证据。

## 章节索引

| 规范章节 | 跟踪文件 | 当前边界 |
|---|---|---|
| §1–5 Scope、Conformance、References、Definitions、Notation | 本页 | 定义兼容目标与来源；尚未满足完整一致性要求 |
| §6 Overview；§7 Errors and Warnings；§21 Reference | [词法、作用域与诊断](lexical-structure.md)、[并发边界](libraries.md) | 部分实现；isolate 并发未实现 |
| §8 Variables | [变量](variables.md) | 部分实现 |
| §9 Functions | [函数](functions.md) | 部分实现 |
| §10 Classes；§11 Interfaces；§12 Mixins；§13 Extensions；§14 Enums；§16 Metadata | [类及相关声明](classes.md) | 简单类部分实现，其余构造仍有大片缺口 |
| §15 Generics；§20 Types | [类型与泛型](types.md) | 核心类型和 List 实参部分实现，一般泛型尚未实现 |
| §17 Expressions | [表达式](expressions.md) | 部分实现 |
| §18 Statements | [语句](statements.md) | 部分实现 |
| §19 Libraries and Scripts | [库与脚本](libraries.md) | 相对库依赖与入口部分实现 |

## 主规范之外的特性

下表补充主规范的索引；状态仍由相应跟踪文件中的具体行为和证据决定。

| 官方特性规范 | 跟踪位置 | 当前边界 |
|---|---|---|
| [空安全](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md) | [类型](types.md)、[变量](variables.md) | 已有底类型与部分赋值、提升规则；完整提升、推断及控制流仍有缺口 |
| [增强枚举](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.17/enhanced-enums/feature-specification.md)、[super 形参](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.17/super-parameters/feature-specification.md) | [类](classes.md) | 未实现 |
| [Records](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/records/feature-specification.md)、[Patterns](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/feature-specification.md)及[穷尽性](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/exhaustiveness.md) | [类型](types.md)、[表达式](expressions.md)、[语句](statements.md) | 未实现 |
| [类修饰符](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/class-modifiers/feature-specification.md)、[Extension types](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.3/extension-types/feature-specification.md) | [类](classes.md)、[类型](types.md) | 未实现 |
| [数字分隔符](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.6/digit-separators/feature-specification.md) | [词法](lexical-structure.md) | 部分实现；整数分隔符可用，浮点及指数形式未实现 |
| [通配变量](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/wildcard-variables/feature-specification.md) | [变量](variables.md) | 已有局部绑定行为，完整声明位置规则待核对 |
| [基于界限的推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/inference-using-bounds/design-document.md) | [类型](types.md) | 未实现 |
| [Null-aware elements](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.8/null-aware-elements/feature-specification.md)、[Dot shorthands](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.10/dot-shorthands/feature-specification.md) | [表达式](expressions.md) | 未实现 |
| [私有命名形参](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.12/private-named-parameters/feature-specification.md) | [函数](functions.md) | 已有 field-formal 名字映射，完整规则待核对 |
| [Primary constructors](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.13/primary-constructors/feature-specification.md) | [类](classes.md) | 未实现 |

## 状态与证据

- **部分实现**：已列出的行为有实现或行为测试，后面明确保留缺口；不表示整条规范符合。
- **未实现**：尚无相应语言实现。解析失败或主动拒绝不等于已正确实现其静态错误规则。
- **待核对**：当前证据不足，先核对规范、源码和实际运行，再确定状态。
- **已实现**：所引用的明确条款范围、必要行为及错误规则均已核对，并附验证证据；不将此状态扩展到整章或整个语言。当前各章仍有缺口，尚无整章符合性结论。

代码链接定位实现，测试链接定位行为证据；有限测试或自编译成功均不代表整章兼容。平台能力以对应平台的原生执行为依据。

## 维护要求

语言变更应同步更新所属条目的支持范围、缺口、上游引用和行为测试入口。绑定、类型检查、流分析与运行时约束必须随语法一起落实；验证复用现有编译执行测试，并对照 SDK 3.13.5 的成功与拒绝行为。
