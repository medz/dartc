# 表达式

兼容目标与 SDK 对照版本见[总览](README.md)，章节号以固定版本的[语言规范草案][draft]为准；[PDF][pdf]是可变的阅读入口。
[官方入口][entry]说明 Dart 3 规范尚不完整；空安全与类型推断还需结合[类型追踪](types.md)所列补充文档。
本页记录表达式的支持范围与缺口，状态含义见[总览](README.md#状态与证据)。

## 表达式语法表示

`package:dartc/ast.dart` 可构造和检查下列表达式语法树。验证覆盖手工构造的节点、源码范围和子节点顺序；文本解析范围见[解析 API](#表达式解析-api)，类型检查和求值尚未接入这些节点。

| 语言条款 | 可表示的语法 | 验证 |
| --- | --- | --- |
| §17 的名称、字面量与运算 | 名称引用、非字符串字面量、括号、前缀 `-` / `!` / `~`、二元运算、条件表达式；保留原始拼写和分组 | [nodes_test.dart](../test/ast/nodes_test.dart) |
| §17.7 字符串与插值 | 普通、raw、多行字符串，`$name` / `$this` / `${expression}`、嵌套插值及相邻字符串；保留原始转义、分隔符、UTF-16 和换行，尚未解码或求值 | [strings_test.dart](../test/ast/strings_test.dart) |
| [Record 字面量][record-literals] | 空 record、单位置字段、位置与命名字段交错、显式 `const`；保留字段书写顺序，区分 `(value)` 与 `(value,)` | [records_test.dart](../test/ast/records_test.dart) |
| [集合元素][collection-elements]与[空感知元素][null-aware-elements] | List 与未判定 Set/Map 的大括号字面量、显式类型实参与 `const`、普通元素、键值条目、`...` / `...?`、嵌套 `if` / `else`、`?expression`、独立的空感知键和值；集合类型推断和常量资格尚未检查 | [collections_test.dart](../test/ast/collections_test.dart) |
| 集合循环与[模式](patterns.md#模式语法表示) | `for`、`for-in`、`await for`、if-case 与守卫；循环头保留声明或表达式初始化、可省略的条件、多条更新、已有变量及模式绑定 | [loops_test.dart](../test/ast/loops_test.dart) |
| [Switch 表达式与模式赋值](patterns.md#模式语法表示) | 选择表达式、有序分支、可选 `when`、解构赋值目标与右值；尚未进行绑定、穷尽性或可写性检查 | [switches_test.dart](../test/ast/switches_test.dart)、[patterns_test.dart](../test/ast/patterns_test.dart) |
| §17.14 [函数表达式](functions.md#函数语法表示) | 可选类型参数、形参列表、同步或异步箭头体、块体及 `async` / `sync*` / `async*`；未推断返回类型或建立捕获关系 | [functions_test.dart](../test/ast/functions_test.dart)、[parameters_test.dart](../test/ast/parameters_test.dart) |
| 调用、实例创建与[显式实例化][constructor-tearoffs] | 位置及命名实参、调用类型实参、`new` / `const`、`f<T>`、`C<T>.new` 等未绑定引用；区分 `f<T>(x)` 和 `(f<T>)(x)` | [nodes_test.dart](../test/ast/nodes_test.dart)、[expressions_test.dart](../test/ast/expressions_test.dart) |
| 赋值、增减与成员访问 | 简单、复合、`??=` 赋值，前后 `++` / `--`，`this` / `super`，属性和索引；目标保留一次，尚未检查是否可写 | [expressions_test.dart](../test/ast/expressions_test.dart) |
| [空安全选择器][null-aware] | `?.`、`?[]`、后缀 `!`，以及链中的括号边界 | [expressions_test.dart](../test/ast/expressions_test.dart)、[access_test.dart](../test/ast/access_test.dart) |
| 类型测试、转换、异步与抛出 | `is` / `is!`、`as`、`await`、`throw`；保留写出的类型与操作数 | [expressions_test.dart](../test/ast/expressions_test.dart) |
| [级联][cascades] | 一个接收者、有序分段、首段 `?..`、属性及索引起始选择器、段内调用与赋值、带括号的嵌套级联 | [access_test.dart](../test/ast/access_test.dart) |
| [点简写][dot-shorthands] | `.name` / `.new`、显式 `const` 前缀、可选类型实参与调用实参及后续选择链；完整链保留独立的上下文边界，无实参列表时保持引用形式，尚未推断目标命名空间 | [access_test.dart](../test/ast/access_test.dart) |

构造与遍历不证明表达式合法、类型正确或求值行为已实现。解析支持如下；编译与执行行为见后续各表。

## 表达式解析 API

`package:dartc/parser.dart` 的 `parseExpression(ScanResult)` 将一次扫描结果解析为表达式 AST。输入应为一个不带末尾分号的表达式；当前使用同步上下文，`await` 与 `yield` 可作为标识符。返回的 `ParseResult<Expression>` 包含节点、词法诊断和语法诊断，调用方通过 `hasErrors` 判断是否成功。

| 语言条款 | 当前解析支持 | 验证 |
| --- | --- | --- |
| 名称、§17.4–17.6 字面量与 §17.12 `this` | 标识符及该位置合法的内置和上下文关键字；整数、double、布尔、null；保留原始拼写，未转换字面量值 | [expressions_test.dart](../test/parser/expressions_test.dart) |
| §17.7 字符串与插值 | 普通、raw、多行和相邻字符串，`$name` / `$this` / `${expression}` 及嵌套插值；保留文本段、空段、原始转义、分隔符、UTF-16 和换行，不解码或求值；嵌入表达式的解析范围同本表 | [strings_test.dart](../test/parser/strings_test.dart) |
| §17.8 Symbol 字面量 | 名称、限定名称、`void` 和可重载运算符；保留 `#`、原始拼写和源码范围，不解析名称对应的库或求值 | [primaries_test.dart](../test/parser/primaries_test.dart) Symbol 用例 |
| §17 运算表达式 | 前缀 `-` / `!` / `~`、二元运算及优先级、括号分组、条件分支和赋值的结合性；关系与相等运算的连续同级使用需要括号 | [expressions_test.dart](../test/parser/expressions_test.dart)、[recovery_test.dart](../test/parser/recovery_test.dart) |
| 赋值与增减 | 简单、复合、`??=` 赋值及前后 `++` / `--`；检查目标语法形式，保留目标一次；未解析声明或检查 final、const、类型及成员可写性 | [expressions_test.dart](../test/parser/expressions_test.dart)、[recovery_test.dart](../test/parser/recovery_test.dart) |
| 调用、属性与[空安全选择器][null-aware] | 位置和命名实参交错、尾逗号、`.` / `?.`、`[]` / `?[]`、后缀 `!`；保留链中的括号和书写顺序，未绑定函数、构造器或成员 | [expressions_test.dart](../test/parser/expressions_test.dart) |
| [级联][cascades] | `..`、首段 `?..`、属性或索引起始的分段、段内选择器、泛型调用与赋值；接收者只出现一次，保留分段顺序与条件表达式的结合边界；拒绝后续 `?..` 及未加括号的级联后续运算 | [access_test.dart](../test/parser/access_test.dart) 级联用例 |
| [点简写][dot-shorthands] | `.name` / `.new`、调用、显式类型实参与 `const` 前缀；保留完整选择链的上下文范围，区分段内空断言与上下文外的赋值、更新和普通运算；按 SDK 3.13.7 接受 `const .name` 引用，不补造实参列表；目标类型、成员查找与常量资格留待分析 | [access_test.dart](../test/parser/access_test.dart) 点简写与上下文边界用例 |
| [显式实例化][constructor-tearoffs]与泛型调用 | `f<T>`、`f<T>(x)`、`C<T>.named(x)`；保留嵌套类型实参，与关系运算及移位区分；未进行名称绑定或判断调用对象类别 | [types_test.dart](../test/parser/types_test.dart) 泛型调用、函数值、比较与移位用例 |
| 显式实例创建 | `new` / `const`、限定名称、类型实参、命名构造器及 `.new`；保持实参顺序，名称中的库前缀与构造器歧义留待绑定；缺少实参列表时用零宽实参列表恢复并报告诊断，不检查构造器存在性或 const 资格 | [primaries_test.dart](../test/parser/primaries_test.dart) 构造调用用例 |
| `super` 接收者 | 成员、索引、调用及可用的运算符位置；拒绝将裸 `super` 用作普通值及 `super?.member`；父类查找、可调用性和成员类型留待分析 | [primaries_test.dart](../test/parser/primaries_test.dart) super 用例 |
| 类型测试与转换 | `is`、`is!`、`as`，包括泛型、函数及 record 类型；区分可空类型标记与条件表达式，检查运算的语法结合规则 | [types_test.dart](../test/parser/types_test.dart) 类型运算用例；类型语法范围见[类型解析](types.md#类型解析-api) |
| `throw` 表达式 | 保留抛出操作数及其条件、赋值和级联边界；在普通二元及前缀运算的操作数位置要求括号；不执行抛出或检查异常传播 | [statements_test.dart](../test/parser/statements_test.dart) throw 用例 |
| [Record 字面量][record-literals] | 空 record、单位置字段的尾逗号、交错的位置和命名字段及显式 `const`；区分 `(value)` 与 `(value,)`，报告 `const (value)` 缺少的逗号 | [expressions_test.dart](../test/parser/expressions_test.dart)、[primaries_test.dart](../test/parser/primaries_test.dart) |
| [集合字面量与元素][collection-elements] | List、大括号字面量、显式 `const` 和类型实参、尾逗号、普通元素和键值条目、`...` / `...?`、嵌套 `if` / `else`；Set/Map 分类、类型推断和常量资格留待分析 | [collections_test.dart](../test/parser/collections_test.dart) |
| [空感知集合元素][null-aware-elements] | `?expression`、独立的空感知键和值；`?[...]` 与条件表达式按上下文消歧，保留赋值目标错误的诊断 | [collections_test.dart](../test/parser/collections_test.dart) |
| 集合循环 | 同步 `for` 和 `for-in`；表达式或普通变量声明初始化、可省略的条件、多条更新、已有或声明的迭代变量；保留类型、变量关键字和源顺序，不补写空条件 | [collections_test.dart](../test/parser/collections_test.dart) |
| 不完整或无效的输入 | 报告缺少的操作数、名称、冒号和闭合括号；以零宽节点恢复操作数，继续处理后续实参；不修改源文本或输入 token | [recovery_test.dart](../test/parser/recovery_test.dart) |

[函数表达式](functions.md#函数表达式与局部声明解析)已接入可选泛型、形参和独立的函数体上下文。尚缺模式赋值和 switch。集合中的 if-case、模式循环头和声明元数据尚未解析。[函数体解析](functions.md#函数体解析-api)已接入异步上下文中的 `await` 和集合 `await for`；独立 `parseExpression` 入口仍使用同步上下文。这些缺口产生的诊断不表示相应 Dart 写法非法。

错误结果可能只覆盖部分输入，不能直接当作合法表达式使用。解析不进行名称绑定、类型检查、常量求值或执行，也不改变下述已发布编译器的支持范围。

## 求值、常量与字面量

| 规范条目 | 状态 | 支持范围与缺口 | 验证 |
| --- | --- | --- | --- |
| §17.1 表达式求值 | 部分实现 | 已支持表达式按规定顺序求值，短路保留副作用；异常完成、异步及完整表达式集合尚缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`assignmentValues`、`conditionContexts` |
| [§17.2 对象身份][identity] | 部分实现 | `identical` 覆盖整数、布尔、null 和对象身份；整数身份不受数值大小影响；const 类实例按实际类及规范化字段共享身份，普通构造调用保持新实例；同一顶层函数的值引用跨前缀和导出共享身份。double 身份按完整位模式比较，区分正负零以及 NaN 的符号和负载；记录身份未实现。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`constantLists`、`constObjects`、`functionValues`、`doubleValues`、`floatingContexts` |
| §17.3 常量表达式 | 部分实现 | 标量、支持的运算、条件、插值、常量引用、[常量 `as`/`is`/`is!`][constant-type-checks]、受支持的顶层函数引用与核心 `identical` 可求值；拒绝非常量引用和循环。静态类型与实际负载分开；支持当前生成式构造器子集的 const 实例，与 List 共用规范化身份；Map、Set、完整潜在常量表达式及其他构造形式仍缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`constObjects`、`typeChecks`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`rejected`、`rejectedConstantTypes`、`constantTypeDifferences`、`libraries` |
| §17.3.2 常量上下文 | 部分实现 | 支持顶层和局部 const、嵌套隐式 const List 及上下文元素类型；参数 List 默认值需显式 `const`，不能把普通 `[]` 当默认常量。const 构造实参引入隐式常量上下文；构造器声明默认值和字段初始化仍按自身声明作用域及常量资格检查，不能由调用方上下文放宽。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`constantDefaults`、`constantLists` |
| §17.4 null、§17.6 布尔 | 部分实现 | 有字面量及静态类型，动态布尔消费有检查；`Object`、`bool?` 不能未经转换或提升用作条件。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`valueContexts`、`flowBranches` |
| [§17.5 数字][numbers] | 部分实现 | 支持有符号 64 位整数及 `num` 身份；十进制负边界只允许[直接负字面量][negative-literals]，括号内字面量先独立校验。非负十六进制可用完整 64 位补码，直接负十六进制仍受有符号范围约束；普通表达式和常量同用范围规则。支持 binary64 字面量（含小数、指数及分隔符）、double 上下文的精确整数字面量转换、负零、次正规数、无穷大与 NaN。数值 API 和异常的缺口见下文。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`shiftContexts`、`doubleValues`、`floatingContexts`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`rejected` |
| §17.7 字符串与插值 | 部分实现 | 字面量、拼接、插值和 UTF-16 内容可用；完整词法变体与全部 String API 尚未逐项核验。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`stringBoundaries`、`constantLists` |
| §17.9 集合字面量 | 部分实现 | 可变与 const List，显式或上下文元素类型、嵌套与空列表；const 按完整实际 `List<T>` 及元素规范化，跨库和嵌套共享身份。支持嵌套的 if/else、for、for-in 及普通/空感知展开，具体规则见下一条；运行时 if-case 元素及 for / for-in 解构见[模式](patterns.md)。Set、Map 与异步集合元素未实现。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`constantLists`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`libraries` |
| [§17.9 集合元素、推断与求值][collection-elements] | 部分实现 | List 的条件与循环元素按源码顺序求值，共用语句的作用域、流分析和逐轮捕获规则；局部、顶层、静态/实例字段及构造器初始化中的循环均保留绑定。`...` 与 `...?` 支持 List，空感知展开仅跳过 null 集合，保留内部 null；静态元素类型参与上下文与 LUB 推断，dynamic 源按运行时元素逐个检查。const 支持条件/展开及规范化身份；未执行元素仍检查类型和潜在常量资格，for 元素不是潜在常量。一般 Iterable/Iterator、Set/Map 及完整推断仍缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`collectionValues`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`rejected`、`failingValues` |
| [空感知集合元素][null-aware-elements] | 部分实现 | 语言版本 3.8 起支持 List 中的 `?expression`，包括 if/for 嵌套和常量上下文。表达式一次求值，仅丢弃 null；下行上下文允许 null，上行元素类型取 NonNull，Null 得 Never，dynamic 仍为 dynamic。过滤不提升后续表达式中的变量，赋值副作用仍无条件发生；跳过 null 保留正常后继，不能使函数的返回义务消失；静态类型和潜在常量资格不因元素被跳过而省略。Set/Map 尚未实现；void 与未选中常量分支的 SDK 差异见下文。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`collectionValues`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`rejected`、`failingValues` |

## 调用、查找与访问

| 规范条目 | 状态 | 支持范围与缺口 | 验证 |
| --- | --- | --- | --- |
| §17.12 `this`、§17.13 实例创建 | 部分实现 | 支持当前类实例、字段、普通构造器与字段形参；支持已实现的生成式构造与规范化 const 实例，细则见[类追踪](classes.md)；支持显式或隐式父类构造链及非泛型工厂。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`localBindings`、`argumentCalls`、`constObjects` |
| [§17.13.1 `new` 表达式][new-expression] | 部分实现 | 前导 `new` 必须解析到已实现的类构造器，可经类名或用户类类型别名调用未命名、命名与 `.new` 构造器，并保留原有参数检查和求值顺序；支持既有 `List.filled`、`String.fromCharCodes` 构造入口，其类型别名入口尚缺。普通函数、getter、函数值及静态方法不因 `new` 变成构造器；`new` 在嵌套或未执行的常量分支中也不是常量。生成式重定向的规则见[类追踪](classes.md)；泛型类及 external 构造仍缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`namedConstructors`、`filledLists`、`stringBoundaries`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`named-constructors-imports.dart`、`rejected` |
| [§17.14 函数表达式][function-expressions] | 部分实现 | 支持同步非泛型匿名箭头体与块体及必需/可选位置和命名参数签名的捕获，以及签名上下文推断。一般函数值签名限制与捕获范围见[函数](functions.md)。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `program/anonymousFunctions()`、`rejected` |
| §17.15 函数调用 | 部分实现 | 必需/可选位置参数、命名/required 参数、声明库范围内的默认常量；实参按源码顺序求值后绑定。调用的类型实参与 callee 自有类型分开存储；已有普通函数、构造器和方法拒绝不匹配的类型实参。支持已知类的[可调用对象](functions.md#可调用对象)，以及具体非泛型签名的函数值调用及 `.call`，参数和结果按静态签名检查；泛型声明的直接调用与推断见[函数](functions.md#泛型直接调用)；泛型函数值及 dynamic/裸 Function 调用尚缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`argumentCalls`、`functionValues` |
| [§17.16 函数提取][closurization] | 部分实现 | 对[已支持的函数值来源和签名](functions.md#函数值)按声明规范化身份，保留仅经值引用的目标。静态方法提取复用普通函数值，实例方法值保存单次求值的接收者；完整签名、相等性与缺口由函数条目维护。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`functionValues`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`function-imports.dart` |
| §17.18–17.19 查找与顶层 getter | 部分实现 | 声明库及前缀按读/写分别解析，支持顶层 getter/setter 和变量惰性读取；本库任一同名声明遮蔽导入的两侧。完整库冲突与 SDK 差异见[库追踪](libraries.md)。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`topAccessorValues`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`libraries` |
| §17.20–17.22 成员调用与属性读取 | 部分实现 | 按[类成员声明](classes.md)区分实例接收者与静态限定目标，读取和写入分别选择声明与类型；字段/getter 返回的具体函数值可调用，读取时机见下方 SDK 差异说明。仅写属性不能读取；支持父类具体方法、字段和访问器的 super 选择，包括词法闭包及直接方法值；super 返回函数值时先读取、后求值实参。一般动态成员分派仍缺；空短路访问见下一条。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`accessorValues`、`localBindings`、`functionValues`、`inheritanceValues` |
| [空安全补充：空短路访问][null-aware] | 部分实现 | 支持 `?.`、`?[]` 的属性、调用、索引、空断言及赋值/增减链；接收者一次求值，null 时跳过后续选择器、实参、索引和 RHS。括号与普通运算终止传播，类型限定目标沿用静态查找。值接收者的结果可空，即使接收者静态非空；void 仍不能被消费。常量路径支持 String.length 与被跳过的索引，仍检查潜在常量资格及索引类型；一般动态分派和完整常量成员规则仍缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`nullAwareValues`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`rejected`、`failingValues` |
| [§17.15 级联][cascades] | 部分实现 | 支持 `..` 与首次 `?..`，接收者一次求值并保留为结果；各段按序访问、调用、索引或赋值，null 时跳过整组副作用。接收者获得上下文类型，空短路分支参与提升及确定赋值合流；3.9 起以非空目标类型排除 null 分支。静态义务不因跳过执行而消失。嵌套级联、段内空短路访问与箭头函数体遵循 SDK 解析；一般动态分派仍缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`cascadeValues`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`rejected` |
| 空安全补充：`Never` 表达式消费 | 部分实现 | 支持底类型接收者的属性、索引及已有调用入口；结果保留 `Never`，仍检查实参、重复命名参数、类型实参与 void 消费。此类路径不能产生实际接收者，不引入一般动态分派；方法提取等入口仍缺。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`neverExpressions`、`rejected` |
| §17.37–17.38 词法查找与标识符 | 部分实现 | 整个局部作用域预绑定，支持遮蔽、前向/自身引用错误及 `_`；局部和匿名函数保持独立函数体作用域，外层捕获沿原声明绑定；switch 表达式模式绑定见[模式](patterns.md)。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`localBindings`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`rejected` |

## 赋值、分支与运算

| 规范条目 | 状态 | 支持范围与缺口 | 验证 |
| --- | --- | --- | --- |
| §17.23、§17.36 赋值与可赋值表达式 | 部分实现 | 局部、全局、字段、实例/顶层 setter、List 与用户运算符索引及已有复合赋值；接收者/索引只求值一次，简单赋值保留原 RHS 类型和负载，setter 返回值不替代它；复合赋值独立检查 getter 运算和 setter 写入类型。final/const 存储只读，同名显式 setter 可以接收写入。`??=` 仅 null 时求值并写入 RHS，仍检查读写两侧及未执行的 RHS；原读取/RHS 负载独立于 setter 转换。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`assignmentValues`、`accessorValues`、`topAccessorValues`、`coalescingAssignmentValues`、`operatorIndexing`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`neverExpressions`、`rejected`、`failingValues` |
| §17.24 条件表达式 | 部分实现 | 仅执行选定分支，两分支均检查并接受上下文类型；结果合并依赖当前有限类型 LUB。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`conditionTernary`、`flowContexts` |
| §17.25 `??` | 部分实现 | 左侧一次求值，仅 null 时执行 RHS；两侧静态检查和接收 List 上下文；Null 左侧取 RHS 类型，否则合并非空左类型与 RHS。拒绝 void 左侧，允许 void RHS 并保留选中负载。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`coalescingContexts` |
| §17.26 逻辑表达式 | 部分实现 | `&&`、`\|\|` 短路及分支提升；普通布尔值与条件消费均保留副作用和动态 bool 检查。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`conditionContexts`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`failingValues` |
| §17.27 相等 | 部分实现 | 当前标量值比较与 List/普通对象身份，`Object?` 和 null 可比较；用户声明的 `operator ==` 与完整分派未实现。const 实例比较区分 canonical 身份与 primitive equality，覆写 `hashCode` 的类不能参与一般活跃常量相等求值，与 null 比较除外。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`staticContexts`、`constantLists` |
| §17.28 关系运算 | 部分实现 | 支持 int/double、num 与 dynamic 数值路径，NaN 关系比较为 false；静态数值左侧结果 bool，动态左侧结果 dynamic。类左操作数按[用户运算符](classes.md)调用。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`staticContexts`、`conditionComparisons`；[values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`doubleValues`、`floatingContexts` |
| §17.29–17.30 位运算与移位 | 部分实现 | 整数 `&`、`\|`、`^`、`<<`、`>>`、`>>>` 及布尔位运算；覆盖 64 位边界、大移位与负数失败。类左操作数按[用户运算符](classes.md)调用。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`literalShifts`、`shiftContexts`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`failingValues` |
| §17.31–17.32 加法与乘法类 | 部分实现 | 支持 int/double 的 `+`、`-`、`*`、`/`、`~/`、`%` 及其复合赋值，String 拼接；`int + dynamic` 为 num，`dynamic + int` 为 dynamic，`~/` 为 int。浮点 `/` 的零除产生无穷大或 NaN；整数 `~/`、`%` 的零除在两侧实参求值后抛出可捕获 IntegerDivisionByZeroException；复合赋值失败保留原值。覆盖最小 int 除以 `-1` 的溢出和正负除数的非负余数；非有限浮点 `~/` 结果抛出 UnsupportedError。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`staticContexts`；[values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`doubleValues`、`floatingContexts`、`integerDivisions`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`failingValues` |
| §17.33、§17.35 一元与后缀 | 部分实现 | 前缀逻辑 `!`、数值负号、整数 `~`、前后 `++`/`--`；增减的结果与存储类型分别处理。类操作数按[用户运算符](classes.md)调用。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`assignmentValues`、`flowAssignments` |
| 空安全补充：空断言 `e!` | 部分实现 | 操作数只求值一次，仅 null 时抛出可捕获 TypeError，否则保留原值；结果为 NonNull(T)，Null 得 Never，dynamic 仍为 dynamic。透传 List 上下文并提升直接局部读取；void 操作数、常量上下文及作为赋值目标均拒绝。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`nullAssertionValues`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`nullAssertion`、`neverAssertion`、`neverExpressions`、`rejected`、`failingValues` |
| §17.39–17.40 类型测试与转换 | 部分实现 | `is`、`is!`、`as` 保留单次求值，覆盖当前类型和完整 List 参数；允许无关静态类型的显式 cast 后在运行时检查，失败时抛出可捕获 TypeError；`as` 可消费 void 的实际负载，`is` 和隐式消费不因此放宽。支持已实现函数签名、Function 上界及函数类型参数的运行时实例化；常量表达式按实际常量类型检查，`as` 保留原值及目标静态类型，`is`/`is!` 产生 bool。潜在常量构造器和字段类型推断共用此规则，失败转换只在实际常量求值时拒绝。记录及一般泛型类目标未实现。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`typeChecks`、`valueContexts`、`functionValues` |
| 空安全补充：底类型运算结果 | 部分实现 | 支持的普通运算在 Never 左侧保留底类型；相等、逻辑和 `!` 仍为 bool。具体接收者沿用其结果规则，例如 `int + Never` 为 num。不能因路径不完成而跳过其他操作数的静态检查。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`neverNegation`、`neverRelation`、`neverRightArithmetic`、`neverLogical` |

## 常量类型检查

依据[常量类型转换与测试][constant-type-checks]，操作数须满足潜在常量资格，目标须为常量类型表达式。`as` 不给操作数提供目标上下文，例如 `1 as double` 不产生整数到 double 的隐式转换；活跃常量求值中的失败 cast 是编译错误。判断使用值的实际类型，保留 List 的实际实参与函数签名；向较宽静态类型转换不改变规范化身份。`as` 可消费 void 的实际常量负载，`is`/`is!` 仍拒绝 void 操作数。

未选中条件分支、短路的逻辑右侧和 `??` 右侧不执行 cast，但仍核验名字、操作数潜在常量资格及目标类型。只有推断类型时也不执行转换，因此普通字段中的失败 cast 在该字段初始化时才失败。验证：[values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) 的 `typeChecks()`；失败常量、运行时字段初始化和规范差异分别由 [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `rejectedConstantTypes`、`failingValues` 与 `constantTypeDifferences` 拥有。

固定规范要求常量目标类型不依赖外层类型参数，包括未选中分支。SDK 3.13.7 的 CFE 与 analyzer 接受 `true ? true : (1 is T)`、`true ? 1 : (2 as T)` 和嵌套的 `List<T>` 目标；dartc 在这些位置遵守固定规范并拒绝，单独记录该差异。泛型函数类型中的自有类型参数仍受当前类型模型限制，不能据此声称覆盖完整常量类型语言。

## 索引赋值

用户 `[]` 与 `[]=` 的索引参数可以不同。接收者和源码索引各求值一次；简单赋值用写入参数提供上下文，复合赋值、增减及 `??=` 用读取参数提供上下文。读取和写入分别对原始索引检查类型及提取隐式 `call`，一侧的转换不能改变另一侧的输入。`??=` 读取非 null 时跳过 RHS 和写入参数的运行时检查，但仍检查两侧的静态义务，包括未调用函数中的赋值。

支持 [§17.23 的 `super[i]` 赋值](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L16035-L16049)及其复合、`??=`、前后增减形式。读写分别从词法父类查找具体运算符，保留当前 this，绕过子类覆写；闭包捕获同一接收者。简单赋值只要求写入运算符，复合形式还要求读取运算符；索引、RHS 和结果类型沿用上述规则。当前范围为已支持的非泛型类，泛型类、mixin 及 noSuchMethod 转发仍缺。

索引类型检查与 SDK 3.13.7 的行为一致：直接丢弃结果的复合赋值和后缀增减先检查写入索引；消费复合赋值结果时，在读取和 RHS 运算后检查。消费后缀结果时，在读取后、增减运算前检查；前缀增减在运算后检查。`??=` 仅在 null 分支检查写入索引，丢弃结果时先检查再求 RHS，消费结果时顺序相反。表达式语句、for 更新及级联段直接丢弃结果；条件表达式中的赋值仍作为值求解。

`super[i]` 使用相同的索引检查顺序。

验证：[values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) 的 `operatorIndexing()`，运行时失败前的副作用和未执行代码的拒例分别由 [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `failingValues`、`rejectedOperators` 验证。运行时类型检查失败抛出可捕获 TypeError；其他自动错误的边界见[异常范围](statements.md)。

## 点简写

依据 [Dart 3.10 点简写规范][dot-shorthands]，支持已有类和标准库入口的 `.new(...)`、命名生成式/工厂构造、静态字段、getter 及方法调用。整个最长选择器链的上下文决定声明身份；括号终止该链。声明查找忽略局部同名变量，类型别名按展开后的类型处理，可空上下文使用非空声明。实参、返回、赋值、条件、`??`、List 元素及泛型调用已有的向下推断可提供上下文；List 的空感知元素也支持 `?.member`。运行时求值顺序、默认值、访问检查与正常显式调用共用实现。

`==`/`!=` 只给直接的简写右操作数提供左侧静态类型作为声明查找上下文，不改变该操作数自身的类型推断上下文。`value == .name` 与 `value == (.name)` 因此不同。常量及关系模式按匹配类型和运算符参数上下文处理，关系模式的 SDK 差异见[模式](patterns.md)。常量求值使用相同声明身份，检查未选中分支及未调用声明的义务。`const .name(...)` 必须选择 const 构造器；普通静态 getter 或方法不因此成为常量。

缺少上下文、dynamic/void/Never、结构化函数类型和类型参数（包括有类上界的参数）不能提供静态命名空间。无上下文时不按成员名搜索类。检查语言版本至少 3.10、私有成员与构造器、实例成员误用及非法赋值。按 SDK 3.13.7 的 CFE/analyzer 行为，跨库私有类不能提供简写命名空间，即使通过公共别名得到该类型；同库及 part 可用。泛型函数值、泛型类、FutureOr、enum/mixin/extension type 及未实现的标准库成员仍依赖各自语言和库缺口。

固定规范与 SDK 3.13.7 analyzer 都要求显式 const 简写调用选择 const 构造器；CFE 却接受并执行 `const .make()` 指向的普通静态方法。dartc 在此遵守 const 资格并拒绝，即使函数未调用。固定规范的裸常量模式还排除 `.new`，而此 SDK 的 CFE 与 analyzer 接受构造器函数值模式；dartc 接受已支持非泛型用户类的该模式，构造器引用及剩余缺口见[类追踪](classes.md#构造器函数值)。

验证：[values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `shorthandValues()`、`shorthandContexts()`，[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `shorthand-imports.dart`、私有访问拒例和 `rejected`；[roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart) 的对象和 List 元素分配继续验证根枚举。

## List API 边界

这些条目属于标准库 API，不能计作 §17.9 的全部语言规则已完成。

| 规范条目 | 状态 | 支持范围与缺口 | 验证 |
| --- | --- | --- | --- |
| [`List.filled`][filled] | 部分实现 | 默认固定长度，`growable: true` 可增长；实参一次求值、共享 fill 引用。并未覆盖全部 List 构造器和长度 setter。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`filledLists` |
| [`[]=`][put]、[`clear`][clear] 与只读 List | 部分实现 | 支持索引、add、removeLast、clear；写入按实际元素类型检查，再检查只读性和范围；空 const 也不可 clear。类型检查失败抛出可捕获 TypeError；固定长度及只读变更抛出 UnsupportedError，支持首次轨迹、finally 与继续执行，失败不修改列表；范围失败仍以进程退出表示。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`filledLists`；[roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart)：`exceptionRoots`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`failingValues`、`uncaught` |
| [`removeAt`](https://api.dart.dev/stable/3.13.7/dart-core/List/removeAt.html) | 部分实现 | 删除并返回指定元素，保留其静态类型和剩余元素顺序；接收者与索引按序各求值一次。固定/只读列表在范围检查前拒绝改长，索引的入口类型检查仍先执行。类型检查失败抛出可捕获 TypeError；固定/只读变更抛出 UnsupportedError，范围失败仍终止进程。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`listGrowth`、`filledLists`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`failingValues` |
| [`sublist`](https://api.dart.dev/dart-core/List/sublist.html) | 部分实现 | 支持 start 与可省略或为 null 的 end；按接收者、start、end 顺序求值及检查参数类型，再按调用时长度检查范围。返回独立可增长列表，保留实际元素类型和原始元素表示，支持固定/只读源。参数类型检查失败抛出可捕获 TypeError，范围失败仍终止进程；一般动态成员分派仍缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`sublistValues`；[roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart)：`listPatternRoots`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`failingValues`、NoGC 拒例；[ssa_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/ssa_test.dart)：切片操作数合同 |
| [`insert`](https://api.dart.dev/dart-core/List/insert.html) | 部分实现 | 在 `0..length` 插入并保持后续元素顺序，返回 void；接收者、索引、元素按序求值。元素按实际类型检查，再拒绝固定/只读列表及非法范围；类型检查失败抛出可捕获 TypeError，固定/只读变更抛出 UnsupportedError，范围失败仍终止进程。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`listGrowth`、`filledLists`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`failingValues`、NoGC 拒例 |
| [`toString`](https://api.dart.dev/stable/3.13.7/dart-core/List/toString.html) | 部分实现 | 按序格式化元素，保留嵌套列表并处理循环引用。元素回调改变当前列表长度时抛出 ConcurrentModificationError，modifiedObject 保留实际被修改的列表；支持首次轨迹、finally、异常后再次格式化。替换元素和回调返回前恢复原长度可继续。当前边界与 SDK 3.13.7 的 List 格式化行为对照；for-in 的可捕获并发修改错误和一般 Iterable/Iterator 仍缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`listGrowth`；[roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart)：`collectionRoots`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`uncaught` |

## String API 边界

[`String.fromCharCodes`](https://api.dart.dev/dart-core/String/String.fromCharCodes.html) 当前接受 List<int>，按 UTF-16 保留 16 位码元并将补充码点拆为代理对。小于 0 或大于 0x10FFFF 的元素抛出 ArgumentError.value：invalidValue 为原列表，name 为 `charCodes`，message 为 `Contains invalid character code, not 0 <= code <= 0x10FFFF`。支持首次轨迹、finally、继续执行和异常载荷 GC 保活，失败不改变输入列表；一般 Iterable、可选 start/end 及 fromCharCode 尚缺。

错误类型和展开行为与 SDK 3.13.7 对照，载荷采用其[一般 Iterable 路径](https://github.com/dart-lang/sdk/blob/3.13.7/sdk/lib/_internal/vm/lib/string_patch.dart)的合同。SDK VM 的 List 路径存在可观察差异：负值或非 Smi 整数使 message 指向原列表；正的超 Unicode Smi 值使 message 为 null；两者 name 和 invalidValue 都为 null。dartc 对上述输入统一保留原列表于 invalidValue 并提供参数名及说明，不复刻 VM 整数表示造成的字段差异。[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `codeErrors`、`iterableCodeErrors` 分别固定 native、SDK List 与 SDK 一般 Iterable 的字段结果并验证展开，`uncaught` 验证退出255与清理；[roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart) `exceptionRoots` 验证载荷及轨迹保活。成功边界仍由 [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `stringBoundaries` 拥有。

## StringBuffer API 边界

这些条目属于标准库 API，不代表完整标准库已实现。

| 规范条目 | 状态 | 支持范围与缺口 | 验证 |
| --- | --- | --- | --- |
| [`writeCharCode`](https://api.dart.dev/dart-core/StringBuffer/writeCharCode.html)、[`isNotEmpty`](https://api.dart.dev/dart-core/StringBuffer/isNotEmpty.html) | 部分实现 | 支持 0..0x10FFFF，补充字符拆为 UTF-16 代理对，保留孤代理项；长度按 UTF-16 单元计算，clear 后查询为空。非法码点在 API 入口抛出 RangeError.range，保留非法值和 0..0x10FFFF 边界，失败不改变内容或长度；支持首次轨迹、finally、继续写入。writeAll 等 API 尚未实现。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`bufferValues`；[roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart)：`exceptionRoots`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`uncaught` |

## 尚缺与待核验

| 规范条目 | 状态 | 支持范围与缺口 | 验证 |
| --- | --- | --- | --- |
| §17.10 throw | 部分实现 | 单次求值后抛出非空对象，结果为 Never；支持条件、赋值、集合元素和括号内表达式，保留此前副作用并终止后续求值。静态拒绝 nullable、void 及可能为空的类型参数，接受 dynamic；dynamic 为 null 时由非空类型检查抛出可捕获 TypeError。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `exceptionValues()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `rejected` |
| §17.8、§17.11 | 未实现 | Symbol 字面量和 isolate 创建未实现。 | 待补充 |
| §17.17、§17.34 | 未实现 | 泛型函数值实例化表达式、await；直接泛型调用不代表已实现泛型函数值或异步执行。 | 待补充 |
| Dart 3 表达式 | 部分实现 | switch 表达式、标量/对象/List 模式、守卫、变量绑定及穷尽性边界见[模式](patterns.md)；记录和 Map/record 模式未实现。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart)：`switchExpressions`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`rejected`、`failingValues` |
| 优先级、所有静态错误及完成方式 | 待核对 | 优先级、静态错误及完成方式的完整一致性覆盖尚缺。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart)：`rejected` |

实例 getter 的函数值调用按 SDK 3.13.5 CFE 求值顺序处理：以 receiver、getter、实参、函数体分别记为 1、2、3、4，`receiver().callback(arg())` 的轨迹为 `1324`，`(receiver().callback)(arg())` 为 `1234`；隐式 this 遵循实例形式；顶层和静态 getter 先读取再求实参，静态选择器加括号不改变顺序。[固定草案的 getter fallback][getter-invocation]描述先调用 getter 再调用返回值，与此行为有差异；dartc 采用 SDK 3.13.5 的顺序，不据此判定上游缺陷。验证：[values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) 的 `functionValues()` 与 `staticMembers()`。

SDK 3.13.7 在命名实参位于位置实参之前时，部分函数表达式调用会先执行前面的实参，再读取函数值。例如 `(receiver().callback)(a: mark(2), mark(1))` 中若 receiver 记录 5、getter 记录 4，SDK 输出轨迹为 `2541`，dartc 为 `5421`；直接选择器调用两者均为 `5214`。dartc 保留函数表达式先求值、各实参再按源码顺序求值的边界；这与[命名实参重排提案](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.17/named-arguments-anywhere/feature-specification.md#runtime-semantics)的接收者先求值规则一致，仍属于对当前 SDK 的已知行为差异。`function-getter-order.dart` 显式断言两种结果，不把它计为差分一致。

SDK 3.13.5 对 `??=` 有两处 analyzer/CFE 差异待核对：`void` getter 作为左侧时 analyzer 拒绝，CFE 接受表达式语句，dartc 按 void 值消费规则拒绝；`int f(Never value, dynamic fallback) { value ??= fallback; }` 的正常落空被 analyzer 拒绝而被 CFE 接受，dartc 将 `Never` 读取视为不能正常完成，仍检查 RHS。此差异不扩展为一般诊断一致性结论，后者由 [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `neverLocalCoalescing` 跟踪。

空断言选择器遵循固定草案的 `selector*`：允许重复 `!` 后继续成员、索引或调用。SDK 3.13.5 拒绝 `value!!.member`、`value!![0]`、`value!!(1)`，而 `(value!!)(1)` 可通过；dartc 在此采用规范文法，与 SDK 的诊断不完全一致。

SDK 3.13.7 CFE 接受 `const values = [if (false) <int>[1][9] else 2]`，analyzer 将被跳过的索引报告为 `non_constant_list_element`。dartc 按 CFE 检查该分支的潜在常量资格与索引类型，不执行取值或范围检查；`collectionValues` 保留该差异的行为用例与逐行 analyzer 忽略。

SDK 3.13.7 CFE 接受推断或显式 `List<void>` 中的空感知元素，按实际负载过滤 null；analyzer 报 `use_of_void_result`。CFE 也接受 `const dynamic x = 'wrong'; const values = <int>[if (false) ?x]`，analyzer 报 `non_constant_list_element`。dartc 在这两处采用 CFE 行为：仍检查 void 不能用于其他元素类型，动态常量只在选中分支检查实际负载。`collectionValues` 保留行为用例和逐行 analyzer 忽略，`rejected` 验证对应的静态及活跃常量错误。

SDK 3.13.7 对 `?[]` 的歧义优先按条件表达式解析；`true ? (values?[0]) : 0` 需要内层括号，否则该写法被拒绝。类型转换、可空类型和泛型实参不得误作条件分隔符。普通级联在此 SDK 中终止空短路传播：`receiver()?.child()..field = 1` 的级联目标仍可空，不能按非空 child 检查；dartc 遵循该行为，与[空安全补充][null-aware]中级联可继续传播的描述有差异。验证：`nullAwareValues` 与 `rejected`。

SDK 3.13.7 CFE 接受 `const dynamic value = null; const result = value?[true]`、`const result = null?.missing` 和 `const result = null?[0]`，analyzer 拒绝这些常量。dartc 采用 CFE 的空短路结果，同时拒绝被跳过的非常量函数调用、赋值和已知错误索引类型；`nullAwareValues` 保留对应 analyzer 诊断的逐行忽略，`rejected` 检查静态义务。

## 数值 API 与对照边界

[int `~/`](https://api.dart.dev/dart-core/int/operator_truncate_divide.html)、[int `%`](https://api.dart.dev/dart-core/int/operator_modulo.html) 和 [remainder](https://api.dart.dev/dart-core/num/remainder.html) 的整数零除沿普通同步异常机制抛出 IntegerDivisionByZeroException，静态、num/dynamic 与复合赋值保持求值顺序。错误类实现 Exception 与 UnsupportedError，message 为 `Division resulted in non-finite value`，自身 stackTrace 保持 null；catch 接收本次非空轨迹。混合 double 操作保留浮点规则：非有限整除结果抛出 UnsupportedError，模与余数为 NaN；无效实参先抛 TypeError。当前按 SDK 3.13.7 执行行为对照。验证：[values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) 的 `integerDivisions()`、[roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart) 的 `exceptionRoots()` 及 [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `uncaught` 和 NoGC 用例。

[double API](https://api.dart.dev/dart-core/double-class.html) 中已接入下列方法的直接调用：`parse`、`tryParse`、`toString`、`toInt`/`truncate`、`toDouble`、`remainder`、`compareTo`、`isNaN`/`isFinite`/`isInfinite`/`isNegative`，以及五个 double 常量。[parse](https://api.dart.dev/dart-core/double/parse.html) 对非法输入抛出普通 FormatException，保留原始 source 并支持类型捕获、finally、未捕获清理和异常载荷 GC 保活；tryParse 对同一输入返回 null。核心静态成员经类型别名访问、方法值提取和一般动态方法分派仍需补齐。`abs`、`sign`、取整变体、`clamp`、指定精度字符串、hashCode 与公开 Type 等仍是标准库缺口；`toInt`/`truncate` 的 NaN、正负 Infinity，以及 `~/` 的非有限 double 商，抛出普通 UnsupportedError，支持类型捕获、首次轨迹、finally 与继续执行；有限值仍按 64 位整数边界饱；类型检查失败抛出 TypeError，具体错误文本仍缺。验证：[values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) 的 `doubleValues`、`floatingContexts`，[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `uncaught`、`failingValues`，以及 [roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart) 的 `exceptionRoots`。

十进制输入输出、混合整数比较、非有限值及常量/运行时一致性以 SDK 3.13.7 为对照。SDK 的混合数值运算符会先把整数转换为 double：例如 `9007199254740992.0 == 9007199254740993` 为 true；`compareTo` 按精确数值返回 -1。这与 [num.operator == 的数学值描述](https://api.dart.dev/dart-core/num/operator_equals.html)存在边界差异，当前保留 SDK 行为并由用例固定，不把它宣称为完整规范一致性。[compareTo](https://api.dart.dev/dart-core/num/compareTo.html) 的 NaN 总序和正负零规则单独验证。SDK 的命名 `double.nan` 在 Linux x64 为负，在 macOS x64 和 ARM64 为正；无效浮点四则算术则在 x64 为负、ARM64 为正；无效取模与 remainder 使用平台数学库的 NaN，Linux x64 为负，其余当前目标为正。不同来源不能只按 CPU 使用同一规则。命名常量、无效四则及取模常量均按显式输出目标生成位模式，不依赖编译器宿主。`identical` 继续比较完整位模式。`doubleValues` 按同平台 SDK 对照命名常量与无效算术、运行时结果以及 const List/对象的身份。`parse`/`tryParse` 对 `NaN`、`-NaN` 使用平台默认 NaN，对 `+NaN` 使用正 NaN，与 [SDK 解析入口](https://github.com/dart-lang/sdk/blob/3.13.7/sdk/lib/_internal/vm/lib/double_patch.dart)一致。余数与取模在输入已是 NaN 时通过浮点原语保留符号和载荷并安静化 signaling NaN；输入并非 NaN 而取模或余数无效时生成平台数学库的 NaN。`doubleValues` 同时验证解析符号、无效取模常量和静态/dynamic 数值路径的 NaN 身份。

[draft]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex
[pdf]: https://dart.dev/to/spec-draft
[entry]: https://dart.dev/resources/language/spec
[nnbd]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md
[filled]: https://api.dart.dev/stable/3.13.5/dart-core/List/List.filled.html
[put]: https://api.dart.dev/stable/3.13.5/dart-core/List/operator_put.html
[clear]: https://api.dart.dev/stable/3.13.5/dart-core/List/clear.html

[closurization]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L13644-L13712
[getter-invocation]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L14589-L14601

[function-expressions]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L11795-L11831

[numbers]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L9232-L9353
[negative-literals]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L16817-L16845

[new-expression]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L12273-L12375

[cascades]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L14640-L14690
[constructor-tearoffs]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.15/constructor-tearoffs/feature-specification.md
[record-literals]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/records/feature-specification.md#record-expressions

[null-aware]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md

[collection-elements]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex

[null-aware-elements]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.8/null-aware-elements/feature-specification.md

[dot-shorthands]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.10/dot-shorthands/feature-specification.md

[identity]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L7915-L7962

[constant-type-checks]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L8895-L8964
