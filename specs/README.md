# Dart 语言规范

这里只列规范在哪里、dartc 的目标是什么。现在支持到哪里，见 [README](../README.md#know-what-to-expect) 和 [PLAN](../PLAN.md)。

## 基线

语言和标准库是 Dart SDK 3.14.0，标准库固定在 [fa8c1270](https://github.com/dart-lang/sdk/tree/fa8c1270c374c1346931583a17c3b7f278d3822d/sdk/lib)。3.14 没有新增语法，变化见 [3.14 语言变化](https://dart.dev/resources/language/evolution#dart-3-14)。

行为以官方 `dart` 运行的结果为准，见 [ARCHITECTURE](../ARCHITECTURE.md)。规范用来理解原因。

## 目标范围

目标是完整的 Dart 语言和原生程序需要的标准库。以下明确不做：

- 全部 JavaScript 互操作：`dart:js`、`dart:js_util`、`package:js`、`dart:js_interop`、`dart:js_interop_unsafe`。
- 动态反射：`dart:mirrors`。`Type`、`runtimeType`、泛型类型信息、`dynamic` 调用、`noSuchMethod` 不在此列，都要支持。

Wasm 是以后的目标。

## analyzer 和官方编译器的差别

静态检查和常量求值用 analyzer 14.7，它和官方编译器有时不同。下面几条已在 3.14.0 上试过，都已经按官方处理，见 `lib/src/source/differences.dart`：

- `extension type E<T>(T value) { T get() => value; }` 时，`B extends E<int>` 的值可以调用 `get()`。
- 结构体里可以不写 `this` 就用自己的字段的 `.address`。
- `receiver?.method<int>`，不调用，是错误。
- 延迟导入的 `prefix.Type<int>`，当作值，是错误。
- 明确写出泛型扩展的运算符 `E<int>(box) + 7`：参数和结果的类型按给出的类型参数算。analyzer 算成 `T`，所以接受它对参数和赋值的报错，前提是按 `int` 算是对的。

## 规范

主规范固定为 [dart-lang/language@6a254a68](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)。它还没有写进 Dart 3 的全部特性，新特性看同一版本的 [accepted](https://github.com/dart-lang/language/tree/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted)。没有接受的提案不是目标。[网上的草案](https://dart.dev/to/spec-draft)便于查章节，但内容会变。

| 主题 | 主规范 | 特性规范 |
| --- | --- | --- |
| 词法、作用域、错误 | §6、§7、§21 | [语言版本选择](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.8/language-versioning/feature-specification.md)、[数字分隔符](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.6/digit-separators/feature-specification.md) |
| 变量 | §8 | [空安全与 late](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md)、[通配变量](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/wildcard-variables/feature-specification.md) |
| 函数 | §9、§17 | [构造器提取](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.15/constructor-tearoffs/feature-specification.md)、[私有命名形参](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.12/private-named-parameters/feature-specification.md) |
| 类、mixin、枚举 | §10–§16 | [类修饰符](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/class-modifiers/feature-specification.md)、[主构造器](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.13/primary-constructors/feature-specification.md)、[增强枚举](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.17/enhanced-enums/feature-specification.md) |
| 扩展类型 |  | [extension types](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.3/extension-types/feature-specification.md) |
| 表达式 | §17 | [空安全](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md)、[空感知元素](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.8/null-aware-elements/feature-specification.md)、[点简写](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.10/dot-shorthands/feature-specification.md)、[Records](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/records/feature-specification.md)、[`>>>`](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.14/triple-shift-operator/feature-specification.md) |
| 语句 | §18 | [流分析](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/flow-analysis.md) |
| 模式 |  | [模式](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/feature-specification.md)、[穷尽性](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/exhaustiveness.md) |
| 库 | §19、§6.3 | [包配置](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.8/language-versioning/package-config-file-v2.md) |
| 类型 | §15、§20 | [类型规范化](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/normalization.md)、[类型推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md)、[水平推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.18/horizontal-inference/feature-specification.md)、[基于界限的推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/inference-using-bounds/design-document.md)、[类型别名](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.13/nonfunction-type-aliases/feature-specification.md) |

## 按语言规范而不按官方的地方

下面几条官方 3.14.0 和语言规范不同，dartc 按规范做。这些测试程序有 `// official: …` 一行，期望是手写的：

- 抽象声明给了别的默认值时，用实现的默认值（#61，dart-lang/sdk#52557）。
- 隐式协变的 `late final` 字段，写入错类型的值时检查（#63）。
- 可空的类型别名和界：`C<NullableInt, Null>` 可以，`E<NullableInt>`（界是 `Object`）不行（#64，dart-lang/sdk#64958）。
- 命名参数只是顺序不同的函数类型相等，散列也相同（#60）。
