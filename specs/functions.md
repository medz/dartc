# 函数

调用按源码顺序计算实参，按绑定后的形参传值。调用结果被丢弃也须保留可能发生的副作用与异常。声明为 `void` 的函数仍可返回值；`return f();` 会传递 `f` 的实际返回值，包括 `f` 的静态返回类型为 `void` 的情况。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 顶层函数、同步块体与箭头体 | 非泛型顶层函数，可直接调用其他库中已解析的顶层函数。 |
| 必需/可选位置、命名、required 参数 | 支持顶层、静态和实例调用，以及构造器。按源码顺序计算实际传入的参数，省略的参数由最终调用目标补齐。默认值支持标量、record 和常量函数值。见[默认参数](../test/lowering/fixtures/defaults.dart)和[工厂转发样本](../test/lowering/fixtures/nominal/factories.dart)。 |
| 字段、super、私有命名形参 | 支持构造器中绑定到实例字段或父类形参的参数。私有命名形参的行为对照待补。 |
| `covariant` 参数 | 非泛型实例分派按选中的实现检查形参类型。协变收窄失败在进入方法体前抛出 TypeError。 |
| 顶层 getter/setter | 待实现。 |
| 同步非泛型局部/匿名函数 | 待实现。 |
| 泛型顶层函数、方法的直接调用 | 待实现。 |
| 泛型局部/匿名函数 | 待实现。 |
| 非泛型函数值、方法提取、`.call` | 支持提取顶层与静态函数、绑定实例或 super 方法、提取构造器，以及通过函数签名调用。协变方法提取的运行时参数类型为 Object?，调用时仍检查实现的参数类型。见[函数值样本](../test/lowering/fixtures/callables.dart)。 |
| 泛型函数值、显式函数值实例化 | 待实现。 |
| 裸 `Function`/dynamic 函数值调用 | 待实现。 |
| 可调用对象、隐式 `call` 提取 | 待实现。 |
| `async`、`sync*`、`async*` | 待实现。 |
| `external` 函数 | 待实现。 |

[IR 行为对照](../test/lowering/lowering_test.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/functions.md)。

## 规范依据

[主规范 §9、§17](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[类型推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md)、[水平推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.18/horizontal-inference/feature-specification.md)、[基于界限的推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/inference-using-bounds/design-document.md)、[私有命名形参](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.12/private-named-parameters/feature-specification.md)。
