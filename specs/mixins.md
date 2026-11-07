# Mixins

## 当前 IR 范围

| 语言行为 | 支持情况 |
| --- | --- |
| mixin 声明与应用 | 支持普通与泛型 mixin、泛型应用类和父类、多个及重复应用。每次应用拥有独立的实例字段，保留声明的名义接口。 |
| 成员 | 支持方法、泛型方法、属性、运算符、默认参数、方法提取、闭包和跨库私有成员。抽象成员不遮盖继承的具体实现。 |
| 字段 | 支持可变、final、late 和 late final；保留每个应用的实际类型参数、初始化顺序和协变写入检查。 |
| `on` 与 `super` | 支持泛型约束和词法 super，包括逃逸闭包中的 super。调用选择该应用之前的实现。 |
| 命名应用与 mixin class | 支持分析器生成的构造器、命名参数、默认值和嵌套 mixin class 应用。 |
| 接口与缺失成员 | 支持 implements、抽象成员及普通 typed noSuchMethod 转发；替换成员时保留显式及类类型参数带来的协变检查。 |
| 常量 | 支持合法的 const 应用及其泛型父类存储、成员派发和规范身份。 |

## 当前边界

支持枚举混入及其泛型实参和成员重写，见[枚举混入验证](../test/lowering/enum_mixins_test.dart)。协变转发遵循[类成员转发](classes.md)的入口与默认值规则。所有源 mixin 和非 Object 父类声明须包含在输入库批次中；未提供的源码不会自动装配。

行为验证：[基本应用](../test/lowering/mixins_test.dart)、[字段与词法 super](../test/lowering/mixin_application_state_test.dart)、[泛型、接口、常量及嵌套应用](../test/lowering/mixin_type_environments_test.dart)、[输入库边界](../test/lowering/mixins_unsupported_test.dart)。
