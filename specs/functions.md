# 函数：§9 Functions

按[固定草案源码](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)的 §9.1–§9.4 建立索引；条款目录见[官方草案 PDF](https://dart.dev/to/spec-draft)。
兼容验证基线为 Dart SDK 3.13.5；调用求值的关联条款为 §17.15，类成员另见[类追踪](classes.md)。

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §9 函数体 | 部分实现 | 支持同步块体和 `=>`；异步与生成器函数体未实现。 | [parser.dart](../lib/src/parser.dart) `parserFunction()`；[values.dart](../test/fixtures/values.dart) `integer()`、`argumentCalls()` |
| §9.1 顶层函数声明 | 部分实现 | 支持声明绑定、直接调用、递归和跨库引用；非泛型、仅必需位置参数的顶层函数可提取为值。泛型函数与捕获闭包未实现。 | [symbols.dart](../lib/src/symbols.dart)；[frontend.dart](../lib/src/frontend.dart) `feRegisterFunction()`；[behavior_test.dart](../test/behavior_test.dart) `program/fibonacci()` |
| 顶层访问器 | 部分实现 | 支持 getter/setter 配对、仅读和仅写属性；文件版本至少 3.9 时，读结果与写参数类型可独立；此前要求 getter 结果是 setter 参数的子类型，写入仍按 setter 参数检查，按拥有声明的库版本决定，导入方不重新配对。未注解时为 dynamic；setter 只能省略或显式 void 结果且有一个必需位置参数。静态类成员及完整库冲突规则尚缺。 | [symbols.dart](../lib/src/symbols.dart) `declareAccessor()`；[frontend.dart](../lib/src/frontend.dart) `feRegisterFunction()`、`feLoadDeclaration()`；[values.dart](../test/fixtures/values.dart) `topAccessorValues()`；[behavior_test.dart](../test/behavior_test.dart) `libraries`、`rejected`、`failingValues` |
| §9.1 局部函数声明 | 未实现 | 无局部函数 AST、闭包捕获或局部递归绑定。 | [ast.dart](../lib/src/ast.dart) 语句种类；[parser.dart](../lib/src/parser.dart) `parseStatement()`；尚无验证入口 |
| §9 返回值 | 部分实现 | 按声明结果类型检查显式 return 和箭头体，必要时执行动态检查；`void` 箭头体可保留实际负载，普通块体的 return 值受 void 上下文限制。完整返回类型推断、异常及异步相关规则尚缺。 | [frontend.dart](../lib/src/frontend.dart) `feLowerStatement()`、`parseSource()`；[values.dart](../test/fixtures/values.dart) `valueContexts()`、`staticReturn()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §9 非空返回类型的正常落空 | 部分实现 | 结合当前流分析，拒绝可达的非空返回类型函数末尾；接受所有路径返回或已知不正常完成的循环/调用。完整异常、闭包及异步控制流未实现。 | [frontend.dart](../lib/src/frontend.dart) `parseSource()`；[flow.dart](../lib/src/flow.dart) `FlowState.reachable`；[values.dart](../test/fixtures/values.dart) `completeReturn()`、`nonCompletingFor()`、`nonCompletingDo()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §9 隐式返回 null | 部分实现 | 可空、dynamic、void 同步块体正常落空产生 null；未把未知的零值当作非空返回。`Future` 和生成器的隐式返回规则未实现。 | [frontend.dart](../lib/src/frontend.dart) `parseSource()`；[values.dart](../test/fixtures/values.dart) `fallthroughInt()`、`fallthroughBool()`、`fallthroughDynamic()`、`fallthroughVoid()` |
| 空安全：`Never` 返回类型 | 部分实现 | 按声明结果使调用路径不正常完成，Never 返回类型不能正常落空；getter 的 Never 值也可在调用位置使用。同一规则用于源码诊断函数，函数体及调用方仍受当前表达式和类型子集限制，见[类型追踪](types.md)。 | [frontend.dart](../lib/src/frontend.dart) `feCall()`、`feLowerCall()`；[parser.dart](../lib/src/parser.dart) `parserError()`；[source.dart](../lib/src/source.dart) `sourceError()`；[values.dart](../test/fixtures/values.dart) `neverWrapper()`；[behavior_test.dart](../test/behavior_test.dart) `neverExpressions()`、`neverGetterCall()` |
| §9.2.1 必需位置参数 | 部分实现 | 检查数量、类型并绑定参数槽，形参可为已支持的函数类型；一般泛型签名尚缺。 | [arguments.dart](../lib/src/arguments.dart) `bindArguments()`；[frontend.dart](../lib/src/frontend.dart) `feLowerArguments()`；[values.dart](../test/fixtures/values.dart) `argumentCalls()` |
| §9.2.2 可选位置参数 | 部分实现 | 支持省略、显式 `null` 和常量默认值；默认值仅限当前常量求值子集。 | [parser.dart](../lib/src/parser.dart) `parserParameters()`；[values.dart](../test/fixtures/values.dart) `positionalArguments()`、`constantDefaults()` |
| §9.2.2 命名参数 | 部分实现 | 支持重排、必需命名参数及缺失、重复、未知参数诊断；命名实参之后再出现位置实参要求调用点文件版本至少 2.17，普通调用和常量构造调用都保留源码求值顺序。未实现完整函数子类型规则。 | [arguments.dart](../lib/src/arguments.dart) `bindArguments()`；[values.dart](../test/fixtures/values.dart) `namedArguments()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §9.2.2 默认值绑定 | 部分实现 | 默认值在声明库作用域求值，保留声明静态类型；支持规范化常量 List，拒绝可变引用；支持已实现构造子集的 const 类实例、顶层函数引用及嵌套值默认，仍不代表完整常量语言。 | [constants.dart](../lib/src/constants.dart) `evaluateConstant()`；[frontend.dart](../lib/src/frontend.dart) 参数默认值生成；[values.dart](../test/fixtures/values.dart) `positionalArguments()`、`coalescingDefaults()`、`constObjectDefault()`、`functionDefault()` |
| §9.2.2 隐式默认 `null` | 部分实现 | 可空或动态参数允许省略；非空参数缺默认值报错。 | [frontend.dart](../lib/src/frontend.dart) `feLowerArguments()`；[values.dart](../test/fixtures/values.dart) `nullableArguments()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §9.2 初始化形式参数 | 部分实现 | 未命名构造支持 `this.field`、命名默认值及显式子类型到字段表示转换；私有命名字段形式参数要求声明库版本至少 3.12，并以公开参数名调用，旧版本调用方不改变该声明规则。重定向和 super 参数未实现。 | [frontend.dart](../lib/src/frontend.dart) `feRegisterFunction()`；[arguments.dart](../lib/src/arguments.dart) `parameterName()`；[values.dart](../test/fixtures/values.dart) `Cell`、`argumentCalls()` |
| §9.2.3 `covariant` 参数 | 未实现 | 未记录此修饰符或建立 override 参数入口检查；List 协变写入检查不能代替它。 | [ast.dart](../lib/src/ast.dart) `AstParameter`；[parser.dart](../lib/src/parser.dart) `parserParameters()`；尚无验证入口 |
| [§9.3 函数类型与函数对象][signature] | 部分实现 | 支持嵌套、可空的非泛型必需位置参数签名，顶层函数引用按声明共享身份；可存入局部、参数、返回值、字段、List 与常量，通过具体签名调用或 `.call`。可选/命名函数值签名、泛型、方法/构造器提取、捕获及 dynamic/裸 Function 调用尚缺。 | [ast.dart](../lib/src/ast.dart) `AstFunctionType`；[frontend.dart](../lib/src/frontend.dart) `feFunctionReference()`、`feLowerFunctionCall()`；[values.dart](../test/fixtures/values.dart) `functionValues()`；[behavior_test.dart](../test/behavior_test.dart) `function-imports.dart`、`failingValues` |
| §9.4 外部函数 | 部分实现 | 仅受信运行时中的显式原语签名可连接；没有通用 external 链接或 `NoSuchMethodError` 路径。 | [frontend.dart](../lib/src/frontend.dart) `feRegisterFunction()`；[runtime.dart](../lib/src/runtime.dart) external 声明；[behavior_test.dart](../test/behavior_test.dart) `invalidRuntimes` |
| §9 异步与生成器 | 未实现 | 无 `async`、`sync*`、`async*` 函数表示、暂停点及调度实现。 | [ast.dart](../lib/src/ast.dart) `AstFunction`；[parser.dart](../lib/src/parser.dart) `parserFunction()`；尚无验证入口 |
| §17.15 参数求值及绑定 | 部分实现 | 直接调用保留实参源码顺序及形参重排；具体函数值先读取 callee 再求实参。实例字段/getter 的未加括号调用按 SDK 3.13.5 在实参之后读取值，与括号形式有别，见[表达式追踪](expressions.md)。 | [frontend.dart](../lib/src/frontend.dart) `feLowerArguments()`；[values.dart](../test/fixtures/values.dart) `argumentCalls()`、`functionValues()` 的 trace 与寄存器/栈参数 |
| §19.6 脚本入口的函数调用 | 部分实现 | 显式入口适配器传 CLI 参数、第二位置参数 `null` 并补其余默认值；不是一般函数对象启动模型。 | [frontend.dart](../lib/src/frontend.dart) `feGenerateEntry()`；[behavior_test.dart](../test/behavior_test.dart) `namedEntry`、`twoEntry`、`invalidEntry` |

实现边界：

- 已知声明的直接调用保留原参数绑定；函数值调用目前只消费具体的非泛型必需位置签名，不能把裸 `Function` 或 `dynamic` 当作已知签名。
- 已验证的常量默认值不能扩展解释为任意常量构造器或完整常量语言。
- 原语和 FFI 回调有独立签名边界；普通 Dart 函数对象不能隐式变成 FFI 指针，一般 external 连接仍缺。
- 非空落空与 Never 调用采用现有局部流分析；`late`、闭包、泛型函数、异常和异步路径仍有缺口。

版本门槛依据 [SDK 3.13.5 的特性表](https://github.com/dart-lang/sdk/blob/3.13.5/tools/experimental_features.yaml)；真实跨版本入口为 [behavior_test.dart](../test/behavior_test.dart) 的 `version-imports.dart`、`version-named.dart` 与拒绝用例。类与库级访问器都受声明版本约束；这不等同于完整旧版函数或继承规则。

后续验收应复用 `argumentCalls()` 的求值轨迹和既有拒绝用例，扩展闭包或泛型时再补对应行为。

[signature]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L2522-L2564
