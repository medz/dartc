# 库、脚本与并发边界

转换以调用方明确提供的库批次为单位，包含每个库的所有 part。`package:dartc/frontend.dart` 的 `AnalysisSession` 复用官方 analyzer 的解析结果；名称与指令解析不由 lowering 重复实现。`includeDependencies: true` 纳入非 SDK 导入和导出库，整个批次完成静态检查后才开始转换。导入库的函数调用保留声明身份，但只有批次内的库会生成函数体。一般 Dart 可执行程序的入口和目标运行时链接仍待实现。

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
| main 入口 | 可转换普通 main 函数体；入口选择、启动参数及进程生命周期待实现。 |
| StackTrace API | 调用保留普通 SDK 导入；catch/rethrow 保留异常与栈信息。完整运行时实现待后续执行领域提供。 |
| isolate、消息端口与 spawn | 调用保留普通 SDK 导入；isolate 与调度的运行时实现待开发。 |

[库与命名空间行为对照](../test/frontend/lowering/libraries_test.dart)、[包上下文与诊断对照](../test/frontend/lowering/lowering_test.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/libraries.md)。

SDK 成员按已解析的声明生成普通调用、方法提取或扩展调用；未提供函数体时保留导入身份。已有语义 IR 操作只替换它们明确表示的操作，其他方法不会因参考执行器缺少实现而在 lowering 阶段拒绝。SDK 实现的装配、链接及执行属于后续交付范围。见[SDK 调用与用户重写测试](../test/frontend/lowering/sdk_calls_test.dart)。

[延迟导入对照](../test/frontend/lowering/deferred_imports_test.dart)覆盖未加载、请求已发出但尚未完成、加载完成和重复加载；两个前缀指向同一库时仍各自检查。`LoadLibrary` 返回代表加载完成的 Future，`CheckLibraryLoaded` 保留可抛错的读取效果。`loadLibrary` 的隐式函数保留普通调用和函数值身份。普通 extension 声明不能通过 deferred 导入，由 analyzer 检查。

SDK 3.13.7 接受 deferred 前缀下的具名构造器提取，却将[无名 `.new` 提取](../test/frontend/lowering/fixtures/deferred_unnamed_tearoff.dart)诊断为不是构造器引用；analyzer 14.7 接受后者。IR 对该用例保留已解析构造器及加载检查，并独立验证其结果，不将它计入 SDK 执行对照。

## 原生库

`package:dartc/interop.dart` 的 `@Export<T>(symbol: ...)` 声明原生函数导出，`T` 使用 `dart:ffi` 函数类型。绑定依据注解声明身份，符号默认采用函数名。静态库、动态库和目标文件使用同一份声明，并可生成 C/C++ 头文件。

