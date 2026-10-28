# 类及相关声明：§10–§14、§16

按[固定草案源码](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)建立索引；条款目录见[官方草案 PDF](https://dart.dev/to/spec-draft)。
SDK 对照版本见[总览](README.md)；§15 泛型和 §20 类型关系另见[类型追踪](types.md)。
字段的空安全初始化约束还依据[空安全补充][nnbd]，不能只用旧草案章节判定兼容。

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §10 类声明 | 部分实现 | 支持非泛型普通类、abstract 类及 implements 列表；按声明身份解析接口及类型别名，检查重复接口与环；接口使用的别名边界在图检查后验证，直接表示自身类型参数的别名不能作为接口。Function 仍不能作类名。extends、泛型类及其余类修饰符尚缺。 | [ast.dart](../lib/src/ast.dart) `AstClass`；[frontend/classes.dart](../lib/src/frontend/classes.dart) `resolveClassInterfaces()`；[values.dart](../test/fixtures/values.dart) `interfaceValues()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §10.1 完整实现接口 | 部分实现 | 非泛型用户类收集父接口的实例签名，读取、写入与方法分别处理；具体类必须提供兼容实现，implements 不继承方法体或字段存储。检查包含未使用类；Object 默认 toString 可满足对应接口。noSuchMethod 转发、其余 Object 默认成员和完整内建接口仍缺。 | [frontend/classes.dart](../lib/src/frontend/classes.dart) `checkClassInterfaces()`；[values.dart](../test/fixtures/values.dart) `interfaceValues()`；[behavior_test.dart](../test/behavior_test.dart) `interface-imports.dart`、`rejected` |
| §10.2 实例方法 | 部分实现 | 支持已知类 receiver 的方法调用、递归、泛型直接调用和非泛型必需位置方法的值提取。接口调用按实际对象选择实现，省略参数使用该实现的默认值，实参仍按源码顺序求值。覆写检查参数形状、参数逆变、结果协变及泛型边界；可从合并后的父签名推断省略的注解。一般 dynamic 查找、extends 分派和协变参数尚缺；函数值边界见[函数](functions.md#函数值)。 | [frontend/classes.dart](../lib/src/frontend/classes.dart) `classSignatureSubtype()`；[frontend.dart](../lib/src/frontend.dart) `feGenerateDispatches()`；[values.dart](../test/fixtures/values.dart) `interfaceValues()`、`Box.arguments()`、`Box.recurse()` |
| §10.2.1 用户运算符 | 未实现 | 基础类型运算由 builtin lowering 处理，没有用户 `operator` 声明及分派。 | [parser.dart](../lib/src/parser.dart) `parserClass()`；[frontend.dart](../lib/src/frontend.dart) `feCombine()`；尚无用户运算符验证 |
| §10.2.2 `noSuchMethod` | 未实现 | 不生成 Invocation，也没有缺失成员动态转发。 | [frontend.dart](../lib/src/frontend.dart) `feLowerMemberCall()`；尚无验证入口 |
| §10.2.3 `==` 与对象相等 | 部分实现 | 有基础值比较、引用身份及常量实例 canonical 身份；常量相等检查 primitive equality，覆写 `hashCode` 的类不能参与一般活跃常量相等求值，与 null 比较除外。用户覆写 `==` 及完整运行时契约未实现。 | [runtime.dart](../lib/src/runtime.dart) `rtValueEq()`、`rtValueIdentical()`；[values.dart](../test/fixtures/values.dart) `objectValues()`、`constantLists()` |
| §10.3 Getter | 部分实现 | 支持实例、静态 getter 和接口属性读取；实现可由字段或显式 getter 提供。覆写时从合并后的父接口签名推断省略的返回类型，其余未注解 getter 为 dynamic。可读取并调用具体函数类型或[可调用对象](functions.md#可调用对象)结果；时序见[表达式](expressions.md)。extends 访问器继承尚缺。 | [members.dart](../lib/src/members.dart) `MemberBinding`；[frontend.dart](../lib/src/frontend.dart) `feCheckBoundMember()`；[values.dart](../test/fixtures/values.dart) `accessorValues()`、`interfaceValues()` |
| §10.4 Setter | 部分实现 | 支持实例、静态及接口 setter、仅写属性和独立的写入类型；实现可由可写字段或显式 setter 提供。结果只能省略或 void，恰有一个必需位置参数；覆写可从父接口签名推断参数类型，其余未注解参数为 dynamic。顶层访问器见[函数](functions.md)和[库](libraries.md)。 | [frontend/classes.dart](../lib/src/frontend/classes.dart) 签名核验；[frontend.dart](../lib/src/frontend.dart) `feLowerLvalue()`、`feWriteLvalue()`；[values.dart](../test/fixtures/values.dart) `accessorValues()`、`interfaceValues()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §10.5 抽象实例成员 | 部分实现 | abstract 类可声明无体实例方法和访问器，或保留尚未实现的接口成员；具体类不能保留这些义务。抽象类的生成式构造及 const 构造不能直接实例化，包括未执行代码和常量死分支；有体成员仍检查其全部静态义务。抽象字段、外部成员和工厂构造尚缺。 | [frontend/classes.dart](../lib/src/frontend/classes.dart) `checkClassInterfaces()`；[frontend.dart](../lib/src/frontend.dart) `feLowerConstructorCall()`；[constants.dart](../lib/src/constants.dart) 常量构造检查；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| [§10.6 实例变量][instance-variables] | 部分实现 | 要求字段显式类型，支持字段存取及函数值、可调用对象字段的类型化调用；final 字段存储不可直接再写，可与显式 setter 配对；可空 final 也必须初始化，const 实例字段被拒绝。`late` 字段见[变量](variables.md)；协变字段及完整初始化形式仍缺。 | [frontend.dart](../lib/src/frontend.dart) `feLowerLvalue()`；[initialization.dart](../lib/src/initialization.dart) `checkInitializers()`；[values.dart](../test/fixtures/values.dart) `Plain`、`accessorValues()`、`finalContexts()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| [§10.7.1 生成式构造][generative-constructors] | 部分实现 | 支持未命名、命名生成式构造及[字段初始化列表][initializer-lists]；只有完全未声明构造器的类才获得缺省无参构造。非重定向构造的声明初始化、字段形参与显式列表共用初始化计划；先按字段声明顺序执行声明表达式，再按参数顺序执行字段形参，最后按源码顺序执行显式列表，之后进入体。列表目标只允许本类直接字段，初始化 final 字段不经过同名 setter；检查缺失、重复及类型兼容。assert initializer、super 调用仍未实现并明确拒绝。 | [parser.dart](../lib/src/parser.dart) `parserInitializers()`；[initialization.dart](../lib/src/initialization.dart) `planConstructorInitializers()`；[frontend.dart](../lib/src/frontend.dart) 构造 lowering；[values.dart](../test/fixtures/values.dart) `constructorInitializers()`、`namedConstructors()`；[behavior_test.dart](../test/behavior_test.dart) `rejected`、`failingValues` |
| [§10.7 构造器名称][constructor-names]、[2.15 `.new` 别名][new-alias] | 部分实现 | 经类名或用户类的非泛型别名按实际类声明身份及后缀选择构造器，别名链不创建独立构造器或常量身份；构造器名称不进入普通成员作用域，可与实例方法同名；私有后缀按[库身份][privacy]检查，包含 part。`.new` 与未命名构造器为同一身份，声明和调用都要求至少 2.15；重复声明被拒绝。支持前导 `new` 的直接构造调用；构造器 tear-off 及其括号后函数值调用仍未实现。 | [members.dart](../lib/src/members.dart) `constructorSelector()`、`lookupConstructor()`；[frontend.dart](../lib/src/frontend.dart) 构造器选择；[values.dart](../test/fixtures/values.dart) `namedConstructors()`；[behavior_test.dart](../test/behavior_test.dart) `named-constructors-imports.dart`、`rejected` |
| [§10.7.1 生成式重定向][redirecting-generative] | 部分实现 | `this(...)`、`this.name(...)`、`this.new(...)` 转发到本类生成式构造器，共用同一实例；转发参数先求值，只有最终目标执行字段初始化与体。每级独立绑定参数和默认值；禁止字段形参、其他 initializer 或体共存，并在声明边界检查未使用的重定向环。const 转发要求 const 目标和 potentially constant 的转发表达式，不放宽嵌套 const 的参数资格；最终类及字段值决定 canonical 身份。工厂重定向及父类构造链尚缺。 | [initialization.dart](../lib/src/initialization.dart) `ConstructorPlan`、`checkConstructorRedirects()`；[frontend.dart](../lib/src/frontend.dart) 构造 lowering；[constants.dart](../lib/src/constants.dart) `checkConstantConstructors()`；[values.dart](../test/fixtures/values.dart) `namedConstructors()`、`RedirectOrder`；[behavior_test.dart](../test/behavior_test.dart) `named-constructors-imports.dart`、`redirect-finite-constant.dart`、`rejected`、`failingValues` |
| [§10.7.1 形参初始化作用域][initializer-scope] | 部分实现 | 初始化列表可读取字段形参的声明名，其局部值为 final，且不进入构造器体作用域；普通参数在列表和体中共享变量，列表中的合法赋值对后续初始化和体可见。RHS 及其闭包不允许读取 this 或隐式实例成员；支持初始化器闭包捕获普通参数和字段形参，见[词法捕获](functions.md#词法捕获)。 | [binding.dart](../lib/src/binding.dart) `bindFunctionLocals()`；[values.dart](../test/fixtures/values.dart) `InitializerOrder`、`InitializerPrivate`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §10.7.2 Factory | 未实现 | 无 factory 声明、重定向目标或返回实例规则。 | [ast.dart](../lib/src/ast.dart) `AstFunction`；[parser.dart](../lib/src/parser.dart) `parserClass()`；尚无验证入口 |
| [§10.7.3 常量构造器][constant-constructors] | 部分实现 | 支持非泛型、未命名及命名生成式 const 构造，字段须全部 final 并各初始化一次，构造器无体。默认值与字段声明初始化使用声明作用域；显式字段列表按构造实参求值，并在声明边界检查 potentially constant 资格，不将整个列表误作隐式 const 上下文。[实际类及字段负载][canonical-objects]决定规范化身份，同类不同构造器也可得到同一常量；普通调用仍创建新实例。实例可用于普通程序、嵌套 List、默认值及注解。工厂、继承、assert initializer 和 super 仍缺。 | [initialization.dart](../lib/src/initialization.dart) `planConstructorInitializers()`；[constants.dart](../lib/src/constants.dart) `ConstantConstructorInfo`、`checkConstantConstructors()`；[frontend.dart](../lib/src/frontend.dart) `feConstantGetter()`；[values.dart](../test/fixtures/values.dart) `constObjects()`、`constructorInitializers()`、`namedConstructors()`；[behavior_test.dart](../test/behavior_test.dart) `libraries`、`rejected` |
| [§10.8 静态方法][static-methods]及静态字段 | 部分实现 | 支持非泛型类的静态方法、getter/setter、可变/final/const 字段；类内未限定访问、类或类型别名（含可空别名）限定访问、库前缀及 part 私有性按声明身份解析。静态体没有 this，不能隐式读取实例成员，也不能经实例选择静态成员。字段复用惰性初始化和常量求值，实例布局及构造计划只含实例字段。静态泛型方法支持[直接调用](functions.md#泛型直接调用)；非泛型必需位置参数的方法可作为函数值及常量引用。继承、泛型类和完整 Object 语义仍缺。 | [ast.dart](../lib/src/ast.dart) `AstClass.staticFields`、`AstFunction.isStatic`；[members.dart](../lib/src/members.dart) `MemberBinding`；[frontend.dart](../lib/src/frontend.dart) `feReadStaticMember()`、`feLowerStaticMemberCall()`；[values.dart](../test/fixtures/values.dart) `staticMembers()`；[behavior_test.dart](../test/behavior_test.dart) `static-members-imports.dart`、`rejected` |
| §10.9–10.10 继承与父接口 | 部分实现 | 支持非泛型用户类的 implements 关系、传递子类型、接口成员与覆写检查；私有名称按声明库区分。extends、super、继承对象布局及构造链尚未实现，不能把接口关系当作实现继承。 | [frontend/classes.dart](../lib/src/frontend/classes.dart)；[types.dart](../lib/src/types.dart)；[values.dart](../test/fixtures/values.dart) `interfaceValues()`；[behavior_test.dart](../test/behavior_test.dart) `interface-imports.dart`、`rejected` |
| [§10.11 类成员冲突][member-conflicts] | 部分实现 | 在声明边界绑定本类字段、方法和访问器，拒绝重复声明、方法与访问器冲突、可写字段与显式访问器冲突；允许 getter/setter 配对，final 实例/静态字段及 const 静态字段可配显式 setter。静态声明不能与本类实例成员、同名构造器后缀或绑定 core Object 的实例接口名冲突；接口覆写检查见 §11；完整实现继承仍缺。 | [members.dart](../lib/src/members.dart) `MemberBinding`、`bindClassMembers()`；[symbols.dart](../lib/src/symbols.dart) `DeclarationSymbol.instanceMembers`；[frontend.dart](../lib/src/frontend.dart) `feCollectDeclarations()`；[values.dart](../test/fixtures/values.dart) `accessorValues()`、`staticMembers()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §11 接口及组合成员签名 | 部分实现 | 按[接口继承][interface-inheritance]收集可见签名；[组合签名][combined-signatures]选择类型最具体且满足其他候选的声明，同等候选按接口顺序选择。没有组合签名时，需要足够显式的兼容覆写；不能将失败的覆写推断退成 dynamic。[覆写][member-overrides]保留泛型参数身份和形状检查。泛型类、协变参数及完整类型规范化仍缺。 | [frontend/classes.dart](../lib/src/frontend/classes.dart)；[values.dart](../test/fixtures/values.dart) `CombinedInterface`、`InferredArithmetic`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §12 Mixins | 未实现 | 无 mixin 声明、约束或应用展开。 | [ast.dart](../lib/src/ast.dart) `AstUnit`；[parser.dart](../lib/src/parser.dart) `parseUnit()`；尚无验证入口 |
| §13 Extensions | 未实现 | 无 extension 声明、适用性、优先级及显式调用。 | [ast.dart](../lib/src/ast.dart) `AstUnit`；[parser.dart](../lib/src/parser.dart) `parseUnit()`；尚无验证入口 |
| §14 Enums | 未实现 | 无枚举声明、值构建或成员；增强枚举还需对应特性规范补充。 | [ast.dart](../lib/src/ast.dart) `AstUnit`；[parser.dart](../lib/src/parser.dart) `parseUnit()`；尚无验证入口 |
| §16 Metadata | 部分实现 | 解析并附着声明注解，校验 const-variable 引用身份，支持标量、List、null 及已实现构造子集的类实例；按外围声明作用域、局部绑定及库前缀/导出过滤解析。支持已实现 const 构造器的注解调用，以及真实 core `pragma` 的 name/options 常量值。编译期消费 `dartc:no-gc` 等函数约束，按类声明身份区分同名用户类；合同与验证边界见[运行时文档](../doc/runtime.md)。其他 core 注解、反射和运行时注解表尚缺；内部对象/类型 metadata 不属于此语法能力。 | [parser.dart](../lib/src/parser.dart) `parserMetadata()`；[binding.dart](../lib/src/binding.dart) `bindingStatement()`；[constants.dart](../lib/src/constants.dart) `evaluateMetadataConstant()`；[frontend.dart](../lib/src/frontend.dart) `feCheckMetadata()`；[values.dart](../test/fixtures/values.dart) `metadataValues()`；[behavior_test.dart](../test/behavior_test.dart) `libraries`、`rejected` |

## 实现边界

- 接口调用按实际类选择声明；Object 的默认 `toString()` 通过绑定的运行时声明提供，格式化继续使用描述符回调。一般 dynamic 调用和 noSuchMethod 分派仍缺。
- 读取、写入和方法调用分别选择对应声明；get/set 和 static 作为普通方法或字段名称仍按语法上下文区分。静态声明与自有实例成员、同名构造器后缀及绑定 core Object 的实例接口名冲突；Object 接口表绑定名称、角色和已有运行时实现，其余默认成员仍缺。
- [抽象成员声明][abstract-members]只约束接口签名，不遮蔽继承的具体实现；无体 `toString()` 声明可继续使用 Object 的兼容实现。其他缺少具体实现的成员仍须由抽象类保留，或由具体类实现。
- 精确 GC 尚未启用；对象布局与内存管理边界见[运行时文档](../doc/runtime.md)。

## 规范与 SDK 差异

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
