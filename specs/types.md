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
| §20.1 静态类型 | 部分实现 | 区分 `int`、`double`、`num`、`bool`、`String`、`Null`、`Never`、`Object`、`dynamic`、`void`、可空类型、`List<T>`、函数签名、Function 上界和已声明类；局部 value 声明遮蔽同名类型/prefix 时拒绝，函数签名不看 body locals；尚非完整 Dart 类型模型。 | [types.dart](../lib/src/legacy/types.dart)：`DartType`；[values.dart](../test/legacy/fixtures/values.dart)：`typeChecks`、`staticContexts`、`neverContexts`、`doubleValues`；[behavior_test.dart](../test/legacy/behavior_test.dart)：`program/localFunctions`、`rejected`。 |
| §20.1 类型名解析 | 部分实现 | 按声明库、导入前缀和 part 的库身份解析类型；别名、顶层函数和方法的类型参数具有独立声明身份与作用域，可遮蔽同名类或导入前缀，检查参数数量及边界。泛型类的参数、上界、字段/构造和实例成员作用域已接入；闭包可捕获实际类参数。泛型父接口及自身声明类型参数的闭包仍缺，见[类追踪](classes.md#泛型运行时实例)。 | [resolve_type.dart](../lib/src/legacy/resolve_type.dart)：`resolveType`；[behavior_test.dart](../test/legacy/behavior_test.dart)：`libraries`、`rejected`。 |
| §20.2 动态类型系统 | 部分实现 | `is`、`is!`、`as` 与隐式动态转换使用实际运行时类型；覆盖嵌套 List、类、函数签名与可空类型；内部类型记录支持堆引用扫描，泛型直接调用和实例成员重化 List、用户类、可空及函数类型；类型检查失败抛出可捕获 TypeError。不含一般动态成员分派或 dynamic 函数值调用。 | [runtime.dart](../lib/src/legacy/runtime.dart)：`rtValueMatches`、`rtValueCast`；[values.dart](../test/legacy/fixtures/values.dart)：`typeChecks`；[behavior_test.dart](../test/legacy/behavior_test.dart)：`failingValues`；[roots.dart](../test/legacy/fixtures/roots.dart)：`typeGraphRoots`、`genericTypeRoots`、`exceptionRoots`。 |
| §20.4 子类型 | 部分实现 | 有 `Never` 底类型、`int <: num`、`double <: num`、空性、支持类型到 `Object` 的关系、List 协变及函数参数逆变/结果协变；用户类的非泛型父类 extends / implements 图参与静态与运行时子类型计算，包括嵌套 List 和函数签名；类的共同上界使用唯一最具体的共同接口。泛型类的实参协变参与静态与运行时检查及共同类型计算；泛型父接口代入仍缺，见[类](classes.md)。 | [types.dart](../lib/src/legacy/types.dart)：`typeIsSubtype`；[runtime.dart](../lib/src/legacy/runtime.dart)：`rtTypeSubtype`、`rtClassSubtype`；[values.dart](../test/legacy/fixtures/values.dart)：`typeChecks`、`staticContexts`、`neverContexts`、`doubleValues`、`interfaceValues`、`runtimeGenericClasses`。 |
| [§20.5–20.6 函数类型与 `Function`][function-types] | 部分实现 | 顶层、局部与匿名函数共用结构签名、参数逆变/返回协变、Function 上界和运行时测试/转换/List 写入检查；局部缺省结果与匿名结果从 typed body 推断，声明身份不充当类型身份。支持非泛型必需/可选位置及命名参数签名，包含必需命名参数、顺序无关的命名类型身份、结构上下界及外层类型参数代入；泛型值签名未实现，裸 Function 尚不能直接调用。 | [types.dart](../lib/src/legacy/types.dart) `functionType()`、`typeIsSubtype()`；[frontend.dart](../lib/src/legacy/frontend.dart) `feInferLocalResult()`、`feLowerFunctionExpression()`；[runtime.dart](../lib/src/legacy/runtime.dart) `rtTypeSubtype()`；[behavior_test.dart](../test/legacy/behavior_test.dart) `program/localFunctions()`、`program/anonymousFunctions()`、`failingValues` |
| §20.7 `dynamic` | 部分实现 | 独立语义类型；可隐式转入具体类型并执行运行时检查，不能与 `Object` 或声明存储类型混用；仅实现部分动态运算。 | [typing.dart](../lib/src/legacy/typing.dart)：`typingAssignable`、`typingBinary`；[frontend.dart](../lib/src/legacy/frontend.dart)：`feConvertValue`；[values.dart](../test/legacy/fixtures/values.dart)：`valueContexts`、`staticContexts`。 |
| §20.9 `void` | 部分实现 | 限制值消费；`void` 上下文可保留实际返回负载，支持 `List<void>`；显式 `as` 可检查并取得实际负载；局部仅向严格子类型提升，`as dynamic` / `as Object?` 不改变原 void 读取类型；普通隐式消费仍拒绝。泛型函数类型和异步语义相关规则尚缺。 | [typing.dart](../lib/src/legacy/typing.dart)：`typingAssignable`；[frontend.dart](../lib/src/legacy/frontend.dart)：`feConvertValue`；[values.dart](../test/legacy/fixtures/values.dart)：`valueContexts`。 |
| §20.10 参数化类型 | 部分实现 | 保留完整嵌套 `List<T>` 实际类型；协变视图写入按底层元素类型检查。类和函数类型参数中的 List、用户类、可空及函数类型在运行时保留实际类型，支持类型变化的递归调用；泛型类成员按实际接收者检查协变参数和字段写入。`Pointer<T>` 仅有受限 FFI 语义；泛型父接口仍缺。 | [types.dart](../lib/src/legacy/types.dart)：`listType`；[runtime.dart](../lib/src/legacy/runtime.dart)：`rtListGet`、`rtListSet`、`rtListAdd`；[values.dart](../test/legacy/fixtures/values.dart)：`staticContexts`、`typeChecks`。 |
| §20.10.2 最小上界 | 部分实现 | 对支持类型、空性、嵌套 List 和函数签名求公共类型，区分 `void` 与 `dynamic`；不是完整约束求解或所有 Dart 类型的 LUB 算法。 | [types.dart](../lib/src/legacy/types.dart)：`joinTypes`；[values.dart](../test/legacy/fixtures/values.dart)：`staticContexts`、`coalescingContexts`、`functionValues`。 |
| §20.11 相同类型 | 部分实现 | 已支持类型按结构复用类型身份；运行时检查保留实际 List、用户类参数和函数签名。尚无一般 `Type` 值及其公开操作。 | [types.dart](../lib/src/legacy/types.dart)：`listType`、`nullableType`、`classType`、`functionType`；[values.dart](../test/legacy/fixtures/values.dart)：`constantLists`、`typeChecks`。 |
| [§15 类型参数][type-parameters] | 部分实现 | 泛型类、别名、顶层函数和方法保存有序参数及上界，以声明身份绑定和代入；保留 List、可空类型及函数签名中的参数结构，检查未使用声明的重复名、作用域、边界与循环。[3.7 起 `_` 参数][wildcards]保留身份和实参数量，但不引入可查找名字；此前按普通参数绑定。泛型父接口、泛型类的泛型实例方法及函数类型自身的泛型参数仍未实现；函数调用和推断范围见[函数](functions.md#泛型直接调用)。 | [ast.dart](../lib/src/legacy/ast.dart)：`AstTypeParameter`；[types.dart](../lib/src/legacy/types.dart)：`TypeParameterInfo`、`substituteType`；[resolve_type.dart](../lib/src/legacy/resolve_type.dart)：`resolveTypeAliasDeclarations`、`checkTypeAliasDeclarations`、`resolveFunctionTypeParameters`；[values.dart](../test/legacy/fixtures/values.dart)：`genericAliases`、`genericFunctions`；[behavior_test.dart](../test/legacy/behavior_test.dart)：`generic-aliases-imports.dart`、`rejectedTypeAliases`。 |
| §15.1 型变 | 部分实现 | List 和类实参协变、函数参数逆变/结果协变参与型变计算及实例化；List 和类字段写入按实际实参检查。显式或继承的 `covariant` 参数与由类参数产生的运行时检查分别处理，见[类](classes.md#泛型运行时实例)；用户声明的型变仍缺。 | [types.dart](../lib/src/legacy/types.dart)：`typeIsSubtype`；[runtime.dart](../lib/src/legacy/runtime.dart)：`rtListSet`；[behavior_test.dart](../test/legacy/behavior_test.dart)：`failingValues`。 |
| [§20.3 类型别名][aliases] | 部分实现 | 支持现代 `=` 形式及旧式函数 typedef，含泛型参数、省略结果/参数类型和嵌套函数形参；两种拼写复用类型代入、前向和链式展开。别名先展开，待接口图检查完成后统一验证声明与接口使用处的边界，避免声明顺序改变子类型判断。在声明库下将真实参数代入当前 List、函数签名、可空及用户类模型。普通 RHS 要求至少 2.13，2.12 只接受直接且非可空的函数类型 RHS；Function 不能作别名名。用户类别名复用实际类构造计划、私有性及常量身份，`.new` 仍要求 2.15；可空结果差异见下文。内建 List/String 构造别名、泛型函数类型和旧式 typedef 的 covariant 形参仍缺；FFI 标记类型和 Pointer/NativeFunction 实参保留在一般类型表中，函数别名与其他别名沿同一解析、代入和上界检查路径；Native/Dart ABI 映射在导出声明边界验证。 | [symbols.dart](../lib/src/legacy/symbols.dart)：`TypeAlias`；[resolve_type.dart](../lib/src/legacy/resolve_type.dart)：`resolveType`、`resolveDeclarationType`、`resolveSuperinterface`；[values.dart](../test/legacy/fixtures/values.dart)：`genericAliases`、`legacyAliases`、`namedConstructors`、`interfaceValues`；[behavior_test.dart](../test/legacy/behavior_test.dart)：`generic-aliases-imports.dart`、`named-constructors-imports.dart`、`rejected`。 |
| [§15.2 超界类型][super-bounded-types]、[§15.3 实例化到界][instantiate-to-bound] | 部分实现 | 泛型别名区分显式实参检查、合法超界类型与原始别名的默认实例化；依赖和 F-bound 按参数身份与型变求默认值，替换所需的下界使用 Never；无显式上界的原始参数按规则取 dynamic。原始类型用于上界时须满足简单界限制。只覆盖现有类型模型；函数直接调用使用相同默认实例化并检查代入后的上界。普通及 const 泛型生成式构造使用相同默认实例化；完整调用推断、泛型父接口和类的递归上界仍缺，见[类追踪](classes.md#泛型运行时实例)。 | [types.dart](../lib/src/legacy/types.dart)：`instantiateTypeParameters`、`superBoundedType`；[resolve_type.dart](../lib/src/legacy/resolve_type.dart)：`resolveTypeAliasDeclarations`；[values.dart](../test/legacy/fixtures/values.dart)：`genericAliases`；[behavior_test.dart](../test/legacy/behavior_test.dart)：`rejectedTypeAliases`。 |

## 空安全、推断与流分析

下表依赖[空安全][nnbd]、[推断][inference]和[流分析][flow]补充文档；旧草案章节不能单独代表这些规则。Dart 3.9 的 sound-flow-analysis 门槛还依据[对应 SDK 特性表][features]与真实编译差分。

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| [3.7 基于界限的推断][bounds-inference] | 部分实现 | 在向下、水平及最终求解阶段，由已收集的下界与声明上界继续生成约束；覆盖 List、可空类型与非泛型函数签名，函数参数保持逆变。按参数声明顺序求解，前阶段已固定的解不变；调用库版本控制普通泛型调用、普通及 const 泛型构造和类别名。完整 F-bound、泛型父接口和其余约束算法仍缺，细则见[函数](functions.md#基于界限的推断)。 | [generics.dart](../lib/src/legacy/frontend/generics.dart)：`constrainGenericBound`、`genericConstraintSolution`；[values.dart](../test/legacy/fixtures/values.dart)：`genericBoundInference`、`metadataValues`；[behavior_test.dart](../test/legacy/behavior_test.dart)：`bounds-3.6.dart` / `bounds-3.7.dart`、泛型拒例。 |
| 可空与非空类型 | 部分实现 | 识别 `T?`，拒绝未经提升的可空成员、索引和算术消费；`== null` 真分支不直接把类型变成 `Null`；空断言的结果去除空性，Null 结果为 Never，dynamic 保留 dynamic。空短路访问按非空接收者检查链内操作，再将结果变为可空；类型限定的静态访问不添加空性。 | [types.dart](../lib/src/legacy/types.dart)：`nullableType`、`typeCanBeNull`；[flow.dart](../lib/src/legacy/flow.dart)：`flowNull`；[values.dart](../test/legacy/fixtures/values.dart)：`flowBranches`、`nullAssertionValues`、`nullAwareValues`；[behavior_test.dart](../test/legacy/behavior_test.dart)：`rejected`。 |
| 空安全底类型 `Never` | 部分实现 | 作为子类型与合并的底类型，`Never?` 规范化为 `Null`；空 `List<Never>` 可协变读取，写入仍按实际元素类型检查。没有 `Never` 实例；未初始化的普通及 late 局部存储不触发 Never 求值，读取仍受赋值及延迟初始化规则约束。完整类型参数及交集类型规则尚缺。 | [types.dart](../lib/src/legacy/types.dart)：`typeIsSubtype`、`joinTypes`、`nullableType`；[runtime.dart](../lib/src/legacy/runtime.dart)：`rtTypeSubtype`、`rtValueMatches`；[values.dart](../test/legacy/fixtures/values.dart)：`neverContexts`；[behavior_test.dart](../test/legacy/behavior_test.dart)：`failingValues`。 |
| 隐式赋值兼容 | 部分实现 | `Object`、可空类型不能直接下转为具体值；`dynamic` 可以检查转换。赋值目标的转换与表达式自身结果类型分别处理；赋值边界先做[可调用对象的隐式提取](functions.md#可调用对象)，表达式结果保留所得函数类型；`??=` 再合并非空读取类型与 RHS 类型，目标存储的装箱或检查转换不改变结果类型。 | [typing.dart](../lib/src/legacy/typing.dart)：`typingAssignable`；[frontend.dart](../lib/src/legacy/frontend.dart)：`feLowerAssignment`；[values.dart](../test/legacy/fixtures/values.dart)：`assignmentValues`、`staticContexts`、`coalescingAssignmentValues`。 |
| 局部与顶层推断、[匿名函数上下文][anonymous-inference] | 部分实现 | 从初始化表达式、List 元素及上下文推断；集合条件、循环与展开的所有元素类型参与推断，条件路径保留提升；空感知单元素接受可空上下文并以 NonNull 类型参与合并，过滤不向后传播变量提升；支持部分条件表达式和常量默认值。匿名函数省略参数使用对应签名参数，返回表达式获得期望结果上下文；Null/Never 参数上下文推为 Object?，void 结果上下文仍约束块体 return 的合法性。当前同步闭包可推断捕获表达式；泛型直接调用支持已有类型模型的部分上下文与实参约束，并按[回调水平推断](functions.md#回调水平推断)分阶段解出回调参数；schema 的最大/最小闭包分别以 Object?/Never 代入未知部分并反转函数参数方向。具体边界见[函数](functions.md#泛型直接调用)。完整约束求解与覆盖推断尚缺。 | [frontend.dart](../lib/src/legacy/frontend.dart)：`feLowerHint`、`feLowerFunctionExpression`、`feInferGlobal`；[constants.dart](../lib/src/legacy/constants.dart)：`evaluateConstant`；[behavior_test.dart](../test/legacy/behavior_test.dart)：`program/anonymousFunctions()`、`rejected`；[values.dart](../test/legacy/fixtures/values.dart)：`constantLists`、`staticContexts`。 |
| 类型提升与撤销 | 部分实现 | 按局部绑定身份处理 `is`、空检查、逻辑分支、退出、赋值及循环写入；`??=` 的非空路径与实际写入路径分别提升、合流；直接局部空断言在检查后提升，读取类型与声明存储类型分开。可变 late 局部可由初始化器结果提升；late final 初始化器不建立此提升。闭包捕获按声明身份检查写入：被闭包写入的绑定不提升，未显式写入的捕获可保留外围提升。模式声明/赋值的上下文 schema、switch 语句/表达式和 if-case 的类型、对象和 List 模式、List/泛型类/别名实参及 Null 模式变量推导及提升边界见[模式](patterns.md)；字段提升及完整闭包流规则仍缺。 | [binding.dart](../lib/src/legacy/binding.dart)：`bindFunctionLocals`；[flow.dart](../lib/src/legacy/flow.dart)：`flowPromote`、`flowExclude`、`flowWrite`、`flowDemote`；[values.dart](../test/legacy/fixtures/values.dart)：`flowBranches`、`flowAssignments`、`flowContexts`、`coalescingAssignmentFlow`、`nullAssertionValues`、`lateValues`。 |
| 确定赋值、确定未赋值与可达性 | 部分实现 | 分别跟踪局部可读与 final 首次可写事实，合并分支、循环和标签退出；不可达代码仍检查读写；空短路访问与级联分开合并执行/跳过路径的写入事实。`Never` 调用终止正常路径，非空结果不能正常落空。3.9 起才以非空静态类型、总真 `is` 及 Null/非空类型不匹配判定相应死边；不把任意不相交的 `int is String` 分支当作 DFA 豁免。版本来自函数或全局初始化的拥有文件；捕获继承声明点的已赋值事实，闭包写入不反向确立外层赋值，非 late 的捕获 final 不允许赋值；late 的赋值和失败边界见[变量](variables.md)；同步 try/catch/finally 合流见[语句](statements.md)；异步及完整闭包控制流仍缺。 | [flow.dart](../lib/src/legacy/flow.dart)：`FlowState`、`flowJoin`；[frontend.dart](../lib/src/legacy/frontend.dart)：`feReadLocal`、`feWriteLvalue`、`feCall`；[values.dart](../test/legacy/fixtures/values.dart)：`finalAssignments`、`neverWrapper`、`nullAwareValues`；[behavior_test.dart](../test/legacy/behavior_test.dart)：`version-imports.dart`、`rejected`。 |
| [实例字段推断][field-inference] | 部分实现 | 普通字段使用父接口的组合 getter/setter 签名；可写字段的读写类型必须一致，只有 getter 的字段使用读取类型。声明初始化器按推得类型检查；无父接口和声明初始化器时取 dynamic，构造器赋值不参与推断。字段形参及初始化义务使用最终字段类型，late 访问器同步更新。非主构造器类的未覆盖字段支持字面量、常量引用、已有常量类型运算（含 `as`/`is`/`is!`）、List、函数 tear-off 和直接构造结果的推断；Null 推为 dynamic。普通函数调用、实例成员依赖、主构造器字段初始化器和一般声明依赖图仍缺。 | [classes.dart](../lib/src/legacy/frontend/classes.dart) `checkClassInterfaces()`；[constants.dart](../lib/src/legacy/constants.dart) `inferConstantType()`；[initialization.dart](../lib/src/legacy/initialization.dart) `checkConstructorInitializers()`；[values.dart](../test/legacy/fixtures/values.dart) `interfaceValues()`；[behavior_test.dart](../test/legacy/behavior_test.dart) `rejectedFieldInference`、`failingValues`。 |
| `num` 与数值推断 | 部分实现 | `num` 是 `int` 与 `double` 的共同上界；`int + dynamic` 推断 `num`，double 数值参与算术时传播 double，`/` 返回 double，`~/` 返回 int；动态左操作数结果保留 dynamic。支持 double 上下文中可精确表示的整数字面量、可空值、泛型边界与 List 协变检查；没有普通 int 变量到 double 的隐式转换。 | [typing.dart](../lib/src/legacy/typing.dart)：`typingBinary`、`typingBinaryContext`、`typingUnary`；[values.dart](../test/legacy/fixtures/values.dart)：`staticContexts`、`floatingContexts`。 |

## 尚缺与待核验

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §20.8 `FutureOr` | 未实现 | `Future`、`FutureOr`、异步类型规则未接入。 | [types.dart](../lib/src/legacy/types.dart) 尚无对应类型；尚无行为验证。 |
| Records 与扩展类型 | 未实现 | 记录类型、扩展类型及相应关系未实现；已有 `Never` 和有限不相交类型分析不代表这些规则成立。 | [types.dart](../lib/src/legacy/types.dart)、[resolve_type.dart](../lib/src/legacy/resolve_type.dart)。 |
| 完整类型规范及诊断覆盖 | 待核对 | 完整类型关系、推断及诊断的一致性覆盖尚缺。 | [behavior_test.dart](../test/legacy/behavior_test.dart) 为差分入口。 |

## 验证方式

[behavior_test.dart](../test/legacy/behavior_test.dart) 将行为程序分别交给 SDK 与原生 dartc 编译执行，并检查应拒绝的源码。
[values.dart](../test/legacy/fixtures/values.dart) 用实际 List 推断、类型检查、成员消费和副作用使静态类型区别可观察。
已实现类型的显式 cast、隐式动态转换、布尔条件、空断言和协变写入失败抛出可捕获的 [TypeError](https://api.dart.dev/dart-core/TypeError-class.html)，保留首次轨迹并执行 finally；`failingValues` 与 SDK 对照捕获及继续执行，`uncaught` 验证未捕获清理，`exceptionRoots` 验证运行时根恢复和 GC 保活。错误文本尚未包含源值、目标类型或参数名；一般动态成员分派和其他自动错误的缺口见[语句](statements.md)。

类型参数注解在整组参数作用域中检查，typedef 自身注解仍取外围作用域。元数据构造和列表类型参数按展开后的实际类型依赖检查常量资格：擦除参数的 `Phantom<T> = Marker` 可用于注解构造及 `const <Phantom<T>>[]`，仍依赖 T 的 `const <T>[]` 被拒绝。SDK 3.13.7 CFE 接受前一种常量 List 注解，而 analyzer 报错；行为用例放在生成的库程序中保留这一差异，不将它解释为规范给出相反结论。

SDK 3.13.7 对跨库带前缀的泛型别名到非泛型类的 `p.A<int>()` 隐式构造报类型实参数量错误，而同库调用、显式 `new p.A<int>()` 及命名形式被接受。固定 2.13 规则允许 qualified alias 用于实例创建；此差异待核对，不据此增加前缀名称分支或判定该形式在语言上非法。

非泛型可空类别名的隐式命名及 `.new` 调用，SDK 3.13.7 的 CFE 与 analyzer 对结果 nullability 的处理有差异：CFE 保留可空结果，未命名、显式 `new` 和 `const` 路径返回非空结果；analyzer 将这些结果均按非空类处理。泛型可空类别名的 CFE 行为又有区别：省略实参的调用结果保持可空，显式实参的调用结果非空。dartc 尚未完整区分这些构造结果。固定的 2.13/2.15 特性文档未单独解释这组差异，不据此宣称规范给出同样区分。

数值运算与 `remainder` 的上下文按[空安全数值推断规则](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/number-operation-typing.md#improved-context-type)传播：接收者无上下文；结果约束结合接收者类型决定右实参上下文。`/` 与 `~/` 的返回类型独立于右实参，不沿用这项特殊收窄。验证入口为 `floatingContexts` 和 `rejected`。

[draft]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex
[pdf]: https://dart.dev/to/spec-draft
[entry]: https://dart.dev/resources/language/spec
[nnbd]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md
[inference]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md
[bounds-inference]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/inference-using-bounds/design-document.md
[flow]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/flow-analysis.md

[features]: https://github.com/dart-lang/sdk/blob/3.13.5/tools/experimental_features.yaml

[aliases]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.13/nonfunction-type-aliases/feature-specification.md
[function-types]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L22447-L22501
[anonymous-inference]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md#L263-L372

[type-parameters]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L7413-L7478
[instantiate-to-bound]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L7882-L8357
[wildcards]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/wildcard-variables/feature-specification.md#L114-L126
[super-bounded-types]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L7685-L7880

[field-inference]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md#L219-L260

## FFI 类型与原生导出声明

依据 SDK [`dart:ffi` 原生类型][ffi-native]及 [`NativeFunction<T>`][ffi-function]，`Int8`、`Uint8`、`Int16`、`Uint16`、`Int32`、`Uint32`、`Int64`、`Uint64`、`IntPtr`、`UintPtr`、`Float`、`Double`、`Bool`、`Void` 和 `Pointer<T>` 保留不同类型身份；不能把 `Int64` 当作 Dart `int` 的类型别名。Pointer 的原生类型上界与 NativeFunction 的 Function 上界按普通类型应用检查。结构体、联合体及其他 FFI API 仍有缺口。

`package:dartc/export.dart` 的普通 const `Export<T>` 注解在求值后按声明身份消费。函数需要闭合、必需位置参数的 FFI 签名，Dart 函数的 int/double/bool/Pointer 结果及参数须与映射相符；const 标量数据需要对应的 FFI 数据类型。全部实际加载库中的显式注解形成导出根；顶层函数和静态方法可使用多个不同符号，顶层与静态 const 数据使用同一命名规则。省略 symbol 时取声明名；空名、NUL 和重复外部符号拒绝。未完成的非 const 数据、实例接收者、泛型调用、getter/setter 等导出入口明确诊断。目标位宽转换、运行时上下文、异常边界及链接行为由后端验证，不从 Dart int 猜测 C 位宽。

[frontend.dart](../lib/src/legacy/frontend.dart) 的 `feCheckExport()`、[ffi.dart](../lib/src/legacy/ffi.dart) 和 [exports.dart](../lib/src/legacy/exports.dart) 拥有检查及交接结果；[behavior_test.dart](../test/legacy/behavior_test.dart) 的 `native-annotation-imports.dart`、`rejectedNativeAnnotations` 拥有源语言行为，真正的 C ABI、数据符号和头文件验证归 [library_test.dart](../test/legacy/library_test.dart)。通用 metadata 接受不代表库输出已追平可执行产物的 AOT 能力。

macOS 与 Linux 的 ARM64/x64 后端为 object、static、dylib 输出实现上述整数类型、Float/Double、Bool、Pointer 参数及结果和 Void 结果；支持分别耗尽整数与浮点寄存器后的栈参数、递归内部调用，以及嵌套指针和原生函数指针的传递。导出常量支持整数、浮点和布尔类型；目标位宽转换仅作用于导出副本，不改变 Dart 常量。macOS 使用 Mach-O，Linux 使用 ELF64 及 GNU ar，共享库分别为 .dylib 和 .so。macOS ARM64、Linux ARM64/x64 已通过真实 C/C++ 调用；macOS x64 已交叉链接，同一 System V 标量适配在 Linux x64 执行，macOS x64 宿主执行仍待补齐。结构体/联合体按值传递、可写数据、TLS、对象句柄、托管堆、异常和调度边界尚未完成；不能把已有可执行产物的能力当作库输出已支持的证据。

[header.dart](../lib/src/legacy/header.dart) 从 CheckedExport 生成固定宽度 C 类型、const 数据和函数指针声明，包含 C++ linkage。非 C 标识符、保留字及生成器保留前缀按 UTF-16 单元编码成无冲突 C 别名，Clang/GCC asm 标签保留外部符号；二进制符号和文件内容按 UTF-8 编码。抽象 NativeType、SizedNativeType、Handle 等指针目标的 C 声明仍缺，不隐式当作 void 指针。[library_test.dart](../test/legacy/library_test.dart) 通过 C11、C++17 的真实编译与执行验证头文件、标量边界值、26 个混合参数、函数指针、Unicode/保留名、只读常量和库文件迁移后的链接与 dlopen/dlsym；[native_library.dart](../test/legacy/fixtures/native_library.dart) 与 [native_library.c](../test/legacy/fixtures/native_library.c) 提供同一 ABI 行为用例。

[ffi-native]: https://api.dart.dev/stable/3.13.7/dart-ffi/NativeType-class.html
[ffi-function]: https://api.dart.dev/stable/3.13.7/dart-ffi/NativeFunction-class.html
