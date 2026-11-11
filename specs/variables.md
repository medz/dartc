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

非捕获、非逃逸、非 `late` 的局部存储支持已表示的标量、原生指针、对象引用及可空类型，包括声明后赋值、分支合流、循环和跨调用保存；非 `late final` 的赋值义务仍由前端静态检查。见[原生行为对照](../test/compiler/control_flow_test.dart)。后端在使用局部栈存储前确认每条到达读取的路径都已写入；循环中新声明的存储不能继承上一次迭代的初始化状态。独立 IR 的不安全读取由[发码契约检查](../test/codegen/cells_test.dart)拒绝。引用槽参与栈根扫描并在调用后重载；[栈根验证](../test/codegen/stack_roots_native_test.dart)覆盖对象引用和 null，[装箱验证](../test/codegen/boxed_values_native_test.dart)及[动态装箱验证](../test/codegen/dynamic_boxes_native_test.dart)覆盖 Object、int? 和 double? 存储的初始化与写入。

顶层变量和类静态变量已支持标量、对象引用、可空类型和 num 的原生持久存储，包括 final、late 和 late final。模块存储跨 native 调用保留，泛型类共享声明槽位。先写跳过初始化，未绑定失败后重试，已经完成的写入不回滚；可变递归初始化以成功的外层结果为准，final 递归初始化在求值后检查绑定并保留内层值。未绑定 late 读取和重复 final 绑定通过 SDK 实际 dart:_internal LateError 类抛出普通 Error，RHS 与类型转换先于重复写检查。诊断字符串按固定 SDK 的 NI/AI/ADI 文本构造；动态错误格式化仍未接通。引用槽参与 GC，跨入口保留对象别名、循环引用和装箱数值；已绑定的 null 与未初始化状态分开。含引用全局槽的模块在同线程同步重入时共享堆并扫描暂停的外层栈帧，其他模块仍使用入口返回即释放的独立堆。持久堆由 dartc 链接的共享库在卸载时释放，独立程序在退出前显式释放，详见[库生命周期](libraries.md#模块清理与卸载)。见[标量验证](../test/compiler/scalar_globals_test.dart)、[托管全局验证](../test/compiler/managed_globals_test.dart)与[分配中的 native 重入](../test/codegen/managed_heap_native_test.dart)。跨线程调用、并发调用和跨模块托管值 ABI 尚未支持。

实例 late/late final 已支持可表示的标量、对象引用、可空及泛型字段。物理存储为每个声明字段保留值槽和独立绑定位，区分未绑定与已绑定的 null；各实例独立，继承字段按原声明身份寻址。显式构造写入绑定字段，惰性初始化体接收实际对象及继承后的泛型环境。先写跳过初始化，失败后未绑定字段可重试，抛错前已完成的写入保留；可变递归初始化提交成功的外层结果，final 在初始化求值后检查绑定并保留内层值。赋值的 RHS、表示转换和实际泛型类型检查先于重复 final 绑定检查，失败不修改字段；未绑定读取和绑定冲突通过普通 SDK LateError 抛错。接收者、字段引用及初始化结果参与 GC 根与异常清理。见[实例 late 原生验证](../test/compiler/late_fields_test.dart)；泛型 late-final 的规范安全检查与 SDK 差异见下节。未表示类型不在此支持范围内。

非 `late` 捕获存储与存储别名已支持原生执行：同一绑定的闭包共享后续写入，逃逸闭包及全局保存的闭包保留其存储，`CopyCell` 为循环迭代创建独立身份。无需共享身份的局部变量仍使用栈槽，只有需要存储身份的 cell 使用托管指针；捕获值和引用随普通对象参与 GC。未初始化引用载荷的物理清零仅保证 GC 安全，不表示源码变量已绑定，也不替代初始化检查。见[原生闭包验证](../test/compiler/closures_test.dart)与[存储契约检查](../test/codegen/cells_test.dart)。

局部及捕获的 `late`、`late final` 已支持可表示类型的原生执行。未绑定读取抛出 SDK LateError，null 与未绑定状态分开。先赋值跳过初始化，未绑定初始化失败后可重试；失败前的写入保留，成功的可变初始化覆盖中途写入，递归 final 初始化保留内层绑定并使外层初始化失败。赋值 RHS 和类型检查先于 final 绑定检查，失败不改变原值。初始化器保留词法泛型环境、可变捕获及循环内每次声明的独立存储；跨入口闭包和初始化结果参与 GC。首次成功绑定后释放不再需要的初始化闭包引用。见[局部 late 原生验证](../test/compiler/late_locals_test.dart)和[复制存储与异常边契约](../test/codegen/instance_storage_test.dart)。初始化表达式仍受各项原生执行能力的限制。

## 已知 SDK 差异

SDK 3.13.7（416e33b0ffaef062a60ec966bb8c82ed2b83f128）的 JIT 和 AOT 均允许 `Box<num> box = Box<int>()` 向 `late final T value` 写入 `1.5`；显式 `covariant` 则会抛出 TypeError。IR 与原生后端按规范的 covariant-by-class 规则拒绝该写入，并保持失败后字段未绑定。这两条安全测试单独列出，不计为 SDK 一致结果。[固定版本前端源码](https://github.com/dart-lang/sdk/blob/3.13.7/pkg/front_end/lib/src/fragment/field/declaration.dart#L914-L934) 的 final 排除条件与相邻 TODO 支持存在遗漏的推断，但这不是上游已确认的问题。

最小复现：`class Box<T> { late final T value; } void main() { Box<num> box = Box<int>(); box.value = 1.5; print(box.value); }`。当前 SDK 两种模式输出 `1.5`；IR 与原生后端在赋值时抛出 TypeError。见[独立安全测试](../test/frontend/lowering/late_fields_test.dart)与[原生安全测试](../test/compiler/late_fields_test.dart)。

## 规范依据

[主规范 §8](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[空安全与 late](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md)、[通配变量](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/wildcard-variables/feature-specification.md)。
