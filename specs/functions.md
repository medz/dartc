# 函数

调用按源码顺序计算实参，按绑定后的形参传值。调用结果被丢弃也须保留可能发生的副作用与异常。声明为 `void` 的函数仍可返回值；`return f();` 会传递 `f` 的实际返回值，包括 `f` 的静态返回类型为 `void` 的情况。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 顶层函数、同步块体与箭头体 | 支持普通和泛型顶层函数，可直接调用其他库中已解析的顶层函数；类型实参采用 analyzer 的显式或推断结果。 |
| 必需/可选位置、命名、required 参数 | 支持顶层、静态和实例调用，以及构造器。按源码顺序计算实际传入的参数，省略的参数由最终调用目标补齐。默认值支持标量、record、集合、普通用户对象和常量函数值。见[默认参数](../test/frontend/lowering/fixtures/defaults.dart)和[工厂转发样本](../test/frontend/lowering/fixtures/nominal/factories.dart)。 |
| 字段、super、私有命名形参 | 支持构造器中绑定到实例字段或父类形参的参数。私有命名字段形参及主构造器声明形参使用对应的公开命名键；跨库调用、super 转发、默认值、required、构造器函数值与 dynamic 调用已有 [SDK 行为对照](../test/frontend/lowering/private_named_parameters_test.dart)。普通函数的私有命名形参由 analyzer 拒绝。 |
| `covariant` 参数 | 实例分派按选中的实现和实际类型实参检查形参类型。类类型参数的协变出现也触发入口检查。协变收窄失败在进入方法体前抛出 TypeError。 |
| 顶层 getter/setter | 支持显式 getter/setter、函数值 getter 的调用及复合更新。支持顶层及静态存储的合成访问器，初始化表达式复用普通函数/闭包 lowering。见[访问器样本](../test/frontend/lowering/fixtures/static_accessors.dart)。 |
| 同步局部/匿名函数 | 支持递归局部函数、嵌套函数与逃逸闭包。闭包可捕获参数、局部变量、其他局部函数、实例接收者，以及外层类和函数的类型环境；泛型闭包还保留自身类型参数。同一次调用中的闭包共享被捕获变量的后续写入。见[闭包样本](../test/frontend/lowering/fixtures/closures.dart)。 |
| 泛型顶层函数、方法的直接调用 | 支持顶层、静态和实例方法的显式及推断调用，包括 super、虚派发、callable object 和不同类型实参的递归。类和函数类型实参分别传递，入口检查遵循运行时实现及其界限。 |
| 泛型局部/匿名函数 | 支持泛型局部函数、匿名函数、递归和逃逸闭包。每次调用独立绑定自身类型实参，并保留捕获的外层类型环境。 |
| 非泛型函数值、方法提取、`.call` | 支持提取顶层与静态函数、绑定实例或 super 方法、提取构造器，以及通过函数签名调用。协变方法提取的运行时参数类型为 Object?，调用时仍检查实现的参数类型。见[函数值样本](../test/frontend/lowering/fixtures/callables.dart)。 |
| 泛型函数值、显式函数值实例化 | 支持函数、绑定方法、泛型构造器函数值，以及显式和上下文隐式实例化。运行时类型保留泛型签名与界限，实例化检查实际实现的界限。常量实例化保留规范身份，包括通过其他库的私有别名取得的构造器和未出现在签名中的类型实参。见[泛型函数样本](../test/frontend/lowering/fixtures/generic_functions.dart)和[常量函数样本](../test/frontend/lowering/fixtures/generic_constants.dart)。 |
| 裸 `Function`/dynamic 函数值调用 | 支持已表示的函数、方法、构造器、闭包及 callable object，包括 Function 上界和 `.call` 提取。先验证位置/命名/类型实参个数，再应用实际声明的默认类型、界限和形参检查。保留闭包环境及构造器别名身份。原生回调只支持明确建模的签名。见[动态调用样本](../test/frontend/lowering/fixtures/dynamic_dispatch.dart)。 |
| 可调用对象、隐式 `call` 提取 | 支持实例的普通和泛型 `call` 调用，以及在函数类型上下文中隐式提取其绑定方法。见[可调用对象样本](../test/frontend/lowering/fixtures/callables.dart)。 |
| `sync*` | 支持带显式 `Yield`/恢复边的生成器 IR：调用及取得 iterator 不执行函数体，每个 iterator 的局部状态独立，外层捕获绑定仍共享。支持 `yield`、`yield*`、泛型及跨暂停的 catch/finally。行为通过 SDK 对照验证；支持 FutureOr<Iterable<T>> 返回声明；生成器的具体实现 runtimeType 和同一 iterator 重入尚未建模，原生后端的帧保存/状态机转换尚未实现。见[生成器样本](../test/frontend/lowering/fixtures/generators.dart)。 |
| `async`、`await` | IR 区分公开返回签名与 `completionType`，用显式 `Await` 终结符和正常/异常恢复边保存暂停点。支持立即执行、类型化 Future/value 双臂、跨暂停的捕获/异常/控制流，以及 finally 完成后才接续返回的 Future；返回表达式的类型检查仍在 finally 之前。参考执行器使用 SDK Future 微任务，已作顺序/错误/身份对照；原生后端的异步帧与运行时转换尚未实现。见[异步样本](../test/frontend/lowering/fixtures/async_functions.dart)。 |
| `async*` | 支持普通、泛型和局部 `async*` 函数，返回 `Stream<T>`。`Yield` 区分继续和取消，`YieldStream` 委托数据与错误事件，订阅操作本身的异常可进入局部处理器。开始监听、暂停、取消、异步 finally 和清理失败已有 [SDK 行为对照](../test/ir/async_generators_test.dart)。源码转换也通过[暂停与取消对照](../test/frontend/lowering/async_generators_test.dart)验证。 |
| `external` 函数 | `IrExternal` 保存外部实现的 Dart 签名、默认值和声明身份，源码支持顶层函数、类成员、构造器和 extension 成员；external 变量生成访问器声明，不分配普通字段或全局存储。[IR 校验](../test/ir/program_references_test.dart)覆盖重复实现、缺失实现和默认值类型。见[源码声明验证](../test/frontend/lowering/externals_test.dart)。外部符号绑定及原生调用仍由后续领域实现。 |

