# 类型与泛型

IR 保存值的 Dart 类型。寄存器宽度、装箱和原生调用约定由后续后端决定。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 类型名、前缀、嵌套实参、可空类型 | 支持下列核心类型的可空形式，包括参数、返回、变量和分支汇合。嵌套类型实参待实现。 |
| 核心标量、`Object`、`dynamic`、`void`、`Never` | int、double、num、bool、String、Object、Null、void 和 Never。Never 没有正常返回值，Never? 等价于 Null。dynamic 待实现。 |
| 异常及栈轨迹 | 支持 Error、TypeError、StackTrace，以及按用户声明的非泛型类和接口捕获异常。 |
| `List<T>` 及实际类型检查 | 待实现。 |
| 非泛型函数签名 | 顶层函数的必需和可选参数；直接调用会补齐缺省实参。函数值待实现。 |
| 泛型函数类型与泛型函数值签名 | 待实现。 |
| 类型参数、上界、泛型别名 | 待实现。 |
| 现代与旧式函数 typedef | 待实现。 |
| 普通及 const 泛型类实例 | 待实现。 |
| 泛型 `extends`/`implements` | 待实现。 |
| 推断、类型提升、确定赋值 | 支持局部变量和参数在核心类型测试及判空后的读取和更新，包括 `is!` 分支提前返回后的提升。非空变量的延后首次赋值待实现。 |
| 基于界限的推断 | 待实现。 |
| Record 类型、extension type | 支持 Record、具名和位置字段的结构类型、嵌套及可空 record。相同形状按字段类型协变，命名顺序不影响形状。extension type 待实现。 |
| `Future`、`FutureOr` 与异步类型规则 | 待实现。 |
| FFI 标量、指针与原生导出 | 待实现。 |

[IR 行为对照](../test/lowering/lowering_test.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/types.md)。

## 规范依据

[主规范 §15、§20](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[空安全](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md)、[类型推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md)、[流分析](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/flow-analysis.md)、[类型别名](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.13/nonfunction-type-aliases/feature-specification.md)、[`dart:ffi`](https://api.dart.dev/stable/3.13.7/dart-ffi/NativeType-class.html)。
