# Managed native 工具链、自托管与运行时演进调查

调查日期：2026-10-27。本文仅查阅官方文档和当前源码，没有构建这些项目、运行性能测试。下面的“可借鉴”是工程判断，不是这些项目替 dartc 完成了正确性证明。

## 先给结论

1. **用自身语言实现可替换的运行时是可行路线，Go 和 SubstrateVM 是直接证据。** 但它们依赖编译器理解的引用表示、栈图、内存屏障、线程状态以及受约束的底层操作；没有哪套系统仅凭“编译器能编译自己”就自动获得安全 GC 或任意底层能力。
2. **官方 Dart 更适合研究语义、表示选择和 GC 协作，不能当作“VM 已主要用 Dart 写”的例子。** CFE、Kernel 和 TFA 有大量 Dart 实现；机器码后端、对象模型和 GC 的主要拥有者仍在 C++ VM 中。[D-CFE], [D-Kernel], [D-TFA], [D-Passes], [D-GC]
3. **NativeAOT 是另一种清晰的混合实现。** C# 的 ILC 负责全程序分析和编译组织，RyuJIT 后端、主要 GC 和本机启动层仍包含 C++/汇编；另有真正用 C# 实现的类型检查等运行时组件。它并非“全部执行基础已用 C# 自托管”。[N-Workflow], [N-ILC], [N-JitBridge], [N-GCEnv], [N-TypeCast]
4. **引导必须分清宿主与目标。** `C(host=A, target=B)` 是有意义的过渡编译器：它自己安全运行在 A 布局上，但输出遵循 B 的程序。一个共享源码常量被改成 B，不足以证明这种过渡成立。
5. **先建立完整性和测量契约，再选择复杂度。** 精确引用表示、分配后无 safepoint 的初始化尾段、跨调用根、真正回收后复用、错误路径和桥接构建都要有证据。PGO、分代、移动和并发 GC 都不能补救根遗漏；自编译收敛也不能证明语言完整。

## 研究引用的版本边界

通过 GitHub 官方仓库 API 读取分支头，再以完整 commit 固定下文源码链接：

| 项目 | 所查分支及固定 commit | 使用边界 |
|---|---|---|
| Dart SDK | `main`，`0e6e3cc127332355e3b786080280dd1a51969502` | 当前开发源码；不能把 main 新语法当作 Dart 3.13.5 已发布能力。VM overview 自注最后更新于 2022-10-06，具体实现以所列源码交叉核对。 |
| Go | `master`，`29cfee917f0a3eaad01bd868e533e7bc4bd1224a` | 开发分支；其 `internal/goversion` 已写 28，不等于 Go 1.28 已发布。Go 文档有些条款是稳定工具链的实现说明，不是语言规范要求。 |
| .NET runtime | `main`，`c3b0100a2b7bbca629d79aa07860e86962df4d7b` | 此 commit 的 `eng/Versions.props` 为 `12.0.0-alpha`。开发源码、NativeAOT 文档示例版本和正式 .NET 发行版要分开。 |
| Graal | `master`，`7b9a75fe3cb4a5777b3cda0035c7b510fb5064c9` | Native Image、Graal compiler 与 SubstrateVM 当前源码。网站 `latest` 此时展示 25.4 Innovation / 25.0 LTS 导航，部分例子又使用开发版；版本、发行商、edition 和平台限制都要单列。 |

上述头引用：[Dart commit][D-Commit]、[Go commit][G-Commit]、[.NET commit][N-Commit]、[Graal commit][S-Commit]。Go 开发版本和 .NET branding 的来源见 [G-Version]、[N-Version]。本次没有对这些开发分支做构建验收。

## 1. 官方 Dart VM AOT：Dart 前端与 C++ 执行基础分工

### 1.1 管线与语义边界

可以把已核到的主线表示为：

```text
Dart source / packages / language versions
  → CFE（Dart：解析、绑定、类型/常量及语言检查）
  → Kernel AST / .dill（高层、带类型的可序列化表示）
  → VM Dart transformations / TFA / tree shaking
  → C++ Kernel-to-IL / FlowGraph
  → SSA + 类型传播 + specialization + representation conversions
  → register allocation + architecture codegen
  → AOT code / heap snapshot + matching precompiled runtime
```

CFE 与 Kernel 是独立源码拥有者，不是 VM 后端里的名字匹配器。TFA 是对已表达的程序做保守可达性与类型流分析，不能替代前端补齐未知语言语义。AOT 需要保留可能执行的代码；从本机调用的 Dart 入口还要显式作为 reachability roots。`vm:entry-point` 文档说明了这一外部可见性问题。[D-CFE], [D-Kernel], [D-TFA], [D-Entry]

JIT 与 AOT 也不能混为一谈：JIT 的 profile/ICData 能支持带 guard 和 deoptimization 的投机；AOT 不能依赖未获保障的假设，但可以静态证明后无条件特化，也可以保留 guard 与语义完整的 generic fallback，无需 deopt。当前 `aot_call_specializer.cc` 的条件 dispatch 路径保留了原调用，不能把 AOT 优化全写成无条件去虚化。overview 是解释材料；`compiler_pass.cc` 可直接核到 ComputeSSA、Inlining、TypePropagation、RangeAnalysis、SelectRepresentations、AllocateRegisters 等次序。[D-Overview], [D-Passes], [D-AotSpecializer]

### 1.2 具体源码拥有者

| 职责 | 已查拥有者 | 对 dartc 的意义 |
|---|---|---|
| 语言前端 | `pkg/front_end/` | 把诊断、绑定、语言版本及常量语义放在前端职责内。 |
| 高层 IR | `pkg/kernel/` | 保存语言含义后再 lowering；序列化 IR 本身也是有版本的接口。 |
| AOT 类型流和裁剪 | `pkg/vm/lib/transformations/type_flow/transformer.dart` | 程序根与原生回调根要进入同一可达闭包。 |
| AOT 驱动 | `runtime/vm/compiler/aot/precompiler.cc`，`CompileAll` / `DoCompileAll` | 全程序分析与逐函数机器码编译是不同拥有者。 |
| SSA、表示和转换 | `runtime/vm/compiler/backend/flow_graph.cc`，`ComputeSSA` / `InsertConversion`；`compiler_pass.cc` | 语义类型、值表示与 GC 分类不能用一个 `int` 概念混掉。 |
| 分配寄存器/发码 | `runtime/vm/compiler/backend/linearscan.*`、`flow_graph_compiler_*`；目录已核实 | 低层平台能力有具体后端边界，不应把运行时算法塞进机器码模板。 |
| 宿主/目标布局 | `runtime/vm/compiler/runtime_api.h` | 文档明确目标 word size/offset 可不同于宿主；使用 `compiler::target`。 |
| GC 与线程状态 | `runtime/vm/heap/`、`heap/safepoint.h` | 精确根、handles、线程切换、屏障与 codegen 是共同协议。 |
| 内建方法边界 | `sdk/lib/_internal/vm/lib/array.dart` 与 `runtime/lib/array.cc` | Dart API、external/intrinsic 声明和 C++ 实现可以明确分开，但这是混合运行时。 |

