# 库、脚本与并发边界

转换以调用方明确提供的库批次为单位，包含每个库的所有 part。`package:dartc/frontend.dart` 的 `AnalysisSession` 复用官方 analyzer 的解析结果；名称与指令解析不由 lowering 重复实现。`includeDependencies: true` 纳入非 SDK 导入和导出库，整个批次完成静态检查后才开始转换。用户库的函数体由输入批次提供；引用的 SDK 普通顶层函数、静态方法、属性、全局存储及构造器和常量所属类按声明身份读取源码，并在转换前检查所在库的全部单元。`Lowering.lower` 返回 `Future<LoweringResult>`，须在分析会话关闭前等待完成。无参数的同步或 async main 可作为独立进程入口，其他启动能力见下文。

接入的 SDK 实现片段在所属库内完成静态检查，包括未使用的方法体。原声明保留类型、默认参数、构造器初始化及已有 Dart 方法体；实现可重写已继承的实例成员，签名由 analyzer 检查；不得增添无对应声明的公开 API 或改变公共类的继承关系。已有 Dart 正文仅允许基于明确的目标存储约束或已核实的规范偏差替换；官方文件或内部库身份本身不构成替换依据。签名和返回类型不一致仍是错误。`dart:ffi` 的 Array 注解实现包含官方私有成员，即使未接入 runtime 源码也必须完成该库的检查。见[实现片段检查](../test/frontend/analysis/sdk_patches_test.dart)。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 编译单元、具名/无名 library、脚本标记 | analyzer 解析；转换库内声明，脚本标记不生成 IR。 |
| import、as 前缀、显式/隐式 core | analyzer 解析；保留已解析声明身份，支持普通导入前缀。SDK API 的运行时实现另计。 |
| 条件 import/export | 使用 analyzer 当前环境选择的库；尚无面向目标平台的环境配置接口。 |
| export、再导出、show/hide | analyzer 解析导出命名空间及组合器；引用保留原声明身份。不是原生符号导出。 |
| 命名空间冲突与读写查找 | analyzer 拒绝歧义、不可见名称；getter/setter 引用复用声明身份。 |
| deferred import | 支持每个源前缀独立的加载状态、loadLibrary 调用及提取、异步完成和重复加载。访问成员、常量、类型及构造器之前保留加载检查；检查早于实参和赋值右侧的求值。实际代码装载由后续执行及链接领域提供。 |
| part、URI/具名 part of | 读取官方 analyzer 返回的库单元，在转换前检查所有单元的 error 诊断。 |
| 相对、file:、package: URI | 支持源码导入 URI 的 analyzer 解析；API 输入仍为文件路径。 |
| package configuration v2 | 使用首个输入库的包上下文，保留 package URI 身份并检查包语言版本。 |
| main 入口 | `LoweringResult.entryPoint` 保留首个库导出命名空间中的 main 声明身份，包括再导出。原生支持无参数的同步及 async 入口，正常结束退出码为 0，返回值不作为进程退出码。返回后处理微任务、定时器和终结事件，未捕获的异步错误到达进程边界；启动参数及完整进程生命周期待实现。 |
| StackTrace API | 同步原生 throw 与 `StackTrace.current` 捕获调用链，包括原生回调重入前的暂停帧；catch/rethrow 保留关联轨迹。`StackTrace.fromString`、`empty` 与文本读取可用；捕获轨迹按调用顺序输出帧地址，函数名、源码位置及异步帧尚未提供。`Error.stackTrace` 读取首次抛出的轨迹；`Error.throwWithStackTrace` 在首次抛错时记录传入轨迹，后续抛错不覆盖；记录不调用用户覆盖的 getter，仅实现 Error 接口的类不获得隐藏存储。见[原生异常验证](../test/compiler/exceptions_test.dart)。 |
| isolate、消息端口与 spawn | 调用保留普通 SDK 导入；isolate 的创建、消息调度及线程进入协议待开发。 |

[库与命名空间行为对照](../test/frontend/lowering/libraries_test.dart)、[包上下文与诊断对照](../test/frontend/lowering/lowering_test.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/libraries.md)。

SDK 成员按已解析的声明生成普通调用、方法提取或扩展调用；未提供函数体时保留导入身份。普通顶层函数和类静态方法的 Dart 函数体支持别名、再导出、函数提取、默认参数及继续引用其他函数；静态方法不要求先提供类的实例布局。范围检查的成功分支与 SDK 对照，失败分支保留构造和抛错操作。引用的 SDK 非 external 构造器会纳入所属类、父类及普通实例成员；有 Dart 函数体的工厂和重定向目标通过相同路径转换；整数移位也纳入负计数所需的 ArgumentError 类。ArgumentError 的生成式构造器和 message、name、invalidValue 属性已通过原生验证。SDK 的 MapEntry 重定向构造及 Iterable.map 使用的工厂体已有[原生验证](../test/compiler/maps_test.dart)；SDK extension 的普通 Dart 函数体沿相同依赖路径纳入，包含 3.14 的 TypedData rangeEquals；未纳入类的实例成员仍有缺口；external 声明所需原语也未完整实现。RangeError.checkNotNegative 的成功和失败分支已原生执行，保留实际 RangeError 的 invalidValue、start、end 与字符串 message。ArgumentError、RangeError、StateError 和 UnsupportedError 的格式化已接通，包括值文本转义。其他错误类型及 StackTrace 的符号化、源码位置仍有缺口。缺少原生依赖时拒绝生成产物。见[SDK 函数体对照](../test/frontend/lowering/sdk_functions_test.dart)、[原生依赖拒绝](../test/compiler/compiler_test.dart)及[SDK 调用与用户重写测试](../test/frontend/lowering/sdk_calls_test.dart)。

