# 运行时接口与所有权

[runtime.dart](../lib/src/runtime.dart) 实现目标程序的运行时算法；共享尺寸、偏移和表示由 [layout.dart](../lib/src/layout.dart) 定义。编译器与运行时必须使用匹配的 ABI，改变布局或调用协议时整体重建。

当前 ABI 为 14。TypeRef 带对象头，List 和函数对象的类型引用参与扫描；ABI 13 的无对象头类型记录不能与此布局混用。

main 使用进程级 bump arena，不执行 GC、空闲块复用或 arena 释放。根枚举和 NoGC 校验提供收集器所需的边界，不代表收集器已启用。收集器、异常展开和线程/调度的目标设计见 [architecture.md](architecture.md)。

## 对象与元数据布局

对象采用未压缩引用，头部两个 word 分别为描述符引用和布局标志。托管堆对象的描述符为绝对地址；只读映像对象设置 `objectStaticRelative`，首字按对象基址解释为有符号位移，由 `rtObjectDescriptor()` 统一读取。

| 对象 | 负载与扫描规则 |
| --- | --- |
| 普通实例 | 字段从 `+16` 开始，按声明表示分为 Word、Ref、Tagged |
| String | `+16` 长度，`+24` 起为 UTF-16 数据；无托管子引用 |
| List | `+16` 长度、`+24` 容量、`+32` backing Ref、`+40` TypeRef 引用 |
| backing array | `+16` 已初始化前缀长度，`+24` 起存元素；Word、Ref、Tagged 分别使用对应描述符，仅扫描有效前缀 |
| IntBox | `+16` 完整整数负载；无托管子引用 |
| Function | `+16` TypeRef 引用、`+24` 调用适配器入口；类型引用及捕获字段参与扫描，捕获字段从 `+32` 开始；无捕获对象仍为 32 字节 |
| TypeRef | `+16` 类型种类、`+24` 子类型或函数签名位移、`+32` 类描述符位移、`+40` 值表示；堆记录扫描子类型，类描述符不作托管引用 |

ClassDesc 为 64 字节只读记录，保存实例尺寸、字段数、对象种类、Ref/Tagged 位图、类名及可达的 toString 入口。位图按每 64 字段一个 word 分段，不限制为 64 个字段，全零位图不保留存储。变长对象按描述符种类扫描，不借用普通字段位图。

TypeRef 的固定部分为 48 字节，是内部类型记录，不直接充当公开的 Dart Type 值。静态记录带 `objectStaticRelative` 标记，只引用静态元数据；堆记录使用普通对象头，其子类型由根遍历保留。List 和函数对象可引用这两种记录，扫描时跳过不持有堆引用的静态类型。函数签名记录保存结果类型、必需参数数和参数类型；堆函数类型将签名内联在固定部分之后，并扫描结果及参数类型。记录内类型边仍以所属记录或条目为基址保存相对位移。描述符、类型记录及常量按实际依赖链接，编译期实体 ID 不直接写作运行时地址。

List 标志 `objectListFixed` / `objectListReadOnly` 分别限制长度变化和内容修改；语言行为见 [表达式](../specs/expressions.md)。更新 List 长度时同步维护 backing 的已初始化前缀，缩短后不扫描前缀之外的旧元素。

## NoGC 提示

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

NoGC 是静态合同验证，不插入收集器、安全点轮询或运行时注解表，也不因证明 NoGC 而删除调用返回点的根记录。新增编译能力先由已有 native 编译器构建支持它的编译器，再由新编译器校验并采用运行时注解。

当前支持范围限原生可执行文件。静态/动态库产物路径尚不装载 core pragma 入口。

实现入口：[frontend.dart](../lib/src/frontend.dart) 的 `fePragmaFlags()`、`feCheckMetadata()`；[nogc.dart](../lib/src/nogc.dart) 的 `checkNoGcSsa()`、`checkNoGcMachine()`。core 声明入口是 [core.dart](../lib/src/std/core.dart)，不等同于完整 SDK core 库。

## 根所有权

根表示使用 `storageRef` / `storageTagged`；原始 Word、代码及 TypeRef 地址不作托管根。Ref 的零值和 Tagged 的立即值不加入对象队列。

| API | 所有权合同 |
| --- | --- |
| `rtRootMark()` | 返回当前临时根前缀位置 |
| `rtRootPush(value, kind)` | 按 Ref/Tagged 表示登记临时引用；根缓冲为原始内存 |
| `rtRootPushValue(value, type)` | 根据 TypeRef 的值表示登记；Word 不登记 |
| `rtRootRestore(mark)` | 截断临时根活跃前缀，不影响持久槽 |
| `rtGlobalRootNew(value, kind)` | 创建持久槽，返回从 1 开始的稳定索引 |
| `rtGlobalRootValue(index)` / `rtGlobalRootSet(index, value)` | 读取或更新持久槽；设为零释放其持有关系，槽索引不复用 |
| `rtTraceRoots(frame, worklist, capacity)` | 将栈、全局和显式根写入调用方原始队列，返回数量 |
| `rtTraceObject(value, worklist, capacity)` | 从已知对象基址枚举托管子引用，返回数量；不执行递归标记或清扫 |

