# 运行时接口与所有权

[runtime.dart](../lib/src/runtime.dart) 实现目标程序的运行时算法；共享尺寸、偏移和表示由 [layout.dart](../lib/src/layout.dart) 定义。编译器与运行时必须使用匹配的 ABI，改变布局或调用协议时整体重建。

当前源码 ABI 为 15。TypeRef 带对象头，List 和函数对象的类型引用参与扫描；值元数据的 `+64` 保存 DoubleBox 描述符位移。旧 ABI 的元数据不能与此运行时混用。

main 使用进程级 bump arena，不执行 GC、空闲块复用或 arena 释放。根枚举和 NoGC 校验提供收集器所需的边界，不代表收集器已启用。收集器和线程/调度的目标设计见 [architecture.md](architecture.md)。

## 对象与元数据布局

对象采用未压缩引用，头部两个 word 分别为描述符引用和布局标志。托管堆对象的描述符为绝对地址；只读映像对象设置 `objectStaticRelative`，首字按对象基址解释为有符号位移，由 `rtObjectDescriptor()` 统一读取。

| 对象 | 负载与扫描规则 |
| --- | --- |
| 普通实例 | 字段从 `+16` 开始，按声明表示分为 Word、Ref、Tagged；late 状态字追加在语言字段之后，不参与扫描 |
| 捕获的 late cell | `+16` 为声明类型的负载，`+24` 为已初始化标志，`+32` 为初始化器 Ref；初始负载为零，成功写入后清空初始化器 |
| String | `+16` 长度，`+24` 起为 UTF-16 数据；无托管子引用 |
| List | `+16` 长度、`+24` 容量、`+32` backing Ref、`+40` TypeRef 引用 |
| backing array | `+16` 已初始化前缀长度，`+24` 起存元素；Word、Ref、Tagged 分别使用对应描述符，仅扫描有效前缀 |
| IntBox | `+16` 完整整数负载；无托管子引用 |
| DoubleBox | `+16` IEEE binary64 位模式；无托管子引用 |
| Function | `+16` TypeRef 引用、`+24` 调用适配器入口；类型引用及捕获字段参与扫描，捕获字段从 `+32` 开始；无捕获对象仍为 32 字节 |
| TypeRef | `+16` 类型种类、`+24` 子类型或函数签名位移、`+32` 类描述符位移、`+40` 值表示；堆记录扫描子类型，类描述符不作托管引用 |

ClassDesc 为 64 字节只读记录，保存实例尺寸、字段数、对象种类、Ref/Tagged 位图、类名及可达的 toString 入口。位图按每 64 字段一个 word 分段，不限制为 64 个字段，全零位图不保留存储。变长对象按描述符种类扫描，不借用普通字段位图。

TypeRef 的固定部分为 48 字节，是内部类型记录，不直接充当公开的 Dart Type 值。静态记录带 `objectStaticRelative` 标记，只引用静态元数据；堆记录使用普通对象头，其子类型由根遍历保留。List 和函数对象可引用这两种记录，扫描时跳过不持有堆引用的静态类型。函数签名记录保存结果类型、必需参数数和参数类型；堆函数类型将签名内联在固定部分之后，并扫描结果及参数类型。记录内类型边仍以所属记录或条目为基址保存相对位移。描述符、类型记录及常量按实际依赖链接，编译期实体 ID 不直接写作运行时地址。

静态泛型模板另带 `objectTypeTemplate`；`typeKindParameter` 的 `+24` 保存类型环境索引，复合模板保留相对类型边。`rtInstantiateType` 接收模板及托管类型环境，直接复用具体类型，按需构造 List、可空和函数签名记录。构造过程中通过 runtime root scope 保留环境、子类型和已初始化的对象；实际类型记录不带模板标记。当前不缓存或驻留这些堆类型记录。

