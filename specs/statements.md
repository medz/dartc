# 语句

条件决定实际进入哪个块。返回结束当前路径，循环回边携带下一次迭代所需的变量值。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 块、空语句、表达式语句 | 同步块、空语句和已支持的表达式。 |
| 局部变量与同步非泛型局部函数 | 带立即初值的标量局部变量。局部函数待实现。 |
| if/else、while、do、普通 for | 普通 if/else 和 while，含循环变量、分支汇合和提前返回。 |
| for-in | 待实现。 |
| if-case、模式声明及循环头 | 待实现。 |
| switch、守卫、共享 case、隐式 break | 待实现。 |
| 标签、break、continue | 待实现。 |
| return 与正常完成检查 | 返回非空 int、bool 或从 void 函数返回。 |
| try/on/catch、rethrow、finally | 待实现。 |
| await for | 待实现。 |
| yield/yield* | 待实现。 |
| assert | 待实现。 |

[IR 行为对照](../test/ir/lowering_test.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/statements.md)。

## 规范依据

[主规范 §18](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[模式规范](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/feature-specification.md)、[流分析](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/flow-analysis.md#statements)、[Error API](https://api.dart.dev/stable/3.13.7/dart-core/Error-class.html)。
