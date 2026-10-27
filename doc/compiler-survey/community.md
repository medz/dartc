# 紧凑、高性能编译器的社区实践调查

调查日期：2026-10-27。只读研究，未构建或运行所调查项目。本报告中的“已实现”指官方文档与固定源码相互支持；不等于本次独立验证了其全部平台、性能或自举产物一致性。

## 结论

对纯 Dart、独立原生后端、可持续自演进这组目标，最有价值的组合是：**QBE 的优化投入边界，Zig 的语义与代码生成分层，Cranelift 的后端契约和正确性验证，再参考 Nim、Crystal、DMD 的自托管与运行时源码组织。** Odin 对内存责任和工程取舍很有参考价值，但其“不自托管、无捕获闭包、手动内存”的选择不能变成缩小 Dart 语言目标的理由。

没有找到一个项目同时证明“完整 Dart 类语言语义、主要运行时算法用同一语言、独立机器后端、极小代码规模、最高执行性能、极低编译成本”。不能把不同项目各自最好的数字拼成一个已经实现的方案。

研究中的三个关键纠偏：

- QBE 首页的“工业编译器 70% 性能、10% 代码”是**设计目标**，不是带版本、任务、输入、机器与原始结果的通用实测结论。
- 当前 Bun 固定源码的主要实现已为 Rust，不能继续拿早期“Bun 用 Zig”解释当前性能。稳定 --compile 路径是应用加 runtime 打包；同时，开放的 #45631 与 Oven fork 已合并的 #757 确实在实现实验性 SSA→B3 AOT。两者应分别评价，不能用打包文档否定 AOT 工作，也不能把实验性 PR 当作稳定发布能力。
- 当前 DMD 的后端文件已经是 D；“D 前端 + C++ 后端”是过时概括。Cranelift 仓库内也仍有描述旧单 IR 管线的文档，当前源码实际有 CLIF → VCode → 寄存器分配 → 机器码。

## 1. 定位与证据范围

| 项目 | 实际类别 | 实现、seed 与自托管证据 | 本次能确认和不能确认 |
| --- | --- | --- | --- |
| Zig | 系统语言、编译器与工具链 | 自托管 Zig 前端；存在独立机器后端及 LLVM 路径；固定源码有 Wasm seed → C → Zig 编译器引导 | 构建链可核实；自托管不等于所有目标摆脱 LLVM/Clang，也不等于 seed 无信任根 |
| QBE | 可复用原生代码生成后端 | C 实现，接受低层 IL，输出汇编，再由外部工具汇编链接 | 没有完整用户语言前端/标准库；“QBE 自托管”不是与 Dart 编译器相同的问题 |
| Cranelift | Rust 实现的优化后端库 | Rust/Cargo 构建；用于 Wasmtime JIT/AOT，也用于 rustc 的实验后端 | 能编译 Rust 程序不等于整个 Cranelift 构建链默认自托管；Wasm runtime 不属于后端本体 |
| Odin | 通用系统语言编译器 | 官方 FAQ 明确当前不自托管；C++ 前端接 LLVM 主后端 | 可研究编译器与运行时组织；不据此证明同语言持续自演进 |
| Nim | 自托管语言前端与转译工具链 | Nim 编写；旧编译器生成的 C 源作为 bootstrap；常用路径再交 C/C++ 编译器 | 自托管明确，但不符合 dartc 的最终独立机器后端约束 |
| Crystal | 自托管静态语言编译器 | Crystal 编写，用已有 Crystal 构建；LLVM 代码生成 | 编译器/大量库可同语言修改；默认 GC 仍依赖 Boehm，不是纯 Crystal 全运行时 |
| DMD | D 参考编译器 | 当前前端和本机后端源码为 D；已有 D 编译器 + dub 可构建 | 独立后端方向更接近目标；本次未复现 stage 一致性或跨平台执行 |
| LDC | D 前端 + LLVM 编译器 | DMD 前端复用，C++/D 构建环境和 LLVM；支持 DMD/GDC/LDC 作为 host | 是复用语义前端的实例，不是整个工具链纯 D、独立于 LLVM |
| Zerolang | 实验性通用语言与图程序数据库 | 当前 native/zero-c 用 C 构建；有 direct 与 LLVM 输出族 | 有原生编译实现；未见同语言 stage 自举链证据，README 的性能条目主要是目标 |
| Bun / JSC | JS/TS 工具链、宿主 runtime / JavaScript 引擎 | 当前 Bun 主体 Rust，JSC 为 C++ 引擎；JSC 解释器和多层 JIT | 可借鉴运行时、分层编译和验证；不是相同类别的自托管静态语言编译器 |
| oxc | JS/TS 解析、绑定、转换、lint、格式化、压缩组件集 | Rust 实现 | “Compiler”名称不代表原生机器后端，也不代表完整 TypeScript 类型检查器或自托管 |

固定源码基线：

