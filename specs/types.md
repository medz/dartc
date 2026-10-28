# 类型与泛型

兼容目标、SDK 对照版本与状态含义见[总览](README.md#状态与证据)。
章节号取自固定版本的[语言规范草案][draft]；[PDF][pdf]便于阅读，但链接内容可能更新。
[官方规范入口][entry]说明 Dart 3 规范仍未覆盖当前全部语言特性，因此还需参考补充文档与对应 SDK 行为。

## 依据与状态

- [空安全提案][nnbd]位于官方 `accepted/2.12`；[类型推断][inference]和[流分析][flow]为同一版本的官方补充文档，文档自身仍标为 Draft。
- 对象表示、TypeRef 布局、GC 与引导机制见[架构设计](../doc/architecture.md)；表达式规则见[表达式](expressions.md)。

## 当前实现

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §20.1 静态类型 | 部分实现 | 区分 `int`、`double`、`num`、`bool`、`String`、`Null`、`Never`、`Object`、`dynamic`、`void`、可空类型、`List<T>`、函数签名、Function 上界和已声明类；局部 value 声明遮蔽同名类型/prefix 时拒绝，函数签名不看 body locals；尚非完整 Dart 类型模型。 | [types.dart](../lib/src/types.dart)：`DartType`；[values.dart](../test/fixtures/values.dart)：`typeChecks`、`staticContexts`、`neverContexts`、`doubleValues`；[behavior_test.dart](../test/behavior_test.dart)：`program/localFunctions`、`rejected`。 |
| §20.1 类型名解析 | 部分实现 | 按声明库、导入前缀和 part 的库身份解析类型；别名、顶层函数和方法的类型参数具有独立声明身份与作用域，可遮蔽同名类或导入前缀，检查参数数量及边界。泛型类及泛型闭包的参数作用域仍未接入。 | [resolve_type.dart](../lib/src/resolve_type.dart)：`resolveType`；[behavior_test.dart](../test/behavior_test.dart)：`libraries`、`rejected`。 |
| §20.2 动态类型系统 | 部分实现 | `is`、`is!`、`as` 与隐式动态转换使用实际运行时类型；覆盖嵌套 List、类、函数签名与可空类型；内部类型记录支持堆引用扫描，泛型直接调用实例化 List、可空及函数类型；不含一般动态成员分派或 dynamic 函数值调用。 | [runtime.dart](../lib/src/runtime.dart)：`rtValueMatches`、`rtValueCast`；[values.dart](../test/fixtures/values.dart)：`typeChecks`；[behavior_test.dart](../test/behavior_test.dart)：`failingValues`；[roots.dart](../test/fixtures/roots.dart)：`typeGraphRoots`、`genericTypeRoots`。 |
| §20.4 子类型 | 部分实现 | 有 `Never` 底类型、`int <: num`、`double <: num`、空性、支持类型到 `Object` 的关系、List 协变及函数参数逆变/结果协变；非泛型用户类的 implements 图参与静态与运行时子类型计算，包括嵌套 List 和函数签名；类的共同上界使用唯一最具体的共同接口。泛型类及 extends 层次仍缺，接口规则见[类](classes.md)。 | [types.dart](../lib/src/types.dart)：`typeIsSubtype`；[runtime.dart](../lib/src/runtime.dart)：`rtTypeSubtype`、`rtClassSubtype`；[values.dart](../test/fixtures/values.dart)：`typeChecks`、`staticContexts`、`neverContexts`、`doubleValues`、`interfaceValues`。 |
| [§20.5–20.6 函数类型与 `Function`][function-types] | 部分实现 | 顶层、局部与匿名函数共用结构签名、参数逆变/返回协变、Function 上界和运行时测试/转换/List 写入检查；局部缺省结果与匿名结果从 typed body 推断，声明身份不充当类型身份。源函数值签名仍限非泛型必需位置参数；可选/命名/泛型值签名未实现，裸 Function 尚不能直接调用。 | [types.dart](../lib/src/types.dart) `functionType()`、`typeIsSubtype()`；[frontend.dart](../lib/src/frontend.dart) `feInferLocalResult()`、`feLowerFunctionExpression()`；[runtime.dart](../lib/src/runtime.dart) `rtTypeSubtype()`；[behavior_test.dart](../test/behavior_test.dart) `program/localFunctions()`、`program/anonymousFunctions()`、`failingValues` |
| §20.7 `dynamic` | 部分实现 | 独立语义类型；可隐式转入具体类型并执行运行时检查，不能与 `Object` 或声明存储类型混用；仅实现部分动态运算。 | [typing.dart](../lib/src/typing.dart)：`typingAssignable`、`typingBinary`；[frontend.dart](../lib/src/frontend.dart)：`feConvertValue`；[values.dart](../test/fixtures/values.dart)：`valueContexts`、`staticContexts`。 |
| §20.9 `void` | 部分实现 | 限制值消费；`void` 上下文可保留实际返回负载，支持 `List<void>`；显式 `as` 可检查并取得实际负载；局部仅向严格子类型提升，`as dynamic` / `as Object?` 不改变原 void 读取类型；普通隐式消费仍拒绝。泛型函数类型和异步语义相关规则尚缺。 | [typing.dart](../lib/src/typing.dart)：`typingAssignable`；[frontend.dart](../lib/src/frontend.dart)：`feConvertValue`；[values.dart](../test/fixtures/values.dart)：`valueContexts`。 |
| §20.10 参数化类型 | 部分实现 | 保留完整嵌套 `List<T>` 实际类型；协变视图写入按底层元素类型检查。函数类型参数中的 List、可空及函数类型在运行时保留实际类型，支持类型变化的递归调用；`Pointer<T>` 仅有受限 FFI 语义，泛型类仍缺。 | [types.dart](../lib/src/types.dart)：`listType`；[runtime.dart](../lib/src/runtime.dart)：`rtListGet`、`rtListSet`、`rtListAdd`；[values.dart](../test/fixtures/values.dart)：`staticContexts`、`typeChecks`。 |
| §20.10.2 最小上界 | 部分实现 | 对支持类型、空性、嵌套 List 和函数签名求公共类型，区分 `void` 与 `dynamic`；不是完整约束求解或所有 Dart 类型的 LUB 算法。 | [types.dart](../lib/src/types.dart)：`joinTypes`；[values.dart](../test/fixtures/values.dart)：`staticContexts`、`coalescingContexts`、`functionValues`。 |
| §20.11 相同类型 | 部分实现 | 已支持类型按结构复用类型身份；运行时检查保留实际 List 参数和函数签名。尚无一般 `Type` 值及其公开操作。 | [types.dart](../lib/src/types.dart)：`listType`、`nullableType`、`classType`、`functionType`；[values.dart](../test/fixtures/values.dart)：`constantLists`、`typeChecks`。 |
| [§15 类型参数][type-parameters] | 部分实现 | 泛型别名、顶层函数和方法保存有序参数及上界，以声明身份绑定和代入；保留 List、可空类型及函数签名中的参数结构，检查未使用声明的重复名、作用域、边界与循环。[3.7 起 `_` 参数][wildcards]保留身份和实参数量，但不引入可查找名字；此前按普通参数绑定。泛型类及函数类型自身的泛型参数仍未实现；函数调用和推断范围见[函数](functions.md#泛型直接调用)。 | [ast.dart](../lib/src/ast.dart)：`AstTypeParameter`；[types.dart](../lib/src/types.dart)：`TypeParameterInfo`、`substituteType`；[resolve_type.dart](../lib/src/resolve_type.dart)：`resolveTypeAliasDeclarations`、`checkTypeAliasDeclarations`、`resolveFunctionTypeParameters`；[values.dart](../test/fixtures/values.dart)：`genericAliases`、`genericFunctions`；[behavior_test.dart](../test/behavior_test.dart)：`generic-aliases-imports.dart`、`rejectedTypeAliases`。 |
| §15.1 型变 | 部分实现 | List 元素协变、函数参数逆变/结果协变参与别名参数的型变计算及实例化；List 写入仍检查实际元素类型。接口覆写复用这些子类型关系，见[类](classes.md)；用户声明的型变和 `covariant` 参数规则未实现。 | [types.dart](../lib/src/types.dart)：`typeIsSubtype`；[runtime.dart](../lib/src/runtime.dart)：`rtListSet`；[behavior_test.dart](../test/behavior_test.dart)：`failingValues`。 |
| [§20.3 类型别名][aliases] | 部分实现 | 支持现代 `=` 形式及旧式函数 typedef，含泛型参数、省略结果/参数类型和嵌套函数形参；两种拼写复用类型代入、前向和链式展开。别名先展开，待接口图检查完成后统一验证声明与接口使用处的边界，避免声明顺序改变子类型判断。在声明库下将真实参数代入当前 List、函数签名、可空及用户类模型。普通 RHS 要求至少 2.13，2.12 只接受直接且非可空的函数类型 RHS；Function 不能作别名名。用户类别名复用实际类构造计划、私有性及常量身份，`.new` 仍要求 2.15；可空结果差异见下文。内建 List/String 构造别名、泛型函数类型和旧式 typedef 的 covariant 形参仍缺；FFI 别名保留独立原生签名，泛型原生模板尚未支持。 | [symbols.dart](../lib/src/symbols.dart)：`TypeAlias`；[resolve_type.dart](../lib/src/resolve_type.dart)：`resolveType`、`resolveDeclarationType`、`resolveSuperinterface`；[values.dart](../test/fixtures/values.dart)：`genericAliases`、`legacyAliases`、`namedConstructors`、`interfaceValues`；[behavior_test.dart](../test/behavior_test.dart)：`generic-aliases-imports.dart`、`named-constructors-imports.dart`、`rejected`。 |
| [§15.2 超界类型][super-bounded-types]、[§15.3 实例化到界][instantiate-to-bound] | 部分实现 | 泛型别名区分显式实参检查、合法超界类型与原始别名的默认实例化；依赖和 F-bound 按参数身份与型变求默认值，替换所需的下界使用 Never；无显式上界的原始参数按规则取 dynamic。原始类型用于上界时须满足简单界限制。只覆盖现有类型模型；函数直接调用使用相同默认实例化并检查代入后的上界。完整调用推断与泛型类仍缺。 | [types.dart](../lib/src/types.dart)：`instantiateTypeParameters`、`superBoundedType`；[resolve_type.dart](../lib/src/resolve_type.dart)：`resolveTypeAliasDeclarations`；[values.dart](../test/fixtures/values.dart)：`genericAliases`；[behavior_test.dart](../test/behavior_test.dart)：`rejectedTypeAliases`。 |

## 空安全、推断与流分析

下表依赖[空安全][nnbd]、[推断][inference]和[流分析][flow]补充文档；旧草案章节不能单独代表这些规则。Dart 3.9 的 sound-flow-analysis 门槛还依据[对应 SDK 特性表][features]与真实编译差分。

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| 可空与非空类型 | 部分实现 | 识别 `T?`，拒绝未经提升的可空成员、索引和算术消费；`== null` 真分支不直接把类型变成 `Null`；空断言的结果去除空性，Null 结果为 Never，dynamic 保留 dynamic。空短路访问按非空接收者检查链内操作，再将结果变为可空；类型限定的静态访问不添加空性。 | [types.dart](../lib/src/types.dart)：`nullableType`、`typeCanBeNull`；[flow.dart](../lib/src/flow.dart)：`flowNull`；[values.dart](../test/fixtures/values.dart)：`flowBranches`、`nullAssertionValues`、`nullAwareValues`；[behavior_test.dart](../test/behavior_test.dart)：`rejected`。 |
| 空安全底类型 `Never` | 部分实现 | 作为子类型与合并的底类型，`Never?` 规范化为 `Null`；空 `List<Never>` 可协变读取，写入仍按实际元素类型检查。没有 `Never` 实例；未初始化的普通及 late 局部存储不触发 Never 求值，读取仍受赋值及延迟初始化规则约束。完整类型参数及交集类型规则尚缺。 | [types.dart](../lib/src/types.dart)：`typeIsSubtype`、`joinTypes`、`nullableType`；[runtime.dart](../lib/src/runtime.dart)：`rtTypeSubtype`、`rtValueMatches`；[values.dart](../test/fixtures/values.dart)：`neverContexts`；[behavior_test.dart](../test/behavior_test.dart)：`failingValues`。 |
| 隐式赋值兼容 | 部分实现 | `Object`、可空类型不能直接下转为具体值；`dynamic` 可以检查转换。赋值目标的转换与表达式自身结果类型分别处理；赋值边界先做[可调用对象的隐式提取](functions.md#可调用对象)，表达式结果保留所得函数类型；`??=` 再合并非空读取类型与 RHS 类型，目标存储的装箱或检查转换不改变结果类型。 | [typing.dart](../lib/src/typing.dart)：`typingAssignable`；[frontend.dart](../lib/src/frontend.dart)：`feLowerAssignment`；[values.dart](../test/fixtures/values.dart)：`assignmentValues`、`staticContexts`、`coalescingAssignmentValues`。 |
| 局部与顶层推断、[匿名函数上下文][anonymous-inference] | 部分实现 | 从初始化表达式、List 元素及上下文推断；集合条件、循环与展开的所有元素类型参与推断，条件路径保留提升；空感知单元素接受可空上下文并以 NonNull 类型参与合并，过滤不向后传播变量提升；支持部分条件表达式和常量默认值。匿名函数省略参数使用对应签名参数，返回表达式获得期望结果上下文；Null/Never 参数上下文推为 Object?，void 结果上下文仍约束块体 return 的合法性。当前同步闭包可推断捕获表达式；泛型直接调用支持已有类型模型的部分上下文与实参约束，具体边界见[函数](functions.md#泛型直接调用)。完整约束求解与覆盖推断尚缺。 | [frontend.dart](../lib/src/frontend.dart)：`feLowerHint`、`feLowerFunctionExpression`、`feInferGlobal`；[constants.dart](../lib/src/constants.dart)：`evaluateConstant`；[behavior_test.dart](../test/behavior_test.dart)：`program/anonymousFunctions()`、`rejected`；[values.dart](../test/fixtures/values.dart)：`constantLists`、`staticContexts`。 |
| 类型提升与撤销 | 部分实现 | 按局部绑定身份处理 `is`、空检查、逻辑分支、退出、赋值及循环写入；`??=` 的非空路径与实际写入路径分别提升、合流；直接局部空断言在检查后提升，读取类型与声明存储类型分开。可变 late 局部可由初始化器结果提升；late final 初始化器不建立此提升。闭包捕获按声明身份检查写入：被闭包写入的绑定不提升，未显式写入的捕获可保留外围提升。模式声明/赋值的上下文 schema、switch 语句/表达式和 if-case 的类型、对象和 List 模式、List/别名实参及 Null 模式变量推导及提升边界见[模式](patterns.md)；字段提升及完整闭包流规则仍缺。 | [binding.dart](../lib/src/binding.dart)：`bindFunctionLocals`；[flow.dart](../lib/src/flow.dart)：`flowPromote`、`flowExclude`、`flowWrite`、`flowDemote`；[values.dart](../test/fixtures/values.dart)：`flowBranches`、`flowAssignments`、`flowContexts`、`coalescingAssignmentFlow`、`nullAssertionValues`、`lateValues`。 |
| 确定赋值、确定未赋值与可达性 | 部分实现 | 分别跟踪局部可读与 final 首次可写事实，合并分支、循环和标签退出；不可达代码仍检查读写；空短路访问与级联分开合并执行/跳过路径的写入事实。`Never` 调用终止正常路径，非空结果不能正常落空。3.9 起才以非空静态类型、总真 `is` 及 Null/非空类型不匹配判定相应死边；不把任意不相交的 `int is String` 分支当作 DFA 豁免。版本来自函数或全局初始化的拥有文件；捕获继承声明点的已赋值事实，闭包写入不反向确立外层赋值，非 late 的捕获 final 不允许赋值；late 的赋值和失败边界见[变量](variables.md)；同步 try/catch/finally 合流见[语句](statements.md)；异步及完整闭包控制流仍缺。 | [flow.dart](../lib/src/flow.dart)：`FlowState`、`flowJoin`；[frontend.dart](../lib/src/frontend.dart)：`feReadLocal`、`feWriteLvalue`、`feCall`；[values.dart](../test/fixtures/values.dart)：`finalAssignments`、`neverWrapper`、`nullAwareValues`；[behavior_test.dart](../test/behavior_test.dart)：`version-imports.dart`、`rejected`。 |
| `num` 与数值推断 | 部分实现 | `num` 是 `int` 与 `double` 的共同上界；`int + dynamic` 推断 `num`，double 数值参与算术时传播 double，`/` 返回 double，`~/` 返回 int；动态左操作数结果保留 dynamic。支持 double 上下文中可精确表示的整数字面量、可空值、泛型边界与 List 协变检查；没有普通 int 变量到 double 的隐式转换。 | [typing.dart](../lib/src/typing.dart)：`typingBinary`、`typingBinaryContext`、`typingUnary`；[values.dart](../test/fixtures/values.dart)：`staticContexts`、`floatingContexts`。 |

## 尚缺与待核验

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §20.8 `FutureOr` | 未实现 | `Future`、`FutureOr`、异步类型规则未接入。 | [types.dart](../lib/src/types.dart) 尚无对应类型；尚无行为验证。 |
| Records 与扩展类型 | 未实现 | 记录类型、扩展类型及相应关系未实现；已有 `Never` 和有限不相交类型分析不代表这些规则成立。 | [types.dart](../lib/src/types.dart)、[resolve_type.dart](../lib/src/resolve_type.dart)。 |
| 完整类型规范及诊断覆盖 | 待核对 | 完整类型关系、推断及诊断的一致性覆盖尚缺。 | [behavior_test.dart](../test/behavior_test.dart) 为差分入口。 |

## 验证方式

[behavior_test.dart](../test/behavior_test.dart) 将行为程序分别交给 SDK 与原生 dartc 编译执行，并检查应拒绝的源码。
[values.dart](../test/fixtures/values.dart) 用实际 List 推断、类型检查、成员消费和副作用使静态类型区别可观察。
运行时类型失败仍以进程退出表示；TypeError 等错误对象及完整诊断兼容未实现。显式 throw 的同步捕获见[语句](statements.md)。

类型参数注解在整组参数作用域中检查，typedef 自身注解仍取外围作用域。元数据构造和列表类型参数按展开后的实际类型依赖检查常量资格：擦除参数的 `Phantom<T> = Marker` 可用于注解构造及 `const <Phantom<T>>[]`，仍依赖 T 的 `const <T>[]` 被拒绝。SDK 3.13.7 CFE 接受前一种常量 List 注解，而 analyzer 报错；行为用例放在生成的库程序中保留这一差异，不将它解释为规范给出相反结论。

SDK 3.13.7 对跨库带前缀的泛型别名到非泛型类的 `p.A<int>()` 隐式构造报类型实参数量错误，而同库调用、显式 `new p.A<int>()` 及命名形式被接受。固定 2.13 规则允许 qualified alias 用于实例创建；此差异待核对，不据此增加前缀名称分支或判定该形式在语言上非法。

非泛型可空类别名的隐式命名及 `.new` 调用，SDK 3.13.7 的 CFE 与 analyzer 对结果 nullability 的处理有差异：CFE 保留可空结果，未命名、显式 `new` 和 `const` 路径返回非空结果；analyzer 将这些结果均按非空类处理。泛型可空类别名的 CFE 行为又有区别：省略实参的调用结果保持可空，显式实参的调用结果非空。dartc 尚未完整区分这些构造结果。固定的 2.13/2.15 特性文档未单独解释这组差异，不据此宣称规范给出同样区分。

数值运算与 `remainder` 的上下文按[空安全数值推断规则](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/number-operation-typing.md#improved-context-type)传播：接收者无上下文；结果约束结合接收者类型决定右实参上下文。`/` 与 `~/` 的返回类型独立于右实参，不沿用这项特殊收窄。验证入口为 `floatingContexts` 和 `rejected`。

[draft]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex
[pdf]: https://dart.dev/to/spec-draft
[entry]: https://dart.dev/resources/language/spec
[nnbd]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md
[inference]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md
[flow]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/flow-analysis.md

[features]: https://github.com/dart-lang/sdk/blob/3.13.5/tools/experimental_features.yaml

[aliases]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.13/nonfunction-type-aliases/feature-specification.md
[function-types]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L22447-L22501
[anonymous-inference]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md#L263-L372

[type-parameters]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L7413-L7478
[instantiate-to-bound]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L7882-L8357
[wildcards]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/wildcard-variables/feature-specification.md#L114-L126
[super-bounded-types]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L7685-L7880
