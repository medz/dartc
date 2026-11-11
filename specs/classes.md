# 类及相关声明

类的身份由声明库和声明共同确定。字段按声明区分，物理存储由 layout 表达，codegen 将声明和语义类型映射到该布局。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 普通、abstract 类 | 支持普通与泛型类、单继承和实现多个接口，保留继承路径中的类型实参。抽象类可参与类型判断与父类初始化。 |
| base/interface/final/sealed 修饰符 | analyzer 检查修饰符约束。IR 可表示这些类及其类型关系，禁止直接分配抽象类和 sealed 类。 |
| 字段、方法、getter/setter、静态成员 | 支持实例字段的构造初始化及 late/late final 惰性存储、隐式和显式 getter/setter、实例方法及静态方法。普通实例调用按运行类分派，super 调用选定的父类实现。私有成员限于声明库。支持显式静态 getter/setter。支持静态 const 及非 const 存储，包括 final、late/late final 的惰性初始化。 |
| 抽象成员与 abstract 字段 | 支持通过抽象 getter 和方法调用具体类的实现。 |
| 用户算术、关系、一元及索引运算符 | 类的运算符按解析后的成员分派，包括复合赋值和索引读写。super 直接调用选中的祖先实现。普通 extension 运算符复用静态调用，边界与 SDK 差异见[扩展访问](extension-access.md)。见[运算符与更新样本](../test/frontend/lowering/fixtures/nominal/updates.dart)。 |
| `operator ==`、`noSuchMethod` | 支持用户相等方法及动态缺失成员回退。自定义 noSuchMethod 收到含私有库身份、调用种类和实际参数的 Invocation；Object 默认实现抛出 NoSuchMethodError。合成 typed forwarder 使用普通函数体，复用入口默认值、泛型边界、协变参数及返回检查；void 返回保留实际结果，Never 返回执行检查。真实继承实现优先，同签名转发继承保留原默认值；super 解析实际实现，支持声明顺序、闭包和提取。跨库私有义务使用独立的库选择器并生成抛错体；不兼容真实祖先按原函数子类型关系决定替换，保留组合接口签名、默认值及协变检查，兼容祖先仍复用。泛型接口的原始协变标记经具体化及真实重写后仍保留，参数按位置或命名身份对齐；方法泛型界限的协变来源单独保留。抽象声明和接口带来的协变检查使用普通 direct-super 转发，保留声明默认值、泛型实参及命名参数身份；接口声明与继承实现的入口类型分别记录，静态调用检查不改变继承实现可接受的运行时参数。方法、访问器、运算符及跨库私有抽象义务均使用此规则；多层包装直接转发最终祖先，仍保留后续 noSuchMethod 替换资格。具体类的同签名 noSuchMethod 复用保留祖先默认值。缺失合并泛型默认元数据时仍明确拒绝。见[继承入口与接口声明对照](../test/frontend/lowering/covariance_transitions_test.dart)。 |
| 普通、命名、生成式重定向构造 | 支持隐式和显式构造器、命名构造、this 重定向和 super 调用。子类字段先初始化，父类构造体先执行。 |
| const 生成式构造 | 支持普通调用和普通用户类的常量实例。常量值保留实际泛型、继承及私有字段存储；相同类型和字段值按规范身份复用。 |
| 工厂与重定向工厂 | 工厂体可以返回已有或新建的子类实例。重定向工厂可经过多级重定向到生成式构造器或工厂体，并逐级代换泛型实参。实参只求值一次，省略的参数采用最终目标的默认值。见[重定向工厂样本](../test/frontend/lowering/fixtures/nominal/factories.dart)。 |
| this/super 形参 | 支持初始化形参和转发给对应父类形参的 super 参数。 |
| 主构造器及 new/factory 简写 | 支持主构造器、声明字段的形参、类体中的 this 初始化列表和构造体，以及简写的次级构造器。 |
| 构造器函数值 | 支持生成式和工厂构造器提取，包括泛型构造器函数值、显式或上下文实例化、重定向工厂、默认参数和函数值身份。泛型类型别名的参数重排、固定/重复参数和不同界限保留其独立身份。 |
| 泛型实例、成员代入和协变检查 | 支持类类型参数、界限、嵌套实参、成员类型代入和泛型继承。实例保留实际类型实参，宽化静态引用后的字段写入、方法调用和方法提取仍执行协变检查。类体只保留一份，闭包捕获类型环境。见[泛型样本](../test/frontend/lowering/fixtures/generic_classes.dart)和[泛型工厂重定向样本](../test/frontend/lowering/fixtures/generic_redirect_factory.dart)。 |
| 简单、增强及泛型枚举 | 复用类的常量存储和成员派发，支持 values、index、隐式 EnumName.name、默认/自定义 toString、字段、方法、运算符、工厂及模式；values 保留每项实际类型参数。具体 enum、Enum 及其类型参数界限支持显式 toString 调用与提取；通用 Object 接收者也支持 toString 调用与提取。带用户存储字段 `_name` 的 enum 因 analyzer 丢失原值而明确拒绝；同名 getter 不受此限制。支持普通及泛型 mixin，保留混入方法对 toString 的重写；Enum/EnumByName 的其他 SDK helper 保留普通导入调用，参考执行器尚未提供这些函数体。见[枚举样本](../test/frontend/lowering/fixtures/enums.dart)。 |
| Object.toString | Object?/类型参数视图支持虚调用及提取，super 保留选定祖先语义，用户重写优先。静态、dynamic、对象模式及 super 默认方法的绑定身份一致。fixture 当前覆盖用户实例、null/标量、Type 与 Symbol；聚合值、函数、错误及未建模 SDK 存储明确拒绝。见[字符串样本](../test/frontend/lowering/fixtures/object_to_string.dart)。 |
| 元数据注解 | analyzer 检查注解表达式及常量要求；IR 尚未保存通用注解。interop 可从已检查元数据绑定 `Export<Int64 Function(...)>`，当前范围见[原生库](libraries.md#原生库)。其他原生绑定仍待实现。 |
| 普通 extension | 声明与直接方法调用复用普通静态目标，接收者为显式首参数，扩展与方法类型参数按声明顺序展开。支持隐式选择、显式 override、词法调用、静态成员/变量，以及闭包捕获 this 与类型环境。非类、可空、record、函数和类型变量接收者无需伪造类。实例 getter/setter、索引、一元/二元运算符、复合赋值及增减复用同一调用适配器；对象与关系模式使用相同的已解析目标。隐式 call 调用复用静态目标，方法提取复用捕获接收者的普通闭包；部分 analyzer 泛型元数据边界仍明确拒绝，见[扩展访问范围与差异](extension-access.md)。见[扩展样本](../test/frontend/lowering/fixtures/extension_methods.dart)。 |
| extension type | 支持普通/泛型的主构造器体、生成式/this 重定向/factory body、implements 和表示擦除。自身及继承的 extension type 成员复用静态函数，普通接口在表示对象上虚派发，无名义分配。支持可空/record/函数表示、const、构造器与方法提取，具体范围与拒绝边界见[extension type](extension-types.md)。 |
| mixin、mixin application | 支持普通及泛型声明、应用类与父类、重复及嵌套应用、字段/late、on 约束、词法 super、泛型方法与闭包、abstract/implements、常量和 alias 构造。成员保留继承的协变检查；具体范围见 [mixins](mixins.md)。 |
| 构造器 assert initializer | 非 const 调用的断言默认关闭，使用 `enableAssertions: true` 启用，保持初始化列表顺序及抛错行为。const 求值始终检查断言，失败属于静态错误；数值常量及已知诊断缺口见[数值比较](expressions.md#数值比较与-sdk-差异)。 |

[构造样本](../test/frontend/lowering/fixtures/nominal/constructors.dart)和[分派、默认参数与私有成员样本](../test/frontend/lowering/fixtures/nominal/members.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/classes.md)。

## 原生执行范围

`CodeGenerator` 支持已检查 IR 中的不可变 `ObjectConstant`、`Construct`、直接 `LoadField`/`StoreField`、`TypeView`，以及对象引用的直接调用、参数、返回、分支和循环传递。字段可以存储 int、bool、double、null 或对象引用；继承字段及不同声明库的同名私有字段分别保留。构造器先分配实例，再执行初始化；嵌套分配保留接收者、参数和可达对象。普通 getter 和方法仍保留虚派发语义，不能用直接读取字段代替。

单个生成模块中的同类型、同字段值常量共用存储；负零与正零、不同 NaN 位模式及不同具体类型保持各自身份。double 身份保留二进制表示，见 [identical 契约](https://api.dart.dev/dart-core/identical.html)与[常量身份验证](../test/ir/constants_test.dart)。

`super.hashCode` 选择 Object 默认实现时，原生对象返回稳定的身份哈希，不调用自身的重写 getter。常量重复引用、移动回收及同模块跨入口保留的对象保持该值，见[原生行为验证](../test/compiler/object_members_test.dart)与[身份哈希契约](https://api.dart.dev/dart-core/identityHashCode.html)。虚 `hashCode` 派发保留用户重写；函数值和内建 Type 使用与相等关系一致的哈希，见[函数值](functions.md)与[类型](types.md)。

泛型字段按声明类型确定存储，类型参数字段保存引用。int、double 及 bool 值可以装箱进入参数、返回值、分支和局部存储；计算所得的数值也可以写入非泛型引用字段，其装箱对象参与回收。泛型字段、成员调用及静态类型界限已确定的标量可以拆箱。泛型调用按声明的表示传值，具体化后的结果再转换；具体化为 void 的结果可以丢弃。构造调用支持参数表示转换和运行时类类型实参，在分配、初始化和嵌套回收期间保留实参。类环境按实际接收者的继承关系代入，factory 接收请求的类类型；泛型字段写入在检查实际字段类型成功后才修改存储。见[类环境与 SDK 对照](../test/compiler/class_types_test.dart)和[字段检查验证](../test/codegen/dynamic_boxes_native_test.dart)。late/late final 字段使用独立绑定位，支持实际泛型检查、惰性初始化及 GC 存活，见[实例存储](variables.md#原生局部存储)。跨模块常量身份统一和完整源码类的原生执行仍是缺口。此处的 IR 原生路径不表示上表的全部行为已能生成机器码。

普通类的原生方法、getter/setter 和运算符按实际接收者选择实现，支持抽象接口、继承与 mixin；super 保留直接选择的实现。省略参数采用实际实现的默认值，命名实参保持源码求值顺序。协变形参和方法类型实参按接收者的实际类环境检查，失败在执行方法体前抛出 TypeError；检查与方法体共享 catch/finally 清理路径。返回值在声明表示与调用方表示之间转换，装箱值参与回收。见[原生成员调用与 SDK 对照](../test/compiler/member_calls_test.dart)。

原生成员选择限于同一封闭程序中构造或常量提供的类实例；不接收其他模块提供的托管对象。runtimeType 重写及 Type 相等见[类型行为范围](types.md#原生泛型调用与-type-值)，方法提取、Never 形参及 void 返回视图见[函数](functions.md)。其余 Object/Type 成员及 dynamic/noSuchMethod 仍有缺口，尚未提供完整的原生类调用支持。

同步原生入口内支持对象分配与不可达对象回收，保留引用别名及循环引用。含引用全局槽的模块跨入口保留堆，同模块、同线程的同步原生回调重入共享堆及 GC 根，包括暂停的外层栈帧。没有引用全局槽时，入口及重入仍使用各自的独立堆，返回即释放。持久堆在 dartc 链接的共享库卸载时释放，独立程序退出前显式释放，见[模块清理与卸载](libraries.md#模块清理与卸载)。并发调用、跨线程调用、跨模块托管值 ABI 及异步执行尚未实现。同步异常传播与清理见[原生异常范围](statements.md#原生异常与清理)。分配失败目前仍作为未捕获错误终止进程；可捕获的 `OutOfMemoryError` 尚未实现。

[布局契约](../test/layout/object_layout_test.dart)、[常量身份与表示检查](../test/codegen/object_values_test.dart)和[原生对象引用验证](../test/codegen/object_values_native_test.dart)覆盖字段、具体类型身份、嵌套引用、寄存器与栈参数、调用保存、循环交换及 null。

实参已确定的泛型类、继承与接口可用于原生 `is`、`is!` 和类型化异常捕获，见[原生类型判断范围](types.md#原生类型判断与空安全)。

[标量装箱验证](../test/codegen/boxed_values_native_test.dart)覆盖 int 边界、负零、次正规数、无穷及不同 NaN 载荷，检查泛型字段、成员返回、引用栈参数和循环中的精确值，以及 bool 装箱与各类传值位置的拆箱。

[计算结果装箱验证](../test/codegen/dynamic_boxes_native_test.dart)覆盖数值的参数、返回、分支、局部和字段传递，以及连续装箱和调用期间回收后的存活值；[可空数值源码验证](../test/compiler/numeric_boxes_test.dart)检查可空返回、计算结果及未选择分支的行为。

[托管对象验证](../test/codegen/managed_heap_native_test.dart)覆盖存活链、循环引用、嵌套构造、栈参数及原生重入；[源码构造验证](../test/compiler/managed_objects_test.dart)检查构造器副作用、浮点返回值、独立程序与分配失败。

## 规范依据

[主规范 §10–§16](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[类修饰符](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/class-modifiers/feature-specification.md)、[主构造器](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.13/primary-constructors/feature-specification.md)、[构造器提取](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.15/constructor-tearoffs/feature-specification.md)、[增强枚举](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.17/enhanced-enums/feature-specification.md)。

Typed forwarder 的 Invocation 与动态缺失回退及公开工厂分开建模：成员/命名键使用规范化 Symbol，命名实参按声明顺序排列；空位置列表为 const<dynamic>[]，命名 Map 每次创建，集合不可修改。沿用 SDK 3.13.7 的可观察身份，不将其声明为跨 SDK 保证。见[转发样本](../test/frontend/lowering/fixtures/typed_forwarders.dart)。

跨库私有转发通过真实 SDK NoSuchMethodError.withInvocation 工厂和普通 Throw 构造错误，保持类型检查先于函数体、错误身份和异常传播。派发选择器保留原声明库，生成错误的 Invocation Symbol 按 SDK 3.13.7 使用目标体所属库；动态错误形状回退仍使用调用选择器身份。多个库的同名私有成员可以共存。见[跨库转发样本](../test/frontend/lowering/fixtures/private_forwarders.dart)。
