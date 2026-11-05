# 类及相关声明

类的身份由声明库和声明共同确定。字段按声明区分，机器布局由后端决定。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 普通、abstract 类 | 支持普通与泛型类、单继承和实现多个接口，保留继承路径中的类型实参。抽象类可参与类型判断与父类初始化。 |
| base/interface/final/sealed 修饰符 | analyzer 检查修饰符约束。IR 可表示这些类及其类型关系，禁止直接分配抽象类和 sealed 类。 |
| 字段、方法、getter/setter、静态成员 | 支持实例字段的构造初始化及 late/late final 惰性存储、隐式和显式 getter/setter、实例方法及静态方法。普通实例调用按运行类分派，super 调用选定的父类实现。私有成员限于声明库。支持显式静态 getter/setter。支持静态 const 及非 const 存储，包括 final、late/late final 的惰性初始化。 |
| 抽象成员与 abstract 字段 | 支持通过抽象 getter 和方法调用具体类的实现。 |
| 用户算术、关系、一元及索引运算符 | 类的运算符按解析后的成员分派，包括复合赋值和索引读写。super 直接调用选中的祖先实现。扩展运算符待实现。见[运算符与更新样本](../test/lowering/fixtures/nominal/updates.dart)。 |
| `operator ==`、`noSuchMethod` | 支持用户相等方法及动态缺失成员回退。自定义 noSuchMethod 收到含私有库身份、调用种类和实际参数的 Invocation；Object 默认实现抛出 NoSuchMethodError。需要入口/返回类型检查的合成 forwarder 暂以成员级保护明确拒绝，不能当普通缺失成员执行。真实继承实现优先，跨库私有成员的特殊转发保持保护。 |
| 普通、命名、生成式重定向构造 | 支持隐式和显式构造器、命名构造、this 重定向和 super 调用。子类字段先初始化，父类构造体先执行。 |
| const 生成式构造 | 支持普通调用和普通用户类的常量实例。常量值保留实际泛型、继承及私有字段存储；相同类型和字段值按规范身份复用。 |
| 工厂与重定向工厂 | 工厂体可以返回已有或新建的子类实例。重定向工厂可经过多级重定向到生成式构造器或工厂体，并逐级代换泛型实参。实参只求值一次，省略的参数采用最终目标的默认值。见[重定向工厂样本](../test/lowering/fixtures/nominal/factories.dart)。 |
| this/super 形参 | 支持初始化形参和转发给对应父类形参的 super 参数。 |
| 主构造器及 new/factory 简写 | 支持主构造器、声明字段的形参、类体中的 this 初始化列表和构造体，以及简写的次级构造器。 |
| 构造器函数值 | 支持生成式和工厂构造器提取，包括泛型构造器函数值、显式或上下文实例化、重定向工厂、默认参数和函数值身份。泛型类型别名的参数重排、固定/重复参数和不同界限保留其独立身份。 |
| 泛型实例、成员代入和协变检查 | 支持类类型参数、界限、嵌套实参、成员类型代入和泛型继承。实例保留实际类型实参，宽化静态引用后的字段写入、方法调用和方法提取仍执行协变检查。类体只保留一份，闭包捕获类型环境。见[泛型样本](../test/lowering/fixtures/generic_classes.dart)和[泛型工厂重定向样本](../test/lowering/fixtures/generic_redirect_factory.dart)。 |
| 简单、增强及泛型枚举 | 复用类的常量存储和成员派发，支持 values、index、隐式 EnumName.name、默认/自定义 toString、字段、方法、运算符、工厂及模式；values 保留每项实际类型参数。具体 enum、Enum 及其类型参数界限支持显式 toString 调用与提取；通用 Object 接收者及 super.toString 仍待实现。带用户存储字段 `_name` 的 enum 因 analyzer 丢失原值而明确拒绝；同名 getter 不受此限制。混入及 Enum/EnumByName 的其他 SDK helper 待实现。见[枚举样本](../test/lowering/fixtures/enums.dart)。 |
| 元数据注解 | 待实现。 |
| mixin、mixin application、extension、extension type | 待实现。 |
| 构造器 assert initializer | 支持可配置的构造器断言，保持初始化列表顺序及抛错行为。默认关闭，使用 `enableAssertions: true` 启用。 |

[构造样本](../test/lowering/fixtures/nominal/constructors.dart)和[分派、默认参数与私有成员样本](../test/lowering/fixtures/nominal/members.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/classes.md)。

## 规范依据

[主规范 §10–§16](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[类修饰符](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/class-modifiers/feature-specification.md)、[主构造器](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.13/primary-constructors/feature-specification.md)、[构造器提取](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.15/constructor-tearoffs/feature-specification.md)、[增强枚举](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.17/enhanced-enums/feature-specification.md)。
