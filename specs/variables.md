# 变量

作用域使用已绑定的声明身份。分支与循环中的局部变量保留各条路径实际写入的值。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 显式类型、`var`、多变量声明 | 支持已表示类型的局部变量。非 late 可空可变变量缺省为 null；非空变量和 final 可在声明后首次赋值，由 analyzer 检查确定赋值。 |
| 顶层、静态、实例和局部变量 | 支持局部变量、参数、实例字段，以及顶层/静态 const 和非 const 存储；全局按声明库及类身份区分，泛型类的 static 仅有一个槽。 |
| 局部遮蔽、捕获、声明前引用 | 按 analyzer 绑定的声明区分同名局部变量，闭包可在外层函数返回后继续读写捕获的变量。声明前引用的静态错误由 analyzer 诊断。见[遮蔽与捕获样本](../test/frontend/lowering/fixtures/closures.dart)。 |
| 通配变量 `_` | 支持局部声明、形参及模式中的通配变量；仍按顺序执行各个初始化表达式的副作用和异常。 |
| 确定赋值与确定未赋值 | analyzer 检查非 late 局部变量的读取及 final 首次赋值；IR 保留分支、循环、异常路径与闭包共享的延后初始化存储。见[确定赋值样本](../test/frontend/lowering/fixtures/definite_assignment.dart)。 |
| 局部 `final` 首次赋值 | 支持立即初始化和声明后的首次赋值，包括分支合流及闭包捕获。 |
| 库级/字段 `final` 与隐式访问器 | 支持顶层及静态 final 与合成访问器，沿用普通调用、复合赋值及索引更新路径。实例 final 保留构造初始化。 |
| `const` 与常量对象 | 顶层、静态和局部 const 支持标量、record、List/Set/Map、普通用户类及枚举实例、Type 和函数值的嵌套组合；保留规范身份、实际泛型和不可变操作检查。支持公开 Symbol 及 Symbol 字符串构造的常量；可恢复完整字段值的 SDK 常量使用相同的对象表示；未知或不完整的常量存储仍拒绝。私有 Symbol 字面量可能被 analyzer 错误折叠，当前在读取结果前递归检查并拒绝这类依赖，包括已折叠的标量；不另写常量求值器。 |
| `late`、`late final` | 支持顶层、静态、实例及局部 late/late final：未绑定读取及重复 final 赋值抛出运行时错误，null 与未绑定状态不同，RHS 和类型转换先于重复写检查。实例初始化体按声明字段只生成一次，接收实际对象和泛型环境；构造器不提前执行，但显式构造写入仍会绑定。局部 initializer 复用词法闭包与 cell，捕获未绑定存储不触发读取，延后求值保留可变捕获的当前值和循环迭代身份。见[实例 late 样本](../test/frontend/lowering/fixtures/late_fields.dart)和[局部 late 样本](../test/frontend/lowering/fixtures/late_locals.dart)。 |
| 库变量和静态字段惰性初始化 | 支持首次实际读取才初始化、先写跳过初始化、失败重试及递归初始化。初始化中已写值不因后续异常回滚；final 初始化完成时检查递归绑定，保留内层值。闭包与异常/trace 身份保持，未输入库的访问器仍是 import，不伪造存储。见[全局存储样本](../test/frontend/lowering/fixtures/global_storage.dart)。 |
| 模式变量声明与赋值 | 支持用 record 模式声明局部变量、交换已有变量及在三段式 for 中解构。后续字段断言抛错时，catch 仍可读到目标变量的原值。见[解构](../test/frontend/lowering/fixtures/destructure.dart)和[失败赋值样本](../test/frontend/lowering/fixtures/exceptions.dart)。 |

[IR 行为对照](../test/frontend/lowering/lowering_test.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/variables.md)。

## 原生局部存储

非捕获、非 `late` 的 `int`、`bool`、`double` 和原生指针局部变量支持声明后赋值，包括分支合流、循环和跨调用保存；非 `late final` 的赋值义务仍由前端静态检查。见[原生行为对照](../test/compiler/control_flow_test.dart)。后端在使用局部栈存储前确认每条到达读取的路径都已写入；循环中新声明的存储不能继承上一次迭代的初始化状态。独立 IR 的不安全读取由[发码契约检查](../test/codegen/cells_test.dart)拒绝。

非 late、可变、精确类型为 int/double/bool 的顶层变量和类静态变量已支持原生执行。模块存储跨 native 调用保留，泛型类的所有实例共享同一声明槽位；初始化在首次读取运行，先写跳过初始化，未绑定失败后重试，已经完成的写入不回滚。有限递归读取不设 busy 错误，成功的外层可变初始化最后覆盖内层结果。初始化期间可以分配托管对象，但只有标量结果持久保存，现有每次同步入口的堆仍在返回时释放。见[固定原生验证](../test/compiler/scalar_globals_test.dart)与[分配中的 native 重入](../test/codegen/managed_heap_native_test.dart)。可空、num、对象引用、final/late 全局变量仍明确拒绝发码；没有提供跨线程隔离或并发同步协议。

捕获存储、存储别名、可空或托管值以及 `late` 初始化的原生执行仍待实现；已有 IR 支持不代表这些路径已能发码。

## 已知 SDK 差异

SDK 3.13.7（416e33b0ffaef062a60ec966bb8c82ed2b83f128）的 JIT 和 AOT 均允许 `Box<num> box = Box<int>()` 向 `late final T value` 写入 `1.5`；显式 `covariant` 则会抛出 TypeError。本 IR 按规范的 covariant-by-class 规则拒绝该写入，并保持失败后字段未绑定。这两条安全测试单独列出，不计为 SDK 一致结果。[固定版本前端源码](https://github.com/dart-lang/sdk/blob/3.13.7/pkg/front_end/lib/src/fragment/field/declaration.dart#L914-L934) 的 final 排除条件与相邻 TODO 支持存在遗漏的推断，但这不是上游已确认的问题。

最小复现：`class Box<T> { late final T value; } void main() { Box<num> box = Box<int>(); box.value = 1.5; print(box.value); }`。当前 SDK 两种模式输出 `1.5`；IR 在赋值时抛出 TypeError。见[独立安全测试](../test/frontend/lowering/late_fields_test.dart)。

## 规范依据

[主规范 §8](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[空安全与 late](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md)、[通配变量](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/wildcard-variables/feature-specification.md)。