[延迟导入对照](../test/frontend/lowering/deferred_imports_test.dart)覆盖未加载、请求已发出但尚未完成、加载完成和重复加载；两个前缀指向同一库时仍各自检查。`LoadLibrary` 返回代表加载完成的 Future，`CheckLibraryLoaded` 保留可抛错的读取效果。`loadLibrary` 的隐式函数保留普通调用和函数值身份。普通 extension 声明不能通过 deferred 导入，由 analyzer 检查。

SDK 3.13.7 接受 deferred 前缀下的具名构造器提取，却将[无名 `.new` 提取](../test/frontend/lowering/fixtures/deferred_unnamed_tearoff.dart)诊断为不是构造器引用；analyzer 14.7 接受后者。IR 对该用例保留已解析构造器及加载检查，并独立验证其结果，不将它计入 SDK 执行对照。

## 微任务、事件与终结回调

支持 `scheduleMicrotask`、`Timer`、`Timer.run` 和 `Timer.periodic`，包括取消、isActive、tick 与负时长按零处理。复用 SDK Zone 的 Dart 实现；`Finalizer` 在创建 Zone 内调用，未处理异常经该 Zone 的处理器转交。根 Zone 未处理的异步异常终止原生入口。Zone 值及错误处理、微任务优先级、定时取消、零周期回调、同一目标的多次终结和回调内 GC 见[调度与终结验证](../test/compiler/finalizers_test.dart)。

`Future` 的普通、value、error、sync、microtask、delayed 构造，then、catchError、whenComplete、wait、any、forEach 和 timeout 通过官方 Dart 函数体原生执行。`Completer` 与 `Completer.sync` 保留异步/同步通知顺序、Future 结果接续、重复完成拒绝、错误及关联轨迹。回调在注册 Zone 中执行，结果与捕获对象在回收后保持有效；不匹配的 catchError 返回值产生 ArgumentError。record 的 `.wait` 支持异类结果组合与 ParallelWaitError 的逐字段结果、错误聚合。见[Future 执行验证](../test/compiler/futures_test.dart)和 [SDK Future 契约](../sdk/std/lib/async/future.dart)。async/await 原生执行见[异步函数验证](../test/compiler/async_functions_test.dart)。Stream 和 isolate 原生执行仍未交付。

动态库在最外层同步 Dart 入口返回前处理待执行事件。重入的 FFI 入口不启动第二个事件循环；持续活动的周期定时器会使这次调用保持运行。卸载库只释放存储，不启动新回调。外部线程和异步宿主驱动入口尚未接通。

## URI 编解码

`Uri.encodeComponent`、`encodeQueryComponent`、`encodeFull` 及对应的 decode 方法支持原生执行和函数值调用；编码直接复用固定 SDK 的 [uri_encode_patch.dart](../sdk/std/lib/_internal/vm_shared/lib/uri_encode_patch.dart)，解码与 `splitQueryString` 复用 [core/uri.dart](../sdk/std/lib/core/uri.dart)。component、query 和 full 保留各自的字符集合，query 将空格与加号按表单规则转换；查询参数拆分保留 SDK 的重复键、无值键与空键规则。

UTF-8、Latin-1、ASCII 及允许畸形 UTF-8 的 Encoding 配置已做[原生对照](../test/compiler/object_text_test.dart)，包括控制字符、孤立代理项、非法百分号和非法字节序列。错误仍以 ArgumentError 或 FormatException 传播。URI 对象的完整构造、解析、路径处理和 `Uri.base` 尚未接通，仍依赖大小写转换、RegExp 与平台环境能力；上述编解码范围不代表完整 Uri 支持。

## 数学函数

