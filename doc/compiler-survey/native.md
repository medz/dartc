# 主流原生编译器架构研究：LLVM/Clang、GCC、rustc、Swift

研究日期：2026-10-27。本文只调查官方文档和官方源码；没有构建这些工具链，没有运行跨编译器性能比较。以下“可借鉴”是根据源码职责和语言差异作出的工程判断，不表示这些机制已经在 dartc 实现。

## 1. 范围与版本证据

本次通过 GitHub API 读取以下分支 HEAD，再用固定提交读取目录与关键文件。它们是**观察时的开发分支快照**，不是“最新稳定版”声明；在线文档通常随开发分支更新，版本化源码链接比滚动文档更适合复核具体文件名。

| 项目 | 观察分支与固定提交 | 提交者时间（UTC） | 说明 |
| --- | --- | --- | --- |
| LLVM monorepo | main，[0bb039df436dee7400ebfebf80a302344c075142](https://github.com/llvm/llvm-project/commit/0bb039df436dee7400ebfebf80a302344c075142) | 2026-10-27 12:29:26 | 同一树含 llvm、clang、lld、compiler-rt、libcxx 等项目 |
| GCC | master，[684c9811dee6573fdb8b01c9bef16e68054fc87c](https://github.com/gcc-mirror/gcc/commit/684c9811dee6573fdb8b01c9bef16e68054fc87c) | 2026-10-27 12:43:13 | 固定源码通过 gcc-mirror/GCC 官方镜像核对；规范仓库位置见 [GCC Git 文档](https://gcc.gnu.org/git.html) |
| Rust | main，[16d1ffac17ad8b739e32483ac2e65fe7e1804977](https://github.com/rust-lang/rust/commit/16d1ffac17ad8b739e32483ac2e65fe7e1804977) | 2026-10-26 19:40:24 | compiler 与 library 同树；LLVM 后端另有 C++ 依赖 |
| Swift | main，[6ec9d935489a496aca02bb7ac9613160ecf0659b](https://github.com/swiftlang/swift/commit/6ec9d935489a496aca02bb7ac9613160ecf0659b) | 2026-10-27 11:24:50 | 编译器是 C++ 与 Swift 混合实现；Swift driver 还有独立仓库 |
| rustc-perf（辅助） | main，[41b881fd51c2d4099b218904bdfbdb209f72ba7e](https://github.com/rust-lang/rustc-perf/commit/41b881fd51c2d4099b218904bdfbdb209f72ba7e) | 2026-10-27 11:46:29 | 与 rustc 的语义实现仓库分开 |

需要先纠正三个容易误导架构判断的简称：

1. **LLVM 不是一门语言，也不是完整语言前端或托管运行时。** Clang、rustc 和 Swift 使用它的部分基础设施，仍各自承担类型系统、语言语义和运行时约定。
2. **“MIR”不能跨项目直接等同。** rustc MIR 是语言相关、可赋值位置与控制流导向的表示；LLVM MIR 指 Machine IR；Swift SIL 与二者都不同。
3. **“自举成功”不是相同的验收条件。** 各项目的 stage 编号、宿主库、目标库、产物比较方式不同。不能拿 stage 数量排序语言完整度或编译器独立性。

### 1.1 端到端结构对照

| 工具链 | 语言语义的主要拥有者 | 语言相关 lowering / 中间表示 | 机器后端与链接 |
| --- | --- | --- | --- |
| Clang + LLVM | Clang Parser、AST、Sema | 类型化 AST → LLVM IR；当前树另有 CIR，但不能仅因目录存在便断言其替代普通默认路径 | LLVM 指令选择、Machine IR、寄存器分配、MC；driver 调用选定 linker，LLD 是独立 linker 项目 |
| GCC | 各语言前端；C/C++ 不是整个 GCC 的唯一入口 | 前端树 / GENERIC → GIMPLE，许多优化使用 GIMPLE SSA → RTL | GCC RTL target passes、IRA/LRA、目标描述、汇编输出；driver/collect2 协调外部工具与 LTO |
| rustc | 名称解析、HIR 类型分析/trait solving、借用检查、const evaluation | AST → HIR → THIR → 多阶段 MIR；monomorphization / CGU → LLVM IR 等后端表示 | 常用 LLVM 后端；codegen_ssa/linker 层协调目标与链接；当前树也有 Cranelift/GCC 后端 |
| Swift | AST、Sema 约束求解、泛型与一致性系统 | AST → raw SIL → mandatory passes → canonical SIL → 可选性能优化 → LLVM IR | LLVM 机器后端；driver 调度 frontend、系统链接器及其他工具 |

依据：[Clang 内部架构](https://clang.llvm.org/docs/InternalsManual.html)、[GCC parsing/gimplification 边界](https://gcc.gnu.org/onlinedocs/gccint/Parsing-pass.html)、[rustc 总览](https://rustc-dev-guide.rust-lang.org/overview.html)、[Swift 编译器架构](https://www.swift.org/documentation/swift-compiler/)；Swift 阶段还核对了固定源码 [compilation-model.tex](https://github.com/swiftlang/swift/blob/6ec9d935489a496aca02bb7ac9613160ecf0659b/docs/Generics/chapters/compilation-model.tex)。

## 2. LLVM 与 Clang：语言语义与通用后端的明确分工

### 2.1 语义前端、类型与 lowering

Clang 的 lexer/preprocessor、递归下降 parser、Sema、AST 各有职责。Sema 不只是检查后附一个类型标签：它参与建立已解析声明、表达式和隐式转换。AST 保留部分源语法信息，例如括号节点；类型的规范化身份与源码中类型的写法也有不同表示。这支持诊断、工具和后续代码生成，而不是让 CodeGen 再靠名字猜源语言含义。[Clang Internals Manual](https://clang.llvm.org/docs/InternalsManual.html)

普通 CodeGen 把这些语义转换成 LLVM 可表达的控制流、数据、调用与异常机制。这个边界并不保证“一个 C++ 对象等于一个 LLVM struct”：位域、联合、基类、虚表以及 ABI 都需要明确 lowering。当前的 [CGRecordLayoutBuilder.cpp](https://github.com/llvm/llvm-project/blob/0bb039df436dee7400ebfebf80a302344c075142/clang/lib/CodeGen/CGRecordLayoutBuilder.cpp) 直接说明 AST 对象布局到 LLVM 类型的差异；[CGCXXABI.h](https://github.com/llvm/llvm-project/blob/0bb039df436dee7400ebfebf80a302344c075142/clang/lib/CodeGen/CGCXXABI.h) 则是 C++ ABI 专用代码生成边界。

这给 Dart 的启示是：解析后的调用角色、声明身份、求值顺序和赋值/返回转换应先明确，再进入低层 IR。后端接收的是已决定的语义，不应重新解释名称或按编译器自身源码写例外。

### 2.2 LLVM IR 与优化契约

LLVM IR 的类型描述低层值与操作，不等价于 C++、Rust、Swift 或 Dart 的完整类型系统。SSA、基本块、PHI、调用约定、内存与原子操作组成了优化器能够依赖的契约。[LLVM Language Reference](https://llvm.org/docs/LangRef.html)

必须区分三件事：

- IR 结构合法；
- frontend 正确表达了源语言行为；
- 某次优化保持了 IR 的语义。

[Verifier.cpp](https://github.com/llvm/llvm-project/blob/0bb039df436dee7400ebfebf80a302344c075142/llvm/lib/IR/Verifier.cpp) 检查类型、控制流、PHI 等约束，不能证明一段 C++ 或 Dart lowering 正确。LLVM 的 poison、undef、即时 UB 和延迟 UB 也是优化契约的一部分；错误地加 no-wrap 等承诺，可能让合法源程序被错误优化。[LLVM UB Manual](https://llvm.org/docs/UndefinedBehavior.html)

优化器并非只串联函数。中端 New Pass Manager 管理 module/CGSCC/function/loop 等层级分析，pass 需要说明哪些分析仍有效；机器后端目前仍有 legacy pass manager 路径，不能把“LLVM 已采用新 PM”理解为所有层都统一替换。[New Pass Manager](https://llvm.org/docs/NewPassManager.html)

**对 Dart 的取舍：**值得借用的是明确的分析失效与 effects 约定；不值得为了相似外观先引入 LLVM 的完整 pass manager。小编译器可用直接、有限的 pass 顺序，但每个 pass 仍须知道自己破坏了哪些事实。

### 2.3 机器后端、寄存器分配和链接

LLVM 的后端包含不同指令选择路径、目标合法化、机器级优化、寄存器分配、栈帧构建和 MC 层。指令已经选择不等于可以直接编码：调用破坏寄存器、寄存器类别、约束、spill、栈布局、prologue/epilogue 等仍需处理。[Code Generator 文档](https://llvm.org/docs/CodeGenerator.html)

当前源码确实包含 SelectionDAG、GlobalISel、Fast/Basic/Greedy/PBQP 分配器。Greedy 的实现、活跃区间与栈帧处理分别有独立拥有者：[RegAllocGreedy.cpp](https://github.com/llvm/llvm-project/blob/0bb039df436dee7400ebfebf80a302344c075142/llvm/lib/CodeGen/RegAllocGreedy.cpp)、[LiveIntervals.cpp](https://github.com/llvm/llvm-project/blob/0bb039df436dee7400ebfebf80a302344c075142/llvm/lib/CodeGen/LiveIntervals.cpp)、[PrologEpilogInserter.cpp](https://github.com/llvm/llvm-project/blob/0bb039df436dee7400ebfebf80a302344c075142/llvm/lib/CodeGen/PrologEpilogInserter.cpp)。不能把网页中的历史 LinearScan 文件名当作本次 HEAD 的现有实现。

AArch64 的指令、寄存器、调用约定与 lowering 不是零散编码模板，而有 [目标目录](https://github.com/llvm/llvm-project/tree/0bb039df436dee7400ebfebf80a302344c075142/llvm/lib/Target/AArch64) 的明确拥有者。MC 的 [MCAssembler.cpp](https://github.com/llvm/llvm-project/blob/0bb039df436dee7400ebfebf80a302344c075142/llvm/lib/MC/MCAssembler.cpp) 以及 ELF/MachO streamers 处理更接近目标文件的职责。

Clang driver 与链接器分开。LLD 支持 ELF、PE/COFF、Mach-O、Wasm，各有实现；使用 Clang 不表示所有平台自动使用 LLD。链接涉及符号、重定位、段布局和运行时依赖，LLVM IR 优化不是最终可执行文件的全部工作。[Clang 命令阶段](https://clang.llvm.org/docs/CommandGuide/clang.html)、[LLD 官方文档](https://lld.llvm.org/)、[固定 LLD 目录](https://github.com/llvm/llvm-project/tree/0bb039df436dee7400ebfebf80a302344c075142/lld)

### 2.4 泛型、对象和内存模型

Clang 的 C++ 模板实例化属于语言前端；例如 [SemaTemplateInstantiateDecl.cpp](https://github.com/llvm/llvm-project/blob/0bb039df436dee7400ebfebf80a302344c075142/clang/lib/Sema/SemaTemplateInstantiateDecl.cpp) 处理模板声明实例化。LLVM IR 并不会自动替 frontend 保留 C++ 模板语义，也不会凭泛型源码自行决定共享或特化策略。

C/C++ 对象布局和生命周期由源语言与目标 ABI 决定；LLVM 不提供统一“语言对象头”。LLVM 也不自带一个适用于所有语言的 GC。它提供 GC 集成能力，客户端仍负责收集器与语言运行时；moving GC 更需要 safepoint、活引用和重定位的明确合同。[Garbage Collection with LLVM](https://llvm.org/docs/GarbageCollection.html)、[GC Statepoints](https://llvm.org/docs/Statepoints.html)

因此纯 Dart 后端即使借用 LLVM，也不会免去 Dart 对象布局、reified type、异常、GC roots、分配器与标准库。反过来，选择自写后端也应把这些语言合同与机器约束分开，而不是复制 LLVM 的全部对象 API。

### 2.5 实现语言、bootstrap 和目录职责

LLVM/Clang 核心主要用 C++，目标描述使用 TableGen；构建/测试还依赖 CMake、Python 等。Clang 的 bootstrap 可先用宿主编译器构建 stage1，再以 stage1 构建 stage2；官方高级构建文档提供专门配置。这是有意配置的工具链构建，不应说每次普通 LLVM build 都自动三代比较。[Advanced Builds](https://llvm.org/docs/AdvancedBuilds.html)

| 固定源码入口 | 职责 |
| --- | --- |
| [clang/lib/Lex](https://github.com/llvm/llvm-project/tree/0bb039df436dee7400ebfebf80a302344c075142/clang/lib/Lex)、[Parse](https://github.com/llvm/llvm-project/tree/0bb039df436dee7400ebfebf80a302344c075142/clang/lib/Parse) | 预处理、token 与语法 |
| [clang/lib/AST](https://github.com/llvm/llvm-project/tree/0bb039df436dee7400ebfebf80a302344c075142/clang/lib/AST)、[Sema](https://github.com/llvm/llvm-project/tree/0bb039df436dee7400ebfebf80a302344c075142/clang/lib/Sema) | 声明、类型、表达式语义与诊断 |
| [clang/lib/CodeGen](https://github.com/llvm/llvm-project/tree/0bb039df436dee7400ebfebf80a302344c075142/clang/lib/CodeGen)、[Driver](https://github.com/llvm/llvm-project/tree/0bb039df436dee7400ebfebf80a302344c075142/clang/lib/Driver) | AST lowering 与工具调度，二者不是同一层 |
| [llvm/lib/IR](https://github.com/llvm/llvm-project/tree/0bb039df436dee7400ebfebf80a302344c075142/llvm/lib/IR)、[Transforms](https://github.com/llvm/llvm-project/tree/0bb039df436dee7400ebfebf80a302344c075142/llvm/lib/Transforms) | 通用 IR 定义、校验和优化 |
| [llvm/lib/CodeGen](https://github.com/llvm/llvm-project/tree/0bb039df436dee7400ebfebf80a302344c075142/llvm/lib/CodeGen)、[Target/AArch64](https://github.com/llvm/llvm-project/tree/0bb039df436dee7400ebfebf80a302344c075142/llvm/lib/Target/AArch64) | 机器表示/公共后端与目标约束 |
| [llvm/lib/MC](https://github.com/llvm/llvm-project/tree/0bb039df436dee7400ebfebf80a302344c075142/llvm/lib/MC)、[lld](https://github.com/llvm/llvm-project/tree/0bb039df436dee7400ebfebf80a302344c075142/lld) | 汇编/目标文件与最终链接 |

测试上有单元、lit/FileCheck 回归和单独的 test-suite。结构检查适合精确锁定一个优化或目标指令行为；能成功 FileCheck 不代表整个程序语义、运行时或所有平台已通过。[Testing Guide](https://llvm.org/docs/TestingGuide.html)、[test-suite Guide](https://llvm.org/docs/TestSuiteGuide.html)

**可借鉴：**源码保真 AST、明确 ABI lowering、typed IR verifier、机器约束拥有者和可独立复现的回归。**不可照搬：**多语言/多目标规模产生的目录、TableGen 层次、pass infrastructure，以及 C++ 的 UB 或对象模型。

## 3. GCC：多语言前端、GIMPLE 优化与 RTL 目标约束

### 3.1 前端语义与 GENERIC/GIMPLE 边界

GCC 是 compiler collection，不是仅一个 C parser。各语言前端可以使用适合自己的表示，再接语言无关部分。官方文档明确允许前端私有表示；C/C++ 的前端树与 gimplifier hooks 也不等于所有前端先完整生成同一种 GENERIC AST。[Parsing pass](https://gcc.gnu.org/onlinedocs/gccint/Parsing-pass.html)

GENERIC 是供前端与语言无关部分沟通的树表示；GIMPLE 限制表达式复杂度，把复杂运算拆到更明确的语句和临时值。存在 high/low GIMPLE 的阶段差别，不能把“GIMPLE”当作一开始就已完成全部控制流和 SSA lowering 的单一状态。[GENERIC](https://gcc.gnu.org/onlinedocs/gccint/GENERIC.html)、[GIMPLE](https://gcc.gnu.org/onlinedocs/gccint/GIMPLE.html)

C++ 的语法、类型、模板和类语义在 gcc/cp 中处理，C 家族共享部分在 c-family。语言合法性仍属于这些前端，而不是 RTL 后端通过名称或机器类型反推。

### 3.2 SSA、pass 与跨过程优化的契约

GCC 的许多 tree optimizers 使用 GIMPLE SSA。真实值和虚拟内存名字的 SSA、PHI 与 CFG 必须随变换更新；某个 pass 新建值、复制语句或改变别名事实后，不能继续使用旧的 SSA 假设。[GCC SSA](https://gcc.gnu.org/onlinedocs/gccint/SSA.html)

当前 [tree-pass.h](https://github.com/gcc-mirror/gcc/blob/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/tree-pass.h) 的 pass_data 明确记录 required/provided/destroyed properties 与 todo flags，gate 和 execute 也分开。其价值是使一个优化有清楚的前置状态和输出状态，而不只是“能遍历 IR”。[Pass manager 文档](https://gcc.gnu.org/onlinedocs/gccint/Pass-manager.html)

LTO 不只是再调用一次 linker：GIMPLE、类型、声明和调用图会被写入中间对象，在链接阶段重新读入；WPA 与 LTRANS 将全局分析和分区变换分开。这是对大量翻译单元、内存与并行成本的回应，并不是小编译器第一天必需的框架。[LTO Overview](https://gcc.gnu.org/onlinedocs/gccint/LTO-Overview.html)

对 Dart 的推论：先维护可靠的符号/类型/控制流和跨模块依赖，才可能安全地添加跨库内联或 whole-program 优化。以字符串拼接“合并所有源文件”不能代替库身份与私有性。

### 3.3 RTL、IRA/LRA、目标描述与链接

GIMPLE 转为 RTL 后，机器模式、寄存器、目标指令约束和后端优化成为核心。IRA 使用区域化寄存器分配，并考虑 live ranges、合并、分裂和目标代价；LRA 再处理指令实际约束及由 spill/reload 等引起的反复合法化。这不是两种可随意互换的文件名。[RTL passes](https://gcc.gnu.org/onlinedocs/gccint/RTL-passes.html)、[ira.cc](https://github.com/gcc-mirror/gcc/blob/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/ira.cc)、[lra.cc](https://github.com/gcc-mirror/gcc/blob/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/lra.cc)

目标目录中的 .md、约束和 C++ hooks 描述机器行为；例如 [config/aarch64](https://github.com/gcc-mirror/gcc/tree/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/config/aarch64)。公共后端会输出汇编，driver 与 assembler/linker 配合完成产物；不能把 GCC 的机器后端说成自己包含 GNU binutils 的全部 linker。

[gcc.cc](https://github.com/gcc-mirror/gcc/blob/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/gcc.cc) 的文件说明直接把它定义为多语言 driver：选择工具、传递参数、管理临时文件。[collect2.cc](https://github.com/gcc-mirror/gcc/blob/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/collect2.cc) 与 LTO 也在链接调度边界内；它们不承担 C++ 表达式类型检查。

### 3.4 泛型、对象模型，以及 GCC 自己的 GC

C++ 模板实例化的主要实现位于 [gcc/cp/pt.cc](https://github.com/gcc-mirror/gcc/blob/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/cp/pt.cc)；类处理位于 [cp/class.cc](https://github.com/gcc-mirror/gcc/blob/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/cp/class.cc)。这是一种源语言特性实现；名称 GENERIC 不表示 GCC 自动为所有语言提供同一种运行时泛型机制。

必须特别区分 **GCC 编译器内部的 GGC** 与被编译程序的内存模型。GGC 为编译器树等对象及 PCH 提供追踪/分配支持，GTY/gengtype 描述相关字段；它不会把普通 C/C++ 程序改成使用这一 GC。[Type Information](https://gcc.gnu.org/onlinedocs/gccint/Type-Information.html)、[ggc-page.cc](https://github.com/gcc-mirror/gcc/blob/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/ggc-page.cc)

对纯 Dart 自托管，这一点尤其重要：用 Dart 实现的编译器进程如何管理内存，与它生成程序的对象/GC 合同，是两个分别需要闭合的系统。当前 native dartc 的 bump 分配并不包含回收；不能因为编译器源码可创建对象，就认为目标对象扫描或 safepoint 已正确。

### 3.5 实现语言、bootstrap、源码与测试

GCC 核心目前是 C++ 实现；官方当前构建前提列出 C++14 宿主编译器要求。不能因历史文件名或 GCC 起源于 C 而说当前核心仍必须用 C 编译。[Build prerequisites](https://gcc.gnu.org/install/prerequisites.html)

普通 native bootstrap 的默认路线是三阶段，比较 stage2 与 stage3 编译器结果，并使用 stage3 构建目标运行库。可以关闭 bootstrap；交叉编译与更多配置又有不同路线。因此“三阶段”描述的是具体构建配置，不是整套语言已完成的证明。[Building GCC](https://gcc.gnu.org/install/build.html)

| 固定源码入口 | 职责 |
| --- | --- |
| [gcc/c](https://github.com/gcc-mirror/gcc/tree/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/c)、[cp](https://github.com/gcc-mirror/gcc/tree/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/cp)、[c-family](https://github.com/gcc-mirror/gcc/tree/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/c-family) | C/C++ 及共享的语言前端 |
| [gimplify.cc](https://github.com/gcc-mirror/gcc/blob/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/gimplify.cc)、[gimple.h](https://github.com/gcc-mirror/gcc/blob/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/gimple.h) | GIMPLE lowering 与表示 |
| [passes.cc](https://github.com/gcc-mirror/gcc/blob/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/passes.cc)、[passes.def](https://github.com/gcc-mirror/gcc/blob/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/passes.def) | pass 管理与顺序 |
| [cfgexpand.cc](https://github.com/gcc-mirror/gcc/blob/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/cfgexpand.cc)、[ira.cc](https://github.com/gcc-mirror/gcc/blob/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/ira.cc)、[lra-constraints.cc](https://github.com/gcc-mirror/gcc/blob/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/lra-constraints.cc) | RTL 展开、分配、机器约束 |
| [config/aarch64](https://github.com/gcc-mirror/gcc/tree/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/config/aarch64) | 目标模式、约束、ABI 与调优 |
| [gcc/testsuite](https://github.com/gcc-mirror/gcc/tree/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/testsuite)、[gcc/doc/sourcebuild.texi](https://github.com/gcc-mirror/gcc/blob/684c9811dee6573fdb8b01c9bef16e68054fc87c/gcc/doc/sourcebuild.texi) | DejaGnu 测试与指令约定 |

测试覆盖诊断、编译、链接、执行、不同优化选项、GIMPLE/RTL 和 ABI 等维度；测试驱动有明确的预期输出与 target 条件。[Testsuites](https://gcc.gnu.org/onlinedocs/gccint/Testsuites.html) 编译器本身有 IR dump、时间和内存报告选项，适合定位阶段成本。[Developer Options](https://gcc.gnu.org/onlinedocs/gcc/Developer-Options.html) 本次没有核实或假设一个与 rustc-perf 完全相同的统一 GCC 性能服务。

**可借鉴：**stage 产物比较、显式 IR properties、语言无关优化和 target constraints 分层、编译时间与内存可观察。**不可照搬：**多十年目标兼容与宏/hook 体系、完整机器描述生成系统，以及 C/C++ 模板/生命周期替代 Dart 泛型/GC。

## 4. Rust rustc：语言专属 MIR、单态化与查询依赖

### 4.1 语义前端与不同层的作用

rustc 的词法、解析、宏展开、名称解析和 HIR lowering 是不同职责。HIR 类型分析包含推断、trait 相关推理等，THIR 具有更明确的已检查表达式语义，然后构造 MIR。不能因为最终常用 LLVM，就把 Rust 类型系统视为“LLVM 类型的语法糖”。[rustc Overview](https://rustc-dev-guide.rust-lang.org/overview.html)

MIR 不要求每个 Rust local 只赋值一次。它用 local/place、赋值、基本块和 terminator 表达程序；借用检查、move/初始化分析和 drop elaboration 依赖这一结构。它与 LLVM Machine IR 既不处在同一层，也不承诺相同语义。[MIR guide](https://rustc-dev-guide.rust-lang.org/mir/index.html)、[Borrow checking](https://rustc-dev-guide.rust-lang.org/borrow-check.html)

### 4.2 MIR 阶段不是仅一组 pass 名

当前 [mir/syntax.rs](https://github.com/rust-lang/rust/blob/16d1ffac17ad8b739e32483ac2e65fe7e1804977/compiler/rustc_middle/src/mir/syntax.rs) 明确区分 Built、Analysis、Runtime 等 dialect/phase。相同数据结构不等于相同语义：例如 drop 从分析阶段的条件含义转到 runtime 阶段的明确操作，允许出现的结构也逐步收紧。

这比“统一一个无所不能的 IR”更值得借鉴：哪一步已经完成初始化分析、异常展开、drop、const promotion，必须能判断。Dart 可以用较少的类或文件表达阶段，但必须知道例如 checked cast、nullable representation、constructor plan 与 GC-safe call 在什么时候已确定。

### 4.3 单态化、代码单元与后端

Rust 的泛型机器码通常经过 mono item 收集：从根出发，跟踪调用、函数引用、drop glue 等依赖，发现实际需要的实例，随后分 codegen units。跨 crate 的泛型也可能在使用方实例化。这里既有运行速度收益，也有编译时间、重复码与增量稳定性的代价。[Monomorphization](https://rustc-dev-guide.rust-lang.org/backend/monomorph.html)、[collector.rs](https://github.com/rust-lang/rust/blob/16d1ffac17ad8b739e32483ac2e65fe7e1804977/compiler/rustc_monomorphize/src/collector.rs)

Rust 的通用 codegen 层、LLVM 层和链接调度不是一个文件。使用 LLVM 后端时，机器指令选择与寄存器分配主要由 LLVM 承担；rustc 仍负责语言 ABI lowering、代码单元、元数据和选定 linker 的参数等。当前树也有 Cranelift 与 GCC 后端；目录存在不能说明它们在全部目标、优化质量或生产使用上等价。[Code generation guide](https://rustc-dev-guide.rust-lang.org/backend/codegen.html)、[codegen_ssa/back/link.rs](https://github.com/rust-lang/rust/blob/16d1ffac17ad8b739e32483ac2e65fe7e1804977/compiler/rustc_codegen_ssa/src/back/link.rs)

### 4.4 所有权、对象布局与动态分派

Rust 没有一个适用于所有值的语言对象头。普通值、引用、Box、Rc/Arc 与 trait object 是不同机制；已初始化值离开作用域时的 drop 及部分初始化规则，是语言语义，不是“LLVM 自动释放内存”。[Rust destructors](https://doc.rust-lang.org/reference/destructors.html)

trait object 的间接引用携带数据与相应 vtable 信息，动态分派由此实现；这与模板实例化或一个通用 GC object pointer 不能混为一谈。[Trait objects](https://doc.rust-lang.org/reference/types/trait-object.html) 默认 Rust 布局、repr(C) 和函数 ABI 还需区分：值的大小/字段偏移相同不自动意味着调用 ABI 相同，默认布局也不能被当成稳定 C ABI。[Type layout](https://doc.rust-lang.org/reference/type-layout.html)

对 Dart 的界限非常直接：借用检查和确定性 Drop 不能取代 Dart 的 tracing GC、闭包引用生命周期和动态类型语义。可以借鉴“显式表示哪些值是引用、何时存在 alias、调用有何 effect”；不能借另一语言的限制来消除合法 Dart 程序。

### 4.5 查询与增量编译

rustc 的 query system 按依赖获取结果，并用增量依赖图判断可复用性。跨编译缓存需要稳定身份；会话中的数字 ID 不能不经处理直接作为持久化键，文档举 DefPathHash 等例子说明这一点。[Incremental compilation in detail](https://rustc-dev-guide.rust-lang.org/queries/incremental-compilation-in-detail.html)

这不是建议立即给 dartc 新建一个 query framework。可先把库身份、声明身份、target/语言版本/配置输入和结果依赖定义清楚；出现可测重复分析或增量需求后，再决定缓存粒度。缓存一个原本不纯或漏依赖的 lowering，只会让错误更难复现。

### 4.6 实现语言、bootstrap、源码与测试

rustc 本身主要用 Rust；默认工具链仍有 LLVM 的 C++ 实现和宿主构建工具。stage0 通常取近期预编译 beta 编译器及对应库；stage1 由旧工具构建当前编译器，stage2 把当前编译器与树内库配套构建，stage3 是可选 same-result 检验。编译器阶段与其生成的库阶段存在错位，不能只写三个同名二进制就认为链条等价。[What bootstrapping does](https://rustc-dev-guide.rust-lang.org/building/bootstrapping/what-bootstrapping-does.html)

| 固定源码入口 | 职责 |
| --- | --- |
| [rustc_lexer](https://github.com/rust-lang/rust/tree/16d1ffac17ad8b739e32483ac2e65fe7e1804977/compiler/rustc_lexer)、[rustc_parse](https://github.com/rust-lang/rust/tree/16d1ffac17ad8b739e32483ac2e65fe7e1804977/compiler/rustc_parse)、[rustc_resolve](https://github.com/rust-lang/rust/tree/16d1ffac17ad8b739e32483ac2e65fe7e1804977/compiler/rustc_resolve) | token、语法、解析声明身份 |
| [rustc_hir_typeck](https://github.com/rust-lang/rust/tree/16d1ffac17ad8b739e32483ac2e65fe7e1804977/compiler/rustc_hir_typeck)、[rustc_trait_selection](https://github.com/rust-lang/rust/tree/16d1ffac17ad8b739e32483ac2e65fe7e1804977/compiler/rustc_trait_selection) | 表达式类型与 trait 相关语义 |
| [rustc_mir_build](https://github.com/rust-lang/rust/tree/16d1ffac17ad8b739e32483ac2e65fe7e1804977/compiler/rustc_mir_build)、[rustc_borrowck](https://github.com/rust-lang/rust/tree/16d1ffac17ad8b739e32483ac2e65fe7e1804977/compiler/rustc_borrowck)、[rustc_const_eval](https://github.com/rust-lang/rust/tree/16d1ffac17ad8b739e32483ac2e65fe7e1804977/compiler/rustc_const_eval) | MIR 建立与语言正确性分析 |
| [rustc_mir_transform](https://github.com/rust-lang/rust/tree/16d1ffac17ad8b739e32483ac2e65fe7e1804977/compiler/rustc_mir_transform)、[rustc_monomorphize](https://github.com/rust-lang/rust/tree/16d1ffac17ad8b739e32483ac2e65fe7e1804977/compiler/rustc_monomorphize) | MIR 变换和实际代码实例收集 |
| [rustc_codegen_ssa](https://github.com/rust-lang/rust/tree/16d1ffac17ad8b739e32483ac2e65fe7e1804977/compiler/rustc_codegen_ssa)、[rustc_codegen_llvm](https://github.com/rust-lang/rust/tree/16d1ffac17ad8b739e32483ac2e65fe7e1804977/compiler/rustc_codegen_llvm) | 后端共用调度与 LLVM 实现 |
| [library](https://github.com/rust-lang/rust/tree/16d1ffac17ad8b739e32483ac2e65fe7e1804977/library)、[src/bootstrap](https://github.com/rust-lang/rust/tree/16d1ffac17ad8b739e32483ac2e65fe7e1804977/src/bootstrap) | core/alloc/std 等库与分阶段构建 |

compiletest 将 UI 诊断、运行、MIR 优化、LLVM/codegen、assembly、增量、run-make 等测试分开；一类绿色不能取代其他层证据。[Compiletest](https://rustc-dev-guide.rust-lang.org/tests/compiletest.html)

性能证据也应更新到实际源码：本次 rustc-perf HEAD 的 README 同时指向 compile-benchmarks 与 runtime-benchmarks，不能沿用旧介绍说它“只测编译时间”。collector 收集、site 展示和触发请求，是与编译器实现分开的职责。[固定 rustc-perf README](https://github.com/rust-lang/rustc-perf/blob/41b881fd51c2d4099b218904bdfbdb209f72ba7e/README.md)

**可借鉴：**语言相关 CFG IR、阶段语义、按真实引用收集产物、稳定输入身份、bootstrap 与诊断/执行/性能多层闭环。**不可照搬：**trait solver、所有权语言规则、全面单态化策略、庞大 query/CGU 系统作为 Dart 初始架构的必选项。

## 5. Swift：语言专属 SSA、运行时泛型与渐进自用

### 5.1 类型检查与 SILGen

Swift 的 Sema 使用约束系统，类型检查不只是从左向右给每节点选一个类型：上下文、重载、泛型要求和解的应用都会影响最终 AST。固定 [TypeChecker.md](https://github.com/swiftlang/swift/blob/6ec9d935489a496aca02bb7ac9613160ecf0659b/docs/TypeChecker.md) 把约束生成、求解与应用解分开，也解释了限制求解范围的工程代价。

完成类型检查后，SILGen 生成 raw SIL。SIL 是 Swift 语义层的 SSA，而不是 LLVM IR 换一个名字。mandatory passes 进行必要的数据流检查/lowering，形成 canonical SIL；性能 passes 在此基础上工作。关闭性能优化并不表示可以跳过 definite initialization 等语言正确性步骤。[固定 SIL 文档](https://github.com/swiftlang/swift/blob/6ec9d935489a496aca02bb7ac9613160ecf0659b/docs/SIL/SIL.md)、[官方架构](https://www.swift.org/documentation/swift-compiler/)

### 5.2 Ownership SSA、ARC 与优化边界

SIL 的 ownership information 位于 value/operand 的语义上，区分非结束生命周期与结束生命周期的 use。ownership verifier 可以检查相应不变量，优化也必须维持它们。[Ownership.md](https://github.com/swiftlang/swift/blob/6ec9d935489a496aca02bb7ac9613160ecf0659b/docs/SIL/Ownership.md)

因此 Swift 的 ARC 优化、值拷贝消除、devirtualization、generic specialization 等可以在仍保留语言事实的层上做，再由 IRGen 进入 LLVM。若过早抹成普通指针和函数调用，会失去不少安全优化依据。另一方面，SIL 的所有权规则并不是 tracing GC 的 root/liveness 合同；不能用 ARC retain/release 的正确性推断 Dart moving/nonmoving GC 已正确。

### 5.3 泛型、协议与对象/值布局

Swift 泛型通常允许共享实现：调用方传入泛型实参的运行时类型 metadata；未知布局的值通过 metadata 提供的操作处理。定义可见且合适时再生成 specialization。它不是“每个类型都必须像 C++ 模板一样只生成一份独立机器码”的统一路线。[Generics introduction.tex](https://github.com/swiftlang/swift/blob/6ec9d935489a496aca02bb7ac9613160ecf0659b/docs/Generics/chapters/introduction.tex)

协议一致性同时拥有类型与值 witnesses。SILGen/IRGen 将语义一致性转换成 witness tables 等运行时结构；泛型算法和 existential 都需要在不知道具体类型布局时操作值。[conformances.tex](https://github.com/swiftlang/swift/blob/6ec9d935489a496aca02bb7ac9613160ecf0659b/docs/Generics/chapters/conformances.tex)、[GenProto.cpp](https://github.com/swiftlang/swift/blob/6ec9d935489a496aca02bb7ac9613160ecf0659b/lib/IRGen/GenProto.cpp)

运行时 metadata 描述类型、值操作和布局；普通 nominal types 与泛型实例的建立时机可以不同。类、struct、enum、existential 的表示也不应混成单一对象指针。旧 ABI 说明中某些字段枚举与 TODO 仍具历史痕迹，本文只取其职责，不把其中所有常数视作当前所有平台的最终布局。[TypeMetadata.rst](https://github.com/swiftlang/swift/blob/6ec9d935489a496aca02bb7ac9613160ecf0659b/docs/ABI/TypeMetadata.rst)、[TypeLayout.rst](https://github.com/swiftlang/swift/blob/6ec9d935489a496aca02bb7ac9613160ecf0659b/docs/ABI/TypeLayout.rst)

这一方向对 Dart 比照搬 Rust 单态化更有直接参考价值：reified types、动态检查与共享泛型代码需要明确 metadata；特化是保留语义后的可选成本决策。但 Dart 的协变、dynamic、类模型、GC 与异常仍需自己的规范实现，不能直接换成 Swift witness/ARC ABI。

### 5.4 机器后端、driver 与产物

IRGen 将 SIL 的调用、类型与布局约定落实为 LLVM IR；LLVM 随后承担低层优化、指令选择和寄存器分配。Swift 不需要再在 SIL 层做一份等同 LLVM 的物理寄存器分配器。[Swift compiler architecture](https://www.swift.org/documentation/swift-compiler/)

driver 负责 source files、frontend jobs、模块、对象文件与 linker 等工具。当前泛型书的 compilation model 已说明 batch 与 WMO 的职责/重复工作差异；较旧的 CompilerPerformance 文档仍含“batch 将成为默认”的历史措辞，不能据此断言当前默认模式。性能分析要区分 driver 等待、frontend 工作以及链接/调试工具成本。[当前 compilation model](https://github.com/swiftlang/swift/blob/6ec9d935489a496aca02bb7ac9613160ecf0659b/docs/Generics/chapters/compilation-model.tex)、[CompilerPerformance.md](https://github.com/swiftlang/swift/blob/6ec9d935489a496aca02bb7ac9613160ecf0659b/docs/CompilerPerformance.md)

### 5.5 实现语言与真实 bootstrap 链

Swift 编译器**并非全部用 Swift 实现**。当前树有大量 C++ frontend/IRGen/SIL 基础设施，也有 SwiftCompilerSources 的 Swift AST/Basic/SIL/Optimizer 模块。标准库核心以 Swift 为主，runtime 仍有大量 C++/少量其他语言实现；不能把“标准库是 Swift”说成 allocator、metadata、引用计数等基础全由 Swift 自主实现。[Swift 标准库架构](https://www.swift.org/documentation/standard-library/)、[stdlib/public/runtime](https://github.com/swiftlang/swift/tree/6ec9d935489a496aca02bb7ac9613160ecf0659b/stdlib/public/runtime)

当前 [SwiftCompilerSources/README.md](https://github.com/swiftlang/swift/blob/6ec9d935489a496aca02bb7ac9613160ecf0659b/SwiftCompilerSources/README.md) 列出 off、hosttools 与 bootstrapping 等模式。bootstrapping 先生成不含这些 Swift 模块的 level0 编译器，再构建最小标准库和后续 Swift 模块/编译器，逐步得到最终产物；hosttools 当前要求 Swift 6.2。该设计还约束哪些 mandatory passes 可以迁移到可选 Swift 模块，不能把这条链简写为“现有 Swift 直接编译全部新版 Swift”。

这对 Dart 是支持后采用的有力类比，但也有清楚界限：如果纯 Dart 独立编译器是目标，不应把一个长期保留的 C++ level0/frontend 当作最终自托管成果。可恢复的旧 native dartc 应作为新能力支持链的种子，而不是永久外部实现替代。

### 5.6 源码职责与验证闭环

| 固定源码入口 | 职责 |
| --- | --- |
| [lib/Parse](https://github.com/swiftlang/swift/tree/6ec9d935489a496aca02bb7ac9613160ecf0659b/lib/Parse)、[AST](https://github.com/swiftlang/swift/tree/6ec9d935489a496aca02bb7ac9613160ecf0659b/lib/AST)、[Sema](https://github.com/swiftlang/swift/tree/6ec9d935489a496aca02bb7ac9613160ecf0659b/lib/Sema) | 语法与语义基础；当前树另有 ASTGen/CompilerSwiftSyntax，不宜把全部未来前端归为一条旧路径 |
| [lib/SILGen](https://github.com/swiftlang/swift/tree/6ec9d935489a496aca02bb7ac9613160ecf0659b/lib/SILGen)、[SIL](https://github.com/swiftlang/swift/tree/6ec9d935489a496aca02bb7ac9613160ecf0659b/lib/SIL)、[SILOptimizer](https://github.com/swiftlang/swift/tree/6ec9d935489a496aca02bb7ac9613160ecf0659b/lib/SILOptimizer) | 语言 IR 建立、表示及变换 |
| [lib/IRGen](https://github.com/swiftlang/swift/tree/6ec9d935489a496aca02bb7ac9613160ecf0659b/lib/IRGen) | LLVM lowering、metadata、调用与布局 |
| [SwiftCompilerSources/Sources](https://github.com/swiftlang/swift/tree/6ec9d935489a496aca02bb7ac9613160ecf0659b/SwiftCompilerSources/Sources) | Swift 编写的真实编译器模块，不是整个编译器 |
| [stdlib/public/core](https://github.com/swiftlang/swift/tree/6ec9d935489a496aca02bb7ac9613160ecf0659b/stdlib/public/core)、[runtime](https://github.com/swiftlang/swift/tree/6ec9d935489a496aca02bb7ac9613160ecf0659b/stdlib/public/runtime) | 标准库值/容器等与底层运行时的不同职责 |
| [test](https://github.com/swiftlang/swift/tree/6ec9d935489a496aca02bb7ac9613160ecf0659b/test)、[validation-test](https://github.com/swiftlang/swift/tree/6ec9d935489a496aca02bb7ac9613160ecf0659b/validation-test)、[benchmark](https://github.com/swiftlang/swift/tree/6ec9d935489a496aca02bb7ac9613160ecf0659b/benchmark) | 功能/回归、验证和运行时基准分开 |

Swift 的测试包含 lit、单元和真实开源项目；validation、long/stress 又有不同用途。[Testing.md](https://github.com/swiftlang/swift/blob/6ec9d935489a496aca02bb7ac9613160ecf0659b/docs/Testing.md) benchmark suite 对比既有与变更工具链，标准库路径和优化级别是输入的一部分。[benchmark/README.md](https://github.com/swiftlang/swift/blob/6ec9d935489a496aca02bb7ac9613160ecf0659b/benchmark/README.md)

**可借鉴：**语言专属 SSA、mandatory correctness passes、metadata + 可选特化、逐步用本语言实现基础设施。**不可照搬：**ARC 语义、resilience/ObjC 兼容的全部 ABI 层、C++ fallback 作为纯 Dart 长期终点，以及为尚无需求的协议系统先建 Requirement Machine。

## 6. 研究边界与文档漂移

- 本次核对了四个固定 HEAD 的实际目录和关键源码，不是逐文件全面审计；没有独立执行其完整测试或证明某后端在某平台的产品成熟度。
- GCC 的在线 internals、LLVM CodeGenerator、Swift CompilerPerformance/部分 ABI 文档都有历史例子、旧文件后缀、TODO 或默认值描述。本文以当前路径核对职责，不把滚动网页的每一句当固定提交的精确实现。
- Swift 当前泛型书同样明确是持续完善的实现说明；其中编译模型比某些旧性能页面新。源码与文档冲突时，报告保留限定，不猜测统一的“官方最终算法”。
- 当前 rustc-perf 已包含 compile/runtime 两类目录；沿用旧介绍会漏掉实际演进。
- GitHub 网页/检索器生成的行号可能不是文件实际行号。本文使用固定提交文件链接，不制造未经原始字节验证的行锚点。
- 所有运行时选择都受各自语言语义约束。借鉴职责与验证方法，不代表接受缩小 Dart 目标、移除合法行为，或把其他编译器永久作为执行基础。


跨项目取舍与本项目审查统一见 [总览](README.md) 和 [dartc](dartc.md)。
