# 函数：§9 Functions

按[固定草案源码](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)的 §9.1–§9.4 建立索引；条款目录见[官方草案 PDF](https://dart.dev/to/spec-draft)。
SDK 对照版本见[总览](README.md)；调用求值的关联条款为 §17.15，类成员另见[类追踪](classes.md)。

## 函数语法表示

`package:dartc/ast.dart` 可构造以下函数语法。构造器检查源码范围、快照归属及子节点顺序，不解析文本或执行语义检查。

| 语言条款 | 可表示的语法 | 验证 |
| --- | --- | --- |
| §9.2 形参 | 必需与可选位置参数、必需与可选命名参数、元数据、`covariant`、写出的类型、名字和默认表达式；保留 `this.` / `super.` 前缀、函数形式参数的类型参数、嵌套形参与 `?` | [parameters_test.dart](../test/ast/parameters_test.dart) |
| §9 函数体、§17.14 函数表达式 | 匿名函数的类型参数与形参；同步块、`async` / `sync*` / `async*` 块、可选 `async` 的箭头体及声明的分号体；区分箭头表达式与声明结尾的分号范围 | [functions_test.dart](../test/ast/functions_test.dart) |
| §9.1、§18.4 局部函数声明 | 元数据、可省略返回类型、名字、类型参数、形参和函数体 | [functions_test.dart](../test/ast/functions_test.dart) |
| §9.1 顶层函数声明与顶层访问器 | 函数、getter、setter 的元数据、`external`、可省略返回类型、名字和函数体；函数保留类型参数与形参，setter 保留形参，getter 不添加形参列表 | [declarations_test.dart](../test/ast/declarations_test.dart) |

形参节点也保留 `var` / `final` / `const` 修饰符及旧式默认值分隔符 `:`，供后续版本和上下文检查；可构造节点不表示这些写法在任意语言版本或声明位置合法。类成员声明的语法表示见[类与成员](classes.md#类与成员语法表示)。AST 节点不检查作用域、参数绑定、默认值常量资格、闭包捕获、返回或生成类型；文本解析支持见下文，编译与执行支持以下表为准。

## 形参解析 API

`package:dartc/parser.dart` 的 `parseFormalParameterList(ScanResult)` 解析包含圆括号的声明形参列表，返回 `ParseResult<FormalParameterList>`。调用方通过 `hasErrors` 检查词法和语法诊断；类型、默认值及接收者前缀保留写出的形式，不补造省略的类型或默认值。

| 语言条款 | 当前解析支持 | 验证 |
| --- | --- | --- |
| §9.2 必需与可选形参 | 必需位置、可选位置、必需与可选命名参数、尾逗号；检查可选组边界和修饰符顺序 | [parameters_test.dart](../test/parser/parameters_test.dart) 分组与修饰符用例 |
| §9.2 类型、名字与函数形式参数 | 可省略类型、命名／函数／record 类型、`covariant`、`this.` / `super.` 前缀；函数形式参数保留类型参数、上界、嵌套形参和 `?` | [parameters_test.dart](../test/parser/parameters_test.dart) 类型与函数形式参数用例 |
| §9.2 默认值 | 可选参数的 `=`、命名参数的旧式 `:`；拒绝必需位置参数的默认值、位置参数的 `:` 和嵌套函数形式参数中的默认值；表达式范围同[表达式解析](expressions.md#表达式解析-api)，尚未检查常量资格 | [parameters_test.dart](../test/parser/parameters_test.dart) 默认值用例 |
| §16 形参元数据 | 常量名称引用、限定名称、类型实参、构造器名称及实参；遵循[注解实参的相邻规则](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/records/feature-specification.md#ambiguity-with-metadata-annotations)，与后续 record 类型区分 | [parameters_test.dart](../test/parser/parameters_test.dart) 元数据用例 |

在形参列表中，`int Function(int value)` 表示名为 `Function` 的函数形式形参；`int Function(int value) callback` 表示具有函数类型的普通形参。泛型、可空尾缀和嵌套函数形式均保留对应结构，验证见 [parameters_test.dart](../test/parser/parameters_test.dart)。

此入口不接收外围声明，因此保留 `var` / `final` 等声明信息，但尚未检查它们及 `covariant`、`this.`、`super.` 在具体函数、方法或构造器位置是否合法。重复参数、字段绑定、类型与默认值的语义检查也未接入。 整文件入口检查顶层、局部函数和静态成员中的 `covariant` 参数，以及普通构造器中的字段声明修饰符；主构造器仍可使用 `final` / `var` 声明字段。验证见 [contexts_test.dart](../test/parser/contexts_test.dart)。类型内部的元数据已接入；文档注释留在扫描结果中。解析不修改输入 token，损坏输入和深层嵌套验证见 [parameters_test.dart](../test/parser/parameters_test.dart)。

## 函数体解析 API

`parseFunctionBody(ScanResult)` 解析声明形式的函数体，返回 `ParseResult<FunctionBody>`。输入包含写出的修饰符和函数体，不含函数名或形参；箭头体和空体包含末尾分号。

| 语言条款 | 当前解析支持 | 验证 |
| --- | --- | --- |
| §9 函数体 | 同步块、`async` 块、`sync*` / `async*` 生成器块、同步或 `async` 箭头体、分号空体；缺失函数体使用零宽 `MissingFunctionBody` | [function_bodies_test.dart](../test/parser/function_bodies_test.dart) 函数体和恢复用例 |
| §17.34 Await | 在异步体中解析 `await` 及一元操作数，保持调用、条件、级联和类型运算的结合关系；同步生成器中的 `await` 产生诊断 | [function_bodies_test.dart](../test/parser/function_bodies_test.dart) await 和条件消歧用例 |
| §18.6.3、§18.16–18.17 | 异步体中的语句与集合 `await for`、生成器中的 `yield` / `yield*`；拒绝普通 `for` 头前的 `await`、非生成器的 yield、生成器的带值 return 和箭头体 | [function_bodies_test.dart](../test/parser/function_bodies_test.dart) 循环与生成器用例 |
| §17.38 标识符引用 | 同步体保留 `await` / `yield` 标识符；异步或生成器体检查值名称、声明名称、成员与实参名称中的关键字使用；类型名称保持未绑定形式 | [function_bodies_test.dart](../test/parser/function_bodies_test.dart) 名称用例 |

函数体内部沿用已支持的表达式和语句语法。同步语句直接以 `await:` 起始时，当前按 SDK 3.13.7 报告诊断；已有标签后的 `await:` 可解析。模式及 switch 已接入；未绑定捕获、跳转目标或检查返回与生成类型。此入口不检查外围声明能否省略实现，也不把解析成功当作函数可执行的证明。损坏输入、深层 await 和块嵌套验证见 [function_bodies_test.dart](../test/parser/function_bodies_test.dart)。

## 函数表达式与局部声明解析

`parseExpression` 接受匿名函数，`parseStatement` 接受局部函数声明；这两种函数也可嵌套在函数体、实参、默认值和元数据中。

| 语言条款 | 当前解析支持 | 验证 |
| --- | --- | --- |
| §17.14 匿名函数 | 可选类型参数与上界、形参、同步及异步箭头体、同步及生成器块体；保留表达式范围，不吞入外围分号 | [functions_test.dart](../test/parser/functions_test.dart) 闭包与表达式边界用例 |
| §9.1、§18.4 局部函数 | 元数据、可省略返回类型、名字、类型参数与形参；箭头声明包含末尾分号 | [functions_test.dart](../test/parser/functions_test.dart) 局部声明与类型消歧用例 |
| §9 函数上下文 | 嵌套函数体独立设置 async/generator 上下文；参数元数据及默认值沿用外层上下文；拒绝函数参数的 `var` / `final` / `const` | [functions_test.dart](../test/parser/functions_test.dart) 上下文与非法语法用例 |

捕获、参数绑定、默认值常量资格、返回类型和生成类型由后续分析检查；解析成功不代表函数可执行。深层嵌套及损坏输入的源码范围验证见 [functions_test.dart](../test/parser/functions_test.dart)。

## 顶层声明解析

`parseCompilationUnit` 解析顶层函数、getter、setter、变量及两种 typedef。函数保留元数据、external、返回类型、类型参数、形参和函数体；检查非 external 顶层函数缺少实现以及 external 函数包含实现的写法。变量保留 late、var/final/const、共享类型及各个初始化表达式。

`import`、`export`、`library`、`part`、`typedef`、`extension`、`mixin` 和 `external` 也可作为函数名，包括泛型函数；它们与同名指令、修饰符和声明按上下文区分。验证见 [compilation_units_test.dart](../test/parser/compilation_units_test.dart)。名称绑定、类型、常量资格和初始化行为仍需分析与执行阶段实现；程序体语法见本页的函数体解析范围。

## 编译与执行

| 规范条目 | 状态 | 支持范围与缺口 | 验证 |
| --- | --- | --- | --- |
| §9 函数体 | 部分实现 | 支持同步块体和 `=>`；异步与生成器函数体未实现。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `integer()`、`argumentCalls()` |
| §9.1 顶层函数声明 | 部分实现 | 支持声明绑定、直接调用、递归和跨库引用；非泛型顶层函数可提取为值，保留必需、可选位置及命名参数签名。泛型直接调用的支持范围见下文。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `program/fibonacci()` |
| 顶层访问器 | 部分实现 | 支持 getter/setter 配对、仅读和仅写属性；文件版本至少 3.9 时，读结果与写参数类型可独立；此前要求 getter 结果是 setter 参数的子类型，写入仍按 setter 参数检查，按拥有声明的库版本决定，导入方不重新配对。未注解时为 dynamic；setter 结果只能省略或在类型别名展开后为 void，且有一个必需位置参数；未使用的声明同样检查。静态类访问器见[类追踪](classes.md)；完整库冲突规则尚缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `topAccessorValues()`、`operatorIndexing()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `libraries`、`rejected`、`rejectedOperators`、`failingValues` |
| [§9.1、§18.4 局部函数声明][local-declaration] | 部分实现 | 支持同步非泛型局部声明、词法捕获和自递归；作用域、调用与捕获限制见[局部函数](#局部函数)。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `program/localFunctions()`、`rejected` |
| [§17.14 匿名函数表达式][function-expressions]、[上下文推断][anonymous-inference] | 部分实现 | 支持同步非泛型箭头体、块体、词法捕获和上下文推断；调用与推断范围见[匿名函数](#匿名函数)。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `program/anonymousFunctions()`、`rejected` |
| §9 返回值 | 部分实现 | 按声明结果检查 return 和箭头体并执行必要转换；void 箭头体可保留实际负载，块体仍限制 void 返回表达式。局部省略结果的推断见下行；类型参数按声明身份检查返回，异常与异步相关规则尚缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `valueContexts()`、`staticReturn()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `program/localFunctions()`、`rejected` |
| [局部返回类型推断][local-inference] | 部分实现 | 按本函数的 return 类型和正常完成性推断；细则与递归边界见[局部返回类型推断](#局部返回类型推断)。[顶层省略结果仍为 dynamic][top-inference]。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `program/localFunctions()` 的 List 推断、Null/Never、void 与返回上下文 |
| §9 非空返回类型的正常落空 | 部分实现 | 结合当前流分析，拒绝可达的非空返回类型函数末尾；接受所有路径返回或已知不正常完成的循环/调用。同步异常与 finally 完成方式见[语句](statements.md)；异步控制流未实现。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `completeReturn()`、`nonCompletingFor()`、`nonCompletingDo()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `rejected` |
| §9 隐式返回 null | 部分实现 | 可空、dynamic、void 同步块体正常落空产生 null；未把未知的零值当作非空返回。`Future` 和生成器的隐式返回规则未实现。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `fallthroughInt()`、`fallthroughBool()`、`fallthroughDynamic()`、`fallthroughVoid()` |
| 空安全：`Never` 返回类型 | 部分实现 | 按声明结果使调用路径不正常完成，Never 返回类型不能正常落空；getter 的 Never 值也可在调用位置使用。直接调用、闭包及泛型实例化保留先行副作用，不执行后续实参或语句；不可达部分仍检查名字、类型及 return。相同规则用于源码诊断函数；异步及未实现的类型规则仍缺，见[类型追踪](types.md)。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `neverWrapper()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `neverExpressions()`、`neverGetterCall()`、`io.dart` 退出路径、`rejected`；[ssa_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/ssa_test.dart) 的终止值/后继合同 |
| §9.2.1 必需位置参数 | 部分实现 | 检查数量、类型并绑定参数槽，形参可为已支持的函数类型，包括 `int callback(int value)` 函数形式、可空函数及省略返回注解；泛型直接调用保留参数类型并在调用点代入；泛型函数类型仍缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `argumentCalls()` |
| [§9.2.1 形参修饰符][formal-modifiers]、[3.13 版本边界][parameter-modifiers] | 部分实现 | 2.12–3.12 文件支持普通 `final` / `var` 形参，包含可选位置、命名、局部及匿名函数；旧式 typedef 和嵌套函数形式参数也支持这两个修饰符，但它们不参与函数类型身份；`final` 绑定从入口起只读，闭包捕获、复合写入和模式赋值同样不能重写，`var` 仍可写。3.13 起禁止非声明参数上的这些修饰符；主构造器声明字段的 `final` / `var` 不受此旧语法规则影响。`const`、`late`、修饰符组合及 `var` 与显式类型组合被拒绝。初始化形式及函数形式的范围与差异见下文。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `parameter-modifier-imports.dart`、`rejectedParameterModifiers` |
| §9.2.2 可选位置参数 | 部分实现 | 支持省略、显式 `null` 和常量默认值；默认值仅限当前常量求值子集。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `positionalArguments()`、`constantDefaults()` |
| §9.2.2 命名参数 | 部分实现 | 支持重排、必需命名参数及缺失、重复、未知参数诊断；命名实参之后再出现位置实参要求调用点文件版本至少 2.17，普通调用和常量构造调用都保留源码求值顺序。未实现完整函数子类型规则。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `namedArguments()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `rejected` |
| §9.2.2 默认值绑定 | 部分实现 | 库/成员默认值在声明库作用域求值；局部函数采用声明处词法常量作用域，可引用此前可见的 outer const，不能偷读调用方名字或普通外层变量。支持当前标量、常量 List、类实例与顶层函数引用子集，不代表完整常量语言。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `positionalArguments()`、`constantDefaults()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `program/localFunctions()` |
| §9.2.2 隐式默认 `null` | 部分实现 | 可空或动态参数允许省略；非空参数缺默认值报错。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `nullableArguments()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `rejected` |
| §9.2 初始化形式参数 | 部分实现 | 已实现的生成式构造支持 `this.field`、命名默认值及显式子类型到字段表示转换；[私有命名字段形式参数][private-named]要求声明库版本至少 3.12，去掉首个 `_` 后须为合法公共标识符，且声明名和公共名不得与其他形参冲突（含位置形参）。以公共名调用，旧版本调用方不改变声明规则；支持 [super 形参][super-parameters]，具有关联父参数的类型、默认值和初始化作用域；命名 super 形参须为公共名称，包括父参数为私有命名字段形参的情况。字段及 super 形参支持 `int this.f(int x)` 一类函数形式，省略返回注解为 dynamic。[3.13 之前的 final 修饰符][parameter-modifiers]可用于字段及 super 形参，不改变字段本身的可写性；主构造器中的声明参数与初始化作用域见[类](classes.md#主构造器)。生成式重定向不能带字段或 super 形式参数，见[构造器规则](classes.md)。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `Cell`、`argumentCalls()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `version-private.dart`、`version-imports.dart`、`rejected` |
| [§9.2.3 `covariant` 参数][covariant-parameters] | 部分实现 | 支持用户类的实例方法、setter 和运算符参数，包括可选/命名参数、函数形式参数及已有泛型方法。协变性按参数位置或公共名从所有接口继承；参数可收窄，但必须与每个直接/间接父声明的对应类型可比较，调用形状约束不变。调用仍按静态签名检查，运行时分派在方法体前检查实际实现的参数类型；方法值的运行时签名把协变参数放宽到 Object?，实际调用仍检查参数类型。显式 covariant 字段及主构造器声明参数见[类](classes.md)；泛型类按实际接收者检查由类参数产生的协变形参，这不授予收窄覆写的权限，见[类追踪](classes.md#泛型运行时实例)；泛型类方法值与完整动态成员查找仍缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `covariantValues()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `rejectedCovariant`、`covariantSyntaxDifferences`、`failingValues`、`parameter-modifier-imports.dart` |
| [§9.3 函数类型与函数对象][signature] | 部分实现 | 可执行文件支持非泛型必需/可选位置及命名参数签名的函数值及存储、传参、返回、typed List、调用/`.call`；常量、身份与输出限制见[函数值](#函数值)。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `functionValues()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `program/localFactory()`、`program/localFunctions()`、`program/anonymousFunctions()`、`rejected` |
| §9.4 外部函数 | 部分实现 | 仅受信运行时中的显式原语签名可连接；没有通用 external 链接或 `NoSuchMethodError` 路径。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `invalidRuntimes` |
| §9 异步与生成器 | 未实现 | 无 `async`、`sync*`、`async*` 函数表示、暂停点及调度实现。 | 待补充 |
| §17.15 参数求值及绑定 | 部分实现 | 直接调用保留实参源码顺序及形参重排；函数值的读取时机按 callee 形式区分，实例与静态选择器的 SDK 求值顺序见[表达式追踪](expressions.md)。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `argumentCalls()`、`functionValues()`、`staticMembers()` 的 trace 与寄存器/栈参数 |
| §19.6 脚本入口的函数调用 | 部分实现 | 入口函数接收 CLI 参数；第二位置参数取 `null`，其余可选参数取声明默认值。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `namedEntry`、`twoEntry`、`invalidEntry` |

固定草案 [§9.2.1][formal-modifiers] 禁止 `var this.field`；SDK 3.13.7 的 CFE 和 analyzer 接受 3.12 文件中的这一形式，dartc 按草案拒绝，并由 `var-field-formal.dart` 单独验证，不计为 SDK 一致。带 `final` / `var` 的函数形式参数（如 `final int callback(int n)`，包括对应字段形式）按 SDK 拒绝；显式 `final int Function(int) callback` 在旧版本可用。草案的字段形式产生式仍容纳修饰符和函数尾缀的组合，这部分尚未宣称完全一致。实例参数的 covariant 可与旧版 final / var 组合；修饰符顺序仍按语法检查。

协变参数的[覆写规则][covariant-overrides]与[方法闭包化规则][covariant-closurization]分别约束静态签名和方法值的运行时签名。合并接口时先选择原有函数子类型关系下的签名，再合并所有父签名的协变标记；不能通过放宽覆写检查来改变合并签名。继承具体实现也保留接口引入的协变性，`super.method` 则使用父实现的签名。隐式字段 setter 实现协变接口时按字段类型检查写入。

普通形参上的 covariant 按固定规范与 SDK 3.13.7 analyzer 限于实例方法、setter 或运算符；主构造器的字段声明参数另按 3.13 规则处理。该 SDK 的 CFE 还接受局部/匿名函数、普通及工厂构造器、字段形式参数、两种函数 typedef 中的该修饰符。dartc 按规范和 analyzer 拒绝这些位置，`covariantSyntaxDifferences` 单独核实 CFE 接受与 dartc 拒绝。协变入口的类型检查失败抛出可捕获 TypeError，`failingValues` 验证参数求值顺序、捕获、首次轨迹及 finally；具体诊断文本仍缺，见[异常范围](statements.md)。

## int.parse

依据 §17.15 调用义务及 SDK [`int.parse(String source, {int? radix})`](https://api.dart.dev/stable/3.13.7/dart-core/int/parse.html)，省略 radix 的调用在源 API 边界检查一个必需位置 String 实参；缺参、多余位置参数、命名 source、未知命名参数、类型实参和不兼容的静态值类型被拒绝，未使用函数也检查。实参只求值一次。显式 radix 和静态方法函数值仍未实现。

默认解析接受 Unicode 首尾空白、可选正负号、十进制及 `0x`/`0X` 前缀。十进制和负十六进制受有符号 64 位范围约束；正十六进制允许完整 64 位位模式，因此 `0xffffffffffffffff` 为 -1。空输入、没有数字、非法数字或超范围输入抛出普通 FormatException，保留原始 source、非空 message 和可用时的 offset，沿一般 catch/finally 路径处理；错误文案与具体 offset 可能与 SDK 不同。

验证：[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `program/intParseInput()`、`program/intParsing()`、`uncaught` 与 `rejected`，异常载荷及轨迹的 GC 保活见 [roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart) 的 `exceptionRoots()`。

## 泛型直接调用

[§9 类型参数作用域][generic-scope]和[§17.15 调用][generic-call]部分实现。顶层函数、静态及实例方法（包括 `call`）可声明类型参数、显式上界和必需/可选/命名值参数。参数按声明身份绑定，默认值在声明作用域检查；未使用函数也检查边界、函数体、返回和确定赋值。类型参数可用于 List、用户类、可空类型、非泛型函数签名、`is`/`as` 和已支持的模式。类型参数不能用于常量类型实参，构造器和访问器不能声明自身类型参数。

显式调用检查实参数量和代入后的上界。省略类型实参时，支持已有类型模型中的上下文、普通实参及带类型回调约束；返回上下文与参数上下文保持独立，例如 `print` 的 `Object?` 参数参与向下推断。没有约束时采用实例化到界。实参求值、必要检查和命名重排保持源码顺序；调用成员 getter 的时序遵守已有调用规则。

`dynamic` 实参可传给 `List<T>`、嵌套 List、可空复合类型及非泛型函数签名等含类型参数的形参；类型实参仍由静态约束、返回上下文和默认边界决定，不读取实参对象的运行时类型来推断。依照[子类型约束生成与求解][generic-inference]，无法从 dynamic 分解复合类型时不产生内部类型参数约束；推断完成后再检查实际值，并保持该检查早于下一实参的求值。验证：[values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) 的 `genericDynamicArguments()` 及 `failingValues` 的非 List 实参。

SDK 3.13.7 对未显式给出类型实参的上述调用存在检查差异：虽然从其他实参推断出 `int`，仍可让 dynamic 持有的 `List<String>` 进入 `List<int>` 形参；从上界或默认类型得到的 List/函数参数同样可能漏检。dartc 按[实参与形参绑定规则](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L13352-L13369)保留类型检查；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `generic-dynamic-checks.dart` 分别验证推断和显式调用，以 SDK 显式调用为检查对照，并单独记录隐式调用差异。

泛型类中再声明类型参数的实例方法、泛型局部/匿名函数、泛型函数值及 tear-off、泛型函数类型、一般泛型父接口参与的界限推断和 `T & S` 交叉类型提升仍缺。泛型 `main` 当前仅支持无值参数、默认类型实参满足边界的声明。类型参数作为公开 `Type` 值尚未实现。这些限制是实现缺口，不改变语言兼容目标。

验证：[values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) 的 `genericFunctions`、[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `generic-functions-imports.dart`、`generic-entry.dart`、`rejected` 与 `failingValues`。推断依据[类型推断规则][generic-inference]，运行时类型图的存活检查由 [roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart) 的 `genericTypeRoots` 拥有。

### 回调水平推断

按 [Dart 2.18 水平推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.18/horizontal-inference/feature-specification.md)，普通泛型函数、方法和生成式构造的直接调用支持从其他实参推断函数字面量中未标注的参数。回调之间按类型依赖分阶段，循环依赖留在同一阶段；同阶段共享进入该阶段时的上下文，阶段结束后固定已确定的类型。命名参数、可选参数及括号包住的直接函数字面量遵守相同规则，条件表达式等间接产生的函数值不会借此推迟推断。旧于 2.18 的调用库仍使用原来的同阶段推断。

普通实参保持源码求值及检查顺序，直接函数字面量在其后分析和构造。普通声明的非泛型调用、显式泛型调用、构造器调用及具体函数值调用也延后函数字面量，允许它捕获由其他实参完成初始化的变量。未得到约束的回调参数使用类型 schema 的最大闭包，未知类型取 Object?，嵌套函数参数按逆变方向取 Never；不会自动退化为 dynamic。回调结果仍由函数体和返回上下文推断。捕获写入与类型提升仍受[词法捕获](#词法捕获)所列流分析边界限制，部分标准库调用及 dynamic 调用尚不支持此推断。

验证：[values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) 的 `horizontalInference()`、[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `horizontal-2.17.dart` / `horizontal-2.18.dart` 及对应拒例。

### 基于界限的推断

调用库从 3.7 起按[基于界限的推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/inference-using-bounds/design-document.md)组合已有下界约束与声明上界。例如 `X extends List<Y>` 的 X 从实参得到 `List<int>` 时，继续为 Y 生成 int 约束；支持当前类型模型中的嵌套 List、可空界限、函数结果及参数逆变、多级界限链。普通泛型直接调用与普通及 const 泛型构造、类别名使用同一规则；版本取调用所在库，不取被调用声明的版本。

向下上下文、水平推断阶段与最终求解都按类型参数声明顺序处理，前阶段已经固定的解不重新选择。部分求解仅在该参数的约束解已知时使用界限，最终求解也处理含未知部分的下界；没有可分解的下界时不凭运行时值补充类型。最终阶段中已处理的参数不会因后面的界限产生新约束而回头重解，因此没有其他 Y 约束时，`<Y, X extends List<Y>>` 与相反声明顺序可能得到不同结果。界限关系不会向回调水平推断的依赖图添加额外边，仅依赖 Y 的回调不会因另一个参数的类型是 X 而自动推迟。

验证：[values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) 的 `genericBoundInference()`、`metadataValues()`，以及 [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `bounds-3.6.dart` / `bounds-3.7.dart` 和泛型拒例。泛型父接口、完整 F-bound 约束生成与其余约束求解缺口仍待实现。

## 局部函数

局部声明支持同步非泛型函数、自递归、块内遮蔽和只读名字。直接调用和函数值调用都支持必需、可选和命名参数，捕获不改变参数规则。

声明前引用不会回退到同名 global；互递归的前向引用被拒绝。支持捕获普通外层变量及显式/隐式 `this`；构造初始化器中的闭包可以捕获参数，但不能借闭包读取尚不可用的实例。

### 局部返回类型推断

省略返回类型时，根据本函数的 return 类型及函数体能否正常结束推断：

- 死代码中的 return 也参；子函数的 return 不参与。
- 无 return 且正常落空时推断为 Null，不正常完成时推断为 Never。
- 推得结果只控制最终转换，不反向改变返回字面量的实际类型。

局部递归推断以 dynamic 为初始结果类型，兼容 SDK 3.13.5；不消费递归结果时仍可推得更具体类型。固定推断 Draft 的空安全段落描述 inference failure，诊断与此不同。

## 匿名函数

匿名表达式支持同步非泛型箭头体和块体，以及必需、可选位置和命名参数签名的捕获。泛型、异步与生成器尚未实现。

省略的参数类型按期望签名推断，返回表达式使用期望结果上下文。上下文可来自变量、实参、返回、条件及全局/字段初始化；没有上下文时，参数类型为 dynamic。

直接调用、提取后的函数值调用及 `.call` 共用参数规则；命名参数按公共名称匹配上下文，与声明顺序无关。

## 词法捕获

[函数闭包化规则][closurization]与[匿名函数规则][function-expressions]在当前同步、非泛型签名范围内支持：外层绑定的持续读写、多个闭包共享变量、嵌套捕获、自递归与函数值调用。同一作用域中的局部函数重复读取保持身份；不同工厂调用保留各自的绑定。

`for (var i = …)` 的闭包保留每轮绑定，更新表达式作用于下一轮绑定；`for-in` 的声明变量同样逐轮独立。循环使用外部已有变量时继续共享它。按声明点检查捕获的确定赋值事实；子函数中的写入不使父函数的变量自动成为已赋值。捕获的 final 不能在子函数中赋值。被闭包写入的绑定不参与类型提升；没有显式写入的绑定可以在闭包中保留外围提升。更完整的流规则仍按[类型追踪](types.md)补齐。

验证：[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `capturedFunctions()` 及捕获拒绝用例；[roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart) 的 `closureRoots()` 验证逃逸闭包、共享绑定和捕获引用的枚举。自身声明类型参数的局部/匿名函数和异步捕获仍有实现缺口。

泛型顶层函数、静态和实例方法，以及泛型类的构造器和实例成员中，非泛型局部函数与匿名函数可捕获外层类型参数和普通变量，包括多层逃逸、共享可变绑定、自递归和隐式 `this`。外层类型参数可用于参数/结果/局部类型、List 和用户类构造、其他泛型直接调用、`is`/`as` 与模式；无值捕获或仅在函数体中使用类型参数的闭包也保留类型环境。函数对象按创建时的实际类型实参形成签名，参数逆变、结果协变及调用入口检查沿用非泛型函数值规则。未使用的泛型函数和局部函数仍检查函数体、返回、确定赋值与常量义务。

依据[函数闭包化][closurization]和[函数对象签名][signature]；验证：[values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) 的 `genericClosures()`、[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `rejected` / `failingValues`。外层返回后，闭包签名、类型环境及捕获值的根枚举由 [roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart) 的 `genericTypeRoots()` 验证。

## 函数值

可执行文件产物支持将顶层函数、静态方法、绑定实例方法、局部函数和匿名函数作为值存储、传参、返回或放入 typed List，并通过具体的非泛型签名调用或 `.call`。目标文件、静态库和动态库产物不支持 Dart 函数值。非泛型用户类的构造器函数值见[类追踪](classes.md#构造器函数值)。泛型函数值及 dynamic/裸 `Function` 调用尚未实现。

[实例方法闭包化][instance-closurization]支持已绑定类声明的非泛型方法，包括显式/隐式 this、嵌套闭包内提取、跨库可见性及空短路接收者。接收者只求值一次，方法值持续持有该对象；相同对象的同一方法且运行时函数类型相同时比较相等，协变接口可能使 `super.method` 与 `this.method` 的运行时类型不同。普通闭包仍按自身身份比较；不规定重复方法提取的 `identical` 结果。实例方法引用不是常量，未使用函数和未执行常量分支也须检查这一义务。支持继承方法和 super 方法值；super 选择父类具体实现，仍绑定原对象。泛型类中声明的方法提取、部分标准库方法的提取及 Function.hashCode 等继承 API 仍缺。验证：[values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) 的 `functionValues`、`inheritanceValues`、[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `function-imports.dart`、拒例与失败用例，以及 [roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart) 的 `closureRoots`。

函数签名区分必需/可选位置参数、命名参数及 `required`，命名顺序不构成类型身份。结构子类型检查参数逆变、结果协变、允许的位置参数区间、命名参数集合及必需命名参数约束；静态检查和运行时 `is`/转换采用同一规则。函数类型别名、上下文推断、上下界合并和外层类型参数代入保留这些形状。依据[函数子类型][function-subtyping]及[上下界规则][function-bounds]。

调用方只传显式实参；实际目标补默认值，不从静态函数类型猜测默认值。省略与显式 null 保持区别，转换为较窄签名后仍用原目标的默认值。参数表达式及必要类型检查按源码顺序执行，再按位置和公共名对应。实例函数 getter 的读取时机及 SDK 差异见[表达式](expressions.md#尚缺与待核验)。验证：[values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) 的 `functionParameterValues()`、[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的拒例、失败转换及 `function-getter-order.dart`，以及 [roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart) 的 `closureRoots()`。

顶层函数和静态方法引用可用于常量，局部声明引用与匿名表达式不因此成为 const。无捕获局部函数对象可按声明共享；跨调用的对象身份是实现选择，不能依赖 SDK 某次分配行为。重复读取同一作用域中的局部声明仍保持身份，依据[函数闭包化规则][closurization]。

## 可调用对象

依据[函数表达式调用][callable-invocation]与[隐式转换][callable-coercion]，已知非空类声明中的实例 `call` 方法支持 `object(...)`，直接调用复用必需、可选和命名参数绑定。字段、getter 和静态成员名为 `call` 时，不会使所属实例可直接调用；支持继承的 `call` 和方法体内的 `super(...)`，后者按[super 调用规则][super-invocations]调用父类的 `call`。extension 提供的调用仍缺。

在赋值、传参、返回、列表单元素和 `for-in` 变量的函数类型上下文中，非空对象可隐式提取 `call`。支持具体非泛型签名、`Function` 及其可空形式；转换结果沿用绑定方法的接收者存活和相等性。`Object`、`dynamic` 和无上下文推断保留原对象；对象本身不是 `Function`，显式 `as` 和来自 dynamic 的检查转换不提取方法。

条件、`??`、级联和空断言先确定整个表达式的类型，再做隐式提取；可空对象不能借可空函数目标自动提取。集合 spread 不逐元素插入该转换。实例字段/getter 的直接调用保持先求值实参、再读取成员的顺序；括号包住成员时先读取。泛型函数值签名和 dynamic 调用仍受前述缺口限制。

SDK 3.13.7 CFE 允许未选中常量集合分支及构造实参中的隐式提取，并检查签名兼容；实际执行提取时报告常量错误。它也允许 const 构造器声明中的对应隐式转换在普通实例创建时执行。analyzer 分别报告 `non_constant_list_element`、`const_with_non_constant_argument`、`invalid_constant`；dartc 采用 CFE 行为，测试逐行注明诊断忽略。显式实例方法引用仍不是常量表达式，即使位于未选中的分支。

验证：[values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) 的 `functionValues()`、[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `function-imports.dart`、`nogc-values.dart`、`rejected` 与 `failingValues`；[roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart) 的 `closureRoots()` 检查隐式提取后接收者的根枚举。

## 支持边界

- 已知声明的直接调用保留原参数绑定；函数值调用目前只消费具体的非泛型签名，不能把裸 `Function` 或 `dynamic` 当作已知签名。
- 默认值仅接受[已支持的常量表达式](expressions.md)，不覆盖完整常量语言。
- 工厂构造器体复用普通函数的参数绑定、捕获和返回检查；重定向仅转发显式实参，最终目标补入默认值，见[类追踪](classes.md#工厂构造器)。
- 构造器函数值复用相同签名与实参协议，支持 `.new`、命名提取及 `(C.named)(...)`；生成式与工厂的分配和默认值职责见[类追踪](classes.md#构造器函数值)。
- 原语和 FFI 回调有独立签名边界；普通 Dart 函数对象不能隐式变成 FFI 指针，一般 external 连接仍缺。
- 非空落空与 Never 调用采用现有局部流分析；`late`、捕获闭包、泛型交叉类型、异常和异步路径仍有缺口。

语言版本边界的验证见 [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `version-imports.dart`、`version-named.dart` 与拒绝用例。类与库级访问器都受声明版本约束；这不等同于完整旧版函数或继承规则。

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

[super-invocations]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L14746

[super-parameters]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.17/super-parameters/feature-specification.md

[formal-modifiers]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L2366-L2420

[parameter-modifiers]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.13/primary-constructors/feature-specification.md#language-versioning

[function-subtyping]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/subtyping.md#L202-L224
[function-bounds]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/upper-lower-bounds.md

[covariant-parameters]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L2486-L2635
[covariant-overrides]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L3187-L3204
[covariant-closurization]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L15272-L15294
