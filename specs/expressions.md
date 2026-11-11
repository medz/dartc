# 表达式

表达式按 Dart 规定的顺序求值。短路右侧保持条件执行。

| 特性 | 当前 IR 范围 |
| --- | --- |
| null、bool、整数、double、字符串 | 支持这五种字面量，包括最小有符号 int、整数在 double 上下文中的解释和负零。 |
| 普通、raw、多行、插值与相邻字符串 | 支持普通、raw、多行、运行时插值与相邻拼接；保留插值表达式和 toString 的求值顺序、虚派发及异常。见[字符串样本](../test/frontend/lowering/fixtures/strings.dart)。 |
| Symbol 字面量与构造 | 支持公开字面量、Symbol(String) 的普通/const 构造、构造器提取、empty/unaryMinus 与嵌套公开常量；const 按规范身份复用，普通构造保留独立身份。相等、hashCode、Symbol 类型的 toString 调用/提取及对象模式保留用户实现的虚派发。私有源码字面量及其常量依赖仍明确拒绝，避免消费 analyzer 丢失库身份后的错误折叠结果。构造器接收任意字符串，包括以 `_` 开头但不带私有库身份的名字。见[Symbol 样本](../test/frontend/lowering/fixtures/symbols.dart)。 |
| Invocation 工厂与属性 | 支持 method/genericMethod/getter/setter 的直接调用及构造器提取、缺省参数、八个属性和对象模式；保留 Symbol 身份、类型实参、不可变浅快照及拷贝顺序。用户 implements/extends Invocation、抽象重声明及接口访问保留虚派发和继承默认 getter。匹配 SDK 3.13.7 的各类空集合身份与实际类型，这些细节不声明为跨 SDK 的语言保证。见[Invocation 样本](../test/frontend/lowering/fixtures/invocations.dart)。 |
| Record 字面量 | 支持空、单字段、位置与命名混合的 record，以及嵌套和 const record。字段按源码顺序求值及隐式转换，失败时跳过后续字段；支持字段读取和结构相等。见[record 样本](../test/frontend/lowering/fixtures/records.dart)。 |
| 可变/const List | 支持保留实际元素类型的可变 List 字面量、length、索引读写、sublist、add 和 addAll。支持 const List 的内容和规范身份；集合构造器和完整 SDK API 待实现。 |
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

## 规范依据