主要源码依据：[D-Precompiler], [D-Flow], [D-Target], [D-Safepoint], [D-ArrayDart], [D-ArrayCpp]。表中的目录链接是组织入口，不等于已审完其中全部实现。

### 1.3 GC 协作决定了 unsafe 的实际成本

官方 VM 的 tagged object 约定和 dartc 现有约定不同，不能复制常量。其 GC 文档区分 Smi、heap pointer、boxed/unboxed 值，说明精确且可移动的收集器如何依赖机器栈分类。VM 自己的 C++ 局部变量也不是自动可见的根，跨可收集点需要 handles。线程必须在已定义的 generated/VM/native/blocked 状态之间正确过渡。[D-GC], [D-Safepoint]

初始化优化也有明确前提：某次 allocation 与字段 store 之间没有可能触发 GC 的指令，才可利用分配器建立的屏障不变量。这支持 dartc 的“reserve 前允许 poll，reserve 后到合法对象头/引用字段发布之间是已证明的安全尾段”方向；不能把“Dart 写的函数”误等同于“它内部的 raw 地址自然会被扫描”。[D-GC]

**可借鉴：** 类型化 SSA 与表示转换显式化、GC map 与寄存器分配协作、普通 runtime 与 target layout 分离、外部 reachability roots。

**不能照搬：** 整个 C++ VM 作为最终执行基础、JIT deopt 假设直接移植到无 deopt 的 AOT、VM 的具体 tag/header 作为语言语义、为图省事长期采用按名字特判的“编译器自用语法”。Dart 核心库存在 VM 专用实现不构成 dartc 缩小语言目标的理由。

### 1.4 构建与兼容性

官方 AOT 产物仍需要与 snapshot 匹配的 precompiled runtime；它排除了 JIT 等组件，却不是“没有运行时”。`runtime_api.h` 明确隔离 target offsets；`tools/make_version.py` 列出会影响 snapshot 兼容性的实现文件并产生 snapshot hash，`version_in.cc` 暴露相应版本字符串。[D-Target], [D-SnapshotVersion], [D-Version]

这是一种实际的兼容拒绝机制，不是布局升级自动迁移。CFE 用 Dart 实现，也不证明官方 VM 能由一个不含 C++ 工具链的纯 Dart 原生编译器重建。本文没有核到官方通用“旧纯 Dart native seed → 新 VM 全部底层”的协议，不作这种声称。

## 2. Go `gc` 工具链：最直接的同语言 runtime 参照

### 2.1 编译器与运行时的真实分界

Go 编译器主要用 Go 写，`runtime` 的分配、GC、调度和栈管理也大量用 Go；入口、栈切换、系统调用与极低层辅助仍有平台汇编，另有 cgo/OS 边界。`gc` 是标准 Go 编译器名称的一部分，不代表“所有编译动作都是 GC”。源码 README 明确区分前端、逃逸分析、generic SSA、目标 lowering、寄存器分配与 pointer liveness。[G-Compiler], [G-Runtime], [G-Asm]

```text
Go source / package/type information
  → syntax + types2 / IR construction
  → inlining / escape analysis
  → 目标无关 SSA optimization
  → architecture-specific SSA lowering/rules
  → register allocation + GC liveness / stack metadata
  → object files + Go linker + runtime
```

这里的 IR 组织与 dartc 的独立 Machine IR 不必逐层对应。借鉴目标应是转换的含义与可验证不变量，不是照抄 pass 数量和目录数量。

### 2.2 可直接阅读的拥有者

| 职责 | 已查源码 | 关键边界 |
|---|---|---|
| 编译流水线 | `src/cmd/compile/README.md`、`doc.go` | 明确语言检查、优化和目标后端的职责。 |
| 精确栈信息 | `src/cmd/compile/internal/liveness/plive.go` | 栈上哪些 pointer 在 safe point 活跃，是编译器分析结果。 |
| GC 算法 | `src/runtime/mgc.go`、`mgcmark*`、`mgcsweep.go` | 当前实现仍自述 non-generational、non-compacting；存在不同标记实现文件，不应把某个旧算法细节当永久合同。 |
| 物理分配 | `src/runtime/malloc.go`、`mheap.go` | size classes、每 P 快路径、OS arena 与 GC 协作；不是每对象 `mmap`。 |
| 本机能力 | `src/runtime/asm_arm64.s`、`sys_*`、`stubs.go` | 调度/栈/原语不假装成普通安全 Go 方法。 |
| 屏障约束验证 | `src/cmd/compile/internal/ssagen/nowb.go` | `nowritebarrierrec` 不是仅靠人相信的注释。 |
| 内部调用 ABI | `src/cmd/compile/abi-internal.md` | ABIInternal 与面向汇编的 ABI0 不同，可通过转换适配。 |
| 引导构建 | `src/cmd/dist/buildtool.go`、`build.go` | 旧工具链的宿主环境、新工具链源码和后续阶段有明确分界。 |

依据：[G-Liveness], [G-GC], [G-Malloc], [G-NoWB], [G-ABI], [G-BootTools], [G-BootBuild]。

### 2.3 同语言 GC 仍需要受约束的 runtime 方言

`runtime/HACKING.md` 是最值得 dartc 借鉴的合同文档之一：