| 项目 | 本次固定 ref |
| --- | --- |
| Zig | 0.15.2 / 3eac10ac2933d96a71a90a1424659238169d5f28；另核对官方 0.16.0 release notes |
| Odin | 1bc18e5bf4b200a606ce263762b5a789d0b52dd2 |
| Cranelift / Wasmtime | ec63b69f3da9783db784eef6ba67635385926a2a |
| Nim | 15dd344680bf9bd6f7388cb4056d81b5b700c15f |
| Crystal | bc32e48d5b402726d9b39391cc40e729850db0b2 |
| DMD | b8c2648d312a745ad1340fd674e1fc3d767dd39e |
| LDC | df98a635a7ba665d8907c7cfd7cbd0f2f1aa7810 |
| Zerolang | 7e1a64d27cc37671df31c6370890bce86f5135e1 |
| Bun | 9b8347a24e2de025d1bcca1f2e2a6b1518af64cb |
| WebKit | 88886f089df5fcbd66c670c822f59e62149afac8 |
| Oven 的 AOT 分支 | Bun PR #45631 head 72ab4f530b77b65e68b2d34aa1a052886ace78db；Oven WebKit PR #757 merge 3d5b1926eb2eb87da678b045e04fdf1d4f390771 |
| oxc | 36e5ddb0f2463a175c04b990451a396f0028d86c |

