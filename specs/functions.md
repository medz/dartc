# 函数：§9 Functions

按[固定草案源码](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)的 §9.1–§9.4 建立索引；条款目录见[官方草案 PDF](https://dart.dev/to/spec-draft)。
兼容验证基线为 Dart SDK 3.13.5；调用求值的关联条款为 §17.15，类成员另见[类追踪](classes.md)。

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §9 函数体 | 部分实现 | 支持同步块体和 `=>`；异步与生成器函数体未实现。 | [parser.dart](../lib/src/parser.dart) `parserFunction()`；[values.dart](../test/fixtures/values.dart) `integer()`、`argumentCalls()` |
| §9.1 顶层函数声明 | 部分实现 | 支持声明绑定、直接调用、递归和跨库引用；函数对象及泛型函数未实现。 | [symbols.dart](../lib/src/symbols.dart)；[frontend.dart](../lib/src/frontend.dart) `feRegisterFunction()`；[behavior_test.dart](../test/behavior_test.dart) `program/fibonacci()` |
| 顶层访问器 | 部分实现 | 支持 getter/setter 配对、仅读和仅写属性；读结果与写参数类型独立，未注解时为 dynamic；setter 只能省略或显式 void 结果且有一个必需位置参数。静态类成员及完整库冲突规则尚缺。 | [symbols.dart](../lib/src/symbols.dart) `declareAccessor()`；[frontend.dart](../lib/src/frontend.dart) `feRegisterFunction()`、`feLoadDeclaration()`；[values.dart](../test/fixtures/values.dart) `topAccessorValues()`；[behavior_test.dart](../test/behavior_test.dart) `libraries`、`rejected`、`failingValues` |
| §9.1 局部函数声明 | 未实现 | 无局部函数 AST、闭包捕获或局部递归绑定。 | [ast.dart](../lib/src/ast.dart) 语句种类；[parser.dart](../lib/src/parser.dart) `parseStatement()`；尚无验证入口 |
| §9 返回值 | 部分实现 | 按声明结果类型检查显式 return 和箭头体，必要时执行动态检查；`void` 箭头体可保留实际负载，普通块体的 return 值受 void 上下文限制。函数类型、异常及异步相关规则尚缺。 | [frontend.dart](../lib/src/frontend.dart) `feLowerStatement()`、`parseSource()`；[values.dart](../test/fixtures/values.dart) `valueContexts()`、`staticReturn()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §9 非空返回类型的正常落空 | 部分实现 | 结合当前流分析，拒绝可达的非空返回类型函数末尾；接受所有路径返回或已知不正常完成的循环/调用。完整异常、闭包及异步控制流未实现。 | [frontend.dart](../lib/src/frontend.dart) `parseSource()`；[flow.dart](../lib/src/flow.dart) `FlowState.reachable`；[values.dart](../test/fixtures/values.dart) `completeReturn()`、`nonCompletingFor()`、`nonCompletingDo()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §9 隐式返回 null | 部分实现 | 可空、dynamic、void 同步块体正常落空产生 null；未把未知的零值当作非空返回。`Future` 和生成器的隐式返回规则未实现。 | [frontend.dart](../lib/src/frontend.dart) `parseSource()`；[values.dart](../test/fixtures/values.dart) `fallthroughInt()`、`fallthroughBool()`、`fallthroughDynamic()`、`fallthroughVoid()` |
| 空安全：`Never` 返回类型 | 部分实现 | 按声明结果使调用路径不正常完成，Never 返回类型不能正常落空；getter 的 Never 值也可在调用位置使用。同一规则用于源码诊断函数，函数体及调用方仍受当前表达式和类型子集限制，见[类型追踪](types.md)。 | [frontend.dart](../lib/src/frontend.dart) `feCall()`、`feLowerCall()`；[parser.dart](../lib/src/parser.dart) `parserError()`；[source.dart](../lib/src/source.dart) `sourceError()`；[values.dart](../test/fixtures/values.dart) `neverWrapper()`；[behavior_test.dart](../test/behavior_test.dart) `neverExpressions()`、`neverGetterCall()` |
| §9.2.1 必需位置参数 | 部分实现 | 检查数量、类型，绑定参数槽；不支持函数类型参数和一般泛型签名。 | [arguments.dart](../lib/src/arguments.dart) `bindArguments()`；[frontend.dart](../lib/src/frontend.dart) `feLowerArguments()`；[values.dart](../test/fixtures/values.dart) `argumentCalls()` |
| §9.2.2 可选位置参数 | 部分实现 | 支持省略、显式 `null` 和常量默认值；默认值仅限当前常量求值子集。 | [parser.dart](../lib/src/parser.dart) `parserParameters()`；[values.dart](../test/fixtures/values.dart) `positionalArguments()`、`constantDefaults()` |
| §9.2.2 命名参数 | 部分实现 | 支持重排、必需命名参数及缺失、重复、未知参数诊断；未实现完整函数子类型规则。 | [arguments.dart](../lib/src/arguments.dart) `bindArguments()`；[values.dart](../test/fixtures/values.dart) `namedArguments()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §9.2.2 默认值绑定 | 部分实现 | 默认值在声明库作用域求值，保留声明静态类型；支持规范化常量 List，拒绝可变引用；支持已实现构造子集的 const 类实例及嵌套值默认，仍不代表完整常量语言。 | [constants.dart](../lib/src/constants.dart) `evaluateConstant()`；[frontend.dart](../lib/src/frontend.dart) 参数默认值生成；[values.dart](../test/fixtures/values.dart) `positionalArguments()`、`coalescingDefaults()`、`constObjectDefault()` |
| §9.2.2 隐式默认 `null` | 部分实现 | 可空或动态参数允许省略；非空参数缺默认值报错。 | [frontend.dart](../lib/src/frontend.dart) `feLowerArguments()`；[values.dart](../test/fixtures/values.dart) `nullableArguments()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §9.2 初始化形式参数 | 部分实现 | 未命名构造支持 `this.field`、命名默认值及显式子类型到字段表示转换；重定向和 super 参数未实现。 | [frontend.dart](../lib/src/frontend.dart) `feRegisterFunction()`；[arguments.dart](../lib/src/arguments.dart) `parameterName()`；[values.dart](../test/fixtures/values.dart) `Cell`、`argumentCalls()` |
| §9.2.3 `covariant` 参数 | 未实现 | 未记录此修饰符或建立 override 参数入口检查；List 协变写入检查不能代替它。 | [ast.dart](../lib/src/ast.dart) `AstParameter`；[parser.dart](../lib/src/parser.dart) `parserParameters()`；尚无验证入口 |
| §9.3 函数类型与函数对象 | 未实现 | 普通函数不能作为值闭包化；现有 `typedef` 只服务受限原生回调签名。 | [ast.dart](../lib/src/ast.dart) `AstTypedef`；[frontend.dart](../lib/src/frontend.dart) `feCheckNativeInt64()`；[library_test.dart](../test/library_test.dart) 原生回调验证 |
| §9.4 外部函数 | 部分实现 | 仅受信运行时中的显式原语签名可连接；没有通用 external 链接或 `NoSuchMethodError` 路径。 | [frontend.dart](../lib/src/frontend.dart) `feRegisterFunction()`；[runtime.dart](../lib/src/runtime.dart) external 声明；[behavior_test.dart](../test/behavior_test.dart) `invalidRuntimes` |
| §9 异步与生成器 | 未实现 | 无 `async`、`sync*`、`async*` 函数表示、暂停点及调度实现。 | [ast.dart](../lib/src/ast.dart) `AstFunction`；[parser.dart](../lib/src/parser.dart) `parserFunction()`；尚无验证入口 |
| §17.15 参数求值及绑定 | 部分实现 | receiver 先求值，实参按源码顺序各求值一次，再按形参槽重排；动态函数对象调用未实现。 | [frontend.dart](../lib/src/frontend.dart) `feLowerArguments()`；[values.dart](../test/fixtures/values.dart) `argumentCalls()` 的 trace 与 13 个物理参数 |
| §19.6 脚本入口的函数调用 | 部分实现 | 显式入口适配器传 CLI 参数、第二位置参数 `null` 并补其余默认值；不是一般函数对象启动模型。 | [frontend.dart](../lib/src/frontend.dart) `feGenerateEntry()`；[behavior_test.dart](../test/behavior_test.dart) `namedEntry`、`twoEntry`、`invalidEntry` |

实现边界：

- 当前普通函数调用有显式目标和完整物理参数，不是基于 Function 对象的通用调用协议。
- 已验证的常量默认值不能扩展解释为任意常量构造器或完整常量语言。
- 原语和 FFI 回调有独立签名边界，不应借此宣称一般 external 或函数类型支持。
- 非空落空与 Never 调用采用现有局部流分析；`late`、闭包、泛型函数、异常和异步路径仍有缺口。

后续验收应复用 `argumentCalls()` 的求值轨迹和既有拒绝用例，扩展闭包或泛型时再补对应行为。
