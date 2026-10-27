# 类型与泛型

兼容目标为 Dart 3.13.5。本页追踪语言能力，不把有限样例通过等同于规范符合性。
章节号取自固定版本的[语言规范草案][draft]；[PDF][pdf]便于阅读，但链接内容可能更新。
[官方规范入口][entry]说明 Dart 3 规范仍未覆盖当前全部语言特性，因此还需参考补充文档与对应 SDK 行为。

## 依据与状态

- [空安全提案][nnbd]位于官方 `accepted/2.12`；[类型推断][inference]和[流分析][flow]为同一版本的官方补充文档，文档自身仍标为 Draft。
- 状态含义统一见[总览](README.md#状态与证据)，当前各行只描述已有子集和已知缺口。
- 实现入口指当前拥有者；验证入口指真实编译、执行或编译拒绝的已有测试，不表示整个章节已验证。
- 对象表示、TypeRef 布局、GC 与引导机制见[架构设计](../doc/architecture.md)；表达式规则见[表达式](expressions.md)。

## 当前实现

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §20.1 静态类型 | 部分实现 | 区分 `int`、`num`、`bool`、`String`、`Null`、`Never`、`Object`、`dynamic`、`void`、可空类型、`List<T>`、函数签名、Function 上界和已声明类；局部 value 声明遮蔽同名类型/prefix 时拒绝，函数签名不看 body locals；尚非完整 Dart 类型模型。 | [types.dart](../lib/src/types.dart)：`DartType`；[values.dart](../test/fixtures/values.dart)：`typeChecks`、`staticContexts`、`neverContexts`；[behavior_test.dart](../test/behavior_test.dart)：`program/localFunctions`、`rejected`。 |
| §20.1 类型名解析 | 部分实现 | 按声明库、导入前缀解析类型，检查已支持类型的参数数量；没有通用类型参数作用域。 | [resolve_type.dart](../lib/src/resolve_type.dart)：`resolveType`；[behavior_test.dart](../test/behavior_test.dart)：`libraries`、`rejected`。 |
| §20.2 动态类型系统 | 部分实现 | `is`、`is!`、`as` 与隐式动态转换使用实际运行时类型；覆盖嵌套 List、类、函数签名与可空类型；不含一般动态成员分派或 dynamic 函数值调用。 | [runtime.dart](../lib/src/runtime.dart)：`rtValueMatches`、`rtValueCast`；[values.dart](../test/fixtures/values.dart)：`typeChecks`；[behavior_test.dart](../test/behavior_test.dart)：`failingValues`。 |
| §20.4 子类型 | 部分实现 | 有 `Never` 底类型、`int <: num`、空性、支持类型到 `Object` 的关系、List 协变及函数参数逆变/结果协变；类之间仅识别同一声明，尚无继承层次的子类型计算。 | [types.dart](../lib/src/types.dart)：`typeIsSubtype`；[runtime.dart](../lib/src/runtime.dart)：`rtTypeSubtype`；[values.dart](../test/fixtures/values.dart)：`typeChecks`、`staticContexts`、`neverContexts`。 |
| [§20.5–20.6 函数类型与 `Function`][function-types] | 部分实现 | 顶层与非捕获局部函数共用结构签名、参数逆变/返回协变、Function 上界和运行时测试/转换/List 写入检查；局部缺省结果从 typed body 推断，声明身份不充当类型身份。源函数值签名仍限非泛型必需位置参数；可选/命名/泛型值签名、匿名函数上下文推断和捕获未实现；裸 Function 尚不能直接调用。 | [types.dart](../lib/src/types.dart) `functionType()`、`typeIsSubtype()`；[frontend.dart](../lib/src/frontend.dart) `feInferLocalResult()`；[runtime.dart](../lib/src/runtime.dart) `rtTypeSubtype()`；[behavior_test.dart](../test/behavior_test.dart) `program/localFunctions()`、`failingValues` |
| §20.7 `dynamic` | 部分实现 | 独立语义类型；可隐式转入具体类型并执行运行时检查，不能与 `Object` 或声明存储类型混用；仅实现部分动态运算。 | [typing.dart](../lib/src/typing.dart)：`typingAssignable`、`typingBinary`；[frontend.dart](../lib/src/frontend.dart)：`feConvertValue`；[values.dart](../test/fixtures/values.dart)：`valueContexts`、`staticContexts`。 |
| §20.9 `void` | 部分实现 | 限制值消费；`void` 上下文可保留实际返回负载，支持 `List<void>`；显式 `as` 可检查并取得实际负载；局部仅向严格子类型提升，`as dynamic` / `as Object?` 不改变原 void 读取类型；普通隐式消费仍拒绝。泛型函数类型和异步语义相关规则尚缺。 | [typing.dart](../lib/src/typing.dart)：`typingAssignable`；[frontend.dart](../lib/src/frontend.dart)：`feConvertValue`；[values.dart](../test/fixtures/values.dart)：`valueContexts`。 |
| §20.10 参数化类型 | 部分实现 | 保留完整嵌套 `List<T>` 实际类型；协变视图写入按底层元素类型检查。`Pointer<T>` 仅有受限 FFI 语义，不能视为一般泛型实现。 | [types.dart](../lib/src/types.dart)：`listType`；[runtime.dart](../lib/src/runtime.dart)：`rtListGet`、`rtListSet`、`rtListAdd`；[values.dart](../test/fixtures/values.dart)：`staticContexts`、`typeChecks`。 |
| §20.10.2 最小上界 | 部分实现 | 对支持类型、空性、嵌套 List 和函数签名求公共类型，区分 `void` 与 `dynamic`；不是完整约束求解或所有 Dart 类型的 LUB 算法。 | [types.dart](../lib/src/types.dart)：`joinTypes`；[values.dart](../test/fixtures/values.dart)：`staticContexts`、`coalescingContexts`、`functionValues`。 |
| §20.11 相同类型 | 部分实现 | 已支持类型按结构复用类型身份；运行时检查保留实际 List 参数和函数签名。尚无一般 `Type` 值及其公开操作。 | [types.dart](../lib/src/types.dart)：`listType`、`nullableType`、`classType`、`functionType`；[values.dart](../test/fixtures/values.dart)：`constantLists`、`typeChecks`。 |
| §15 泛型 | 部分实现 | 能使用内建 `List<T>`；不能声明泛型类、泛型函数或方法，不能据此宣布泛型章节完成。 | [resolve_type.dart](../lib/src/resolve_type.dart)：`resolveType`；[values.dart](../test/fixtures/values.dart)：`typeChecks`。 |
| §15.1 型变 | 部分实现 | List 元素参数有协变关系和运行时写入检查；用户声明的型变、覆盖和 `covariant` 参数规则未实现。 | [types.dart](../lib/src/types.dart)：`typeIsSubtype`；[runtime.dart](../lib/src/runtime.dart)：`rtListSet`；[behavior_test.dart](../test/behavior_test.dart)：`failingValues`。 |
| [§20.3 类型别名][aliases] | 部分实现 | 类型注解中支持非泛型别名、声明库解析、前向展开与循环拒绝；普通 RHS 要求语言版本至少 2.13，2.12 仅接受直接且非可空的函数类型 RHS。Function 不能作类型别名名。泛型别名及别名作为构造/静态调用目标尚缺；FFI 别名保留独立原生签名。 | [symbols.dart](../lib/src/symbols.dart)：`TypeAlias`；[resolve_type.dart](../lib/src/resolve_type.dart)：`resolveType`；[behavior_test.dart](../test/behavior_test.dart)：`function-imports.dart`、`rejected`；[library_test.dart](../test/library_test.dart)。 |

## 空安全、推断与流分析

下表依赖[空安全][nnbd]、[推断][inference]和[流分析][flow]补充文档；旧草案章节不能单独代表这些规则。Dart 3.9 的 sound-flow-analysis 门槛还依据[对应 SDK 特性表][features]与真实编译差分。

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| 可空与非空类型 | 部分实现 | 识别 `T?`，拒绝未经提升的可空成员、索引和算术消费；`== null` 真分支不直接把类型变成 `Null`；空断言的结果去除空性，Null 结果为 Never，dynamic 保留 dynamic。 | [types.dart](../lib/src/types.dart)：`nullableType`、`typeCanBeNull`；[flow.dart](../lib/src/flow.dart)：`flowNull`；[values.dart](../test/fixtures/values.dart)：`flowBranches`、`nullAssertionValues`；[behavior_test.dart](../test/behavior_test.dart)：`rejected`。 |
| 空安全底类型 `Never` | 部分实现 | 作为子类型与合并的底类型，`Never?` 规范化为 `Null`；空 `List<Never>` 可协变读取，写入仍按实际元素类型检查。没有 `Never` 实例；完整类型参数及交集类型规则尚缺。 | [types.dart](../lib/src/types.dart)：`typeIsSubtype`、`joinTypes`、`nullableType`；[runtime.dart](../lib/src/runtime.dart)：`rtTypeSubtype`、`rtValueMatches`；[values.dart](../test/fixtures/values.dart)：`neverContexts`；[behavior_test.dart](../test/behavior_test.dart)：`failingValues`。 |
| 隐式赋值兼容 | 部分实现 | `Object`、可空类型不能直接下转为具体值；`dynamic` 可以检查转换。赋值目标的转换与表达式自身结果类型分别处理；`??=` 合并非空读取类型与原 RHS 类型，写入转换不改变结果类型。 | [typing.dart](../lib/src/typing.dart)：`typingAssignable`；[frontend.dart](../lib/src/frontend.dart)：`feLowerAssignment`；[values.dart](../test/fixtures/values.dart)：`assignmentValues`、`staticContexts`、`coalescingAssignmentValues`。 |
| 局部与顶层推断 | 部分实现 | 从初始化表达式、List 元素及上下文推断；支持部分条件表达式和常量默认值。尚无泛型约束求解、闭包参数及覆盖推断。 | [frontend.dart](../lib/src/frontend.dart)：`feLowerHint`、`feLowerVariable`、`feInferGlobal`；[constants.dart](../lib/src/constants.dart)：`evaluateConstant`；[values.dart](../test/fixtures/values.dart)：`constantLists`、`staticContexts`。 |
| 类型提升与撤销 | 部分实现 | 按局部绑定身份处理 `is`、空检查、逻辑分支、退出、赋值及循环写入；`??=` 的非空路径与实际写入路径分别提升、合流；直接局部空断言在检查后提升，读取类型与声明存储类型分开。闭包捕获、字段提升和模式提升未实现。 | [binding.dart](../lib/src/binding.dart)：`bindFunctionLocals`；[flow.dart](../lib/src/flow.dart)：`flowPromote`、`flowExclude`、`flowWrite`、`flowDemote`；[values.dart](../test/fixtures/values.dart)：`flowBranches`、`flowAssignments`、`flowContexts`、`coalescingAssignmentFlow`、`nullAssertionValues`。 |
| 确定赋值、确定未赋值与可达性 | 部分实现 | 分别跟踪局部可读与 final 首次可写事实，合并分支、循环和标签退出；不可达代码仍检查读写。`Never` 调用终止正常路径，非空结果不能正常落空。3.9 起才以非空静态类型、总真 `is` 及 Null/非空类型不匹配判定相应死边；不把任意不相交的 `int is String` 分支当作 DFA 豁免。版本来自函数或全局初始化的拥有文件；未覆盖异常、闭包及异步控制流。 | [flow.dart](../lib/src/flow.dart)：`FlowState`、`flowJoin`；[frontend.dart](../lib/src/frontend.dart)：`feReadLocal`、`feWriteLvalue`、`feCall`；[values.dart](../test/fixtures/values.dart)：`finalAssignments`、`neverWrapper`；[behavior_test.dart](../test/behavior_test.dart)：`version-imports.dart`、`rejected`。 |
| `num` 与数值推断 | 部分实现 | `num` 与 `int` 独立；`int + dynamic` 推断 `num`，动态左操作数结果保留 `dynamic`，`~/` 和整数位运算有独立规则。运行时当前仅有整数数值。 | [typing.dart](../lib/src/typing.dart)：`typingBinary`、`typingUnary`；[values.dart](../test/fixtures/values.dart)：`staticContexts`。 |

## 尚缺与待核验

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §15.2–15.3 超界类型与实例化到界 | 未实现 | 没有类型参数、边界或通用实例化算法。 | 后续扩展 [resolve_type.dart](../lib/src/resolve_type.dart)、[types.dart](../lib/src/types.dart)；尚无行为验证。 |
| §20.8 `FutureOr` | 未实现 | `Future`、`FutureOr`、异步类型规则未接入。 | [types.dart](../lib/src/types.dart) 尚无对应类型；尚无行为验证。 |
| 后续 Dart 3 类型 | 未实现 | 记录类型、扩展类型及相应关系未实现；已有 `Never` 和有限不相交类型分析不代表这些规则成立。 | 后续扩展 [types.dart](../lib/src/types.dart)、[resolve_type.dart](../lib/src/resolve_type.dart)。 |
| 完整类型规范及诊断覆盖 | 待核对 | 尚未逐条运行官方语言测试；现有有限类型关系和推断必须继续与规范对照。 | [behavior_test.dart](../test/behavior_test.dart) 为当前差分入口；原生自举只验证构建链，不证明类型系统完整。 |

## 验证方式

[behavior_test.dart](../test/behavior_test.dart) 将行为程序分别交给 SDK 与原生 dartc 编译执行，并检查应拒绝的源码。
[values.dart](../test/fixtures/values.dart) 用实际 List 推断、类型检查、成员消费和副作用使静态类型区别可观察。
运行时失败目前主要以进程退出表示；错误对象、可捕获异常及完整诊断兼容仍需单独实现和验证。
修改状态时应同时给出拥有者和实际行为入口，不以编译器成功自编译替代语言验收。

[draft]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex
[pdf]: https://dart.dev/to/spec-draft
[entry]: https://dart.dev/resources/language/spec
[nnbd]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md
[inference]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md
[flow]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/flow-analysis.md

[features]: https://github.com/dart-lang/sdk/blob/3.13.5/tools/experimental_features.yaml

[aliases]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.13/nonfunction-type-aliases/feature-specification.md
[function-types]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L20734-L20783
