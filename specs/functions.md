# 函数：§9 Functions

按[固定草案源码](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)的 §9.1–§9.4 建立索引；条款目录见[官方草案 PDF](https://dart.dev/to/spec-draft)。
SDK 对照版本见[总览](README.md)；调用求值的关联条款为 §17.15，类成员另见[类追踪](classes.md)。

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §9 函数体 | 部分实现 | 支持同步块体和 `=>`；异步与生成器函数体未实现。 | [parser.dart](../lib/src/parser.dart) `parserFunction()`；[values.dart](../test/fixtures/values.dart) `integer()`、`argumentCalls()` |
| §9.1 顶层函数声明 | 部分实现 | 支持声明绑定、直接调用、递归和跨库引用；非泛型、仅必需位置参数的顶层函数可提取为值。泛型直接调用的支持范围见下文。 | [symbols.dart](../lib/src/symbols.dart)；[frontend.dart](../lib/src/frontend.dart) `feRegisterFunction()`；[behavior_test.dart](../test/behavior_test.dart) `program/fibonacci()` |
| 顶层访问器 | 部分实现 | 支持 getter/setter 配对、仅读和仅写属性；文件版本至少 3.9 时，读结果与写参数类型可独立；此前要求 getter 结果是 setter 参数的子类型，写入仍按 setter 参数检查，按拥有声明的库版本决定，导入方不重新配对。未注解时为 dynamic；setter 只能省略或显式 void 结果且有一个必需位置参数。静态类访问器见[类追踪](classes.md)；完整库冲突规则尚缺。 | [symbols.dart](../lib/src/symbols.dart) `declareAccessor()`；[frontend.dart](../lib/src/frontend.dart) `feRegisterFunction()`、`feLoadDeclaration()`；[values.dart](../test/fixtures/values.dart) `topAccessorValues()`；[behavior_test.dart](../test/behavior_test.dart) `libraries`、`rejected`、`failingValues` |
| [§9.1、§18.4 局部函数声明][local-declaration] | 部分实现 | 支持同步非泛型局部声明、词法捕获和自递归；作用域、调用与捕获限制见[局部函数](#局部函数)。 | [ast.dart](../lib/src/ast.dart) `AstStatement.function`；[binding.dart](../lib/src/binding.dart) `bindingReference()`；[frontend.dart](../lib/src/frontend.dart) `feLowerLocalFunction()`；[behavior_test.dart](../test/behavior_test.dart) `program/localFunctions()`、`rejected` |
| [§17.14 匿名函数表达式][function-expressions]、[上下文推断][anonymous-inference] | 部分实现 | 支持同步非泛型箭头体、块体、词法捕获和上下文推断；调用与推断范围见[匿名函数](#匿名函数)。 | [parser.dart](../lib/src/parser.dart) `parserFunctionExpression()`；[binding.dart](../lib/src/binding.dart) `bindExpressionLocals()`；[frontend.dart](../lib/src/frontend.dart) `feLowerFunctionExpression()`；[behavior_test.dart](../test/behavior_test.dart) `program/anonymousFunctions()`、`rejected` |
| §9 返回值 | 部分实现 | 按声明结果检查 return 和箭头体并执行必要转换；void 箭头体可保留实际负载，块体仍限制 void 返回表达式。局部省略结果的推断见下行；类型参数按声明身份检查返回，异常与异步相关规则尚缺。 | [frontend.dart](../lib/src/frontend.dart) `feLowerStatement()`；[values.dart](../test/fixtures/values.dart) `valueContexts()`、`staticReturn()`；[behavior_test.dart](../test/behavior_test.dart) `program/localFunctions()`、`rejected` |
| [局部返回类型推断][local-inference] | 部分实现 | 按本函数的 return 类型和正常完成性推断；细则与递归边界见[局部返回类型推断](#局部返回类型推断)。[顶层省略结果仍为 dynamic][top-inference]。 | [frontend.dart](../lib/src/frontend.dart) `feInferLocalResult()`、`feBeginFunction()`；[behavior_test.dart](../test/behavior_test.dart) `program/localFunctions()` 的 List 推断、Null/Never、void 与返回上下文 |
| §9 非空返回类型的正常落空 | 部分实现 | 结合当前流分析，拒绝可达的非空返回类型函数末尾；接受所有路径返回或已知不正常完成的循环/调用。完整异常及异步控制流未实现。 | [frontend.dart](../lib/src/frontend.dart) `parseSource()`；[flow.dart](../lib/src/flow.dart) `FlowState.reachable`；[values.dart](../test/fixtures/values.dart) `completeReturn()`、`nonCompletingFor()`、`nonCompletingDo()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §9 隐式返回 null | 部分实现 | 可空、dynamic、void 同步块体正常落空产生 null；未把未知的零值当作非空返回。`Future` 和生成器的隐式返回规则未实现。 | [frontend.dart](../lib/src/frontend.dart) `parseSource()`；[values.dart](../test/fixtures/values.dart) `fallthroughInt()`、`fallthroughBool()`、`fallthroughDynamic()`、`fallthroughVoid()` |
| 空安全：`Never` 返回类型 | 部分实现 | 按声明结果使调用路径不正常完成，Never 返回类型不能正常落空；getter 的 Never 值也可在调用位置使用。同一规则用于源码诊断函数，函数体及调用方仍受当前表达式和类型子集限制，见[类型追踪](types.md)。 | [frontend.dart](../lib/src/frontend.dart) `feCall()`、`feLowerCall()`；[parser.dart](../lib/src/parser.dart) `parserError()`；[source.dart](../lib/src/source.dart) `sourceError()`；[values.dart](../test/fixtures/values.dart) `neverWrapper()`；[behavior_test.dart](../test/behavior_test.dart) `neverExpressions()`、`neverGetterCall()` |
| §9.2.1 必需位置参数 | 部分实现 | 检查数量、类型并绑定参数槽，形参可为已支持的函数类型；泛型直接调用保留参数类型并在调用点代入；泛型函数类型仍缺。 | [arguments.dart](../lib/src/frontend/arguments.dart) `bindArguments()`；[frontend.dart](../lib/src/frontend.dart) `feLowerArguments()`；[values.dart](../test/fixtures/values.dart) `argumentCalls()` |
| §9.2.2 可选位置参数 | 部分实现 | 支持省略、显式 `null` 和常量默认值；默认值仅限当前常量求值子集。 | [parser.dart](../lib/src/parser.dart) `parserParameters()`；[values.dart](../test/fixtures/values.dart) `positionalArguments()`、`constantDefaults()` |
| §9.2.2 命名参数 | 部分实现 | 支持重排、必需命名参数及缺失、重复、未知参数诊断；命名实参之后再出现位置实参要求调用点文件版本至少 2.17，普通调用和常量构造调用都保留源码求值顺序。未实现完整函数子类型规则。 | [arguments.dart](../lib/src/frontend/arguments.dart) `checkArgumentOrder()`、`bindArguments()`；[values.dart](../test/fixtures/values.dart) `namedArguments()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §9.2.2 默认值绑定 | 部分实现 | 库/成员默认值在声明库作用域求值；局部函数采用声明处词法常量作用域，可引用此前可见的 outer const，不能偷读调用方名字或普通外层变量。支持当前标量、常量 List、类实例与顶层函数引用子集，不代表完整常量语言。 | [constants.dart](../lib/src/constants.dart) `evaluateConstant()`；[frontend.dart](../lib/src/frontend.dart) `feResolveFunctionDefaults()`；[values.dart](../test/fixtures/values.dart) `positionalArguments()`、`constantDefaults()`；[behavior_test.dart](../test/behavior_test.dart) `program/localFunctions()` |
| §9.2.2 隐式默认 `null` | 部分实现 | 可空或动态参数允许省略；非空参数缺默认值报错。 | [frontend.dart](../lib/src/frontend.dart) `feLowerArguments()`；[values.dart](../test/fixtures/values.dart) `nullableArguments()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §9.2 初始化形式参数 | 部分实现 | 已实现的生成式构造支持 `this.field`、命名默认值及显式子类型到字段表示转换；[私有命名字段形式参数][private-named]要求声明库版本至少 3.12，去掉首个 `_` 后须为合法公共标识符，且声明名和公共名不得与其他形参冲突（含位置形参）。以公共名调用，旧版本调用方不改变声明规则；super 参数及主构造器未实现；生成式重定向不能带字段形式参数，见[构造器规则](classes.md)。 | [frontend.dart](../lib/src/frontend.dart) `feRegisterFunction()`、`feResolveFunctionDefaults()`；[parameters.dart](../lib/src/frontend/parameters.dart) `parameterName()`、`checkParameterName()`；[values.dart](../test/fixtures/values.dart) `Cell`、`argumentCalls()`；[behavior_test.dart](../test/behavior_test.dart) `version-private.dart`、`version-imports.dart`、`rejected` |
| §9.2.3 `covariant` 参数 | 未实现 | 未记录此修饰符或建立 override 参数入口检查；List 协变写入检查不能代替它。 | [ast.dart](../lib/src/ast.dart) `AstParameter`；[parser.dart](../lib/src/parser.dart) `parserParameters()`；尚无验证入口 |
| [§9.3 函数类型与函数对象][signature] | 部分实现 | 可执行文件支持非泛型必需位置签名的函数值及存储、传参、返回、typed List、调用/`.call`；常量、身份与输出限制见[函数值](#函数值)。 | [frontend.dart](../lib/src/frontend.dart) `feFunctionReference()`、`feLowerValueCall()`；[values.dart](../test/fixtures/values.dart) `functionValues()`；[behavior_test.dart](../test/behavior_test.dart) `program/localFactory()`、`program/localFunctions()`、`program/anonymousFunctions()`、`rejected` |
| §9.4 外部函数 | 部分实现 | 仅受信运行时中的显式原语签名可连接；没有通用 external 链接或 `NoSuchMethodError` 路径。 | [frontend.dart](../lib/src/frontend.dart) `feRegisterFunction()`；[runtime.dart](../lib/src/runtime.dart) external 声明；[behavior_test.dart](../test/behavior_test.dart) `invalidRuntimes` |
| §9 异步与生成器 | 未实现 | 无 `async`、`sync*`、`async*` 函数表示、暂停点及调度实现。 | [ast.dart](../lib/src/ast.dart) `AstFunction`；[parser.dart](../lib/src/parser.dart) `parserFunction()`；尚无验证入口 |
| §17.15 参数求值及绑定 | 部分实现 | 直接调用保留实参源码顺序及形参重排；函数值的读取时机按 callee 形式区分，实例与静态选择器的 SDK 求值顺序见[表达式追踪](expressions.md)。 | [frontend.dart](../lib/src/frontend.dart) `feLowerArguments()`；[values.dart](../test/fixtures/values.dart) `argumentCalls()`、`functionValues()`、`staticMembers()` 的 trace 与寄存器/栈参数 |
| §19.6 脚本入口的函数调用 | 部分实现 | 显式入口适配器传 CLI 参数、第二位置参数 `null` 并补其余默认值；不是一般函数对象启动模型。 | [frontend.dart](../lib/src/frontend.dart) `feGenerateEntry()`；[behavior_test.dart](../test/behavior_test.dart) `namedEntry`、`twoEntry`、`invalidEntry` |

## 泛型直接调用

[§9 类型参数作用域][generic-scope]和[§17.15 调用][generic-call]部分实现。顶层函数、静态及实例方法（包括 `call`）可声明类型参数、显式上界和必需/可选/命名值参数。参数按声明身份绑定，默认值在声明作用域检查；未使用函数也检查边界、函数体、返回和确定赋值。类型参数可用于 List、可空类型、非泛型函数签名、`is`/`as` 和已支持的模式。类型参数不能用于常量类型实参，构造器和访问器不能声明自身类型参数。

显式调用检查实参数量和代入后的上界。省略类型实参时，支持已有类型模型中的上下文、普通实参及带类型回调约束；返回上下文与参数上下文保持独立，例如 `print` 的 `Object?` 参数参与向下推断。没有约束时采用实例化到界。实参求值、必要检查和命名重排保持源码顺序；调用成员 getter 的时序遵守已有调用规则。

泛型局部/匿名函数、泛型函数值及 tear-off、泛型函数类型、泛型体内的局部函数/闭包、未确定回调参数的水平推断、动态复合实参的向上推断、完整基于上界的推断和 `T & S` 交叉类型提升仍缺。泛型 `main` 当前仅支持无值参数、默认类型实参满足边界的声明。类型参数作为公开 `Type` 值尚未实现。这些限制是实现缺口，不改变语言兼容目标。

实现入口为 [resolve_type.dart](../lib/src/resolve_type.dart) 的 `resolveFunctionTypeParameters`、[generics.dart](../lib/src/frontend/generics.dart) 的约束收集及求解、[frontend.dart](../lib/src/frontend.dart) 的 `fePrepareGenericArguments`。行为入口为 [values.dart](../test/fixtures/values.dart) 的 `genericFunctions`、[behavior_test.dart](../test/behavior_test.dart) 的 `generic-functions-imports.dart`、`generic-entry.dart`、`rejected` 与 `failingValues`。推断依据[类型推断规则][generic-inference]，运行时类型图的存活检查由 [roots.dart](../test/fixtures/roots.dart) 的 `genericTypeRoots` 拥有。

## 局部函数

局部声明支持同步非泛型函数、自递归、块内遮蔽和只读名字。无捕获的直接调用复用必需、可选和命名参数绑定；捕获函数目前限必需位置参数。

声明前引用不会回退到同名 global；互递归的前向引用被拒绝。支持捕获普通外层变量及显式/隐式 `this`；构造初始化器中的闭包可以捕获参数，但不能借闭包读取尚不可用的实例。

### 局部返回类型推断

省略结果类型时，箭头体和块体都通过 typed lowering 汇合本函数的所有 return 类型与末尾正常完成性：

- 死代码中的 return 也参与；子函数的 return 不参与。
- 无 return 且正常落空时推断为 Null，不正常完成时推断为 Never。
- 推得结果只控制最终转换，不反向改变返回字面量的实际类型。

局部递归推断以 dynamic 为初始结果类型，兼容 SDK 3.13.5；不消费递归结果时仍可推得更具体类型。固定推断 Draft 的空安全段落描述 inference failure，诊断与此不同。

## 匿名函数

匿名表达式支持同步非泛型箭头体和块体，以及必需位置参数签名的捕获。匿名节点没有声明名，复用独立函数体绑定；泛型、异步与生成器尚未实现。

省略的参数类型按期望签名推断，返回表达式使用期望结果上下文。上下文可来自变量、实参、返回、条件及全局/字段初始化；没有上下文时，参数类型为 dynamic。

无捕获字面量的直接调用及 `.call` 支持可选和命名参数。提取为一般函数值时，仍受下面的签名限制。

## 词法捕获

[函数闭包化规则][closurization]与[匿名函数规则][function-expressions]在当前同步、非泛型、必需位置参数范围内支持：外层绑定的持续读写、多个闭包共享变量、嵌套捕获、自递归与函数值调用。同一作用域中的局部函数重复读取保持身份；不同工厂调用保留各自的绑定。

`for (var i = …)` 的闭包保留每轮绑定，更新表达式作用于下一轮绑定；`for-in` 的声明变量同样逐轮独立。循环使用外部已有变量时继续共享它。按声明点检查捕获的确定赋值事实；子函数中的写入不使父函数的变量自动成为已赋值。捕获的 final 不能在子函数中赋值。被闭包写入的绑定不参与类型提升；没有显式写入的绑定可以在闭包中保留外围提升。更完整的流规则仍按[类型追踪](types.md)补齐。

行为入口为 [behavior_test.dart](../test/behavior_test.dart) 的 `capturedFunctions()` 及捕获拒绝用例；[roots.dart](../test/fixtures/roots.dart) 的 `closureRoots()` 验证逃逸闭包、共享绑定和捕获引用的枚举。可选/命名参数捕获、泛型捕获和异步捕获仍有实现缺口。

## 函数值

可执行文件产物支持将顶层函数、静态方法、绑定实例方法、局部函数和匿名函数作为值存储、传参、返回或放入 typed List，并通过具体的非泛型必需位置签名调用或 `.call`。目标文件、静态库和动态库产物不支持 Dart 函数值。可选/命名函数值、泛型函数值、构造器提取及 dynamic/裸 `Function` 调用尚未实现。

[实例方法闭包化][instance-closurization]支持已绑定类声明的非泛型必需位置方法，包括显式/隐式 this、嵌套闭包内提取、跨库可见性及空短路接收者。接收者只求值一次，方法值持续持有该对象；相同对象的同一方法比较相等，不同对象或方法不相等。普通闭包仍按自身身份比较；不规定重复方法提取的 `identical` 结果。实例方法引用不是常量，未使用函数和未执行常量分支也须检查这一义务。仍以 builtin 分支实现的方法提取、继承/super 分派以及 Function.hashCode 等继承 API 仍缺。验证入口为 [values.dart](../test/fixtures/values.dart) 的 `functionValues`、[behavior_test.dart](../test/behavior_test.dart) 的 `function-imports.dart`、拒例与失败用例，以及 [roots.dart](../test/fixtures/roots.dart) 的 `closureRoots`。

顶层函数和静态方法引用可用于常量，局部声明引用与匿名表达式不因此成为 const。无捕获局部函数对象可按声明共享；跨调用的对象身份是实现选择，不能依赖 SDK 某次分配行为。重复读取同一作用域中的局部声明仍保持身份，依据[函数闭包化规则][closurization]。

## 可调用对象

依据[函数表达式调用][callable-invocation]与[隐式转换][callable-coercion]，已知非空类声明中的实例 `call` 方法支持 `object(...)`，直接调用复用必需、可选和命名参数绑定。字段、getter 和静态成员名为 `call` 时，不会使所属实例可直接调用；继承和 extension 提供的调用仍缺。

在赋值、传参、返回、列表单元素和 `for-in` 变量的函数类型上下文中，非空对象可隐式提取 `call`。支持具体必需位置签名、`Function` 及其可空形式；转换结果沿用绑定方法的接收者存活和相等性。`Object`、`dynamic` 和无上下文推断保留原对象；对象本身不是 `Function`，显式 `as` 和来自 dynamic 的检查转换不提取方法。

条件、`??`、级联和空断言先确定整个表达式的类型，再做隐式提取；可空对象不能借可空函数目标自动提取。集合 spread 不逐元素插入该转换。实例字段/getter 的直接调用保持先求值实参、再读取成员的顺序；括号包住成员时先读取。函数值的可选/命名、泛型签名和 dynamic 调用仍受前述缺口限制。

SDK 3.13.7 CFE 允许未选中常量集合分支及构造实参中的隐式提取，并检查签名兼容；实际执行提取时报告常量错误。它也允许 const 构造器声明中的对应隐式转换在普通实例创建时执行。analyzer 分别报告 `non_constant_list_element`、`const_with_non_constant_argument`、`invalid_constant`；dartc 采用 CFE 行为，测试逐行注明诊断忽略。显式实例方法引用仍不是常量表达式，即使位于未选中的分支。

行为入口为 [values.dart](../test/fixtures/values.dart) 的 `functionValues()`、[behavior_test.dart](../test/behavior_test.dart) 的 `function-imports.dart`、`nogc-values.dart`、`rejected` 与 `failingValues`；[roots.dart](../test/fixtures/roots.dart) 的 `closureRoots()` 检查隐式提取后接收者的根枚举。

## 实现边界

- 已知声明的直接调用保留原参数绑定；函数值调用目前只消费具体的非泛型必需位置签名，不能把裸 `Function` 或 `dynamic` 当作已知签名。
- 默认值仅接受[已支持的常量表达式](expressions.md)，不覆盖完整常量语言。
- 命名构造器的直接调用复用相同参数绑定；`.new` 是未命名构造器别名，不代表支持构造器函数值或 `(C.named)(...)`，见[类追踪](classes.md)。
- 原语和 FFI 回调有独立签名边界；普通 Dart 函数对象不能隐式变成 FFI 指针，一般 external 连接仍缺。
- 非空落空与 Never 调用采用现有局部流分析；`late`、捕获闭包、泛型交叉类型、异常和异步路径仍有缺口。

版本门槛依据 [SDK 3.13.5 的特性表](https://github.com/dart-lang/sdk/blob/3.13.5/tools/experimental_features.yaml)；真实跨版本入口为 [behavior_test.dart](../test/behavior_test.dart) 的 `version-imports.dart`、`version-named.dart` 与拒绝用例。类与库级访问器都受声明版本约束；这不等同于完整旧版函数或继承规则。

[signature]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L2640-L2781

[local-declaration]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L18287-L18355
[local-inference]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md#L374-L386
[top-inference]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md#L147-L179

[closurization]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L13644-L13712
[function-expressions]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L11795-L11831
[anonymous-inference]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md#L263-L372
[private-named]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.12/private-named-parameters/feature-specification.md

[instance-closurization]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L14032-L14148

[callable-invocation]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L12456-L12561
[callable-coercion]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md#L1051-L1082

[generic-scope]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L2115-L2170
[generic-call]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L11716-L12120
[generic-inference]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md
