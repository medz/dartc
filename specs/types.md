# 类型与泛型

IR 保存值的 Dart 类型。寄存器宽度、装箱和原生调用约定由后续后端决定。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 类型名、前缀、嵌套实参、可空类型 | 支持已表示的核心类型、类和 record 的可空形式，以及嵌套的类类型实参。带导入前缀的类型仍指向声明库中的类。 |
| 核心标量、`Object`、`dynamic`、`void`、`Never` | 支持这些类型及 Null；dynamic 与 Object? 保持不同类型身份和双向顶类型关系。typed 存储、参数、返回值和 bool 上下文保留逐次隐式检查。dynamic 接收者的成员、函数和运算符通过统一运行时派发，未建模 SDK 成员明确拒绝。Never 没有正常返回值，Never? 等价于 Null。 |
| 异常及栈轨迹 | 支持 Error、TypeError、NoSuchMethodError、AssertionError、StateError、UnsupportedError、StackTrace，以及按用户声明的类和接口捕获异常。 |
| `List<T>` 及实际类型检查 | 支持 List、Set、Map、MapEntry、Iterable 和 Iterator 的参数化类型及其继承关系。字面量保留实际类型实参，宽化引用不绕过写入类型检查。 |
| Type 值和类型参数实化 | 支持已表示类型的 Type 字面量、别名与泛型 T 值，严格保持类型相等、哈希、集合键和规范身份；闭包保留实化环境。支持 Type/Type? 测试和转换；dynamic runtimeType 支持已表示的具体用户类、函数、record、List 及标量。Set/Map 和部分错误的 SDK 私有实现类型尚未建模，读取明确拒绝，不将公开接口伪装成实际类型。静态 runtimeType 读取和 object pattern 字段复用相同虚分派，保持用户 override、实际泛型类型和模式 getter 缓存；super.runtimeType 直接调用选中的祖先实现，不重新分派到 override。见[类型值样本](../test/lowering/fixtures/type_values.dart)及[runtimeType 样本](../test/lowering/fixtures/runtime_type.dart)。 |
| 函数签名 | 顶层函数、方法和构造器保留必需及可选形参。实例调用在选定实现后按其签名绑定参数。函数类型按参数逆变、返回值协变、位置参数范围及命名参数的必需性判断子类型。 |
| 泛型函数类型与泛型函数值签名 | 支持独立绑定的函数类型参数、界限、嵌套泛型函数类型及显式实例化。类型相等、哈希和子类型比较忽略绑定参数名称；外层自由类型参数仍按声明身份区分，类型代换避免捕获。 |
| 类型参数、上界、泛型别名 | 支持类和函数类型参数、递归上界、嵌套代入及解析为已表示类型的别名。类型参数保留声明身份和作用域，实例化同时检查全部参数的界限。 |
| 泛型缺省类型元数据 | 保留 analyzer 预计算的默认类型，区分隐式 dynamic 与显式 Object?，支持相互依赖、逆变递归界限、别名及捕获类型代入。默认元数据不参与类型身份，仅在应用时验证界限；结构类型元数据缺失时不猜测。dynamic 调用在参数形状检查后才请求默认类型。见[元数据验证](../test/lowering/generic_defaults_test.dart)。 |
| 现代与旧式函数 typedef | 支持别名解析为已表示的函数签名。 |
| 普通及 const 泛型类实例 | 支持普通和 const 泛型实例、成员代入、类型测试和转换；const 对象按实际类型和各声明字段的常量值保留规范身份。 |
| 泛型 `extends`/`implements` | 保留继承路径中的实参和次序，支持继承成员、super 调用以及泛型子类型检查。 |
| 推断、类型提升、确定赋值 | 支持局部变量和参数在核心类型测试及判空后的读取和更新，包括 `is!` 分支提前返回后的提升。支持非 late 变量的延后首次赋值，以及类类型参数判空后提升为 T & Object。更一般的类型参数交类型待实现。 |
| 基于界限的推断 | 消费 analyzer 对已支持类构造和函数调用的推断结果；推断包含未表示类型（如 FutureOr）时仍明确拒绝。 |
| Record 类型、extension type | 支持 Record、具名和位置字段的结构类型、嵌套及可空 record。相同形状按字段类型协变，命名顺序不影响形状。普通/泛型 extension type 按 analyzer 表示擦除处理，保留可空表示及嵌套类型；成员仍按源声明选择。见[范围与边界](extension-types.md)。 |
| `Future`、`FutureOr` 与异步类型规则 | 待实现。 |
| FFI 标量、指针与原生导出 | 待实现。 |

[IR 行为对照](../test/lowering/lowering_test.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/types.md)。

## 规范依据

[主规范 §15、§20](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[空安全](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md)、[类型推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md)、[流分析](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/flow-analysis.md)、[类型别名](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.13/nonfunction-type-aliases/feature-specification.md)、[`dart:ffi`](https://api.dart.dev/stable/3.13.7/dart-ffi/NativeType-class.html)。
