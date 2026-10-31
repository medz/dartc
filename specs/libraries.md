# 库、脚本与并发边界

本页说明库装入、命名空间、入口与包解析，对应主规范 §19、§6.3。[状态与阶段含义](README.md#如何读矩阵)适用于下表；语义分析 API 当前未提供。公开 ProjectLoader 的源码装入能力另列于[装入矩阵](#库装入-api)，不属于裸 parser，也不替代旧 CLI 的名称检查或编译/运行。

## 特性支持

| 特性 | 语法解析 | 语义分析 API | 编译/运行 | 使用限制 |
| --- | --- | --- | --- | --- |
| 编译单元、具名/无名 library、脚本标记 | ✅ | ❌ | 🟡 | parser 与 CLI 的 library; 均要求至少 2.19；顶层声明并非全部可编译。 |
| import、as 前缀、显式/隐式 core | ✅ | ❌ | 🟡 | 仅受支持 SDK 子集，非完整 dart:core。 |
| 条件 import/export | ✅ | ❌ | 🟡 | CLI 环境来自目标，不继承编译宿主；ProjectLoader 环境由调用方指定，均只读取选中来源。 |
| export、再导出、show/hide | ✅ | ❌ | 🟡 | 保留来源身份；扩展命名空间仍缺。 |
| 命名空间冲突与读写查找 | ➖ | ❌ | 🟡 | import 按使用诊断，export 在声明收集后检查；完整一致性未确认。 |
| deferred import | ✅ | ❌ | ❌ | CLI 拒绝，无 loadLibrary 或加载状态。 |
| part、URI/具名 part of | ✅ | ❌ | 🟡 | CLI 检查归属、版本和重复使用；augmentation 未支持。 |
| 相对、file:、package: URI | ✅ | ❌ | 🟡 | parser 只解析字符串结构；ProjectLoader 可解析 URI 和装入源码，CLI 另有自己的 URI 规则。 |
| package configuration v2 | ➖ | ❌ | 🟡 | 不解析 pubspec/旧 .packages，不求解或下载依赖。 |
| main 入口 | ✅ | ❌ | 🟡 | 最多两个必需位置参数，第二实参固定 null，即使该参数可选或有默认值。 |
| StackTrace API | ✅ | ❌ | 🟡 | 按普通调用解析；运行轨迹仅同步函数名。 |
| isolate、消息端口与 spawn | 🟡 | ❌ | ❌ | 可解析普通名称/调用不代表提供 dart:isolate。 |

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

可用 `languageVersion` 显式指定[解析语言版本](lexical-structure.md#解析语言版本)；文件内的声明、表达式、语句和模式均沿用该选项。裸 parser 不读取 pubspec 或包配置，不解释 `// @dart`；可用 ProjectLoader [自动选择文件版本](lexical-structure.md#文件版本选择-api)。CLI 的版本选择仍为独立能力。

## 库装入 API

`package:dartc/project.dart` 的 `ProjectLoader.load(Uri entry)` 从**绝对入口 URI** 异步装入库图，返回不可变 `Project`。`Project.libraries` 按发现顺序、以逻辑 URI 索引各个 `Library`；每个库包含定义单元 `unit`、按指令顺序排列的 `parts` 和选中的 import/export `dependencies`。`LibraryUnit` 保留 AST、源码快照、所选语言版本及诊断。

以下状态仅指公开项目装入 API，不改变上表的三个阶段：

| 能力 | 项目装入 API | 使用限制 |
| --- | --- | --- |
| 通过 SourceProvider 装入库图 | ✅ | 来源可同步或异步返回文本；不内置完整 SDK 源码。 |
| URI 字符串解码、相对/file/package/dart/自定义来源 | ✅ | 支持非插值 raw、相邻、转义和多行字符串；具体来源须由提供者读取。 |
| 条件 import/export 与隐式 core 依赖 | ✅ | 使用调用方明确提供的字符串环境，只读取选中来源。 |
| deferred 依赖的源码装入 | ✅ | 保留 deferred 指令，不提供运行时 loadLibrary 或加载状态。 |
| part 归属和版本一致性检查 | ✅ | 按逻辑 URI 或库名检查；不绑定 part 内名称或私有成员。 |
| 按包默认值和文件头自动选择语言版本 | ✅ | 选择结果传给 parser；规则见[文件版本选择 API](lexical-structure.md#文件版本选择-api)。 |
| package configuration v2 与最近配置发现辅助函数 | ✅ | 由调用方发现/解析并传入 loader；不读取 pubspec/旧 .packages，不求解或下载依赖。 |
| 命名空间合并、名称绑定、类型/常量/流分析 | ❌ | 装入完成或无诊断均不表示已通过语义检查。 |

`SourceProvider` 定义于 `package:dartc/source.dart`，返回解码后的 `String` 或表示来源不存在的 null。loader 的 `readSource` 默认是 `readFileSource`，后者只读取 `file:`；`dart:` 源码及自定义来源必须由调用方提供。条件环境通过 `environment` 传入，默认空映射，不根据宿主运行时或提供者能读取哪些文件来推断可用库。

下面仅演示源码装入和版本选择，不演示编译或执行；空 `dart:core` 是示例占位，不是标准库实现：

```dart
import 'package:dartc/project.dart';

Future<void> main() async {
  final entry = Uri.parse('memory:/app/main.dart');
  final sources = <Uri, String>{
    entry: "// @dart = 3.12\nimport 'values.dart';",
    Uri.parse('memory:/app/values.dart'): 'final value = 1;',
    Uri.parse('dart:core'): '',
  };
  final loader = ProjectLoader(readSource: (uri) => sources[uri]);
  final project = await loader.load(entry);
  if (project.hasErrors) {
    for (final diagnostic in project.diagnostics) {
      print(diagnostic.message);
    }
    return;
  }
  print(project.libraries[entry]!.unit.languageVersion); // 3.12。
}
```

非 core 库若没有选中的显式 `dart:core` 导入，会加入隐式 core 依赖；仅导出 core 不会消除隐式导入。依赖边保留原指令，包括前缀和 show/hide，但不执行名称过滤或绑定；隐式边的 `directive` 为 null。循环和共享依赖按逻辑 URI 去重。

条件 URI 按源码顺序选择首个匹配分支，无匹配取默认 URI。未定义环境值视为空字符串，省略比较值时与 `"true"` 比较。未选中来源不读取，但整条指令仍接受词法和语法检查。装入 deferred 源码不等于运行时延迟加载；装入 SDK 源码也不代表该库已可编译执行。

part 按 URI 或点分库名核对 part-of 归属。缺失/不匹配 part-of、同一逻辑 part 重复包含或跨库共用、把 part 当库导入、part 中的其他库指令，以及[语言版本不一致](lexical-structure.md#文件版本选择-api)都会产生诊断。错误结果仍可能保留有关 AST，不能仅凭文件出现在图中就认定归属合法。

### 项目包配置与源码 URI

`ProjectLoader` 默认使用空包配置，**不会自行搜索配置**。可先调用 `findPackageConfiguration(entry, readSource: provider)`，再把返回值通过 `packages` 传给 loader；返回 null 时可使用 `const PackageConfiguration.empty()`。辅助函数从入口目录逐级向上寻找最近的 `.dart_tool/package_config.json`；找到但无效时抛错，不退回更远配置。它要求绝对、非 `package:`/`dart:` 的源码位置。

也可用 `PackageConfiguration.parse(text, uri: configUri)` 显式解析 v2 JSON。`configUri` 须是无 query/fragment 的绝对非 package URI；相对 rootUri 按配置位置解析，packageUri 是根内的相对暴露目录，省略时暴露根目录。配置检查重复包名、相同根及嵌套包根与暴露目录的冲突；合法嵌套包按最深根归属。未识别的元数据忽略，不读取 pubspec、旧 .packages，也不进行依赖求解或下载。

配置中的 `languageVersion` 须为无前导零、无补丁号的 `major.minor` 字符串，每个分量不超过 2147483647；格式有效不等于该语言版本受支持。实际装入文件时才把所选版本交给 parser 检查，未装入的未来版本包不会仅因版本较新而触发解析错误。

`resolveSourceUri(reference, from: base)` 解析相对引用和 URI 点段，不查询文件系统别名。相对引用需要绝对基址；源码 URI 不允许 query/fragment。`package:` 相对引用保留包名，`dart:core` 的相对引用位于 `dart:core/` 下；自定义 scheme 的读取能力取决于提供者，而不是 loader 自动提供网络或文件系统访问。

提供者收到的是解析后的源码位置，例如 package 映射后的 file URI；AST 和库图保留**逻辑 URI**。`package:app/a.dart` 与指向同一文件的 `file:` URI 仍是不同库身份，即使同次装入可共用该位置的读取结果。符号链接和不同物理路径也不会被文件系统查询自动合并；不能把 URI 解析或包配置验证当作文件系统沙箱保证。

### 诊断与异常

调用方须检查 `Project.hasErrors` 和 `diagnostics`；图可以包含未能装入的依赖目标。诊断包含装入、文件版本及 scanner/parser 的错误，不包含名称或类型检查结果。

- `resolveSourceUri`、`PackageConfiguration.parse` 的格式错误抛 `FormatException`；`load` 的入口 URI 不合法也会抛错，而非返回项目诊断。配置发现辅助函数的非法入口产生 `ArgumentError`，配置内容错误和提供者失败向调用方传播。
- `load` 内部遇到指令 URI 错误、未知包、来源不存在，以及提供者抛出的 `Exception`，会收集相应诊断。提供者的 `Error`（如 `StateError`）仍传播，不能假定所有失败都能恢复为项目结果。
- 直接调用 `readFileSource` 时，非 file URI 或文件不存在返回 null，非法 file URI 抛 `FormatException`，其他文件系统错误传播。文本按 UTF-8 容错解码，损坏编码变为替换字符，保留 BOM 和原始行结束符；通过 loader 调用时，读取的 `Exception` 转为装入诊断。

### 重复装入与缓存

同一 loader 的包配置、环境和默认版本固定；改变这些选项应创建新 loader。每次 `load` 重新读取可达来源，文本和所选语言版本未变时复用同一 `LibraryUnit` 与源码快照；库关系和 part 一致性仍按本次装入检查。旧 `Project` 保留自己的结果，不随后续源码改变。

只有最新启动的装入能更新缓存；较早的异步调用仍返回自己的结果，由调用方决定采用哪份。缓存只保留该次可达文件，不是所有历史来源。`clear()` 释放缓存而不使旧结果失效，也阻止已经进行中的装入重新填充被清空的缓存。缓存不提供文件监听、自动重装入或无限历史保留。

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

CLI 的 part 可按 URI 或具名 part of 关联。纳入前核对库身份，主文件/parts 共享声明、前缀和私有成员；物理文件保持自己的 URI、token 和诊断。每个文件先按 package/header 算版本，part 要求版本及“是否存在版本标记”均一致。拒绝重复 part、跨库复用、part 内其他指令、直接导入 part。augmentation 和完整库语法仍缺。

## 包配置与 URI

CLI 从入口目录向上找最近 package configuration v2，也可用 --packages 指定，整次编译读一次。最深包根决定文件归属和默认 languageVersion，覆盖 bin/test 等文件，文件头可覆盖版本。无配置默认 3.13；使用不支持版本的包报错，未使用的未来版本包不阻断编译。

重复包名、重复规范化根、嵌套根约束会检查；数组顺序不改变大小写敏感查找或最深根归属。不支持 pubspec、旧 .packages、依赖求解和下载。SDK 3.13.5 在未使用重叠包时接受部分无效配置，dartc 按固定 v2 格式拒绝库目录包含嵌套根或位于嵌套根内的重叠，不保证该边界与 SDK 完全相同。

本地相对 URI、file:、package:、dart:core、dart:ffi 在当前子集内，支持点段、百分号 UTF-8 和包根约束。身份按规范 URI 保存：同一规范 file/relative 合并，package 保持包身份；内部双斜线和保留字符编码差异不被磁盘路径归一吞掉。包内相对引用按 package 基址解析。非本地 scheme/authority 拒绝，完整 URI 组合仍待确认。

没有显式 dartc 包映射时，CLI 提供内置 package:dartc/export.dart；包配置映射优先。Dart 多文件导出与原生符号导出是不同机制，后者见[FFI](types.md#ffi-类型与原生导出声明)。

## 脚本入口与并发

CLI 从导出空间查找 main，支持至多两个必需位置参数。声明了位置参数时，第一实参为 List<String> 命令行参数，第二固定为 null，不是 isolate 启动载荷。第二参数即使可选或声明了默认值，也仍收到 null；若其类型非空，可能在进入函数体前因类型检查失败。只有第三个及以后可选位置参数和命名参数使用声明默认值。

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
