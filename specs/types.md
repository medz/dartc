# 类型与泛型

IR 保存值的 Dart 类型。寄存器宽度、装箱和原生调用约定由后续后端决定。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 类型名、前缀、嵌套实参、可空类型 | 支持已表示的核心类型、类和 record 的可空形式，以及嵌套的类类型实参。带导入前缀的类型仍指向声明库中的类。 |
| 核心标量、`Object`、`dynamic`、`void`、`Never` | 支持这些类型及 Null；dynamic 与 Object? 保持不同类型身份和双向顶类型关系。typed 存储、参数、返回值和 bool 上下文保留逐次隐式检查。dynamic 接收者的成员、函数和运算符通过统一运行时派发，未建模 SDK 成员明确拒绝。Never 没有正常返回值，Never? 等价于 Null。 |
| 异常及栈轨迹 | 支持 Error、TypeError、NoSuchMethodError、AssertionError、StateError、UnsupportedError、StackTrace，以及按用户声明的类和接口捕获异常。 |
| `List<T>` 及实际类型检查 | 支持 List、Set、Map、MapEntry、Iterable 和 Iterator 的参数化类型及其继承关系。字面量保留实际类型实参，宽化引用不绕过写入类型检查。 |
| Type 值和类型参数实化 | 支持已表示类型的 Type 字面量、别名与泛型 T 值，严格保持类型相等、哈希、集合键和规范身份；闭包保留实化环境。支持 Type/Type? 测试和转换；dynamic runtimeType 支持已表示的具体用户类、函数、record、List 及标量。Set/Map 和部分错误的 SDK 私有实现类型尚未建模，读取明确拒绝，不将公开接口伪装成实际类型。静态 runtimeType 读取和 object pattern 字段复用相同虚分派，保持用户 override、实际泛型类型和模式 getter 缓存；super.runtimeType 直接调用选中的祖先实现，不重新分派到 override。见[类型值样本](../test/frontend/lowering/fixtures/type_values.dart)及[runtimeType 样本](../test/frontend/lowering/fixtures/runtime_type.dart)。 |
| 函数签名 | 顶层函数、方法和构造器保留必需及可选形参。实例调用在选定实现后按其签名绑定参数。函数类型按参数逆变、返回值协变、位置参数范围及命名参数的必需性判断子类型。 |
| 泛型函数类型与泛型函数值签名 | 支持独立绑定的函数类型参数、界限、嵌套泛型函数类型及显式实例化。类型相等、哈希和子类型比较忽略绑定参数名称；外层自由类型参数仍按声明身份区分，类型代换避免捕获。 |
| 类型参数、上界、泛型别名 | 支持类和函数类型参数、递归上界、嵌套代入及解析为已表示类型的别名。类型参数保留声明身份和作用域，实例化同时检查全部参数的界限。函数或程序校验完成后，引用的类型参数与继承元数据不可再初始化。 |
| 泛型缺省类型元数据 | 保留 analyzer 预计算的默认类型，区分隐式 dynamic 与显式 Object?，支持相互依赖、逆变递归界限、别名及捕获类型代入。默认元数据不参与类型身份，仅在应用时验证界限；结构类型元数据缺失时不猜测。dynamic 调用在参数形状检查后才请求默认类型。见[元数据验证](../test/frontend/lowering/generic_defaults_test.dart)。 |
| 现代与旧式函数 typedef | 支持别名解析为已表示的函数签名。 |
| 普通及 const 泛型类实例 | 支持普通和 const 泛型实例、成员代入、类型测试和转换；const 对象按实际类型和各声明字段的常量值保留规范身份。 |
| 泛型 `extends`/`implements` | 保留继承路径中的实参和次序，支持继承成员、super 调用以及泛型子类型检查。 |
| 类声明身份与继承存储 | IR 按声明库和类名核对名义身份，拒绝循环继承及沿不同路径取得的同一接口的冲突类型实参。导入函数引用也须复用同一声明身份。实例字段按声明槽访问，常量实例须提供批次内各级父类的存储。见[声明验证](../test/ir/program_references_test.dart)。 |
| 推断、类型提升、确定赋值 | 支持局部变量和参数在核心类型测试及判空后的读取和更新，包括 `is!` 分支提前返回后的提升。支持非 late 变量的延后首次赋值，以及类型参数判空后的 T & Object 和 analyzer 解析的 T & S 提升。交类型保留词法参数身份及提升上界，支持已表示的标量、泛型类/接口、record、函数、FutureOr 上界，含嵌套提升与闭包撤销。成员视图按提升上界选择；推断集合/调用实参仍按 analyzer 的原始 T，不能把交类型当作 S。类型参数具体代入擦除静态提升，运行时测试/转换须在擦除前同时检查两侧。见[提升交类型样本](../test/frontend/lowering/fixtures/promoted_intersections.dart)。 |
| 基于界限的推断 | 消费 analyzer 对已支持类构造和函数调用的推断结果；推断结果保留 FutureOr 联合类型；未表示的类型交集仍明确拒绝。 |
| Record 类型、extension type | 支持 Record、具名和位置字段的结构类型、嵌套及可空 record。相同形状按字段类型协变，命名顺序不影响形状。普通/泛型 extension type 按 analyzer 表示擦除处理，保留可空表示及嵌套类型；成员仍按源声明选择。见[范围与边界](extension-types.md)。 |
| `Future`、`FutureOr` 与异步类型规则 | `Future<T>` 使用规范名义身份；`FutureOr<T>` 单独表示联合类型，支持双臂子类型、规范化、泛型替换、函数类型 alpha 相等/hash、Type 值及同步 `is`/`as`/`!`。`FutureOr<int?>` 的 `!` 保留原静态类型和实际 null 检查；不把内部 Future<int?> 收窄。共同 Future 视图保留联合类型身份，无法求得的视图明确拒绝。async/await 的 IR 与 SDK 微任务参考执行已支持；原生 Future 输入的类型桥仍明确拒绝。公开返回类型与异步完成类型分开，例如 `Object f() async` 和 `FutureOr<Object> f() async` 分别产生 `Future<Object?>` 与 `Future<Object>`，不从规范化后的公开 IR 类型反推完成类型。见[类型样本](../test/frontend/lowering/fixtures/future_types.dart)。 |
| FFI 标量、指针与原生导出 | 固定宽度整数、Float、Double、标量指针和 Void 返回已接通[原生库](libraries.md#原生库)；聚合类型的原生调用仍待实现。 |

[IR 行为对照](../test/frontend/lowering/lowering_test.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/types.md)。

## 原生类型判断与空安全

原生代码支持 `== null`、`!= null`、`??`、`??=`、`is` 和 `is!`。类型判断读取值的实际类型，支持已接通原生存储的标量和用户类、继承与接口、可空类型及实参已确定的泛型类型；`Object?` 的 `is int` 不依赖变量的静态类型猜测结果。泛型实参中的函数按参数逆变、返回协变检查，record 按形状与字段类型检查，FutureOr 保留联合类型关系。精化后的值可拆箱为 int、double、bool，或继续作为引用传递；短路只执行必要分支。见[类型与异常筛选对照](../test/compiler/type_checks_test.dart)、[空安全对照](../test/compiler/nullability_test.dart)和[精化值验证](../test/codegen/boxed_values_native_test.dart)。

int、double 和 bool 值均可装箱为引用，包括运行时计算的数值；仍被使用的装箱值在调用及回收后保持不变，见[计算结果装箱验证](../test/codegen/dynamic_boxes_native_test.dart)。地址为零的非空 FFI Pointer 值不等于 Dart null。依赖运行时类型参数的检查、`as`、后缀 `!`、Type/runtimeType 值以及尚无原生存储的函数和 record 值仍是缺口；支持这些类型作为泛型实参不表示对应值已可原生执行。跨模块托管值传递尚未接通。

## analyzer 元数据边界

analyzer 14.7 对部分合并接口缺少泛型默认类型，或保留显式 extension 运算符的未代入类型参数；lowering 不把这些值当作已检查的类型。枚举 `_name` 存储以及私有 Symbol 常量也有信息丢失，分别见[类](classes.md)和[变量及常量](variables.md)。这些是兼容缺口。

将继承方法 `f<T>()` 与接口 `f<U extends T>()` 在 `T=Object?` 时合并，analyzer 14.7 还可能抛出 `_TopMergeStateError`，而 SDK 3.13.7 可编译执行。这发生在取得已解析库之前；显式为原方法写出 `T extends Object?` 可绕过该上游差异，不改变 dartc 的语言目标。

## 规范依据

[主规范 §15、§20](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[空安全](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md)、[类型推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md)、[流分析](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/flow-analysis.md)、[类型别名](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.13/nonfunction-type-aliases/feature-specification.md)、[`dart:ffi`](https://api.dart.dev/stable/3.13.7/dart-ffi/NativeType-class.html)。

抽象成员的静态签名可以与其继承实现的运行时入口不同。IR 分别记录声明与入口，并验证参数形状、泛型界限及返回类型的兼容关系；动态查找选择实际入口。见[成员入口契约测试](../test/ir/member_implementations_test.dart)。
