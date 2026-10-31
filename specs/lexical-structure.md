# 词法结构、作用域与错误

本页说明源码如何分成 token、如何选择语言版本，以及名称与错误的边界，对应主规范 §6.1、§6.2、§7、§21。[状态与阶段含义](README.md#如何读矩阵)适用于下表；语义分析 API 当前未提供，CLI 内部的静态检查另见正文。

## 特性支持

| 特性 | 语法解析 | 语义分析 API | 编译/运行 | 使用限制 |
| --- | --- | --- | --- | --- |
| 标识符、关键词、标点及运算符 | 🟡 | ❌ | 🟡 | scanner 支持 ASCII 标识符；完整关键词位置规则未覆盖。 |
| 十进制、十六进制整数，小数与指数 | ✅ | ❌ | 🟡 | 扫描不转换数值、不检查范围；CLI 数值为 64 位整数和 binary64。 |
| 数字分隔符 | ✅ | ❌ | 🟡 | 数字之间可有连续 `_`；parser 所选版本与 CLI 文件版本均须至少 3.6。 |
| 普通、raw、多行、相邻字符串及插值 | 🟡 | ❌ | 🟡 | parser 保留原始文本，不解码、拼接或求值；CLI 转义范围与换行边界未完全确认。 |
| 单行、文档及嵌套块注释 | ✅ | ➖ | 🟡 | 未闭合块注释报错；CLI 的全部换行边界未确认。 |
| BOM 与 `#!` 文件头 | ✅ | ➖ | 🟡 | `#!` 仅在偏移 0 识别，不能放在 BOM 后。 |
| 按显式所选版本检查语法 | ✅ | ❌ | 🟡 | parser 接受 2.12–2.19、3.0–3.13，覆盖下列语法门控；不代表完整旧版本语义。 |
| 自动解释 `// @dart` 选择语言版本 | ❌ | ❌ | 🟡 | scanner 只保留注释；parser 的版本由调用方传入。CLI 仍独立按文件选择版本。 |
| 局部作用域、遮蔽及声明前引用 | ➖ | ❌ | 🟡 | CLI 检查部分名称规则，不提供公开绑定结果。 |
| 按库划分的下划线私有名 | ➖ | ❌ | 🟡 | 主文件与 part 共享私有性；扩展组合仍缺。 |
| 带源码位置的诊断 | ✅ | ❌ | 🟡 | 新 API 只报告词法/语法错误；CLI 的警告与错误分类不完整。 |

## 扫描 API

`package:dartc/scanner.dart` 接受源码快照，保留原始拼写及 UTF-16 区间。调用方负责提供已解码的文本。非法字符会产生诊断并保留 invalid token，扫描继续到 EOF。

```dart
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';

void main() {
  final source = SourceFile(Uri.parse('memory:sample.dart'), '1__000 + .5');
  final result = scan(source);
  if (!result.hasErrors) {
    for (final token in result.tokens) {
      print(token.lexeme);
    }
  }
}
```

数字按以下边界识别：

- `1_000`、`0xAB__CD`、`1_2.3__4e-5_6` 合法；`0x_1`、`1_`、`1e_2` 非法。
- 支持 `.5`；前导正负号不属于数字 token。小数点不吞并成员访问与级联，如 `1.foo`、`1..foo`。
- 任意长数字仍可成为 token；是否超出可执行数值范围由编译阶段判断。

字符串支持单双引号、raw、三引号、转义形状与 Unicode 范围检查，以及 `$name`、`${expression}` 和嵌套插值。相邻字符串在扫描结果中分开保留，parser 才表示其组合；两者都不提供最终字符串值。未闭合字符串只保留实际文本，不补造引号或花括号。

错误带代码和源码区间。词法错误、括号和语法恢复属于不同阶段：扫描成功不保证括号成对或关键字位置合法，解析成功也不保证名称、类型或运行正确。

## 解析语言版本

`package:dartc/parser.dart` 公开导出 `LanguageVersion`。七个入口 `parseCompilationUnit`、`parseExpression`、`parseStatement`、`parseTypeAnnotation`、`parseFormalParameterList`、`parseFunctionBody` 和 `parsePattern` 均接受可选命名参数 `languageVersion`，默认 `LanguageVersion.current`，当前为 3.13。

支持的显式版本为 **2.12–2.19 和 3.0–3.13**。不支持的版本（如 2.11、2.20、3.14）产生 `parser.unsupported_language_version` 诊断，仍返回可恢复 AST。调用方负责根据文件与包配置选择版本；parser 不读取 pubspec、package configuration，也不解释 `// @dart`，scanner 仅保留该注释。

```dart
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';

void main() {
  final input = scan(SourceFile(
    Uri.parse('memory:version.dart'),
    '// @dart = 2.19\nfinal value = (1, 2);',
  ));
  print(parseCompilationUnit(input).hasErrors); // false：默认按 3.13 解析。
  print(parseCompilationUnit(
    input,
    languageVersion: const LanguageVersion(2, 19),
  ).hasErrors); // true：record 语法要求 3.0。
}
```

低于下列最低版本时，相应语法产生 `parser.language_feature_disabled` 诊断；返回的树仍须结合诊断使用。

| 最低版本 | 已有语法门控 |
| --- | --- |
| 2.13 | 非函数类型 RHS 的 typedef。 |
| 2.14 | 泛型元数据、`>>>`、`>>>=` 和 `operator >>>`。 |
| 2.15 | 明确的函数/构造器 tear-off 语法，如 `f<T>`、`C.new`、`C<T>.named`；泛型直接调用不因此被禁用。 |
| 2.17 | super 形参、命名实参后的位置实参、增强枚举。 |
| 2.19 | 无名 `library;`。 |
| 3.0 | 类修饰符、record、模式、if-case 和 switch 表达式。 |
| 3.3 | extension type。 |
| 3.6 | 数字分隔符。 |
| 3.8 | 空感知集合元素，包括 Map 的空感知键/值。 |
| 3.10 | 点简写。 |
| 3.13 | 主构造器、`new`/`factory` 构造器简写，以及 class、enum、mixin、普通 extension 的分号空声明体；不指函数的分号空体。 |

小于 3.0 时，switch 语句的 case 使用常量表达式文法，而不是模式文法。版本检查不解析名称，不能从普通属性访问确定它是否为 tear-off；通配名字的绑定、私有命名参数的公共名、推断和提升等语义规则也不在其范围内。显式版本选项不是完整旧语言兼容保证，更不扩展 CLI 的编译/运行支持。

## 文件头与语言版本

仅文件起始的 BOM 被跳过；`#!` 必须从 UTF-16 偏移 0 开始。初始空白和注释不改变后续 token 的原始位置。

CLI 每个源文件独立选择语言版本：

```dart
// @dart = 3.6
final count = 1__000;
```

- 只采用代码或指令前首个完整的 `// @dart = M.m`。允许空格和 tab；`///`、块注释、补丁号或尾随内容不构成标记，后续标记不覆盖首个有效标记。
- 未标记时采用[所属包的默认版本](libraries.md#包配置与-uri)，未配置时为 3.13。导入方的版本不覆盖被导入文件。
- 数字分隔符要求 3.6；`>>>`、`>>>=` 要求 2.14。嵌套泛型的连续右尖括号仍按类型语法解释。其余版本化语法并非全部实现。
- 上述自动版本选择属于 CLI；新 parser 仅按调用方显式传入的版本进行[语法门控](#解析语言版本)。SDK 3.13.5 CFE 未识别含 tab 的版本标记，CLI 按版本规范接受。

## 作用域与私有性

CLI 为块、参数、循环、switch 分支和标签建立作用域，检查重复声明。局部和匿名函数有独立函数体作用域，捕获保持原绑定；局部值也会遮蔽同名类型或导入前缀。声明前引用不会退回同名全局声明，局部函数可自递归，但不能通过前向引用互递归。详见[变量](variables.md)和[词法捕获](functions.md#词法捕获)。

下划线名称按**声明所属库**而非文件或调用方判定私有性。part 与主文件共享私有顶层名和实例成员。继承成员与 super 构造也检查声明库；跨库同名私有成员不构成覆写。扩展成员与完整泛型查找仍有缺口。

## CLI 诊断与运行错误

CLI 的扫描、解析、部分语义和版本错误保留源码及 UTF-16 区间，在 stderr 显示路径、从 1 开始的行列和源码行。列按 UTF-16 code unit 计数，CRLF 算一次换行。源码按 UTF-8 容错解码，非法序列按最长合法前缀替换为 U+FFFD；字符串、注释可以保留替换字符，标识符中的替换字符被拒绝。

编译拒绝不保证已实现全部规范错误分类或警告。运行错误也须区分可捕获异常与直接进程退出：同步 throw/catch/finally 仅覆盖[语句页](statements.md#核心错误与异常对象)列出的错误对象，不能假定所有范围或 late 失败均可捕获。

## 规范依据

[主规范 §6、§7、§21](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[语言版本选择](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.8/language-versioning/feature-specification.md)、[数字分隔符](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.6/digit-separators/feature-specification.md)。