- 管理器自身所需数据有 sysAlloc / persistentalloc / fixalloc 等 unmanaged 域；persistent 分配不可任意释放，不会因叫“raw”而自动免除拥有权义务。
- unmanaged 内存里的 heap pointer 必须经全局或显式 `markroot` 成为根；复用内存在对 GC 可见前必须清成合法状态。
- 用户栈与系统栈的 GC/抢占约束不同；`systemstack` 是受控边界。
- `nosplit` 针对栈增长和调用链预算，不等于通用“不分配/不收集”证明。`nowritebarrierrec` 则有递归调用图检查，不能把两者混成一个万能标记。[G-Runtime], [G-NoWB]

Go 的 `unsafe.Pointer`、`uintptr`、编译器特殊处理的存活性与 cgo 约束也说明：把 pointer 装成 integer 不会自然变成强根。当前 heap 不移动也不免除这条规则；栈可以变化，引用仍会因活跃性分析或未登记 raw 存储而丢失。[G-Runtime], [G-CompilerDoc], [G-ABI]

**可借鉴：** 普通语言实现算法，有限的 runtime-only 低层能力；显式 unmanaged ownership；编译期检查危险调用链；精确 pointer maps；可解释的 per-allocation/scan 成本。

**不能照搬：** 把 goroutine、M/P/G 调度、可增长栈和并发 GC 一次性搬进 dartc；把 Go 的结构类型、逃逸分析或非移动假设等同于 Dart 语义；用大量 `linkname` 规避拥有者边界。Go 自托管不意味着 runtime 不再需要平台汇编、编译器配合或兼容演进限制。

### 2.4 可恢复 bootstrap 的实证

官方安装文档规定引导 Go 版本要求，也支持用另一台机器交叉生成 bootstrap 工具链。[G-Install]

更重要的是当前源码的实际操作：`buildtool.go` 复制并改写引导所需的源码/导入，在 bootstrap workspace 内使用旧 `GOROOT_BOOTSTRAP`。它明确让 `GOROOT` 指向旧工具链，而不是把新 runtime 目录冒充旧 stdlib。随后 `build.go` 解释并实现：

```text
旧 Go + 旧运行环境 → 新源码的 toolchain1（宿主仍由旧工具链提供）
toolchain1 + go_bootstrap → toolchain2
toolchain2 + go_bootstrap → toolchain3 / 最终工具链
需要时再做 GOEXPERIMENT convergence；目标平台另作交叉阶段
```

源码注释称这些阶段在语义上收敛，也解释 build IDs 与实验开关导致的额外重建；**不能据此声称这段代码做了 dartc 式逐字节 stage2/3 比较**。本文读取的是构建组织，不是实际运行证明。[G-BootTools], [G-BootBuild]

这给 dartc 的证据是“分阶段构建与宿主隔离确有成熟先例”，不是“任何旧 Go 编译器都能直接编译任意新 Go runtime”。导出数据也有显式版本和按版本存在的字段，见 `internal/pkgbits/version.go`。[G-PkgBits]

## 3. .NET NativeAOT / RyuJIT：typed managed IR 与混合 runtime

### 3.1 不能把三个编译阶段混在一起

C# 前端（通常 Roslyn）负责 C# 源码语义并输出 IL/元数据；NativeAOT 的 ILCompiler 读取 IL 和类型系统，分析可达代码/泛型/反射需求，再通过共享 JIT 接口使用 RyuJIT 生成机器码。RyuJIT 的 importer 仍要验证/理解 IL；它不是 C# 源码解析器。ILC 程序源码中实际创建 `RyuJitCompilationBuilder`，并可传入 profile 数据。[N-ILC], [N-Workflow]

RyuJIT 的 IR 不是“处处独立 SSA 节点”的简单教材模型：基本块、GenTree、局部变量 SSA/value numbering、lowering 后的 LIR、LSRA 和 codegen 各有职责。文档明确 JIT/EE 请求接口返回机器码，同时返回 GC、EH、debug 信息；这些元数据是 codegen 的产物，不应事后靠猜机器栈补上。[N-RyuJIT]

### 3.2 实际文件组织与实现语言

| 职责 | 已查拥有者 | 语言/边界 |
|---|---|---|
| Whole-program ILC 驱动 | `src/coreclr/tools/aot/ILCompiler/Program.cs` | C#；类型系统、依赖分析、编译 roots 和构建组织。 |
| ILC 到后端接口 | `src/coreclr/tools/Common/JitInterface/CorInfoImpl.cs` | C# `DllImport` / callbacks 调用本机 JIT，不能把 ILC 用 C# 写推成后端也全是 C#。 |
| 优化器与发码 | `src/coreclr/jit/` | RyuJIT C++；SSA/值编号、lowering、寄存器分配。 |
| GC map 编码 | `src/coreclr/jit/gcencode.cpp` | 处理活跃引用、stack/register roots 以及返回表示等元数据。 |
| NativeAOT 启动 | `nativeaot/Bootstrap/main.cpp`、`Runtime/startup.cpp` | 本机入口初始化 runtime/模块，再进入 managed Main。 |
| GC 接口与暂停线程 | `nativeaot/Runtime/GCHelpers.cpp`、`gcenv.ee.cpp`；共享 `src/coreclr/gc/gc.h` | NativeAOT 与共享本机 GC/线程系统的 C++ 边界。 |
| managed runtime 算法 | `nativeaot/Runtime.Base/src/System/Runtime/TypeCast.cs` | 真实 C# 类型检查/缓存算法。 |
| 有限内部入口 | 同目录 `RuntimeImports.cs` | 显式 RuntimeImport：分配、handles、带屏障复制等。 |
| 平台打包/链接 | `nativeaot/BuildIntegration/Microsoft.NETCore.Native.targets` | 编译器、framework、native runtime 和链接材料分别拥有。 |

依据：[N-JitBridge], [N-GCEncode], [N-BootMain], [N-Startup], [N-GCHelpers], [N-GCEnv], [N-GCHeader], [N-TypeCast], [N-Imports], [N-Targets]。这是一套可以选择性研究的成熟边界，不是建议把整个 CoreCLR 搬过来。

### 3.3 GC、ABI 与错误效应

CLR ABI 文档区分 managed/native 调用、引用/内部引用、泛型上下文、返回缓冲、unwind 和 GC transition；文档还单列 NativeAOT 与其他 CLR 模式的差别。因此“都是 ARM64 指令”不代表与 C ABI 相同，也不代表整数寄存器里的所有位模式都可当 root。[N-ABI], [N-GCEncode]

