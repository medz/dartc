# 语句

条件决定实际进入哪个块。返回结束当前路径，循环回边携带下一次迭代所需的变量值。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 块、空语句、表达式语句 | 同步块、空语句和已支持的表达式。 |
| 局部变量与同步局部函数 | 支持[局部变量](variables.md)和可递归调用、捕获外部变量的[局部函数](functions.md)。 |
| if/else、while、do、普通 for | 普通 if/else、while、do-while 和三段式 for。for 支持变量声明、表达式或空初始段，以及多个按序求值的更新表达式。每轮更新前为循环头声明的变量建立新绑定，闭包保留所捕获那一轮的绑定。见[循环闭包样本](../test/frontend/lowering/fixtures/closures.dart)。 |
| for-in | 支持同步迭代、局部变量声明、已有局部变量赋值和 record 模式。iterator 只读取一次，每轮先 moveNext 再 current；声明变量每轮建立新绑定，已有变量保持共享。break、continue 和异常保留 finally 执行。见[集合与迭代样本](../test/frontend/lowering/fixtures/collections.dart)。 dynamic 源先检查 Iterable 协议，元素按循环变量或模式的要求逐项转换。 |
| if-case、模式声明及循环头 | if-case 支持标量与 record 模式及守卫。局部声明和三段式 for 可使用 record 解构。见[模式](patterns.md)。 |
| switch、守卫、共享 case、隐式 break | 支持标量与 record 模式、when、default 和多个 case 共享的分支体。分支体正常结束时退出 switch。非穷尽类型未命中时继续执行 switch 后的语句。见[switch 语句样本](../test/frontend/lowering/fixtures/switch_statements.dart)。 |
| 标签、break、continue | 支持循环和 switch 的 break，以及从带标签的语句中 break。continue 可跳到目标循环的继续点或 switch 标签对应的分支体。跳向 case 时跳过其模式与守卫。 |
| return 与正常完成检查 | 函数返回与声明兼容的值。void 和可空返回类型允许隐式返回 null；抛出或调用返回 Never 的函数会结束当前路径。 |
| try/on/catch、rethrow | on 可按[已支持的类型](types.md)筛选异常，同步函数进入首个匹配的子句。调用、运行时类型检查和显式 throw 产生的异常均可捕获。catch 可读取抛出时的局部变量、异常对象及栈轨迹。rethrow 传递原异常和轨迹。见[异常样本](../test/frontend/lowering/fixtures/exceptions.dart)。 |
| finally | 同步 try 或 catch 正常结束、返回、抛错或跳向外部目标时，执行 finally。返回表达式先求值。finally 正常结束时继续原操作，否则由 finally 的返回、异常或跳转决定结果。见[finally 样本](../test/frontend/lowering/fixtures/finalizers.dart)。 |
| await for | 支持语句和集合元素中的原生流迭代，复用官方 StreamIterator 调用及 Await。continue 保留当前订阅；break、return、异常和外层生成器取消经过异步清理。见[流循环对照](../test/frontend/lowering/await_for_test.dart)。 |
| yield/yield* | 同步生成器的 `yield` 暂停直到下一次 moveNext，提前停止保留悬挂的 finally。`yield*` 检查 Iterable<T> 后按 iterator/moveNext/current 协议委托；协议异常进入源位置的 catch/finally。两者已原生执行，跨暂停保留捕获变量、异常和 GC 根。异步生成器的原生恢复分支将订阅取消接到清理路径，委托流的错误事件转发给监听者。支持异步生成器源码转换、泛型及局部生成器。见[生成器行为](functions.md)。 |
| assert | 支持断言语句。默认关闭；`Lowering(enableAssertions: true).lower(input)` 启用后按需求值条件与失败消息，抛出 AssertionError 并正常经过 catch/finally。关闭时不求值条件或消息。见[断言样本](../test/frontend/lowering/fixtures/assertions.dart)。 |

[循环样本](../test/frontend/lowering/fixtures/loops.dart)与[SDK 行为对照](../test/frontend/lowering/lowering_test.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/statements.md)。

## 原生异常与清理

支持同步 `throw`、`on T`/`catch`、`rethrow` 与 `finally`，包括跨函数传播和构造器失败。`on T` 按[原生类型判断范围](types.md#原生类型判断与空安全)读取实际异常类型，依次选择首个匹配子句；不匹配的子句不执行。正常调用结果只在成功后读取；异常保留同一个对象和关联的栈轨迹。`rethrow` 沿用原轨迹，新的 `throw` 捕获当时的调用链。异常与轨迹在处理器分配和回收期间仍然存活。

`finally` 保留返回表达式的求值顺序；清理正常结束时继续原完成方式，清理自身的返回或抛错会替换待处理结果。见[源码与 SDK 对照](../test/compiler/exceptions_test.dart)及[身份、轨迹与回收验证](../test/codegen/exceptions_native_test.dart)。

dynamic 抛出值先检查为非空 Object；null 产生 TypeError，其他已支持的值保持原异常身份。见[动态抛出对照](../test/compiler/type_checks_test.dart)。穷尽 switch 意外落空时抛出 Error，沿正常异常边展开。依赖运行时类型参数的 `on T`、断言、可捕获分配失败、异步展开仍是缺口。异常不能越过原生入口展开外部栈；未捕获异常释放入口资源、输出错误提示并以 255 退出，尚不格式化异常对象和栈轨迹。

## 规范依据

[主规范 §18](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[模式规范](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/feature-specification.md)、[流分析](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/flow-analysis.md#statements)、[Error API](https://api.dart.dev/stable/3.13.7/dart-core/Error-class.html)。
