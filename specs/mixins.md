# Mixins

## 当前 IR 范围

| 语言行为 | 支持情况 |
| --- | --- |
| mixin 声明与应用 | 支持普通与泛型 mixin、泛型应用类和父类、多个及重复应用。每次应用拥有独立的实例字段，保留声明的名义接口。 |
| 成员 | 支持方法、泛型方法、属性、运算符、默认参数、方法提取、闭包和跨库私有成员。抽象成员不遮盖继承的具体实现。 |
| 静态成员 | 支持通过 mixin 名称读取常量、调用静态方法及读写 getter/setter；复合赋值保留求值顺序。见[静态访问验证](../test/frontend/lowering/cascades_test.dart)。 |
| 字段 | 支持可变、final、late 和 late final；保留每个应用的实际类型参数、初始化顺序和协变写入检查。 |
| `on` 与 `super` | 支持泛型约束和词法 super，包括逃逸闭包中的 super。调用选择该应用之前的实现。 |
| 命名应用与 mixin class | 支持分析器生成的构造器、命名参数、默认值和嵌套 mixin class 应用。 |
| 接口与缺失成员 | 支持 implements、抽象成员及普通 typed noSuchMethod 转发；替换成员时保留显式及类类型参数带来的协变检查。 |
| 常量 | 支持合法的 const 应用及其泛型父类存储、成员派发和规范身份。 |

## 原生验证

基本调用、别名构造、跨库私有成员、重复应用的独立/late 存储、初始化顺序、词法 super、泛型环境、协变检查及常量身份复用上述前端样本，在 macOS/Linux ARM64 [原生执行](../test/compiler/mixins_test.dart)。组合样本同时覆盖 sync*、extension type 和暂停后分配压力，恢复时仍读取对应应用的 super 与 late 捕获。

## 当前边界

支持枚举混入及其泛型实参和成员重写，见[枚举混入验证](../test/frontend/lowering/enum_mixins_test.dart)。协变转发遵循[类成员转发](classes.md)的入口与默认值规则。用户源码中的 mixin 和非 Object 父类声明须包含在输入库批次中。官方 SDK 的普通父类与 mixin 源码按引用接入；已验证 `ListMixin<int>` 的继承成员，以及 `String.codeUnits` 使用的不可变列表 mixin。其余成员能否原生执行仍取决于所用语言和库能力，不能视为完整标准库支持。

行为验证：[基本应用](../test/frontend/lowering/mixins_test.dart)、[字段与词法 super](../test/frontend/lowering/mixin_application_state_test.dart)、[泛型、接口、常量及嵌套应用](../test/frontend/lowering/mixin_type_environments_test.dart)、[输入库边界](../test/frontend/lowering/mixins_unsupported_test.dart)、[SDK 继承成员](../test/frontend/lowering/sdk_functions_test.dart)、[不可变码元视图](../test/compiler/strings_test.dart)。
