# Extension type 表示擦除

非泛型 extension type 的简单主构造器和 representation getter 使用普通静态 identity 函数。实例成员复用普通 extension 的显式接收者 ABI；不新增 IR 类型、分派指令、对象分配或伪造类。

## 当前范围

- 单一主构造器，没有构造体、初始化列表或 implements。非泛型类型可以声明泛型方法。
- representation 为已支持的类型，包括可空、dynamic、record、函数、集合及嵌套 extension type。声明未写 `?` 不表示擦除后的值一定非空。
- 自身方法、getter/setter、索引与一元/二元运算符、call、静态成员及变量；保留实参、索引更新和级联的求值顺序。
- 词法 this 和成员访问、捕获接收者的闭包、普通/泛型方法提取、隐式 call 提取及主构造器提取。
- 普通与 const 构造、类型值、is/as、对象模式、集合中的类型参数及函数类型。运行时类型使用 analyzer 的 extensionTypeErasure；成员选择仍使用源声明，不能从擦除后的类型重新推断。
- 主构造器返回表示值本身；提取构造器仍保留声明身份。运行时不保存 extension type 的名义身份。

[SDK 差分及边界测试](../test/lowering/extension_types_test.dart)与[样本](../test/lowering/fixtures/extension_types.dart)覆盖结果、异常种类、效果顺序，并检查没有 extension type 的类、Construct 或 representation LoadField。

## 明确边界

泛型 extension type、implements、额外构造器、主构造器体/初始化列表在声明处拒绝；泛型构造器别名提取在使用处拒绝，非泛型别名复用原构造器身份。即使只在类型注解或函数签名中引用，extension type 的声明库也必须包含在输入 batch 中注册；不会仅凭导入自动装配或放开尚未验证的声明。其他未实现的核心库 API、async 和普通 extension 的已知边界不变。

下一阶段保留源类型实参并展开泛型 extension type 的声明 binder，尤其不能从表示值恢复 phantom 类型参数；随后分别处理接口成员选择和额外构造器初始化。
