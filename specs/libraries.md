# 库、脚本与并发边界

本页说明库装入、命名空间、入口与包解析，对应主规范 §19、§6.3。[状态与阶段含义](README.md#如何读矩阵)适用于下表；语义分析 API 当前未提供，CLI 的装入和名称检查与新 parser 分开。

## 特性支持

| 特性 | 语法解析 | 语义分析 API | 编译/运行 | 使用限制 |
| --- | --- | --- | --- | --- |
| 编译单元、具名/无名 library、脚本标记 | 支持 | 未支持 | 部分 | CLI 的 library; 要求至少 2.19；顶层声明并非全部可编译。 |
| import、as 前缀、显式/隐式 core | 支持 | 未支持 | 部分 | 仅受支持 SDK 子集，非完整 dart:core。 |
| 条件 import/export | 支持 | 未支持 | 部分 | 环境来自目标，不继承编译宿主；仅装入选中分支。 |
| export、再导出、show/hide | 支持 | 未支持 | 部分 | 保留来源身份；扩展命名空间仍缺。 |
| 命名空间冲突与读写查找 | — | 未支持 | 部分 | import 按使用诊断，export 在声明收集后检查；完整一致性未确认。 |
| deferred import | 支持 | 未支持 | 未支持 | CLI 拒绝，无 loadLibrary 或加载状态。 |
| part、URI/具名 part of | 支持 | 未支持 | 部分 | CLI 检查归属、版本和重复使用；augmentation 未支持。 |
| 相对、file:、package: URI | 支持 | 未支持 | 部分 | parser 只解析字符串，CLI 才装入和检查包根。 |
| package configuration v2 | — | 未支持 | 部分 | 不解析 pubspec/旧 .packages，不求解或下载依赖。 |
| main 入口 | 支持 | 未支持 | 部分 | 最多两个必需位置参数，第二实参固定 null。 |
| StackTrace API | 支持 | 未支持 | 部分 | 按普通调用解析；运行轨迹仅同步函数名。 |
| isolate、消息端口与 spawn | 部分 | 未支持 | 未支持 | 可解析普通名称/调用不代表提供 dart:isolate。 |

## 编译单元解析 API

`parseCompilationUnit(ScanResult)` 返回整文件 AST 与词法/语法诊断，保留空文件、完整范围、脚本标记、注释/BOM 位置，以及有序指令和声明。缺失声明或 URI 使用恢复节点，调用方须检查 hasErrors。

```dart
library sample;
import 'base.dart' if (dart.library.io) 'native.dart' as platform
    show Service hide Internal;
export 'public.dart' show Service;
part 'implementation.dart';
```

parser 支持元数据、无名 library、条件 URI、deferred/as、顺序 show/hide、part 和 URI/点分名 part of，检查部分指令顺序。URI 可用 raw、多行、相邻字符串，但拒绝插值。它**不解码或解析 URI、不装入依赖、不选择条件、不检查命名空间或 part 实际归属**。模式和 switch 已可在文件内解析。

## 导入、导出与命名空间

CLI 区分库身份与物理文件身份。立即导入可用 as 前缀；显式或隐式 core、再导出、用户同名遮蔽按真实来源处理。StringBuffer、StackTrace、pragma 由 core 的实际导出提供，原生内建类型保留系统身份，但不代表完整 SDK 已装入。

### 前缀与私有名

前缀不能与本库或 part 的同 basename 顶层声明重名，setter 也参与。相同前缀可合并普通导入，组内未使用歧义不立即报错。前缀遮蔽同名无前缀导入和隐式 core 名，不能作值、赋值目标或类型；局部变量、参数、类型参数和成员可以遮蔽它。

从 3.7 起通配前缀 `_` 不引入可访问名，旧版仍可用 _.member；按 SDK 3.13.7，它仍参与和顶层 `_` 的声明冲突。私有名按原声明库检查，过滤或再导出不使私有名公开；part 共享库身份。

### 读写、过滤与冲突

getter/setter 两侧分别查找，可来自不同库；本库任意同名声明遮蔽导入两侧。show/hide 按指令顺序以 basename 同时过滤两侧。再导出在本库缺少所需读/写侧时继续查找原来源。

同一声明的菱形/循环再导出可合并；普通库和系统库按 basename 决定优先级，指令顺序不用于挑选冲突目标。import 消费到歧义名才报错，export 在声明收集后检查所有已加载库的公开名称，任一读/写侧冲突即错；调用方过滤不能掩盖被导出库自身冲突。part 声明参与本库遮蔽。

访问器 basename 的完整一致性**待确认**：固定草案与 SDK 3.13.5 analyzer/CFE 不完全相同。一个库提供 getter+setter、另一个仅 getter 时，仅写该名的 CFE 结果可能随 import/export 顺序变化，analyzer 对两种 export 顺序都报冲突。dartc 不复刻顺序选择；扩展及完整前缀/命名空间组合仍缺。

## 条件 URI 与 part

CLI 按源码顺序选择首个字符串值匹配条件，省略比较值取 "true"，无匹配取默认 URI。所有分支都检查 URI 字面量并拒绝插值，但只装入选中库。当前目标仅将 core 和受限 ffi 注册为 "true"，io/isolate/js 等未提供；不继承宿主 VM 能力。自定义环境、String.fromEnvironment 和 deferred 行为未支持。

part 可按 URI 或具名 part of 关联。纳入前核对库身份，主文件/parts 共享声明、前缀和私有成员；物理文件保持自己的 URI、token 和诊断。每个文件先按 package/header 算版本，part 要求版本及“是否存在版本标记”均一致。拒绝重复 part、跨库复用、part 内其他指令、直接导入 part。augmentation 和完整库语法仍缺。

## 包配置与 URI

CLI 从入口目录向上找最近 package configuration v2，也可用 --packages 指定，整次编译读一次。最深包根决定文件归属和默认 languageVersion，覆盖 bin/test 等文件，文件头可覆盖版本。无配置默认 3.13；使用不支持版本的包报错，未使用的未来版本包不阻断编译。

重复包名、重复规范化根、嵌套根约束会检查；数组顺序不改变大小写敏感查找或最深根归属。不支持 pubspec、旧 .packages、依赖求解和下载。SDK 3.13.5 在未使用重叠包时接受部分无效配置，dartc 按固定 v2 格式拒绝库目录包含嵌套根或位于嵌套根内的重叠，不保证该边界与 SDK 完全相同。

本地相对 URI、file:、package:、dart:core、dart:ffi 在当前子集内，支持点段、百分号 UTF-8 和包根约束。身份按规范 URI 保存：同一规范 file/relative 合并，package 保持包身份；内部双斜线和保留字符编码差异不被磁盘路径归一吞掉。包内相对引用按 package 基址解析。非本地 scheme/authority 拒绝，完整 URI 组合仍待确认。

没有显式 dartc 包映射时，CLI 提供内置 package:dartc/export.dart；包配置映射优先。Dart 多文件导出与原生符号导出是不同机制，后者见[FFI](types.md#ffi-类型与原生导出声明)。

## 脚本入口与并发

CLI 从导出空间查找 main。支持至多两个必需位置参数，以及其余可选/命名默认值：第一位置实参为 List<String> 命令行参数，第二固定 null，不是 isolate 启动载荷。

```dart
void main(List<String> args) {
  print(args);
}
```

原生产物无 isolates、消息端口、spawn 或独立隔离堆，也不提供 dart:isolate 执行能力。async/生成器同样没有调度实现；Wasm 是后续目标，不代表当前可输出或可用宿主 JS 互操作。

## StackTrace API

StackTrace.current 同步捕获 Dart 调用链，包含直接、递归、闭包和函数值调用，返回独立不可变轨迹。文本按栈顺序列函数名，可能含生成的调用适配器；没有文件/行号、异步调用链或原生边界轨迹。

StackTrace.fromString 保留任意 String，toString 返回原文本；empty 可作常量空轨迹。当前用普通 Dart 类和非 const 命名构造器提供 API，不是 SDK 完整抽象接口/factory 语义，用户实现 StackTrace 仍受缺口限制。同步 throw 携带轨迹，rethrow 保留原轨迹；Error 首次轨迹和指定轨迹的身份边界见[异常对象](statements.md#核心错误与异常对象)。

## 规范依据

[主规范 §19、§6.3](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[语言版本与包配置 v2](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.8/language-versioning/package-config-file-v2.md)、[通配前缀](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/wildcard-variables/feature-specification.md#imports)、[StackTrace API](https://api.dart.dev/stable/3.13.7/dart-core/StackTrace-class.html)。