共享泛型调用在实例接收者后、普通参数前传入 `List<Object>` 类型环境。语义类型参数的值使用 Tagged；复合 List/函数值保持 Ref。`rtValueCheck` 按实际 TypeRef 检查并保留原负载，具体调用方再按已知结果类型转换；`rtListFilledChecked` 按实际元素类型取得存储表示。类型环境和实例化属于分配效果，不能因被调函数体简单而从 NoGC 检查中省略。

List 标志 `objectListFixed` / `objectListReadOnly` 分别限制长度变化和内容修改；语言行为见 [表达式](../specs/expressions.md)。更新 List 长度时同步维护 backing 的已初始化前缀，缩短后不扫描前缀之外的旧元素。

## 数值表示与机器边界

`double` 的语义类型独立于机器表示 `rF64Bits`。已知 double 在内部调用中用通用寄存器和栈槽传递原始 64 位值，前八个参数依次使用 x0–x7，结果为 x0；d0/d1 只在一条浮点机器操作内作临时寄存器，不跨调用或安全点存活。分配器可以把 `rF64Bits` 放入通用寄存器，但根表和对象位图不把它当引用。`num`、`Object`、`dynamic` 与 `double?` 的 double 负载经 DoubleBox 进入 Tagged 表示。

四则运算、比较和整数转换由 ARM64 binary64 原语执行。原语以整数位模式收发，比较返回 -1、0、1 或 unordered 的 2；机器转整数采用截断和饱和，Dart 数值入口先拒绝 NaN 与无穷大。独立可执行文件使用进程初始的最近偶数舍入环境。此内部协议不适用于平台 FFI；浮点 FFI 参数、结果和外部浮点环境管理尚未接入。

[binary64.dart](../lib/src/binary64.dart) 由编译器常量求值与目标运行时共用。十进制解析以整数比值执行精确舍入，输出按相邻 binary64 值的舍入区间选择最短十进制表示；余数算法使用整数有效位和指数。算法保持为普通 Dart 源码，原语只提供机器运算。

`nativeValueBits(Object?)` 暴露内部 Tagged word；`nativeValueFromBits(int)` 恢复同一表示。恢复的 word 必须来自合法的当前 ABI 值，不能把任意地址或浮点位模式当对象。转换本身不分配、不建立根，也不转移所有权。暴露的对象地址跨可能 GC 的调用前，调用方必须保留对应托管引用或登记 runtime root；转换的两侧各按自身表示参与根分析。数值字符串入口通过这个边界连接普通 Dart String 与原有的运行时地址接口。

## 进程终止

受信原语 `nativeExit(int status)` 的结果类型为 `Never`；绑定与 SSA 验证参数、结果及原生副作用。发码使用目标平台的进程退出入口，系统调用异常返回时触发硬件陷阱。`rtHostExit`、构建结束和致命错误出口均传播不返回的契约，不生成占位返回值或忙等循环。进程终止不提供 Dart 异常捕获与展开。

实现入口：[ir.dart](../lib/src/ir.dart) 的原语签名、[emit.dart](../lib/src/emit.dart) 的 `emitExit()`；行为由 [behavior_test.dart](../test/behavior_test.dart) 的退出状态与先行副作用用例验证，签名及 effects 由 [ssa_test.dart](../test/ssa_test.dart) 验证。

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
- 尚未消除的受检转换、动态布尔消费和 late 失败路径按潜在 Dart 异常保守拒绝。不能用当前失败路径直接退出进程或不再分配托管内存来豁免语言义务。
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

根表示使用 `storageRef` / `storageTagged`；原始 Word 和代码地址不作托管根；持有的 TypeRef 引用按 Ref 登记，静态记录不进入堆对象队列。Ref 的零值和 Tagged 的立即值不加入对象队列。

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

## 帧描述符与同步轨迹

可达代码请求 `metadataFrames` 时，元数据 `+72` 指向只读帧表；未请求时不保留帧表或函数名。表按代码地址排序，每个描述符保存半开代码区间、FP 以下的固定帧字节数、保存寄存器的起始 FP 偏移、x19–x27 位图及函数名。区间和名称用相对描述符的位移表示，表内引用相对表本身，随最终映像一起重定位。

