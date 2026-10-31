# Dart 语言兼容性

这里说明 dartc 用户可以解析、编译和运行哪些 Dart 特性，以及使用时的限制。兼容目标为 **Dart SDK 3.13.7**，不是完整 Dart 或完整标准库的实现。安装和命令行用法见[项目首页](../README.md)。

## 按特性查支持情况

每页先列特性矩阵，再说明语法、行为和限制。不要用整章的状态推断某个特性可用。

| 主题 | 可查内容 |
| --- | --- |
| [词法结构、作用域与错误](lexical-structure.md) | token、字符串、数字分隔符、文件版本、私有性与诊断 |
| [类型与泛型](types.md) | 空安全、类型关系、推断、typedef、[FFI 与原生导出](types.md#ffi-类型与原生导出声明) |
| [变量](variables.md) | 绑定、确定赋值、`final`、`const`、`late` 与惰性初始化 |
| [表达式](expressions.md) | 字面量、运算、集合、调用顺序、空短路、级联与点简写 |
| [语句](statements.md) | 分支、循环、跳转、异常与清理 |
| [函数](functions.md) | 参数、返回、泛型调用、闭包与函数值 |
| [类及相关声明](classes.md) | 成员、继承、构造器、枚举、修饰符、元数据与扩展 |
| [库与脚本](libraries.md) | import/export、part、URI、包配置、入口与并发边界 |
| [模式、switch 与 if-case](patterns.md) | 模式类别、解构、守卫、绑定与穷尽性 |

## 如何读矩阵

| 标记 | 含义 |
| --- | --- |
| 支持 | 支持该行明确限定的能力，不扩展到整条语言规范。 |
| 部分 | 仅支持正文列出的子集；限制同样是使用约束。 |
| 未支持 | 当前不提供该能力；解析接受或编译拒绝都不等于实现其语义。 |
| 待确认 | 不能据现有信息作出支持承诺。 |
| — | 该阶段不适用；例如库装入没有独立的表达式解析操作。 |

三列互不替代：

- **语法解析**：公开 scanner/parser API 能从文本得到语法树及词法、语法诊断。不绑定名称、不检查类型、不执行程序，也不按文件版本完整限制特性。
- **语义分析 API**：指面向上述语法树的公开名称解析、类型检查、推断及流分析能力，**当前尚未提供**。`ParseResult.hasErrors == false` 只表示未发现词法或语法错误。
- **编译/运行**：指 CLI 使用的旧编译管线及原生产物。它包含部分静态检查，但不是公开语义分析 API。该列保留 0.5 编译器的已记录支持边界，历史行为基线为 [c3394a9f](https://github.com/medz/dartc/tree/c3394a9fb38107ccde2e200d744db96aea2c276f)；新 parser 的支持不会自动扩展该列。

原生目标为 macOS/Linux 的 ARM64、x86-64。可执行文件的能力不能自动用于 object、static、dylib 输出；尤其函数值、托管对象和异常有额外边界，见[函数值](functions.md#函数值)与[FFI](types.md#ffi-类型与原生导出声明)。

## 目标范围

Wasm 是后续目标，当前不提供 Wasm 输出。以下能力明确排除，不作为待补齐缺口：

- 全部 JavaScript 互操作：`dart:js`、`dart:js_util`、`package:js`、`dart:js_interop`、`dart:js_interop_unsafe` 及其兼容实现；此选择也适用于后续 Wasm 目标。
- 动态反射：`dart:mirrors` 的声明枚举、反射访问和调用。

排除反射不排除 `Type`、`runtimeType`、`is`/`as`、泛型类型信息、`dynamic` 调用、`noSuchMethod` 或元数据的语言要求；这些能力的当前缺口仍在对应主题列出。原生 `dart:ffi` 和库导出仍在范围内。这是 dartc 的范围选择，不是说官方 Dart/Wasm 已移除现代 JS 互操作，或 3.13.7 已移除 `dart:mirrors`。

## 规范依据

- [官方规范入口](https://dart.dev/resources/language/spec)指出 Dart 3 主规范尚未覆盖全部特性。章节编号使用 [2026-10-14 草案](https://dart.dev/to/spec-draft)的条款名；封面的 `Version 2.13-dev` 不是完整 Dart 3 规范。
- 可追溯的主规范固定为 [dart-lang/language@6a254a68](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)，新特性使用该版本的 [accepted 规范](https://github.com/dart-lang/language/tree/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted)。未接受提案和 `future-releases` 不自动进入兼容目标。
- 各页保留影响用户程序的规范与 SDK 差异，并注明涉及的 SDK 版本。实现几个标准库方法不代表语言条款已完整符合。
