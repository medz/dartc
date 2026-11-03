# 模式、switch 与 if-case

模式、守卫、解构和穷尽分支的 IR 转换仍待实现。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 常量、变量、类型、通配、括号模式 | 待实现。 |
| 逻辑与/或、关系模式 | 待实现。 |
| cast、null-check、null-assert 模式 | 待实现。 |
| 对象模式、字段名推导 | 待实现。 |
| List 模式及 rest | 待实现。 |
| Map、record 模式 | 待实现。 |
| switch 表达式 | 待实现。 |
| 语句和 List 元素 if-case | 待实现。 |
| 局部模式声明/赋值 | 待实现。 |
| for/for-in 模式循环头 | 待实现。 |
| switch 语句、guard、共享 case | 待实现。 |
| bool/Null/Never/枚举穷尽性 | 待实现。 |
| 非泛型 sealed 层次穷尽性 | 待实现。 |
| List 长度与对象属性空间覆盖 | 待实现。 |
| 完整不可达 case 诊断 | 待实现。 |

[兼容范围](README.md)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/patterns.md)。

## 规范依据

[模式特性规范](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/feature-specification.md)、[穷尽性](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/exhaustiveness.md)、[对象模式类型推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/feature-specification.md#type-checking-and-pattern-required-type)。
