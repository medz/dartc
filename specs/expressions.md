# 表达式

兼容目标与 SDK 对照版本见[总览](README.md)，章节号以固定版本的[语言规范草案][draft]为准；[PDF][pdf]是可变的阅读入口。
[官方入口][entry]说明 Dart 3 规范尚不完整；空安全与类型推断还需结合[类型追踪](types.md)所列补充文档。
本页记录表达式的支持范围与缺口，状态含义见[总览](README.md#状态与证据)。
实现布局、常量数据编码和原生调用约定见[架构设计](../doc/architecture.md)。

## 求值、常量与字面量

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §17.1 表达式求值 | 部分实现 | 已支持表达式按规定顺序求值，短路保留副作用；异常完成、异步及完整表达式集合尚缺。 | [frontend.dart](../lib/src/frontend.dart)：`feLowerExpression`；[values.dart](../test/fixtures/values.dart)：`assignmentValues`、`conditionContexts`。 |
| §17.2 对象身份 | 部分实现 | `identical` 覆盖整数、布尔、null 和对象身份；宽整数装箱不改变整数身份；const 类实例按实际类及规范化字段共享身份，普通构造调用保持新实例；同一顶层函数的值引用跨前缀和导出共享身份。双精度与记录身份未实现。 | [runtime.dart](../lib/src/runtime.dart)：`rtValueIdentical`；[constants.dart](../lib/src/constants.dart)：`_constantSame`；[values.dart](../test/fixtures/values.dart)：`constantLists`、`constObjects`、`functionValues`。 |
| §17.3 常量表达式 | 部分实现 | 标量、支持的运算、条件、插值、常量引用、受支持的顶层函数引用与核心 `identical` 可求值；拒绝非常量引用和循环。静态类型与实际负载分开；支持当前生成式构造器子集的 const 实例，与 List 共用规范化身份；Map、Set、完整潜在常量表达式及其他构造形式仍缺。 | [constants.dart](../lib/src/constants.dart)：`evaluateConstant`、`evaluateGlobalConstant`、`checkConstantConstructors`；[values.dart](../test/fixtures/values.dart)：`constObjects`；[behavior_test.dart](../test/behavior_test.dart)：`rejected`、`libraries`。 |
| §17.3.2 常量上下文 | 部分实现 | 支持顶层和局部 const、嵌套隐式 const List 及上下文元素类型；参数 List 默认值需显式 `const`，不能把普通 `[]` 当默认常量。const 构造实参引入隐式常量上下文；构造器声明默认值和字段初始化仍按自身声明作用域及常量资格检查，不能由调用方上下文放宽。 | [constants.dart](../lib/src/constants.dart)：`_constantList`；[frontend.dart](../lib/src/frontend.dart)：`feResolveDefaults`；[values.dart](../test/fixtures/values.dart)：`constantDefaults`、`constantLists`。 |
| §17.4 null、§17.6 布尔 | 部分实现 | 有字面量及静态类型，动态布尔消费有检查；`Object`、`bool?` 不能未经转换或提升用作条件。 | [typing.dart](../lib/src/typing.dart)：`typingCondition`；[frontend.dart](../lib/src/frontend.dart)：`feBooleanValue`；[values.dart](../test/fixtures/values.dart)：`valueContexts`、`flowBranches`。 |
| [§17.5 数字][numbers] | 部分实现 | 支持有符号 64 位整数及 `num` 身份；十进制负边界只允许[直接负字面量][negative-literals]，括号内字面量先独立校验。非负十六进制可用完整 64 位补码，直接负十六进制仍受有符号范围约束；普通表达式和常量同用范围规则。浮点字面量、`double` 与浮点执行未实现。 | [literals.dart](../lib/src/frontend/literals.dart)：`isNegatedIntegerLiteral`、`decodeIntegerLiteral`；[values.dart](../test/fixtures/values.dart)：`shiftContexts`；[behavior_test.dart](../test/behavior_test.dart)：`rejected`。 |
| §17.7 字符串与插值 | 部分实现 | 字面量、拼接、插值和 UTF-16 内容可用；完整词法变体与全部 String API 尚未逐项核验。 | [parser.dart](../lib/src/parser.dart)：`parserPrimary`；[frontend.dart](../lib/src/frontend.dart)：`feLowerInterpolation`；[values.dart](../test/fixtures/values.dart)：`stringBoundaries`、`constantLists`。 |
| §17.9 集合字面量 | 部分实现 | 可变与 const List，显式或上下文元素类型、嵌套与空列表；const 按完整实际 `List<T>` 及元素规范化，跨库和嵌套共享身份。支持嵌套的 if/else、for、for-in 及普通/空感知展开，具体规则见下一条；Set、Map、模式与异步集合元素未实现。 | [frontend.dart](../lib/src/frontend.dart)：`feLowerList`；[constants.dart](../lib/src/constants.dart)：`_constantList`；[values.dart](../test/fixtures/values.dart)：`constantLists`；[behavior_test.dart](../test/behavior_test.dart)：`libraries`。 |
| [§17.9 集合元素、推断与求值][collection-elements] | 部分实现 | List 的条件与循环元素按源码顺序求值，共用语句的作用域、流分析和逐轮捕获规则；局部、顶层、静态/实例字段及构造器初始化中的循环均保留绑定。`...` 与 `...?` 支持 List，空感知展开仅跳过 null 集合，保留内部 null；静态元素类型参与上下文与 LUB 推断，dynamic 源按运行时元素逐个检查。const 支持条件/展开及规范化身份；未执行元素仍检查类型和潜在常量资格，for 元素不是潜在常量。一般 Iterable/Iterator、Set/Map 及完整推断仍缺。 | [parser.dart](../lib/src/parser.dart)：`parserCollectionElement`、`parserFor`；[binding.dart](../lib/src/binding.dart)：`bindingExpression`；[frontend.dart](../lib/src/frontend.dart)：`feLowerListElement`、`feLowerListSpread`、`feLowerInitializer`；[constants.dart](../lib/src/constants.dart)：`_constantListElement`；[values.dart](../test/fixtures/values.dart)：`collectionValues`；[behavior_test.dart](../test/behavior_test.dart)：`rejected`、`failingValues`。 |
| [空感知集合元素][null-aware-elements] | 部分实现 | 语言版本 3.8 起支持 List 中的 `?expression`，包括 if/for 嵌套和常量上下文。表达式一次求值，仅丢弃 null；下行上下文允许 null，上行元素类型取 NonNull，Null 得 Never，dynamic 仍为 dynamic。过滤不提升后续表达式中的变量，赋值副作用仍无条件发生；静态类型和潜在常量资格不因元素被跳过而省略。Set/Map 尚未实现；void 与未选中常量分支的 SDK 差异见下文。 | [parser.dart](../lib/src/parser.dart)：`parserCollectionElement`；[typing.dart](../lib/src/typing.dart)：`typingNonNull`；[frontend.dart](../lib/src/frontend.dart)：`feLowerListElement`；[constants.dart](../lib/src/constants.dart)：`_constantListElement`；[values.dart](../test/fixtures/values.dart)：`collectionValues`；[behavior_test.dart](../test/behavior_test.dart)：`rejected`、`failingValues`。 |

## 调用、查找与访问

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §17.12 `this`、§17.13 实例创建 | 部分实现 | 支持当前类实例、字段、普通构造器与字段形参；支持已实现的生成式构造与规范化 const 实例，细则见[类追踪](classes.md)；工厂和父类构造链未实现。 | [frontend.dart](../lib/src/frontend.dart)：`feWithReceiver`、`feLowerStaticCall`；[values.dart](../test/fixtures/values.dart)：`localBindings`、`argumentCalls`、`constObjects`。 |
| [§17.13.1 `new` 表达式][new-expression] | 部分实现 | 前导 `new` 必须解析到已实现的类构造器，可经类名或用户类类型别名调用未命名、命名与 `.new` 构造器，并保留原有参数检查和求值顺序；支持既有 `List.filled`、`String.fromCharCodes` 构造入口，其类型别名入口尚缺。普通函数、getter、函数值及静态方法不因 `new` 变成构造器；`new` 在嵌套或未执行的常量分支中也不是常量。生成式重定向的规则见[类追踪](classes.md)；一般工厂、泛型类及继承构造仍缺。 | [ast.dart](../lib/src/ast.dart)：`astCallNew`；[parser.dart](../lib/src/parser.dart)：`parserPrimary`；[frontend.dart](../lib/src/frontend.dart)：`feLowerCall`；[constants.dart](../lib/src/constants.dart)：`_constantConstructor`；[values.dart](../test/fixtures/values.dart)：`namedConstructors`、`filledLists`、`stringBoundaries`；[behavior_test.dart](../test/behavior_test.dart)：`named-constructors-imports.dart`、`rejected`。 |
| [§17.14 函数表达式][function-expressions] | 部分实现 | 支持同步非泛型匿名箭头体与块体及必需位置参数签名的捕获，以及签名上下文推断；无捕获字面量直接调用和 `.call` 支持可选/命名参数。一般函数值签名限制与捕获范围见[函数](functions.md)。 | [parser.dart](../lib/src/parser.dart) `parserFunctionExpression()`；[frontend.dart](../lib/src/frontend.dart) `feLowerFunctionExpression()`；[behavior_test.dart](../test/behavior_test.dart) `program/anonymousFunctions()`、`rejected`。 |
| §17.15 函数调用 | 部分实现 | 必需/可选位置参数、命名/required 参数、声明库范围内的默认常量；实参按源码顺序求值后绑定。调用的类型实参与 callee 自有类型分开存储；已有普通函数、构造器和方法拒绝不匹配的类型实参。支持具体非泛型必需位置签名的值调用及 `.call`，参数和结果按静态签名检查；可选/命名函数值签名、泛型以及 dynamic/裸 Function 调用尚缺。 | [arguments.dart](../lib/src/frontend/arguments.dart)：`bindArguments`；[frontend.dart](../lib/src/frontend.dart)：`feLowerArguments`、`feLowerFunctionCall`；[values.dart](../test/fixtures/values.dart)：`argumentCalls`、`functionValues`。 |
| [§17.16 函数提取][closurization] | 部分实现 | 对[已支持的函数值来源和签名](functions.md#函数值)按声明规范化身份，保留仅经值引用的目标。静态方法提取复用普通函数值，实例方法值保存单次求值的接收者；完整签名、相等性与缺口由函数条目维护。 | [frontend.dart](../lib/src/frontend.dart)：`feFunctionReference`、`feCreateBoundMethod`；[reach.dart](../lib/src/reach.dart)：`reachableFunctions`；[values.dart](../test/fixtures/values.dart)：`functionValues`；[behavior_test.dart](../test/behavior_test.dart)：`function-imports.dart`。 |
| §17.18–17.19 查找与顶层 getter | 部分实现 | 声明库及前缀按读/写分别解析，支持顶层 getter/setter 和变量惰性读取；本库任一同名声明遮蔽导入的两侧。完整库冲突与 SDK 差异见[库追踪](libraries.md)。 | [symbols.dart](../lib/src/symbols.dart)：`resolveSymbol`、`resolveWriteSymbol`；[frontend.dart](../lib/src/frontend.dart)：`feLoadDeclaration`、`feGenerateGlobals`；[values.dart](../test/fixtures/values.dart)：`topAccessorValues`；[behavior_test.dart](../test/behavior_test.dart)：`libraries`。 |
| §17.20–17.22 成员调用与属性读取 | 部分实现 | 按[类成员声明](classes.md)区分实例接收者与静态限定目标，读取和写入分别选择声明与类型；字段/getter 返回的具体函数值可调用，读取时机见下方 SDK 差异说明。仅写属性不能读取；一般动态成员分派和 super 未实现；空短路访问见下一条。 | [members.dart](../lib/src/members.dart)：`bindClassMembers`；[frontend.dart](../lib/src/frontend.dart)：`feLowerMemberCall`、`feReadBoundMember`；[values.dart](../test/fixtures/values.dart)：`accessorValues`、`localBindings`、`functionValues`。 |
| [空安全补充：空短路访问][null-aware] | 部分实现 | 支持 `?.`、`?[]` 的属性、调用、索引、空断言及赋值/增减链；接收者一次求值，null 时跳过后续选择器、实参、索引和 RHS。括号与普通运算终止传播，类型限定目标沿用静态查找。值接收者的结果可空，即使接收者静态非空；void 仍不能被消费。常量路径支持 String.length 与被跳过的索引，仍检查潜在常量资格及索引类型；一般动态分派和完整常量成员规则仍缺。 | [parser.dart](../lib/src/parser.dart)：`parserSelectors`、`parserIndexIsConditional`；[frontend.dart](../lib/src/frontend.dart)：`feLowerNullAware`；[constants.dart](../lib/src/constants.dart)：`_evaluateConstant`；[values.dart](../test/fixtures/values.dart)：`nullAwareValues`；[behavior_test.dart](../test/behavior_test.dart)：`rejected`、`failingValues`。 |
| [§17.15 级联][cascades] | 部分实现 | 支持 `..` 与首次 `?..`，接收者一次求值并保留为结果；各段按序访问、调用、索引或赋值，null 时跳过整组副作用。接收者获得上下文类型，空短路分支参与提升及确定赋值合流；3.9 起以非空目标类型排除 null 分支。静态义务不因跳过执行而消失。嵌套级联、段内空短路访问与箭头函数体遵循 SDK 解析；一般动态分派仍缺。 | [parser.dart](../lib/src/parser.dart)：`parserCascadeSection`；[frontend.dart](../lib/src/frontend.dart)：`feLowerCascade`；[values.dart](../test/fixtures/values.dart)：`cascadeValues`；[behavior_test.dart](../test/behavior_test.dart)：`rejected`。 |
| 空安全补充：`Never` 表达式消费 | 部分实现 | 支持底类型接收者的属性、索引及已有调用入口；结果保留 `Never`，仍检查实参、重复命名参数、类型实参与 void 消费。此类路径不能产生实际接收者，不引入一般动态分派；方法提取等入口仍缺。 | [frontend.dart](../lib/src/frontend.dart)：`feReadMember`、`feLowerNeverArguments`、`feLowerLvalue`；[behavior_test.dart](../test/behavior_test.dart)：`neverExpressions`、`rejected`；规则依据[空安全补充][nnbd]。 |
| §17.37–17.38 词法查找与标识符 | 部分实现 | 整个局部作用域预绑定，支持遮蔽、前向/自身引用错误及 `_`；局部和匿名函数保持独立函数体作用域，外层捕获沿原声明绑定；模式绑定未实现。 | [binding.dart](../lib/src/binding.dart)：`bindFunctionLocals`；[frontend.dart](../lib/src/frontend.dart)：`feReadLocal`；[values.dart](../test/fixtures/values.dart)：`localBindings`；[behavior_test.dart](../test/behavior_test.dart)：`rejected`。 |

## 赋值、分支与运算

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §17.23、§17.36 赋值与可赋值表达式 | 部分实现 | 局部、全局、字段、实例/顶层 setter、List 索引及已有复合赋值；接收者/索引只求值一次，简单赋值保留原 RHS 类型和负载，setter 返回值不替代它；复合赋值独立检查 getter 运算和 setter 写入类型。final/const 存储只读，同名显式 setter 可以接收写入。`??=` 仅 null 时求值并写入 RHS，仍检查读写两侧及未执行的 RHS；原读取/RHS 负载独立于 setter 转换。 | [frontend.dart](../lib/src/frontend.dart)：`feLowerLvalue`、`feLowerAssignment`、`feWriteLvalue`；[values.dart](../test/fixtures/values.dart)：`assignmentValues`、`accessorValues`、`topAccessorValues`、`coalescingAssignmentValues`；[behavior_test.dart](../test/behavior_test.dart)：`neverExpressions`、`rejected`、`failingValues`。 |
| §17.24 条件表达式 | 部分实现 | 仅执行选定分支，两分支均检查并接受上下文类型；结果合并依赖当前有限类型 LUB。 | [frontend.dart](../lib/src/frontend.dart)：`feLowerConditional`；[values.dart](../test/fixtures/values.dart)：`conditionTernary`、`flowContexts`。 |
| §17.25 `??` | 部分实现 | 左侧一次求值，仅 null 时执行 RHS；两侧静态检查和接收 List 上下文；Null 左侧取 RHS 类型，否则合并非空左类型与 RHS。拒绝 void 左侧，允许 void RHS 并保留选中负载。 | [typing.dart](../lib/src/typing.dart)：`typingCoalescing`；[frontend.dart](../lib/src/frontend.dart)：`feLowerCoalescing`；[constants.dart](../lib/src/constants.dart)：`_constantCoalescing`；[values.dart](../test/fixtures/values.dart)：`coalescingContexts`。 |
| §17.26 逻辑表达式 | 部分实现 | `&&`、`\|\|` 短路及分支提升；普通布尔值与条件消费均保留副作用和动态 bool 检查。 | [frontend.dart](../lib/src/frontend.dart)：`feConditionJumps`、`feLowerExpression`；[values.dart](../test/fixtures/values.dart)：`conditionContexts`；[behavior_test.dart](../test/behavior_test.dart)：`failingValues`。 |
| §17.27 相等 | 部分实现 | 当前标量值比较与 List/普通对象身份，`Object?` 和 null 可比较；用户声明的 `operator ==` 与完整分派未实现。const 实例比较区分 canonical 身份与 primitive equality，覆写 `hashCode` 的类不能参与一般活跃常量相等求值，与 null 比较除外。 | [typing.dart](../lib/src/typing.dart)：`typingBinary`；[runtime.dart](../lib/src/runtime.dart)：`rtValueEq`；[values.dart](../test/fixtures/values.dart)：`staticContexts`、`constantLists`。 |
| §17.28 关系运算 | 部分实现 | 整数及整数 `num` 路径；静态数值左侧结果 bool，动态左侧结果 dynamic；浮点和用户运算符未实现。 | [typing.dart](../lib/src/typing.dart)：`typingBinary`；[values.dart](../test/fixtures/values.dart)：`staticContexts`、`conditionComparisons`。 |
| §17.29–17.30 位运算与移位 | 部分实现 | 整数 `&`、`\|`、`^`、`<<`、`>>`、`>>>` 及布尔位运算；覆盖 64 位边界、大移位与负数失败。用户运算符未实现。 | [typing.dart](../lib/src/typing.dart)：`typingBinary`；[values.dart](../test/fixtures/values.dart)：`literalShifts`、`shiftContexts`；[behavior_test.dart](../test/behavior_test.dart)：`failingValues`。 |
| §17.31–17.32 加法与乘法类 | 部分实现 | `+`、`-`、`*`、`~/`、`%`，String 拼接；`int + dynamic` 为 num，`dynamic + int` 为 dynamic，整数 `~/ dynamic` 为 int。`/` 和浮点运算未实现。 | [typing.dart](../lib/src/typing.dart)：`typingBinary`；[frontend.dart](../lib/src/frontend.dart)：`feCombine`；[values.dart](../test/fixtures/values.dart)：`staticContexts`。 |
| §17.33、§17.35 一元与后缀 | 部分实现 | 前缀逻辑 `!`、数值负号、整数 `~`、前后 `++`/`--`；增减的结果与存储类型分别处理。用户运算符未实现。 | [typing.dart](../lib/src/typing.dart)：`typingUnary`；[frontend.dart](../lib/src/frontend.dart)：`feLowerAssignment`；[values.dart](../test/fixtures/values.dart)：`assignmentValues`、`flowAssignments`。 |
| 空安全补充：空断言 `e!` | 部分实现 | 操作数只求值一次，仅 null 时运行失败（尚不可捕获），否则保留原值；结果为 NonNull(T)，Null 得 Never，dynamic 仍为 dynamic。透传 List 上下文并提升直接局部读取；void 操作数、常量上下文及作为赋值目标均拒绝。 | [typing.dart](../lib/src/typing.dart)：`typingNullAssertion`；[frontend.dart](../lib/src/frontend.dart)：`feLowerNullAssertion`；[values.dart](../test/fixtures/values.dart)：`nullAssertionValues`；[behavior_test.dart](../test/behavior_test.dart)：`nullAssertion`、`neverAssertion`、`neverExpressions`、`rejected`、`failingValues`；依据[空安全补充][nnbd]。 |
| §17.39–17.40 类型测试与转换 | 部分实现 | `is`、`is!`、`as` 保留单次求值，覆盖当前类型和完整 List 参数；允许无关静态类型的显式 cast 后在运行时检查；`as` 可消费 void 的实际负载，`is` 和隐式消费不因此放宽。支持已实现函数签名及 Function 上界；记录及一般泛型目标未实现。 | [frontend.dart](../lib/src/frontend.dart)：`feLowerExpression`；[runtime.dart](../lib/src/runtime.dart)：`rtValueMatches`、`rtValueCast`；[values.dart](../test/fixtures/values.dart)：`typeChecks`、`valueContexts`、`functionValues`。 |
| 空安全补充：底类型运算结果 | 部分实现 | 支持的普通运算在 Never 左侧保留底类型；相等、逻辑和 `!` 仍为 bool。具体接收者沿用其结果规则，例如 `int + Never` 为 num。不能因路径不完成而跳过其他操作数的静态检查。 | [typing.dart](../lib/src/typing.dart)：`typingBinary`、`typingUnary`；[frontend.dart](../lib/src/frontend.dart)：`feCombine`；[behavior_test.dart](../test/behavior_test.dart)：`neverNegation`、`neverRelation`、`neverRightArithmetic`、`neverLogical`。 |

## List API 边界

这些条目属于标准库 API，不能计作 §17.9 的全部语言规则已完成。

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| [`List.filled`][filled] | 部分实现 | 默认固定长度，`growable: true` 可增长；实参一次求值、共享 fill 引用。并未覆盖全部 List 构造器和长度 setter。 | [frontend.dart](../lib/src/frontend.dart)：`feLowerStaticCall`；[runtime.dart](../lib/src/runtime.dart)：`rtListFilled`；[values.dart](../test/fixtures/values.dart)：`filledLists`。 |
| [`[]=`][put]、[`clear`][clear] 与只读 List | 部分实现 | 支持索引、add、removeLast、clear；写入按实际元素类型检查，再检查只读性和范围；空 const 也不可 clear。类型、只读及范围失败尚以退出表示，不具备完整可捕获异常语义。 | [runtime.dart](../lib/src/runtime.dart)：`rtListSet`、`rtListAdd`、`rtListClear`；[behavior_test.dart](../test/behavior_test.dart)：`failingValues`。 |
| [`removeAt`](https://api.dart.dev/stable/3.13.7/dart-core/List/removeAt.html) | 部分实现 | 删除并返回指定元素，保留其静态类型和剩余元素顺序；接收者与索引按序各求值一次。固定/只读列表在范围检查前拒绝改长，索引的入口类型检查仍先执行；失败沿用进程终止边界，尚无完整可捕获异常。 | [runtime.dart](../lib/src/runtime.dart)：`rtListRemoveAt`；[values.dart](../test/fixtures/values.dart)：`listGrowth`；[behavior_test.dart](../test/behavior_test.dart)：`failingValues`。 |
| [`insert`](https://api.dart.dev/dart-core/List/insert.html) | 部分实现 | 在 `0..length` 插入并保持后续元素顺序，返回 void；接收者、索引、元素按序求值。元素按实际类型检查，再拒绝固定/只读列表及非法范围；失败仍为进程终止，尚无可捕获异常。 | [runtime.dart](../lib/src/runtime.dart)：`rtListInsert`、`rtListGrow`；[values.dart](../test/fixtures/values.dart)：`listGrowth`；[behavior_test.dart](../test/behavior_test.dart)：`failingValues`、NoGC 拒例。 |

## StringBuffer API 边界

这些条目属于标准库 API，不代表完整标准库已实现。

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| [`writeCharCode`](https://api.dart.dev/stable/3.13.5/dart-core/StringBuffer/writeCharCode.html)、[`isNotEmpty`](https://api.dart.dev/stable/3.13.5/dart-core/StringBuffer/isNotEmpty.html) | 部分实现 | 支持 0..0x10FFFF，补充字符拆为 UTF-16 代理对，保留孤代理项；长度按 UTF-16 单元计算，clear 后查询为空。非法码点沿用运行时终止边界，尚无可捕获的 RangeError 对象；writeAll 等 API 尚未实现。 | [string_buffer.dart](../lib/src/std/core/string_buffer.dart)：`writeCharCode`、`isNotEmpty`；[values.dart](../test/fixtures/values.dart)：`bufferValues`；[behavior_test.dart](../test/behavior_test.dart)：`failingValues`。 |

## 尚缺与待核验

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §17.8、§17.10–17.11 | 未实现 | Symbol 字面量、throw 表达式和 isolate 创建未实现。 | [ast.dart](../lib/src/ast.dart) 尚无对应表达式；尚无行为验证。 |
| §17.17、§17.34 | 未实现 | 泛型函数实例化、await；尚无一般泛型或异步执行基础。 | [parser.dart](../lib/src/parser.dart)、[frontend.dart](../lib/src/frontend.dart)；尚无行为验证。 |
| Dart 3 表达式 | 未实现 | 记录和模式相关表达式未实现。 | [parser.dart](../lib/src/parser.dart)、[ast.dart](../lib/src/ast.dart)；尚无行为验证。 |
| 优先级、所有静态错误及完成方式 | 待核对 | 优先级、静态错误及完成方式的完整一致性覆盖尚缺。 | [parser.dart](../lib/src/parser.dart)：`parserPrecedence`、`parserBinary`；[behavior_test.dart](../test/behavior_test.dart)：`rejected`。 |

实例 getter 的函数值调用按 SDK 3.13.5 CFE 求值顺序处理：以 receiver、getter、实参、函数体分别记为 1、2、3、4，`receiver().callback(arg())` 的轨迹为 `1324`，`(receiver().callback)(arg())` 为 `1234`；隐式 this 遵循实例形式；顶层和静态 getter 先读取再求实参，静态选择器加括号不改变顺序。[固定草案的 getter fallback][getter-invocation]描述先调用 getter 再调用返回值，与此行为有差异；dartc 采用 SDK 3.13.5 的顺序，不据此判定上游缺陷。行为入口为 [values.dart](../test/fixtures/values.dart) 的 `functionValues()` 与 `staticMembers()`。

SDK 3.13.5 对 `??=` 有两处 analyzer/CFE 差异待核对：`void` getter 作为左侧时 analyzer 拒绝，CFE 接受表达式语句，dartc 按 void 值消费规则拒绝；`int f(Never value, dynamic fallback) { value ??= fallback; }` 的正常落空被 analyzer 拒绝而被 CFE 接受，dartc 将 `Never` 读取视为不能正常完成，仍检查 RHS。此差异不扩展为一般诊断一致性结论，后者由 [behavior_test.dart](../test/behavior_test.dart) 的 `neverLocalCoalescing` 跟踪。

空断言选择器遵循固定草案的 `selector*`：允许重复 `!` 后继续成员、索引或调用。SDK 3.13.5 的[解析路径][sdk-bang-parser]会拒绝 `value!!.member`、`value!![0]`、`value!!(1)`，而 `(value!!)(1)` 可通过；dartc 在此采用规范文法，与 SDK 的诊断不完全一致。

SDK 3.13.7 CFE 接受 `const values = [if (false) <int>[1][9] else 2]`，analyzer 将被跳过的索引报告为 `non_constant_list_element`。dartc 按 CFE 检查该分支的潜在常量资格与索引类型，不执行取值或范围检查；`collectionValues` 保留该差异的行为用例与逐行 analyzer 忽略。

SDK 3.13.7 CFE 接受推断或显式 `List<void>` 中的空感知元素，按实际负载过滤 null；analyzer 报 `use_of_void_result`。CFE 也接受 `const dynamic x = 'wrong'; const values = <int>[if (false) ?x]`，analyzer 报 `non_constant_list_element`。dartc 在这两处采用 CFE 行为：仍检查 void 不能用于其他元素类型，动态常量只在选中分支检查实际负载。`collectionValues` 保留行为用例和逐行 analyzer 忽略，`rejected` 验证对应的静态及活跃常量错误。

SDK 3.13.7 的 [`?[]` 判定][sdk-null-index-parser]优先选择可解析的条件表达式；`true ? (values?[0]) : 0` 需要内层括号，否则该写法被拒绝。类型转换、可空类型和泛型实参不得误作条件分隔符。普通级联在此 SDK 中终止空短路传播：`receiver()?.child()..field = 1` 的级联目标仍可空，不能按非空 child 检查；dartc 遵循该行为，与[空安全补充][null-aware]中级联可继续传播的描述有差异。验证入口为 `nullAwareValues` 与 `rejected`。

SDK 3.13.7 CFE 接受 `const dynamic value = null; const result = value?[true]`、`const result = null?.missing` 和 `const result = null?[0]`，analyzer 拒绝这些常量。dartc 采用 CFE 的空短路结果，同时拒绝被跳过的非常量函数调用、赋值和已知错误索引类型；`nullAwareValues` 保留对应 analyzer 诊断的逐行忽略，`rejected` 检查静态义务。

[draft]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex
[pdf]: https://dart.dev/to/spec-draft
[entry]: https://dart.dev/resources/language/spec
[nnbd]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md
[filled]: https://api.dart.dev/stable/3.13.5/dart-core/List/List.filled.html
[put]: https://api.dart.dev/stable/3.13.5/dart-core/List/operator_put.html
[clear]: https://api.dart.dev/stable/3.13.5/dart-core/List/clear.html
[sdk-bang-parser]: https://github.com/dart-lang/sdk/blob/3.13.5/pkg/_fe_analyzer_shared/lib/src/parser/parser_impl.dart#L7400-L7413

[closurization]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L13644-L13712
[getter-invocation]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L14589-L14601

[function-expressions]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L11795-L11831

[numbers]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L9232-L9353
[negative-literals]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L16817-L16845

[new-expression]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L12273-L12375

[cascades]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L13521-L13613

[null-aware]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md
[sdk-null-index-parser]: https://github.com/dart-lang/sdk/blob/3.13.7/pkg/_fe_analyzer_shared/lib/src/parser/parser_impl.dart#L6694-L6719

[collection-elements]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex

[null-aware-elements]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.8/null-aware-elements/feature-specification.md
