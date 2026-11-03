# 语句

条件决定实际进入哪个块。返回结束当前路径，循环回边携带下一次迭代所需的变量值。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 块、空语句、表达式语句 | 同步块、空语句和已支持的表达式。 |
| 局部变量与同步非泛型局部函数 | 支持[变量](variables.md)中列出的局部声明。局部函数待实现。 |
| if/else、while、do、普通 for | 普通 if/else、while、do-while 和三段式 for。for 支持变量声明、表达式或空初始段，以及多个按序求值的更新表达式。循环退出后保留最后一次条件或循环体实际写入的值。 |
| for-in | 待实现。 |
| if-case、模式声明及循环头 | if-case 支持[标量模式与守卫](patterns.md)。模式声明、模式循环头待实现。 |
| switch、守卫、共享 case、隐式 break | 支持标量模式、when、default 和多个 case 共享的分支体。分支体正常结束时退出 switch。非穷尽类型未命中时继续执行 switch 后的语句。见[switch 语句样本](../test/lowering/fixtures/switch_statements.dart)。 |
| 标签、break、continue | 支持循环和 switch 的 break，以及从带标签的语句中 break。continue 可跳到目标循环的继续点或 switch 标签对应的分支体。跳向 case 时跳过其模式与守卫。 |
| return 与正常完成检查 | 函数返回与声明兼容的值。void 和可空返回类型允许隐式返回 null；抛出或调用返回 Never 的函数会结束当前路径。 |
| try/on/catch、rethrow、finally | 待实现。 |
| await for | 待实现。 |
| yield/yield* | 待实现。 |
| assert | 待实现。 |

[循环样本](../test/lowering/fixtures/loops.dart)与[SDK 行为对照](../test/lowering/lowering_test.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/statements.md)。

## 规范依据

[主规范 §18](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[模式规范](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/feature-specification.md)、[流分析](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/flow-analysis.md#statements)、[Error API](https://api.dart.dev/stable/3.13.7/dart-core/Error-class.html)。
