# 类及相关声明

类的身份由声明库和声明共同确定。字段按声明区分，机器布局由后端决定。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 普通、abstract 类 | 支持非泛型类、单继承和实现多个非泛型接口。抽象类可参与类型判断与父类初始化。 |
| base/interface/final/sealed 修饰符 | analyzer 检查修饰符约束。IR 可表示这些类及其类型关系，禁止直接分配抽象类和 sealed 类。 |
| 字段、方法、getter/setter、静态成员 | 支持实例字段的构造初始化、隐式和显式 getter、实例方法及静态方法。普通实例调用按运行类分派，super 调用选定的父类实现。私有成员限于声明库。属性赋值和静态存储待实现。 |
| 抽象成员与 abstract 字段 | 支持通过抽象 getter 和方法调用具体类的实现。 |
| 用户算术、关系、一元及索引运算符 | 待实现。 |
| `operator ==`、`noSuchMethod` | 支持用户相等方法，包括作为 record 字段进行比较。noSuchMethod 转发待实现。 |
| 普通、命名、生成式重定向构造 | 支持隐式和显式构造器、命名构造、this 重定向和 super 调用。子类字段先初始化，父类构造体先执行。 |
| const 生成式构造 | 支持作为普通构造器调用。常量实例待实现。 |
| 工厂与重定向工厂 | 支持返回自身或子类实例的工厂体。重定向工厂待实现。 |
| this/super 形参 | 支持初始化形参和转发给对应父类形参的 super 参数。 |
| 主构造器及 new/factory 简写 | 支持主构造器、声明字段的形参、类体中的 this 初始化列表和构造体，以及简写的次级构造器。 |
| 构造器函数值 | 待实现。 |
| 泛型实例、成员代入和协变检查 | 待实现。 |
| 简单与增强枚举 | 待实现。 |
| 元数据注解 | 待实现。 |
| mixin、mixin application、extension、extension type | 待实现。 |
| 构造器 assert initializer | 待实现。 |

[构造样本](../test/lowering/fixtures/nominal/constructors.dart)和[分派、默认参数与私有成员样本](../test/lowering/fixtures/nominal/members.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/classes.md)。

## 规范依据

[主规范 §10–§16](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[类修饰符](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/class-modifiers/feature-specification.md)、[主构造器](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.13/primary-constructors/feature-specification.md)、[构造器提取](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.15/constructor-tearoffs/feature-specification.md)、[增强枚举](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.17/enhanced-enums/feature-specification.md)。
