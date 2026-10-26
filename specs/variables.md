# 变量：§8 Variables

按[固定草案源码](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)的 §8、§8.1、§8.2 建立索引；条款目录见[官方草案 PDF](https://dart.dev/to/spec-draft)。
兼容验证基线为 Dart SDK 3.13.5；下表只描述现有实现，不能据此认定整章符合规范。

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §8 变量声明及初始化 | 部分实现 | 支持显式类型、`var`、逗号分隔声明；类型范围受当前类型系统限制。 | [parser.dart](../lib/src/parser.dart) `parserVariablesRest()`；[behavior_test.dart](../test/behavior_test.dart) `program/main()` |
| §8 局部变量绑定 | 部分实现 | 有独立绑定 ID、块与循环作用域、遮蔽及重复声明检查；闭包捕获未实现。 | [binding.dart](../lib/src/binding.dart) `bindingDeclare()`、`bindingLookup()`；[values.dart](../test/fixtures/values.dart) `localBindings()` |
| §8 声明前引用 | 部分实现 | 预收集局部名字，结合确定赋值状态拒绝声明前读取；复杂控制流尚非完整流分析。 | [binding.dart](../lib/src/binding.dart) `bindingCollect()`；[frontend.dart](../lib/src/frontend.dart) `feLocalSlot()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §8 初始化类型及赋值 | 部分实现 | 区分声明类型、提升后的读取类型和存储表示，执行必要的装箱与检查；完整类型推断见[类型追踪](types.md)。 | [frontend.dart](../lib/src/frontend.dart) `feLowerVariable()`、`feConvertValue()`；[values.dart](../test/fixtures/values.dart) `flowAssignments()`、`staticContexts()` |
| §8 确定赋值与确定未赋值 | 部分实现 | 分别跟踪可读和允许 final 首次赋值的事实；按局部可达性合并分支，覆盖现有循环、标签和返回。父路径不可达时仍检查局部分支中的读写；异常、闭包和模式变量未覆盖。 | [flow.dart](../lib/src/flow.dart) `flowJoin()`、`flowSplit()`、`flowUnsplit()`；[frontend.dart](../lib/src/frontend.dart) `feReadLocal()`；[values.dart](../test/fixtures/values.dart) `flowContexts()`、`neverContexts()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §8 无初始值的声明 | 部分实现 | 非 final 的可空或动态局部变量取 null；未初始化的 final 即使可空也不能读取。库级 final 和非空变量要求初始化；现有类字段须由声明或受支持构造器初始化。完整初始化形式仍缺失。 | [frontend.dart](../lib/src/frontend.dart) `feLowerVariable()`；[initialization.dart](../lib/src/initialization.dart) `checkInitializers()`；[values.dart](../test/fixtures/values.dart) `flowContexts()`、`finalAssignments()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §8 局部 `final` | 部分实现 | 支持声明后首次赋值、互斥分支赋值；重复写、增减和可能重复的循环外变量写入被拒绝。循环体内新声明可各自初始化；RHS 求值后的写入也重新检查，防止嵌套赋值绕过限制。`late final` 未实现。 | [binding.dart](../lib/src/binding.dart) `LocalVariable.finalVariable`；[frontend.dart](../lib/src/frontend.dart) `feWriteLvalue()`；[flow.dart](../lib/src/flow.dart) `flowWrite()`、`flowDemote()`；[values.dart](../test/fixtures/values.dart) `finalAssignments()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §8 库级及字段 `final` | 部分实现 | final 存储没有隐式 setter；库变量和实例字段可与显式 setter 配对，此时赋值调用 setter 而不修改 final 存储。已检查缺少初始化和重复初始化；静态字段及完整构造器初始化链未实现。 | [symbols.dart](../lib/src/symbols.dart) `declareAccessor()`；[frontend.dart](../lib/src/frontend.dart) `feLowerLvalue()`；[initialization.dart](../lib/src/initialization.dart) `checkInitializers()`；[values.dart](../test/fixtures/values.dart) `finalContexts()`、`accessorValues()`、`topAccessorValues()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §8 `const` 变量 | 部分实现 | 要求初始化且常量存储只读；库级 const 可与显式 setter 配对，写入调用 setter，不改变常量读取。支持标量、嵌套 List 及部分常量运算，非完整常量语言。 | [constants.dart](../lib/src/constants.dart) `evaluateConstant()`；[symbols.dart](../lib/src/symbols.dart) `declareAccessor()`；[values.dart](../test/fixtures/values.dart) `constantLists()`、`topAccessorValues()` |
| §8 常量绑定与作用域 | 部分实现 | 局部和库级常量独立绑定；参数默认值在声明库作用域求值，检查引用及循环。 | [constants.dart](../lib/src/constants.dart) `ConstantContext`、`evaluateGlobalConstant()`；[values.dart](../test/fixtures/values.dart) `positionalArguments()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §8 常量引用与对象只读 | 部分实现 | 常量 List 规范化并冻结，元素写入及改变长度失败；final 只限制变量重新赋值，所指向的普通 List 仍可修改。两类约束不能混同。 | [runtime.dart](../lib/src/runtime.dart) `rtListFreeze()`、`rtListSet()`；[values.dart](../test/fixtures/values.dart) `finalAssignments()`、`constantLists()`；[behavior_test.dart](../test/behavior_test.dart) `failingValues` |
| §8 `late` 声明 | 未实现 | 无 `late` AST 状态、延迟局部初始化或写入次数检查。 | [ast.dart](../lib/src/ast.dart) `AstVariable`；[parser.dart](../lib/src/parser.dart) `parserModifier()`；尚无验证入口 |
| §8.1 库变量隐式访问器 | 部分实现 | 库变量区分读取、写入与初始化状态；可变变量已有隐式写入，不能再配显式 setter，final/const 没有隐式写入。静态字段及完整访问器约束未实现。 | [symbols.dart](../lib/src/symbols.dart) `declareAccessor()`；[frontend.dart](../lib/src/frontend.dart) `fePrepareGlobals()`、`feGenerateGlobals()`；[values.dart](../test/fixtures/values.dart) `topAccessorValues()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §8.2 首次读取初始化 | 部分实现 | 普通库变量首次读取初始化并缓存；写入可跳过初始化。运行库内部原始全局有独立启动约定。 | [frontend.dart](../lib/src/frontend.dart) `feLoadGlobalValue()`、`feGenerateGlobals()`；[values.dart](../test/fixtures/values.dart) `conditionContexts()` 的 `lazyCondition` |
| §8.2 初始化重入 | 部分实现 | 有正在初始化状态和错误终止；尚无规范要求的异常对象及恢复传播。 | [frontend.dart](../lib/src/frontend.dart) `feGenerateGlobals()`；[runtime.dart](../lib/src/runtime.dart) `rtInitializationError()`；缺少独立重入行为验证 |
| §8.2 `late` getter/setter | 未实现 | 未初始化读取、`late final` 再写入及其运行时错误尚未实现。 | [ast.dart](../lib/src/ast.dart) `AstVariable`；尚无验证入口 |
| §8 静态及实例变量规则 | 部分实现 | 有普通实例字段；静态字段、`covariant` 字段和完整初始化规则见[类追踪](classes.md)。 | [frontend.dart](../lib/src/frontend.dart) `feCollectDeclarations()`；[values.dart](../test/fixtures/values.dart) `Cell`、`assignmentValues()` |

实现边界：

- `const` 对象的不可变性与 `final` 变量只写一次分别检查。
- 库变量的惰性初始化不代表已经支持 `late`。
- `Never` 调用参与可达性；底类型和提升边界见[类型追踪](types.md)，不能据此推定完整流分析已完成。
- 当前运行时失败以诊断和退出结束，尚无可捕获的 Dart 异常。

验证入口采用真实编译、执行与 SDK 输出对照；负例分别由 `rejected` 和 `failingValues` 管理。
闭包捕获、模式变量、异常路径及完整初始化形式仍需各自的行为验证。
