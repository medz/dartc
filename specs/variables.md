# 变量：§8 Variables

按[固定草案源码](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)的 §8、§8.1、§8.2 建立索引；条款目录见[官方草案 PDF](https://dart.dev/to/spec-draft)。
兼容验证基线为 Dart SDK 3.13.5；下表只描述现有实现，不能据此认定整章符合规范。

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §8 变量声明及初始化 | 部分实现 | 支持显式类型、`var`、逗号分隔声明；类型范围受当前类型系统限制。 | [parser.dart](../lib/src/parser.dart) `parserVariablesRest()`；[behavior_test.dart](../test/behavior_test.dart) `program/main()` |
| §8 局部变量绑定 | 部分实现 | 有独立绑定 ID、块与循环作用域、遮蔽及重复声明检查；闭包捕获未实现。 | [binding.dart](../lib/src/binding.dart) `bindingDeclare()`、`bindingLookup()`；[values.dart](../test/fixtures/values.dart) `localBindings()` |
| §8 声明前引用 | 部分实现 | 预收集局部名字，结合确定赋值状态拒绝声明前读取；复杂控制流尚非完整流分析。 | [binding.dart](../lib/src/binding.dart) `bindingCollect()`；[frontend.dart](../lib/src/frontend.dart) `feLocalSlot()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §8 初始化类型及赋值 | 部分实现 | 区分声明类型、提升后的读取类型和存储表示，执行必要的装箱与检查；完整类型推断见[类型追踪](types.md)。 | [frontend.dart](../lib/src/frontend.dart) `feLowerVariable()`、`feConvertValue()`；[values.dart](../test/fixtures/values.dart) `flowAssignments()`、`staticContexts()` |
| §8 确定赋值 | 部分实现 | 合并分支、循环及返回路径的赋值状态；尚未覆盖异常、闭包和模式变量。 | [flow.dart](../lib/src/flow.dart) `flowJoin()`；[values.dart](../test/fixtures/values.dart) `flowContexts()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §8 无初始值的声明 | 部分实现 | 局部可空或动态变量取 null，非空局部读取受确定赋值检查；库变量和字段的完整初始化诊断仍缺失。 | [frontend.dart](../lib/src/frontend.dart) `feLowerVariable()`、`feInferGlobal()`；[values.dart](../test/fixtures/values.dart) `flowContexts()` |
| §8 `final` | 部分实现 | 解析并保存修饰符；尚无一般的只写一次检查，不能把 `final` 当作已落实的只读约束。 | [parser.dart](../lib/src/parser.dart) `parserModifier()`；[binding.dart](../lib/src/binding.dart) `LocalVariable`；[frontend.dart](../lib/src/frontend.dart) `feLowerLvalue()`；缺少对应行为验证 |
| §8 `const` 变量 | 部分实现 | 要求初始化，求值并拒绝重新赋值；支持标量、嵌套 List 及部分常量运算，非完整常量语言。 | [constants.dart](../lib/src/constants.dart) `evaluateConstant()`；[frontend.dart](../lib/src/frontend.dart) `feLowerVariable()`；[values.dart](../test/fixtures/values.dart) `constantLists()` |
| §8 常量绑定与作用域 | 部分实现 | 局部和库级常量独立绑定；参数默认值在声明库作用域求值，检查引用及循环。 | [constants.dart](../lib/src/constants.dart) `ConstantContext`、`evaluateGlobalConstant()`；[values.dart](../test/fixtures/values.dart) `positionalArguments()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §8 常量引用与对象只读 | 部分实现 | 常量 List 规范化并冻结，元素写入及改变长度失败；普通 `final` 的引用约束仍缺失，两者不可混同。 | [constant_data.dart](../lib/src/constant_data.dart)；[runtime.dart](../lib/src/runtime.dart) `rtListFreeze()`、`rtListSet()`；[behavior_test.dart](../test/behavior_test.dart) `failingValues` |
| §8 `late` 声明 | 未实现 | 无 `late` AST 状态、延迟局部初始化或写入次数检查。 | [ast.dart](../lib/src/ast.dart) `AstVariable`；[parser.dart](../lib/src/parser.dart) `parserModifier()`；尚无验证入口 |
| §8.1 库变量隐式访问器 | 部分实现 | 可执行文件为普通库变量生成 getter、setter 和初始化状态；静态字段及完整访问器约束未实现。 | [frontend.dart](../lib/src/frontend.dart) `fePrepareGlobals()`、`feGenerateGlobals()`；[behavior_test.dart](../test/behavior_test.dart) `program` 的 `initial`、`spare` |
| §8.2 首次读取初始化 | 部分实现 | 普通库变量首次读取初始化并缓存；写入可跳过初始化。运行库内部原始全局有独立启动约定。 | [frontend.dart](../lib/src/frontend.dart) `feLoadGlobalValue()`、`feGenerateGlobals()`；[values.dart](../test/fixtures/values.dart) `conditionContexts()` 的 `lazyCondition` |
| §8.2 初始化重入 | 部分实现 | 有正在初始化状态和错误终止；尚无规范要求的异常对象及恢复传播。 | [frontend.dart](../lib/src/frontend.dart) `feGenerateGlobals()`；[runtime.dart](../lib/src/runtime.dart) `rtInitializationError()`；缺少独立重入行为验证 |
| §8.2 `late` getter/setter | 未实现 | 未初始化读取、`late final` 再写入及其运行时错误尚未实现。 | [ast.dart](../lib/src/ast.dart) `AstVariable`；尚无验证入口 |
| §8 静态及实例变量规则 | 部分实现 | 有普通实例字段；静态字段、`covariant` 字段和完整初始化规则见[类追踪](classes.md)。 | [frontend.dart](../lib/src/frontend.dart) `feCollectDeclarations()`；[values.dart](../test/fixtures/values.dart) `Cell`、`assignmentValues()` |

实现边界：

- `const` 对象的不可变性不代替 `final` 变量的赋值规则。
- 库变量的惰性初始化不代表已经支持 `late`。
- 当前运行时失败以诊断和退出结束，尚无可捕获的 Dart 异常。

验证入口采用真实编译、执行与 SDK 输出对照；负例分别由 `rejected` 和 `failingValues` 管理。
新增声明能力应先补变量状态及绑定，再接 lowering 和既有行为测试，避免只接受修饰符。
