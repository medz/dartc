# Extension type 表示擦除

普通与泛型 extension type 的构造器返回表示值，representation getter 使用普通静态 identity 函数。实例成员复用普通 extension 的显式接收者 ABI；不新增 IR 类型、分派指令、对象分配或伪造类。

## 当前范围

- 主构造器体与断言、次级生成式构造器、this 重定向、普通 factory body 和 redirecting factory。重定向保留最终目标的默认值、命名参数身份及类型实参。类型和方法均可声明泛型参数。构造器复用静态 target 的参数默认值与提取规则。
- representation 初始化完成后执行初始化断言，再执行 body；即使断言在源码中位于 representation initializer 之前也如此。这一顺序有 SDK 3.13.7 JIT/AOT 差分覆盖。正常完成或裸 return 返回表示值，finally 与闭包捕获沿用 FunctionLowering；断言启用/省略由 enableAssertions 决定。
- 支持 implements：继承的 extension type 成员按 analyzer 选定的声明静态调用；普通接口成员在擦除后的表示对象上保留虚派发与协变检查。多层接口映射使用源类型的 asInstanceOf，不从运行时表示猜测父接口的 phantom 实参。
- 类型实参来自 analyzer 已解析的成员代入和源接收者类型；不从表示值反推 phantom 参数。构造器展开声明 binder，成员按类型参数再方法参数的顺序传递；闭包保留运行时类型环境。
- representation 为已支持的类型，包括可空、dynamic、record、函数、集合及嵌套 extension type。声明未写 `?` 不表示擦除后的值一定非空。
- 自身方法、getter/setter、索引与一元/二元运算符、call、静态成员及变量；保留实参、索引更新和级联的求值顺序。
- 词法 this 和成员访问、捕获接收者的闭包、普通/泛型方法提取、隐式 call 提取及主构造器提取。
- 普通与 const 构造、类型值、is/as、对象模式、集合中的类型参数及函数类型。运行时类型使用 analyzer 的 extensionTypeErasure；成员选择仍使用源声明，不能从擦除后的类型重新推断。
- 方法提取复用普通 extension 的联合默认值规则，不能把声明默认值简单替换为实际接收者类型参数。支持泛型构造器提取、显式/上下文实例化及 const 构造器函数值。
- 主构造器返回表示值本身；提取构造器仍保留声明身份。运行时不保存 extension type 的名义身份。

[SDK 差分及边界测试](../test/frontend/lowering/extension_types_test.dart)与[样本](../test/frontend/lowering/fixtures/extension_types.dart)覆盖结果、异常种类、效果顺序，并检查没有 extension type 的类、Construct 或 representation LoadField。

[重定向工厂对照](../test/frontend/lowering/extension_type_redirects_test.dart)覆盖多级重定向、可选及命名默认值、泛型目标、const 和构造器提取。

## 明确边界

external 构造器保留擦除后的外部调用签名，具体实现由链接方提供。泛型构造器别名支持类型参数重排、固定、重复和未使用参数，以及不同界限；非平凡的泛型别名保留自己的函数值身份。显式应用类型参数的构造器提取复用目标声明；先提取泛型别名再实例化则保留别名身份。见[构造器别名对照](../test/frontend/lowering/extension_type_aliases_test.dart)。

导入的 extension type 可以直接擦除类型并引用其构造器及成员；未提供声明库时保留外部目标，提供该库时生成对应函数体，不要求调用方为类型引用装配无关函数体。见[导入测试](../test/frontend/lowering/extension_types_test.dart)。普通 SDK 调用同样保留为导入。普通 extension 的已知边界不变。

泛型覆盖见[差分测试](../test/frontend/lowering/extension_types_generic_test.dart)及[样本](../test/frontend/lowering/fixtures/extension_types_generic.dart)。[接口差分测试](../test/frontend/lowering/extension_types_interfaces_test.dart)覆盖多个接口、同一声明的菱形继承、own 覆盖、静态父视图、泛型类型参数映射、跨库私有成员、继承提取的默认值，以及普通接口的真实覆盖与协变检查。不同声明的同名冲突、无效表示类型和禁止的接口仍由 analyzer 拒绝。[构造器差分测试](../test/frontend/lowering/extension_types_constructors_test.dart)覆盖初始化/断言/body/finally 顺序、异常、可空表示、泛型与 const、默认值及闭包。

### analyzer 14.7 边界

[泛型别名上下文实例化](../test/frontend/lowering/fixtures/extension_alias_inference.dart)通过 analyzer 检查并可转换为 IR；SDK 3.13.7 的编译器在直接将别名构造器提取赋给具体函数类型时于 `LoweredTypedefTearOff.fromExpression` 崩溃。此用例以明确的参数映射和返回值检查，不计入 SDK 执行一致的用例；先保存泛型提取值再实例化的形式可正常对照。

对于 `extension type E<T>(T value) { T get() => value; }`，`int read<B extends E<int>>(B value) => value.get();` 被 analyzer 14.7 诊断为接收者可空，连 `!` 与 `?.` 形式也不能消除该诊断。同一最小程序在 SDK 3.13.7 的 JIT 与 AOT 均输出 `3`，这是 analyzer 与 kernel 的差异。已检查库入口保留此错误，不绕过分析；显式转换为 `E<int>` 后访问可工作。边界测试保留最小源程序。

## 规范依据

[官方 extension types 规范](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.3/extension-types/feature-specification.md)：[成员静态绑定、实际类型参数和提取](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.3/extension-types/feature-specification.md#L697-L727)、[表示擦除与泛型界限](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.3/extension-types/feature-specification.md#L1112-L1133)、[构造和运行时类型语义](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.3/extension-types/feature-specification.md#L1406-L1459)。