typed Ref/Tagged 参数及活跃临时值由编译器根槽保活；不能把它们误判为全都需要额外根范围。运行时以 `int` 保存的对象基址则不自动成为根；跨托管分配时必须已有其他根 owner，或显式登记。对象内部地址不能单独承担保活责任。

### 根表生成与编码

[root_map.dart](../lib/src/root_map.dart) 从 MIR CFG 计算每个直接或间接调用之前的活跃值，再使用寄存器分配确定的实际 FP 槽，区分 Ref 与 Tagged。发射器在真实 BL/BLR 之后记录返回 PC，按发射顺序形成有序调用根表。零根调用仍保留记录；启动跳板的无帧调用使用边界记录终止遍历。全局根按槽的 Ref/Tagged 表示列出，整数、布尔和原生地址不作根。

只有可达的 `nativeMetadataAddress` 请求包含 `metadataRoots` 时才保留根表。调用返回 PC、全局槽和子表引用均用相对各记录基址的位移，和代码、常量及数据段一起布局。相同的有序根槽向量共享只读存储，每个调用点仍保留自己的返回 PC、根数和向量引用；零根及启动边界记录不因共享而省略。

根遍历只增加 `nativeFramePointer` 这一读取当前帧指针的受信机器原语；帧链查找、根值过滤和对象边遍历保持为 Dart 算法。未知返回 PC、非法根种类或队列容量不足会终止。

## 原始缓冲与构建期间的根

`rtCStringAcquire()` / `rtCStringRelease()` 独占借用可复用的原生四 word 缓冲；无对象头的 C 字符块不进入托管 arena，重复借用或无借用释放会终止。`rtStringFromWords()` 在解码完成后释放借用；`rtStringFromCString()` 只读取调用方提供的地址，不取得其所有权。argv 等 OS 内存不是托管对象根。该原生缓冲的所有权持续到进程结束，NoGC 允许它的原始映射。

以 `int` 保存的对象地址不会自动成为根。`rtArguments()`、`rtListFilled()`、List 转换/扩容路径、`rtStringConcat()` 及默认运行时路径构造在跨托管分配处使用 mark/push/restore 作用域：

- 来源值和转换后的值分别按其 TypeRef 的 Ref/Tagged 表示登记；Word 不因数值像指针而入根。
- 新 List 的结果在分配 backing 前保活；扩容前保留已装箱的实际元素。
- 最后一次需要该对象的分配完成后，才能退出根作用域。

构造器从 reservation 到安全对象头/引用前缀完成之间保持无回收窗口。常量对象物化同样先建立可安全扫描的字段/已初始化前缀，再发布子引用。此后每次分配前，所有需继续访问的对象都必须有根；对象边枚举本身不能证明对象在分配中途仍然存活。

这些根记录仅适用于非移动表示：raw 局部地址和派生指针没有重定位后重读协议。

UTF-8 编码使用 I/O 层拥有的可复用原始缓冲，按需映射和扩容，不消耗托管 arena。打印在同步写出结束后释放借用，路径在 open 或 chmod 返回后释放；后续调用复用容量，扩容时解除旧映射。借用期间没有 Dart 回调或托管分配，toString 回调发生在借用前。该单执行者协议不提供线程、isolate 或异步 I/O 共享借用。

## 托管分配的物理区间

每个 arena 在 payload 前保留 48 字节原始记录，保存下一 arena、映射请求长度、已使用长度及边界图。当前 bump arena 是链头，换 arena 后仍保留旧区间的所有权。

边界图为每 16 字节保留 2 bit；当前只将每次 reservation 的起点置为 allocated，内部保持零。物理跨度由下一起点或已使用前缀末尾决定，不从 String 的逻辑长度或 List 的当前元素数反推。最后一个 backing 原位增长只推进同一区间末尾；搬移增长保留新旧两个起点，复制完成后才发布新 backing。

8 MiB arena 的边界图请求为 128 KiB，约为 payload 映射请求的 1.5625%；每个 arena 增加一次原始映射，每次分配写入起点及使用末尾。记录不进入托管对象扫描，普通对象不逐个 mmap。当前没有标记、清扫、空闲块复用或 arena 释放，所有映射仍保留至进程退出；这些记录尚不构成 GC。reservation 到对象头、引用槽及复制前缀安全之间仍必须保持无回收窗口。

