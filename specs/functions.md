# 函数

调用按源码顺序计算实参，按绑定后的形参传值。调用结果被丢弃也须保留可能发生的副作用与异常。声明为 `void` 的函数仍可返回值；`return f();` 会传递 `f` 的实际返回值，包括 `f` 的静态返回类型为 `void` 的情况。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 顶层函数、同步块体与箭头体 | 支持普通和泛型顶层函数，可直接调用其他库中已解析的顶层函数；类型实参采用 analyzer 的显式或推断结果。 |
| 必需/可选位置、命名、required 参数 | 支持顶层、静态和实例调用，以及构造器。按源码顺序计算实际传入的参数，省略的参数由最终调用目标补齐。默认值支持标量、record、集合、普通用户对象和常量函数值。见[默认参数](../test/lowering/fixtures/defaults.dart)和[工厂转发样本](../test/lowering/fixtures/nominal/factories.dart)。 |
| 字段、super、私有命名形参 | 支持构造器中绑定到实例字段或父类形参的参数。私有命名字段形参及主构造器声明形参使用对应的公开命名键；跨库调用、super 转发、默认值、required、构造器函数值与 dynamic 调用已有 [SDK 行为对照](../test/lowering/private_named_parameters_test.dart)。普通函数的私有命名形参由 analyzer 拒绝。 |
| `covariant` 参数 | 实例分派按选中的实现和实际类型实参检查形参类型。类类型参数的协变出现也触发入口检查。协变收窄失败在进入方法体前抛出 TypeError。 |
| 顶层 getter/setter | 支持显式 getter/setter、函数值 getter 的调用及复合更新。支持顶层及静态存储的合成访问器，初始化表达式复用普通函数/闭包 lowering。见[访问器样本](../test/lowering/fixtures/static_accessors.dart)。 |
| 同步局部/匿名函数 | 支持递归局部函数、嵌套函数与逃逸闭包。闭包可捕获参数、局部变量、其他局部函数、实例接收者，以及外层类和函数的类型环境；泛型闭包还保留自身类型参数。同一次调用中的闭包共享被捕获变量的后续写入。见[闭包样本](../test/lowering/fixtures/closures.dart)。 |
| 泛型顶层函数、方法的直接调用 | 支持顶层、静态和实例方法的显式及推断调用，包括 super、虚派发、callable object 和不同类型实参的递归。类和函数类型实参分别传递，入口检查遵循运行时实现及其界限。 |
| 泛型局部/匿名函数 | 支持泛型局部函数、匿名函数、递归和逃逸闭包。每次调用独立绑定自身类型实参，并保留捕获的外层类型环境。 |
| 非泛型函数值、方法提取、`.call` | 支持提取顶层与静态函数、绑定实例或 super 方法、提取构造器，以及通过函数签名调用。协变方法提取的运行时参数类型为 Object?，调用时仍检查实现的参数类型。见[函数值样本](../test/lowering/fixtures/callables.dart)。 |
| 泛型函数值、显式函数值实例化 | 支持函数、绑定方法、泛型构造器函数值，以及显式和上下文隐式实例化。运行时类型保留泛型签名与界限，实例化检查实际实现的界限。常量/default 函数值保留未出现在签名中的类型实参及身份。见[泛型函数样本](../test/lowering/fixtures/generic_functions.dart)和[常量函数样本](../test/lowering/fixtures/generic_constants.dart)。 |
| 裸 `Function`/dynamic 函数值调用 | 支持已表示的函数、方法、构造器、闭包及 callable object，包括 Function 上界和 `.call` 提取。先验证位置/命名/类型实参个数，再应用实际声明的默认类型、界限和形参检查。保留闭包环境及构造器别名身份。原生回调只支持明确建模的签名。见[动态调用样本](../test/lowering/fixtures/dynamic_dispatch.dart)。 |
| 可调用对象、隐式 `call` 提取 | 支持实例的普通和泛型 `call` 调用，以及在函数类型上下文中隐式提取其绑定方法。见[可调用对象样本](../test/lowering/fixtures/callables.dart)。 |
| `sync*` | 支持带显式 `Yield`/恢复边的生成器 IR：调用及取得 iterator 不执行函数体，每个 iterator 的局部状态独立，外层捕获绑定仍共享。支持 `yield`、`yield*`、泛型及跨暂停的 catch/finally。行为通过 SDK 对照验证；FutureOr 结果类型、生成器的具体实现 runtimeType 和同一 iterator 重入尚未建模，原生后端的帧保存/状态机转换尚未实现。见[生成器样本](../test/lowering/fixtures/generators.dart)。 |
| `async`、`async*` | 待实现，保持显式拒绝。 |
| `external` 函数 | 待实现。 |

[IR 行为对照](../test/lowering/lowering_test.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/functions.md)。

## 规范依据

[主规范 §9、§17](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[类型推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md)、[水平推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.18/horizontal-inference/feature-specification.md)、[基于界限的推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/inference-using-bounds/design-document.md)、[私有命名形参](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.12/private-named-parameters/feature-specification.md)。
