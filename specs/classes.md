# 类及相关声明

类的身份由声明库和声明共同确定。字段按声明区分，机器布局由后端决定。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 普通、abstract 类 | 支持普通与泛型类、单继承和实现多个接口，保留继承路径中的类型实参。抽象类可参与类型判断与父类初始化。 |
| base/interface/final/sealed 修饰符 | analyzer 检查修饰符约束。IR 可表示这些类及其类型关系，禁止直接分配抽象类和 sealed 类。 |
| 字段、方法、getter/setter、静态成员 | 支持实例字段的构造初始化及 late/late final 惰性存储、隐式和显式 getter/setter、实例方法及静态方法。普通实例调用按运行类分派，super 调用选定的父类实现。私有成员限于声明库。支持显式静态 getter/setter。支持静态 const 及非 const 存储，包括 final、late/late final 的惰性初始化。 |
| 抽象成员与 abstract 字段 | 支持通过抽象 getter 和方法调用具体类的实现。 |
| 用户算术、关系、一元及索引运算符 | 类的运算符按解析后的成员分派，包括复合赋值和索引读写。super 直接调用选中的祖先实现。普通 extension 运算符复用静态调用，边界与 SDK 差异见[扩展访问](extension-access.md)。见[运算符与更新样本](../test/lowering/fixtures/nominal/updates.dart)。 |
| `operator ==`、`noSuchMethod` | 支持用户相等方法及动态缺失成员回退。自定义 noSuchMethod 收到含私有库身份、调用种类和实际参数的 Invocation；Object 默认实现抛出 NoSuchMethodError。合成 typed forwarder 使用普通函数体，复用入口默认值、泛型边界、协变参数及返回检查；void 返回保留实际结果，Never 返回执行检查。真实继承实现优先，同签名转发继承保留原默认值；super 解析实际实现，支持声明顺序、闭包和提取。跨库私有义务使用独立的库选择器并生成抛错体；不兼容真实祖先按原函数子类型关系决定替换，保留组合接口签名、默认值及协变检查，兼容祖先仍复用。泛型接口的原始协变标记经具体化及真实重写后仍保留，参数按位置或命名身份对齐；方法泛型界限的协变来源单独保留。自身抽象普通方法与实际祖先的完整函数类型相同时，可生成普通 direct-super 协变包装，保留自身默认值、泛型实参及命名参数身份；多层包装直接转发最终祖先，仍保留后续 noSuchMethod 替换资格。具体类的同签名 noSuchMethod 复用保留祖先默认值。仅接口变化、不同函数类型的半桩、私有/访问器/运算符包装及缺失合并泛型默认元数据仍明确拒绝。 |
| 普通、命名、生成式重定向构造 | 支持隐式和显式构造器、命名构造、this 重定向和 super 调用。子类字段先初始化，父类构造体先执行。 |
| const 生成式构造 | 支持普通调用和普通用户类的常量实例。常量值保留实际泛型、继承及私有字段存储；相同类型和字段值按规范身份复用。 |
| 工厂与重定向工厂 | 工厂体可以返回已有或新建的子类实例。重定向工厂可经过多级重定向到生成式构造器或工厂体，并逐级代换泛型实参。实参只求值一次，省略的参数采用最终目标的默认值。见[重定向工厂样本](../test/lowering/fixtures/nominal/factories.dart)。 |
| this/super 形参 | 支持初始化形参和转发给对应父类形参的 super 参数。 |
| 主构造器及 new/factory 简写 | 支持主构造器、声明字段的形参、类体中的 this 初始化列表和构造体，以及简写的次级构造器。 |
| 构造器函数值 | 支持生成式和工厂构造器提取，包括泛型构造器函数值、显式或上下文实例化、重定向工厂、默认参数和函数值身份。泛型类型别名的参数重排、固定/重复参数和不同界限保留其独立身份。 |
| 泛型实例、成员代入和协变检查 | 支持类类型参数、界限、嵌套实参、成员类型代入和泛型继承。实例保留实际类型实参，宽化静态引用后的字段写入、方法调用和方法提取仍执行协变检查。类体只保留一份，闭包捕获类型环境。见[泛型样本](../test/lowering/fixtures/generic_classes.dart)和[泛型工厂重定向样本](../test/lowering/fixtures/generic_redirect_factory.dart)。 |
| 简单、增强及泛型枚举 | 复用类的常量存储和成员派发，支持 values、index、隐式 EnumName.name、默认/自定义 toString、字段、方法、运算符、工厂及模式；values 保留每项实际类型参数。具体 enum、Enum 及其类型参数界限支持显式 toString 调用与提取；通用 Object 接收者也支持 toString 调用与提取。带用户存储字段 `_name` 的 enum 因 analyzer 丢失原值而明确拒绝；同名 getter 不受此限制。混入及 Enum/EnumByName 的其他 SDK helper 待实现。见[枚举样本](../test/lowering/fixtures/enums.dart)。 |
| Object.toString | Object?/类型参数视图支持虚调用及提取，super 保留选定祖先语义，用户重写优先。静态、dynamic、对象模式及 super 默认方法的绑定身份一致。fixture 当前覆盖用户实例、null/标量、Type 与 Symbol；聚合值、函数、错误及未建模 SDK 存储明确拒绝。见[字符串样本](../test/lowering/fixtures/object_to_string.dart)。 |
| 元数据注解 | 待实现。 |
| 普通 extension | 声明与直接方法调用复用普通静态目标，接收者为显式首参数，扩展与方法类型参数按声明顺序展开。支持隐式选择、显式 override、词法调用、静态成员/变量，以及闭包捕获 this 与类型环境。非类、可空、record、函数和类型变量接收者无需伪造类。实例 getter/setter、索引、一元/二元运算符、复合赋值及增减复用同一调用适配器；对象与关系模式使用相同的已解析目标。隐式 call 调用复用静态目标，方法提取复用捕获接收者的普通闭包；部分 analyzer 泛型元数据边界仍明确拒绝，见[扩展访问范围与差异](extension-access.md)。见[扩展样本](../test/lowering/fixtures/extension_methods.dart)。 |
| extension type | 支持普通/泛型的简单主构造器、implements 和表示擦除。自身及继承的 extension type 成员复用静态函数，普通接口在表示对象上虚派发，无名义分配。支持可空/record/函数表示、const、构造器与方法提取，具体范围与拒绝边界见[extension type](extension-types.md)。 |
| mixin、mixin application | 待实现。 |
| 构造器 assert initializer | 支持可配置的构造器断言，保持初始化列表顺序及抛错行为。默认关闭，使用 `enableAssertions: true` 启用。 |