## 编译器的文件服务

[host.dart](../lib/src/host.dart) 定义编译器的宿主接口；官方 Dart 运行时使用 SDK 实现，原生 dartc 通过受信模块的声明身份连接到普通 Dart 运行时函数。同名用户函数仍按用户声明调用。

- `hostReadIfExists(path)` 返回 `String?`。仅在 open 返回 `ENOENT` 或 `ENOTDIR` 时返回 null；空文件返回空字符串。权限、目录读取及其他 I/O 失败仍终止，路径与错误写入 stderr，保留调用方的 stdout。
- `hostCurrentDirectory()` 返回实际工作目录，不读取 `PWD`，也不从可执行文件推断。macOS 使用 open/fcntl 的 [F_GETPATH](https://github.com/apple-oss-distributions/Libc/blob/main/gen/FreeBSD/getcwd.c) 路径，Linux 使用 [getcwd 系统调用](https://github.com/torvalds/linux/blob/master/tools/include/uapi/asm-generic/unistd.h)并在缓冲不足时重试。超出这些系统接口能表示的路径会报告 I/O 错误；尚无 libc 的长路径遍历回退。
- `hostStdPath()` 按实际运行的可执行文件位置查找 `../lib/src/runtime.dart`，支持 PATH 与符号链接启动。macOS 读取进程可执行路径，Linux 读取 `/proc/self/exe`；显式 `--std` 跳过自动发现。
- 文件和工作目录的原始缓冲在解码后释放；托管 String 或 null 使用现有 Ref 表示。两项服务可能创建托管 String，不能作为 NoGC 接口。

这些内部接口服务于[源码和包配置加载](../specs/libraries.md)，不构成完整 `dart:io`。

## 函数值与调用边界

无捕获函数值在映像中使用只读对象，按实际声明或语法节点保存身份，不按静态函数类型复制对象。对象沿用 16 字节头，后续两个 word 分别引用结构签名和调用适配器；只读字段相对对象基址编码，不预留空捕获环境。语言支持范围及身份规则见 [函数](../specs/functions.md)。

函数 TypeRef 与代码声明 ID 分开。bare `Function` 使用上界记录；具体签名保存结果、必需位置参数数目、总位置参数数目与参数 TypeRef。签名链接保留嵌套函数、List 和可空类型，运行时按参数逆变及返回协变检查。当前没有 named/generic 签名。

普通已知目标调用保留原 ABI。函数值调用先取得已验证 callable 的代码地址，通过每目标一个适配器传递隐藏 callable Ref 和 tagged 实参，再按目标声明检查、解箱并直接调用原函数，将结果转回 tagged 表示；调用方按静态签名还原结果。这样允许函数子类型跨越 Word、Ref 和 Tagged 表示，不把原生地址调用原语当作 Dart 函数调用协议。代码地址不是根，仍活跃的 callable Ref 和 tagged 实参与其他值一样参与调用点根表。

未知函数值调用保守拒绝用于 NoGC；适配器不继承目标函数的 NoGC 提示。提取只读函数对象与调用它的效果不同。堆闭包在固定函数前缀后保存捕获字段，描述符扫描 Ref/Tagged 捕获。可变绑定使用共享单元；单元保存声明类型的值并按该表示扫描，稳定捕获直接保存值。函数体接收隐藏 callable Ref，源码签名不含它。只读函数对象没有捕获字段，仍按叶处理。调用求值规则见 [表达式](../specs/expressions.md)。

绑定方法沿用函数对象前缀，`+32` 保存接收者 Ref；描述符的内部类 ID 为 `boundMethodClassId`，每个方法拥有唯一描述符。相等比较先判断该标记，再比较描述符地址和接收者身份，不调用接收者的相等运算。链接不能把不同方法的描述符合并为同一身份。调用适配器从捕获字段取出接收者，再进入原方法的直接入口；方法本体仍接收普通 this 参数。`ClosureLayout.boundReceiver` 拥有这一区别，SSA 检查接收者字段的数量和类型。提取期间接收者与尚未完成初始化的函数对象分别由活跃局部根持有；分配器先将引用字段置零再允许后续分配。

## 行为验证入口

- [behavior_test.dart](../test/behavior_test.dart)：core/NoGC、函数值、I/O 程序及拒绝/失败用例。
- [roots.dart](../test/fixtures/roots.dart)：`noGcRoots()`、`runtimeOwnership()`、`builderRoots()`、`constantObjectRoots()`、`closureRoots()`、`typeGraphRoots()`。
- [values.dart](../test/fixtures/values.dart)：String、List、类型与函数值行为。