NativeAOT 的 `GCToEEInterface` 实际实施暂停线程、扫描 thread statics/stack roots 和恢复执行；这不是仅在应用层保存几个对象地址。其共享 GC 的分配预算、零初始化和收集调度也都有明确拥有者。[N-GCEnv], [N-GCHelpers], [N-GCDoc]

CoreCLR 的 contract 文档把是否允许触发 GC、异常、线程模式、锁等拆开，存在运行时断言和静态标记；这不能直接当作 NativeAOT 每个 C# 方法都经同一静态效果系统证明。对 dartc 值得保留的是“能力分开声明、传递验证、作用域恢复”，而非复制宏名称或宣称 `no-gc` 自动涵盖全部异常/线程行为。[N-Contracts]

### 3.4 兼容、成熟度与限制

`jiteeversionguid.h` 明确规定 JIT/EE 接口变化时更新 GUID。NativeAOT 开发文档还警告：本地 compiler/runtime/framework 与 SDK 相差太远，会出现类型/成员、参数和链接不兼容。这是强有力的“版本拒绝与匹配材料”证据；GUID 正确本身仍不证明对象布局或 GC map 语义正确。[N-JitVersion], [N-Workflow]

NativeAOT 已是正式部署能力，但受 AOT/裁剪约束：运行时生成代码、任意动态加载、部分反射及泛型实例需要静态可知性或会产生兼容警告。它不等于完整 CLR 动态能力，也不等于所有 .NET 库无条件可用。本文查阅的 main 又是开发版，不能把其全部选项算作当前正式 SDK 合同。[N-Overview], [N-Warnings]

**可借鉴：** 语义类型与 GC 表示分离、GC/EH 与机器码一同生成、模块 roots、managed 算法通过有限 imports 使用本机能力、编译器/运行时/框架版本分别固定。

**不能照搬：** C++ GC 作为“Dart 自演进”的最终实现、全部 JIT/EE 回调接口规模、C# 的泛型特化/IL 表示直接替代 Dart 的泛型类型身份、只压制 AOT warnings 而没有真实执行证明。

## 4. GraalVM Native Image / SubstrateVM：Java 实现运行时与初始化尾段

### 4.1 Native Image 不是 Java 源码前端

Native Image 接收 Java bytecode/JAR/模块；Java 源码到 classfile 的语义工作通常已由 javac 完成。builder 的 points-to / reachability 分析建立可达闭包，再用 Graal compiler 生成目标代码和 image heap。目标进程运行在 SubstrateVM 的原生运行时上，不需要启动 HotSpot JVM。构建阶段依赖宿主 JDK 和本机链接工具，不能与目标进程没有 JVM 混为一谈。[S-Docs], [S-Readme], [S-Generator]

Graal compiler 与 SVM 的重要算法用 Java 实现，这是比“前端恰好用 Java”更直接的同语言 runtime 例子。但它使用 Word/Pointer、intrinsics、native code 和特定 JDK substitutions；这些都不是任意普通 Java 程序天然拥有的能力。[S-GraalCompiler], [S-GC], [S-Pointer]

### 4.2 具体拥有者

| 职责 | 已查目录/文件 | 合同 |
|---|---|---|
| 目标编译器 | `compiler/src/jdk.graal.compiler/.../core/GraalCompiler.java` | Java 实现的图优化、tier pipeline 和 codegen 组织。 |
| 语义可达性分析 | `substratevm/src/com.oracle.graal.pointsto/` | 处理 bytecode/对象类型可达性，不能代替 javac 的 Java 源码前端。 |
| hosted 编译组织 | `com.oracle.svm.hosted/.../NativeImageGenerator.java`、`code/CompileQueue.java` | 分析、universe、编译和镜像布局是 build-time 工作。 |
| 静态 image heap | `com.oracle.svm.hosted/.../image/NativeImageHeap.java` | 对象、引用和 relocation 显式物化；不能把宿主地址直接写成目标长期地址。 |
| Java GC | `com.oracle.svm.core.genscavenge/.../GCImpl.java` | 真正用 Java 表达的收集器，使用受约束的底层能力。 |
| safepoints | `com.oracle.svm.core/.../thread/Safepoint.java` | Java/native 状态、暂停协议及 VM operations。 |
| stack/reference map | `com.oracle.svm.core/.../code/CodeInfoDecoder.java` | PC、frame 信息与引用映射有可解码格式。 |
| unsafe/原语 | `sdk/.../org/graalvm/word/Pointer.java` 与各平台/C 函数边界 | 原始内存访问不自动提供 bounds、类型或 barrier 安全。 |
| 静态约束检查 | `com.oracle.svm.shared/.../Uninterruptible.java`；hosted `UninterruptibleAnnotationChecker.java` | 不只是一个被相信的 annotation。 |
| 启动/外部 ABI | `com.oracle.svm.core/.../c/function/CEntryPointNativeFunctions.java` | isolate/thread 的进入、退出和本机调用协议。 |

依据：[S-CompileQueue], [S-ImageHeap], [S-GC], [S-Safepoint], [S-CodeInfo], [S-Pointer], [S-Uninterruptible], [S-Checker], [S-CEntry]。当前源码将 `Uninterruptible` 放在 **shared** 模块；不能用旧文章的 core 路径假称已核对。

### 4.3 最适合 dartc 学习的合同

`Uninterruptible` 的说明直接列出这一场景：raw allocation 返回的内存，在装好 hub 和合法引用字段之前不能遇到 safepoint；如果 callee 返回未初始化存储，它可以要求 **caller 也必须无 safepoint**。这与 Dart 实现对象初始化尾段是同一个问题。[S-Uninterruptible]

配套 checker 不仅核对调用者/被调用者和 overrides，也检查图中的 allocation nodes，并约束可能破坏保证的内联/合成方法。另有 `NoAllocationVerifier` 检查特定运行期区域的分配。二者不能混称同一证明，也不能把当前线程不分配误推成整个系统不会移动任何对象。[S-Checker], [S-NoAllocation]

这比“把所有 allocator 标 no-gc”更精确：应分别定义 reserve 的触发能力、返回未初始化存储的 caller obligation、对象头与引用槽发布、以及内联后效果仍成立。无 safepoint 的区域还必须短且可解释，不能用无限 raw 循环阻塞未来全局暂停。

