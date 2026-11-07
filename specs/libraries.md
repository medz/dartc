# 库、脚本与并发边界

转换以调用方明确提供的库批次为单位，包含每个库的所有 part。`CheckedLibraries.read` 复用官方 analyzer 的解析结果；名称与指令解析不由 lowering 重复实现。导入库的函数调用保留声明身份，但只有批次内的库会生成函数体。可执行程序的入口选择、传递依赖装配和链接仍待实现。

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

## 规范依据

[主规范 §19、§6.3](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[语言版本与包配置 v2](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.8/language-versioning/package-config-file-v2.md)、[通配前缀](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/wildcard-variables/feature-specification.md#imports)、[StackTrace API](https://api.dart.dev/stable/3.13.7/dart-core/StackTrace-class.html)。
