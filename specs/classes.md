# 类及相关声明

对象布局、构造、成员查找和动态分派仍待实现。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 普通、abstract 类 | 待实现。 |
| base/interface/final/sealed 修饰符 | 待实现。 |
| 字段、方法、getter/setter、静态成员 | 待实现。 |
| 抽象成员与 abstract 字段 | 待实现。 |
| 用户算术、关系、一元及索引运算符 | 待实现。 |
| `operator ==`、`noSuchMethod` | 待实现。 |
| 普通、命名、生成式重定向构造 | 待实现。 |
| const 生成式构造 | 待实现。 |
| 工厂与重定向工厂 | 待实现。 |
| this/super 形参 | 待实现。 |
| 主构造器及 new/factory 简写 | 待实现。 |
| 构造器函数值 | 待实现。 |
| 泛型实例、成员代入和协变检查 | 待实现。 |
| 简单与增强枚举 | 待实现。 |
| 元数据注解 | 待实现。 |
| mixin、mixin application、extension、extension type | 待实现。 |
| 构造器 assert initializer | 待实现。 |

[兼容范围](README.md)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/classes.md)。

## 规范依据

[主规范 §10–§16](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[类修饰符](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/class-modifiers/feature-specification.md)、[主构造器](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.13/primary-constructors/feature-specification.md)、[构造器提取](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.15/constructor-tearoffs/feature-specification.md)、[增强枚举](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.17/enhanced-enums/feature-specification.md)。