### 4.4 hosted/runtime 的边界和成熟度

构建期 class initialization 能减少目标启动工作，但会把构建时的静态状态保存到产物。官方文档明确约束类型初始化关系；这不能直接照搬到 Dart lazy globals，尤其不能提前执行 I/O、读取环境或改变副作用时机。应先证明属于常量或可安全提前计算的状态。[S-ClassInit], [S-ImageHeap]

Native Image 是成熟的部署技术，适合闭世界、可静态描述反射/资源/动态行为的应用；它不是任意 JVM 动态程序的等价替换。反射/JNI 等依赖额外 reachability metadata，部分动态能力受限。自动产生 JVM fallback 也不应算作 dartc 的原生产物成功。[S-Compatibility]

GC 选择与 edition/OS 有实际限制：所查文档列 Serial、G1 和不回收的 Epsilon；不能仅因源码里有 G1 目录就声称每个发行版/平台都提供同样能力。`no-op GC` 是有界短程序的策略，不是“GC 已实现”。[S-Memory]

**可借鉴：** Java runtime 算法、受检验的无 safepoint 尾段、raw/managed 表示边界、hosted 与 runtime 明确分离、reference-map 编码与共享。

**不能照搬：** 整个 hosted framework/substitution 体系、所有 JDK 特定替换、默认 eager 初始化、未经测试的反射 metadata 自动生成、把 Word 的 unsafe 权限泛化为用户隐式指针转换。

## 5. 自托管升级：宿主布局 A 与目标布局 B 必须分别描述

### 5.1 dartc 当前检查证明了什么

本次只读查看本地 `79b22ba0309a14f2d3e1417a121a37b6293dfcd4`：`layout.runtimeAbiVersion` 与 runtime 的 `rtAbiVersion` 都是 11；frontend 要求可信 runtime marker 严格等于编译器内置期望；bootstrap 复制既有 seed、构建 stage1/2/3、比较 stage2/3，并对 stage2 运行 behavior 后才替换 verified seed。

拥有者：[layout.dart](../../lib/src/layout.dart)、[runtime.dart](../../lib/src/runtime.dart)、[frontend.dart](../../lib/src/frontend.dart)、[bootstrap.dart](../../tool/bootstrap.dart)。这里记录源码合同，没有重新执行构建。

当前项目还已有两项不应误报为“尚未实现”的基础：Ref/Tagged 保守落栈是分配位置策略，根图仍是按类型与活跃性生成的精确根图，不是对所有整数猜指针的保守 GC；`checkNoGcSsa` / `checkNoGcMachine` 也已经计算并核验 SSA 义务与调用闭包的 MIR 效果摘要。后续议题应是一般优化如何消费这些摘要、初始化 caller obligation 如何闭合，而不是重新建立一个名字驱动的 NoGC 检查器。拥有者：[allocate.dart](../../lib/src/allocate.dart)、[root_map.dart](../../lib/src/root_map.dart)、[nogc.dart](../../lib/src/nogc.dart)。

这些检查对防止已知不匹配、验证一次构建收敛很有价值；**它们没有证明任意 A→B 布局迁移**。尤其不能从“新 layout.dart 与新 runtime marker 都改成 B”推导旧 compiler 对新 header/TypeRef/root-map/call ABI 已有正确 producer。

### 5.2 最小可审协议建议

用 `C[H,T]` 表示“宿主运行时为 H、所产程序采用目标 ABI T”的编译器。语言/primitive 能力再单独记录，不要把三个维度塞成同一个版本数字。

| 节点 | 自身必须运行于 | 允许输出/输入的目标合同 | 实际必要条件 |
|---|---|---|---|
| `C0[A,A]` | 已验证 A | 原 A | 保留 binary、runtime A 的完整 import closure、layout A 和原语表/源码身份。 |
| `Bridge[A,B]` | A | B | 用 C0 能理解的语言和旧原语实现 B producer；**构建 Bridge 自身仍使用独立旧 runtime/layout A**。编译器源码中的 target codec/layout B 不能反向污染 runtime A 的实现。 |
| `C1[B,B]` | B | B | Bridge 才采用 runtime B 与新原语，生成新宿主 B 编译器。 |
| `C2[B,B]` | B | B | C1 重建同源码/同 B；稳定条件下比较产物并执行行为、根/布局及真实用户任务。 |

这是由上述成熟系统分工推导的证明义务记法，不是说它们共用这一命名协议，也不要求建立多版本 ABI 框架、长期保留 bridge 或每次固定四节点。A→B 指重新构建新进程，不是迁移旧进程的活堆；ABI 未变、旧能力足够时可继续现有 bootstrap。实际过渡中，如果旧 seed 连新增源码语法、metadata AST 或 emitter 支持代码都不能读，需要先做 `Support[A,A]`，再做必要布局 bridge。

**重点是材料隔离，而不是临时放宽 gate：**

- runtime A 要带自己的 layout A/stdlib closure。仅保存一个旧 runtime.dart、让它继续导入已修改的 layout B，恢复点并不完整。
- target B 的 offsets、TypeRef records、descriptor、call ABI、root-map reader/writer 和代码原语必须来自一个可核对的 schema。代码生成不得误读宿主对象的布局常量。
- compiler binary 应可说明其 host runtime 身份和 target 能力；初期可用构建 manifest/散列即可，不必先造多版本 ABI 通用框架。
- strict equality 仍可保留在 **目标标准库** 边界。Bridge 自己运行在 A，并不意味着它应该接受目标 std A；宿主身份不应由编译时传入 `--std` 的 marker 猜测。

### 5.3 迁移验证不能只比较 hello 或 compiler 自己

建议未来升级时挑最少的一组 **跨新旧 schema 有区分力** 的真实程序，而不是源码形状断言：

1. 大字段类与多 word Ref/Tagged bitmap，包含 integer-looking raw value、真正引用和宽整数装箱。
2. 经过真实 call/indirect call、溢出参数、root-map 与 globals/临时持久根的对象；回收能力若启用，要跨真实 collection/reuse 保持存活。
3. 新 header/relative literals/TypeRef/const graph 由 Bridge 写出，再由 B runtime 真实消费；目标平台实际运行，不能只识别 MachO/ELF。
4. 旧目标被不支持的 reader 拒绝；新的例子不能被旧代码碰巧以旧布局解释却仍输出同一个常量。
5. 在新 C2 通过后才原子替换本地 verified seed；失败保留 C0 的完整可恢复 bundle，不要求远端 checkpoint 分发。

