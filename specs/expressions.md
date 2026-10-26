# 表达式

兼容目标为 Dart 3.13.5，章节号以固定版本的[语言规范草案][draft]为准；[PDF][pdf]是可变的阅读入口。
[官方入口][entry]说明 Dart 3 规范尚不完整；空安全与类型推断还需结合[类型追踪](types.md)所列补充文档。
本页记录可运行子集及缺口，不复制规范正文，也不把某个表达式样例通过当成整个章节符合规范。

状态含义统一见[总览](README.md#状态与证据)，当前各行只描述已有子集和已知缺口。
实现布局、常量数据编码和原生调用约定见[架构设计](../doc/architecture.md)。

## 求值、常量与字面量

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §17.1 表达式求值 | 部分实现 | 已支持表达式按规定顺序求值，短路保留副作用；异常完成、异步及完整表达式集合尚缺。 | [frontend.dart](../lib/src/frontend.dart)：`feLowerExpression`；[values.dart](../test/fixtures/values.dart)：`assignmentValues`、`conditionContexts`。 |
| §17.2 对象身份 | 部分实现 | `identical` 覆盖整数、布尔、null 和对象身份；宽整数装箱不改变整数身份。双精度与记录身份未实现。 | [runtime.dart](../lib/src/runtime.dart)：`rtValueIdentical`；[constants.dart](../lib/src/constants.dart)：`_constantSame`；[values.dart](../test/fixtures/values.dart)：`constantLists`。 |
| §17.3 常量表达式 | 部分实现 | 标量、支持的运算、条件、插值、常量引用与核心 `identical` 可求值；拒绝非常量引用和循环。静态类型与实际负载分开；构造对象、Map、Set 等常量尚缺。 | [constants.dart](../lib/src/constants.dart)：`evaluateConstant`、`evaluateGlobalConstant`；[behavior_test.dart](../test/behavior_test.dart)：`rejected`、`libraries`。 |
| §17.3.2 常量上下文 | 部分实现 | 支持顶层和局部 const、嵌套隐式 const List 及上下文元素类型；参数 List 默认值需显式 `const`，不能把普通 `[]` 当默认常量。 | [constants.dart](../lib/src/constants.dart)：`_constantList`；[frontend.dart](../lib/src/frontend.dart)：`feResolveDefaults`；[values.dart](../test/fixtures/values.dart)：`constantDefaults`、`constantLists`。 |
| §17.4 null、§17.6 布尔 | 部分实现 | 有字面量及静态类型，动态布尔消费有检查；`Object`、`bool?` 不能未经转换或提升用作条件。 | [typing.dart](../lib/src/typing.dart)：`typingCondition`；[frontend.dart](../lib/src/frontend.dart)：`feBooleanValue`；[values.dart](../test/fixtures/values.dart)：`valueContexts`、`flowBranches`。 |
| §17.5 数字 | 部分实现 | 支持原生有符号 64 位整数、边界值和整数作为 `num` 实例；浮点字面量、`double` 与浮点执行未实现。 | [scanner.dart](../lib/src/scanner.dart)：`scanTokens`；[frontend.dart](../lib/src/frontend.dart)：`feLowerExpression`；[values.dart](../test/fixtures/values.dart)：`staticContexts`、`shiftContexts`。 |
| §17.7 字符串与插值 | 部分实现 | 字面量、拼接、插值和 UTF-16 内容可用；完整词法变体与全部 String API 尚未逐项核验。 | [parser.dart](../lib/src/parser.dart)：`parserPrimary`；[frontend.dart](../lib/src/frontend.dart)：`feLowerInterpolation`；[values.dart](../test/fixtures/values.dart)：`stringBoundaries`、`constantLists`。 |
| §17.9 集合字面量 | 部分实现 | 可变与 const List，显式或上下文元素类型、嵌套与空列表；const 按完整实际 `List<T>` 及元素规范化，跨库和嵌套共享身份。Set、Map、展开及集合 if/for 未实现。 | [frontend.dart](../lib/src/frontend.dart)：`feLowerList`；[constants.dart](../lib/src/constants.dart)：`_constantList`；[values.dart](../test/fixtures/values.dart)：`constantLists`；[behavior_test.dart](../test/behavior_test.dart)：`libraries`。 |

## 调用、查找与访问

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §17.12 `this`、§17.13 实例创建 | 部分实现 | 支持当前类实例、字段、普通构造器与字段形参；const 对象、工厂、重定向和父类构造链未实现。 | [frontend.dart](../lib/src/frontend.dart)：`feWithReceiver`、`feLowerStaticCall`；[values.dart](../test/fixtures/values.dart)：`localBindings`、`argumentCalls`。 |
| §17.15 函数调用 | 部分实现 | 必需/可选位置参数、命名/required 参数、声明库范围内的默认常量；实参按源码顺序求值后绑定。函数值调用和一般泛型调用尚缺。 | [arguments.dart](../lib/src/arguments.dart)：`bindArguments`；[frontend.dart](../lib/src/frontend.dart)：`feLowerArguments`；[values.dart](../test/fixtures/values.dart)：`argumentCalls`。 |
| §17.18–17.19 查找与顶层 getter | 部分实现 | 声明库及前缀查找、顶层变量惰性读取、支持的 getter；完整查找冲突和动态调用规则仍需核验。 | [symbols.dart](../lib/src/symbols.dart)：`resolveSymbol`；[frontend.dart](../lib/src/frontend.dart)：`feLoadDeclaration`、`feGenerateGlobals`；[behavior_test.dart](../test/behavior_test.dart)：`libraries`。 |
| §17.20–17.22 成员调用与属性读取 | 部分实现 | 已知类实例方法、字段、getter 及部分内建成员；一般动态成员分派、级联、super 和方法提取未实现。 | [frontend.dart](../lib/src/frontend.dart)：`feLowerMemberCall`、`feLowerMember`；[values.dart](../test/fixtures/values.dart)：`objectValues`、`localBindings`。 |
| §17.37–17.38 词法查找与标识符 | 部分实现 | 整个局部作用域预绑定，支持遮蔽、前向/自身引用错误及 `_`；闭包与局部函数作用域尚缺。 | [binding.dart](../lib/src/binding.dart)：`bindFunctionLocals`；[frontend.dart](../lib/src/frontend.dart)：`feReadLocal`；[values.dart](../test/fixtures/values.dart)：`localBindings`；[behavior_test.dart](../test/behavior_test.dart)：`rejected`。 |

## 赋值、分支与运算

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §17.23、§17.36 赋值与可赋值表达式 | 部分实现 | 局部、全局、字段、List 索引及已有复合赋值；接收者/索引只求值一次，存储转换不替代 RHS 的结果类型和负载。`??=` 未实现。 | [frontend.dart](../lib/src/frontend.dart)：`feLowerLvalue`、`feLowerAssignment`；[values.dart](../test/fixtures/values.dart)：`assignmentValues`、`staticContexts`。 |
| §17.24 条件表达式 | 部分实现 | 仅执行选定分支，两分支均检查并接受上下文类型；结果合并依赖当前有限类型 LUB。 | [frontend.dart](../lib/src/frontend.dart)：`feLowerConditional`；[values.dart](../test/fixtures/values.dart)：`conditionTernary`、`flowContexts`。 |
| §17.25 `??` | 部分实现 | 左侧一次求值，仅 null 时执行 RHS；两侧静态检查和接收 List 上下文；Null 左侧取 RHS 类型，否则合并非空左类型与 RHS。拒绝 void 左侧，允许 void RHS 并保留选中负载。 | [typing.dart](../lib/src/typing.dart)：`typingCoalescing`；[frontend.dart](../lib/src/frontend.dart)：`feLowerCoalescing`；[constants.dart](../lib/src/constants.dart)：`_constantCoalescing`；[values.dart](../test/fixtures/values.dart)：`coalescingContexts`。 |
| §17.26 逻辑表达式 | 部分实现 | `&&`、`\|\|` 短路及分支提升；普通布尔值与条件消费均保留副作用和动态 bool 检查。 | [frontend.dart](../lib/src/frontend.dart)：`feConditionJumps`、`feLowerExpression`；[values.dart](../test/fixtures/values.dart)：`conditionContexts`；[behavior_test.dart](../test/behavior_test.dart)：`failingValues`。 |
| §17.27 相等 | 部分实现 | 当前标量值比较与 List/普通对象身份，`Object?` 和 null 可比较；用户声明的 `operator ==` 与完整分派未实现。 | [typing.dart](../lib/src/typing.dart)：`typingBinary`；[runtime.dart](../lib/src/runtime.dart)：`rtValueEq`；[values.dart](../test/fixtures/values.dart)：`staticContexts`、`constantLists`。 |
| §17.28 关系运算 | 部分实现 | 整数及整数 `num` 路径；静态数值左侧结果 bool，动态左侧结果 dynamic；浮点和用户运算符未实现。 | [typing.dart](../lib/src/typing.dart)：`typingBinary`；[values.dart](../test/fixtures/values.dart)：`staticContexts`、`conditionComparisons`。 |
| §17.29–17.30 位运算与移位 | 部分实现 | 整数 `&`、`\|`、`^`、`<<`、`>>`、`>>>` 及布尔位运算；覆盖 64 位边界、大移位与负数失败。用户运算符未实现。 | [typing.dart](../lib/src/typing.dart)：`typingBinary`；[values.dart](../test/fixtures/values.dart)：`literalShifts`、`shiftContexts`；[behavior_test.dart](../test/behavior_test.dart)：`failingValues`。 |
| §17.31–17.32 加法与乘法类 | 部分实现 | `+`、`-`、`*`、`~/`、`%`，String 拼接；`int + dynamic` 为 num，`dynamic + int` 为 dynamic，整数 `~/ dynamic` 为 int。`/` 和浮点运算未实现。 | [typing.dart](../lib/src/typing.dart)：`typingBinary`；[frontend.dart](../lib/src/frontend.dart)：`feCombine`；[values.dart](../test/fixtures/values.dart)：`staticContexts`。 |
| §17.33、§17.35 一元与后缀 | 部分实现 | `!`、数值负号、整数 `~`、前后 `++`/`--`；增减的结果与存储类型分别处理。空断言 `!` 后缀及用户运算符未实现。 | [typing.dart](../lib/src/typing.dart)：`typingUnary`；[frontend.dart](../lib/src/frontend.dart)：`feLowerAssignment`；[values.dart](../test/fixtures/values.dart)：`assignmentValues`、`flowAssignments`。 |
| §17.39–17.40 类型测试与转换 | 部分实现 | `is`、`is!`、`as` 保留单次求值，覆盖当前类型和完整 List 参数；允许无关静态类型的显式 cast 后在运行时检查。函数、记录及一般泛型目标未实现。 | [frontend.dart](../lib/src/frontend.dart)：`feLowerExpression`；[runtime.dart](../lib/src/runtime.dart)：`rtValueMatches`、`rtValueCast`；[values.dart](../test/fixtures/values.dart)：`typeChecks`。 |

## List API 边界

这些条目属于 Dart 3.13.5 SDK API，不能计作 §17.9 的全部语言规则已完成。

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| [`List.filled`][filled] | 部分实现 | 默认固定长度，`growable: true` 可增长；实参一次求值、共享 fill 引用。并未覆盖全部 List 构造器和长度 setter。 | [frontend.dart](../lib/src/frontend.dart)：`feLowerStaticCall`；[runtime.dart](../lib/src/runtime.dart)：`rtListFilled`；[values.dart](../test/fixtures/values.dart)：`filledLists`。 |
| [`[]=`][put]、[`clear`][clear] 与只读 List | 部分实现 | 支持索引、add、removeLast、clear；写入按实际元素类型检查，再检查只读性和范围；空 const 也不可 clear。类型、只读及范围失败尚以退出表示，不具备完整可捕获异常语义。 | [runtime.dart](../lib/src/runtime.dart)：`rtListSet`、`rtListAdd`、`rtListClear`；[behavior_test.dart](../test/behavior_test.dart)：`failingValues`。 |

## 尚缺与待核验

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §17.8、§17.10–17.11、§17.14 | 未实现 | Symbol 字面量、throw 表达式、函数表达式和 isolate 创建尚未接入。 | [ast.dart](../lib/src/ast.dart) 尚无对应表达式；尚无行为验证。 |
| §17.16–17.17、§17.34 | 未实现 | 函数提取、泛型函数实例化、await；尚无闭包和异步执行基础。 | 后续扩展 [parser.dart](../lib/src/parser.dart)、[frontend.dart](../lib/src/frontend.dart)；尚无行为验证。 |
| 空安全及后续 Dart 3 表达式 | 未实现 | `?.`、`?[]`、空断言、记录和模式相关表达式未实现；不能由 `??` 覆盖推定支持。 | 后续扩展 [parser.dart](../lib/src/parser.dart)、[ast.dart](../lib/src/ast.dart)；尚无行为验证。 |
| 优先级、所有静态错误及完成方式 | 待核对 | 已有解析和拒绝样例，尚未逐规则核验官方语言测试；成功自举不提供完整表达式兼容性证明。 | [parser.dart](../lib/src/parser.dart)：`parserPrecedence`、`parserBinary`；[behavior_test.dart](../test/behavior_test.dart)：`rejected`。 |

[draft]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex
[pdf]: https://dart.dev/to/spec-draft
[entry]: https://dart.dev/resources/language/spec
[filled]: https://api.dart.dev/stable/3.13.5/dart-core/List/List.filled.html
[put]: https://api.dart.dev/stable/3.13.5/dart-core/List/operator_put.html
[clear]: https://api.dart.dev/stable/3.13.5/dart-core/List/clear.html
