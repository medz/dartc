# 语句：§18 Statements

按[固定草案源码](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)的 §18 建立索引；条款目录见[官方草案 PDF](https://dart.dev/to/spec-draft)。
SDK 对照版本见[总览](README.md)；本表的 switch 语句仍采用常量 case，switch 表达式的模式实现见[模式](patterns.md)。

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §18.0.1 语句完成方式 | 部分实现 | lowering 表示正常、返回、break 和 continue；异常完成及栈展开未实现。 | [frontend.dart](../lib/src/frontend.dart) `feLowerStatement()`；[flow.dart](../lib/src/flow.dart) `FlowState`；[values.dart](../test/fixtures/values.dart) `flowContexts()` |
| §18.1 块 | 部分实现 | 顺序执行并创建局部作用域；局部函数有独立参数与函数体作用域，模式声明未实现。 | [binding.dart](../lib/src/binding.dart) `bindingStatements()`；[values.dart](../test/fixtures/values.dart) `localBindings()` |
| §18.2 空及表达式语句 | 部分实现 | 可丢弃结果但保留有副作用或可能失败的操作；表达式集合仍有实现缺口。 | [frontend.dart](../lib/src/frontend.dart) `feLowerStatement()`；[ssa.dart](../lib/src/ssa.dart) effect；[values.dart](../test/fixtures/values.dart) `coalescingContexts()`；[behavior_test.dart](../test/behavior_test.dart) `failingValues` |
| §18.3 局部变量声明 | 部分实现 | 有绑定、类型转换和确定赋值；`final` 规则与 `late` 缺口见[变量追踪](variables.md)。 | [frontend.dart](../lib/src/frontend.dart) `feLowerVariable()`；[values.dart](../test/fixtures/values.dart) `localBindings()`、`flowContexts()` |
| §18.4 局部函数声明 | 部分实现 | 支持声明、词法捕获、自递归与函数值，按声明身份绑定；返回推断和捕获范围见[函数](functions.md)。 | [ast.dart](../lib/src/ast.dart)、[parser.dart](../lib/src/parser.dart)、[binding.dart](../lib/src/binding.dart)；[behavior_test.dart](../test/behavior_test.dart) 的 `localFunctions()`、`rejected` |
| §18.5 `if` | 部分实现 | 支持布尔检查、短路条件和两支流状态合并；支持 Dart 3 的 if-case、守卫和 then 绑定，范围见[模式](patterns.md)；异常流仍缺。 | [frontend.dart](../lib/src/frontend.dart) `feConditionJumps()`、`feIfConditionJumps()`；[values.dart](../test/fixtures/values.dart) `conditionCase()`、`flowBranches()`、`ifCaseValues()` |
| §18.6.1 `for` | 部分实现 | 支持声明或表达式初始化、条件、多条更新及跳转；声明变量的闭包绑定逐轮独立，更新前复制当前值；使用外层变量时继续共享绑定，见[词法捕获](functions.md#词法捕获)。 | [parser.dart](../lib/src/parser.dart) `parserFor()`；[frontend.dart](../lib/src/frontend.dart) `feLowerWhileFor()`；[behavior_test.dart](../test/behavior_test.dart) `program/main()`、`program/capturedFunctions()` |
| §18.6.2 `for-in` | 部分实现 | 当前按 List 长度和索引迭代，支持动态来源的 List 并逐项检查元素类型，iterable 只求值一次；每次迭代步先检查初始长度，长度变化在下次取元素或判定结束前失败，break 不再检查。元素替换及步间恢复原长度可继续；声明变量的捕获绑定逐轮独立，也可对已有可写标识符逐轮赋值；语句与集合 for-in 共用绑定和循环算法。没有一般 Iterable/Iterator 协议或可捕获的 ConcurrentModificationError。 | [frontend.dart](../lib/src/frontend.dart) `feLowerForIn()`；[runtime.dart](../lib/src/runtime.dart) `rtListModificationError()`；[behavior_test.dart](../test/behavior_test.dart) `program/sequence()`、`program/main()`、`failingValues`；[values.dart](../test/fixtures/values.dart) `collectionValues()`；[List API](https://api.dart.dev/stable/3.13.5/dart-core/List-class.html) 补充迭代失效规则 |
| §18.6.3 异步 `for-in` | 未实现 | 无 `await for`、Stream 订阅、暂停或取消语义。 | [parser.dart](../lib/src/parser.dart) `parseStatement()`；尚无验证入口 |
| §18.7 `while` | 部分实现 | 支持条件短路、break/continue 与循环写入后的提升撤销；完整流分析仍待扩展。 | [frontend.dart](../lib/src/frontend.dart) `feLoopFlow()`；[values.dart](../test/fixtures/values.dart) `conditionLoops()`、`flowBranches()` |
| §18.8 `do` | 部分实现 | 先执行循环体，continue 跳到条件，并保留条件求值顺序。 | [frontend.dart](../lib/src/frontend.dart) `feLowerDoWhile()`；[values.dart](../test/fixtures/values.dart) `conditionLoops()` |
| §18.9 switch | 部分实现 | 支持 int/String/bool、受支持常量 case、default 和空 case 合并；文件版本至少 3.0 时，true/false 两个 bool case 可使 switch 在确定赋值分析中穷尽，此前仍有未匹配路径。显式 default 不受该门槛影响。模式、守卫及一般穷尽性分析未实现。 | [frontend.dart](../lib/src/frontend.dart) `feSwitchConstant()`、`feLowerSwitch()`；[behavior_test.dart](../test/behavior_test.dart) `program/main()`、`version-imports.dart` 与旧版本拒绝用例；[values.dart](../test/fixtures/values.dart) `flowContexts()` |
| §18.9.1 case 完成及跳转 | 部分实现 | 支持空 case、分支退出及外层循环 continue；case 标签 continue 和完整非法落空诊断仍待核对。 | [parser.dart](../lib/src/parser.dart) `parserSwitch()`；[frontend.dart](../lib/src/frontend.dart) `feLowerSwitch()`；[behavior_test.dart](../test/behavior_test.dart) `program/main()`、`program/capturedFunctions()` |
| §18.10 `rethrow` | 未实现 | 无当前异常及堆栈追踪上下文。 | [ast.dart](../lib/src/ast.dart)；尚无验证入口 |
| §18.11 `try`、`on`、`catch`、`finally` | 未实现 | 无异常边、匹配处理器或 finally 展开；运行时错误直接终止不等于实现异常。 | [ast.dart](../lib/src/ast.dart)；[runtime.dart](../lib/src/runtime.dart) 错误终止函数；尚无验证入口 |
| §18.12 `return` | 部分实现 | 支持显式值、无值、构造返回及类型检查；生成器返回和完整不可正常完成分析未实现。 | [frontend.dart](../lib/src/frontend.dart) `feLowerStatement()`；[values.dart](../test/fixtures/values.dart) `flowExit()`、`valueContexts()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §18.13–18.15 标签、break、continue | 部分实现 | 有嵌套标签查找、块 break、循环 continue 及目标检查；尚未覆盖 switch case 标签。 | [frontend.dart](../lib/src/frontend.dart) `feLowerLabel()`、`feLowerLabeledJump()`；[behavior_test.dart](../test/behavior_test.dart) `program/main()` 的 `outer`、`finish` |
| §18.16–18.17 `yield`、`yield*` | 未实现 | 无生成器状态、惰性 Iterable 或 Stream 输出。 | [ast.dart](../lib/src/ast.dart)；[parser.dart](../lib/src/parser.dart) `parseStatement()`；尚无验证入口 |
| §18.18 `assert` | 未实现 | 无断言语句、启用模式或 AssertionError 语义。 | [ast.dart](../lib/src/ast.dart)；[parser.dart](../lib/src/parser.dart) `parseStatement()`；尚无验证入口 |

bool switch 的确定赋值穷尽性依据 [Dart 3 模式与穷尽性补充规范](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/feature-specification.md)及跨版本 SDK 行为；这不包含模式语法。
异常与生成器执行机制未实现，进程退出或普通 List 循环不提供对应语义。
