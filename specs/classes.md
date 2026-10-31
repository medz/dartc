# 类及相关声明：§10–§14、§16

按[固定草案源码](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)建立索引；条款目录见[官方草案 PDF](https://dart.dev/to/spec-draft)。
SDK 对照版本见[总览](README.md)；§15 泛型和 §20 类型关系另见[类型追踪](types.md)。
字段的空安全初始化约束还依据[空安全补充][nnbd]，不能只用旧草案章节判定兼容。

## 类与成员语法表示

`package:dartc/ast.dart` 可构造以下声明语法。构造器检查源码范围、快照归属及子节点顺序，不解析文本或执行语义检查。

| 语言条款 | 可表示的语法 | 验证 |
| --- | --- | --- |
| §10 类、[类修饰符][class-modifiers] | 元数据、有序修饰符、名字、类型参数、`extends`、`with`、`implements` 和有序成员；区分 `{}` 与 `;`，不补入隐式父类或构造器 | [classes_test.dart](../test/ast/classes_test.dart) |
| §12 Mixins | mixin 的 `base`、类型参数、`on` 约束、接口及成员；具名 mixin application 的 `class C = B with M;` 形式 | [classes_test.dart](../test/ast/classes_test.dart) |
| §10.2–§10.8 成员 | 实例及静态方法、泛型方法、getter、setter、运算符和字段；保留 `external`、字段的 `abstract` / `covariant` 及共享变量声明，不生成隐式访问器 | [members_test.dart](../test/ast/members_test.dart) |
| §10.7 构造器 | 传统及 `new` / `factory` 简写、`const`、`external`、形参、有序字段初始化、assert、super 调用和 this 重定向；factory 的表达式/块体与 `=` 重定向分别保留 | [constructors_test.dart](../test/ast/constructors_test.dart) |
| [主构造器][primary] | 类头的 `const`、可选名称及声明/初始化/普通参数；类体中单独出现的 `this` 初始化列表与函数体，不展开声明参数或移动成员 | [classes_test.dart](../test/ast/classes_test.dart)、[constructors_test.dart](../test/ast/constructors_test.dart)、[parameters_test.dart](../test/ast/parameters_test.dart) |
| §14 Enums、[增强枚举][enhanced-enums]、[主构造器][primary] | 枚举头、类型参数、mixin、接口、常量与成员；常量保留元数据、类型实参、构造器后缀及省略或显式的实参列表。区分 `{}`、`{;}` 与 `;`，不补入隐式 `const`、构造器或枚举成员 | [enums_test.dart](../test/ast/enums_test.dart) |
| §13 Extensions、[主构造器语法更新][primary] | 具名及匿名 extension、类型参数、`on` 类型、成员和分号体；函数、记录及可空类型均可作为接收者类型。显式应用保留为未绑定的调用与成员访问 | [extensions_test.dart](../test/ast/extensions_test.dart) |
| [Extension types][extension-types]、[主构造器][primary] | extension type 的名字、类型参数、`const`、构造器后缀、表示参数、接口与成员；保留参数元数据和显式修饰符，不生成表示字段 | [extensions_test.dart](../test/ast/extensions_test.dart) |

名称绑定、继承关系、成员冲突、修饰符合法性、初始化规则及 extension 适用性尚未接入这些节点。结构可表示不代表声明合法，例如 extension type 的 `var` 表示参数或多个表示参数仍需诊断。文本解析支持见下文；编译与执行支持以下表为准。

## 类与成员解析

`parseCompilationUnit` 可解析下列声明。类、构造器和成员保留写出的类型与名称，不添加隐式字段、构造器或父类。

| 语言条款 | 当前解析支持 | 验证 |
| --- | --- | --- |
| §10、§11、§12 类、mixin、enum | 修饰符组合、类型参数、extends/with/implements/on、具名 mixin application；enum 常量的元数据、类型实参、构造器后缀及实参 | [type_declarations_test.dart](../test/parser/type_declarations_test.dart) 声明头与 enum 用例 |
| Extension、extension type | 具名或无名 extension、on 类型；extension type 的主构造器、表示参数与 implements | [type_declarations_test.dart](../test/parser/type_declarations_test.dart) extension 用例 |
| 类成员 | 字段、方法、getter/setter、可重载运算符、类型参数、元数据和函数体；保留字段与 setter 的 covariant | [type_declarations_test.dart](../test/parser/type_declarations_test.dart) 成员用例 |
| 构造器 | 普通、const、factory、命名及简写构造器；字段／断言／super 初始化、this 重定向和 factory 等号重定向 | [type_declarations_test.dart](../test/parser/type_declarations_test.dart) 构造器用例 |
| 主构造器与空体 | 类、enum 和 extension type 的主构造器参数；类体中的 this 初始化与实现体；分号声明体 | [type_declarations_test.dart](../test/parser/type_declarations_test.dart) 主构造器用例 |

修饰符、构造器体及初始化形式包含语法检查；字段绑定、继承关系、成员冲突、参数类型和表示类型资格需要后续分析。方法和初始化表达式仍受[表达式](expressions.md#表达式解析-api)、[语句](statements.md#语句解析-api)中列出的解析缺口约束。缺失成员用 `MissingClassMember` 恢复；损坏输入验证见同一测试文件。

## 编译与执行

| 规范条目 | 状态 | 支持范围与缺口 | 验证 |
| --- | --- | --- | --- |
| §10 类声明 | 部分实现 | 支持普通类、泛型类和 abstract 类，以及非泛型父类的 extends / implements 列表；按声明身份解析接口及类型别名，检查重复接口与环；接口使用的别名边界在图检查后验证，直接表示自身类型参数的别名不能作为接口。Function 仍不能作类名。泛型构造、成员和运行时检查的当前范围见[下文](#泛型运行时实例)；类修饰符见下行。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `interfaceValues()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `rejected` |
| [Dart 3.0 类修饰符][class-modifiers] | 部分实现 | 普通类支持 base、interface、final、sealed 与合法 abstract 组合；sealed 隐含抽象。按实际声明所属库检查跨库 extends/implements，base/final 的实现禁令和后代修饰要求沿整个父接口图传递；别名、导出及 part 不能改变所属库。旧于 3.0 的库不能声明修饰符；对平台库保留规范规定的 base/interface/final 限制豁免，sealed 无豁免。枚举满足后代修饰要求，其独立的不可继承/实现规则不变。mixin、mixin class、mixin application 及泛型父接口仍缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `classModifierValues()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `modifier-imports.dart`、`rejectedClassModifiers` |
| §10.1 完整实现接口 | 部分实现 | 用户类收集非泛型父接口的实例签名，读取、写入与方法分别处理；具体类必须声明或继承兼容实现，implements 不继承方法体或字段存储。检查包含未使用类；Object 默认 toString 可满足对应接口。noSuchMethod 转发、其余 Object 默认成员和完整内建接口仍缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `interfaceValues()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `interface-imports.dart`、`rejected` |
| §10.2 实例方法 | 部分实现 | 支持已知类 receiver 的方法调用、递归、泛型直接调用和非泛型方法的值提取（含可选位置和命名参数）。接口调用按实际对象选择实现，省略参数使用该实现的默认值，实参仍按源码顺序求值。覆写检查参数形状、参数逆变、结果协变及泛型边界；可从合并后的父签名推断省略的注解。支持继承实现和直接 super 调用；一般 dynamic 查找尚缺；协变参数规则见[函数](functions.md)，函数值边界见[函数](functions.md#函数值)。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `interfaceValues()`、`inheritanceValues()`（父类、覆写子类与继承叶类混合调用及方法值）、`Box.arguments()`、`Box.recurse()` |
| §10.2.1 用户运算符 | 部分实现 | 支持普通及泛型类的 `operator` 声明：二元 `+ - * / ~/ % < > <= >= << >> >>> & \| ^`、一元 `-`（记为 `unary-`）与 `~`、`[]` 及 `[]=`。声明检查固定参数个数（只能是必需位置参数）、`[]=` 返回类型展开别名后必须为 void、不得 static 或带类型参数，`!`、`!=` 不可定义。左操作数为非空类类型时，二元、一元、索引读写、复合赋值及 `++`/`--` 都调用相应的运算符方法，支持子类覆写，实参按声明参数类型求值。索引读写保留原始索引值，分别检查和转换；复合赋值及 `??=` 的索引上下文来自读取参数，求值时序见[索引赋值](expressions.md#索引赋值)。上界为类的类型参数接收者，以及 `super + x`、`-super`、`super[i]`，同样调用对应实现。`super[i]` 支持简单、复合、`??=` 赋值及前后增减，读写分别选择词法父类的具体实现，包括继承链和捕获 super 的闭包，不调用子类覆写；缺少所需具体运算符仍诊断。`operator ==` 尚未实现；泛型父接口的运算符类型代入仍缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `operatorValues()`、`operatorIndexing()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `rejectedOperators`、`failingValues` |
| §10.2.2 `noSuchMethod` | 未实现 | 不生成 Invocation，也没有缺失成员动态转发。 | 待补充 |
| §10.2.3 `==` 与对象相等 | 部分实现 | 有基础值比较、引用身份及常量实例 canonical 身份；常量相等检查 primitive equality，覆写 `hashCode` 的类不能参与一般活跃常量相等求值，与 null 比较除外。用户覆写 `==` 及完整运行时契约未实现。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `objectValues()`、`constantLists()` |
| §10.3 Getter | 部分实现 | 支持实例、静态 getter 和接口属性读取；实现可由字段或显式 getter 提供。覆写时从合并后的父接口签名推断省略的返回类型，其余未注解 getter 为 dynamic。可读取并调用具体函数类型或[可调用对象](functions.md#可调用对象)结果；时序见[表达式](expressions.md)。继承时分别选择 getter 和 setter；只覆写一侧不会丢弃另一侧，复合赋值仍调用实际 getter。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `accessorValues()`、`interfaceValues()` |
| §10.4 Setter | 部分实现 | 支持实例、静态及接口 setter、仅写属性和独立的写入类型；实现可由可写字段或显式 setter 提供。结果只能省略或为 void（包括展开后为 void 的类型别名），且恰有一个必需位置参数；未使用的声明同样检查。覆写可从父接口签名推断参数类型，其余未注解参数为 dynamic。顶层访问器见[函数](functions.md)和[库](libraries.md)。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `accessorValues()`、`interfaceValues()`、`operatorIndexing()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `rejected`、`rejectedOperators` |
| §10.5 抽象实例成员 | 部分实现 | abstract 类可声明无体实例方法和访问器，或保留尚未实现的接口成员；具体类不能保留这些义务。抽象类的生成式构造（包括 const）不能直接实例化，包括未执行代码和常量死分支；有体成员仍检查其全部静态义务。工厂构造可返回具体实现；抽象字段见下行，外部成员尚缺。 | [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `rejected` |
| [Dart 2.12 抽象字段][abstract-fields] | 部分实现 | 非泛型类支持 abstract 类型/var/final 字段、多变量声明及 covariant 可写字段；不分配存储或要求构造初始化。先按字段规则从父接口推断一个共同类型，再展开为无体 getter 及可选 setter；可写字段的父读写类型必须一致，无约束时为 dynamic。元数据关联两个访问器，协变标记传给 setter，并沿继承传播。沿用私有库身份、接口义务、具体实现继承、const 父构造及 super 访问检查；拒绝初始化器、late/static/const/external 组合、构造初始化及旧于 2.12 的声明。泛型类的范围见下文；mixin 和外部字段仍缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `abstractFieldValues()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `interface-imports.dart`、`rejectedAbstractFields`、`failingValues` |
| [§10.6 实例变量][instance-variables] | 部分实现 | 普通字段支持[覆盖推断][field-inference]：从父接口的 getter/setter 组合签名确定类型，初始化表达式使用该类型作为上下文；没有接口约束和声明初始化器时取 dynamic，不从构造器赋值反推。非主构造器类中，未覆盖字段可从字面量、常量引用、已有常量类型运算（含 `as`/`is`/`is!`）、List、函数 tear-off 和直接构造表达式推断；Null 推为 dynamic，构造实参及字段表达式仍在原初始化时机执行。普通函数调用、实例成员依赖及主构造器字段初始化器的独立推断仍缺；主构造器声明参数保留既有推断。支持字段存取及函数值、可调用对象字段的类型化调用；final 字段存储不可直接再写，可与显式 setter 配对；可空 final 也必须初始化，const 实例字段被拒绝。`late` 字段见[变量](variables.md)。支持[显式 covariant 字段][covariant-fields]，协变标记只影响隐式 setter，getter 的结果协变规则不变；无初始化器的 late final 字段有 setter，也可带该标记。完整初始化形式仍缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `Plain`、`accessorValues()`、`finalContexts()`、`interfaceValues()`、`covariantValues()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `rejected`、`rejectedFieldInference`、`rejectedCovariant`、`failingValues` |
| [§10.7.1 生成式构造][generative-constructors] | 部分实现 | 支持未命名、命名生成式构造及[字段初始化列表][initializer-lists]；只有完全未声明构造器的类才获得缺省无参构造。非重定向构造的声明初始化、字段形参与显式列表共用初始化计划；先按字段声明顺序执行声明表达式，再按参数顺序执行字段形参，再按源码顺序执行显式列表；随后在同一对象上执行父类构造链，成功后进入本类构造器体；体内只能使用无值 return。列表目标只允许本类直接字段，初始化 final 字段不经过同名 setter；检查缺失、重复及类型兼容。支持显式或隐式 super 调用，显式调用必须唯一且位于列表末尾，参数按源码顺序求值；assert initializer 仍缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `constructorInitializers()`、`namedConstructors()`、`inheritanceValues()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `rejected`、`failingValues` |
| [§10.7 构造器名称][constructor-names]、[2.15 `.new` 别名][new-alias] | 部分实现 | 经类名或用户类别名按实际类声明身份及后缀选择构造器，泛型实参参与形参和结果类型代入，别名链不创建独立构造器或常量身份；构造器名称不进入普通成员作用域，可与实例方法同名；私有后缀按[库身份][privacy]检查，包含 part。`.new` 与未命名构造器为同一身份，声明和调用都要求至少 2.15；重复声明被拒绝。支持前导 `new` 的直接构造调用及[构造器函数值](#构造器函数值)。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `namedConstructors()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `named-constructors-imports.dart`、`rejected` |
| [Dart 2.17 super 形参][super-parameters] | 部分实现 | 非泛型类的非重定向生成式构造支持位置、可选及命名 super 形参。位置关联只计 super 形参；命名关联使用父构造器的公共参数名。父类优先推断类型，显式类型须是对应形参类型的子类型，不接受 dynamic 下转型或隐式 call 提取代替。无显式默认值时，在父默认常量的实际类型兼容的前提下继承，保留父声明作用域；否则使用隐式 null 并检查本参数类型。检查显式 super 实参与转发冲突、缺失参数、声明位置和 2.17 版本边界；支持函数形式及位置通配形参。支持主构造器中的转发；3.13 之前的 final 形参修饰符已支持，版本规则见[函数](functions.md)；泛型父类的类型代入仍缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `inheritanceValues()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `inheritance-imports.dart`、`rejected`；[roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart) `DerivedWide` |
| [§10.7.1 生成式重定向][redirecting-generative] | 部分实现 | `this(...)`、`this.name(...)`、`this.new(...)` 转发到本类生成式构造器，共用同一实例；转发参数先求值，只有最终目标执行字段初始化与体。每级独立绑定参数和默认值；禁止字段或 super 形参、其他 initializer 或体共存，并在声明边界检查未使用的重定向环。const 转发要求 const 目标和 potentially constant 的转发表达式，不放宽嵌套 const 的参数资格；最终类及字段值决定 canonical 身份。重定向目标继续执行其父类构造链；目标不能是工厂构造器。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `namedConstructors()`、`RedirectOrder`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `named-constructors-imports.dart`、`redirect-finite-constant.dart`、`rejected`、`failingValues` |
| [§10.7.1 形参初始化作用域][initializer-scope] | 部分实现 | 初始化列表可读取字段及 super 形参的声明名，其局部值为 final，且不进入构造器体作用域；普通参数在列表和体中共享变量，列表中的合法赋值对后续初始化和体可见。RHS 及其闭包不允许读取 this 或隐式实例成员；支持初始化器闭包捕获普通、字段及 super 形参，见[词法捕获](functions.md#词法捕获)。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `InitializerOrder`、`InitializerPrivate`、`SuperScope`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `rejected` |
| [§10.7.2 Factory][factories] | 部分实现 | 非泛型类支持块体、箭头体、命名及未命名工厂、重定向和 const 工厂；调用、默认值及静态义务见[工厂构造器](#工厂构造器)。支持 3.13 简写，并保留旧语言版本的同名普通方法解析。支持非泛型工厂函数值；泛型类及 external 工厂尚缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `factoryValues()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `inheritance-imports.dart`、`factory-method-312.dart`、`factory-private.dart`、`rejected`、`failingValues`；[roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart) `WideOwnFields` |
| [§10.7.3 常量构造器][constant-constructors] | 部分实现 | 支持未命名及命名生成式 const 构造，包括泛型类，字段须全部 final 并各初始化一次，构造器无体。默认值与字段声明初始化使用声明作用域；显式字段列表按构造实参求值，并在声明边界检查 potentially constant 资格，不将整个列表误作隐式 const 上下文。[实际类及字段负载][canonical-objects]决定规范化身份，同类不同构造器也可得到同一常量；普通调用仍创建新实例。实例可用于普通程序、嵌套 List、默认值及注解。显式或隐式 super 目标须为 const 构造器，未使用的声明也检查这一义务；规范化身份包含继承字段和本类字段。const 工厂按最终目标创建常量；assert initializer 仍缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `constObjects()`、`constructorInitializers()`、`namedConstructors()`、`inheritanceValues()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `libraries`、`rejected` |
| [§10.8 静态方法][static-methods]及静态字段 | 部分实现 | 支持普通及泛型类的静态方法、getter/setter、可变/final/const 字段，静态成员不能使用类类型参数；类内未限定访问、类或类型别名（含可空别名）限定访问、库前缀及 part 私有性按声明身份解析。静态体没有 this，不能隐式读取实例成员，也不能经实例选择静态成员。静态字段支持惰性初始化及常量值，不参与实例初始化。静态泛型方法支持[直接调用](functions.md#泛型直接调用)；非泛型类中的非泛型方法可作为函数值及常量引用，保留必需、可选位置和命名参数签名。静态成员不被子类继承；泛型类中的方法提取及完整 Object 语义仍缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `staticMembers()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `static-members-imports.dart`、`rejected` |
| [§10.9–10.10 继承与父接口][superclasses] | 部分实现 | 用户类的非泛型父类 extends 与 implements 参与传递子类型、接口成员及覆写检查；显式 extends 与 implements 不能重复同一类型。extends 继承实例实现与字段，子类同名字段仍有独立存储；私有名称按库区分。super 从词法所属类的父类查找具体实现，忽略抽象声明，并保留原 this；闭包可捕获该接收者。泛型父接口的实参代入、mixin 及 noSuchMethod 转发仍缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `inheritanceValues()`、`interfaceValues()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `inheritance-imports.dart`、`rejected`；[roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart) `DerivedWide` |
| [§10.11 类成员冲突][member-conflicts] | 部分实现 | 在声明边界绑定本类字段、方法和访问器，拒绝重复声明、方法与访问器冲突、可写字段与显式访问器冲突；允许 getter/setter 配对，final 实例/静态字段及 const 静态字段可配显式 setter。静态声明不能与本类实例成员、同名构造器后缀或绑定 core Object 的实例接口名冲突；继承的实例签名也参与冲突检查；覆写检查见 §11。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `accessorValues()`、`staticMembers()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `rejected` |
| §11 接口及组合成员签名 | 部分实现 | 按[接口继承][interface-inheritance]收集可见签名；[组合签名][combined-signatures]选择类型最具体且满足其他候选的声明，同等候选按接口顺序选择。没有组合签名时，需要足够显式的兼容覆写；不能将失败的覆写推断退成 dynamic。[覆写][member-overrides]保留泛型参数身份和形状检查。协变参数标记按全部候选合并，规则见[函数](functions.md)。泛型类的参数运行时检查见下文；完整类型规范化仍缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `CombinedInterface`、`InferredArithmetic`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `rejected` |
| §12 Mixins | 未实现 | 无 mixin 声明、约束或应用展开。 | 待补充 |
| §13 Extensions | 未实现 | 无 extension 声明、适用性、优先级及显式调用。 | 待补充 |
| §14 Enums、[增强枚举][enhanced-enums] | 部分实现 | 支持无类型参数、无 mixin 的简单与增强枚举：值、可选 implements、字段、命名与重定向的 const 生成式构造、工厂构造、静态成员、方法与访问器，以及 `values`、`index`、`name` 和默认 `toString`（`枚举名.值名`）。生成式构造隐含 const，不能有体，实例字段须 final；实例只能由枚举自己的值创建。声明 `index`、`values`、`hashCode` 被拒绝。`Enum` 是核心库接口，只有枚举和抽象类可以实现。switch 按枚举值求覆盖，Dart 3 文件中的 switch 语句须穷尽。SDK 经 `EnumName` 扩展提供 `name`，这里它是 `Enum` 的接口成员，所以声明同名成员的枚举（例如值名为 `name`）被拒绝，待 §13 extension 支持后对齐。类型参数、mixin、用户 `==` 及 `Enum` 的扩展辅助尚缺。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `enumValues()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `rejectedEnums` |
| §16 Metadata | 部分实现 | 解析并附着声明注解，校验 const-variable 引用身份，支持标量、List、null 及已实现构造子集的类实例；按外围声明作用域、局部绑定及库前缀/导出过滤解析。支持已实现 const 构造器的注解调用，包含 2.14 起的显式类型实参、一般实参推断和泛型 const 身份；具体范围见下文。支持真实 core `pragma` 的 name/options 常量值。其他 core 注解与运行时注解访问尚缺；动态反射不在项目支持范围内。 | [values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) `metadataValues()`；[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) `libraries`、`rejected` |

未注解字段按实际读写能力组合父签名：只有 getter 的 final 字段取 getter 结果类型；可写字段若同时继承 getter/setter，两侧类型必须相同。无初始化器的 late final 字段也有 setter，遵循同样的组合约束。构造器字段形参在字段类型确定后推断或检查显式子类型，必需初始化义务同样使用最终类型。独立初始化器推断使用[声明依赖规则][declaration-inference]中的可用类型；支持常量表达式与构造结果的类型推断，普通字段仍在初始化时求值，可变 List 保持可变。一般非恒定声明的依赖图和推断环诊断仍缺。

## 元数据语法表示

`package:dartc/ast.dart` 可表示 §16 的常量引用注解、限定名称、显式类型实参、构造器后缀和调用实参。名称的各部分保留原始拼写；前缀、类型与成员的绑定，以及实参的常量资格尚未检查。验证见 [nodes_test.dart](../test/ast/nodes_test.dart) 的注解实参和类型参数元数据用例。

注解可附在[类及相关声明](#类与成员语法表示)、成员、函数声明、变量声明、形参、类型参数及记录类型字段上。[形参解析](functions.md#形参解析-api)已接入形参元数据；其他位置的文本解析和常量检查尚未接入。编译器的元数据行为见下文的[泛型 const 类与注解](#泛型-const-类与注解)。

## 工厂构造器

[普通工厂][factories]以所属类为返回类型，可以返回已有对象或子类实例。体内没有 this 或隐式实例接收者；普通参数及其词法捕获沿用函数绑定。返回与正常落空按[空安全][nnbd]检查，来自 dynamic 的值保留运行时检查。工厂不执行所属类的字段初始化，也不隐式分配该类对象。只有工厂而无生成式构造的类仍须满足字段声明的初始化义务；未调用的工厂体、默认值和初始化表达式同样检查。

[重定向工厂][factory-redirects]按类或别名的声明身份解析目标，支持库前缀、命名构造器、`.new` 和私有性检查。目标签名须是工厂签名的子类型；在声明处检查循环、显式默认值、const 资格及抽象生成式目标。实参按源码顺序、原工厂参数上下文求值并检查一次，只转发实际提供的实参，最终目标在自己的声明作用域补默认值。目标可有额外可选形参。`super` 调用和生成式 `this` 重定向不能选择工厂。

const 工厂只能重定向到 const 构造器，允许声明在抽象类以及拥有可变或 late 字段的类中；字段约束施加于最终生成式目标。常量的静态类型来自调用的类，规范化身份来自实际类和字段负载，经过别名或重定向仍与直接构造相同。经可空类别名的构造结果为非空。普通调用不会因目标声明了 const 而自动规范化。

固定草案还要求目标默认值的类型是工厂对应形参类型的子类型；SDK 3.13.7 的 CFE 与 analyzer 均接受 `factory C([int n]) = D` 转发到 `D([num n = 4.5])`。dartc 跟随 SDK：省略参数时使用 4.5，显式实参仍按 int 检查；普通和常量调用由 `factoryValues()` 验证。可捕获的运行时类型错误仍是[异常语义缺口](statements.md)，不能把当前失败退出当作完整异常实现。

## 泛型 const 类与注解

依据 [§15 类型参数和作用域][type-parameters]、[常量身份][canonical-objects]和 [Dart 2.14 泛型 metadata][generic-metadata]，泛型类具有独立参数身份与上界，const 实例保留实际类型实参。同一类、同一实参和相同字段值才共享常量身份；同类参数协变参与编译期 `is`/`as` 和共同类型计算。支持字段类型中的类参数、普通及生成式重定向 const 构造、显式实参、已实现类型模型下从参数及上下文推断、类别名和库前缀。静态成员不能使用类参数；无效上界、实参、初始化器及 metadata 在未使用声明中也检查。

这些对象可用于编译期常量计算、普通 metadata 和运行时表达式；运行时物化保留实际类型参数及常量身份。调用库从 3.7 起使用[基于界限的推断](functions.md#基于界限的推断)，包括经类别名及跨库调用的构造；完整 Dart 约束求解仍缺。

验证：[values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) 的 `metadataValues()`，以及 [behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `generic-metadata-imports.dart`、`bounds-3.6.dart` / `bounds-3.7.dart`、`rejectedGenericMetadata`；覆盖常量身份、字段实参、推断、别名/前缀/跨库私有性、版本边界与未使用声明。

## 泛型运行时实例

依据[泛型生成式实例创建][generic-instance-creation]和[类类型参数作用域][type-parameters]，普通、隐式、命名、生成式重定向及主构造器保存实际类类型实参。实参和上下文推断与泛型直接调用共用约束求解；类别名、库前缀、导出及 part 保持同一声明身份。形参代入后按源码顺序求值、检查，成功后分配新实例并执行初始化。`T` 字段不能因其上界允许 null 而省略初始化；`T?` 字段可以使用隐式 null。

字段、非泛型实例方法、getter/setter、`call` 和已支持的运算符按接收者的静态类型替换类参数；方法体、类型测试和捕获闭包使用对象实际的类型环境。支持嵌套类、List、可空和函数类型，以及类型实参逐层增长的递归构造。`is`/`as` 比较同一类的实际实参，遵守类参数协变；可使用非泛型父类和接口，仍沿用其覆写与分派规则。

[由类参数产生的协变检查][covariant-by-class]在进入实例成员前按实际对象的实参检查相关形参，包含隐式字段 setter 与索引写入。读取函数类型等不安全的协变视图时也执行所需检查。这一性质不授予收窄覆写形参的权限：[正确覆写][override-covariance]仍要求显式或继承的 `covariant` 声明。未使用的非法覆写同样拒绝。

泛型类的工厂构造、late 字段、自身再声明类型参数的实例方法、方法及构造器提取、泛型父接口代入、完整 F-bound 和其余约束求解仍缺；相关构造入口明确诊断。泛型对象模式可从匹配值推断省略的实参，具体范围及测试见[模式](patterns.md)。默认对象文本目前不显示具体类型实参；公开 `Type` 值和完整模式推断仍缺。这些缺口不改变完整 Dart 兼容目标。

验证：[values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) 的 `runtimeGenericClasses()`、[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `runtime-generics-imports.dart` 和 `rejectedRuntimeGenerics`；[roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart) 的 `genericTypeRoots()` 验证实例类型环境、常量物化和捕获闭包的 GC 存活。

## 构造器函数值

依据 [Dart 2.15 构造器提取规范][constructor-values]，非泛型用户类的生成式、工厂、生成式重定向及重定向工厂可通过 `C.new` 或 `C.named` 提取。支持必需、可选位置和命名形参、括号后的函数值调用、`.call`、类型检查、参数默认值与常量容器。普通非泛型类别名及可空别名指向同一构造器，函数结果类型为非空类。构造器不会因继承产生新成员；抽象类的生成式构造器不能提取，工厂可以。提取检查 2.15 版本和库私有性，未使用函数及常量死分支也检查。

构造器引用是常量，无须目标声明为 const；同一构造器的引用规范化为同一函数对象。不同声明的生成式重定向或工厂引用保留不同身份。提取 const 构造器后调用仍是普通函数调用，不能作为常量构造。SDK 3.13.7 的 CFE 对未选中分支中的 `(C.new)()` 跳过这项错误，analyzer 仍报告 `const_initialized_with_non_constant_value`；dartc 保留直接常量构造的资格要求，拒例单独标注。常量模式支持 `const (C.new)`；上下文类明确时也支持 SDK 接受的 `.new` 模式。

公开函数签名保留原构造器的参数类型和所属类结果；生成式调用在实参求值后分配对象并执行初始化，工厂不隐式分配。重定向工厂只转发显式实参，最终目标补默认值及额外可选参数，包含原签名参数较窄而目标默认值较宽的 SDK 行为。类型推断在使用构造器签名前完成关联字段及 super 形参类型，包含以构造器引用作为主构造器声明参数默认值的前向引用。

泛型类、泛型类别名的构造器函数值，以及标准库构造器提取尚缺。动态函数调用沿用[函数值缺口](functions.md#函数值)。这些是实现缺口，不限制完整语言目标。

验证：[values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) 的 `constructorValues()`、[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `named-constructors-imports.dart`、`rejectedConstructorValues` 和 `failingValues`；根验证由 [roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart) 的 `ConstructorArgumentRoots` 与 `WideOwnFields` 覆盖。

## 主构造器

依据 [Dart 3.13 特性规范][primary]，普通及泛型类支持命名、未命名和 const 主构造器，声明字段的 var/final 参数、普通参数、this/super 形参、默认值及 this 初始化列表/体。类体可写为分号，生成式构造器可使用 new/new name 简写。以上语法检查 3.13 版本边界。

声明参数省略类型时，先按[字段覆写推断][field-inference]合并父接口签名；可写字段继承的 getter 与 setter 类型必须一致。无继承来源时采用默认表达式的空上下文静态类型，缺省或 Null 转为 Object?。非 late 字段初始化与列表共用参数作用域，并禁止参数赋值，包括嵌套闭包中的赋值。普通参数进入体后可写，先前闭包仍捕获同一变量；声明字段及 this/super 形参不进入体作用域。late/static 初始化不进入参数作用域。

const 主构造器的字段表达式按每次实参求值，并在声明处检查 potentially constant 资格。检查重复体、额外非重定向生成式构造、重复字段及重复初始化。[协变字段声明参数][covariant-declaring]必须写为 covariant var，标记转移到生成的字段，不留在构造器形参上；支持已有的类型推断和函数形式参数。泛型父类、assert initializer、mixin、enum 与 extension type 的相关能力仍缺。

验证：[values.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/values.dart) 的 `primaryConstructorValues()`、`covariantValues()`，[behavior_test.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/behavior_test.dart) 的 `inheritance-imports.dart`、`rejected`、`rejectedCovariant` 与 `failingValues`，以及 [roots.dart](https://github.com/medz/dartc/blob/c3394a9fb38107ccde2e200d744db96aea2c276f/test/legacy/fixtures/roots.dart) 的 `DerivedWide`。

## 支持边界

- 普通实例调用按实际类选择声明；super 按[成员查找][lookup]选择父类具体声明。Object 的默认 `toString()` 直接产生默认文本；普通格式化调用实际覆写的 `toString()`。一般 dynamic 调用、noSuchMethod 分派及 Object 默认方法的值提取仍缺。
- 读取、写入和方法调用分别选择对应声明；get/set 和 static 作为普通方法或字段名称仍按语法上下文区分。静态声明与自有实例成员、同名构造器后缀及绑定 core Object 的实例接口名冲突；其余 Object 默认成员仍缺。
- [抽象成员声明][abstract-members]只约束接口签名，不遮蔽继承的具体实现；无体 `toString()` 声明可继续使用 Object 的兼容实现。其他缺少具体实现的成员仍须由抽象类保留，或由具体类实现。

## 规范与 SDK 差异

[字段声明语法][covariant-field-syntax]只允许无初始化器的 covariant late final 字段。SDK 3.13.7 CFE 和 analyzer 接受 `covariant late final int x, y = 1;`，但拒绝首个字段带初始化器的同类声明。dartc 按固定草案逐字段检查 setter，拒绝前述形式；`covariantSyntaxDifferences` 单独验证这一差异。

Metadata 的资格与作用域依据固定草案 §16。analyzer 对 void 常量、常量属性访问及局部名字遮蔽的部分注解未报错，而 CFE 拒绝；不能据此认为注解有效，也不声称完整诊断一致。

局部 const 注解用于多变量声明时，SDK 3.13.5 analyzer 通过，而 CFE 在复制注解时崩溃；该形式仍按一般元数据声明规则处理，不把该崩溃解释为语言非法，也不推断上游是否已确认缺陷。

常量构造的有限重复依赖按具体默认值和字段表达式判定，不能把同一构造器再次出现直接视为循环。SDK 3.13.5 CFE 接受 `C([child = const C(null)])`，以及重定向实参中按参数终止的嵌套构造；analyzer 报告递归常量构造。dartc 按有限值依赖处理，实际值自依赖仍报错；声明资格检查不执行这些调用，诊断不保证一致。

[nnbd]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md
[instance-variables]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L3923
[generative-constructors]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L4038
[constant-constructors]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L4791

[initializer-lists]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L4279
[initializer-scope]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L4093-L4118

[constructor-names]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L3976-L4034
[new-alias]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.15/constructor-tearoffs/feature-specification.md#L279-L324
[privacy]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L1190-L1210
[canonical-objects]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L12592-L12611

[redirecting-generative]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L4171-L4277

[static-methods]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L4879-L4905
[member-conflicts]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L5219-L5260

[interface-inheritance]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L5314
[combined-signatures]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L5102
[member-overrides]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L5368
[abstract-members]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L3577-L3610

[superclasses]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L4908
[lookup]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L13880

[super-parameters]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.17/super-parameters/feature-specification.md

[primary]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.13/primary-constructors/feature-specification.md
[field-inference]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md#instance-field-getter-and-setter-override-inference

[factories]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L4245
[factory-redirects]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L4291

[constructor-values]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.15/constructor-tearoffs/feature-specification.md
[enhanced-enums]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.17/enhanced-enums/feature-specification.md
[extension-types]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.3/extension-types/feature-specification.md

[covariant-fields]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L3955-L3969
[covariant-declaring]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.13/primary-constructors/feature-specification.md#L919-L924
[covariant-field-syntax]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L2873-L2880


[declaration-inference]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md#L124-L179

[type-parameters]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L7380
[generic-metadata]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.14/small-features-21Q1/feature-specification.md#allow-type-arguments-on-annotations

固定类修饰符规范的 required-modifier 规则只针对 post-feature 库，因此 `// @dart=2.19` 用户类可直接继承另一用户库的 base 类而不声明修饰符；后续现代子类仍必须满足传递限制。SDK 3.13.7 CFE 与 analyzer 均拒绝这个旧版中间类，报 subtype_of_base_or_final_is_not_base_final_or_sealed。当前按固定规范实现该边界，`modifier-legacy-main.dart` 验证实际继承结果，`rejected-legacy-class-modifier` 验证后代限制；这组不是 SDK 等价性通过项。核心库的 Exception 为 abstract interface class，pragma 为 final class；平台库的旧版 interface/final 豁免由 `modifier-core-legacy.dart` 验证，现代库的非法继承/实现由 `rejectedClassModifiers` 验证。

[class-modifiers]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/class-modifiers/feature-specification.md#static-semantics

[abstract-fields]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/abstract-external-fields/feature-specification.md#static-analysis

[generic-instance-creation]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L12329-L12421
[covariant-by-class]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L2588-L2630
[override-covariance]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L5305-L5345
