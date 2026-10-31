# 类型与泛型

本页说明类型语法、CLI 类型检查及原生导出的边界，对应主规范 §15、§20 和空安全、推断规则。[状态与阶段含义](README.md#如何读矩阵)适用于下表；语义分析 API 当前未提供，CLI 静态检查不是面向新 AST 的公开分析服务。

## 特性支持

| 特性 | 语法解析 | 语义分析 API | 编译/运行 | 使用限制 |
| --- | --- | --- | --- | --- |
| 类型名、前缀、嵌套实参、可空类型 | ✅ | ❌ | 🟡 | parser 不查找名称或验证实参数量、上界。 |
| 核心标量、`Object`、`dynamic`、`void`、`Never` | ✅ | ❌ | 🟡 | 没有完整 Dart 类型模型或公开 `Type` 值。 |
| `List<T>` 及实际类型检查 | ✅ | ❌ | 🟡 | 保留嵌套实参；没有一般 Iterable 或完整内建接口。 |
| 非泛型函数签名 | ✅ | ❌ | 🟡 | 支持位置/命名形状、参数逆变和结果协变。 |
| 泛型函数类型与泛型函数值签名 | ✅ | ❌ | ❌ | 泛型直接调用不等于泛型函数值可用。 |
| 类型参数、上界、泛型别名 | ✅ | ❌ | 🟡 | 完整 F-bound 与约束求解仍缺。 |
| 现代与旧式函数 typedef | ✅ | ❌ | 🟡 | 内建构造器别名、旧式 typedef 的 covariant 形参仍缺。 |
| 普通及 const 泛型类实例 | ✅ | ❌ | 🟡 | 支持实参保留、成员代入；泛型父接口未支持。 |
| 泛型 `extends`/`implements` | ✅ | ❌ | ❌ | 非泛型父接口图不代表可进行泛型父接口代入。 |
| 推断、类型提升、确定赋值 | ➖ | ❌ | 🟡 | 字段提升、完整闭包/异步流分析仍缺。 |
| 基于界限的推断 | ➖ | ❌ | 🟡 | 从 3.7 起，限现有类型模型，细则见[函数](functions.md#基于界限的推断)。 |
| Record 类型、extension type | ✅ | ❌ | ❌ | 没有相应类型关系及运行表示。 |
| `Future`、`FutureOr` 与异步类型规则 | 🟡 | ❌ | ❌ | 名称可解析但未绑定，不代表标准库类型存在。 |
| FFI 标量、指针与原生导出 | 🟡 | ❌ | 🟡 | 注解/类型按普通语法解析；ABI 与库输出另有限制。 |

## 类型解析 API

`parseTypeAnnotation(ScanResult)` 解析一个完整类型，`parseCompilationUnit` 解析 typedef。类型名称保持未绑定；省略的类型不自动补写。多余 token、缺失类型和错误分隔符会产生诊断，缺失类型可用零宽节点恢复。

以下是**可解析语法**，不是全部可编译的类型：

```dart
typedef Mapper<T extends Object> = ({T value, int count}) Function(
  T, {required T Function(T) convert});
typedef R Legacy<R, T>(T value, [R fallback]);
```

类型语法包括前缀名称、嵌套实参、`?`、类型参数和上界。函数类型可省略返回类型、嵌套返回函数类型，保留必需/可选位置、必需/可选命名参数、名字、元数据和 `covariant`。Record 类型支持空记录、位置字段及可选名字、命名字段、字段元数据与可空形式。保留这些结构不代表已检查重复声明、名字存在、型变、上界或修饰符的语义合法性。

已知解析限制：注解实参中的构造调用、泛型调用、cast 或闭包再次包含带注解类型时，超深嵌套仍可能触发栈溢出。

## 核心类型与类型关系

CLI 区分核心标量、可空类型、List、函数签名和用户类。名称按声明库、导入前缀和 part 库身份解析；类型参数具有独立声明身份，可遮蔽同名类或前缀。局部值遮蔽类型/prefix 后不能继续把它当类型，函数签名不查找函数体局部名。

- `Never` 是底类型，`Never?` 规范化为 `Null`，没有 Never 实例。未初始化存储不等于求值 Never；读取仍受赋值规则约束。
- `int`、`double` 都是 `num` 的子类型。支持空性、到 Object 的关系、List/用户类实参协变，以及函数参数逆变、结果协变。
- 非泛型父类和接口图参与静态及运行时子类型判断。共同类类型取唯一最具体共同接口；一般 LUB、交集类型和泛型父接口代入仍缺。
- `dynamic` 允许隐式转入具体类型，但执行运行时检查；`Object` 或可空类型不能因此直接下转。一般动态成员分派和 dynamic 函数调用未支持。
- `void` 限制值消费，不表示返回负载必然被清空。支持 `List<void>`；显式 `as` 可检查并取得负载，`is` 和普通隐式消费不放宽。只向严格子类型提升；`as dynamic`、`as Object?` 不改变原 void 读取类型。

`is`、`is!`、`as` 和隐式动态转换使用实际运行时类型，包括嵌套 List、已支持用户类和函数签名。`is`/`is!` 返回布尔测试结果，不因类型不匹配而抛出异常；`as` 和隐式动态转换检查失败则抛出可捕获 TypeError。List 协变视图写入按**底层实际元素类型**检查，而不只看变量的静态类型。

```dart
void main() {
  List<int> integers = <int>[1];
  List<num> numbers = integers;
  print(numbers is List<int>); // true。
  // numbers.add(1.5) 会在运行时类型检查中失败。
}
```

非泛型函数类型按结构判断，包含可接受的位置参数区间、命名集合及 required 约束；命名顺序不影响类型身份。支持结构上下界及外层类型参数代入；裸 `Function` 尚不能直接调用。

## 类型参数与别名

泛型类、typedef、顶层函数和方法支持有序参数及上界，检查未使用声明中的重复名、作用域、上界和循环。3.7 起类型参数 `_` 仍占实参位置并保留身份，但不引入可查找名字；此前为普通名字。

现代 `typedef A<T> = Type;` 与旧式函数 typedef 共用代入、前向和链式展开。别名在声明库展开，不创造新的类、构造器或常量身份；接口图建立后再检查相关边界，避免声明顺序改变结果。普通 RHS 要求至少 2.13，2.12 只接受直接、非可空的函数类型 RHS；`Function` 不能作别名名。用户类别名可用于受支持构造，`.new` 要求 2.15；内建 List/String 构造别名、泛型函数类型及旧式 covariant 形参仍缺。

显式实参、合法超界类型和原始类型的默认实例化分别检查。当前别名模型支持按参数身份和型变处理依赖与部分 F-bound：下界替换使用 Never，无显式上界的原始参数取 dynamic；原始类型用作上界还受简单界限制。函数直接调用和普通/const 泛型生成式构造共用默认实例化。类递归上界、泛型父接口和完整调用约束求解未完成。

普通及 const 泛型实例保留实际实参，字段、非泛型方法、访问器及闭包按实际接收者代入和检查。泛型类的工厂、late 字段、泛型实例方法、方法/构造器提取仍缺，见[泛型运行时实例](classes.md#泛型运行时实例)。

## 空安全、推断与流分析

未经提升的可空值不能直接消费成员、索引或算术。`== null` 的真分支不直接把类型变成 Null；空断言取 NonNull(T)，Null 得 Never，dynamic 仍为 dynamic。空短路链内按非空接收者检查，结果再变可空；类型限定的静态访问不添加空性。

当前 CLI 支持的推断和流分析包括：

- 从初始化式、List 元素、条件表达式和上下文推断。集合 if/for/spread 的所有元素类型均参与推断；空感知单元素使用可空下行上下文，以 NonNull 类型向上合并，过滤不提升后续变量。
- 匿名函数的省略参数使用期望签名，返回表达式使用期望结果上下文。Null/Never 参数上下文推为 Object?；void 结果上下文仍限制块体 return。泛型调用的[水平推断](functions.md#回调水平推断)分阶段处理回调；schema 最大/最小闭包以 Object?/Never 补未知部分，嵌套函数参数反转方向。
- 按绑定身份处理 is、空检查、逻辑分支、退出、赋值及循环写入。读使用提升类型，写仍按声明类型；`??=` 分开合并非空与写入路径，直接局部空断言在检查后可提升。
- 可变 late 局部可由初始化器结果提升，late final 初始化器不建立此提升。被闭包写入的绑定不提升，未显式写入的捕获可保留外层提升。字段提升及完整闭包规则未支持。
- 确定赋值/未赋值按分支、循环、标签及可达性合流，空短路访问与级联分别合并执行/跳过路径。Never 调用终止正常路径；不可达代码仍检查读写。
- 从 3.9 起，以非空静态类型、总真 is、Null/非空不匹配排除相应死边；不把任意 `int is String` 当作赋值分析豁免。版本取函数或全局初始化的拥有文件。捕获只继承声明点的赋值事实，子函数写入不反向确立外层赋值；同步异常合流见[语句](statements.md)。

实例字段优先从父接口的组合 getter/setter 签名推断；可写字段的两侧须同型，只有 getter 时取读取类型。无接口约束和初始化器时取 dynamic，构造器赋值不反推字段类型。非主构造器类的其他字段可从字面量、常量引用、已支持常量类型运算（含 as/is）、List、函数引用和直接构造结果推断，Null 推为 dynamic。普通函数调用、成员依赖及一般声明依赖图仍缺；主构造器声明参数另见[类](classes.md#主构造器)。

数值推断区分动态左右操作数：`int + dynamic` 为 num，动态左侧保留 dynamic；double 算术传播 double，`/` 返回 double，`~/` 返回 int。double 上下文只转换可精确表示的**整数字面量**，不隐式转换普通 int 变量。数值运算及 remainder 的右实参上下文结合接收者和结果约束决定，接收者无上下文；`/`、`~/` 不沿用这一特殊收窄。

赋值、传参等边界可进行[可调用对象的隐式提取](functions.md#可调用对象)。转换所得函数类型与赋值目标类型分开；`??=` 合并非空读取类型和 RHS，写入检查不改变表达式结果类型。完整推断、类型关系和诊断一致性仍未完成。

## 已知 SDK 差异

- 类型参数注解在整组参数作用域检查，typedef 自身注解使用外围作用域。常量资格按别名展开后的真实依赖判断：擦除 T 的 `Phantom<T> = Marker` 可用于注解构造及 `const <Phantom<T>>[]`，`const <T>[]` 仍拒绝。SDK 3.13.7 CFE 接受前一种常量 List 注解，analyzer 报错。
- SDK 3.13.7 对跨库前缀泛型别名到非泛型类的 `p.A<int>()` 报实参数量错误，同库、显式 `new p.A<int>()` 及命名形式却可接受。固定 2.13 规则允许 qualified alias 创建实例，这一差异待确认，不把隐式形式定义为语言非法。
- 可空类别名构造结果尚未完整区分：SDK 3.13.7 CFE 对非泛型隐式命名/`.new` 保留可空结果，未命名、显式 new/const 返回非空；analyzer 均按非空处理。泛型别名在 CFE 中又区分省略实参的可空结果与显式实参的非空结果，不能依赖 dartc 已完整复现。

## FFI 类型与原生导出声明

`Int8`、`Uint8`、`Int16`、`Uint16`、`Int32`、`Uint32`、`Int64`、`Uint64`、`IntPtr`、`UintPtr`、`Float`、`Double`、`Bool`、`Void`、`Pointer<T>` 保留独立类型身份，不能把 Int64 当成 Dart int 别名。Pointer 的 NativeType 上界、NativeFunction 的 Function 上界按普通类型应用检查。FFI 别名共用一般展开和上界检查，Native/Dart ABI 映射在导出边界验证。

用 `package:dartc/export.dart` 的 `@Export<T>` 声明原生导出。函数签名必须闭合且仅含必需位置参数，Dart int/double/bool/Pointer 参数和结果必须符合 FFI 映射；const 标量数据需对应 FFI 数据类型。Dart int 本身不指定 C 位宽。

- 已加载库中的导出都会输出。顶层函数和静态方法可给多个不同符号，顶层及静态 const 数据遵循同一命名规则。省略 symbol 取声明名；拒绝空名、NUL 和重复符号。
- 未完成的非 const 数据、实例接收者、泛型调用、getter/setter 导出会诊断，不因普通元数据可解析而成为可用导出。
- macOS/Linux ARM64、x64 的 object/static/dylib 输出实现上述整数、浮点、Bool、Pointer 参数与结果及 Void 结果，支持寄存器耗尽后的栈参数、递归、嵌套指针和原生函数指针传递。常量导出支持整数、浮点、布尔；目标位宽转换只改导出副本，不改 Dart 常量。
- macOS 为 Mach-O/`.dylib`，Linux 为 ELF64/GNU ar/`.so`。macOS x64 宿主执行仍待确认；交叉链接不等于宿主已可执行。
- 头文件使用固定宽度 C 类型，支持 const 数据、函数指针及 C++ linkage。非 C 标识符、保留字和生成器保留前缀按 UTF-16 编码为无冲突 C 别名，Clang/GCC asm 标签保留外部符号；符号与文件文本按 UTF-8 编码。
- 结构体/联合体按值传递、可写数据、TLS、对象句柄、托管堆、异常和调度边界未完成。NativeType、SizedNativeType、Handle 等抽象指针目标的 C 声明仍缺，不隐式当作 void 指针。库输出不能借用可执行文件的托管运行能力。

## 规范依据

[主规范 §15、§20](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[空安全](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md)、[类型推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/inference.md)、[流分析](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/resources/type-system/flow-analysis.md)、[类型别名](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.13/nonfunction-type-aliases/feature-specification.md)、[`dart:ffi`](https://api.dart.dev/stable/3.13.7/dart-ffi/NativeType-class.html)。
