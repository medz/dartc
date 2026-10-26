# 运行时约束

源码 checkout 的原生可执行文件路径支持 `dart:core` 的 `pragma` 子集。`dartc` 使用下列工具专用提示检查函数，不改变 Dart 语言的普通类型规则。官方 Dart 可以忽略这些提示；它的编译成功不能证明 dartc 合同成立。[pragma API](https://api.dart.dev/dart-core/pragma-class.html)

```dart
@pragma('dartc:no-gc')
int half(int value) => value ~/ 2;

@pragma('dartc:no-gc')
int maskedShift(int value, int count) => value >> (count & 63);
```

## 提示及适用范围

| 提示 | 含义 |
| --- | --- |
| `dartc:no-gc` | 检查函数体及其传递调用：不得分配托管内存、进入 GC 或走可能创建 Dart 异常的失败路径；异步和挂起语法尚不受支持。 |
| `dartc:managed-allocate` | 声明调用此函数可能分配托管内存，供调用方检查；当前函数体是否看起来只有整数和原生存取，不取消这个语义角色。 |
| `dartc:may-gc` | 声明调用此函数可能进入 GC 或安全点，独立于是否分配内存。 |

三个提示只能放在受支持的函数声明上，包括方法、getter、setter 和构造器，不能用来给类、字段、参数或 external 原语授予权限。目前不接受非 null 的 options。同一函数可组合多个提示。

NoGC 检查的是函数体；分配/GC 角色描述的是调用对外的影响。一个只操作原生内存的分配器函数体可以满足 NoGC，但它的 `managed-allocate` 角色仍禁止 NoGC 调用方使用它。未标注的直接被调函数也可以通过真实函数体被证明安全；递归调用按整个调用闭包检查。未使用的带 NoGC 约束函数同样接受检查，不会因此强制链接进产物。

实参、缺省实参及构造接收者分配在调用方发生。NoGC 构造器的字段存储可以合格，但 `C()` 创建对象本身仍可能分配；NoGC `main` 也不表示启动代码和命令行参数适配过程不分配。

## 保守检查边界

- 未知间接调用被拒绝，包括没有直接目标证明的原生函数地址调用。
- 尚未消除的受检转换和动态布尔消费按潜在 Dart 异常保守拒绝。不能用当前失败路径直接退出进程或不再分配托管内存来豁免语言义务。
- 受检 String 索引、切片、字符代码构造，以及带 start 边界的 `startsWith` / `indexOf` / `lastIndexOf` 保留潜在 Dart 失败义务；`int.parse` 同样保留格式失败义务。当前不为具体索引或 start 作范围证明。[String API](https://api.dart.dev/dart-core/String-class.html)、[int.parse](https://api.dart.dev/dart-core/int/parse.html)
- List 读取、写入、增删、清空和 filled 构造保留可能的范围、类型或固定长度/只读失败义务；即使当前调用使用可变 List，也不能证明整个通用函数体无失败路径。`String.length`、`List.length`、`identical` 和布尔编码不因此被一概拒绝；`endsWith` 遇过长后缀返回 false，没有受检 start 参数。[List API](https://api.dart.dev/dart-core/List-class.html)、[endsWith](https://api.dart.dev/dart-core/String/endsWith.html)
- 除法和取模需有已知非零常量除数；移位需有非负常量计数，或通过与非负常量掩码做按位与来证明非负。对其他除数和移位计数尚不作一般范围证明。
- 仍可能分配的整数装箱、对象和 List 创建会被拒绝。常量对象及惰性全局的首次物化路径也参与检查，不能只考虑缓存已热的情况。

编译器在类型化 SSA 和实际运行时调用 lowering 后检查，不以源码看起来简单作为证明。验证保留现有读写、原生调用和异常 effects；NoGC 不是 pure，也不表示不阻塞、线程安全、内存安全或引用生命周期正确。原生 mmap/unmap、存取、系统调用和直接退出进程本身不被 NoGC 禁止。

## 运行时贡献边界

提示只在绑定到真实 core `pragma` 类时消费；同名用户类没有特殊权限，前缀、再导出和常量别名仍保留原声明身份。注解按正常常量规则求值，不通过解析 callee 拼写绕过绑定。

原语能力仍只来自受信运行时的声明绑定。普通应用不能复制一个 pragma 获得原生加载、存储或调用能力。运行时必须显式标记真正的托管分配入口及可能 GC 的入口；漏标是可信边界错误，结构分析无法从整数地址操作推断内存所有权。raw OS 映射与托管分配器使用的 arena 不能混同。

当前是静态合同验证，不插入收集器、安全点轮询或运行时注解表，也不因为 NoGC 删除调用返回点的根记录。完整 GC、线程与安全点设计见[架构](architecture.md)。新增编译能力应先由已有 native 编译器构建支持它的编译器，再由新编译器校验并采用运行时注解。

当前支持范围限原生可执行文件。静态/动态库产物路径尚不装载 core pragma 入口。

实现入口：[frontend.dart](../lib/src/frontend.dart) 的 `fePragmaFlags()`、`feCheckMetadata()`；[nogc.dart](../lib/src/nogc.dart) 的 `checkNoGcSsa()`、`checkNoGcMachine()`。core 声明入口是 [core.dart](../lib/src/std/core.dart)，不等同于完整 SDK core 库。行为验证由 [behavior_test.dart](../test/behavior_test.dart) 的 core/NoGC 程序与拒绝用例，以及 [roots.dart](../test/fixtures/roots.dart) 的 `noGcRoots()` 负责。

## 原始缓冲与构建期间的根

`rtCStringAcquire()` / `rtCStringRelease()` 独占借用可复用的原生四 word 缓冲，不再将无对象头的 C 字符块交给托管 arena；重复借用或无借用释放会终止。`rtStringFromWords()` 在解码完成后释放借用；`rtStringFromCString()` 只读取调用方提供的地址，不取得其所有权。argv 等 OS 内存不是托管对象根。该原生缓冲的所有权持续到进程结束，NoGC 允许它的原始映射。

以 `int` 保存对象地址的运行时函数不能依赖普通整数字段自动成为根。`rtArguments()`、`rtListFilled()`、List 转换/扩容路径、`rtStringConcat()` 及默认运行时路径构造在跨托管分配处使用 mark/push/restore 作用域；来源值和转换后的值分别按其 TypeRef 的 Ref/Tagged 表示登记，Word 不因数值像指针而入根。新 List 的结果在分配 backing 前保活，扩容前保留已装箱的实际元素；退出作用域发生在最后一次需要该对象的分配之后。常量对象物化仍先建立可安全扫描的字段/已初始化前缀，再发布子引用。

这些根记录当前适用于非移动表示的所有权表达；raw 局部地址和派生指针没有重定位后重读协议。尚未开启 GC，构造器 reserve 到安全对象头/引用前缀完成之间也不能任意插入回收点。真实行为测试验证输出、返回后对象图和根作用域恢复，不证明分配中途已发生并通过回收。根枚举与所有权用例归 [roots.dart](../test/fixtures/roots.dart) 的 `runtimeOwnership()`、`builderRoots()`、`constantObjectRoots()`；字符串、List 与命令行行为继续复用 [values.dart](../test/fixtures/values.dart) 和 [behavior_test.dart](../test/behavior_test.dart)。