[主规范 §17](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[空安全](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md)、[空感知元素](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.8/null-aware-elements/feature-specification.md)、[点简写](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.10/dot-shorthands/feature-specification.md)、[Records](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/records/feature-specification.md)。

动态执行对照只覆盖已表示的用户成员和明确实现的核心操作。未知导入/SDK 实现及尚未表示的 typed noSuchMethod forwarder 不会被误报为缺失成员；已表示转发使用普通函数体执行入口及返回检查。NoSuchMethodError 的类型与传播已对照；宿主诊断文本对自定义类型实参和私有 Symbol 的呈现仍有限，不保证与 VM 文本一致。

NoSuchMethodError.withInvocation 的普通工厂调用与提取复用既有调用路径：构造返回新的错误对象，不触发接收者 noSuchMethod，也不提前读取用户 Invocation getter。支持类型判断、抛出、捕获和重新抛出的身份保持；该工厂支持不代表完整原生 Error 实例 API 或诊断文本与 VM 完全一致。

动态调用 `g<String>('bad')` 遗漏必需命名实参时，传给 `noSuchMethod` 的 Invocation 应保留显式类型实参 `String`。在同一份 `shapeBeforeBounds` 样本上，macOS ARM64 的 Dart SDK 3.13.7 JIT 返回 111，SDK AOT 返回 101。IR 保留显式类型实参，结果为 111。对照使用 SDK 显式构造的 Invocation 和同一接收者的 `noSuchMethod`。[样本](../test/frontend/lowering/fixtures/dynamic_dispatch.dart)、[Invocation.typeArguments](https://api.dart.dev/dart-core/Invocation/typeArguments.html)。

## 原生相等与哈希

Object/Object? 视图的 `==`、`!=` 和 hashCode 按实际值选择实现。普通用户对象保留重写、异常和副作用；继承 Object 默认实现时使用身份相等与稳定身份哈希。null 的相等比较不调用用户运算符。int、double、bool 和 null 的内置行为不因装箱改变；数值相等保留整数精度及 NaN 规则，相等的 int/double 与正负零具有相同哈希。见[宽类型与数值边界验证](../test/compiler/bound_methods_test.dart)。函数与 Type 的规则分别见[函数值](functions.md)和[类型值](types.md)。

原生字符串目前只有规范化字面量；一般字符串的值比较和哈希、record 结构比较、dynamic 成员派发仍待接通。哈希值不保证跨运行或编译版本相同，也不保证不等值的哈希不同。

## 原生整数除法、余数与移位

原生整数 `~/` 向零截断，`%` 返回非负欧几里得余数，`remainder` 返回与被除数同号的截断余数；结果遵循 64 位整数回绕。最小整数除以 -1 返回最小整数，相应余数为 0。三个操作遇到整数零除数均抛出 IntegerDivisionByZeroException，保留操作数求值顺序、typed catch 与 finally；忽略结果不会删除抛错。见 [~/ 契约](https://api.dart.dev/dart-core/num/operator_truncate_divide.html)、[% 契约](https://api.dart.dev/dart-core/num/operator_modulo.html)、[remainder 契约](https://api.dart.dev/dart-core/num/remainder.html)和[原生边界验证](../test/compiler/integer_operations_test.dart)。源码数值运算需要的异常类采用官方 SDK 声明，其 message 字符串与空 stackTrace getter 已接通；异常格式化仍未验证。浮点余数仍待实现。

只要 `~/` 的实际操作数之一是 double，按 `(a / b).truncate()` 执行；整数操作数先参与 double 除法，有限商超出原生 int 范围时饱和，非有限商抛出 UnsupportedError。boxed num 的两个实际整数仍走精确整数除法，不提前转换为 double。求值顺序与忽略结果时的异常均保留。依据[固定 SDK 的 num 契约](https://github.com/dart-lang/sdk/blob/416e33b0ffaef062a60ec966bb8c82ed2b83f128/sdk/lib/core/num.dart)，见[数值转换原生验证](../test/compiler/numeric_conversions_test.dart)。

原生 `<<`、`>>`、`>>>` 及其复合赋值保留完整的位移计数。左移按 64 位回绕，算术右移补符号位，逻辑右移补零；计数大于等于 64 时，左移和逻辑右移为 0，算术右移为 0 或 -1。负计数抛出 ArgumentError，操作数只求值一次，忽略结果仍须抛错。错误的 message 保留负计数这个 int，name 与 invalidValue 为 null；这一载荷对应当前固定 SDK 的库行为，不扩大为跨版本语言保证。构造器与属性读取使用 SDK 的普通 Dart 实现，用户重写仍按实际接收者派发。见 [int 的原生整数范围](https://api.dart.dev/dart-core/int-class.html)、[逻辑右移规范](https://github.com/dart-lang/language/blob/main/accepted/2.14/triple-shift-operator/feature-specification.md)和[原生边界验证](../test/compiler/integer_operations_test.dart)。

## 原生转整数与字符串常量

`toInt`、`truncate`、`floor`、`ceil` 和 `round` 支持 int、double 及装箱 num 接收者。整数保持全部 64 位；浮点的 toInt/truncate 向零舍入，floor 向下、ceil 向上，round 就近舍入且半数远离零。有限值超出有符号 64 位范围时饱和到对应边界；正负零转换为 0，NaN 与正负无穷抛出 UnsupportedError。求值和 finally 顺序不变，未使用转换结果仍须执行可能抛错的转换。错误通过 SDK 构造器携带当前固定版本的字符串消息，用户同名成员与 extension 不会被拦截。见 [num.truncate](https://api.dart.dev/dart-core/num/truncate.html)、[num.round](https://api.dart.dev/dart-core/num/round.html)、[double.round](https://api.dart.dev/dart-core/double/round.html)和[原生转换验证](../test/compiler/numeric_conversions_test.dart)。浮点截断除法与余数仍未接通。

`truncateToDouble`、`floorToDouble`、`ceilToDouble` 和 `roundToDouble` 同样支持 int、double 及装箱 num，返回 double 而不饱和到整数范围。已经为整数的 double、正负零和非有限值保持不变；负数舍入到零得到 -0.0，roundToDouble 的半数远离零。int 接收者仅执行通常的 int 到 double 转换。实现先排除绝对值大于等于 2^52 的 double，再复用安全范围内的整数舍入计算，不把 NaN 或无穷送进整数转换。契约见[固定 SDK double 声明](https://github.com/dart-lang/sdk/blob/416e33b0ffaef062a60ec966bb8c82ed2b83f128/sdk/lib/core/double.dart)，行为及负零位模式由同一[原生转换验证](../test/compiler/numeric_conversions_test.dart)覆盖。

原生字符串常量保留 UTF-16 码元和规范身份，可在普通参数、字段与错误载荷中传递。空串、非 BMP 字符及孤立代理项不会被重新编码或规范化；见[常量数据验证](../test/codegen/object_values_test.dart)。动态字符串构造、拼接、比较、索引及完整 String API 仍待实现。异常格式化和 Error.stackTrace getter 也尚未接通。

## 数值比较与 SDK 差异

[`num.==`](https://api.dart.dev/stable/3.13.7/dart-core/num/operator_equals.html) 要求 int 与 double 具有相同数值；[`num.<`](https://api.dart.dev/stable/3.13.7/dart-core/num/operator_less.html) 按数值大小比较。正负零在这些运算符下相等；NaN 与任何值不等，四种大小关系均为假。整数先舍入成 double 再比较不满足这一契约。例如 `9007199254740993 > 9007199254740992.0` 应为真，两者相等应为假；最大 int 小于 `9223372036854775808.0`。

SDK 3.13.7 的 VM JIT/AOT 在这些边界丢失整数精度。官方 [SDK #64728](https://github.com/dart-lang/sdk/issues/64728) 确认把最大整数与其舍入 double 判为相等属于实现错误。IR 数值操作及已接通的原生比较按原始数值执行；[独立数值预期](../test/support/numeric_order.dart)将有限 double 展开为精确整数比例，[原生验证](../test/compiler/mixed_numeric_test.dart)覆盖边界、相邻浮点值、随机位模式、两种操作数顺序和副作用。

analyzer 14.7 的常量求值也存在相同的精度问题，还会将 `0.0 == -0.0` 判为假。当前常量声明、局部常量、函数默认值、条件选择、集合及 record 内容、构造器实参和导出注解中的六种数值比较使用精确数值关系；正负零在比较下相等，`identical` 仍区分其身份。常量引用与别名使用同一规则。[常量验证](../test/frontend/lowering/constant_safety_test.dart)检查数值边界、嵌套内容及进入 IR 的值；[导出验证](../test/frontend/lowering/native_exports_test.dart)检查注解名称及常量别名的类型选择。

构造器常量求值支持参数默认值、字段初始化、断言、泛型代换、super/this 调用及工厂重定向，并保留参数和字段的类型检查。省略的工厂实参采用最终目标默认值；const 断言不受运行时断言开关影响。[构造器样本](../test/frontend/lowering/fixtures/constant_safety/numeric_constructor.dart)覆盖这些路径，以及枚举和 extension type 的常量结果。

分析阶段检查常量声明、默认值、注解、const 对象与集合表达式及模式中的常量表达式，包括未使用声明、不可达代码和已纳入分析的依赖库。常量求值错误在进入 lowering 前报告；重新求值成功的表达式可以通过上游因精度丢失而误报的断言或赋值检查，其余诊断继续保留。[静态检查样本](../test/frontend/analysis/checked_libraries_test.dart)覆盖误报、漏报及同一文件中的真实错误。

常量集合按实际求值结果检查元素类型、primitive equality、重复 Set 元素和 Map 键。未选中的分支仍须满足静态类型及潜在常量要求；空 spread 和被 null-aware 项跳过的表达式也不能隐藏静态类型错误。null-aware Map 键为 null 时不求值对应值，非 null 的 null-aware 元素不跳过后续元素。[集合常量验证](../test/frontend/analysis/collection_constants_test.dart)覆盖合法结果和静态错误。

模式常量、Map 模式重复键与 switch 穷尽性使用同一求值结果，覆盖常量别名、record、枚举及 sealed 层次；带守卫的 case 不保证覆盖。见[模式常量验证](../test/frontend/analysis/pattern_constants_test.dart)。原始 analyzer 对象仍保留上游诊断，包含可能受错误常量折叠影响的不可达警告；会话验收与 IR 转换使用重新检查的结果。

运行时 `identical` 支持普通调用和函数值调用，不执行用户的 `==`。整数按值、double 按位模式比较身份，区分正负零及不同 NaN 位模式；其余已支持原生存储的对象保持引用身份。record 不承诺持久身份，其原生存储尚未接通。见[声明绑定验证](../test/frontend/lowering/identity_test.dart)、[原生身份验证](../test/compiler/pointer_values_test.dart)和 [`identical` 契约](https://api.dart.dev/dart-core/identical.html)。

跨 int/double 的 `identical` 常量结果仍未接通；analyzer 为这类依赖目标表示的判断保留未知值，当前转换会明确拒绝，不能把未知值当作 false。
