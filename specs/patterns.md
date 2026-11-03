# 模式、switch 与 if-case

匹配按源码顺序检查，守卫只在模式成功后执行。守卫失败时，其对外层变量的写入仍然可见。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 常量、变量、类型、通配、括号模式 | 支持标量常量、核心类型变量及通配模式和括号模式。常量模式以常量为相等比较的接收者。 |
| 逻辑与/或、关系模式 | 支持短路 `&&`、`\|\|` 和两侧变量的合并。关系模式以被匹配值为接收者，支持核心标量相等和 int 大小比较。用户定义的运算符待实现。 |
| cast、null-check、null-assert 模式 | `p as T` 可将值转换为已支持的核心类型。`p?` 遇 null 时匹配失败，`p!` 遇 null 时抛出 TypeError。 |
| 对象模式、字段名推导 | 待实现。 |
| List 模式及 rest | 待实现。 |
| Map、record 模式 | 待实现。 |
| switch 表达式 | 支持上述模式和 when 守卫。被匹配表达式求值一次，只执行首个匹配且守卫为真的分支。 |
| 语句和 List 元素 if-case | 支持语句中的 if-case、when 和 else。集合元素待实现。 |
| 局部模式声明/赋值 | 待实现。 |
| for/for-in 模式循环头 | 待实现。 |
| switch 语句、guard、共享 case | 支持上述模式与 when。多个 case 共享分支体时，传递相应 case 中一致绑定的变量值。带标签的 continue 直接进入分支体。 |
| bool/Null/Never/枚举穷尽性 | analyzer 检查输入的穷尽性。IR 行为对照涵盖 bool? 的 true、false、null 以及 num 的 int、double 分支。枚举声明待实现。 |
| 非泛型 sealed 层次穷尽性 | 待实现。 |
| List 长度与对象属性空间覆盖 | 待实现。 |
| 完整不可达 case 诊断 | 待实现。 |

[匹配与守卫样本](../test/lowering/fixtures/patterns.dart)和[SDK 行为对照](../test/lowering/lowering_test.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/patterns.md)。

## 规范依据

[模式特性规范](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/feature-specification.md)、[穷尽性](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/exhaustiveness.md)、[对象模式类型推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/feature-specification.md#type-checking-and-pattern-required-type)。
