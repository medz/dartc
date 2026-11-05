# 变量

作用域使用已绑定的声明身份。分支与循环中的局部变量保留各条路径实际写入的值。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 显式类型、`var`、多变量声明 | 支持已表示类型的局部变量。非 late 可空可变变量缺省为 null；非空变量和 final 可在声明后首次赋值，由 analyzer 检查确定赋值。 |
| 顶层、静态、实例和局部变量 | 支持局部变量、参数、实例字段和顶层/静态 const；顶层及静态可变存储待实现。 |
| 局部遮蔽、捕获、声明前引用 | 按 analyzer 绑定的声明区分同名局部变量，闭包可在外层函数返回后继续读写捕获的变量。声明前引用的静态错误由 analyzer 诊断。见[遮蔽与捕获样本](../test/lowering/fixtures/closures.dart)。 |
| 通配变量 `_` | 支持局部声明、形参及模式中的通配变量；仍按顺序执行各个初始化表达式的副作用和异常。 |
| 确定赋值与确定未赋值 | analyzer 检查非 late 局部变量的读取及 final 首次赋值；IR 保留分支、循环、异常路径与闭包共享的延后初始化存储。见[确定赋值样本](../test/lowering/fixtures/definite_assignment.dart)。 |
| 局部 `final` 首次赋值 | 支持立即初始化和声明后的首次赋值，包括分支合流及闭包捕获。 |
| 库级/字段 `final` 与隐式访问器 | 待实现。 |
| `const` 与常量对象 | 顶层、静态和局部 const 支持标量、record、List/Set/Map、普通用户类及枚举实例、Type 和函数值的嵌套组合；保留规范身份、实际泛型和不可变操作检查。特殊 SDK 对象和 Symbol 值仍待实现。私有 Symbol 字面量可能被 analyzer 错误折叠，当前在读取结果前递归检查并拒绝这类依赖，包括已折叠的标量；不另写常量求值器。 |
| `late`、`late final` | 待实现。 |
| 库变量和静态字段惰性初始化 | 待实现。 |
| 模式变量声明与赋值 | 支持用 record 模式声明局部变量、交换已有变量及在三段式 for 中解构。后续字段断言抛错时，catch 仍可读到目标变量的原值。见[解构](../test/lowering/fixtures/destructure.dart)和[失败赋值样本](../test/lowering/fixtures/exceptions.dart)。 |

[IR 行为对照](../test/lowering/lowering_test.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/variables.md)。

## 规范依据

[主规范 §8](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[空安全与 late](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md)、[通配变量](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/wildcard-variables/feature-specification.md)。
