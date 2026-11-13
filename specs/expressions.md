# 表达式

表达式按 Dart 规定的顺序求值。短路右侧保持条件执行。

| 特性 | 当前 IR 范围 |
| --- | --- |
| null、bool、整数、double、字符串 | 支持这五种字面量，包括最小有符号 int、整数在 double 上下文中的解释和负零。 |
| 普通、raw、多行、插值与相邻字符串 | 支持普通、raw、多行、运行时插值与相邻拼接；保留插值表达式和 toString 的求值顺序、虚派发及异常。见[字符串样本](../test/frontend/lowering/fixtures/strings.dart)。 |
| Symbol 字面量与构造 | 支持公开字面量、Symbol(String) 的普通/const 构造、构造器提取、empty/unaryMinus 与嵌套公开常量；const 按规范身份复用，普通构造保留独立身份。相等、hashCode、Symbol 类型的 toString 调用/提取及对象模式保留用户实现的虚派发。私有字面量以名称和定义库保留身份，同库 part 共享身份，跨库同名与字符串构造的 Symbol 不相等。常量折叠、集合键、默认参数和 Invocation 使用相同身份，见[原生验证](../test/compiler/symbols_test.dart)。构造器接收任意字符串，包括以 `_` 开头但不带私有库身份的名字。见[Symbol 样本](../test/compiler/fixtures/public_symbols.dart)。 |
| Invocation 工厂与属性 | 支持 method/genericMethod/getter/setter 的直接调用及构造器提取、缺省参数、八个属性和对象模式；保留 Symbol 身份、类型实参、不可变浅快照及拷贝顺序。用户 implements/extends Invocation、抽象重声明及接口访问保留虚派发和继承默认 getter。不保证空参数集合在不同调用间共享身份，也不固定其内部实现类型。见[Invocation 样本](../test/frontend/lowering/fixtures/invocations.dart)。 |
| Record 字面量 | 支持空、单字段、位置与命名混合的 record，以及嵌套和 const record。字段按源码顺序求值及隐式转换，失败时跳过后续字段；支持字段读取和结构相等。见[record 样本](../test/frontend/lowering/fixtures/records.dart)。 |
| 可变/const List | 支持保留实际元素类型的可变 List 字面量、length、索引读写、sublist、add 和 addAll，以及 List.empty/filled/of/from/generate/unmodifiable 和 length setter。支持 const List 的内容和规范身份；原生集合范围见下文。 |
| Set、Map 字面量 | 支持可变类型化字面量、插入顺序、重复项处理及用户相等和 hashCode。支持 Set 的 length/add/addAll、Map 的 length/索引读写/containsKey/entries，以及 MapEntry 的普通与 const 构造、key/value。支持 const Set/Map；完整 SDK API 待实现。 |
| List if/for/for-in、spread | 支持 List、Set、Map 的 if/else、三段式 for、同步 for-in 和 spread，按源码顺序执行。sequence spread 使用源 Iterable 的 iterator；Map spread 需要逐项类型检查时使用 entries，否则使用 forEach。dynamic 源先核对 Iterable/Map 协议，再逐项转换。addAll 调用还在遍历前检查实际接收者要求的源类型。 |
| 空感知集合元素 | 支持空感知元素、spread 以及 Map 的空感知 key/value。空 key 跳过对应 value 的求值。 |
| 集合 if-case、模式循环 | 支持已表示模式及 when 守卫的 if-case，以及 record、List 和 Map 模式循环头。见[集合样本](../test/frontend/lowering/fixtures/collections.dart)。 |
| 常量运算、类型测试与转换 | 常量声明和默认值支持标量、record、List/Set/Map、普通用户对象、Type 及函数值常量。`is`、`is!` 和 `as` 支持[已表示的类型](types.md)及其可空形式。record 按形状和字段运行值检查，转换失败抛出 TypeError。见[类型检查样本](../test/frontend/lowering/fixtures/type_checks.dart)。 |
| 算术、位运算、移位、关系与短路 | 支持 int 的算术、按位运算和移位，以及 double、num 和混合数字的算术与大小比较。保留整数精度、NaN、无穷及负零。支持 bool 的逻辑运算、标量相等及 record 字段逐项相等。见[数字样本](../test/frontend/lowering/fixtures/numeric.dart)。 |
| 条件表达式 `c ? a : b` | 按条件只计算一个分支，保留该分支的值、写入和异常。结果可为已支持的值类型或 void。见[条件样本](../test/frontend/lowering/fixtures/conditionals.dart)。 |
| 赋值、复合赋值、增减、索引赋值 | 局部变量、参数、实例属性和用户定义的索引支持简单赋值、复合赋值及前后缀增减。接收者与索引仅求值一次，`??=` 只在读到 null 时求值右侧并写入。见[属性与索引样本](../test/frontend/lowering/fixtures/nominal/updates.dart)。 |
| 函数、构造器、成员调用与提取 | 支持普通和泛型顶层函数、实例与静态方法、实例 getter、super 成员、生成式构造器、工厂及工厂重定向。类成员和构造器保留类类型实参，可提取函数、方法及构造器，显式或按上下文实例化后进行间接调用。见[类](classes.md)。 |
| extension 方法、属性与运算符 | 支持已解析的隐式、显式 override 和未限定词法调用，保留接收者静态视图、类型实参、默认/命名参数、空感知与级联求值顺序。接收者检查先于实参；dynamic 隐式调用不查找 extension。支持实例 getter/setter、索引、运算符、复合赋值、`??=` 和前后缀更新；getter 返回的函数先读取再求值调用实参。方法提取及显式 call 提取复用普通闭包，隐式 extension call 调用复用静态目标；部分显式泛型运算符仍待实现，见[范围与已知 SDK 差异](extension-access.md)。 |
| dynamic 成员、运算符与更新 | 一条 DynamicDispatch 指令复用调用、属性与索引更新路径；支持动态级联、空感知链、赋值值、前后缀及 `??=`。所有实参先求值，再核对实际目标签名。`d.getter(arg())` 与 `(d.getter)(arg())` 保留不同的 getter/实参顺序。见[动态样本](../test/frontend/lowering/fixtures/dynamic_dispatch.dart)。 |
| 空短路、空断言与级联 | 支持 `??`、可赋值位置的 `??=`、与 null 的比较，以及后缀 `!`。实例与 record 的空感知访问会短路同一条链上的成员、实参、索引、赋值和空断言，括号结束这条链。支持普通与空感知级联，接收者只求值一次；空接收者跳过所有级联段。见[级联样本](../test/frontend/lowering/fixtures/cascades.dart)。见[空安全样本](../test/frontend/lowering/fixtures/nullability.dart)。 |
| 点简写 | 支持已表示类型的构造器、工厂、静态方法和显式静态 getter 的点简写。包含已表示的泛型类及枚举成员。见[点简写样本](../test/frontend/lowering/fixtures/dot_shorthand.dart)。 |
| switch 表达式、模式赋值 | switch 表达式支持已表示模式及守卫。模式赋值可将嵌套 record、List 和 Map 解构到局部变量和参数，表达式结果为原右值。见[模式](patterns.md)。 |
| throw、rethrow | 同步函数可抛出非空值，后续实参和更新表达式不再执行。dynamic 操作数先按普通检查转换为非空 Object，非空值保持原身份，null 产生 TypeError；转换失败遵循当前 catch/finally。catch 中的 rethrow 保留原异常对象和栈轨迹。 |
| await、泛型函数值实例化 | 支持普通异步函数中的 `await`，保留成功与异常两条恢复路径。见[异步函数](functions.md)。泛型函数值支持显式和上下文隐式实例化，保留类型实参及函数身份。 |