[emit.dart](../lib/src/emit.dart) 从实际发射的 prologue/epilogue 和分配结果记录布局。已保存寄存器按寄存器编号升序排列，占用连续向下的 FP 槽；固定帧大小不含 FP/LR 头和调用期间临时分配的溢出参数区。无帧启动跳板使用负帧大小，遍历在读取其父 FP 前停止。

[frames.dart](../lib/src/runtime/frames.dart) 的 `rtFrameDescriptor(pc)` 是 NoGC 二分查找，区间外返回零。`rtStackTraceString(frame)` 从传入帧的调用者开始，查询返回 PC 后才沿 FP 前进，遇到未知 PC 按运行时合同失败终止。捕获期间被访问的调用者帧保持活动，StringBuffer 和结果 String 由普通托管引用保活。该路径只读取调用链，不恢复寄存器或执行异常处理；标准库 API 范围见 [specs/libraries.md](../specs/libraries.md#stacktrace-api)。

## 同步异常展开

可达调用需要异常后继时，元数据 `+80` 指向 `metadataHandlers` 处理表，并同时保留帧表。每项把精确返回 PC 映射到调用者的异常边入口，按 PC 排序；两地址均为相对表项的位移。没有处理器的调用无需表项，展开器继续查找父帧。

[exceptions.dart](../lib/src/runtime/exceptions.dart) 拥有当前执行域的待处理对象、StackTrace 和原生恢复上下文。异常对象与轨迹是普通托管字段；catch 或 finally 的异常入口复制到局部根后清空字段，rethrow 使用当前词法 catch 保存的原值。finally 的完成标记、返回值与异常保存由编译器生成，展开器仍只定位处理入口。`nativeCaptureContext` 将 FP、SP、PC、x19–x27 写入 96 字节原始缓冲；`nativeResumeContext` 恢复同一集合并跳转，结果为 Never。缓冲布局由 [layout.dart](../lib/src/layout.dart) 定义，不是平台 FFI 上下文。

展开器按实际保存位图撤销各帧的寄存器保存，找到处理器后以父 FP 和固定帧大小重建 SP，不依赖抛出调用的溢出实参大小。查表和展开为 NoGC 路径。未找到处理器时输出异常与轨迹并以状态 255 退出；未知帧仍按内部合同失败终止。语言范围及缺口见 [specs/statements.md](../specs/statements.md)。

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

捕获外层类型参数的闭包在 `+32` 保存类型环境 Ref，普通值捕获随后排列；类型环境保留外层调用的实际 TypeRef，闭包体和调用适配器共享它。先实例化签名并以活跃 Ref 保留，再分配闭包；固定函数前缀写入完成前不执行托管分配。不能用带自由类型参数的模板代替可见函数类型。描述符枚举环境与普通捕获，函数对象额外枚举托管签名；类型环境的 List/backing 继续持有类型实参。这些边在外层函数返回后仍存在。

绑定方法沿用函数对象前缀，`+32` 保存接收者 Ref；描述符的内部类 ID 为 `boundMethodClassId`，每个方法拥有唯一描述符。相等比较先判断该标记，再比较描述符地址和接收者身份，不调用接收者的相等运算。链接不能把不同方法的描述符合并为同一身份。调用适配器从捕获字段取出接收者，再进入原方法的直接入口；方法本体仍接收普通 this 参数。`ClosureLayout.boundReceiver` 拥有这一区别，SSA 检查接收者字段的数量和类型。提取期间接收者与尚未完成初始化的函数对象分别由活跃局部根持有；分配器先将引用字段置零再允许后续分配。

## 行为验证入口

- [behavior_test.dart](../test/behavior_test.dart)：core/NoGC、函数值、I/O 程序及拒绝/失败用例。
- [roots.dart](../test/fixtures/roots.dart)：`noGcRoots()`、`runtimeOwnership()`、`builderRoots()`、`constantObjectRoots()`、`closureRoots()`、`typeGraphRoots()`。
- [values.dart](../test/fixtures/values.dart)：String、List、类型与函数值行为。
