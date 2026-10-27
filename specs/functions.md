# 函数：§9 Functions

按[固定草案源码](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)的 §9.1–§9.4 建立索引；条款目录见[官方草案 PDF](https://dart.dev/to/spec-draft)。
SDK 对照版本见[总览](README.md)；调用求值的关联条款为 §17.15，类成员另见[类追踪](classes.md)。

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §9 函数体 | 部分实现 | 支持同步块体和 `=>`；异步与生成器函数体未实现。 | [parser.dart](../lib/src/parser.dart) `parserFunction()`；[values.dart](../test/fixtures/values.dart) `integer()`、`argumentCalls()` |
| §9.1 顶层函数声明 | 部分实现 | 支持声明绑定、直接调用、递归和跨库引用；非泛型、仅必需位置参数的顶层函数可提取为值。泛型函数与捕获闭包未实现。 | [symbols.dart](../lib/src/symbols.dart)；[frontend.dart](../lib/src/frontend.dart) `feRegisterFunction()`；[behavior_test.dart](../test/behavior_test.dart) `program/fibonacci()` |
| 顶层访问器 | 部分实现 | 支持 getter/setter 配对、仅读和仅写属性；文件版本至少 3.9 时，读结果与写参数类型可独立；此前要求 getter 结果是 setter 参数的子类型，写入仍按 setter 参数检查，按拥有声明的库版本决定，导入方不重新配对。未注解时为 dynamic；setter 只能省略或显式 void 结果且有一个必需位置参数。静态类访问器见[类追踪](classes.md)；完整库冲突规则尚缺。 | [symbols.dart](../lib/src/symbols.dart) `declareAccessor()`；[frontend.dart](../lib/src/frontend.dart) `feRegisterFunction()`、`feLoadDeclaration()`；[values.dart](../test/fixtures/values.dart) `topAccessorValues()`；[behavior_test.dart](../test/behavior_test.dart) `libraries`、`rejected`、`failingValues` |
| [§9.1、§18.4 局部函数声明][local-declaration] | 部分实现 | 支持同步非泛型、无运行时捕获的局部声明和自递归；作用域、调用与捕获限制见[局部函数](#局部函数)。 | [ast.dart](../lib/src/ast.dart) `AstStatement.function`；[binding.dart](../lib/src/binding.dart) `bindingReference()`；[frontend.dart](../lib/src/frontend.dart) `feLowerLocalFunction()`；[behavior_test.dart](../test/behavior_test.dart) `program/localFunctions()`、`rejected` |
| [§17.14 匿名函数表达式][function-expressions]、[上下文推断][anonymous-inference] | 部分实现 | 支持同步非泛型、无运行时捕获的箭头体、块体和上下文推断；调用与推断范围见[匿名函数](#匿名函数)。 | [parser.dart](../lib/src/parser.dart) `parserFunctionExpression()`；[binding.dart](../lib/src/binding.dart) `bindExpressionFunctions()`；[frontend.dart](../lib/src/frontend.dart) `feLowerFunctionExpression()`；[behavior_test.dart](../test/behavior_test.dart) `program/anonymousFunctions()`、`rejected` |
| §9 返回值 | 部分实现 | 按声明结果检查 return 和箭头体并执行必要转换；void 箭头体可保留实际负载，块体仍限制 void 返回表达式。局部省略结果的推断见下行；泛型、异常与异步相关规则尚缺。 | [frontend.dart](../lib/src/frontend.dart) `feLowerStatement()`；[values.dart](../test/fixtures/values.dart) `valueContexts()`、`staticReturn()`；[behavior_test.dart](../test/behavior_test.dart) `program/localFunctions()`、`rejected` |
| [局部返回类型推断][local-inference] | 部分实现 | 按本函数的 return 类型和正常完成性推断；细则与递归边界见[局部返回类型推断](#局部返回类型推断)。[顶层省略结果仍为 dynamic][top-inference]。 | [frontend.dart](../lib/src/frontend.dart) `feInferLocalResult()`、`feBeginFunction()`；[behavior_test.dart](../test/behavior_test.dart) `program/localFunctions()` 的 List 推断、Null/Never、void 与返回上下文 |
| §9 非空返回类型的正常落空 | 部分实现 | 结合当前流分析，拒绝可达的非空返回类型函数末尾；接受所有路径返回或已知不正常完成的循环/调用。完整异常、捕获闭包及异步控制流未实现。 | [frontend.dart](../lib/src/frontend.dart) `parseSource()`；[flow.dart](../lib/src/flow.dart) `FlowState.reachable`；[values.dart](../test/fixtures/values.dart) `completeReturn()`、`nonCompletingFor()`、`nonCompletingDo()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §9 隐式返回 null | 部分实现 | 可空、dynamic、void 同步块体正常落空产生 null；未把未知的零值当作非空返回。`Future` 和生成器的隐式返回规则未实现。 | [frontend.dart](../lib/src/frontend.dart) `parseSource()`；[values.dart](../test/fixtures/values.dart) `fallthroughInt()`、`fallthroughBool()`、`fallthroughDynamic()`、`fallthroughVoid()` |
| 空安全：`Never` 返回类型 | 部分实现 | 按声明结果使调用路径不正常完成，Never 返回类型不能正常落空；getter 的 Never 值也可在调用位置使用。同一规则用于源码诊断函数，函数体及调用方仍受当前表达式和类型子集限制，见[类型追踪](types.md)。 | [frontend.dart](../lib/src/frontend.dart) `feCall()`、`feLowerCall()`；[parser.dart](../lib/src/parser.dart) `parserError()`；[source.dart](../lib/src/source.dart) `sourceError()`；[values.dart](../test/fixtures/values.dart) `neverWrapper()`；[behavior_test.dart](../test/behavior_test.dart) `neverExpressions()`、`neverGetterCall()` |
| §9.2.1 必需位置参数 | 部分实现 | 检查数量、类型并绑定参数槽，形参可为已支持的函数类型；一般泛型签名尚缺。 | [arguments.dart](../lib/src/frontend/arguments.dart) `bindArguments()`；[frontend.dart](../lib/src/frontend.dart) `feLowerArguments()`；[values.dart](../test/fixtures/values.dart) `argumentCalls()` |
| §9.2.2 可选位置参数 | 部分实现 | 支持省略、显式 `null` 和常量默认值；默认值仅限当前常量求值子集。 | [parser.dart](../lib/src/parser.dart) `parserParameters()`；[values.dart](../test/fixtures/values.dart) `positionalArguments()`、`constantDefaults()` |
| §9.2.2 命名参数 | 部分实现 | 支持重排、必需命名参数及缺失、重复、未知参数诊断；命名实参之后再出现位置实参要求调用点文件版本至少 2.17，普通调用和常量构造调用都保留源码求值顺序。未实现完整函数子类型规则。 | [arguments.dart](../lib/src/frontend/arguments.dart) `checkArgumentOrder()`、`bindArguments()`；[values.dart](../test/fixtures/values.dart) `namedArguments()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §9.2.2 默认值绑定 | 部分实现 | 库/成员默认值在声明库作用域求值；局部函数采用声明处词法常量作用域，可引用此前可见的 outer const，不能偷读调用方名字或普通外层变量。支持当前标量、常量 List、类实例与顶层函数引用子集，不代表完整常量语言。 | [constants.dart](../lib/src/constants.dart) `evaluateConstant()`；[frontend.dart](../lib/src/frontend.dart) `feResolveFunctionDefaults()`；[values.dart](../test/fixtures/values.dart) `positionalArguments()`、`constantDefaults()`；[behavior_test.dart](../test/behavior_test.dart) `program/localFunctions()` |
| §9.2.2 隐式默认 `null` | 部分实现 | 可空或动态参数允许省略；非空参数缺默认值报错。 | [frontend.dart](../lib/src/frontend.dart) `feLowerArguments()`；[values.dart](../test/fixtures/values.dart) `nullableArguments()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §9.2 初始化形式参数 | 部分实现 | 已实现的生成式构造支持 `this.field`、命名默认值及显式子类型到字段表示转换；[私有命名字段形式参数][private-named]要求声明库版本至少 3.12，去掉首个 `_` 后须为合法公共标识符，且声明名和公共名不得与其他形参冲突（含位置形参）。以公共名调用，旧版本调用方不改变声明规则；super 参数及主构造器未实现；生成式重定向不能带字段形式参数，见[构造器规则](classes.md)。 | [frontend.dart](../lib/src/frontend.dart) `feRegisterFunction()`、`feResolveFunctionDefaults()`；[parameters.dart](../lib/src/frontend/parameters.dart) `parameterName()`、`checkParameterName()`；[values.dart](../test/fixtures/values.dart) `Cell`、`argumentCalls()`；[behavior_test.dart](../test/behavior_test.dart) `version-private.dart`、`version-imports.dart`、`rejected` |
| §9.2.3 `covariant` 参数 | 未实现 | 未记录此修饰符或建立 override 参数入口检查；List 协变写入检查不能代替它。 | [ast.dart](../lib/src/ast.dart) `AstParameter`；[parser.dart](../lib/src/parser.dart) `parserParameters()`；尚无验证入口 |
| [§9.3 函数类型与函数对象][signature] | 部分实现 | 可执行文件支持非泛型必需位置签名的函数值及存储、传参、返回、typed List、调用/`.call`；常量、身份与输出限制见[函数值](#函数值)。 | [frontend.dart](../lib/src/frontend.dart) `feFunctionReference()`、`feLowerFunctionCall()`；[values.dart](../test/fixtures/values.dart) `functionValues()`；[behavior_test.dart](../test/behavior_test.dart) `program/localFactory()`、`program/localFunctions()`、`program/anonymousFunctions()`、`rejected` |
| §9.4 外部函数 | 部分实现 | 仅受信运行时中的显式原语签名可连接；没有通用 external 链接或 `NoSuchMethodError` 路径。 | [frontend.dart](../lib/src/frontend.dart) `feRegisterFunction()`；[runtime.dart](../lib/src/runtime.dart) external 声明；[behavior_test.dart](../test/behavior_test.dart) `invalidRuntimes` |
| §9 异步与生成器 | 未实现 | 无 `async`、`sync*`、`async*` 函数表示、暂停点及调度实现。 | [ast.dart](../lib/src/ast.dart) `AstFunction`；[parser.dart](../lib/src/parser.dart) `parserFunction()`；尚无验证入口 |
| §17.15 参数求值及绑定 | 部分实现 | 直接调用保留实参源码顺序及形参重排；函数值的读取时机按 callee 形式区分，实例与静态选择器的 SDK 求值顺序见[表达式追踪](expressions.md)。 | [frontend.dart](../lib/src/frontend.dart) `feLowerArguments()`；[values.dart](../test/fixtures/values.dart) `argumentCalls()`、`functionValues()`、`staticMembers()` 的 trace 与寄存器/栈参数 |
| §19.6 脚本入口的函数调用 | 部分实现 | 显式入口适配器传 CLI 参数、第二位置参数 `null` 并补其余默认值；不是一般函数对象启动模型。 | [frontend.dart](../lib/src/frontend.dart) `feGenerateEntry()`；[behavior_test.dart](../test/behavior_test.dart) `namedEntry`、`twoEntry`、`invalidEntry` |

## 局部函数

局部声明支持同步非泛型、无运行时捕获的函数、自递归、块内遮蔽和只读名字。直接调用复用必需、可选和命名参数绑定。

声明前引用不会回退到同名 global；互递归的前向引用被拒绝。捕获普通外层变量或显式/隐式 `this` 会报告未支持。

### 局部返回类型推断

省略结果类型时，箭头体和块体都通过 typed lowering 汇合本函数的所有 return 类型与末尾正常完成性：

- 死代码中的 return 也参与；子函数的 return 不参与。
- 无 return 且正常落空时推断为 Null，不正常完成时推断为 Never。
- 推得结果只控制最终转换，不反向改变返回字面量的实际类型。

局部递归推断以 dynamic 为初始结果类型，兼容 SDK 3.13.5；不消费递归结果时仍可推得更具体类型。固定推断 Draft 的空安全段落描述 inference failure，诊断与此不同。

## 匿名函数

匿名表达式支持同步非泛型、无运行时捕获的箭头体和块体。匿名节点没有声明名，复用独立函数体绑定；捕获、泛型、异步与生成器尚未实现。

省略的参数类型按期望签名推断，返回表达式使用期望结果上下文。上下文可来自变量、实参、返回、条件及全局/字段初始化；没有上下文时，参数类型为 dynamic。

字面量的直接调用及 `.call` 支持可选和命名参数。提取为一般函数值时，仍受下面的签名限制。

## 函数值

可执行文件产物支持将顶层函数、静态方法、无捕获局部函数和匿名函数作为值存储、传参、返回或放入 typed List，并通过具体的非泛型必需位置签名调用或 `.call`。目标文件、静态库和动态库产物不支持 Dart 函数值。可选/命名函数值、泛型、绑定实例方法/构造器提取、捕获及 dynamic/裸 `Function` 调用尚未实现。

顶层函数和静态方法引用可用于常量，局部声明引用与匿名表达式不因此成为 const。无捕获局部函数对象可按声明共享；跨调用的对象身份是实现选择，不能依赖 SDK 某次分配行为。重复读取同一作用域中的局部声明仍保持身份，依据[函数闭包化规则][closurization]。

## 实现边界

- 已知声明的直接调用保留原参数绑定；函数值调用目前只消费具体的非泛型必需位置签名，不能把裸 `Function` 或 `dynamic` 当作已知签名。
- 默认值仅接受[已支持的常量表达式](expressions.md)，不覆盖完整常量语言。
- 命名构造器的直接调用复用相同参数绑定；`.new` 是未命名构造器别名，不代表支持构造器函数值或 `(C.named)(...)`，见[类追踪](classes.md)。
- 原语和 FFI 回调有独立签名边界；普通 Dart 函数对象不能隐式变成 FFI 指针，一般 external 连接仍缺。
- 非空落空与 Never 调用采用现有局部流分析；`late`、捕获闭包、泛型函数、异常和异步路径仍有缺口。

版本门槛依据 [SDK 3.13.5 的特性表](https://github.com/dart-lang/sdk/blob/3.13.5/tools/experimental_features.yaml)；真实跨版本入口为 [behavior_test.dart](../test/behavior_test.dart) 的 `version-imports.dart`、`version-named.dart` 与拒绝用例。类与库级访问器都受声明版本约束；这不等同于完整旧版函数或继承规则。

[signature]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L2640-L2781

[local-declaration]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L18287-L18355
[local-inference]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md#L374-L386
[top-inference]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md#L147-L179

[closurization]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L13644-L13712
[function-expressions]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L11795-L11831
[anonymous-inference]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md#L263-L372
[private-named]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.12/private-named-parameters/feature-specification.md
