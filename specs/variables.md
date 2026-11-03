# 变量

作用域使用已绑定的声明身份。分支与循环中的局部变量保留各条路径实际写入的值。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 显式类型、`var`、多变量声明 | 带初值的 int、bool 和 void 局部声明。void 变量可以接收不同类型的值。 |
| 顶层、静态、实例和局部变量 | 局部变量和参数，其余存储待实现。 |
| 局部遮蔽、捕获、声明前引用 | 待实现。 |
| 通配变量 `_` | 待实现。 |
| 确定赋值与确定未赋值 | 待实现。 |
| 局部 `final` 首次赋值 | 带立即初值的局部 final。延后首次赋值待实现。 |
| 库级/字段 `final` 与隐式访问器 | 待实现。 |
| `const` 与常量对象 | 待实现。 |
| `late`、`late final` | 待实现。 |
| 库变量和静态字段惰性初始化 | 待实现。 |
| 模式变量声明与赋值 | 待实现。 |

[IR 行为对照](../test/lowering/lowering_test.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/variables.md)。

## 规范依据

[主规范 §8](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[空安全与 late](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md)、[通配变量](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/wildcard-variables/feature-specification.md)。