Go 的旧 GOROOT 与阶段构建、Dart 的 host/target offset API、.NET 的 JIT/EE GUID、Native Image 的 hosted image materialization，各支持这一协议的一个方面；没有任何一个单项替代整条证明。

## 6. 正确性与测量：四套系统能提供什么方法

### 6.1 先分开两个性能问题

| 问题 | 必须相同 | 可以不同 | 主要证据 |
|---|---|---|---|
| 编译器执行/内嵌 runtime 成本 | 任务源码、实际依赖闭包、目标 std、flags、输出行为；若算法/编码应相同，还要求完整目标 bytes 相同 | 构建这个 compiler 的引擎和其内部 runtime | compile wall/CPU/peakRSS、实际产物与语义 gate。 |
| 不同 code generator 的应用质量 | 同一应用任务、输入、参数、输出文件及退出/stdout/stderr；平台/ISA/语义一致 | SDK/native 产物 bytes 与代码布局 | 分开记录 compile、首次启动、持续执行、image size 和运行期资源。 |

AOT 的启动快，不意味着任意长任务吞吐更高；JIT 的动态 PGO 不能拿来解释无 JIT 的 AOT；未清 OS file cache 的“新进程”也不是冷 cache。RSS、managed live heap、reserved address space、image heap、磁盘 image bytes 和瞬时 footprint 是不同指标。

本文没有给四套工具链跑排名。不同语言/标准库/整数溢出/异常/泛型语义不同，不能把各自 hello 或不同算法的数字拼成“架构证明”。

### 6.2 PGO 的可用性和边界

- **Dart：** 本次核到 JIT feedback/deopt 与 AOT TFA 的区别，未核到可直接等价为用户稳定 AOT PGO 合同的通用流程。AppJIT training snapshot 和 AOT source/type analysis 也不同。不要用 JIT 机制替 AOT 宣称未验证优化能力。[D-Overview], [D-Precompiler]
- **Go：** 官方 PGO 使用代表性的 CPU pprof profile，`default.pgo` 等是构建输入；强调真实负载和 profile skew，不建议拿局部 microbenchmark 当整个应用的 profile。应分别保留无 PGO 基线、训练集、未参与训练的验证任务以及 profile hash。[G-PGO]
- **.NET：** JIT tiered/dynamic PGO 与 NativeAOT static profile 不同。当前 NativeAOT targets 收集 MIBC 并传给 ILC，ILC 的 RyuJIT builder 有 UseProfileData。不能把 .NET JIT 默认 dynamic PGO 的宣传数字当 NativeAOT 默认收益，也不能把 ReadyToRun 的开关无验证搬到 NativeAOT。[N-Targets], [N-ILC], [N-PGO]
- **Graal：** 官方说明有 instrumentation → 代表性训练执行 → profile → 重建的循环，且当前页面明确 PGO 的 edition 限制。profile 驱动优化成本决策，不应将训练中未见的合法类型/分支删成不可执行；训练执行与优化后正确性验证是两件事。[S-PGO], [S-PGOUsage]

### 6.3 值得借鉴的验证工具，而非照搬框架

Go 的 perf/benchstat 强调重复样本、统计分布与 profile 定位。.NET performance 的设计指南强调固定输入、消除 DCE、明确 setup/cleanup 和进程隔离；这些原则可采用，dartc 没必要因此引入 BenchmarkDotNet 一样的大框架。[G-Perf], [G-Benchstat], [N-Bench]

SuperPMI 将 JIT/EE 请求记录后重放，可用于断言回归与 assembly diff。它**不执行被编译程序**，因此不能替代语言行为或 GC 存活验证。对 dartc 可借鉴的是可重放输入和差分定位；现有真实 compile/run/differential 闭环仍应当拥有最终语义验收。[N-SuperPMI]

Native Image 的 build output 将分析、编译、image heap、code area 和资源统计分开，且提供机器可读输出方向。对 dartc 有用的是“成本归属清楚”，而不是照抄网站 hello 的时间或把整份产物体积都归给 GC。[S-BuildOutput]


跨项目建议与当前实现审查统一见 [总览](README.md) 和 [dartc](dartc.md)。

## 固定源码与官方文档入口

下列源码链接均固定为本次读取的完整 commit；其中 .NET performance 指南另固定为 bee760ce03eda6021a1466486e067c7c7e76a4ef。官方在线文档则按上面的调查日期解释。文件位置已通过官方仓库读取，404/未查到的猜测路径没有列入本表。