QBE 本次只能确认官方在线 IL、ABI 和项目说明，未成功取得官方 Git/release 的可固定源码快照；不把非官方镜像当成已核实的上游源码。Zig 官方下载页在检索时列出 0.17.0 为 stable，但 0.17.0 release notes/Codeberg 源码入口本次未成功读取，所以下文不会把 0.16 的独立 ARM64 后端状态冒称为 0.17 当前状态。[Zig 下载页](https://ziglang.org/download/)

## 2. Zig：最值得研究的是分层、自举与成本分账

### 语义、IR、优化与后端

固定源码的链条是 AST → AstGen → 未类型化 ZIR → Sema/类型与编译期求值 → 每函数 AIR → 具体后端。ZIR 注释明确列出从 AST 脱离的边界，错误诊断仍可回溯源信息；AIR 则是语义分析产生、代码生成消费的结构。它不是靠源码名字来决定后端含义。[ZIR 定义](https://github.com/ziglang/zig/blob/3eac10ac2933d96a71a90a1424659238169d5f28/lib/std/zig/Zir.zig)、[AIR 定义](https://github.com/ziglang/zig/blob/3eac10ac2933d96a71a90a1424659238169d5f28/src/Air.zig)

AIR 分别表达普通、受检、wrapping 等算术语义；不能因为目标机器存在某条指令就混掉语言行为。类型/常量由 InternPool 拥有，依赖跟踪也有明确数据拥有者，增量编译不是只加一个文件时间戳缓存。[InternPool](https://github.com/ziglang/zig/blob/3eac10ac2933d96a71a90a1424659238169d5f28/src/InternPool.zig)

LLVM 路径与独立后端共享前端产物，但各自承担指令生成、ABI 和链接成本。源码中 LLVM 适配器仍直接依赖目标 ABI 模块；并非把 LLVM 接上后语言 ABI 自动正确。[LLVM 适配器](https://github.com/ziglang/zig/blob/3eac10ac2933d96a71a90a1424659238169d5f28/src/codegen/llvm.zig)、[链接拥有者](https://github.com/ziglang/zig/blob/3eac10ac2933d96a71a90a1424659238169d5f28/src/link.zig)

### 自托管、seed 和运行时

bootstrap.c 展示实际链：用 C 编译 wasm2c，把固定 zig1.wasm 转为 C，构建 zig1，再由它生成新版编译器 C 源。它是明确、可恢复的种子链；不是“已经自托管，所以再也没有外部 compiler seed”。[bootstrap.c](https://github.com/ziglang/zig/blob/3eac10ac2933d96a71a90a1424659238169d5f28/bootstrap.c)

Zig 的手动内存约定是需要分配的函数显式接收 allocator；语言不代替程序管理对象生命周期。其 compiler-rt、启动代码、libc 支持仍有源码，因此官方“无 runtime”措辞不能解释成“产物无需任何启动/辅助函数”。Dart 不能照搬无 GC 和手动释放的语言合同。[内存与所有权](https://ziglang.org/documentation/0.15.2/#Memory)

### 文件责任与工程代价

- lib/std/zig：词法/AST/ZIR 等共享语言结构；src/Sema.zig、src/Air.zig、src/InternPool.zig：编译器语义、类型化产物及常量/类型身份。
- src/codegen、src/arch、src/link：代码生成、目标能力、文件格式/链接责任分开；不是按一串抽象接口预建空目录。
- ZIR/AIR 用紧凑 tag/data 数组和额外载荷，减少遍历冷字段。可借鉴布局意图，不能假设 Dart 中照抄位打包就会更快。
- 多目标、多后端、增量链接、C/C++ 互操作是实在的维护负担。Zig 自身并非一个“几千行简单编译器”的样板。

### 性能和测试证据

0.15.1 官方称独立 x86_64 Debug 后端相较 LLVM 常见编译约快 5 倍；同页给出一次编译 Zig 自身 13.8s → 10.0s 的线程化数据点。这是特定版本、模式与工作负载，不能推导 ARM64 Release 或 Dart 程序也会获得同倍数收益。[0.15.1 后端说明](https://ziglang.org/download/0.15.1/release-notes.html#x86-backend)

0.16 官方仍区分独立 x86 后端“编译快、机器码质量较弱”和独立 aarch64 后端当时尚未通过行为测试。该页同时披露 LLVM loop vectorization 因错编译被禁用，说明项目会为正确性付出优化代价；不能把后端通过部分测试写成全语言验收。[0.16 编译器与已知限制](https://ziglang.org/download/0.16.0/release-notes.html#compiler)

源码 CI 有自举、行为测试、非本机执行工具和资源限制，release notes 也记录 AST 生成 fuzz 与崩溃输入保存。**值得采用的是每后端单独报告能力和行为证据，不是复制其庞大的 CI 矩阵。**[固定 CI](https://github.com/ziglang/zig/blob/3eac10ac2933d96a71a90a1424659238169d5f28/ci/x86_64-linux-debug.sh)

## 3. QBE：适合作为优化预算和后端边界参照

QBE 把自己的任务限定为低层 IL 到汇编。前端仍负责语言绑定、类型关系、异常语义、托管对象布局和标准库；后端实现 C ABI、指令选择、spill 与寄存器分配。这种边界小于完整 Dart 编译器，但非常接近“什么东西值得放进一个小型本机后端”。[官方项目说明](https://c9x.me/compile/)

### 可确认的设计

- IL 是函数/基本块与三地址指令，使用 SSA 与 phi；首块禁止有前驱，跳转/返回和 phi 有明确结构合同。
- w/l/s/d 表示机器值，不携带完整高级语言类型；地址采用整数。聚合布局和 padding 有一部分仍由前端承担。
- 文本 IL 经过 QBE 输出汇编，再经外部 assembler/linker。它不是自己拥有完整 ELF/Mach-O 链接器和 Dart runtime。[IL 手册](https://c9x.me/compile/doc/il.html)

官方列出的高投入产出优化包括 SCCP、copy/dead instruction 消除、小栈槽 registerization、循环信息驱动 spill，以及带 hint 的线性分配。它强调在有限规模内拿到主要收益，不追逐工业优化器的所有尾部收益。[优化范围与目标](https://c9x.me/compile/)

ABI 文档把分类、寄存器/栈传参、聚合拆分/回退、返回值和栈对齐分开描述，并明确该文档讨论的 amd64 子集。首页的“完整 C ABI”宣传应与每目标实际合同、实现和调用测试一起看；不能拿 SysV amd64 一页替 ARM64/macOS ABI 验收。[amd64 ABI](https://c9x.me/compile/doc/abi.html)

### 对 Dart 有用和不适用之处

**有用：**有限 pass 集；输入/输出结构稳定；ABI lowering 与语言语义解耦；分别衡量 spill、phi copy、地址模式与常量传播的实际收益。

**不能照搬：**把 rRef/rTagged 都变成普通 l 后丢掉 root-map 信息；把 Dart 必须抛错的运算变成目标相关 hlt；以更窄 IL 支持范围反过来删减 Dart 语言目标。QBE 没有替前端完成这些工作。

**证据空白：**本次未取得官方版本源码和测试脚本，不能精确断言当前每个 pass 的顺序、文件拥有者、回归覆盖或代码行数。首页的“70%/10%”和旧 Core 2 Duo 上的构建秒数都不足以建立现代跨项目性能排名。这里保留空白，不用 GitHub 镜像目录或传闻补齐。

## 4. Cranelift：比“快后端”更有价值的是可验证的管线

### 现有源码管线

当前固定源码的 optimize 先处理 CFG/dominator、不可达块、常量 phi、alias，再按优化级别进入 egraph pass。后端 MachInst 文档明确：CLIF → ISA VCode → regalloc2 输出 → MachBuffer 编码/分支与重定位修补。[实际优化入口](https://github.com/bytecodealliance/wasmtime/blob/ec63b69f3da9783db784eef6ba67635385926a2a/cranelift/codegen/src/context.rs)、[实际机器管线](https://github.com/bytecodealliance/wasmtime/blob/ec63b69f3da9783db784eef6ba67635385926a2a/cranelift/codegen/src/machinst/mod.rs)

这纠正了仓库旧 compare-llvm.md 中“单一 IR 一路到编码、没有中层优化”的描述；后者不能作为当前架构事实。CLIF 使用块参数表示 phi，函数是独立编译单元；module、JIT、object 输出分别有 crate 拥有者。[文档入口和各 crate](https://github.com/bytecodealliance/wasmtime/blob/ec63b69f3da9783db784eef6ba67635385926a2a/cranelift/docs/index.md)

regalloc2 把 use/def、固定寄存器、reuse-input、early/late 等约束显式表达，分配器不需要理解每条高级语言指令。其符号检查器验证分配前后的数据流连接，区别于“分配结束没有崩溃”。这是适合借鉴的局部合同；算法本身并不简单，不应因其是库就认为移植便宜。[作者设计与迁移说明](https://www.cfallin.org/blog/2022/06/09/cranelift-regalloc2/)

### 正确性、性能与成本

CLIF verifier 负责结构、类型、SSA 等约束，但不能证明优化前后语义等价，也不能证明生产者错误地标注 trusted/notrap 地址是正确的。后者仍属于 embedder 的义务。[verifier 拥有者](https://github.com/bytecodealliance/wasmtime/blob/ec63b69f3da9783db784eef6ba67635385926a2a/cranelift/codegen/src/verifier/mod.rs)

Cranelift 的验证组合包含 IR filetests、执行比较、IR interpreter、寄存器分配 translation validation、语义保持的 chaos 决策及 fuzz；不是用一个 verifier 取代所有测试。官方也要求错误报告提供可自动缩减的最小输入。[测试层次](https://github.com/bytecodealliance/wasmtime/blob/ec63b69f3da9783db784eef6ba67635385926a2a/cranelift/docs/testing.md)、[2023 chaos/fuzz 实践](https://bytecodealliance.org/articles/wasmtime-and-cranelift-in-2023)、[fuzz 报告合同](https://docs.wasmtime.dev/contributing-fuzzing.html)

官网引用的“代码生成约快一个数量级，执行比 LLVM 系统约慢 14%”来自历史论文及其中的 Wasm 工作负载；它不是本次测得，也不是当前所有语言/优化级别上的保证。2022 regalloc2 迁移数据同样是历史工程证据，适合说明分配器可能占主要成本，不宜直接预计 dartc 百分比。[官网性能说明](https://cranelift.dev/)、[所引论文 v3](https://arxiv.org/abs/2011.13127v3)

还应避免把验证宣传当绝对正确性：2026 官方安全公告仍披露 aarch64 Cranelift 等实际错编译问题，并要求架构层面的 fuzz 覆盖。验证覆盖有前提，不等于整个编译器已被证明无 bug。[官方安全公告](https://bytecodealliance.org/articles/wasmtime-security-advisories)

### 所有权与适用性

- codegen 拥有 CLIF、优化、verifier、ISA 与 MachInst；frontend 提供 IR 构造工具；module/object/jit 负责独立的装配责任。
- 后端库不自动带入 Wasmtime 的 Wasm heap、scheduler、GC 或语言标准库。不能用 Wasmtime 整包成本来代表一个 Cranelift 函数后端，也不能把后端速度代表整个应用启动。
- 对纯 Dart 目标，**研究其约束与验证方式比直接 FFI 接入 Rust 更符合方向**。目前没有证据要求 dartc 立即引入 egraph、ISLE DSL 或 regalloc2 规模的系统；小而明确的 pass 与 def/use/ABI/root-map 合同应先成立。

## 5. Odin：直接的数据结构与诚实的工具链取舍

### 编译器、内存、文件责任

当前固定 src 目录由 C++ tokenizer/parser、checker/check_expr/check_type/check_stmt、LLVM lowering、ABI、优化和 linker 文件构成。checker 保存类型/实体，LLVM 后端直接消费检查结果；本次未见一个必须先经过的独立通用高级 SSA 层，不把 LLVM IR 之前的全部结构强称 SSA。[src 文件](https://github.com/odin-lang/Odin/tree/1bc18e5bf4b200a606ce263762b5a789d0b52dd2/src)、[checker](https://github.com/odin-lang/Odin/blob/1bc18e5bf4b200a606ce263762b5a789d0b52dd2/src/checker.cpp)

compiler 自身的 common_memory.cpp 有 permanent/temporary arena 与线程所属关系；语言程序的 allocator/context 机制是另一层。Odin context 在调用约定中隐式传递，分配行为可以由调用方改变；这不是 Dart 的现成语义。[compiler arena](https://github.com/odin-lang/Odin/blob/1bc18e5bf4b200a606ce263762b5a789d0b52dd2/src/common_memory.cpp)、[语言 context 与内存合同](https://odin-lang.org/docs/overview/)

文件拆分不等于模块隔离：main.cpp 直接 include common.cpp 等实现，llvm_backend.cpp 也 include 多个后端 .cpp。可以学习职责命名，不宜把这种 amalgamation 当成 Dart 必须复制的依赖结构。[main](https://github.com/odin-lang/Odin/blob/1bc18e5bf4b200a606ce263762b5a789d0b52dd2/src/main.cpp)、[后端组合](https://github.com/odin-lang/Odin/blob/1bc18e5bf4b200a606ce263762b5a789d0b52dd2/src/llvm_backend.cpp)

### 优化语义与测试

源码保留了警告 C 风格 poison/nsw/nuw 可能破坏 Odin wrapping 语义的旧说明；但当前 pass 表实际已使用 instcombine 等。不能照抄注释中的历史“禁用 pass 列表”当成当前事实，真正的安全边界是生成的 IR 标志、当前 pass 配置与回归行为。[语义警告](https://github.com/odin-lang/Odin/blob/1bc18e5bf4b200a606ce263762b5a789d0b52dd2/src/llvm_backend_opt.cpp)、[实际版本化 pass 表](https://github.com/odin-lang/Odin/blob/1bc18e5bf4b200a606ce263762b5a789d0b52dd2/src/llvm_backend_passes.cpp)

官方提供分阶段 timings、更多 timings、外部工具命令显示与 JSON 导出；tests 划分 ABI、core、issues 和 benchmark。它们证明有测量/回归入口，**本次没有据此得到可横比的 Odin 编译速度或执行性能数字**。[Compiler Flags](https://github.com/odin-lang/Odin/wiki/Compiler-Flags)、[测试拥有者](https://github.com/odin-lang/Odin/tree/1bc18e5bf4b200a606ce263762b5a789d0b52dd2/tests)

官方明确主后端 LLVM、平台 ABI 仍需 Odin 自己实现、当前不自托管、只有 noncapturing procedure values。这些是设计取舍，不能通过引用 Odin 来合理化 Dart 永久缺失 closures、GC 或自托管。[官方 FAQ](https://odin-lang.org/docs/faq/)

## 6. 其他语言的证据化对照

| 项目 | 可确认的组织与运行时 | 对 dartc 的借鉴 | 不能据此宣称 |
| --- | --- | --- | --- |
| Nim | compiler 下语义/变换/C 生成/VM 有实际文件；lib/system 拥有运行时支持。Nim 源经旧 C seed 引导，常用 C/C++ 后端 | 编译器内建语义与 runtime compilerproc 的身份分开；持续保留可恢复 seed；旧/新内存模型文档分开 | “自托管”不代表没有 C 工具链；生成 C 的总代价不能只计 Nim 前端 |
| Crystal | src/compiler/crystal 中 syntax/semantic/codegen，库与 runtime 多为 Crystal；已有 Crystal 构建新版，LLVM codegen，src/gc/boehm.cr 对接外部 GC | 类型检查、代码生成、运行时函数保持普通语言源码；语言演进与编译自身自然形成真实任务 | GC 和全部后端都已经用 Crystal 独立实现；Ruby 风格语法等同 Ruby 动态语义 |
| DMD | frontend、本机 backend、common、druntime 有明确所有者；backend 中 IR/优化/编码/格式文件已为 D | 同语言拥有优化器与机器后端是可行方向；前后端明确接口便于独立替换 | “当前后端仍 C++”；单个快速 Debug 编译器就必然有最佳 Release 代码 |
| LDC | 复用 DMD 前端，LLVM backend；C++/D/LLVM 构建依赖明确 | 同一语言语义拥有者服务不同后端，避免各后端复制 binder/typecheck | 工具链已纯 D、无 LLVM；LDC 的优化质量能免费获得而没有构建/升级成本 |

[Nim 固定 README/bootstrap](https://github.com/nim-lang/Nim/blob/15dd344680bf9bd6f7388cb4056d81b5b700c15f/readme.md)、[Nim 编译器内部文档](https://nim-lang.github.io/Nim/intern.html)、[Crystal 编译入口](https://github.com/crystal-lang/crystal/blob/bc32e48d5b402726d9b39391cc40e729850db0b2/src/compiler/crystal/compiler.cr)、[Crystal 构建 seed](https://github.com/crystal-lang/crystal/blob/bc32e48d5b402726d9b39391cc40e729850db0b2/Makefile)、[DMD 文件责任](https://github.com/dlang/dmd/blob/b8c2648d312a745ad1340fd674e1fc3d767dd39e/compiler/src/dmd/README.md)、[LDC 构建依赖](https://github.com/ldc-developers/ldc/blob/df98a635a7ba665d8907c7cfd7cbd0f2f1aa7810/README.md)

Nim ORC 的核心是引用计数和 cycle collection，编译器会优化 RC 操作；它与 Dart 当前 bump、未来 tracing GC 的根枚举合同不同。Crystal 当前源码的默认 GC 适配仍是 Boehm；D 则把 collector 和非 GC 代码路径作为显式语言/运行时能力。可以研究边界和可替换性，不能因为都叫 GC 就机械移植对象追踪方式。[Nim 内存模型](https://nim-lang.github.io/Nim/mm.html)、[Crystal Boehm 适配](https://github.com/crystal-lang/crystal/blob/bc32e48d5b402726d9b39391cc40e729850db0b2/src/gc/boehm.cr)、[D 内存合同](https://dlang.org/spec/garbage.html)

### Nim：可恢复自举与高级语言运行时的完整例子

经典 C 后端路径由 lexer/parser 建 AST，sem 与 semexprs/semtypes 等完成名称、类型、泛型/宏语义，transf、closure/destructor 相关 lowering 处理高级结构，再由 cgen 与 ccgexprs/ccgstmts 等发 C，extccomp 调外部编译器。pipeline 拥有实际选择：C、JS、NIF、仅语义、VM 等路径不应被写成全部经过同一固定 SSA。本次重点核对 C 路径，不把源码中出现的 NIF 新路径称为已替代全部传统后端。[实际 pipeline](https://github.com/nim-lang/Nim/blob/15dd344680bf9bd6f7388cb4056d81b5b700c15f/compiler/pipelines.nim)、[compiler 目录](https://github.com/nim-lang/Nim/tree/15dd344680bf9bd6f7388cb4056d81b5b700c15f/compiler)

bootstrap 有明确产物：旧 Nim 生成的 csources_v3 先由 C compiler 构成种子，再经 koch/build_all 构建新版；testament 与 tests 拥有编译/执行回归。运行时主要在 lib/system 等 Nim 源中，系统/外部库包装另有层次；ORC/ARC 的 ownership 与 RC lowering 是编译器和运行时共同的合同，不能说只是换一个 malloc。[实际 seed 与目录说明](https://github.com/nim-lang/Nim/blob/15dd344680bf9bd6f7388cb4056d81b5b700c15f/readme.md)、[运行时与 compilerproc 的分工](https://nim-lang.github.io/Nim/intern.html)

对 dartc 最有用的是同语言拥有运行时、可再生 bootstrap 输入、编译期 VM 与本机执行职责分开，以及编译器识别的符号身份和普通 runtime helper 区分。不可照搬的是把 C ABI、C optimizer、C 编译器耗时藏到总任务之外；Nim 的转译路线也不能替代 dartc 独立机器生成目标。

### Crystal：推断语义、编译器自身与外部 GC 的边界清楚

Crystal 编译入口先 parse/normalize，semantic 再区分 top-level 声明、类型声明、实例/类变量 initializer、whole-program main/body 推断与 cleanup，最后 codegen 通过 LLVM builder 生成 IR 和本机代码。syntax、semantic、codegen/abi 与 compiler driver 分属实际目录；不是将 Ruby AST 直接交给 LLVM，也不是以解释器作为正常编译产物。[semantic 拥有者](https://github.com/crystal-lang/crystal/blob/bc32e48d5b402726d9b39391cc40e729850db0b2/src/compiler/crystal/semantic.cr)、[LLVM 生成入口](https://github.com/crystal-lang/crystal/blob/bc32e48d5b402726d9b39391cc40e729850db0b2/src/compiler/crystal/codegen/codegen.cr)

Makefile 的 CRYSTAL 变量明确指已有编译器，构建与 compiler/std specs 各有入口。编译器和库可用 Crystal 持续开发，但 src/gc/boehm.cr 调用外部 GC_malloc/GC_gcollect，fiber 等运行时也需与其根扫描协作。因此这是“高级语言自托管 + LLVM + 外部 collector”的真实组合，不能当成机器后端与 GC 算法均纯 Crystal。[Makefile](https://github.com/crystal-lang/crystal/blob/bc32e48d5b402726d9b39391cc40e729850db0b2/Makefile)、[Boehm 接口](https://github.com/crystal-lang/crystal/blob/bc32e48d5b402726d9b39391cc40e729850db0b2/src/gc/boehm.cr)

可借鉴的是声明收集/initializer/body 推断各有边界、诊断与实际代码生成消费同一语义结果、用编译器自身持续检验语言能力。其全程序推断、宏与 LLVM 编译成本不能免费移植；Dart 已有独立的静态类型、动态边界和求值顺序，不能为了模仿 Ruby 风格推断而改合同。

### DMD / LDC：同一语义前端、两个真实后端成本模型

DMD 将解析后的语义分为符号/类型、初始化表达式、函数体等阶段；CTFE 有独立求值拥有者，随后 glue/e2ir、s2ir、toctype 等把完成语义检查的 AST 转为 backend 表达式树、控制流和静态数据，再做优化、分配和对象文件生成。当前 .d 文件包括这些本机后端算法，不只是外层 driver 被改成 D。[阶段与 glue 文件职责](https://github.com/dlang/dmd/blob/b8c2648d312a745ad1340fd674e1fc3d767dd39e/compiler/src/dmd/README.md)、[后端文件](https://github.com/dlang/dmd/tree/b8c2648d312a745ad1340fd674e1fc3d767dd39e/compiler/src/dmd/backend)

LDC 复用 DMD 的语言前端，gen/toir.cpp 等 C++ 代码把已检查的语义结构接到 LLVM，gen/abi、runtime、classes、arrays 等仍有语言专有 lowering；LLVM 不是消除这些责任的黑盒。LDC 构建要求已有 D/C++ 工具链与 LLVM，DMD 则可由已有 D compiler 构建自身；两者和 druntime/标准库的测试、版本及 ABI 要保持配套。[LDC 实际 toir 拥有者](https://github.com/ldc-developers/ldc/blob/df98a635a7ba665d8907c7cfd7cbd0f2f1aa7810/gen/toir.cpp)、[LDC 构建合同](https://github.com/ldc-developers/ldc/blob/df98a635a7ba665d8907c7cfd7cbd0f2f1aa7810/README.md)、[DMD 自身构建与 druntime](https://github.com/dlang/dmd/blob/b8c2648d312a745ad1340fd674e1fc3d767dd39e/README.md)

对 dartc，最实际的借鉴是保持语义拥有者唯一、把高级语言类型和后端类型映射分开，以及运行时源码随编译器一起演进。D 的 GC/非 GC 选择、BetterC 或现有系统 ABI 不等于 Dart 的精确根与异常合同；不能把 LDC 的 LLVM 产物质量、DMD 的编译延迟和各自最小 runtime 规模拼成一种不存在的统一结果。

以上语言均存在官方构建/测试入口，但本次没有找到并完整核实同一真实任务、同硬件、同模式下的跨语言性能原始结果。因此只确认能力、工具链与测试方式，不写“它们都与 C 一样快”。

## 7. Zerolang、Bun/JSC、oxc 应怎样分类使用

### Zerolang

当前 README 把程序数据库和 checked graph edits 作为核心；.0 文本是图的 projection。native/zero-c 是真实 C 编译器，不是仅有语言介绍。源码有 type_core/call_resolve/checker、program_graph_lower、IR/MIR 验证、direct 指令/格式输出、LLVM 文本输出及 C runtime 拥有者。[固定 README](https://github.com/vercel-labs/zerolang/blob/7e1a64d27cc37671df31c6370890bce86f5135e1/README.md)、[实际源码](https://github.com/vercel-labs/zerolang/tree/7e1a64d27cc37671df31c6370890bce86f5135e1/native/zero-c/src)

默认 direct 与显式 LLVM backend 在一个小拥有者中选择；构建直接调用 C compiler。conformance、MIR verifier、native execution、graph performance 与 budgets 有脚本入口，但这不足以证明 README 的全部性能目标已经达到，更没有同语言自举链证据。[backend 选择](https://github.com/vercel-labs/zerolang/blob/7e1a64d27cc37671df31c6370890bce86f5135e1/native/zero-c/src/backend_family.c)、[Makefile](https://github.com/vercel-labs/zerolang/blob/7e1a64d27cc37671df31c6370890bce86f5135e1/native/zero-c/Makefile)、[测试/测量入口](https://github.com/vercel-labs/zerolang/blob/7e1a64d27cc37671df31c6370890bce86f5135e1/package.json)

适合借鉴的是：稳定语义身份、输入变更前校验、可读 IR/诊断、native/data/reach 的明确责任。**不建议把图数据库、agent patch 协议或能力系统整套搬入 Dart 编译器**；Dart 源码仍应是标准语言输入，源码 AST/符号身份不需要一个新 authoring 体系。

### Bun 与 JavaScriptCore

固定 Bun README 已明确主体为 Rust，src 下是 Rust runtime/transpiler/JSC 绑定等真实模块。JSC 仍是所使用的 JavaScript 引擎，不是 Bun 重新自托管实现的 JS 机器后端。[当前 Bun README](https://github.com/oven-sh/bun/blob/9b8347a24e2de025d1bcca1f2e2a6b1518af64cb/README.md)、[JSC 接口模块](https://github.com/oven-sh/bun/tree/9b8347a24e2de025d1bcca1f2e2a6b1518af64cb/src/jsc)

Bun --compile 的文档明确将源依赖和 Bun runtime 一起打包进 executable。单文件分发、启动速度、无需外装 Bun 是有用产品能力，但它们与“无 VM、无官方编译器包装的 Dart AOT”不是同一个验收条件。本次不据此断言实验分支不存在其他 AOT 工作。[固定 executables 文档](https://github.com/oven-sh/bun/blob/9b8347a24e2de025d1bcca1f2e2a6b1518af64cb/docs/bundler/executables.mdx)

JSC 的核心经验是按执行热度分层：解释/基线负责启动，DFG 做高级动态语义与检查优化，FTL 经 B3/Air 做更低层优化和机器生成。2016 替换 LLVM 的官方解释强调特定动态语言需求与编译开销，不是“LLVM 普遍不好”。当前 B3::Procedure 与 Air::Code 有明确拥有关系。[官方 B3 设计](https://webkit.org/blog/5852/introducing-the-b3-jit-compiler/)、[speculation 机制](https://webkit.org/blog/10308/speculation-in-javascriptcore/)、[固定 B3::Procedure](https://github.com/WebKit/WebKit/blob/88886f089df5fcbd66c670c822f59e62149afac8/Source/JavaScriptCore/b3/B3Procedure.h)

Dart AOT 可借鉴检查与低层运算的责任分离、CFG/SSA 验证、heap 生命周期审计和真实工作负载测试；目前没有理由为复制 JSC 而引入 interpreter、多层 JIT、OSR/deoptimization、浏览器 GC 与全部宿主 API。Bun 的 HTTP/安装器数字也不能替代编译器或纯计算性能。

### Bun #45631 / Oven WebKit #757：真实 AOT 工作，尚非稳定主线合同

**查询时的状态不能混写：**[Bun #45631](https://github.com/oven-sh/bun/pull/45631) 为 open、未合并，head 固定 72ab4f530b77b65e68b2d34aa1a052886ace78db；[oven-sh/WebKit #757](https://github.com/oven-sh/WebKit/pull/757) 已于 2026-10-25 合并，merge 为 3d5b1926eb2eb87da678b045e04fdf1d4f390771。后者是 **Oven fork**，不能写成上游 WebKit 已发布此能力。两 PR 都明确 experimental，engine 由 ENABLE(AOT) 隔离，useAOT 默认 false。本次没有构建或独立执行它们。

它确实提出构建时机器码生成，不能只拿稳定 --compile 的打包说明来否定：Bun 端解析模块与 TS 类型、lower 到 SSA、链接全程序并序列化；engine 做 value-flow、优化、布局/representation，再经 B3 生成 machine-code + readonly-data image，随 executable 分发。此处声明类型是待证明/受检的预测，失配走 generic 版本，而不是制造新的 JS 类型异常。该合同与 Dart 的受检赋值/cast 不同。[固定阶段源码](https://github.com/oven-sh/WebKit/blob/3d5b1926eb2eb87da678b045e04fdf1d4f390771/Source/JavaScriptCore/aot/pipeline/AOTPipelineStages.cpp)

PR 的“无 JIT”也不等于“无语言 runtime”：产物仍携带 JSC 对象、GC、宿主 API 和运行时文本所用 interpreter；eval/new Function 的文本继续解释执行。提案还有冻结部分 builtins、可达模块限制、构建成本和目标平台缺口。不能把“把 TypeScript 编译器编成 native 并运行”说成“Bun/JSC 本身已经用 TypeScript 自托管”。

性能披露较有参考价值，但只能当 **PR 作者报告**：同一 TS 6.0.3 编译器检查固定 Effect 源码，AOT 4.25s、普通 Bun 14.00s，作者给硬件、pin、重复次数与复现命令；同文也披露 warm Koa 34,194 vs JIT 44,362 req/s，及大量 idiom 退化。冷启动、warm 吞吐、CPU、RSS、产物体积和构建成本分开，是可取的方法，不能只摘“3.3x”作总性能结论。[测量任务、原始表与限制](https://github.com/oven-sh/bun/pull/45631)

验证有三层，应分别理解：

| 机制 | 固定源码可确认的内容 | 不能证明的事 |
| --- | --- | --- |
| IR verifier 与 mutation log | AOTVerifierTests 从合法 fixture 复制 IR，故意破坏并要求明确诊断；PassRunner 在校验配置下检查改动是否有 log，以及 Changed pass 后 values 是否有合法 block 列表归属 | 这些结构检查不等于优化前后语义相同，存在选项/阶段前提 |
| runtime facts validator | tests/validation 明确为各事实 producer 放置故意为假的 fact，验证产物会拒绝；对检查器本身有反向验收 | 没有运行 validator 的产物不因此自动获得同样证据，测试集合也不是完整证明 |
| execution differential / generator / 故障注入 | 正常、AOT、擦类型路径比较；历史 commit 有具体被杀死的错误场景 | 一次杀掉 mutant 不代表完整 mutation score，更不代表所有 future regressions 都能发现 |

[Verifier 坏 IR 自测](https://github.com/oven-sh/WebKit/blob/3d5b1926eb2eb87da678b045e04fdf1d4f390771/Source/JavaScriptCore/aot/tests/AOTVerifierTests.cpp)、[engine 测试责任](https://github.com/oven-sh/WebKit/blob/3d5b1926eb2eb87da678b045e04fdf1d4f390771/Source/JavaScriptCore/aot/tests/README.md)、[Bun 三路径/variants/测试分配](https://github.com/oven-sh/bun/blob/72ab4f530b77b65e68b2d34aa1a052886ace78db/test/aot/README.md)

三个关键 commit 的完整 primary ref 已核对，作用不同：

- [b0da97c350fe9c633637ef8ec4dc3ade3c2dacc6](https://github.com/oven-sh/WebKit/commit/b0da97c350fe9c633637ef8ec4dc3ade3c2dacc6)：删除整数乘法 -0 检查后旧测试仍全过，于是增加循环中的 int32 边界、数组/参数输入以及两种 stub 模式。它是一次具体 fault-seeding 改善测试强度的证据。Dart 的整数/浮点合同不同，不能照搬 JS 期待值。
- [65eca5749140b8cd36d7548d9ea3e123d501cc49](https://github.com/oven-sh/WebKit/commit/65eca5749140b8cd36d7548d9ea3e123d501cc49)：除 ARM64/ASAN/fuzz 修复，加入 reachable block 中 value 唯一列出、每个 use 有列表拥有者的检查，并在指定 pass 校验模式接入；另有 shadow checks。这个检查不是 dominator/type/effect 全证明，也不能从提交标题推导全部覆盖。
- [d5e77602462033cd0ac521e3ca45c494d4e4cb6a](https://github.com/oven-sh/WebKit/commit/d5e77602462033cd0ac521e3ca45c494d4e4cb6a)：加入 scopes/closures、objects/shapes/aliases 两类 generator 以及 compare-execution-counts。作者报告某个错编译虽然输出一样却少做工作，表面快 12%；因此“同 stdout”是必要但可能不足的 oracle。操作计数本身也有选择偏差，优化有权减少合法操作，不能无条件要求所有计数相等。

早期 Tools/Scripts/aot/README 的 shell 流程与合并版“IR 来自 Bun front end”的入口已有演变；只能在各自固定 ref 下阅读，不能把旧命令与当前 schema 混装。[历史工具说明及已知坏输入验收](https://github.com/oven-sh/WebKit/blob/d5e77602462033cd0ac521e3ca45c494d4e4cb6a/Tools/Scripts/aot/README.md)

对 dartc 的直接启发是低成本、阶段明确的结构不变量和**检查器本身能失败的真实证据**，以及保留同程序差分/故障注入/不可变复现输入。当前 dartc 已有 SSA/MIR，不应据此重建一套 IR 或搬入整个 AOT pipeline、JS 类型预测、shadow runtime 和生产测试选项。

### oxc

oxc 的真实范围是 JS/TS tooling：parser、semantic binding、transformer、resolver、minifier、linter、formatter；输出主要仍是 JS/TS 工具产物，并不包含本机寄存器分配和机器码后端。[固定 README](https://github.com/oxc-project/oxc/blob/36e5ddb0f2463a175c04b990451a396f0028d86c/README.md)

其 AST bump allocator 与 scope/symbol/reference ID 是可研究的数据布局；semantic crate 有可选 CFG、binder、scoping 等拥有者。但 Rust arena 的 lifetime/unsafe 合同不能直接当成 Dart 托管对象的安全释放方式，TypeScript 解析或符号绑定也不能当成完整类型检查。[allocator](https://github.com/oxc-project/oxc/blob/36e5ddb0f2463a175c04b990451a396f0028d86c/crates/oxc_allocator/src/lib.rs)、[semantic](https://github.com/oxc-project/oxc/blob/36e5ddb0f2463a175c04b990451a396f0028d86c/crates/oxc_semantic/src/lib.rs)

官方 benchmark 页面明确指出 Biome 产生 CST，不能与只产生 AST 的 parser 完全等价比较。其 parser/linter/transformer 倍数只能用于对应任务、版本、输出工作量和线程数；不能扩展成“oxc 编译原生程序快几倍”。[官方 benchmark 与限制](https://oxc.rs/docs/guide/benchmarks)

## 8. 证据空白和不作的结论

- 未构建以上项目，未独立重跑其 benchmark、自举或平台矩阵；不发布跨项目速度排名。
- QBE 官方源码端点访问失败，未固定其当前源码或计数；在线手册仍能支持 IL/ABI 边界分析。
- Zig 0.17 当前后端细节未成功核对，明确使用 0.15.2 固定源码与 0.16 官方事实，不把旧状态冒充最新状态。
- 未发现可直接公平横比的 Odin/Nim/Crystal/DMD/LDC 完整编译任务数据；依赖 LLVM/C 后端不等于性能一定好或坏。
- Zerolang 现有 C 构建和脚本不足以证明自托管及所有性能目标。
- Bun 稳定单文件打包、尚未合并的 Bun AOT PR、Oven fork 已合并的 experimental engine、上游 JSC JIT、Cranelift AOT、Nim/Crystal 自托管分别证明不同能力，不能互相替代。
- 项目首页/旧文档/源码注释可能落后于实际：本次已遇到 Cranelift 旧管线说明、Odin 历史 pass 警告和 DMD backend README 的沿革说法。发生冲突时优先固定实现与实际构建入口，仍把未运行验证的部分标出来。
- 研究重点是 Zig、QBE、Cranelift、Odin；其余项目为有限证据化对照，不声称穷尽编译器社区。


跨项目取舍与本项目审查统一见 [总览](README.md) 和 [dartc](dartc.md)。
