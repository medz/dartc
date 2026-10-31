# 表达式

本页说明表达式语法、求值顺序、常量及常用值操作，对应主规范 §17。[状态与阶段含义](README.md#如何读矩阵)适用于下表；语义分析 API 当前未提供，CLI 的类型/常量检查不代表公开分析器已可用。

## 特性支持

| 特性 | 语法解析 | 语义分析 API | 编译/运行 | 使用限制 |
| --- | --- | --- | --- | --- |
| null、bool、整数、double、字符串 | ✅ | ❌ | 🟡 | 扫描/解析不转换字面量；CLI 数值为 64 位整数/binary64。 |
| 普通、raw、多行、插值与相邻字符串 | ✅ | ❌ | 🟡 | 完整词法边界及 String API 未全部覆盖。 |
| Symbol 字面量 | ✅ | ❌ | ❌ | 保留 #、名称或运算符，不生成 Symbol 值。 |
| Record 字面量 | ✅ | ❌ | ❌ | parser 要求 3.0；`(value)` 和 `(value,)` 不同，无记录运行表示。 |
| 可变/const List | ✅ | ❌ | 🟡 | 支持显式/上下文元素类型及规范化身份。 |
| Set、Map 字面量 | ✅ | ❌ | ❌ | 大括号语法可解析，Set/Map 分类与推断未接入新 API。 |
| List if/for/for-in、spread | ✅ | ❌ | 🟡 | spread/for-in 限 List，无一般 Iterable 协议。 |
| 空感知集合元素 | ✅ | ❌ | 🟡 | parser 要求 3.8；CLI 从 3.8 起仅支持 List，Set/Map 未支持。 |
| 集合 if-case、模式循环 | ✅ | ❌ | 🟡 | 限运行时 List；const if-case 未支持，见[模式](patterns.md)。 |
| 常量运算、类型测试与转换 | ✅ | ❌ | 🟡 | 不含完整潜在常量语言；活跃失败 cast 是编译错误。 |
| 算术、位运算、移位、关系与短路 | ✅ | ❌ | 🟡 | 用户 operator ==、一般动态分派未支持。 |
| 赋值、复合赋值、增减、索引赋值 | ✅ | ❌ | 🟡 | 可写性、getter/setter/索引检查各有独立规则。 |
| 函数、构造器、成员调用与提取 | ✅ | ❌ | 🟡 | 签名、泛型和输出限制见[函数](functions.md)、[类](classes.md)。 |
| 空短路、空断言与级联 | ✅ | ❌ | 🟡 | 保留括号边界；一般动态成员查找仍缺。 |
| 点简写 | ✅ | ❌ | 🟡 | parser 要求 3.10；CLI 还需有效上下文命名空间，泛型类等仍缺。 |
| switch 表达式、模式赋值 | ✅ | ❌ | 🟡 | 模式类别、缓存与穷尽性见[模式](patterns.md)。 |
| throw | ✅ | ❌ | 🟡 | 同步异常可用，自动错误对象未全部接入。 |
| await、泛型函数值实例化 | ✅ | ❌ | ❌ | await 仅在异步体上下文解析；无异步执行。 |

## 表达式解析 API

`parseExpression(ScanResult)` 接受**一个不带末尾分号**的表达式，返回 AST 与词法/语法诊断。默认同步上下文，await/yield 可作标识符；需要解析 await 时使用[异步函数体入口](functions.md#解析入口)。调用方须检查 hasErrors，错误恢复节点可能只覆盖部分输入。

可用 `languageVersion` 显式选择[解析语言版本](lexical-structure.md#解析语言版本)，默认 3.13。`>>>`/`>>>=` 要求 2.14，明确的泛型函数值实例化和 `.new` 提取语法要求 2.15，命名实参后的位置实参要求 2.17；record、switch 表达式和模式赋值要求 3.0。这些是语法检查，不会绑定调用目标或建立运行表示。

parser 保留字面量拼写、原始转义、分组、实参书写顺序和完整选择链，不解码字符串、不绑定成员、不判断调用对象类别或常量资格。赋值只检查目标的语法形状，不检查 final/const 或 setter。泛型调用、显式实例化、移位和关系运算按语法消歧；缺失操作数以零宽节点恢复，不修改输入 token。

可解析语法包含 `new`/`const` 构造、f<T>、this/super、is/as、函数表达式、集合、模式、switch、级联及点简写。裸 super 不能作普通值，super?.member 被拒绝；关系与相等运算连续同级使用需要括号。以下仅为**解析示例**，其中 record/Map 不能据此编译：

```dart
final record = (1, label: 'value');
final map = <String, int>{?key: ?number};
final selected = switch (input) { [var first, ...] => first, _ => null };
```

## 字面量、身份与常量

CLI 整数为有符号 64 位。十进制最小负值只允许直接负字面量，括号内字面量先独立校验；非负十六进制可用完整 64 位补码，直接负十六进制仍限有符号范围。普通和常量表达式用同一范围规则。double 为 binary64，支持小数/指数、分隔符、负零、次正规数、无穷大和 NaN；double 上下文只隐式转换可精确表示的整数字面量。

identical 支持标量和对象身份，整数身份不因大小改变。double 按完整位模式比较，区分正负零及 NaN 符号/负载。const 类实例按实际类、实参和字段规范化，普通构造是新对象；顶层函数引用跨前缀/导出共享身份。记录身份未支持。

常量子集包括标量、支持的运算、条件、插值、引用、as/is/is!、部分函数/构造器引用、核心 identical、List 和已支持 const 实例。检查非常量引用和循环；静态类型与实际负载分开。Map、Set 和完整潜在常量表达式未支持。

const 变量、const 构造实参和嵌套隐式 const List 提供常量上下文；List 默认参数仍须显式 const。构造器声明默认值、字段初始化保持自己的作用域和常量资格，调用方不能放宽。

### 常量类型检查

as/is 的操作数须潜在常量，目标须为常量类型表达式。as 不向操作数提供目标上下文，`1 as double` 不产生整数到 double 转换。使用实际类型检查 List 实参及函数签名，向宽类型转换不改常量身份；as 可消费 void 实际负载，is/is! 仍拒绝 void。

失败 cast 只在活跃常量求值时报错。未选中分支、短路 RHS 仍检查名称、潜在常量资格和目标类型，但不执行 cast。仅推断字段类型时不执行转换，普通字段的失败 cast 到初始化时才抛 TypeError。固定规范要求常量目标不依赖外层类型参数，dartc 在死分支也拒绝；SDK 3.13.7 CFE/analyzer 接受 `true ? true : (1 is T)` 及相应 as、嵌套 List<T> 形式，与此不同。

## 集合元素

```dart
void main() {
  int? optional = null;
  final values = <int>[
    ?optional,
    ...<int>[1, 2],
    if (true) 3,
    for (var i = 4; i < 6; i++) i,
  ];
  print(values); // [1, 2, 3, 4, 5]。
}
```

List 按源码顺序执行 if/else、for、for-in、普通/空感知 spread；循环作用域、流分析和逐轮捕获同语句。所有元素静态类型参与上下文和 LUB，即使该路径不执行。spread 只接受 List，dynamic 来源逐元素检查；`...?` 仅跳过 null 集合，保留内部 null。

const List 按完整实际元素类型和元素值规范化，跨库/嵌套可共享身份；支持条件和展开，for 不是潜在常量。未选中元素仍检查类型及潜在常量资格。运行时 if-case 和解构循环见[模式](patterns.md)，一般 Iterable/Iterator、Set/Map 和异步元素未支持。

从 3.8 起 `?expression` 在 List 中只求值一次并仅丢弃 null，可嵌套 if/for 和常量上下文。下行上下文可空，上行取 NonNull，Null 得 Never，dynamic 不变；过滤不提升后续变量，赋值副作用仍发生。跳过 null、空 List<Never> 的迭代/展开仍可能正常结束，不免除非空函数的返回义务。

## 运算、赋值与分支

&&、||、??、条件表达式只执行所需分支，保留副作用；静态上仍检查两侧并合并流状态。条件须 bool，Object/bool? 未经转换或提升不可使用，dynamic 有运行时 bool 检查。条件两支接收上下文并求公共类型；?? 合并非空左类型和 RHS，Null 左侧直接取 RHS。void 左侧拒绝，void RHS 可保留被选负载。

支持整数/double 的算术、数值关系、整数位运算/移位和布尔位运算、String 拼接及相应复合赋值。`int + dynamic` 为 num，动态左侧为 dynamic，静态数值关系为 bool。NaN 关系为 false；用户非空类左操作数走[运算符方法](classes.md#用户运算符与相等)，operator == 与完整动态分派未支持。基础相等区分值比较和对象身份，const 相等还受 primitive equality 限制。

整数覆盖大移位和负移位失败边界。`/` 返回 double，零除按浮点产生无穷大/NaN；`~/` 返回 int。整数 ~/、%、remainder 零除在两侧实参求值后抛 IntegerDivisionByZeroException，复合赋值失败不改原值；最小 int 除 -1 溢出及负除数的非负模按 64 位规则处理。非有限浮点整除结果抛 UnsupportedError。

简单赋值保留 RHS 的表达式类型和负载，setter 返回值不替代它；复合赋值分别检查读取、运算和写入。接收者/索引一次求值。??= 仅 null 时求 RHS 和写入，仍检查读写两侧及未执行 RHS。final/const 存储只读，但同名显式 setter 可接收赋值。

前后增减的表达式结果与存储类型分开处理。普通 Never 左操作数保留底类型，相等、逻辑和逻辑 ! 仍为 bool；例如 int + Never 为 num。不能因不正常完成跳过其他操作数的静态检查。

## 调用与求值顺序

已知声明的函数、构造器及类成员调用按实参源码顺序检查再绑定。非泛型具体函数签名可调用及 .call，泛型直接调用与推断见[函数](functions.md#泛型直接调用)；泛型函数值、裸 Function/dynamic 调用仍缺。前导 new 必须选到构造器，不会把普通函数、getter 或静态方法变成构造器；已有 List.filled/String.fromCharCodes 入口的类型别名形式仍缺。new 即使在常量死分支也不是常量。

属性读写按声明身份和两侧类型分别选择；仅写属性不能读取。本库任一同名声明遮蔽导入的两侧。super 查词法父具体实现，仍绑定 this，返回函数值时先读成员后求实参；库命名空间见[库](libraries.md)。

**实例函数字段/getter 的直接调用先求实参再读取成员，括号包住成员则先读取。**以 receiver/getter/实参/体记为 1/2/3/4，`receiver().callback(arg())` 为 1324，`(receiver().callback)(arg())` 为 1234。隐式 this 相同；顶层/静态 getter 先读再求实参，静态选择器加括号不变。dartc 采用 SDK 3.13.5 CFE 的该顺序，与固定草案 getter fallback 的先读描述不同。

SDK 3.13.7 对命名实参在位置实参前的某些函数表达式调用又先执行前部实参。例如 receiver 记 5、getter 记 4 时，`(receiver().callback)(a: mark(2), mark(1))` 的 SDK 轨迹为 2541，dartc 为 5421；直接选择器两者均为 5214。dartc 保留函数表达式先求值、实参再按源码顺序求值的边界，不承诺与该 SDK 完全一致。

## 空短路、空断言与级联

?.、?[] 支持属性/调用/索引及链内 !、赋值/增减。接收者一次求值，null 时跳过后续选择器、实参、索引和 RHS；括号和普通运算终止传播。值接收者结果可空，即使静态接收者非空；静态类型限定不添加空性，void 仍不能消费。Never 接收者可用于部分访问/调用，结果 Never，但仍检查实参等义务，不引入动态分派。

后缀 e! 一次求值，null 抛可捕获 TypeError，否则保留原值，结果 NonNull(T)，Null 得 Never，dynamic 不变；传递 List 上下文并提升直接局部读取。void、常量空断言和以其作赋值目标均拒绝。

级联 .. 与首段 ?.. 一次求值接收者并以它为结果，按段顺序执行；null 时整组跳过。接收者得到上下文，执行/跳过路径合并赋值与提升，3.9 起可用非空目标排除 null 路径。后续段不能再次写 ?..。普通级联终止已有空短路：`receiver()?.child()..field = 1` 的级联目标仍可空；这采用 SDK 3.13.7 行为，与空安全补充中的传播描述不同。

?[] 的条件歧义优先按条件解析，`true ? (values?[0]) : 0` 需要内层括号。CLI 的重复 ! 选择器沿固定文法，可继续成员/索引/调用；SDK 3.13.5 拒绝 `value!!.member`、`value!![0]`、`value!!(1)`，带外围括号的调用则可接受。新 parser 的接受范围与 CLI 不自动相同。

## 索引赋值

用户 [] 和 []= 的索引参数可不同。简单赋值用写入参数提供上下文，复合/增减/??= 用读取参数提供上下文；两侧分别对原始索引检查类型和隐式 call 提取，一侧转换不改另一侧输入。super[i] 的各赋值形式绕过子类覆写，读写分别要求父具体实现，保留 this 和闭包接收者；泛型父接口、mixin、noSuchMethod 仍缺。

索引运行时检查顺序取决于是否消费结果：丢弃结果的复合赋值/后缀增减先检查写索引；消费复合结果时先读和执行 RHS 运算再检查，消费后缀结果时在读后、增减前检查，前缀在运算后检查。??= 只在 null 分支查写索引：丢弃结果先查再求 RHS，消费结果则先求 RHS。语句、for 更新、级联段直接丢弃结果，条件中的赋值仍作为值。类型失败抛 TypeError，其他失败见[异常边界](statements.md#核心错误与异常对象)。

## 点简写

从 3.10 起，已有类和标准库入口可用 .new(...)、命名生成式/工厂构造、静态字段/getter/方法调用。最长选择链的上下文决定声明身份，括号终止链；查找忽略局部同名变量，展开别名，可空上下文使用非空声明。赋值、实参、返回、条件、??、List 和既有泛型向下推断可提供上下文；空感知 List 单元素也可用 `?.member`。

==/!= 仅给**直接**简写右侧提供左静态类型的命名空间，不改变其自身推断上下文；`value == .name` 与带括号形式不同。常量/关系模式另见[模式](patterns.md)。const .name(...) 必须选 const 构造，普通静态方法/getter 不会变常量；SDK 3.13.7 CFE 接受 const .make() 普通静态方法，dartc 按规范和 analyzer 拒绝。

无上下文不按成员名搜索类；dynamic/void/Never、结构函数类型和类型参数（即使有类上界）不能提供静态命名空间。检查版本、私有性、实例成员误用及非法赋值；跨库私有类不能借公共别名提供命名空间，同库/part 可用。泛型类、泛型函数值、FutureOr、enum/mixin/extension type 及未实现内建成员仍有各自缺口。

## List API 边界

下列是 CLI 的标准库子集，不等于全部 List 或集合语言特性已支持。公开语义分析 API 不检查这些调用；parser 只解析普通调用语法。

| API | 编译/运行 | 行为与限制 |
| --- | --- | --- |
| List.filled | 🟡 | 默认固定长度，growable: true 可增长；实参一次求值，fill 引用共享。其他构造器和 length setter 未全覆盖。 |
| 索引、add、removeLast、clear | 🟡 | 写入先按实际元素类型检查，再查只读性和范围。空 const 也不能 clear。类型失败为 TypeError，固定/只读变更为 UnsupportedError，范围失败仍退出进程。 |
| removeAt | 🟡 | 返回被删元素、保持顺序；接收者/索引按序一次求值。入口类型检查后，固定/只读改长先于范围失败；范围错误仍退出进程。 |
| sublist | 🟡 | start、可省略/可空 end，按接收者/start/end 顺序求值和查类型，再按调用时长度查范围。返回独立可增长列表，保留实际元素类型，支持只读/固定源；范围失败退出进程。 |
| insert | 🟡 | 接受 0..length，保持顺序并返回 void。按接收者/索引/元素求值，先查实际元素类型，再查固定/只读和范围，失败不改列表；范围失败退出进程。 |
| toString | 🟡 | 按序格式化并处理嵌套和循环。元素回调改长抛 ConcurrentModificationError，modifiedObject 为实际列表；替换元素或回调返回前恢复长度可继续。一般 Iterable 和 for-in 的可捕获并发修改错误仍缺。 |

上述可捕获错误保留首次轨迹、执行 finally，失败后可继续；没有列出的 List API 不据此承诺可用。

## String API 边界

String.fromCharCodes 当前接受 List<int>，保留 16 位 UTF-16 单元，补充码点拆为代理对。非法码点（小于 0 或大于 0x10FFFF）抛 ArgumentError.value，invalidValue 为原列表，name 为 charCodes，message 为 `Contains invalid character code, not 0 <= code <= 0x10FFFF`；失败不改输入，可捕获并继续。一般 Iterable、可选 start/end 和 fromCharCode 未支持。

该载荷采用 SDK 3.13.7 的一般 Iterable 路径合同，不复刻 VM List 路径的内部表示差异：VM 负值/非 Smi 输入会把原列表放进 message，正超 Unicode Smi 值的 message 为 null，两者 name/invalidValue 均为 null。dartc 对这些输入统一保留原列表及参数名、说明。

## StringBuffer API 边界

StringBuffer 的 writeCharCode 支持 0..0x10FFFF，补充字符拆成代理对，孤代理项保留；长度按 UTF-16 单元，isNotEmpty 在 clear 后为 false。非法码点在入口抛 RangeError.range，保留非法值和边界，失败不改内容/长度，可捕获后继续写入。writeAll 尚未支持；其他 API 不在本页承诺范围内。

## 数值 API 与平台差异

double 直接调用子集包括 parse、tryParse、toString、toInt/truncate、toDouble、remainder、compareTo、isNaN/isFinite/isInfinite/isNegative 及五个 double 常量。parse 非法输入抛 FormatException 并保留 source，tryParse 返回 null。toInt/truncate 的 NaN、正负 Infinity，以及 ~/ 的非有限商抛 UnsupportedError；有限值按 64 位整数边界饱和。类型错误抛 TypeError，详细错误文案仍缺。

核心静态成员经别名访问、方法值提取、一般动态分派，以及 abs、sign、其他取整、clamp、指定精度文本、hashCode、公开 Type 等尚缺。int.parse 单独见[函数](functions.md#intparse-与外部调用)。

整数 ~/、%、remainder 零除的 IntegerDivisionByZeroException 实现 Exception 和 UnsupportedError 接口，message 为 `Division resulted in non-finite value`，自身 stackTrace 保持 null，catch 收到本次非空轨迹。混合 double 取模/余数的非有限结果为 NaN，非有限整除为 UnsupportedError，不兼容实参先失败于 TypeError。

混合整数/double 运算符按 SDK 3.13.7 先将整数转换为 double，例如 `9007199254740992.0 == 9007199254740993` 为 true；compareTo 精确比较返回 -1，另遵循 NaN 总序及正负零规则。这与 num 相等 API 的数学值描述存在边界差异，不是完整规范一致性承诺。

NaN 身份依来源和**输出目标**，不由编译宿主决定：

- 命名 double.nan 在 Linux x64 为负，macOS x64/ARM64 为正；无效浮点四则在 x64 为负、ARM64 为正。
- 无效模/remainder 使用平台数学库的 NaN：Linux x64 为负，其他当前目标为正。
- parse/tryParse 对 NaN、-NaN 用平台默认 NaN，+NaN 用正 NaN。
- 输入已是 NaN 的模/余数保留符号和负载并安静化 signaling NaN；输入非 NaN 而运算无效才生成数学库 NaN。identical 始终比较完整位模式，不能只按 CPU 合并这些来源。

## 其他已知边界

- throw 只求一次非空对象，结果 Never，保留此前副作用并终止后续求值。静态拒绝 nullable、void 和可能为空的类型参数；dynamic 为 null 时由非空检查抛 TypeError。同步传播见[语句](statements.md)，isolate 创建未支持。
- SDK 3.13.5 对 void getter 的 ??= 表达式语句 CFE 接受、analyzer 拒绝，dartc 按 void 消费拒绝。Never 局部 ??= 后正常落空的例子，CFE 接受、analyzer 拒绝；dartc 把 Never 读取视为不正常完成，仍检查 RHS。
- SDK 3.13.7 CFE 对未选中常量集合分支的普通 List 索引不做取值/范围检查，analyzer 可报非常量。dartc 采用 CFE：仍检查潜在常量资格和索引类型，不执行被跳过的取值。
- SDK 3.13.7 CFE 接受 List<void> 的空感知元素及未选中 `<int>[if (false) ?x]` 中不兼容的 dynamic 常量，analyzer 报错。dartc 跟随 CFE，仅活跃分支检查 dynamic 常量负载；void 不因此可用于其他元素类型。
- 常量空短路采用 SDK 3.13.7 CFE 的跳过结果，可接受 null?.missing、null?[0] 和 dynamic null 的 ?[true]；analyzer 拒绝。已知错误索引类型、非常量调用和赋值的静态义务不因此全部消失。
- 穷尽性、模式失败错误对象、Map/record 模式见[模式](patterns.md)。完整表达式、诊断及完成方式仍未覆盖，不能从语法接受推断运行支持。

## 规范依据

[主规范 §17](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/specification/dartLangSpec.tex)、[空安全](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/2.12/nnbd/feature-specification.md)、[空感知元素](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.8/null-aware-elements/feature-specification.md)、[点简写](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.10/dot-shorthands/feature-specification.md)、[Records](https://github.com/dart-lang/language/blob/6a254a68b6ef355ad4559b69dd8ed6893d9f3f3b/accepted/3.0/records/feature-specification.md)。