[D-Commit]: https://github.com/dart-lang/sdk/commit/0e6e3cc127332355e3b786080280dd1a51969502
[D-CFE]: https://github.com/dart-lang/sdk/blob/0e6e3cc127332355e3b786080280dd1a51969502/pkg/front_end/README.md
[D-Kernel]: https://github.com/dart-lang/sdk/blob/0e6e3cc127332355e3b786080280dd1a51969502/pkg/kernel/README.md
[D-TFA]: https://github.com/dart-lang/sdk/blob/0e6e3cc127332355e3b786080280dd1a51969502/pkg/vm/lib/transformations/type_flow/transformer.dart
[D-Overview]: https://github.com/dart-lang/sdk/blob/0e6e3cc127332355e3b786080280dd1a51969502/runtime/docs/README.md
[D-Passes]: https://github.com/dart-lang/sdk/blob/0e6e3cc127332355e3b786080280dd1a51969502/runtime/vm/compiler/compiler_pass.cc
[D-AotSpecializer]: https://github.com/dart-lang/sdk/blob/0e6e3cc127332355e3b786080280dd1a51969502/runtime/vm/compiler/aot/aot_call_specializer.cc
[D-Precompiler]: https://github.com/dart-lang/sdk/blob/0e6e3cc127332355e3b786080280dd1a51969502/runtime/vm/compiler/aot/precompiler.cc
[D-Flow]: https://github.com/dart-lang/sdk/blob/0e6e3cc127332355e3b786080280dd1a51969502/runtime/vm/compiler/backend/flow_graph.cc
[D-Target]: https://github.com/dart-lang/sdk/blob/0e6e3cc127332355e3b786080280dd1a51969502/runtime/vm/compiler/runtime_api.h
[D-GC]: https://github.com/dart-lang/sdk/blob/0e6e3cc127332355e3b786080280dd1a51969502/runtime/docs/gc.md
[D-Safepoint]: https://github.com/dart-lang/sdk/blob/0e6e3cc127332355e3b786080280dd1a51969502/runtime/vm/heap/safepoint.h
[D-ArrayDart]: https://github.com/dart-lang/sdk/blob/0e6e3cc127332355e3b786080280dd1a51969502/sdk/lib/_internal/vm/lib/array.dart
[D-ArrayCpp]: https://github.com/dart-lang/sdk/blob/0e6e3cc127332355e3b786080280dd1a51969502/runtime/lib/array.cc
[D-Entry]: https://github.com/dart-lang/sdk/blob/0e6e3cc127332355e3b786080280dd1a51969502/runtime/docs/compiler/aot/entry_point_pragma.md
[D-SnapshotVersion]: https://github.com/dart-lang/sdk/blob/0e6e3cc127332355e3b786080280dd1a51969502/tools/make_version.py
[D-Version]: https://github.com/dart-lang/sdk/blob/0e6e3cc127332355e3b786080280dd1a51969502/runtime/vm/version_in.cc
[G-Commit]: https://github.com/golang/go/commit/29cfee917f0a3eaad01bd868e533e7bc4bd1224a
[G-Version]: https://github.com/golang/go/blob/29cfee917f0a3eaad01bd868e533e7bc4bd1224a/src/internal/goversion/goversion.go
[G-Compiler]: https://github.com/golang/go/blob/29cfee917f0a3eaad01bd868e533e7bc4bd1224a/src/cmd/compile/README.md
[G-CompilerDoc]: https://github.com/golang/go/blob/29cfee917f0a3eaad01bd868e533e7bc4bd1224a/src/cmd/compile/doc.go
[G-Runtime]: https://github.com/golang/go/blob/29cfee917f0a3eaad01bd868e533e7bc4bd1224a/src/runtime/HACKING.md
[G-GC]: https://github.com/golang/go/blob/29cfee917f0a3eaad01bd868e533e7bc4bd1224a/src/runtime/mgc.go
[G-Malloc]: https://github.com/golang/go/blob/29cfee917f0a3eaad01bd868e533e7bc4bd1224a/src/runtime/malloc.go
[G-Asm]: https://github.com/golang/go/blob/29cfee917f0a3eaad01bd868e533e7bc4bd1224a/src/runtime/asm_arm64.s
[G-NoWB]: https://github.com/golang/go/blob/29cfee917f0a3eaad01bd868e533e7bc4bd1224a/src/cmd/compile/internal/ssagen/nowb.go
[G-Liveness]: https://github.com/golang/go/blob/29cfee917f0a3eaad01bd868e533e7bc4bd1224a/src/cmd/compile/internal/liveness/plive.go
[G-ABI]: https://github.com/golang/go/blob/29cfee917f0a3eaad01bd868e533e7bc4bd1224a/src/cmd/compile/abi-internal.md
[G-BootTools]: https://github.com/golang/go/blob/29cfee917f0a3eaad01bd868e533e7bc4bd1224a/src/cmd/dist/buildtool.go
[G-BootBuild]: https://github.com/golang/go/blob/29cfee917f0a3eaad01bd868e533e7bc4bd1224a/src/cmd/dist/build.go
[G-PkgBits]: https://github.com/golang/go/blob/29cfee917f0a3eaad01bd868e533e7bc4bd1224a/src/internal/pkgbits/version.go
[G-Install]: https://go.dev/doc/install/source
[G-PGO]: https://go.dev/doc/pgo
[G-Perf]: https://go.dev/wiki/Performance
[G-Benchstat]: https://pkg.go.dev/golang.org/x/perf/cmd/benchstat
[N-Commit]: https://github.com/dotnet/runtime/commit/c3b0100a2b7bbca629d79aa07860e86962df4d7b
[N-Version]: https://github.com/dotnet/runtime/blob/c3b0100a2b7bbca629d79aa07860e86962df4d7b/eng/Versions.props
[N-Workflow]: https://github.com/dotnet/runtime/blob/c3b0100a2b7bbca629d79aa07860e86962df4d7b/docs/workflow/building/coreclr/nativeaot.md
[N-RyuJIT]: https://github.com/dotnet/runtime/blob/c3b0100a2b7bbca629d79aa07860e86962df4d7b/docs/design/coreclr/jit/ryujit-overview.md
[N-ILC]: https://github.com/dotnet/runtime/blob/c3b0100a2b7bbca629d79aa07860e86962df4d7b/src/coreclr/tools/aot/ILCompiler/Program.cs
[N-JitBridge]: https://github.com/dotnet/runtime/blob/c3b0100a2b7bbca629d79aa07860e86962df4d7b/src/coreclr/tools/Common/JitInterface/CorInfoImpl.cs
[N-GCEncode]: https://github.com/dotnet/runtime/blob/c3b0100a2b7bbca629d79aa07860e86962df4d7b/src/coreclr/jit/gcencode.cpp
[N-BootMain]: https://github.com/dotnet/runtime/blob/c3b0100a2b7bbca629d79aa07860e86962df4d7b/src/coreclr/nativeaot/Bootstrap/main.cpp
[N-Startup]: https://github.com/dotnet/runtime/blob/c3b0100a2b7bbca629d79aa07860e86962df4d7b/src/coreclr/nativeaot/Runtime/startup.cpp
[N-GCHelpers]: https://github.com/dotnet/runtime/blob/c3b0100a2b7bbca629d79aa07860e86962df4d7b/src/coreclr/nativeaot/Runtime/GCHelpers.cpp
[N-GCEnv]: https://github.com/dotnet/runtime/blob/c3b0100a2b7bbca629d79aa07860e86962df4d7b/src/coreclr/nativeaot/Runtime/gcenv.ee.cpp
[N-TypeCast]: https://github.com/dotnet/runtime/blob/c3b0100a2b7bbca629d79aa07860e86962df4d7b/src/coreclr/nativeaot/Runtime.Base/src/System/Runtime/TypeCast.cs
[N-Imports]: https://github.com/dotnet/runtime/blob/c3b0100a2b7bbca629d79aa07860e86962df4d7b/src/coreclr/nativeaot/Runtime.Base/src/System/Runtime/RuntimeImports.cs
[N-ABI]: https://github.com/dotnet/runtime/blob/c3b0100a2b7bbca629d79aa07860e86962df4d7b/docs/design/coreclr/botr/clr-abi.md
[N-GCHeader]: https://github.com/dotnet/runtime/blob/c3b0100a2b7bbca629d79aa07860e86962df4d7b/src/coreclr/gc/gc.h
[N-GCDoc]: https://github.com/dotnet/runtime/blob/c3b0100a2b7bbca629d79aa07860e86962df4d7b/docs/design/coreclr/botr/garbage-collection.md
[N-JitVersion]: https://github.com/dotnet/runtime/blob/c3b0100a2b7bbca629d79aa07860e86962df4d7b/src/coreclr/inc/jiteeversionguid.h
[N-Targets]: https://github.com/dotnet/runtime/blob/c3b0100a2b7bbca629d79aa07860e86962df4d7b/src/coreclr/nativeaot/BuildIntegration/Microsoft.NETCore.Native.targets
[N-Contracts]: https://github.com/dotnet/runtime/blob/c3b0100a2b7bbca629d79aa07860e86962df4d7b/docs/coding-guidelines/clr-code-guide.md
[N-Overview]: https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/
[N-Warnings]: https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/fixing-warnings
[N-PGO]: https://github.com/dotnet/runtime/blob/c3b0100a2b7bbca629d79aa07860e86962df4d7b/docs/design/features/dotnet-pgo.md
[N-SuperPMI]: https://github.com/dotnet/runtime/blob/c3b0100a2b7bbca629d79aa07860e86962df4d7b/src/coreclr/tools/superpmi/readme.md
[N-Bench]: https://github.com/dotnet/performance/blob/bee760ce03eda6021a1466486e067c7c7e76a4ef/docs/microbenchmark-design-guidelines.md
[S-Commit]: https://github.com/oracle/graal/commit/7b9a75fe3cb4a5777b3cda0035c7b510fb5064c9
[S-Readme]: https://github.com/oracle/graal/blob/7b9a75fe3cb4a5777b3cda0035c7b510fb5064c9/docs/reference-manual/native-image/README.md
[S-Generator]: https://github.com/oracle/graal/blob/7b9a75fe3cb4a5777b3cda0035c7b510fb5064c9/substratevm/src/com.oracle.svm.hosted/src/com/oracle/svm/hosted/NativeImageGenerator.java
[S-GraalCompiler]: https://github.com/oracle/graal/blob/7b9a75fe3cb4a5777b3cda0035c7b510fb5064c9/compiler/src/jdk.graal.compiler/src/jdk/graal/compiler/core/GraalCompiler.java
[S-CompileQueue]: https://github.com/oracle/graal/blob/7b9a75fe3cb4a5777b3cda0035c7b510fb5064c9/substratevm/src/com.oracle.svm.hosted/src/com/oracle/svm/hosted/code/CompileQueue.java
[S-ImageHeap]: https://github.com/oracle/graal/blob/7b9a75fe3cb4a5777b3cda0035c7b510fb5064c9/substratevm/src/com.oracle.svm.hosted/src/com/oracle/svm/hosted/image/NativeImageHeap.java
[S-GC]: https://github.com/oracle/graal/blob/7b9a75fe3cb4a5777b3cda0035c7b510fb5064c9/substratevm/src/com.oracle.svm.core.genscavenge/src/com/oracle/svm/core/genscavenge/GCImpl.java
[S-Safepoint]: https://github.com/oracle/graal/blob/7b9a75fe3cb4a5777b3cda0035c7b510fb5064c9/substratevm/src/com.oracle.svm.core/src/com/oracle/svm/core/thread/Safepoint.java
[S-CodeInfo]: https://github.com/oracle/graal/blob/7b9a75fe3cb4a5777b3cda0035c7b510fb5064c9/substratevm/src/com.oracle.svm.core/src/com/oracle/svm/core/code/CodeInfoDecoder.java
[S-Pointer]: https://github.com/oracle/graal/blob/7b9a75fe3cb4a5777b3cda0035c7b510fb5064c9/sdk/src/org.graalvm.word/src/org/graalvm/word/Pointer.java
[S-Uninterruptible]: https://github.com/oracle/graal/blob/7b9a75fe3cb4a5777b3cda0035c7b510fb5064c9/substratevm/src/com.oracle.svm.shared/src/com/oracle/svm/shared/Uninterruptible.java
[S-Checker]: https://github.com/oracle/graal/blob/7b9a75fe3cb4a5777b3cda0035c7b510fb5064c9/substratevm/src/com.oracle.svm.hosted/src/com/oracle/svm/hosted/code/UninterruptibleAnnotationChecker.java
[S-NoAllocation]: https://github.com/oracle/graal/blob/7b9a75fe3cb4a5777b3cda0035c7b510fb5064c9/substratevm/src/com.oracle.svm.core/src/com/oracle/svm/core/heap/NoAllocationVerifier.java
[S-CEntry]: https://github.com/oracle/graal/blob/7b9a75fe3cb4a5777b3cda0035c7b510fb5064c9/substratevm/src/com.oracle.svm.core/src/com/oracle/svm/core/c/function/CEntryPointNativeFunctions.java
[S-Docs]: https://www.graalvm.org/latest/reference-manual/native-image/
[S-Memory]: https://www.graalvm.org/latest/reference-manual/native-image/optimizations-and-performance/MemoryManagement/
[S-ClassInit]: https://www.graalvm.org/latest/reference-manual/native-image/optimizations-and-performance/ClassInitialization/
[S-Compatibility]: https://www.graalvm.org/latest/reference-manual/native-image/metadata/Compatibility/
[S-PGO]: https://www.graalvm.org/latest/reference-manual/native-image/optimizations-and-performance/PGO/
[S-PGOUsage]: https://www.graalvm.org/latest/reference-manual/native-image/optimizations-and-performance/PGO/basic-usage/
[S-BuildOutput]: https://www.graalvm.org/latest/reference-manual/native-image/overview/BuildOutput/
