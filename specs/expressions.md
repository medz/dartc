# 表达式

表达式按 Dart 规定的顺序求值。短路右侧保持条件执行。

| 特性 | 当前 IR 范围 |
| --- | --- |
| null、bool、整数、double、字符串 | 支持这五种字面量，包括最小有符号 int、整数在 double 上下文中的解释和负零。 |
| 普通、raw、多行、插值与相邻字符串 | 支持无插值的字符串及其相邻拼接。常量声明和默认值可包含常量插值，运行时插值待实现。 |
| Symbol 字面量 | 待实现。 |
| Record 字面量 | 支持空、单字段、位置与命名混合的 record，以及嵌套和 const record。字段按源码顺序求值，支持字段读取和结构相等。见[record 样本](../test/lowering/fixtures/records.dart)。 |
| 可变/const List | 待实现。 |
| Set、Map 字面量 | 待实现。 |
| List if/for/for-in、spread | 待实现。 |
| 空感知集合元素 | 待实现。 |
| 集合 if-case、模式循环 | 待实现。 |
| 常量运算、类型测试与转换 | 常量声明和默认值支持标量和 record 常量表达式。`is`、`is!` 和 `as` 支持[已表示的类型](types.md)及其可空形式。record 按形状和字段运行值检查，转换失败抛出 TypeError。见[类型检查样本](../test/lowering/fixtures/type_checks.dart)。 |
| 算术、位运算、移位、关系与短路 | int 的 `+`、`-`、`*`、`<`、`<=`、`>`、`>=` 以及 bool 的 `&&`、`\|\|`。支持标量相等及 record 字段的逐项相等比较。 |
| 条件表达式 `c ? a : b` | 按条件只计算一个分支，保留该分支的值、写入和异常。结果可为已支持的值类型或 void。见[条件样本](../test/lowering/fixtures/conditionals.dart)。 |
| 赋值、复合赋值、增减、索引赋值 | 已初始化的局部变量和参数可在表达式中使用 `=`。整数还支持 `+=`、`-=`、`*=` 和前后缀 `++`、`--`。其他复合运算、属性和索引赋值待实现。 |
| 函数、构造器、成员调用与提取 | 支持非泛型顶层函数、静态方法、生成式构造器和带函数体的工厂。见[类](classes.md)。 |
| 空短路、空断言与级联 | 支持 `??`、局部变量及参数的 `??=`、与 null 的比较，以及后缀 `!`。record 的 `?.` 会短路同一条链上的字段读取和空断言，括号结束这条链。其他成员、索引和级联待实现。见[空安全样本](../test/lowering/fixtures/nullability.dart)。 |
| 点简写 | 待实现。 |
| switch 表达式、模式赋值 | switch 表达式支持标量与 record 模式及守卫。模式赋值可将嵌套 record 解构到局部变量和参数，表达式结果为原右值。见[模式](patterns.md)。 |
| throw、rethrow | 同步函数可抛出非空值，后续实参和更新表达式不再执行。catch 中的 rethrow 保留原异常对象和栈轨迹。 |
| await、泛型函数值实例化 | 待实现。 |

复合赋值先读取左侧旧值，再计算右侧。例如 `x += (x = 3)` 把旧值加上 3。简单赋值、复合赋值和前缀增减的结果都是写入值，后缀增减的结果是旧值。短路跳过的操作数不会写入变量。见[赋值样本](../test/lowering/fixtures/updates.dart)和[SDK 行为对照](../test/lowering/lowering_test.dart)。

发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/expressions.md)。

## 规范依据

[主规范 §17](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[空安全](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md)、[空感知元素](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.8/null-aware-elements/feature-specification.md)、[点简写](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.10/dot-shorthands/feature-specification.md)、[Records](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/records/feature-specification.md)。