| 项目 | 当前原生范围与缺口 |
| --- | --- |
| 导出签名 | 同步、非泛型的顶层函数；参数和结果支持 `Int8/16/32/64`、`Uint8/16/32/64`、`Float`、`Double` 和这些标量类型的 `Pointer<T>`，分别对应非可空 Dart `int`、`double` 和同元素类型的指针；结果另支持 `Void`，对应 Dart `void`。原生整数边界按签名扩展或截断，Float 边界转换单精度与 double；普通 Dart 调用注解函数保留完整 int/double，不受原生签名截断。只接受必需位置参数。其他标量、指针元素类型、结构体、可变参数和数据导出尚未实现。 |
| 函数体 | 整数常量、加法、减法、乘法、按位与/或/异或/取反及相应复合赋值、有符号比较，整数与布尔值的相等/不等比较；整数运算保留 64 位环绕结果，`int / int` 产生 double。支持条件表达式、逻辑短路、if/else、while/do/for、含标签的 break/continue、多返回，以及批次内跨库调用和递归。Dart 函数间的直接调用支持可选位置参数、命名参数及常量默认值；原生导出仍只接受必需位置参数。整数截断除法、余数、移位、对象存储、异常及异步尚未接入原生后端。 |
| 浮点 | 支持静态 int/double 操作数的混合加、减、乘、IEEE 除法、全部数值比较及 `toDouble`，另支持 double 常量和取负；比较保持整数的原始数值，不因算术转换而丢失精度。保留 NaN、无穷、次正规数和正负零行为，不做融合乘加或 fast-math 改写。参数、结果、分支汇合和调用保持 double 表示。部分混合数值常量表达式尚未实现，见[数值比较](expressions.md#数值比较与-sdk-差异)。其他数值转换、浮点取模/截断除法、compareTo 及完整数学库尚未接入。当前执行验证使用 SDK 宿主的默认浮点控制环境，非默认控制状态尚未验证。 |
| 参数与存储 | ARM64 的前八个、x86-64 的前六个原生整数或指针参数使用通用寄存器；两者另有八个由 `Float` 和 `Double` 共用的浮点参数寄存器，与通用寄存器独立分配。各类超出的参数按源顺序使用栈：macOS ARM64 按实际大小自然对齐，Linux ARM64 与 x86-64 使用八字节槽。Dart 函数间另支持布尔参数及结果，不隐式扩展原生导出签名。分支、循环和调用之间保留活跃值，块参数遵循同时赋值语义；栈帧保持 16 字节对齐及帧指针链，出参区与局部存储分开。ARM64 帧支持保存 D8–D15 的低 64 位，x86-64 的标量浮点寄存器均按调用可破坏处理。超出当前栈访问、栈帧或分支/调用位移编码范围时明确报错。 |
| 原生指针 | 支持上述整数、Float 和 Double 元素类型的 `Pointer<T>.fromAddress`、`.address`、相等/不等比较及 `.value` 读写，包括增减和复合赋值。整数读取按有符号/无符号规则扩展，写入截断到元素宽度；Float 使用四字节存储，写入舍入精度、读取转换为 double；Double 使用八字节存储。写入不改变原 Dart 变量或赋值表达式的值，不影响邻接字节。保留接收者与右值的求值顺序及别名可见性。访问要求有效、存活且按元素大小自然对齐的原生存储；不检查无效地址，也不将机器访存失败当作 Dart 异常。指针算术、索引、cast、其他元素类型、结构体、回调及分配器尚未接入。 |
| 文件与链接 | Dart 实现 Mach-O/ELF 目标文件读写、带符号索引的静态归档读写及动态库编码；Mach-O 包含导出树和 ad-hoc 签名，部署下限为 macOS 11。生成与链接不要求匹配宿主，也不调用外部工具。模块区分局部定义、全局可链接定义和公开导出；对象与归档保留跨节调用和地址引用，动态库只公开导出符号。链接输入为有序对象和归档，按未决引用选择归档成员；纳入链接的全局重名和未解析引用报错。跨共享库动态绑定尚未实现。 |
| 数据存储 | 独立 object/linker API 支持只读、可写及零初始化节，保留节对齐、数据符号及跨模块寻址；共享库分别映射可执行、只读和可写内存，BSS 不占用对应的文件字节。ARM64 使用 ADRP/ADD 地址引用，x86-64 使用 RIP 相对 LEA；超出寻址范围时报错。Dart 顶层/静态变量、惰性初始化与数据导出注解尚未接入。 |
| 平台验证 | macOS ARM64、Linux ARM64/x86-64 已验证原生调用；macOS x86-64 当前检查文件生成、重定位表与签名，尚无运行验证。 |
| 标准库与执行支持 | 导出函数尚不能依赖托管分配、GC、调度及一般标准库执行能力。缓存或找到 SDK 源码不等于目标侧实现已经存在。 |

[原生函数验证](../test/compiler/native_test.dart)通过固定 Dart FFI 调用代码执行预编译资产，并与 SDK 对照整数边界行为。[寄存器别名验证](../test/codegen/native_test.dart)覆盖目标寄存器重叠时的实际结果。[格式验证](../test/object/formats_test.dart)检查目标标识、静态归档成员与符号索引；[签名验证](../test/linker/signature_test.dart)检查 Mach-O 签名对全部映像页的覆盖；[头文件验证](../test/compiler/artifacts_test.dart)检查导出原型。上述范围是当前后端实现进度，不改变完整语言目标。

[整数运算对照](../test/compiler/integer_operations_test.dart)覆盖乘法溢出、按位与/或/异或/取反、复合赋值、重复与重叠操作数，以及调用和循环中的值保存；使用正负边界、跨 32 位值及交替位模式对照 SDK。

[指针对照](../test/compiler/pointers_test.dart)检查地址往返、整数边界读写、寄存器与栈的混合参数、跨调用及循环存活、别名修改和复合赋值顺序。[FFI 声明绑定验证](../test/frontend/lowering/ffi_test.dart)检查同名用户类型和 extension 不被替换为原生操作；[IR 契约](../test/ir/native_memory_test.dart)检查语义类型和存储效果。[签名验证](../test/interop/native_signature_test.dart)与[编译拒绝验证](../test/compiler/compiler_test.dart)覆盖不支持及不匹配的类型。

[原生整数验证](../test/compiler/native_integers_test.dart)检查各宽度的正负边界、截断与扩展、邻接字节保护、IR 与原生访问、注解函数的普通 Dart 调用，以及窄整数与浮点混合栈参数。整数读写预期由元素位宽独立计算；SDK 对照不替代该预期。规范依据包括 [Int8Pointer.value](https://api.dart.dev/stable/3.13.7/dart-ffi/Int8Pointer/value.html)、[Uint8Pointer.value](https://api.dart.dev/stable/3.13.7/dart-ffi/Uint8Pointer/value.html)及对应宽度的标准库契约。

[原生浮点存储验证](../test/compiler/native_floats_test.dart)检查 Float 参数与结果、普通调用保持 double 精度、Float/Double 指针读写、复合赋值及混合栈参数。默认浮点环境下的舍入预期使用明确的 binary32 位模式，覆盖中点、次正规数、溢出、正负零与 NaN；另与 SDK 对照。规范依据为 [FloatPointer.value](https://api.dart.dev/stable/3.13.7/dart-ffi/FloatPointer/value.html) 和 [DoublePointer.value](https://api.dart.dev/stable/3.13.7/dart-ffi/DoublePointer/value.html)。

[浮点对照](../test/compiler/doubles_test.dart)检查 double 运算与全部比较、NaN、无穷、次正规数、负零和取负后的 NaN 载荷；覆盖两类寄存器耗尽、十九个混合参数及栈溢出、常量参数、调用保存和循环交换。[ABI 执行验证](../test/abi/native_test.dart)检查浮点局部存储及 ARM64 的被调用者保存标量寄存器；[布局检查](../test/abi/layout_test.dart)区分通用/浮点位置、破坏集合和栈偏移。

[混合数值验证](../test/compiler/mixed_numeric_test.dart)用二进制浮点的精确整数比例检查六种比较、两种操作数顺序、2^53 和 64 位边界及 NaN；算术和转换另与 SDK 对照。固定客户端还检查转换临时值、寄存器压力、调用、循环及原生写入顺序。

[独立链接验证](../test/linker/native_test.dart)调用预先链接的多目标文件与大符号表资产。[链接契约验证](../test/linker/linker_test.dart)覆盖确定性、局部符号隔离、重复全局定义和未解析引用；[输出保护验证](../test/compiler/compiler_test.dart)覆盖源文件和输出路径冲突。

[数据访问验证](../test/linker/data_native_test.dart)检查跨模块常量读取、可写数据与大块 BSS 的初值及重复修改、同名局部数据隔离，以及 Dart FFI 对导出数据的直接访问。[数据格式验证](../test/object/data_sections_test.dart)检查节、地址重定位、归档索引、文件/内存大小和映像权限；链接契约同时拒绝把数据当函数调用、地址越界和布局溢出。

[对象读取验证](../test/object/reader_test.dart)覆盖当前生成的四种目标对象、重新编码/链接、符号别名、输入所有权及损坏记录。读取范围为小端 ELF64/Mach-O 可重定位文件中的既有代码、只读数据、可写数据和 BSS 节，以及当前调用/地址引用形式。其他节和指令引用形式、弱/公共符号、非零符号 addend 等明确拒绝。Mach-O 缺少的符号类型和长度保留为未知；ELF 有明确记录时保留。固定原生函数与数据用例的资产由磁盘对象读取后重新链接。

`Archive.decode` 读取 GNU 与小端 Darwin 的 32 位符号索引归档，保留成员和索引顺序，包括重名候选、GNU 长名称及 BSD 扩展名称。成员头、边界、填充、索引字符串与成员偏移均须有效；成员内容在选中后才按目标对象格式解释。thin 归档、64 位索引及无索引归档尚不支持。见[归档读取验证](../test/object/archive_test.dart)。

`Linker.linkSharedLibrary` 接受 `LinkInput.object` 和 `LinkInput.archive`。Linux 在每个归档的输入位置按索引顺序选择当前未决符号所需的成员，反复扫描该归档；后续输入引入的新引用需要再次列出较早的归档。macOS 先纳入所有显式对象，再为未决符号按归档顺序选择第一个候选，持续处理新引用。未选成员不产生重复定义、未决引用或对象格式错误；选中成员的所有定义和导入均参与链接，不进行成员内裁剪。见[成员选择验证](../test/linker/archive_test.dart)；固定函数和数据资产同时覆盖归档链接后的原生执行。

[跨文件调用验证](../test/compiler/calls_test.dart)覆盖参数换位、重复参数、常量参数、跨调用活跃值、寄存器溢出和导出可见性。[重定位格式验证](../test/object/relocations_test.dart)检查对象文件的引用索引、局部/全局/未定义符号及位移规则。

[栈参数验证](../test/compiler/stack_calls_test.dart)对照 SDK 检查十参数入口、十及十一参数调用、嵌套调用、参数轮换与整数边界；[独立 ABI 调用](../test/abi/native_test.dart)通过另一个目标模块传递栈参数。[位置契约](../test/abi/layout_test.dart)检查参数位置、栈区大小和非法输入；[栈访问边界](../test/codegen/arguments_test.dart)检查机器位移上限。

[原生控制流对照](../test/compiler/control_flow_test.dart)覆盖整数边界比较、布尔辅助函数、短路副作用、循环的零次/一次/多次执行、嵌套循环及标签转移、循环变量轮换和递归返回。[图交接验证](../test/codegen/native_test.dart)覆盖同目标的不同边参数、乱序块布局和空块；[控制流编码验证](../test/codegen/control_flow_test.dart)检查不返回的循环。[不支持的异常路径](../test/compiler/fixtures/unsupported_control_flow.dart)仍明确拒绝生成，不因分支或未使用结果而丢弃。

## 规范依据

[主规范 §19、§6.3](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[语言版本与包配置 v2](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.8/language-versioning/package-config-file-v2.md)、[通配前缀](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/wildcard-variables/feature-specification.md#imports)、[StackTrace API](https://api.dart.dev/stable/3.13.7/dart-core/StackTrace-class.html)。
