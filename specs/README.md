# Dart 语言兼容性

语言与标准库版本基线为 Dart SDK 3.13.7，行为以适用的语言规范、已接受的特性规范和标准库公开契约为准。SDK 是实现对照；与规范冲突的 SDK 行为不自动成为兼容要求。差异须先核查是实现错误、规范尚未更新，还是版本或平台条件不同；已确认结论在对应条款下记录并用独立预期验证。规范未明确的行为再核对 SDK 实现与平台要求。

目标是完整 Dart 语言和所需标准库，明确排除项见下文。当前开发版使用官方 analyzer 的分析结果生成 IR，原生后端可生成整数、浮点和指针函数的目标文件与库，并可执行无参数的同步 main。启动参数、异步入口、托管对象及其他执行能力仍待实现，原生范围见[库与导出](libraries.md#原生库)。已发布编译器的支持范围见 [0.5.0](https://github.com/medz/dartc/tree/v0.5.0/specs)。

各页的“当前 IR 范围”说明哪些 Dart 源码可以转换。仅支持手工构造 IR 的条目单独标明。行为对照比较 IR 和 Dart SDK 的返回值、调用顺序、异常或流事件。

| 主题 | 内容 |
| --- | --- |
| [词法结构、作用域与错误](lexical-structure.md) | 源码、语言版本、绑定与诊断 |
| [类型](types.md)和[变量](variables.md) | 值类型、形参、局部变量与赋值 |
| [表达式](expressions.md)和[语句](statements.md) | 求值顺序、短路、分支、循环与返回 |
| [函数](functions.md)和[类](classes.md) | 调用、参数、构造与分派 |
| [库](libraries.md)和[模式](patterns.md) | 导入、part、模式匹配与穷尽性 |

## 目标范围

Wasm 是后续目标，当前不提供 Wasm 输出。以下能力明确排除，不作为待补齐缺口：

- 全部 JavaScript 互操作：`dart:js`、`dart:js_util`、`package:js`、`dart:js_interop`、`dart:js_interop_unsafe` 及其兼容实现；此选择也适用于后续 Wasm 目标。
- 动态反射：`dart:mirrors` 的声明枚举、反射访问和调用。

排除反射不排除 `Type`、`runtimeType`、`is`/`as`、泛型类型信息、`dynamic` 调用、`noSuchMethod` 或元数据的语言要求；这些能力的当前缺口仍在对应主题列出。原生 `dart:ffi` 和库导出仍在范围内。这是 dartc 的范围选择，不是说官方 Dart/Wasm 已移除现代 JS 互操作，或 3.13.7 已移除 `dart:mirrors`。

## 规范依据

- [官方规范入口](https://dart.dev/resources/language/spec)指出 Dart 3 主规范尚未覆盖全部特性。[当前官方草案](https://dart.dev/to/spec-draft)便于查阅条款名和章节编号，但地址内容会更新，不等同于下列固定源码快照；封面的 `Version 2.13-dev` 不是完整 Dart 3 规范。
- 可追溯的主规范固定为 [dart-lang/language@6a254a68](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)，新特性使用该版本的 [accepted 规范](https://github.com/dart-lang/language/tree/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted)。未接受提案和 `future-releases` 不自动进入兼容目标。
