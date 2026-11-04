# 表达式

表达式按 Dart 规定的顺序求值。短路右侧保持条件执行。

| 特性 | 当前 IR 范围 |
| --- | --- |
| null、bool、整数、double、字符串 | 支持这五种字面量，包括最小有符号 int、整数在 double 上下文中的解释和负零。 |
| 普通、raw、多行、插值与相邻字符串 | 支持普通、raw、多行、运行时插值与相邻拼接；保留插值表达式和 toString 的求值顺序、虚派发及异常。见[字符串样本](../test/lowering/fixtures/strings.dart)。 |
| Symbol 字面量 | 待实现。 |
| Record 字面量 | 支持空、单字段、位置与命名混合的 record，以及嵌套和 const record。字段按源码顺序求值及隐式转换，失败时跳过后续字段；支持字段读取和结构相等。见[record 样本](../test/lowering/fixtures/records.dart)。 |
| 可变/const List | 支持保留实际元素类型的可变 List 字面量、length、索引读写、sublist、add 和 addAll。const List、集合构造器和完整 SDK API 待实现。 |
| Set、Map 字面量 | 支持可变类型化字面量、插入顺序、重复项处理及用户相等和 hashCode。支持 Set 的 length/add/addAll、Map 的 length/索引读写/containsKey。const 集合和完整 SDK API 待实现。 |
| List if/for/for-in、spread | 支持 List、Set、Map 的 if/else、三段式 for、同步 for-in 和 spread，按源码顺序执行。spread 使用源 Iterable 的 iterator 或 Map 的 forEach。 |
| 空感知集合元素 | 支持空感知元素、spread 以及 Map 的空感知 key/value。空 key 跳过对应 value 的求值。 |
| 集合 if-case、模式循环 | 支持已表示模式及 when 守卫的 if-case，以及 record、List 和 Map 模式循环头。见[集合样本](../test/lowering/fixtures/collections.dart)。 |
| 常量运算、类型测试与转换 | 常量声明和默认值支持标量和 record 常量表达式。`is`、`is!` 和 `as` 支持[已表示的类型](types.md)及其可空形式。record 按形状和字段运行值检查，转换失败抛出 TypeError。见[类型检查样本](../test/lowering/fixtures/type_checks.dart)。 |
| 算术、位运算、移位、关系与短路 | 支持 int 的算术、按位运算和移位，以及 double、num 和混合数字的算术与大小比较。保留整数精度、NaN、无穷及负零。支持 bool 的逻辑运算、标量相等及 record 字段逐项相等。见[数字样本](../test/lowering/fixtures/numeric.dart)。 |
| 条件表达式 `c ? a : b` | 按条件只计算一个分支，保留该分支的值、写入和异常。结果可为已支持的值类型或 void。见[条件样本](../test/lowering/fixtures/conditionals.dart)。 |
| 赋值、复合赋值、增减、索引赋值 | 局部变量、参数、实例属性和用户定义的索引支持简单赋值、复合赋值及前后缀增减。接收者与索引仅求值一次，`??=` 只在读到 null 时求值右侧并写入。见[属性与索引样本](../test/lowering/fixtures/nominal/updates.dart)。 |
| 函数、构造器、成员调用与提取 | 支持普通和泛型顶层函数、实例与静态方法、实例 getter、super 成员、生成式构造器、工厂及工厂重定向。类成员和构造器保留类类型实参，可提取函数、方法及构造器，显式或按上下文实例化后进行间接调用。见[类](classes.md)。 |
| 空短路、空断言与级联 | 支持 `??`、可赋值位置的 `??=`、与 null 的比较，以及后缀 `!`。实例与 record 的空感知访问会短路同一条链上的成员、实参、索引、赋值和空断言，括号结束这条链。支持普通与空感知级联，接收者只求值一次；空接收者跳过所有级联段。见[级联样本](../test/lowering/fixtures/cascades.dart)。见[空安全样本](../test/lowering/fixtures/nullability.dart)。 |
| 点简写 | 支持已表示类型的构造器、工厂、静态方法和显式静态 getter 的点简写。泛型和枚举仍受各自类型范围限制。见[点简写样本](../test/lowering/fixtures/dot_shorthand.dart)。 |
| switch 表达式、模式赋值 | switch 表达式支持已表示模式及守卫。模式赋值可将嵌套 record、List 和 Map 解构到局部变量和参数，表达式结果为原右值。见[模式](patterns.md)。 |
| throw、rethrow | 同步函数可抛出非空值，后续实参和更新表达式不再执行。catch 中的 rethrow 保留原异常对象和栈轨迹。 |
| await、泛型函数值实例化 | 支持泛型函数值的显式和上下文隐式实例化，保留类型实参及函数身份。await 待实现。 |

复合赋值先读取左侧旧值，再计算右侧。例如 `x += (x = 3)` 把旧值加上 3。简单赋值、复合赋值和前缀增减的结果都是写入值，后缀增减的结果是旧值。短路跳过的操作数不会写入变量。见[赋值样本](../test/lowering/fixtures/updates.dart)和[SDK 行为对照](../test/lowering/lowering_test.dart)。

发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/expressions.md)。

## 规范依据

[主规范 §17](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[空安全](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md)、[空感知元素](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.8/null-aware-elements/feature-specification.md)、[点简写](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.10/dot-shorthands/feature-specification.md)、[Records](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/records/feature-specification.md)。