复合赋值先读取左侧旧值，再计算右侧。例如 `x += (x = 3)` 把旧值加上 3。简单赋值、复合赋值和前缀增减的结果都是写入值，后缀增减的结果是旧值。短路跳过的操作数不会写入变量。见[赋值样本](../test/frontend/lowering/fixtures/updates.dart)和[SDK 行为对照](../test/frontend/lowering/lowering_test.dart)。

发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/expressions.md)。

带点的 Symbol 字面量代表库名，按[规范的 Symbol 条款](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L9040-L9125)不受库私有规则限制，即使首段以 `_` 开头。固定 Dart VM 将 `#_prefix.name` 区分库；dartc 在此遵循规范，跨库共享身份，并与 `const Symbol('_prefix.name')` 相等。

内建 Symbol 的完整文本格式不承诺与 Dart VM 一致；原生检查验证直接调用、方法提取与插值使用相同派发结果，并保留用户重写的文本。

显式实例化要求非空的泛型函数值，`receiver?.method<T>` 仍是静态错误，包括未使用的声明。可以先提取 `receiver?.method`，再用 `value?.call<T>()` 进行空感知调用；已提升为非空的函数值和返回可空值的函数仍可实例化。analyzer 14.7 对部分链式实例化提前扩展了空短路，dartc 按当前规则补上拒绝检查；支持该语法的[上游问题 #4817](https://github.com/dart-lang/language/issues/4817)及[提案 #4816](https://github.com/dart-lang/language/pull/4816)尚未合并。见[静态验证](../test/frontend/analysis/nullable_instantiations_test.dart)。

## 规范依据

[主规范 §17](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[空安全](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md)、[空感知元素](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.8/null-aware-elements/feature-specification.md)、[点简写](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.10/dot-shorthands/feature-specification.md)、[Records](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/records/feature-specification.md)。

动态执行对照只覆盖已表示的用户成员和明确实现的核心操作。未知导入/SDK 实现及尚未表示的 typed noSuchMethod forwarder 不会被误报为缺失成员；已表示转发使用普通函数体执行入口及返回检查。NoSuchMethodError 的类型与传播已对照；宿主诊断文本对自定义类型实参和私有 Symbol 的呈现仍有限，不保证与 VM 文本一致。

NoSuchMethodError.withInvocation 的普通工厂调用与提取复用既有调用路径：构造返回新的错误对象，不触发接收者 noSuchMethod，也不提前读取用户 Invocation getter。支持类型判断、抛出、捕获和重新抛出的身份保持；原生构造和文本使用 SDK 错误类正文，方法、getter、setter 与 Invocation 信息见[错误文本验证](../test/compiler/object_text_test.dart)；VM 特有的匹配方法签名描述仍未提供，不保证错误文本与 VM 逐字一致。

动态调用 `g<String>('bad')` 遗漏必需命名实参时，传给 `noSuchMethod` 的 Invocation 应保留显式类型实参 `String`。在同一份 `shapeBeforeBounds` 样本上，macOS ARM64 的 Dart SDK 3.13.7 JIT 返回 111，SDK AOT 返回 101。IR 保留显式类型实参，结果为 111。对照使用 SDK 显式构造的 Invocation 和同一接收者的 `noSuchMethod`。[样本](../test/frontend/lowering/fixtures/dynamic_dispatch.dart)、[Invocation.typeArguments](https://api.dart.dev/dart-core/Invocation/typeArguments.html)。

## 原生相等与哈希

Object/Object? 视图的 `==`、`!=` 和 hashCode 按实际值选择实现。普通用户对象保留重写、异常和副作用；继承 Object 默认实现时使用身份相等与稳定身份哈希。null 的相等比较不调用用户运算符。int、double、bool 和 null 的内置行为不因装箱改变；数值相等保留整数精度及 NaN 规则，相等的 int/double 与正负零具有相同哈希。见[宽类型与数值边界验证](../test/compiler/bound_methods_test.dart)。函数与 Type 的规则分别见[函数值](functions.md)和[类型值](types.md)。

原生字符串按内容比较和哈希。record 支持构造、嵌套常量、位置与命名字段、结构相等、哈希和文本格式化；字段保留求值顺序，托管字段在回收后仍可读取。dynamic 读取按实际形状选择字段，函数字段可以调用，缺失字段和赋值产生 NoSuchMethodError。见[原生 record 验证](../test/compiler/records_test.dart)。哈希值不保证跨运行或编译版本相同，也不保证不等值的哈希不同。

record 的 `==` 按字段值比较，包括同一 record 含 NaN 的情况。SDK 3.14 JIT 的身份快捷判断会令样本中的 `pair == pair` 返回 true；dartc 按 [record 相等规则](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/records/feature-specification.md#equality)和 [Record.== 契约](../sdk/std/lib/core/record.dart)返回 false。该反例单独按规范断言，其余行为与 SDK 对照。

`identityHashCode` 支持普通调用，不调用用户重写的 hashCode。已支持的非 record 对象保持与 identical 相容的稳定哈希，数值与布尔值不因重复装箱改变结果，null 也可作为参数。见[原生身份哈希验证](../test/compiler/expandos_test.dart)。

## 原生整数除法、余数与移位

原生整数 `~/` 向零截断，`%` 返回非负欧几里得余数，`remainder` 返回与被除数同号的截断余数；结果遵循 64 位整数回绕。最小整数除以 -1 返回最小整数，相应余数为 0。三个操作遇到整数零除数均抛出 IntegerDivisionByZeroException，保留操作数求值顺序、typed catch 与 finally；忽略结果不会删除抛错。见 [~/ 契约](https://api.dart.dev/dart-core/num/operator_truncate_divide.html)、[% 契约](https://api.dart.dev/dart-core/num/operator_modulo.html)、[remainder 契约](https://api.dart.dev/dart-core/num/remainder.html)和[原生边界验证](../test/compiler/integer_operations_test.dart)。源码数值运算需要的异常类采用官方 SDK 声明，其 message 字符串与空 stackTrace getter 已接通；异常格式化仍未验证。

原生浮点 `%` 与 `remainder` 已接通直接调用、装箱 `num`、dynamic 和绑定方法。混合整数操作先按 SDK 正文转换为 double；`remainder` 保留被除数符号及负零，`%` 的零结果为正零。非有限被除数、NaN 或零除数返回 NaN；有限值除以无穷时 remainder 保留原值，负值的 modulo 为正无穷。官方 `_Double` 正文复用，实际 external 缺口由普通 Dart [SDK patch](../sdk/patches/remainder.dart) 实现。有限输入使用精确二进制整数余数并舍入到 double 的[独立参考计算](../test/support/floating_reduction.dart)，[原生验证](../test/compiler/numeric_methods_test.dart)另覆盖非有限值和调用形状。

浮点 modulo 的严格上界仍有契约疑点：[公开文档](https://api.dart.dev/dart-core/double/operator_modulo.html)要求结果小于除数绝对值，但[固定 SDK 的 `DartModulo`](https://github.com/dart-lang/sdk/blob/416e33b0ffaef062a60ec966bb8c82ed2b83f128/runtime/vm/runtime_entry.cc)先求 fmod 再加除数绝对值，可能向上舍入到该值，例如 `-double.minPositive % 1.0 == 1.0`。当前保留这一舍入结果，不擅自 clamp，也不据此宣称严格上界已经满足。

只要 `~/` 的实际操作数之一是 double，按 `(a / b).truncate()` 执行；整数操作数先参与 double 除法，有限商超出原生 int 范围时饱和，非有限商抛出 UnsupportedError。boxed num 的两个实际整数仍走精确整数除法，不提前转换为 double。求值顺序与忽略结果时的异常均保留。依据[固定 SDK 的 num 契约](https://github.com/dart-lang/sdk/blob/416e33b0ffaef062a60ec966bb8c82ed2b83f128/sdk/lib/core/num.dart)，见[数值转换原生验证](../test/compiler/numeric_conversions_test.dart)。

原生 `<<`、`>>`、`>>>` 及其复合赋值保留完整的位移计数。左移按 64 位回绕，算术右移补符号位，逻辑右移补零；计数大于等于 64 时，左移和逻辑右移为 0，算术右移为 0 或 -1。负计数抛出 ArgumentError，操作数只求值一次，忽略结果仍须抛错。错误的 message 保留负计数这个 int，name 与 invalidValue 为 null；这一载荷对应当前固定 SDK 的库行为，不扩大为跨版本语言保证。构造器与属性读取使用 SDK 的普通 Dart 实现，用户重写仍按实际接收者派发。见 [int 的原生整数范围](https://api.dart.dev/dart-core/int-class.html)、[逻辑右移规范](https://github.com/dart-lang/language/blob/main/accepted/2.14/triple-shift-operator/feature-specification.md)和[原生边界验证](../test/compiler/integer_operations_test.dart)。

## 布尔文本转换

`bool.parse` 和 `bool.tryParse` 使用 SDK 的普通 Dart 实现，支持省略或显式指定 caseSensitive、函数值与原生 Bool 存储。默认只接受 `true`/`false`；关闭大小写敏感后只忽略 ASCII 字母大小写，不裁剪空白，不接受 `0`、`1` 或 Unicode 近似字符。失败时 parse 抛出保留原 source 的 FormatException，tryParse 返回 null。见[SDK 与原生对照](../test/compiler/boolean_text_test.dart)。

## 数字文本转换

`int.parse`、`int.tryParse`、`int.toString` 和 `int.toRadixString` 支持原生执行，包括静态及绑定方法值。进制为 2–36，字母数字不区分大小写，允许前导正负号和外围 Unicode 空白；显式进制的结果必须落在有符号 64 位范围内。省略 radix 的正数 `0x`/`0X` 前缀允许完整无符号 64 位值，并按相同位模式解释为有符号 int。无效文本和溢出使 parse 抛出 FormatException、tryParse 返回 null；异常保留原 source。无效进制的非空输入抛出 RangeError。格式化使用小写数字，对最小 int 也满足往返契约。FormatException 的具体消息和错误定位不承诺与 SDK 实现逐字相同。

`double.parse`、`double.tryParse`、`num.parse` 和 `num.tryParse` 支持直接调用及函数值。double 接受十进制小数、指数、带符号的 Infinity/NaN 和外围空白，不接受十六进制或数字分隔符；保留负零、次正规数以及溢出到无穷、下溢到零的符号，舍入到最接近的 binary64，恰好居中时取偶数尾数。无效输入使 parse 抛出 FormatException、tryParse 返回 null。num 先尝试整数，成功时保留 int 类型，否则尝试 double。见[库契约](../sdk/std/lib/core/double.dart)、[原生行为对照](../test/compiler/object_text_test.dart)和[舍入边界](../test/sdk/fixtures/decimal_text.dart)。

解析与格式化复用官方 Dart 入口，真正外部的十进制转换由 [SDK 目标实现](../sdk/patches/decimal.dart)补齐；JSON 数字解析共用这一实现。

int、double 和 bool 通过 Object 视图调用 toString 使用实际实现。double 支持 toString、toStringAsFixed、toStringAsExponential 和 toStringAsPrecision，保留负零、非有限值、二进制浮点的十进制舍入及精度范围检查；可提取为绑定方法值。fixed/exponential 的显式小数位数为 0–20，precision 的有效位数为 1–21；非法精度在 NaN、无穷的处理之前抛出 RangeError。省略 exponential 的精度时输出最短指数形式。已接通同一封闭程序内的 dynamic 成员派发、getter 返回函数的调用、方法提取、签名和类型检查及 noSuchMethod；缺失成员与不匹配签名保留 Invocation 和求值顺序。见[原生文本对照](../test/compiler/object_text_test.dart)。依据为[固定 SDK int 声明](https://github.com/dart-lang/sdk/blob/416e33b0ffaef062a60ec966bb8c82ed2b83f128/sdk/lib/core/int.dart)，验证见[SDK 与原生整数文本对照](../test/compiler/integer_text_test.dart)。

## 原生转整数与字符串常量

`abs`、`sign`、`isNaN`、`isInfinite`、`isFinite`、`isNegative`、`compareTo` 和 `clamp` 支持 int、double 及装箱 num，包括直接调用、虚调用和方法提取。保留整数边界、负零、NaN 的排序及无效上下界的 ArgumentError；clamp 返回选中的原值或边界值。装箱 num 的加、减、乘、除、取负和 toDouble 根据实际数值类型执行，支持跨调用、返回及泛型传值。见[原生数值方法验证](../test/compiler/numeric_methods_test.dart)及[固定 SDK num 契约](https://github.com/dart-lang/sdk/blob/416e33b0ffaef062a60ec966bb8c82ed2b83f128/sdk/lib/core/num.dart)。

`toInt`、`truncate`、`floor`、`ceil` 和 `round` 支持 int、double 及装箱 num 接收者。整数保持全部 64 位；浮点的 toInt/truncate 向零舍入，floor 向下、ceil 向上，round 就近舍入且半数远离零。有限值超出有符号 64 位范围时饱和到对应边界；正负零转换为 0，NaN 与正负无穷抛出 UnsupportedError。求值和 finally 顺序不变，未使用转换结果仍须执行可能抛错的转换。错误通过 SDK 构造器携带当前固定版本的字符串消息，用户同名成员与 extension 不会被拦截。见 [num.truncate](https://api.dart.dev/dart-core/num/truncate.html)、[num.round](https://api.dart.dev/dart-core/num/round.html)、[double.round](https://api.dart.dev/dart-core/double/round.html)和[原生转换验证](../test/compiler/numeric_conversions_test.dart)。

`truncateToDouble`、`floorToDouble`、`ceilToDouble` 和 `roundToDouble` 同样支持 int、double 及装箱 num，返回 double 而不饱和到整数范围。已经为整数的 double、正负零和非有限值保持不变；负数舍入到零得到 -0.0，roundToDouble 的半数远离零。int 接收者仅执行通常的 int 到 double 转换。实现先排除绝对值大于等于 2^52 的 double，再复用安全范围内的整数舍入计算，不把 NaN 或无穷送进整数转换。契约见[固定 SDK double 声明](https://github.com/dart-lang/sdk/blob/416e33b0ffaef062a60ec966bb8c82ed2b83f128/sdk/lib/core/double.dart)，行为及负零位模式由同一[原生转换验证](../test/compiler/numeric_conversions_test.dart)覆盖。

原生字符串常量保留 UTF-16 码元和规范身份，可在普通参数、字段与错误载荷中传递。空串、非 BMP 字符及孤立代理项不会被重新编码或规范化；见[常量数据验证](../test/codegen/object_values_test.dart)。支持 `String.length` 和 `codeUnitAt(index)` 的直接调用、泛型接收者和方法值；长度按 UTF-16 码元计数，读取保留零码元、代理项和非 BMP 字符的两个码元。`index < 0` 或 `index >= length` 时，在访问载荷前抛出 RangeError；未使用结果也保留边界检查、求值和 catch/finally 顺序。见 [`length` 契约](https://api.dart.dev/stable/3.13.7/dart-core/String/length.html)、[`codeUnitAt` 契约](https://api.dart.dev/stable/3.13.7/dart-core/String/codeUnitAt.html)、[IR 契约](../test/ir/strings_test.dart)和[原生读取验证](../test/compiler/strings_test.dart)。

`String.fromCharCode` 支持直接调用和构造器值；0 到 0xffff（含单独代理项）生成一个码元，0x10000 到 0x10ffff 生成代理对，范围外抛出 RangeError。`[]` 从 `codeUnitAt` 结果构造单码元字符串，越界保留接收者、下标的求值及清理顺序。`+` 按顺序连接全部码元，空串与孤立代理项不改变内容；动态字符串经过回收、绑定方法及跨入口全局保存后仍可读取。`==`、`!=` 和 hashCode 按内容处理，包括 Object 视图；相等字符串的哈希相同，不要求与 SDK 的具体哈希值一致。见 [`fromCharCode`](https://api.dart.dev/stable/3.13.7/dart-core/String/String.fromCharCode.html)、[`[]`](https://api.dart.dev/stable/3.13.7/dart-core/String/operator_get.html)及[构造、拼接与回收验证](../test/compiler/strings_test.dart)。插值使用已支持接收者的普通 toString；Unicode 大小写转换和 RegExp 尚未接通。

`String.fromCharCodes` 支持 Iterable<int>、构造器值和可选 start/end。范围要求 `0 <= start <= end`；输入不足时截短，跳过的元素不读 current，空区间不获取迭代器。16 位值保留为码元，较大合法码点分解为代理对；无效码点抛出 ArgumentError。自定义迭代器的 getter、moveNext、current、异常与 finally 保留求值顺序。`String.codeUnits` 返回不可修改的 List<int>，支持长度、索引、迭代及跨回收/入口保存，修改方法仍执行其参数检查后拒绝写入。依据为 [`fromCharCodes`](https://api.dart.dev/stable/3.13.7/dart-core/String/String.fromCharCodes.html)和[固定 SDK String 声明](https://github.com/dart-lang/sdk/blob/416e33b0ffaef062a60ec966bb8c82ed2b83f128/sdk/lib/core/string.dart)。[原生验证](../test/compiler/strings_test.dart)也覆盖从借用的 Int64 指针输入到有容量上限的 UTF-16 输出，以及调用方释放输入后字符串仍存活。

`substring`、`compareTo`、`startsWith`、`endsWith`、`indexOf`、`lastIndexOf`、`contains`、`trim/trimLeft/trimRight`、`*`、`padLeft/padRight`、`replaceRange`、`replaceFirst/replaceFirstMapped`、`replaceAll/replaceAllMapped`、`split` 和 `splitMapJoin` 支持原生执行。String 的 Pattern 方法保留空匹配和 UTF-16 偏移；自定义 Pattern 保留方法派发及调用副作用。`split` 的空字符串模式逐码元分割，`splitMapJoin` 的空字符串模式保留完整代理对；回调按匹配顺序执行。`runes` 复用 SDK 的码点迭代规则，孤立代理项保持原值。范围错误在访问载荷前抛出，结果可跨 GC 和后续原生调用保存。见[原生与 SDK 对照](../test/compiler/string_operations_test.dart)。

`padLeft` 与 `padRight` 在减去字符串长度前处理负宽度，包括最小 64 位整数，遵循 [String 的公开契约](../sdk/std/lib/core/string.dart)；不继承固定 SDK 正文先减法造成的溢出。负宽度、普通补白和方法提取由同一组原生字符串测试覆盖。

静态类型限定为 String 或 null 的插值已支持原生执行，null 转换成文本 `null`，其余字符串保留码元；插值表达式先按源码顺序求值。固定 SDK 的 `Expando.toString` 使用此路径，见[原生验证](../test/compiler/expandos_test.dart)；一般值的插值格式化仍是缺口。

## 原生 List

支持可变 List 字面量、`List.empty`、`List.filled`、length 读写、索引读写及 add。构造器保留实际元素类型、默认 growable 参数与函数值调用；filled 的所有初始槽引用同一个 fill。固定长度列表允许改写元素，改变长度的操作抛出 UnsupportedError。可增长列表缩短时移除尾部元素，再增长时填入 null；非可空元素类型的列表不能通过 length 增长。依据为 [`List.filled`](https://api.dart.dev/stable/3.13.7/dart-core/List/List.filled.html)、[`List.empty`](https://api.dart.dev/stable/3.13.7/dart-core/List/List.empty.html)和 [`length`](https://api.dart.dev/stable/3.13.7/dart-core/List/length.html)。

协变视图的写入按实际接收者元素类型检查，失败不修改列表；检查先于方法体中的边界与可变性检查。下标访问保持接收者、下标及赋值右侧的求值顺序。超大元素数量不能在转换为存储字节数时回绕；超出存储范围或分配失败抛出可捕获的 `OutOfMemoryError`。列表及元素经过移动回收、别名、循环引用和全局保存后保持身份与内容。用户实现的 List 保留普通虚调用和方法提取，不使用内置列表布局。见[原生 List 验证](../test/compiler/lists_test.dart)和 [IR 操作契约](../test/ir/collections_test.dart)。

const List 保留实际元素类型、嵌套内容和规范身份，支持读取及元素参与的已有原生行为；[]=/add/length setter 在写入前拒绝不可变列表，协变参数检查仍先执行。常量与其元素在回收及全局保存后保留身份；不可变、固定长度和可增长列表共用索引读取行为。

同步 for-in、iterator、moveNext、current 和 elementAt 已接通普通派发，包括自定义 Iterable/Iterator、提取的 moveNext 方法及迭代器跨入口保存。内置列表按索引顺序遍历，元素改写可以被后续步骤读取；两次迭代步骤之间长度变化时抛出 ConcurrentModificationError。循环只在 moveNext 返回 true 后读取 current，异常仍执行 finally；在未改变集合且迭代完成后，再次 moveNext 返回 false。不把首次移动前、结束后或 moveNext 抛错后的 current 固化为特定结果。依据为 [List 迭代约束](https://api.dart.dev/stable/3.13.7/dart-core/List-class.html)、[Iterator.current](https://api.dart.dev/stable/3.13.7/dart-core/Iterator/current.html)和 [Iterator.moveNext](https://api.dart.dev/stable/3.13.7/dart-core/Iterator/moveNext.html)，验证见[原生 List 与迭代用例](../test/compiler/lists_test.dart)。

List.addAll 支持普通调用、方法提取及用户重写，先检查实际元素类型要求的 Iterable 参数，再检查目标可增长性；固定长度和 const List 即使追加空源也拒绝修改。字面量 spread 按迭代顺序逐项转换元素，支持 dynamic 源和 null-aware spread；类型错误或迭代异常停止后续求值并保留 finally。追加及展开后的元素保持别名，经过回收和跨入口保存后仍可读取。依据为 [List.addAll](https://api.dart.dev/stable/3.13.7/dart-core/List/addAll.html)和[语言规范的集合元素求值](https://github.com/dart-lang/language/blob/main/specification/dartLangSpec.tex#L9518)，验证见[原生 List 用例](../test/compiler/lists_test.dart)。

`List.of` 与 `List.from` 支持直接及构造器函数值调用、默认可增长和显式固定长度结果。of 的 Iterable 参数按目标元素类型整体检查，from 逐项检查；保留迭代顺序、用户迭代器异常和 finally。新列表拥有独立的元素槽，元素对象仍共享引用；固定长度副本允许索引写入。依据为 [List.of](https://api.dart.dev/stable/3.13.7/dart-core/List/List.of.html)与 [List.from](https://api.dart.dev/stable/3.13.7/dart-core/List/List.from.html)。

`sublist` 支持省略或显式 null 的 end、空范围和边界错误。内置 List、const/固定长度列表与 String.codeUnits 的切片返回独立的可增长 List，保留实际元素类型和共享对象；用户重写和方法值使用选中实现的默认参数。列表模式中的命名 rest 同样复制相应元素。依据为 [List.sublist](https://api.dart.dev/stable/3.13.7/dart-core/List/sublist.html)，验证见[SDK 与原生 List 对照](../test/compiler/lists_test.dart)。

`List.generate` 按索引顺序调用生成器，支持固定长度结果；`List.unmodifiable` 复制元素槽。不可修改列表拒绝修改操作，包括空源、空范围和不命中元素的操作。列表支持默认 Comparable 排序、重叠 setRange、insertAll、replaceRange、removeWhere、reversed、asMap 和 cast 视图。惰性 Iterable 的 where/map/take/skip/fold/any/every 保留遍历顺序与回调。标量 typed_data 的范围见[标准库](libraries.md)。

非空 `setRange` 要求非负 skipCount，且跳过后有足够的源元素。固定 SDK 3.14.0 的 VM 固定长度列表对一般 Iterable 漏检这两项，可能只写入部分元素而正常返回；dartc 对负 skipCount 抛出 RangeError，对不足的输入抛出 StateError。依据为[公开范围复制契约](../sdk/std/lib/core/list.dart)与[通用 List 实现](../sdk/std/lib/collection/list.dart)，[独立预期验证](../test/compiler/object_text_test.dart)不采用该 VM 行为。

## 原生 Set

支持可变与 const Set 字面量，Set/LinkedHashSet/HashSet 的普通、identity/from/of 构造，以及 Set.unmodifiable、插入、删除、查询、遍历和集合运算。默认 Set 保留插入顺序；重复的相等值保留最先插入的对象，lookup 返回该对象。自定义 equals/hashCode/isValidKey 与 toSet 副本保持相等策略。不可修改集合拒绝空修改；cast 视图保留底层元素类型检查。结构变化使正在遍历的迭代器抛出 ConcurrentModificationError。见[原生集合对照](../test/compiler/object_text_test.dart)。

## 原生 Map

支持可变 Map 字面量和 `Map()`，结果满足 `LinkedHashMap<K, V>` 的类型关系。索引读写、containsKey、length、remove、clear 和 keys 保留插入顺序；更新相等键的值保留原键对象与位置，删除后重新插入移到末尾。不存在的键返回 null，containsKey 可区分缺失键与值为 null 的条目。null 键、整数与相等浮点数的键查询遵循 Dart 相等和哈希契约，clear 不要求键与自身相等。依据为 [Map](https://api.dart.dev/stable/3.13.7/dart-core/Map-class.html) 和 [LinkedHashMap](https://api.dart.dev/stable/3.13.7/dart-collection/LinkedHashMap-class.html)。

协变视图的写入按实际键和值类型检查；类型错误、hashCode 或 == 抛错时不执行该次条目写入，异常保留 catch/finally。keys 是实时视图，迭代器检查新增、删除及清空等结构修改；仅替换已有值不改变键的迭代顺序。支持 values、entries、forEach、addAll、putIfAbsent 和 update 的普通库行为，以及用户 Map 重写、方法值和已有 Map 模式。键、值和迭代状态在移动回收及跨原生入口保存后保持有效，用户哈希和相等回调中也可分配。见[原生 Map 验证](../test/compiler/maps_test.dart)和 [IR 操作契约](../test/ir/collections_test.dart)。

`const Map` 使用 SDK 不可变 Map 的查询与迭代规则，保留键顺序、类型参数与常量身份；数字相等键、Type 键和 GC 后查询见[原生 Map 验证](../test/compiler/maps_test.dart)。写入、remove 和 clear 抛出 UnsupportedError。`HashMap` 支持默认、自定义 equals/hashCode/isValidKey 和 identity 构造，查询不兼容类型的键按契约处理；普通 SDK 工厂继续使用这些入口。见[常量与自定义哈希验证](../test/compiler/finalizers_test.dart)。Map spread 保留逐项转换和求值顺序。Map.from/of/fromEntries/fromIterables/unmodifiable、identity、map、update、putIfAbsent、removeWhere 与 cast 视图使用 SDK 算法；不可修改 Map 复制输入并拒绝空修改。List、Set、Map 的 toString 调用元素的实际方法，并终止对循环容器的递归。见[原生集合与格式化对照](../test/compiler/object_text_test.dart)。

## JSON 与 UTF-8

`jsonEncode`、`jsonDecode`、JsonEncoder 和 JsonDecoder 支持原生执行，保留数字、字符串转义、嵌套集合、重复键的后值、缩进、reviver 遍历顺序及 toEncodable/toJson 回调。非法文本抛出 FormatException；非字符串 Map 键、非有限数和无法转换的对象抛出 JsonUnsupportedObjectError，循环容器抛出 JsonCyclicError。支持分块 JSON 解码及 UTF-8 解码与 JSON 解码的组合转换。见[固定 SDK 契约](../sdk/std/lib/convert/json.dart)和[原生行为验证](../test/compiler/object_text_test.dart)。

UTF-8 编解码保留有效码点；编码将孤立 UTF-16 代理项替换为 U+FFFD，解码忽略开头的 BOM。解码支持任意字节处分块、严格错误及 allowMalformed 替换模式；不完整序列在关闭时处理。依据为[UTF-8 契约](../sdk/std/lib/convert/utf.dart)，验证覆盖多字节边界、BOM 分块、超长编码、代理项、越界码点和截断输入。

StringConversionSink.addSlice 的 `isLast: true` 必须关闭输入，并让 JSON 输出 sink 收到唯一结果。固定 SDK 3.14.0 的字符串 JSON sink 仅完成解析，遗漏结果交付和输出关闭；dartc 按[addSlice 契约](../sdk/std/lib/convert/string_conversion.dart)执行完整关闭。[分块验证](../test/compiler/object_text_test.dart)分别检查显式 close 与最后一个 slice，后者的预期不采用该 SDK 错误行为。

## 数值比较与 SDK 差异

[`num.==`](https://api.dart.dev/stable/3.13.7/dart-core/num/operator_equals.html) 要求 int 与 double 具有相同数值；[`num.<`](https://api.dart.dev/stable/3.13.7/dart-core/num/operator_less.html) 按数值大小比较。正负零在这些运算符下相等；NaN 与任何值不等，四种大小关系均为假。整数先舍入成 double 再比较不满足这一契约。例如 `9007199254740993 > 9007199254740992.0` 应为真，两者相等应为假；最大 int 小于 `9223372036854775808.0`。

SDK 3.13.7 的 VM JIT/AOT 在这些边界丢失整数精度。官方 [SDK #64728](https://github.com/dart-lang/sdk/issues/64728) 确认把最大整数与其舍入 double 判为相等属于实现错误。IR 数值操作及已接通的原生比较按原始数值执行；[独立数值预期](../test/support/numeric_order.dart)将有限 double 展开为精确整数比例，[原生验证](../test/compiler/mixed_numeric_test.dart)覆盖边界、相邻浮点值、随机位模式、两种操作数顺序和副作用。

analyzer 14.7 的常量求值也存在相同的精度问题，还会将 `0.0 == -0.0` 判为假。当前常量声明、局部常量、函数默认值、条件选择、集合及 record 内容、构造器实参和导出注解中的六种数值比较使用精确数值关系；正负零在比较下相等，`identical` 仍区分其身份。常量引用与别名使用同一规则。原生目标的常量 `identical` 区分 int 与 double，即使数值相等；通过 double 上下文解释的整数字面量仍是 double，条件、默认参数和 const 断言使用这一确定结果。见[数值原生验证](../test/compiler/numeric_methods_test.dart)。[常量验证](../test/frontend/lowering/constant_safety_test.dart)检查数值边界、嵌套内容及进入 IR 的值；[导出验证](../test/frontend/lowering/native_exports_test.dart)检查注解名称及常量别名的类型选择。

构造器常量求值支持参数默认值、字段初始化、断言、泛型代换、super/this 调用及工厂重定向，并保留参数和字段的类型检查。省略的工厂实参采用最终目标默认值；const 断言不受运行时断言开关影响。[构造器样本](../test/frontend/lowering/fixtures/constant_safety/numeric_constructor.dart)覆盖这些路径，以及枚举和 extension type 的常量结果。

分析阶段检查常量声明、默认值、注解、const 对象与集合表达式及模式中的常量表达式，包括未使用声明、不可达代码和已纳入分析的依赖库。常量求值错误在进入 lowering 前报告；重新求值成功的表达式可以通过上游因精度丢失而误报的断言或赋值检查，其余诊断继续保留。[静态检查样本](../test/frontend/analysis/checked_libraries_test.dart)覆盖误报、漏报及同一文件中的真实错误。

常量集合按实际求值结果检查元素类型、primitive equality、重复 Set 元素和 Map 键。未选中的分支仍须满足静态类型及潜在常量要求；空 spread 和被 null-aware 项跳过的表达式也不能隐藏静态类型错误。null-aware Map 键为 null 时不求值对应值，非 null 的 null-aware 元素不跳过后续元素。[集合常量验证](../test/frontend/analysis/collection_constants_test.dart)覆盖合法结果和静态错误。

模式常量、Map 模式重复键与 switch 穷尽性使用同一求值结果，覆盖常量别名、record、枚举及 sealed 层次；带守卫的 case 不保证覆盖。见[模式常量验证](../test/frontend/analysis/pattern_constants_test.dart)。原始 analyzer 对象仍保留上游诊断，包含可能受错误常量折叠影响的不可达警告；会话验收与 IR 转换使用重新检查的结果。

运行时 `identical` 支持普通调用和函数值调用，不执行用户的 `==`。整数按值、double 按位模式比较身份，区分正负零及不同 NaN 位模式；其余已支持原生存储的非 record 对象保持引用身份。record 不承诺持久身份，原生运行时的 identical 对 record 返回 false；相等比较仍访问各字段。见[声明绑定验证](../test/frontend/lowering/identity_test.dart)、[原生身份验证](../test/compiler/pointer_values_test.dart)和 [`identical` 契约](https://api.dart.dev/dart-core/identical.html)。

跨 int/double 的 `identical` 常量结果仍未接通；analyzer 为这类依赖目标表示的判断保留未知值，当前转换会明确拒绝，不能把未知值当作 false。
