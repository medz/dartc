# 类及相关声明：§10–§14、§16

按[固定草案源码](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)建立索引；条款目录见[官方草案 PDF](https://dart.dev/to/spec-draft)。
兼容验证基线为 Dart SDK 3.13.5；§15 泛型和 §20 类型关系另见[类型追踪](types.md)。
字段的空安全初始化约束还依据[空安全补充][nnbd]，不能只用旧草案章节判定兼容。

| 规范条目 | 状态 | 实现与缺口 | 实现与验证入口 |
| --- | --- | --- | --- |
| §10 类声明 | 部分实现 | 支持非泛型普通类；AST 尚无类修饰符、父类或接口列表。 | [ast.dart](../lib/src/ast.dart) `AstClass`；[parser.dart](../lib/src/parser.dart) `parserClass()`；[values.dart](../test/fixtures/values.dart) `Box`、`Cell` |
| §10.1 完整实现接口 | 未实现 | 没有接口成员收集、缺失成员诊断及 noSuchMethod 转发。 | [ast.dart](../lib/src/ast.dart) `AstClass`；尚无验证入口 |
| §10.2 实例方法 | 部分实现 | 支持已知类 receiver 的方法调用、递归和参数绑定；一般动态查找与继承分派未实现。 | [frontend.dart](../lib/src/frontend.dart) `feMethod()`、`feLowerMemberCall()`；[values.dart](../test/fixtures/values.dart) `Box.arguments()`、`Box.recurse()` |
| §10.2.1 用户运算符 | 未实现 | 基础类型运算由 builtin lowering 处理，没有用户 `operator` 声明及分派。 | [parser.dart](../lib/src/parser.dart) `parserClass()`；[frontend.dart](../lib/src/frontend.dart) `feCombine()`；尚无用户运算符验证 |
| §10.2.2 `noSuchMethod` | 未实现 | 不生成 Invocation，也没有缺失成员动态转发。 | [frontend.dart](../lib/src/frontend.dart) `feLowerMemberCall()`；尚无验证入口 |
| §10.2.3 `==` 与对象相等 | 部分实现 | 有基础值比较及引用身份；用户覆写 `==`、hashCode 契约未实现。 | [runtime.dart](../lib/src/runtime.dart) `rtValueEq()`、`rtValueIdentical()`；[values.dart](../test/fixtures/values.dart) `objectValues()`、`constantLists()` |
| §10.3 Getter | 部分实现 | 支持实例 getter、隐式 receiver 和独立的读取类型；不带返回注解时为 dynamic，不从 getter 体或配对 setter 推断。static、继承及一般函数值提取未实现。 | [parser.dart](../lib/src/parser.dart) `parserFunction()`；[members.dart](../lib/src/members.dart) `bindClassMembers()`；[frontend.dart](../lib/src/frontend.dart) `feReadBoundMember()`；[values.dart](../test/fixtures/values.dart) `accessorValues()`、`localBindings()` |
| §10.4 Setter | 部分实现 | 支持实例 setter、仅写属性及与 getter 独立的写入类型；结果只能省略或 void，恰有一个必需位置参数；未注解参数为 dynamic，不从 getter 推断。顶层 setter 仅解析为 AST，绑定阶段明确拒绝。 | [ast.dart](../lib/src/ast.dart) `AstFunction.setter`；[parser.dart](../lib/src/parser.dart) `parserFunction()`；[frontend.dart](../lib/src/frontend.dart) `feLowerLvalue()`、`feWriteLvalue()`；[values.dart](../test/fixtures/values.dart) `accessorValues()`；[behavior_test.dart](../test/behavior_test.dart) `rejected`、`failingValues` |
| §10.5 抽象实例成员 | 未实现 | 没有抽象类/成员语义及完整实例化检查；能解析无体签名不代表抽象语义成立。 | [parser.dart](../lib/src/parser.dart) `parserFunction()`；[frontend.dart](../lib/src/frontend.dart) `feRegisterFunction()`；尚无验证入口 |
| [§10.6 实例变量][instance-variables] | 部分实现 | 要求字段显式类型，支持字段存取；final 字段存储不可直接再写，可与显式 setter 配对；可空 final 也必须初始化，const 实例字段被拒绝。`late`、协变字段及完整初始化形式未实现。 | [frontend.dart](../lib/src/frontend.dart) `feLowerLvalue()`；[initialization.dart](../lib/src/initialization.dart) `checkInitializers()`；[values.dart](../test/fixtures/values.dart) `Plain`、`accessorValues()`、`finalContexts()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| [§10.7.1 生成式构造][generative-constructors] | 部分实现 | 支持未命名构造、缺省无参构造、字段声明初始化与 `this.field`；每个已支持构造器须初始化 final/非空字段，final 声明与字段形参重复初始化被拒绝。命名、重定向、初始化列表和 super 调用未实现。 | [parser.dart](../lib/src/parser.dart) `parserClass()`；[initialization.dart](../lib/src/initialization.dart) `checkInitializers()`；[frontend.dart](../lib/src/frontend.dart) 构造 lowering；[values.dart](../test/fixtures/values.dart) `Plain`、`argumentCalls()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §10.7.2 Factory | 未实现 | 无 factory 声明、重定向目标或返回实例规则。 | [ast.dart](../lib/src/ast.dart) `AstFunction`；[parser.dart](../lib/src/parser.dart) `parserClass()`；尚无验证入口 |
| §10.7.3 常量构造器 | 未实现 | 现有常量 List 不包含用户 const 实例、潜在常量初始化或实例规范化。 | [constants.dart](../lib/src/constants.dart) `evaluateConstant()`；尚无类常量构造验证 |
| §10.8 静态方法和字段 | 未实现 | 无 static 成员 AST 状态或静态成员命名空间。 | [ast.dart](../lib/src/ast.dart) `AstClass`、`AstFunction`；[parser.dart](../lib/src/parser.dart) `parserClass()`；尚无验证入口 |
| §10.9–10.10 继承与父接口 | 未实现 | 无 extends/implements 关系、super 查找、override 检查或继承对象布局。 | [ast.dart](../lib/src/ast.dart) `AstClass`；[frontend.dart](../lib/src/frontend.dart) `feCollectDeclarations()`；尚无验证入口 |
| §10.11 类成员冲突 | 部分实现 | 在声明边界绑定本类字段、方法和访问器，拒绝重复声明、方法与访问器冲突、可写字段与显式访问器冲突；允许 getter/setter 及 final 字段/setter 配对。尚不计算 static、继承的 Object 成员命名空间或 override 冲突。 | [members.dart](../lib/src/members.dart) `MemberBinding`、`bindClassMembers()`；[frontend.dart](../lib/src/frontend.dart) `feCollectDeclarations()`；[values.dart](../test/fixtures/values.dart) `accessorValues()`；[behavior_test.dart](../test/behavior_test.dart) `rejected` |
| §11 接口及组合成员签名 | 未实现 | 原生类 TypeRef 目前只描述类身份；不能替代结构化接口、组合签名和 override 规则。 | [types.dart](../lib/src/types.dart)；[ast.dart](../lib/src/ast.dart) `AstClass`；尚无验证入口 |
| §12 Mixins | 未实现 | 无 mixin 声明、约束或应用展开。 | [ast.dart](../lib/src/ast.dart) `AstUnit`；[parser.dart](../lib/src/parser.dart) `parseUnit()`；尚无验证入口 |
| §13 Extensions | 未实现 | 无 extension 声明、适用性、优先级及显式调用。 | [ast.dart](../lib/src/ast.dart) `AstUnit`；[parser.dart](../lib/src/parser.dart) `parseUnit()`；尚无验证入口 |
| §14 Enums | 未实现 | 无枚举声明、值构建或成员；增强枚举还需对应特性规范补充。 | [ast.dart](../lib/src/ast.dart) `AstUnit`；[parser.dart](../lib/src/parser.dart) `parseUnit()`；尚无验证入口 |
| §16 Metadata | 未实现 | 无源码注解的解析、常量求值和附着关系；本项目内部对象/类型 metadata 不属于此语法能力。 | [ast.dart](../lib/src/ast.dart)；[parser.dart](../lib/src/parser.dart)；尚无验证入口 |

实现边界：

- 用户类的 `toString()` 通过描述符回调支持动态格式化；这不是一般虚方法表或 noSuchMethod 分派。
- 本类成员绑定保存各声明所属 AST 的序号，读取、写入和方法调用分别选择对应声明；get/set 作为普通方法或字段名称仍按语法上下文区分。
- 当前对象头与字段扫描信息为后续运行时提供基础，尚未启用精确 GC。
- Dart 3 类修饰符、extension type 等新增声明需补其特性规范，不能仅依据本草案章节判定兼容。

已有对象行为由 `objectValues()`、`assignmentValues()`、`accessorValues()`、`argumentCalls()` 负责；新声明形式应先补 AST 和符号契约，再建立实际调用及拒绝行为。

[nnbd]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md
[instance-variables]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L3646
[generative-constructors]: https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex#L3749
