# 表达式

表达式按 Dart 规定的顺序求值。短路右侧保持条件执行。

| 特性 | 当前 IR 范围 |
| --- | --- |
| null、bool、整数、double、字符串 | 仅非空 bool 和整数字面量。 |
| 普通、raw、多行、插值与相邻字符串 | 待实现。 |
| Symbol 字面量 | 待实现。 |
| Record 字面量 | 待实现。 |
| 可变/const List | 待实现。 |
| Set、Map 字面量 | 待实现。 |
| List if/for/for-in、spread | 待实现。 |
| 空感知集合元素 | 待实现。 |
| 集合 if-case、模式循环 | 待实现。 |
| 常量运算、类型测试与转换 | 待实现。 |
| 算术、位运算、移位、关系与短路 | 非空 int 的 +、-、*、< 以及 bool 的 &&、||。 |
| 赋值、复合赋值、增减、索引赋值 | 仅独立语句中对已初始化局部变量或参数的简单赋值。 |
| 函数、构造器、成员调用与提取 | 非泛型顶层函数的直接调用。 |
| 空短路、空断言与级联 | 待实现。 |
| 点简写 | 待实现。 |
| switch 表达式、模式赋值 | 待实现。 |
| throw | 待实现。 |
| await、泛型函数值实例化 | 待实现。 |

[IR 行为对照](../test/ir/lowering_test.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/expressions.md)。

## 规范依据

[主规范 §17](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[空安全](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md)、[空感知元素](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.8/null-aware-elements/feature-specification.md)、[点简写](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.10/dot-shorthands/feature-specification.md)、[Records](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/records/feature-specification.md)。