直接调用 `dart:math.sqrt` 保留官方声明身份，支持导入前缀与转导；同名用户函数或静态方法仍调用用户实现。输入先转换为 double，再计算平方根；保留负零，其他负值和 NaN 返回 NaN，正无穷返回正无穷。依据为 [sqrt 库契约](https://api.dart.dev/stable/3.13.7/dart-math/sqrt.html)。

IR 支持 num 参数及 dynamic 实参的类型检查，实参只求值一次。原生调用要求输入具有已知的 int 或 double 表示，可用于当前支持的独立程序和原生库。函数值调用、需要装箱的 num 原生执行及其他数学函数仍是缺口。见[声明与类型检查验证](../test/frontend/lowering/math_test.dart)、[原生行为验证](../test/compiler/math_test.dart)和[独立进程验证](../test/compiler/entry_test.dart)。

## 独立程序入口

入口选择遵循主规范的 Scripts 条款，使用根库导出命名空间中的 main，不按依赖遍历顺序查找同名函数。`Compiler.compile(output: const Output.executable())` 和 CLI `--kind exe` 接通现有标量函数的独立执行。整个输入依赖图先完成静态检查，未使用代码的错误仍拒绝编译。

无参数同步及 async 入口可调用当前已接通的 Dart 函数和显式绑定的原生函数。事件队列正常排空后退出码为 0；main 的 Dart 返回值不作为进程退出码。main 返回后先处理微任务，再执行终结和定时事件；每个事件结束后重新处理微任务，直到队列为空才释放堆。定时器使用单调时钟及平台等待，取消的定时器不再保活。返回 Future 的入口及 async main 使用同一事件队列；未捕获的异步错误使进程失败。只有未完成 Future 而没有待执行事件时，不额外保活进程。具有参数的入口、I/O 事件源和跨线程唤醒仍是实现缺口。

Linux ARM64/x86-64 的静态输入生成固定地址 ELF，无需动态加载器；提供 `LinkInput.sharedLibrary` 时生成 PIE，由目标 GNU 动态加载器解析函数、数据地址及装载重定位，只读地址表在重定位后受 RELRO 保护。缺失依赖或符号在装载时失败，见[入口执行验证](../test/compiler/entry_test.dart)与[重定位验证](../test/linker/address_relocations_test.dart)。动态入口不改变现有进程退出协议；原生库终结、musl 加载器及无加载器的静态 PIE 尚未接通。macOS 输出使用 LC_MAIN、系统 dyld 和 ad-hoc 签名，并支持显式动态库依赖。macOS x64 具有结构检查，尚无该目标的实际执行证据。

[入口执行验证](../test/compiler/entry_test.dart)检查正常完成、忽略 Dart 返回值、跨库入口、只读/可写/BSS 数据和指针重定位，以及明确拒绝未支持入口。[独立编译器验证](../test/compiler/standalone_test.dart)通过预编译 CLI 在空 PATH 下生成并执行程序；[链接契约](../test/linker/linker_test.dart)检查入口地址、归档成员选择及非法入口。

## 原生库

`package:dartc/interop.dart` 的 `@Export<T>(symbol: ...)` 声明原生函数导出，`T` 使用 `dart:ffi` 函数类型。绑定依据注解声明身份，符号默认采用函数名。静态库、动态库和目标文件使用同一份声明，并可生成 C/C++ 头文件。

| 项目 | 当前原生范围与缺口 |
| --- | --- |
| 导出签名 | 同步、非泛型的顶层函数；参数和结果支持 `Int8/16/32/64`、`Uint8/16/32/64`、`IntPtr`、`UintPtr`、`Bool`、`Float`、`Double`、`Pointer<T>` 和 Struct/Union 按值传递。对应 Dart `int`、`bool`、`double`、保留元素类型的指针及原聚合声明类型；`Void` 只用于结果。指针可嵌套并指向 NativeFunction 或 Opaque。聚合按输出目标分类到整数/浮点寄存器、栈或间接存储，保留按值复制；不把 Dart 对象引用当作 C 地址。 |
| 函数与不透明指针 | `Pointer<NativeFunction<T>>`、`Pointer<Void>` 及所支持类型的多级指针可作为参数和结果、从地址构造、读取地址及比较；普通 Dart 调用、分支和循环保留地址及语义类型，头文件保留嵌套函数指针声明。相等只取决于地址，不同元素类型不影响指针相等。Void 和 NativeFunction 不具有元素存储大小；指向它们的指针具有存储大小，支持存入和读出指针槽。生成原生回调尚未接通。 |
| 已绑定原生调用 | 独立 `CodeGenerator.generate` API 接受以 `IrExternal.target` 为键的 `imports`，由 `NativeImport` 明确原生符号、上述标量签名及 `isLeaf`。Dart 参数在出站边界转换，原生结果按宽度/精度转换回 Dart 值；指针类型允许兼容的参数收窄和结果扩大。调用者存活值及写入副作用保留，参数遵循目标平台寄存器和栈布局。绑定必须匹配外部声明，缺失或不匹配均报错；原生实现由链接输入提供。从 Dart 函数生成原生回调、跨线程调用及持久托管句柄仍未接通。 |
| `@Native` | 支持顶层和静态 external 函数、变量及 getter；变量支持上述标量、指针、Struct/Union，共享实际原生存储，赋值保留宽度转换与按值复制，final/getter 禁止重绑定。前端按 SDK 声明身份保留资产 ID、符号、原生签名及 `isLeaf`，支持常量别名；缺省资产依次取 `DefaultAsset` 和所属库 URI，part 使用所属库默认值，缺省符号采用声明名。省略类型实参时支持从指针、Struct/Union 和 void 结果推断。`LoweringResult.imports` 交付按声明身份绑定的 `NativeReference`；`Compiler.compile(nativeSymbols: ...)` 按资产 ID 与请求符号查找显式链接符号，shared/executable 输出由 `linkInputs` 提供实现，object/archive 输出保留未决引用。未使用声明仍检查静态义务，未引用的合法导入不要求绑定。Native.addressOf 保留原生函数或数据符号的真实地址，取地址不调用函数或读取字段；支持静态链接与共享库地址重定位。自动资产发现、运行时 resolver/进程回退查找、实例接收者及完整 FFI 类型仍未接通。当前后端支持同步入口内不逃逸的托管对象；`isLeaf` 保留声明承诺，跨线程及异步托管调用转换仍未实现。 |
| 间接原生调用 | 独立 IR/CodeGenerator API 支持 `NativeCall`，从 `Pointer<NativeFunction<T>>` 的完整类型推导签名并检查 Dart 实参；参数和结果执行上述原生边界转换，函数地址通过寄存器调用，无须符号绑定。地址和其他活跃值经过寄存器覆盖、栈传参、分支及循环保持有效。IR 保留 `isLeaf` 承诺，当前后端支持同步标量/指针调用和入口内对象存活；支持从闭包发起调用，跨线程托管调用协议尚未接通。 |
| `asFunction` | 前端按 `dart:ffi` 声明身份将调用转换成捕获当时指针值的普通闭包 IR，其函数体执行 `NativeCall`。支持显式/推断 Dart 函数类型、显式 extension override、空参数/void 结果、上述标量和指针签名及兼容的指针返回类型扩大；`isLeaf` 按常量参数求值，默认 false。返回的函数可经普通 IR 的返回、局部变量、集合、分支、循环、动态调用及嵌套闭包使用。同名用户方法仍是普通调用。已接通同步闭包的原生调用，保留捕获指针、参数及返回对象经过回收后的地址与身份；原生 ABI 接点传递原始地址。`asFunction` 方法本身的提取与间接调用、Dart 原生回调及跨线程协议仍待接通。 |
| 标量 TypedData | 支持十一种整数/浮点 List、ByteData、ByteBuffer 视图、view/sublistView/fromList、独立 sublist、只读视图、重叠 setRange、大小与对齐检查、大小端和非对齐 ByteData 访问。视图长度和偏移在乘加溢出前验证。托管和 FFI 视图保留存储拥有者。两个同类数值 TypedData 列表拼接遵循 SDK API 文档，返回可容纳两边值的 TypedData；固定 SDK 3.14.0 的 VM 当前返回普通 List，此项使用独立预期。原生指针 asTypedList 支持可选 NativeFinalizer 回调与 token，派生视图保留同一存储拥有者，最后一个视图失去引用后才允许回收。整数列表和 ByteData 支持 3.14 的 rangeEquals，保留切片、空区间和范围检查。SIMD 列表及 3.14 的 SIMD 新增 API 仍待实现。 |
| 原生聚合存储 | 支持 Struct/Union 的标量、指针和嵌套聚合字段、`@Packed`、`sizeOf<T>()`、`Struct.create<T>()`/`Union.create<T>()`（含 TypedData 与元素偏移），以及结构体指针的 `ref`、索引和元素偏移。托管存储初始化为零；嵌套视图保留所属存储，按值参数独立复制，调用及复制期间保留 GC 根。`@Export`、`@Native` 和 `asFunction` 共用声明与目标布局。固定内联 Array 支持标量、指针、Struct/Union 元素及多维索引；索引越界抛出 RangeError，数组字段与行赋值按目的区域大小复制，嵌套视图保留 GC 拥有者。数值 Array 的 elements 返回共享存储的 TypedData 视图；可变长度数组及完整 AbiSpecificInteger 家族仍待实现。 |
| 聚合头文件 | 生成 Struct/Union 字段、内联数组、嵌套依赖、递归指针和 Opaque 前向声明，包含固定宽度整数、bool 与 packing；重复 C 标签、非法标识符和按值递归被拒绝。当前原生执行覆盖 macOS ARM64、Linux ARM64/x86-64；未以外部 C/C++ 编译器验证所有头文件形状。 |
| 函数体 | 整数常量、加法、减法、乘法、截断除法、欧几里得取模、remainder、按位与/或/异或/取反及相应复合赋值、有符号比较，整数与布尔值的相等/不等比较；整数运算保留 64 位环绕结果，`int / int` 产生 double。支持条件表达式、逻辑短路、if/else、while/do/for、含标签的 break/continue、多返回，以及批次内跨库调用和递归。Dart 函数间的直接调用支持可选位置参数、命名参数及常量默认值；原生导出仍只接受必需位置参数。同步异常与清理见[原生异常范围](statements.md#原生异常与清理)，对象存储见[类的原生范围](classes.md#原生执行范围)。除零与负移位按 Dart 异常路径传播，保留 catch/finally；三种整数移位保留完整计数及 64 位边界；async/await 和 sync* 已原生执行，async* 与 Stream 的原生路径仍待接通，见[函数](functions.md)。 |
| 浮点 | 支持静态 int/double 操作数的混合加、减、乘、IEEE 除法、全部数值比较及 `toDouble`，另支持 double 常量和取负；比较保持整数的原始数值，不因算术转换而丢失精度。保留 NaN、无穷、次正规数和正负零行为，不做融合乘加或 fast-math 改写。参数、结果、分支汇合和调用保持 double 表示。部分混合数值常量表达式尚未实现，见[数值比较](expressions.md#数值比较与-sdk-差异)。toInt/truncate/floor/ceil/round 支持已知和装箱数值，保留整数精度、有限溢出饱和和非有限异常。已接通保留 double 结果的舍入方法及浮点、混合和装箱 `~/`；abs/sign、分类查询、compareTo/clamp 及装箱 num 的四则运算已接通；浮点 %/remainder 及数字格式化已接通；完整数学库尚未接入。当前执行验证使用 SDK 宿主的默认浮点控制环境，非默认控制状态尚未验证。 |
| WeakReference | 支持泛型工厂、构造器提取和只读 `target`。弱引用不会保活目标；普通强引用保留目标，失去强引用后允许清空。原生验证覆盖用户对象、自引用环、集合、闭包、类型对象、常量和跨导出调用存活，以及数值、字符串、布尔值和 FFI 指针的 `ArgumentError`。records 与 Struct/Union 的弱目标拒绝路径尚未验证。见[源码与原生验证](../test/compiler/weak_references_test.dart)。回收时机和是否清空不构成语言保证。 |
| Expando | 支持可选名称、构造器提取、`name`、`toString`、按对象身份读取/替换属性及写入 null 删除；相同名称的实例互不共享属性。不调用键的重写 hashCode/==；写入保持实际泛型值类型检查。GC 仅在 Expando 与 key 均存活时保留 value，支持跨 Expando 的条件依赖与循环回收。数值、字符串、布尔值和 FFI 指针键抛出 ArgumentError，动态 null 参数受非空类型检查；records、Struct/Union 的目标表示仍缺。见[源码与原生验证](../test/compiler/expandos_test.dart)。 |
| 终结 | `Finalizer<T>` 支持可空 token、多重附着、弱 target/detach key、创建 Zone 绑定及至多一次的事件回调。detach 也取消尚未执行的回调；失去 finalizer 本身的强引用不保留其记录。GC 仅入队，回调可分配并再次触发 GC；关闭堆丢弃剩余附着，不强制调用回调。`NativeFinalizer` 使用真实原生函数指针，callback getter 返回原指针，在 GC 完成后执行；附着记录保留终结器，解绑取消回调，外部存储计量影响回收压力，正常进程退出与动态库卸载执行剩余回调。异常终止不保证回调。`Finalizable` 的静态类型、可空类型、类型参数边界和 FutureOr 保留作用域存活；覆盖参数、this、闭包、late 变量、覆盖赋值、循环及 Never 退出。跨线程和 isolate 生命周期仍待实现。见[原生资源测试](../test/compiler/native_finalizers_test.dart)。 |
| 字符串 | 支持 UTF-16 常量、fromCharCode/fromCharCodes、codeUnits/runes、索引、连接、重复、内容比较/哈希、切片、搜索、替换、分割、填充和 Unicode 空白裁剪。String 实现 Pattern，支持用户 Pattern 与替换回调；载荷在 GC 与跨入口存储中保持有效。插值使用已支持接收者的普通 toString；Unicode 大小写转换、RegExp 和其余文本库仍待接通；见[字符串范围与验证](expressions.md#原生转整数与字符串常量)。 |
| `dart:convert` | 支持 JSON 编码、解码、缩进、转换回调和分块解码，以及 UTF-8 编解码、分块解码和组合 JSON 解码。保留无效输入、循环容器和回调异常；其余转换器尚未验证。见[契约与 SDK 差异](expressions.md#json-与-utf-8)。 |
| 参数与存储 | ARM64 的前八个、x86-64 的前六个原生整数或指针参数使用通用寄存器；两者另有八个由 `Float` 和 `Double` 共用的浮点参数寄存器，与通用寄存器独立分配。各类超出的参数按源顺序使用栈：macOS ARM64 按实际大小自然对齐，Linux ARM64 与 x86-64 使用八字节槽。Dart 函数间另支持布尔参数及结果，不隐式扩展原生导出签名。分支、循环和调用之间保留活跃值，块参数遵循同时赋值语义；栈帧保持 16 字节对齐及帧指针链，出参区与局部存储分开。ARM64 帧支持保存 D8–D15 的低 64 位，x86-64 的标量浮点寄存器均按调用可破坏处理。超出当前栈访问、栈帧或分支/调用位移编码范围时明确报错。 |
| 原生指针 | 支持上述整数、Float 和 Double 元素类型的 `Pointer<T>.fromAddress`、`.address`、相等/不等比较、`+`、`-`、`elementAt`、`.value` 及 `[]`/`[]=` 读写，包括增减和复合赋值。偏移和索引以元素计数，允许负值，地址运算保留目标指针位宽；计算地址不访问存储。整数读取按有符号/无符号规则扩展，写入截断到元素宽度；Float 使用四字节存储，写入舍入精度、读取转换为 double；Double 使用八字节存储。写入不改变原 Dart 变量或赋值表达式的值，不影响邻接字节。接收者、索引及右值按 Dart 顺序各求值一次，别名修改可见。访问要求有效、存活且按元素大小自然对齐的原生存储；不进行集合边界检查，不将机器访存失败当作 Dart 异常。其他元素存储类型、结构体、回调及分配器尚未接入。 |
| 指针槽 | `Pointer<Pointer<T>>` 支持 `.value`、`[]`/`[]=`、`+`、`-` 和 `elementAt`，包括开放的 `T extends NativeType`。当前 64 位目标的每个槽占八字节；存入地址，读出保持 `Pointer<T>` 类型的值，不读取其指向的内容。零地址及完整地址位保留，相邻槽不受写入影响；读出的指针经过普通调用、托管保存和 GC 后保持有效。函数指针槽保留原生签名，可用于同步 `asFunction` 调用。槽存储须由调用方保证有效、存活及自然对齐。 |
| 指针重解释 | `Pointer.cast<T>()` 保留地址并返回所请求元素类型的指针，不读取或验证该地址处的存储。支持直接调用、开放泛型实参、null-aware 短路以及绑定方法值的提取与实例化；目标包括已支持的原生标量、嵌套指针、NativeFunction 和 Never。方法值保留接收者经过回收后的地址，同名用户方法保持普通调用。 |
| 文件与链接 | Dart 实现 Mach-O/ELF 目标文件读写、带符号索引的静态归档读写及动态库编码；Mach-O 包含导出树和 ad-hoc 签名，部署下限为 macOS 11。生成与链接不要求匹配宿主，也不调用外部工具。模块区分局部定义、全局可链接定义和公开导出；对象与归档保留跨节调用和地址引用，动态库只公开导出符号。链接输入为有序对象、归档和显式共享库依赖，按未决引用选择归档成员；纳入链接的全局重名、冲突绑定和未解析引用报错。 |
| 跨共享库符号 | `LinkInput.sharedLibrary(name, symbols: ...)` 将未决对象符号映射到装载器的原生符号名，两者均包含平台符号修饰；对象和已选归档定义优先。依赖顺序保留，相同库名合并，即使没有引用也保留依赖。Mach-O 绑定指定库，ELF 遵循全局符号查找顺序，不能用 ELF 库依赖冒充 Dart 资产隔离。支持函数调用，以及通过间接地址重定位取得数据和真实函数地址；地址槽在装载时解析，缺库或缺符号导致装载失败。`Compiler.compile(linkInputs: ...)` 可使用同一路径；链接器不读取依赖库或验证其导出。自动资产发现和 Dart resolver/进程回退仍是缺口。 |
| 数据存储 | 独立 object/linker API 支持只读、可写及零初始化节，保留节对齐、数据符号及跨模块寻址；共享库分别映射可执行、只读和可写内存，BSS 不占用对应的文件字节。直接地址使用 ARM64 ADRP/ADD 或 x86-64 RIP 相对 LEA；加载符号内容使用 ADRP/LDR 或 RIP 相对 MOV。`Relocation.indirect` 明确将后两种加载的目标改为保存符号地址的槽，支持局部、静态和共享库定义；静态地址槽随映像装载修正。超出寻址范围或不符合指令对齐要求时报错。Dart 顶层/静态变量和惰性初始化使用模块存储，见[变量](variables.md#原生局部存储)；数据导出注解尚未接入。 |
| 平台验证 | macOS ARM64、Linux ARM64/x86-64 已验证原生调用；macOS x86-64 当前检查文件生成、重定位表与签名，尚无运行验证。 |
| 标准库与执行支持 | 同步入口内支持对象构造与不可达对象回收，具体范围见[类](classes.md#原生执行范围)。托管全局状态可跨入口保存；并发调用、跨线程调用、跨模块托管值 ABI、I/O 事件及一般标准库执行能力尚未实现；标准库源码可用不等于目标侧实现已经存在。 |

[原生函数验证](../test/compiler/native_test.dart)通过固定 Dart FFI 调用代码执行预编译资产，并与 SDK 对照整数边界行为。[寄存器别名验证](../test/codegen/native_test.dart)覆盖目标寄存器重叠时的实际结果。[格式验证](../test/object/formats_test.dart)检查目标标识、静态归档成员与符号索引；[签名验证](../test/linker/signature_test.dart)检查 Mach-O 签名对全部映像页的覆盖；[头文件验证](../test/compiler/artifacts_test.dart)检查导出原型。上述范围是当前后端实现进度，不改变完整语言目标。

[共享库绑定契约](../test/linker/shared_libraries_test.dart)检查依赖顺序、符号别名、可写指针槽、装载表及无效引用；[装载验证](../test/linker/native_test.dart)检查同名符号的目标平台查找规则、缺库和缺符号的具体错误。[地址验证](../test/linker/addresses_native_test.dart)检查静态对象、归档和共享库的函数地址身份、数据初始化与双向修改，以及本地地址槽；[重定位契约](../test/object/indirect_relocations_test.dart)检查指令形式、直接/间接引用和损坏记录。[调用验证](../test/codegen/native_calls_test.dart)使用同一组窄整数、Float、混合栈参数、副作用和跨调用存活用例执行独立共享库；[编译验证](../test/compiler/native_imports_test.dart)覆盖源码 `@Native` 到共享库依赖的完整路径。

[整数运算对照](../test/compiler/integer_operations_test.dart)覆盖乘法和截断除法溢出、两种余数的符号、除零与清理、三种移位的完整计数与负计数错误载荷、按位与/或/异或/取反、复合赋值、重复与重叠操作数，以及调用和循环中的值保存；使用正负边界、跨 32 位值及交替位模式对照 SDK。

[指针对照](../test/compiler/pointers_test.dart)检查地址往返、整数边界读写、寄存器与栈的混合参数、跨调用及循环存活、别名修改和复合赋值顺序。[FFI 声明绑定验证](../test/frontend/lowering/ffi_test.dart)检查同名用户类型和 extension 不被替换为原生操作，以及 int 界限用于地址和索引、对应的 int/double 界限用于存储值；[泛型构造源码验证](../test/compiler/managed_objects_test.dart)检查这些参数在嵌套回收后的原生存储结果。[IR 契约](../test/ir/native_memory_test.dart)检查语义类型和存储效果。[签名验证](../test/interop/native_signature_test.dart)与[编译拒绝验证](../test/compiler/compiler_test.dart)覆盖不支持及不匹配的类型。

[函数指针验证](../test/compiler/native_function_pointers_test.dart)检查签名、地址往返、嵌套函数指针、原生栈参数及跨调用存活；返回的函数指针由 SDK FFI 实际调用。[签名契约](../test/interop/native_signature_test.dart)验证不能按值传递函数类型、递归 C 声明及完整签名相等性。类型依据为 [NativeFunction](https://api.dart.dev/stable/3.13.7/dart-ffi/NativeFunction-class.html) 与 [asFunction](https://api.dart.dev/stable/3.13.7/dart-ffi/NativeFunctionPointer/asFunction.html)；C 声明按 [N1570 §6.7.6.1/§6.7.6.3](https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf)的指针与函数声明规则生成。

[间接调用契约](../test/ir/native_calls_test.dart)检查函数指针类型、实参数量、完整嵌套签名、SSA 归属及调用效果。[原生调用验证](../test/codegen/native_calls_test.dart)以相同用例检查已绑定调用与函数指针调用，覆盖窄整数、Float、混合及紧凑栈参数、写入副作用和跨调用存活；原生提供方主动覆盖调用者保存寄存器，函数地址另经过栈传入、分支选择和循环调用。

[`asFunction` 转换验证](../test/frontend/lowering/ffi_test.dart)检查签名、捕获及未使用声明的静态义务；[行为验证](../test/frontend/lowering/ffi_functions_test.dart)由参考执行器运行闭包 IR，经固定 SDK FFI 客户端调用预构建的 dartc 原生函数，检查返回后调用、指针重赋值、函数保存、求值顺序、null-aware 短路和 finally。[原生闭包验证](../test/compiler/pointer_values_test.dart)执行返回后保留的 `asFunction` 闭包，检查指针参数、返回值和移动回收后的调用。

在 macOS ARM64 的 SDK 3.13.7 上，JIT/AOT 编译入口拒绝 `isLeaf: 1 + 1 == 2`，却接受同一表达式声明的 const 变量；analyzer 14.7 接受内联表达式。根据[常量参数契约](https://dart.dev/tools/diagnostics/argument_must_be_a_constant)，dartc 对这个[固定反例](../test/frontend/lowering/fixtures/ffi_constant_leaf.dart)按常量 `true` 转换并验证调用，不以该 SDK 拒绝行为作为预期。

[`Pointer.cast` 验证](../test/compiler/pointer_values_test.dart)检查零地址、负地址、未对齐地址、泛型与嵌套指针、方法值和回收后调用，不解引用存储；预期地址直接取输入，SDK 另作对照。契约依据为 [`Pointer.cast`](https://api.dart.dev/stable/3.13.7/dart-ffi/Pointer/cast.html)。

[指针偏移与索引验证](../test/compiler/pointer_arithmetic_test.dart)覆盖各标量元素宽度、负偏移、地址回绕、索引读写及相邻字节、增减和复合赋值的求值顺序、别名与跨调用存活。预期地址由整数公式独立计算；SDK 另作对照。规范依据为对应元素类型的标准库契约，包括 [Int32Pointer.operator +](https://api.dart.dev/stable/3.13.7/dart-ffi/Int32Pointer/operator_plus.html)、[operator -](https://api.dart.dev/stable/3.13.7/dart-ffi/Int32Pointer/operator_minus.html)、[operator []](https://api.dart.dev/stable/3.13.7/dart-ffi/Int32Pointer/operator_get.html) 与 [FloatPointer.operator []=](https://api.dart.dev/stable/3.13.7/dart-ffi/FloatPointer/operator_put.html)。

[内存循环验证](../test/compiler/runtime_test.dart)通过直接调用与函数值调用复制、清零 `Pointer<Int64>` 指向的区域，检查零长度、原始位模式、源区域不变和相邻存储不被改写；身份观察及持久保存仍由[指针对象验证](../test/compiler/pointer_values_test.dart)覆盖。

[原生整数验证](../test/compiler/native_integers_test.dart)检查各宽度的正负边界、截断与扩展、邻接字节保护、IR 与原生访问、注解函数的普通 Dart 调用，以及窄整数与浮点混合栈参数。整数读写预期由元素位宽独立计算；SDK 对照不替代该预期。规范依据包括 [Int8Pointer.value](https://api.dart.dev/stable/3.13.7/dart-ffi/Int8Pointer/value.html)、[Uint8Pointer.value](https://api.dart.dev/stable/3.13.7/dart-ffi/Uint8Pointer/value.html)及对应宽度的标准库契约。

[原生浮点存储验证](../test/compiler/native_floats_test.dart)检查 Float 参数与结果、普通调用保持 double 精度、Float/Double 指针读写、复合赋值及混合栈参数。默认浮点环境下的舍入预期使用明确的 binary32 位模式，覆盖中点、次正规数、溢出、正负零与 NaN；另与 SDK 对照。规范依据为 [FloatPointer.value](https://api.dart.dev/stable/3.13.7/dart-ffi/FloatPointer/value.html) 和 [DoublePointer.value](https://api.dart.dev/stable/3.13.7/dart-ffi/DoublePointer/value.html)。

[出站调用验证](../test/codegen/native_calls_test.dart)执行独立原生被调函数，检查整数截断/扩展、Float 参数和结果、调用者原值存活、指针与 void 副作用、21 个混合参数及原生栈布局；混合调用同时经 SDK FFI 验证。[绑定契约](../test/codegen/native_imports_test.dart)检查声明身份、签名拒绝、符号别名与未决引用。

[`@Native` 声明验证](../test/frontend/lowering/native_imports_test.dart)检查默认资产、part、别名、静态方法、类型推断与未使用声明；[编译和执行验证](../test/compiler/native_imports_test.dart)覆盖不同资产中的同名符号、缺失绑定、窄整数转换、指针返回类型扩大及三种输出。声明规则依据 [Native](https://api.dart.dev/stable/3.13.7/dart-ffi/Native-class.html) 和 [DefaultAsset](https://api.dart.dev/stable/3.13.7/dart-ffi/DefaultAsset-class.html)；运行时查找顺序仍是实现缺口。

[浮点对照](../test/compiler/doubles_test.dart)检查 double 运算与全部比较、NaN、无穷、次正规数、负零和取负后的 NaN 载荷；覆盖两类寄存器耗尽、十九个混合参数及栈溢出、常量参数、调用保存和循环交换。[ABI 执行验证](../test/abi/native_test.dart)检查浮点局部存储及 ARM64 的被调用者保存标量寄存器；[布局检查](../test/abi/layout_test.dart)区分通用/浮点位置、破坏集合和栈偏移。

[混合数值验证](../test/compiler/mixed_numeric_test.dart)用二进制浮点的精确整数比例检查六种比较、两种操作数顺序、2^53 和 64 位边界及 NaN；算术和转换另与 SDK 对照。固定客户端还检查转换临时值、寄存器压力、调用、循环及原生写入顺序。

[独立链接验证](../test/linker/native_test.dart)调用预先链接的多目标文件与大符号表资产。[链接契约验证](../test/linker/linker_test.dart)覆盖确定性、局部符号隔离、重复全局定义和未解析引用；[输出保护验证](../test/compiler/compiler_test.dart)覆盖源文件和输出路径冲突。

[数据访问验证](../test/linker/data_native_test.dart)检查跨模块常量读取、可写数据与大块 BSS 的初值及重复修改、同名局部数据隔离，以及 Dart FFI 对导出数据的直接访问。[数据格式验证](../test/object/data_sections_test.dart)检查节、地址重定位、归档索引、文件/内存大小和映像权限；链接契约同时拒绝把数据当函数调用、地址越界和布局溢出。

[对象读取验证](../test/object/reader_test.dart)覆盖当前生成的四种目标对象、重新编码/链接、符号别名、输入所有权及损坏记录。读取范围为小端 ELF64/Mach-O 可重定位文件中的既有代码、只读数据、可写数据、BSS 和清理指针节，以及当前调用/地址引用形式。其他节和指令引用形式、弱/公共符号、非零符号 addend 等明确拒绝。Mach-O 缺少的符号类型和长度保留为未知；ELF 有明确记录时保留。固定原生函数与数据用例的资产由磁盘对象读取后重新链接。

`Archive.decode` 读取 GNU 与小端 Darwin 的 32 位符号索引归档，保留成员和索引顺序，包括重名候选、GNU 长名称及 BSD 扩展名称。成员头、边界、填充、索引字符串与成员偏移均须有效；成员内容在选中后才按目标对象格式解释。thin 归档、64 位索引及无索引归档尚不支持。见[归档读取验证](../test/object/archive_test.dart)。

`Linker.linkSharedLibrary` 接受 `LinkInput.object` 和 `LinkInput.archive`。Linux 在每个归档的输入位置按索引顺序选择当前未决符号所需的成员，反复扫描该归档；后续输入引入的新引用需要再次列出较早的归档。macOS 先纳入所有显式对象，再为未决符号按归档顺序选择第一个候选，持续处理新引用。未选成员不产生重复定义、未决引用或对象格式错误；选中成员的所有定义和导入均参与链接，不进行成员内裁剪。见[成员选择验证](../test/linker/archive_test.dart)；固定函数和数据资产同时覆盖归档链接后的原生执行。

[跨文件调用验证](../test/compiler/calls_test.dart)覆盖参数换位、重复参数、常量参数、跨调用活跃值、寄存器溢出和导出可见性。[重定位格式验证](../test/object/relocations_test.dart)检查对象文件的引用索引、局部/全局/未定义符号及位移规则。

[栈参数验证](../test/compiler/stack_calls_test.dart)对照 SDK 检查十参数入口、十及十一参数调用、嵌套调用、参数轮换与整数边界；[独立 ABI 调用](../test/abi/native_test.dart)通过另一个目标模块传递栈参数。[位置契约](../test/abi/layout_test.dart)检查参数位置、栈区大小和非法输入；[栈访问边界](../test/codegen/arguments_test.dart)检查机器位移上限。

[原生控制流对照](../test/compiler/control_flow_test.dart)覆盖整数边界比较、布尔辅助函数、短路副作用、循环的零次/一次/多次执行、嵌套循环及标签转移、循环变量轮换和递归返回。[图交接验证](../test/codegen/native_test.dart)覆盖同目标的不同边参数、乱序块布局和空块；[控制流编码验证](../test/codegen/control_flow_test.dart)检查不返回的循环。[同步异常对照](../test/compiler/exceptions_test.dart)覆盖捕获、重抛、构造器失败、finally 的完成替换及未捕获异常退出。

## 模块清理与卸载

`Section.finalizers` 保存八字节对齐的清理函数地址槽，每个零值槽必须有一个指向模块局部代码的 `Relocation.address`。清理函数使用目标平台的无参数、无返回值原生 ABI，不是 Dart 调用 ABI。对象文件、归档及对象读取保留这些引用；ELF 共享库通过 `.fini_array` 注册清理。Mach-O 原始对象保留传统终止函数节，但宿主装载器不能仅凭该元数据保证卸载调用；dartc 的共享库链接器将其转换为装载时的 `__cxa_atexit` 注册。将原始 Mach-O 对象交给外部系统链接器不在卸载保证范围内。

含引用全局槽的模块跨同步入口保留托管堆，由 dartc 链接的共享库在实际卸载时释放；关闭一个仍有其他装载引用的句柄不会提前清理。无引用全局槽的模块仍在每次入口返回时释放堆。独立程序显式释放堆再退出，不生成清理指针节；可执行文件链接拒绝包含该节的对象及已选归档成员。此生命周期不提供并发调用、跨线程调用或跨模块托管值 ABI。

[清理节契约](../test/object/finalizers_test.dart)和[链接契约](../test/linker/finalizers_test.dart)检查格式、引用及可执行文件拒绝；[卸载验证](../test/linker/finalizers_native_test.dart)覆盖最后一个句柄关闭、归档成员与重新装载。[托管全局验证](../test/compiler/managed_globals_test.dart)覆盖跨入口回收、别名、循环、可空和 num 存储，以及 final/late 和失败或递归初始化语义。平台执行范围仍以上表为准。

## 规范依据

[主规范 §19、§6.3](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[语言版本与包配置 v2](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.8/language-versioning/package-config-file-v2.md)、[通配前缀](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/wildcard-variables/feature-specification.md#imports)、[StackTrace API](https://api.dart.dev/stable/3.13.7/dart-core/StackTrace-class.html)。

[聚合互操作验证](../test/compiler/native_aggregates_test.dart)以官方 SDK FFI 客户端检查同质浮点、混合字段、大结构体间接返回、Union、packed 字段、类型化状态、嵌套视图存活、浮点寄存器耗尽，以及原生函数指针进入 SDK 回调。调用 SDK 提供的回调不表示 dartc 已实现 `NativeCallable` 回调创建。

[TypedData 与共享原生视图验证](../test/compiler/typed_data_test.dart)覆盖宽度截断、钳位、浮点精度与位模式、字节序、重叠转换、同一原生地址的独立视图、只读缓冲、元素偏移、长度溢出及 GC 存活。
