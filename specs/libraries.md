# 库、脚本与并发边界

转换以调用方提供的已解析库为单位，包含库的所有 part。可执行程序的入口、传递依赖装配和链接仍待实现。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 编译单元、具名/无名 library、脚本标记 | 待实现。 |
| import、as 前缀、显式/隐式 core | 保留顶层直接调用的声明身份，支持普通导入前缀。 |
| 条件 import/export | 待实现。 |
| export、再导出、show/hide | 待实现。 |
| 命名空间冲突与读写查找 | 待实现。 |
| deferred import | 待实现。 |
| part、URI/具名 part of | 读取官方 analyzer 返回的库单元，在转换前检查所有单元的 error 诊断。 |
| 相对、file:、package: URI | 待实现。 |
| package configuration v2 | 待实现。 |
| main 入口 | 待实现。 |
| StackTrace API | 待实现。 |
| isolate、消息端口与 spawn | 待实现。 |

[IR 行为对照](../test/ir/lowering_test.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/libraries.md)。

## 规范依据

[主规范 §19、§6.3](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[语言版本与包配置 v2](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.8/language-versioning/package-config-file-v2.md)、[通配前缀](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.7/wildcard-variables/feature-specification.md#imports)、[StackTrace API](https://api.dart.dev/stable/3.13.7/dart-core/StackTrace-class.html)。
