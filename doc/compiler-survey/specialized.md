# 科学计算、函数式及小型工具链

这些案例补充 [主流系统工具链](native.md) 和 [托管运行时](managed.md)。它们的价值在具体语义和工程边界，不表示处在同一个性能排行榜。源码引用固定到调研所读的 revision；在线文档可能继续更新。

## Fortran：Flang 与 LFortran

Fortran 值得调查的原因是数组、别名、参数关联、临时量和布局都直接影响优化。把所有语言操作过早变成无区别的 loads/stores，会让后端失去原有语义信息；LLVM 不能自动恢复已经丢失的数组或对象合同。

**Flang** 是 LLVM 项目中的 C++ 前端。语义分析后通过 HLFIR/FIR 逐步降低到 LLVM；HLFIR 保留数组表达式、赋值、分配和变量属性，使消除临时量等变换发生在信息仍然存在的时候。文档中的 transition 计划含历史内容，不能把旧的可选 lowering 路径当成当前结构。[HLFIR 设计](https://flang.llvm.org/docs/HighLevelFIR.html)、[Flang driver 与 pass 边界](https://flang.llvm.org/docs/FlangDriver.html)

实际职责包括 `flang/lib/Parser`、`Semantics`、`Lower`、`Optimizer`；所读 LLVM revision 的运行时拥有者已是独立 [flang-rt/](https://github.com/llvm/llvm-project/tree/0bb039df436dee7400ebfebf80a302344c075142/flang-rt)，不能从旧文章假定仍在前端目录下。与 GCC 的 gfortran 一样，它证明的是前端保留 Fortran 语义再交给公共后端，并非 Fortran 编译器整体由 Fortran 自托管。LLVM 当前源码基线见 [native.md](native.md)。

**LFortran** 的 AST 与 ASR 是更直接的语义边界案例：AST 表示语法；ASR 的合同是已经过语义检查的程序；高层变换操作 ASR，再进行低层 codegen。设计文档讨论不可变构建和 Debug 校验，但不能据此认定当前所有节点已不可变。源码确有独立的 ASR verifier、pass 和 codegen 拥有者。[设计](https://docs.lfortran.org/en/design/)、[ASR 定义和验证源码](https://github.com/lfortran/lfortran/tree/cb859775a5537e9600485ba0de0a499e667d7db1/src/libasr)

在 [cb859775](https://github.com/lfortran/lfortran/tree/cb859775a5537e9600485ba0de0a499e667d7db1) 中，`src/lfortran/parser`、`semantics` 拥有前端，`src/libasr/ASR.asdl` 拥有表示，`asr_verify.cpp` 拥有验证，`pass/`、`codegen/` 分别拥有变换和发码。它的实现主要是 C++，使用 LLVM 等后端，不构成纯 Fortran 执行基础的证据。

**对 dartc 的取舍**：学习“lowering 前的语义事实必须有拥有者”和延迟表示决策；不必复制 ASR 全家桶或引入 MLIR 依赖。已有 AST 加已检查结果表就可以成为第一步。Dart 对象、类型检查、异常和分配也不应在需要分析之前就全部隐藏到无区别的 runtime 调用里。

## Julia

Julia 的重要性在于：语言自身实现了类型推断、抽象解释和大量优化，同时与原生 codegen/运行时协作。其 SSA 设计文档明确解释了历史上缺少完整合流表示对中端优化的限制，并单独处理路径类型事实和异常流；这比“有一个 SSA 类”更具体。[执行流程](https://docs.julialang.org/en/v1/devdocs/eval/)、[SSA 设计](https://docs.julialang.org/en/v1/devdocs/ssair/)

当前 [a60dfe36](https://github.com/JuliaLang/julia/tree/a60dfe36e139c6125e41fddabb4e3b5c405ef718) 中，`JuliaSyntax/`、`JuliaLowering/` 与 `Compiler/` 已成为明确目录；`Compiler/src/typeinfer.jl`、`abstractinterpretation.jl`、`effects.jl`、`optimize.jl`、`ssair/` 拥有语言级推断与优化。旧文档里 `base/compiler` 或小写 `compiler` 的路径不能直接当成当前文件布局。[Compiler 源码](https://github.com/JuliaLang/julia/tree/a60dfe36e139c6125e41fddabb4e3b5c405ef718/Compiler/src)

底层仍有 `src/` 中的 C/C++ 运行时和 LLVM codegen。官方 GC 文档描述非移动、分代、并行且部分并发的 mark-sweep，以及 pool、大对象和空页处理；这不是一个“Julia 编译器能编译自己，所以 GC 也全由 Julia 实现”的例子。[GC 设计](https://docs.julialang.org/en/v1/devdocs/gc/)

**对 dartc 的取舍**：学习可在自身语言中替换的推断/效果/优化算法，以及语言事实对装箱消除的支持。Julia 的动态方法世界、JIT、失效和系统镜像有自己的语义和成本；封闭程序 Dart AOT 不应为模仿它们引入整套动态编译系统。Julia 科学计算的某项优势也不能替代 dartc 自己的同任务测量。

## GHC / Haskell

GHC 将 Haskell 的类型、字典、惰性求值和闭包语义分阶段交接：Core 上做语言级简化和专门化，STG 明确运行时执行形式，再到 Cmm 和 native/LLVM 后端。这些表示不是几份随意重命名的 CFG，它们分别承担不同的不变量。官方文档也提供 Core/STG/Cmm dump、lint、阶段耗时和分配统计。[调试与一致性检查](https://ghc.gitlab.haskell.org/ghc/doc/users_guide/debugging.html)、[后端说明](https://ghc.gitlab.haskell.org/ghc/doc/users_guide/codegens.html)

在 [c83c6733](https://github.com/ghc/ghc/tree/c83c673315407f28209004fc5a1cb2c47ad3890e) 中，`compiler/GHC/Parser`、`Rename`、`Tc`、`HsToCore`、`Core`、`CoreToStg`、`Stg`、`StgToCmm`、`Cmm`、`CmmToAsm`、`CmmToLlvm` 是实际拥有者；不能照抄旧版本中已经不同的 LLVM codegen 路径。`rts/` 与 `libraries/` 分开，`hadrian/` 和 `testsuite/` 分别负责构建和测试。[编译器源码](https://github.com/ghc/ghc/tree/c83c673315407f28209004fc5a1cb2c47ad3890e/compiler/GHC)

编译器主要由 Haskell 实现、使用已有 GHC 引导；运行时包含 C、Cmm 和汇编。native backend 生成汇编并依赖相应原生工具；使用 LLVM 的路径又有自己的构建成本。官方关于两条后端性能的描述是该项目的经验，不是本调查重跑的跨语言排名。

**对 dartc 的取舍**：闭包转换、运行时调用形式、异常和 GC 的阶段边界很有价值；不能照搬惰性求值或把 Haskell 的专门化规则当成 Dart 泛型规则。函数值、捕获环境和异常的引入，需要显式更新 IR/根/调用合同，而不是只在 AST 增加节点。

## OCaml 与 OxCaml

OCaml 有清晰的 syntax → typedtree → 中端 → 机器后端边界。上游 [8aaafa8b](https://github.com/ocaml/ocaml/tree/8aaafa8b4b92f94f16305c8f7c45b2618f6173f4) 的实际目录是 `parsing/`、`typing/`、`lambda/`、`middle_end/`、`asmcomp/`、`bytecomp/`，另有 `runtime/`、`stdlib/`、`testsuite/`。`typing/typedtree.mli` 与低层表示不是同一个概念。运行时主要用 C 和少量平台汇编，不随“编译器由 OCaml 实现”而变为全 OCaml。[HACKING](https://github.com/ocaml/ocaml/blob/8aaafa8b4b92f94f16305c8f7c45b2618f6173f4/HACKING.adoc)

其 [BOOTSTRAP.adoc](https://github.com/ocaml/ocaml/blob/8aaafa8b4b92f94f16305c8f7c45b2618f6173f4/BOOTSTRAP.adoc) 很切中 dartc：改变 runtime primitives、bytecode 或类型对象文件格式之前，先建立稳定的旧系统，再构建新 runtime/compiler、测试并提升新引导节点。该路径含字节码，不是 dartc 应照搬的产物方案；可借鉴的是兼容边界改变时的具体构建顺序，而不只是连续重编几次。

**OxCaml** 是应单独标识的社区/生产分支，不能把 Flambda 2 和扩展语言能力都写成上游 OCaml 的默认现状。其站点说明是 Jane Street 的生产编译器及性能相关扩展平台；[629921bf](https://github.com/oxcaml/oxcaml/tree/629921bf80b188e71bdca919f8fbbf885e7df964) 的 README 描述 Flambda 2 与 CFG backend。官方资料将布局、非装箱类型、分配控制和 `zero_alloc` 检查联系到语言/类型能力。[项目定位](https://oxcaml.org/)、[扩展文档与论文](https://oxcaml.org/documentation/)、[README](https://github.com/oxcaml/oxcaml/blob/629921bf80b188e71bdca919f8fbbf885e7df964/README.md)

**对 dartc 的取舍**：学习表示、逃逸、分配与可检查合同之间的关系；不把 OxCaml 的新增 kinds/modes 直接加入 Dart 语言。Dart 内部优化可以利用已证明的事实，不能要求用户接受另一门语言才能得到正确实现。

## TinyGo

TinyGo 的前端复用 Go 语言工具库构造高层 Go SSA，再降低到 LLVM IR；中间有接口/运行时操作 lowering、逃逸等专用变换，以及全局初始化的编译期解释。之后由 LLVM 优化并生成对象文件。[官方 pipeline](https://tinygo.org/docs/concepts/compiler-internals/pipeline/)

所读 [release 分支 bdc4a21a](https://github.com/tinygo-org/tinygo/tree/bdc4a21af007d8f059b5cefe5644b7ee7bda5b2d) 的 `loader/`、`compiler/`、`interp/`、`transform/`、`builder/`、`compileopts/` 是实际模块。`src/runtime/` 中包含 Go 的 GC/调度/集合实现，以及按目标选用的 C/汇编；存在 precise、conservative、leaking、none 等不同配置源码，不能据此认定每种目标都具备同样 GC 能力。[运行时源码](https://github.com/tinygo-org/tinygo/tree/bdc4a21af007d8f059b5cefe5644b7ee7bda5b2d/src/runtime)

这是“同一语言有不同编译器和运行时取舍”的实用案例，不是完整 Go 兼容性或 TinyGo 原生自编译链已经成立的证明。具体支持仍需查其目标和兼容性表。

**对 dartc 的取舍**：学习运行时能力按目标/需求选择，以及高层语义进入公共后端前仍需专门处理。生产上复用官方前端和 LLVM 的依赖模型不满足 dartc 当前独立、主要纯 Dart 的最终约束；独立前端与后端的工作量必须明确承担，不能因为学习 TinyGo 就忽略这项成本。

## Kotlin/Native

Kotlin/Native 展示了另一个需要区分“native 产物”和“native 自托管”的案例。源码先到含已解析 backend IR 和 metadata 的 klib，后续对闭包依赖进行 lowering、LLVM 优化与链接，runtime 也在 native 产物构建过程中加入。高层 IR 缓存与 ABI、依赖和反序列化成本有关。[编译模型](https://github.com/JetBrains/kotlin/blob/065bf70a72cc8cb586aa9f27e3f0a3b4260d5fe5/docs/native/compilation-model.md)、[后端调试和 LLVM IR 导出](https://github.com/JetBrains/kotlin/blob/065bf70a72cc8cb586aa9f27e3f0a3b4260d5fe5/kotlin-native/HACKING.md)

在 [065bf70a](https://github.com/JetBrains/kotlin/tree/065bf70a72cc8cb586aa9f27e3f0a3b4260d5fe5) 中，共用前端/IR 在 `compiler/`，native backend 在 `kotlin-native/backend.native/`，runtime 在 `kotlin-native/runtime/`；后者将 `alloc`、`gc`、`gcScheduler`、`compiler_interface`、异常和启动等分别组织。编译器的 JVM 构建/运行环境与其输出不需要 JVM 是两件事，不能把它列作已证明的纯原生 Kotlin 自托管工具链。

官方当前文档描述共享堆和并发 mark-sweep，并保留兼容配置；其实现演进说明 GC 算法是可调整的工程选择，不能从某次旧版介绍固定为另一种 GC。[内存管理](https://kotlinlang.org/docs/native-memory-manager.html)

**对 dartc 的取舍**：学习语义库与最终机器产物分阶段、runtime/compiler 接口和缓存兼容性。现在不需要照搬 klib 发布格式、Gradle 生态、Objective-C 自动桥接或多套 GC 配置；它们不是解决当前前端交接和原生引导的最小步骤。

## TCC 与 chibicc：用于识别取舍，而非性能目标

TCC 的 [0.9.27 参考手册](https://bellard.org/tcc/tcc-doc.html) 描述单遍直接生成链接后的代码、值栈和表达式级优化，以及集成 assembler/linker。该文档是历史设计证据，不用来断言今日每个 target 的维护状态。它说明很小、编译很快和独立写出产物可以成立，但不因此获得成熟全局优化能力。

chibicc 在 [90d1f7f1 README](https://github.com/rui314/chibicc/blob/90d1f7f199cc55b13c7fdb5839d1409806633fdb/README.md) 明确列出 tokenize → preprocess → 带类型 AST → assembly，并说明没有优化 pass，定位于可读的 C 编译器实现。它的自编译/可读性价值不能当成高性能优化器或当前 ARM64 后端的证据。作者的速度表述也没有被本调查当成新测量。

**对 dartc 的取舍**：学习直接、清楚的代码组织和真实编译执行验证；不要把“小编译器能自编译”作为最终架构标准。dartc 已有 SSA/MIR，应完善它们的语义与验证合同，而不是退回直接 AST 发码来追求编译时间数字。

## MLIR 的位置

MLIR 是编译基础设施，不是另一门已经自托管的高性能语言。它通过渐进 lowering 保留高层操作、类型、布局和 effects，并提供验证、分析失效、pass instrumentation 与失败复现机制。[设计理由](https://mlir.llvm.org/docs/Rationale/Rationale/)、[pass 基础设施](https://mlir.llvm.org/docs/PassManagement/)

对 dartc 最有价值的是这些问题的定义：哪一阶段可以丢弃什么信息，变换保持哪些不变量，分析何时失效，失败如何定位。它的 dialect、生成器和通用 pass 系统有服务更大生态的成本，当前没有证据证明 dartc 需要复制这些框架。块参数 SSA 与显式边实参已经是合理选择，无需为模仿 LLVM PHI 而重写。

## 厂商工具链：NVCC 与 Intel ifx

NVCC 是值得纳入高性能语言调查的 driver 案例。官方轨迹区分 CUDA device 编译、PTX/cubin/fatbinary、host C++ 编译，以及链接进 CUDA runtime；host 编译继续依赖受支持的 C++ 工具链。这里“宿主/目标分离”既有编译工具角色，也有 CPU/GPU 两种执行域，不能与自举 stage 编号混称。公开文档没有提供足以审查全部专有设备优化器的源码，本调查只确认其公开编译/链接边界。[CUDA Compiler Driver 13.4](https://docs.nvidia.com/cuda/cuda-compiler-driver-nvcc/)

Intel ifx 的官方 2026.0 文档明确以既有 Intel Fortran frontend/runtime 配合 LLVM backend；迁移指南还单独讨论选项、浮点和兼容差异。换公共后端没有取消语言前端和运行时责任。其完整专有实现、优化顺序和源码布局不在这组公开证据中，不能套用开源 Flang 的目录代替。[ifx 2026.0](https://www.intel.com/content/www/us/en/docs/fortran-compiler/developer-guide-reference/2026-0/introducing-the-intel-compiler.html)、[ifort→ifx 迁移](https://www.intel.com/content/www/us/en/developer/articles/guide/porting-guide-for-ifort-to-ifx.html)

这些是产品级异构编译和后端迁移的参照，不是将 dartc 主线扩张到 GPU、OpenMP 或厂商 SDK 的建议。先把 CPU AOT 的语义、ABI 和运行时合同做好，才有依据讨论更多执行域。

## 新社区实现：Mojo 与 V

### Mojo


**当前编译器已开源，不能继续写成只有标准库公开。** Modular 的 [2026-08-18 公告](https://www.modular.com/blog/mojo-open-source)宣布公开编译器与工具链；[26.6 发布说明](https://www.modular.com/blog/modular-26-6-open-compiler-contributions-audio-generation-and-expanded-model-support)进一步说明开始接受编译器贡献，并统一顶层 Mojo 目录。本次核对 [modular/modular@cb987e0e4f4df28d19f04dd586dc76713751cf65](https://github.com/modular/modular/tree/cb987e0e4f4df28d19f04dd586dc76713751cf65/Mojo)，实际已有 lib、include、stdlib、test、integration-test。顶层 README 的简短目录清单没有列全 compiler，不能据此反向判断其仍闭源。

其语言语义与多级 IR 不是单纯“Python 语法转 LLVM”。当前 [Compiler Walkthrough](https://github.com/modular/modular/blob/cb987e0e4f4df28d19f04dd586dc76713751cf65/Mojo/docs/compiler/MojoCompilerWalkthrough.md)描述 parser/type checking 产生源级 LIT dialect，再做语义/生命周期检查与 KGEN lowering、elaboration/monomorphization、后继优化和 LLVM lowering。具体 [KGENToLLVMPipeline.cpp](https://github.com/modular/modular/blob/cb987e0e4f4df28d19f04dd586dc76713751cf65/Mojo/lib/Compiler/ObjectCompiler/KGENToLLVMPipeline.cpp)确有 KGEN/POP、closure/control-flow lowering 和 target-specific LLVM-dialect passes，之后再走 LLVM IR/机器后端。目录 [MojoParser](https://github.com/modular/modular/tree/cb987e0e4f4df28d19f04dd586dc76713751cf65/Mojo/lib/MojoParser)、[Elaborator](https://github.com/modular/modular/tree/cb987e0e4f4df28d19f04dd586dc76713751cf65/Mojo/lib/Elaborator)、[KGENToLLVM](https://github.com/modular/modular/tree/cb987e0e4f4df28d19f04dd586dc76713751cf65/Mojo/lib/KGENToLLVM)分别有真实实现。不能从“基于 MLIR”推断语言检查由框架自动完成，也不能推断每个目标都走完全相同路线。

**没有找到“编译器已用 Mojo 自托管”的证据。** 固定 [compiler README](https://github.com/modular/modular/blob/cb987e0e4f4df28d19f04dd586dc76713751cf65/Mojo/docs/compiler/README.md)明确 lib/tools 为 C++ libraries/CLI sources，源码也确为大量 .cpp；标准库以 Mojo 编写是另一层事实。[WorkingInOSRepo.md](https://github.com/modular/modular/blob/cb987e0e4f4df28d19f04dd586dc76713751cf65/Mojo/docs/compiler/WorkingInOSRepo.md)提供 Bazel 从当前 checkout 构建 compiler/stdlib 的流程，而非 Mojo→Mojo 三代自举证明；本次未执行。还应避开 [DesignOverview.md](https://github.com/modular/modular/blob/cb987e0e4f4df28d19f04dd586dc76713751cf65/Mojo/docs/compiler/DesignOverview.md)的历史误用：文件开头明确说它写于 Mojo 被构想之前。对纯 Dart 可借鉴的是分阶段保留语义、参数化 IR 与可观察 lowering；不能照搬整套 MLIR 多 dialect 体量，也不能将公开 C++ 编译器或标准库自用等同于纯本语言独立执行基础。

### V

本次固定 [vlang/v@9e1d7f2416cb22d4cbdb8db72510febed20b1ec3](https://github.com/vlang/v/tree/9e1d7f2416cb22d4cbdb8db72510febed20b1ec3)。**默认 C backend 仍真实存在，但“V 只有 C 转译，没有自己的 IR/native 路径”已经不准确。** 当前 [driver.v](https://github.com/vlang/v/blob/9e1d7f2416cb22d4cbdb8db72510febed20b1ec3/vlib/v/driver/driver.v)默认 backend 为 c，并使用 FlatAst/type checking/transform 后的 C generation；同文件也实际接有 SSA build、可选 SSA optimize、ARM64 generator 与 write/link 路线。[ssa.v](https://github.com/vlang/v/blob/9e1d7f2416cb22d4cbdb8db72510febed20b1ec3/vlib/v/ssa/ssa.v)有类型、块、PHI、直接/间接调用等表示，[mir.v](https://github.com/vlang/v/blob/9e1d7f2416cb22d4cbdb8db72510febed20b1ec3/vlib/v/mir/mir.v)有目标 ABI/参数位置等结构；它们的存在不能证明全部 V 特性或目标均已走这条后端。另有独立 [FastC](https://github.com/vlang/v/blob/9e1d7f2416cb22d4cbdb8db72510febed20b1ec3/vlib/v/gen/fastc/fastc.v)路线，源码说明它直接处理 scanner tokens 并产生 C，不能把其特殊设计误写成所有 V 编译路径的共同结构。

V 编译器主体为 V 源码，入口与 vlib/v 分工已变化。[当前默认编译器文档](https://docs.vlang.io/the-default-compiler.html)说明顶层 v 内嵌 vlib/v 的默认 compiler，direct C builds（含 self-build）在进程内编译，CLI 留在 cmd/v；这句话不等于机器代码直接由 V emitter 生成。该页还明确 ordinary builds 可在失败后自动尝试 0.5.2 compatibility compiler，严格的 -new-compiler 路线与兼容重试必须区分。因此不能只见一次普通命令成功，就断言新默认 compiler 独立处理了该程序。此文档页面标注的更新提交并非本次固定 HEAD；源码路线另由本次 driver 核对。

自举证据来自实际 [GNUmakefile](https://github.com/vlang/v/blob/9e1d7f2416cb22d4cbdb8db72510febed20b1ec3/GNUmakefile)：先以 C compiler 构建外部 vc/v.c snapshot 成 v1，再由 v1 构建 v2、由 v2 构建最终 v；[README](https://github.com/vlang/v/blob/9e1d7f2416cb22d4cbdb8db72510febed20b1ec3/README.md)也说明 C snapshot 的兼容处理。这支持“V 源码编译器有项目提供的自举链”，不支持“默认链已经脱离 C 编译器/兼容工具、所有 native backend 已完成自举”的更强断言；本次没有执行任何一条链。对 Dart 可借鉴的是小语言自用、分层后端和明确 seed；不可照搬默认失败后隐式换旧 compiler 的验收逻辑，更不能以 C backend 的宿主成功代替目标所要求的独立 native 编译证明。