[构造样本](../test/lowering/fixtures/nominal/constructors.dart)和[分派、默认参数与私有成员样本](../test/lowering/fixtures/nominal/members.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/classes.md)。

## 规范依据

[主规范 §10–§16](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[类修饰符](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/class-modifiers/feature-specification.md)、[主构造器](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.13/primary-constructors/feature-specification.md)、[构造器提取](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.15/constructor-tearoffs/feature-specification.md)、[增强枚举](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.17/enhanced-enums/feature-specification.md)。

Typed forwarder 的 Invocation 与动态缺失回退及公开工厂分开建模：成员/命名键使用规范化 Symbol，命名实参按声明顺序排列；空位置列表为 const<dynamic>[]，命名 Map 每次创建，集合不可修改。沿用 SDK 3.13.7 的可观察身份，不将其声明为跨 SDK 保证。见[转发样本](../test/lowering/fixtures/typed_forwarders.dart)。

跨库私有转发通过真实 SDK NoSuchMethodError.withInvocation 工厂和普通 Throw 构造错误，保持类型检查先于函数体、错误身份和异常传播。派发选择器保留原声明库，生成错误的 Invocation Symbol 按 SDK 3.13.7 使用目标体所属库；动态错误形状回退仍使用调用选择器身份。多个库的同名私有成员可以共存。见[跨库转发样本](../test/lowering/fixtures/private_forwarders.dart)。
