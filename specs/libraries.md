# 库、脚本与并发边界

转换以调用方明确提供的库批次为单位，包含每个库的所有 part。`package:dartc/analyzer.dart` 的 `AnalysisSession` 复用官方 analyzer 的解析结果；名称与指令解析不由 lowering 重复实现。`includeDependencies: true` 纳入非 SDK 导入和导出库，整个批次完成静态检查后才开始转换。导入库的函数调用保留声明身份，但只有批次内的库会生成函数体。一般 Dart 可执行程序的入口和目标运行时链接仍待实现。

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

[库与命名空间行为对照](../test/lowering/libraries_test.dart)、[包上下文与诊断对照](../test/lowering/lowering_test.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/libraries.md)。

SDK 成员按已解析的声明生成普通调用、方法提取或扩展调用；未提供函数体时保留导入身份。已有语义 IR 操作只替换它们明确表示的操作，其他方法不会因参考执行器缺少实现而在 lowering 阶段拒绝。SDK 实现的装配、链接及执行属于后续交付范围。见[SDK 调用与用户重写测试](../test/lowering/sdk_calls_test.dart)。

[延迟导入对照](../test/lowering/deferred_imports_test.dart)覆盖未加载、请求已发出但尚未完成、加载完成和重复加载；两个前缀指向同一库时仍各自检查。`LoadLibrary` 返回代表加载完成的 Future，`CheckLibraryLoaded` 保留可抛错的读取效果。`loadLibrary` 的隐式函数保留普通调用和函数值身份。普通 extension 声明不能通过 deferred 导入，由 analyzer 检查。

SDK 3.13.7 接受 deferred 前缀下的具名构造器提取，却将[无名 `.new` 提取](../test/lowering/fixtures/deferred_unnamed_tearoff.dart)诊断为不是构造器引用；analyzer 14.7 接受后者。IR 对该用例保留已解析构造器及加载检查，并独立验证其结果，不将它计入 SDK 执行对照。

## 原生库

`package:dartc/export.dart` 的 `@Export<T>(symbol: ...)` 声明原生函数导出，`T` 使用 `dart:ffi` 函数类型。绑定依据注解声明身份，符号默认采用函数名。静态库、动态库和目标文件使用同一份声明，并可生成 C/C++ 头文件。

| 项目 | 当前原生范围与缺口 |
| --- | --- |
| 导出签名 | 同步、非泛型的顶层函数；参数和结果为 `Int64`，对应非可空 Dart `int`；只接受必需位置参数。其他标量、指针、结构体、可变参数和数据导出尚未实现。 |
| 函数体 | 单基本块内的整数常量、加法、减法和返回，保留有符号 64 位环绕结果。支持批次内跨库整数函数的直接调用，包括嵌套调用和未导出的辅助函数。分支、对象存储、异常和异步尚未接入原生后端。 |
| 参数与存储 | ARM64 最多八个整数寄存器参数，x86-64 最多六个。活跃值使用调用方保存寄存器及溢出槽，调用前保存仍需使用的值，栈帧保持 16 字节对齐及帧指针链。尚无栈参数；超出寄存器参数数量、栈帧大小或调用位移范围时明确报错。 |
| 文件与链接 | Dart 实现 Mach-O/ELF 目标文件、带符号索引的静态归档及动态库编码；Mach-O 包含导出树和 ad-hoc 签名，部署下限为 macOS 11。生成与链接不要求匹配宿主，也不调用外部工具。模块区分局部定义、全局可链接定义和公开导出，支持 ARM64 BL 与 x86-64 CALL 重定位；未定义符号须由同批模块提供，全局重名和未解析引用报错。对象与归档保留引用，动态库只公开导出符号。数据段、进程外动态绑定及目标文件读取尚未实现。 |
| 平台验证 | macOS ARM64、Linux ARM64/x86-64 已验证原生调用；macOS x86-64 当前检查文件生成、重定位表与签名，尚无运行验证。 |
| 标准库与执行支持 | 导出函数尚不能依赖托管分配、GC、调度及一般标准库执行能力。缓存或找到 SDK 源码不等于目标侧实现已经存在。 |

[原生函数验证](../test/compiler/native_test.dart)通过固定 Dart FFI 调用代码执行预编译资产，并与 SDK 对照整数边界行为。[寄存器别名验证](../test/codegen/native_test.dart)覆盖目标寄存器重叠时的实际结果。[格式验证](../test/formats/formats_test.dart)检查目标标识、静态归档成员与符号索引，以及 Mach-O 签名对全部映像页的覆盖；[头文件验证](../test/compiler/artifacts_test.dart)检查导出原型。上述范围是当前后端实现进度，不改变完整语言目标。

[独立链接验证](../test/linker/native_test.dart)调用预先链接的多目标文件与大符号表资产。[链接契约验证](../test/linker/linker_test.dart)覆盖确定性、局部符号隔离、重复全局定义和未解析引用；[输出保护验证](../test/compiler/compiler_test.dart)覆盖源文件和输出路径冲突。

[跨文件调用验证](../test/compiler/calls_test.dart)覆盖参数换位、重复参数、常量参数、跨调用活跃值、寄存器溢出和导出可见性。[重定位格式验证](../test/formats/relocations_test.dart)检查对象文件的引用索引、局部/全局/未定义符号及位移规则。

## 规范依据

[主规范 §19、§6.3](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[语言版本与包配置 v2](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.8/language-versioning/package-config-file-v2.md)、[通配前缀](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/wildcard-variables/feature-specification.md#imports)、[StackTrace API](https://api.dart.dev/stable/3.13.7/dart-core/StackTrace-class.html)。
