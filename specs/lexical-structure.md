# 词法结构、作用域与错误

源码、包配置中的语言版本和名称由官方 analyzer 解析。IR 输入使用 SDK 稳定语言配置；编辑器的诊断分级以及源码中的 `// ignore:` 不能隐藏语言错误。项目通过分析选项开启的实验特性尚未接入。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 标识符、关键词、标点及运算符 | 前端解析；原生行为待验证。 |
| 十进制、十六进制整数，小数与指数 | 前端解析；原生行为待验证。 |
| 数字分隔符 | 前端解析；原生行为待验证。 |
| 普通、raw、多行、相邻字符串及插值 | 前端解析；原生行为待验证。 |
| 单行、文档及嵌套块注释 | 前端解析；原生行为待验证。 |
| BOM 与 `#!` 文件头 | 前端解析；原生行为待验证。 |
| 按显式所选版本检查语法 | 前端解析；原生行为待验证。 |
| 自动解释 `// @dart` 选择语言版本 | 前端解析；原生行为待验证。 |
| 局部作用域、遮蔽及声明前引用 | 局部变量和形参通过 analyzer 的声明身份取值。 |
| 按库划分的下划线私有名 | 前端解析；原生行为待验证。 |
| 带源码位置的诊断 | 输入库中带 error 诊断的单元阻止该批库生成 IR。 |

[IR 行为对照](../test/lowering/lowering_test.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/lexical-structure.md)。

## 规范依据

[主规范 §6、§7、§21](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[语言版本选择](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.8/language-versioning/feature-specification.md)、[数字分隔符](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.6/digit-separators/feature-specification.md)。
