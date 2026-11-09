# 模式、switch 与 if-case

匹配按源码顺序检查，守卫只在模式成功后执行。守卫失败时，其对外层变量的写入仍然可见。

| 特性 | 当前 IR 范围 |
| --- | --- |
| 常量、变量、类型、通配、括号模式 | 支持已表示的标量、record、集合、对象及函数常量，以及变量、通配和括号模式。常量模式以常量为相等比较的接收者。 |
| 逻辑与/或、关系模式 | 支持短路 `&&`、`\|\|` 和两侧变量的合并。关系模式以被匹配值为接收者，支持标量相等、num/double/int 大小比较、类及普通 extension 的比较运算符；可空 extension 接收者不会被强制非空。同一次匹配共享相同接收路径、运算符和常量实参的比较结果；`==` 与 `!=` 共享正向相等调用。 |
| cast、null-check、null-assert 模式 | `p as T` 可将值转换为已支持的核心类型。`p?` 遇 null 时匹配失败，`p!` 遇 null 时抛出 TypeError。 |
| 对象模式、字段名推导 | 支持名义对象的类型测试、getter/方法提取及字段名推导，以及普通 extension getter 与方法提取；保持字段求值顺序，并在同一次匹配的候选分支间共享提取结果。支持已表示的核心集合属性模式；extension getter/关系操作的缓存同时区分声明和结构化类型实参，普通虚派发的缓存规则不变。完整核心库 API 待实现。见[对象模式样本](../test/frontend/lowering/fixtures/object_patterns.dart)。 |
| List 模式及 rest | 支持类型检查、精确及最小长度、前后缀元素、rest 提取和通配跳过。自定义 List 的 length、索引及 sublist 保持虚派发和求值顺序；候选分支共享相同路径的提取。 |
| Record 模式 | 核对位置字段数和命名字段集合，再按模式书写顺序匹配各字段。支持嵌套、命名字段简写及在逻辑或的两侧绑定不同字段。 |
| Map 模式 | 支持已表示的常量 key、嵌套值模式及用户 Map。先取值，仅在值为 null 且模式值类型允许 null 时调用 containsKey；不读取 length/keys。 |
| switch 表达式 | 支持上述模式和 when 守卫。被匹配表达式求值一次，只执行首个匹配且守卫为真的分支。 |
| 语句和 List 元素 if-case | 支持语句和集合元素中的 if-case、when 和 else。 |
| 局部模式声明/赋值 | 支持用上述不可反驳模式声明局部变量，以及给已有局部变量和参数解构赋值。右侧只求值一次，先执行上下文隐式转换，全部解构成功后才写入，赋值表达式返回右侧的值。长度/缺 key 失败抛 StateError，类型转换失败抛 TypeError。 |
| for/for-in 模式循环头 | 三段式 for 支持模式变量声明和解构更新。同步 for-in 支持 record、List 和 Map 解构声明，并为每次迭代建立独立绑定。 |
| switch 语句、guard、共享 case | 支持上述模式与 when。多个 case 共享分支体时，传递相应 case 中一致绑定的变量值。带标签的 continue 直接进入分支体。 |
| bool/Null/Never/record/枚举穷尽性 | analyzer 检查输入的穷尽性。IR 行为对照涵盖 bool? 的 true、false、null，num 的 int、double，以及 (bool, bool?) 的全部组合。支持枚举声明及其常量模式，见[枚举样本](../test/frontend/lowering/fixtures/enums.dart)。 |
| sealed 层次穷尽性 | analyzer 检查普通及泛型 sealed 层次的静态穷尽性；lowering 保留子类类型检查及分支。见[sealed 层次样本](../test/frontend/lowering/fixtures/nominal/constructors.dart)。 |
| List 长度与对象属性空间覆盖 | analyzer 检查静态覆盖；SDK 差分验证长度/属性读取及守卫失败后的缓存行为。 |
| 不可达 case 诊断 | analyzer 提供诊断，调用方可在 CheckedLibraries 的回调中读取；lowering 不重复诊断。warning 不阻止转换，error 阻止整批转换。 |

[集合模式样本](../test/frontend/lowering/fixtures/collection_patterns.dart)、[匹配与守卫样本](../test/frontend/lowering/fixtures/patterns.dart)、[record 解构样本](../test/frontend/lowering/fixtures/destructure.dart)和[SDK 行为对照](../test/frontend/lowering/lowering_test.dart)。发布版的行为、已知差异和逐项验证记录见[原条目](https://github.com/medz/dartc/blob/4b44afb1de207415f31379118c2f736afce5e276/specs/patterns.md)。

## 规范依据

[模式特性规范](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/feature-specification.md)、[穷尽性](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/exhaustiveness.md)、[对象模式类型推断](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/patterns/feature-specification.md#type-checking-and-pattern-required-type)。