[IR 行为对照](../test/frontend/lowering/lowering_test.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/functions.md)。

## 原生词法闭包范围

同步局部函数和匿名函数支持捕获值及共享的非 `late` 可变存储，可在创建函数返回后调用，也可经全局变量跨原生入口保留。普通类型化 `FunctionCall` 按实际闭包目标补齐位置和命名默认值，支持递归及自身引用；循环复制的存储保留各次迭代身份。泛型闭包每次调用绑定自身类型实参，并保留外层函数和类的实际类型环境。闭包对象使用真实 `FunctionType` 作为运行时类型，捕获的引用参与普通 GC 根扫描与异常清理。见[原生闭包验证](../test/compiler/closures_test.dart)。

此范围不包含 `InstantiateFunction` 泛型函数值实例化、顶层/静态函数及方法/构造器提取、dynamic/noSuchMethod 调用、捕获的 `late` 绑定与初始化体存储，也不包含 FFI 回调。一般局部 `late` 的原生绑定语义仍待实现；上表的 IR 支持不表示这些路径均可原生执行。

## 异步参考执行器范围

测试执行器将 guest Future 的类型与载荷分开保存，使用真实 SDK Future 调度，而非把暂停伪装成普通调用或同步循环。支持 `Future.value/error/sync/microtask`、`Completer`/`Completer.sync`、`then`、`catchError` 和 `scheduleMicrotask` 的已建模协议；`Future.sync` 保留可直接返回的 Future 身份与实际类型。普通同步函数不创建异步帧。

参考执行器显式拒绝原生 Future 输入的类型桥、自定义 Future 的 await/接续协议、`whenComplete` 及其他未建模 Future API、Future/Completer 的方法提取和具体实现 runtimeType/toString。Zone 用户 API、完整异步堆栈文本和一般 Stream 成员仍待验证。

## 规范依据

[主规范 §9、§17](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[类型推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md)、[水平推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.18/horizontal-inference/feature-specification.md)、[基于界限的推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/inference-using-bounds/design-document.md)、[私有命名形参](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.12/private-named-parameters/feature-specification.md)。
